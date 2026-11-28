import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mangabaka_app/core/constants/app_constants.dart';
import 'package:mangabaka_app/core/localization/localization_service.dart';
import 'package:mangabaka_app/core/theme/eirenyu_palette.dart';
import 'package:mangabaka_app/core/theme/theme_context.dart';

/// Native route drag stays disabled. The sheet and its handle request exit
/// through the owning editor, including when the inner scroll reaches the top.
class GuardedDraggableSheet extends StatefulWidget {
  const GuardedDraggableSheet({
    super.key,
    required this.openExtent,
    required this.dismissExtent,
    required this.canDrag,
    required this.onDismiss,
    required this.builder,
    this.handleKey = const ValueKey('editor_sheet_drag_handle'),
  }) : fitContent = false;

  const GuardedDraggableSheet.compact({
    super.key,
    required this.canDrag,
    required this.onDismiss,
    required this.builder,
    this.handleKey = const ValueKey('editor_sheet_drag_handle'),
  }) : fitContent = true,
       openExtent = 1,
       dismissExtent = 0;

  final double openExtent;
  final double dismissExtent;
  final bool Function() canDrag;
  final FutureOr<void> Function() onDismiss;
  final Widget Function(BuildContext, ScrollController, Widget?) builder;
  final Key handleKey;
  final bool fitContent;

  @override
  State<GuardedDraggableSheet> createState() => _GuardedDraggableSheetState();
}

class _GuardedDraggableSheetState extends State<GuardedDraggableSheet> {
  final _sheet = DraggableScrollableController();
  final _compactScroll = ScrollController();
  double _handleDrag = 0;
  double _contentDrag = 0;
  bool _keyboardAtPointerDown = false;
  bool _requesting = false;

  bool get _keyboardVisible => MediaQuery.viewInsetsOf(context).bottom > 0;
  bool get _canDrag =>
      mounted &&
      !_requesting &&
      !_keyboardAtPointerDown &&
      !_keyboardVisible &&
      widget.canDrag();

  @override
  void dispose() {
    _sheet.dispose();
    _compactScroll.dispose();
    super.dispose();
  }

  Future<void> _request() async {
    if (!_canDrag || ModalRoute.of(context)?.isCurrent != true) return;
    _requesting = true;
    try {
      await widget.onDismiss();
    } finally {
      if (mounted && ModalRoute.of(context)?.isCurrent == true) _reopen();
      _requesting = false;
    }
  }

  void _reopen() {
    if (!_sheet.isAttached || _sheet.size == widget.openExtent) return;
    unawaited(
      _sheet.animateTo(
        widget.openExtent,
        duration: AppConstants.shortAnimationDuration,
        curve: Curves.easeOut,
      ),
    );
  }

  bool _onExtent(DraggableScrollableNotification notification) {
    if (notification.depth == 0 &&
        _canDrag &&
        notification.extent <= widget.dismissExtent) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_canDrag &&
            _sheet.isAttached &&
            _sheet.size <= widget.dismissExtent) {
          unawaited(_request());
        }
      });
    }
    return false;
  }

  void _endHandleDrag([DragEndDetails? details]) {
    if (widget.fitContent) {
      if (_handleDrag >= 48 || (details?.primaryVelocity ?? 0) > 700) {
        unawaited(_request());
      }
      _handleDrag = 0;
      return;
    }
    if (!_canDrag || !_sheet.isAttached) return;
    if (_sheet.size <= (widget.openExtent + widget.dismissExtent) / 2 ||
        (details?.primaryVelocity ?? 0) > 700) {
      unawaited(_request());
    } else {
      _reopen();
    }
  }

  Widget _handle(BuildContext context) {
    final colors = context.colors;
    final enabled = widget.canDrag();
    return Semantics(
      label: LocalizationService().translate('library_editor_drag_handle'),
      onDismiss: enabled
          ? () {
              _keyboardAtPointerDown = false;
              unawaited(_request());
            }
          : null,
      child: GestureDetector(
        key: widget.handleKey,
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: enabled
            ? (details) {
                if (!_canDrag) return;
                if (widget.fitContent) {
                  _handleDrag += details.delta.dy;
                  return;
                }
                if (!_sheet.isAttached) return;
                _sheet.jumpTo(
                  (_sheet.size - _sheet.pixelsToSize(details.delta.dy)).clamp(
                    widget.dismissExtent,
                    widget.openExtent,
                  ),
                );
              }
            : null,
        onVerticalDragEnd: enabled ? _endHandleDrag : null,
        onVerticalDragCancel: enabled ? _endHandleDrag : null,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: MbPalette.ensureContrast(
                  colors.textMuted,
                  colors.surface,
                  minimum: 3,
                ),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const SizedBox(width: 36, height: 4),
            ),
          ),
        ),
      ),
    );
  }

  Widget _material(BuildContext context, ScrollController scroll) => Material(
    color: context.colors.surface,
    borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
    clipBehavior: Clip.antiAlias,
    child: widget.builder(
      context,
      scroll,
      _keyboardVisible ? null : _handle(context),
    ),
  );

  bool _onCompactScroll(ScrollNotification notification) {
    if (notification.depth != 0 || !_canDrag) return false;
    if (notification is OverscrollNotification &&
        notification.dragDetails != null) {
      _contentDrag = (_contentDrag - notification.overscroll).clamp(0, 96);
    }
    if (notification is ScrollUpdateNotification &&
        notification.dragDetails != null) {
      final metrics = notification.metrics;
      if (metrics.pixels < metrics.minScrollExtent) {
        _contentDrag = metrics.minScrollExtent - metrics.pixels;
      } else {
        _contentDrag = 0;
      }
    }
    if (notification is ScrollEndNotification && _contentDrag >= 48) {
      _contentDrag = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_request());
      });
    }
    return false;
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) {
      _keyboardAtPointerDown = _keyboardVisible;
      _contentDrag = 0;
    },
    onPointerUp: (_) {
      if (_keyboardAtPointerDown || !widget.canDrag()) _reopen();
    },
    child: widget.fitContent
        ? NotificationListener<ScrollNotification>(
            onNotification: _onCompactScroll,
            child: _material(context, _compactScroll),
          )
        : NotificationListener<DraggableScrollableNotification>(
            onNotification: _onExtent,
            child: DraggableScrollableSheet(
              controller: _sheet,
              expand: false,
              initialChildSize: widget.openExtent,
              maxChildSize: widget.openExtent,
              minChildSize: widget.dismissExtent,
              shouldCloseOnMinExtent: false,
              snap: true,
              builder: _material,
            ),
          ),
  );
}

/// Routes native Back and explicit Cancel through the same dirty-form check.
/// Successful mutations close through the owner's existing completion path.
mixin EditorDismissal<T extends StatefulWidget> on State<T> {
  bool _confirmingExit = false;
  bool _exitRequested = false;
  bool get exitLocked;
  bool get hasPendingEdits;

  Future<void> requestEditorDismissal() async {
    final route = ModalRoute.of(context);
    if (exitLocked ||
        _confirmingExit ||
        _exitRequested ||
        route?.isCurrent != true) {
      return;
    }
    FocusScope.of(context).unfocus();
    if (hasPendingEdits) {
      _confirmingExit = true;
      final strings = LocalizationService();
      final discard = await showDialog<bool>(
        context: context,
        useRootNavigator: false,
        builder: (context) => AlertDialog(
          title: Text(strings.translate('discard_editor_changes')),
          content: Text(strings.translate('discard_editor_changes_message')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(strings.translate('cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(strings.translate('discard_editor_confirm')),
            ),
          ],
        ),
      );
      _confirmingExit = false;
      if (discard != true ||
          !mounted ||
          exitLocked ||
          route?.isCurrent != true) {
        return;
      }
    }
    _exitRequested = true;
    route!.navigator!.pop();
  }

  Widget guardEditorDismissal(Widget child) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && mounted) unawaited(requestEditorDismissal());
    },
    child: child,
  );
}
