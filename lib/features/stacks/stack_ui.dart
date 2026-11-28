import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/database/database.dart' show LibraryCacheLease;
import '../../core/di/service_locator.dart';
import '../../core/exceptions/app_exceptions.dart';
import '../../core/localization/localization_service.dart';
import '../../core/settings/settings_manager.dart';
import '../../core/theme/theme_context.dart';
import '../../core/utils/widget_utils.dart';
import '../../core/widgets/app_snack_bar.dart';
import '../../core/widgets/design/mb_cover.dart';
import '../../core/widgets/guarded_draggable_sheet.dart';
import '../library/models/library_entry.dart';
import '../library/services/library_service.dart';
import '../library/widgets/collection_header_search.dart';
import '../library/widgets/library_notes_editor.dart';
import '../series/models/series.dart';
import '../series/screens/series_detail_screen.dart';
import '../series/services/series_search_service.dart';
import '../series/widgets/entry_progress_overlay.dart';
import 'stack_controller.dart';
import 'stack_models.dart';
import 'stack_service.dart';

part 'stack_overview.dart';
part 'stack_detail_page.dart';
part 'stack_editor.dart';

String _t(String key) => LocalizationService().translate(key);
String _count(String key, int count) => _t(key).replaceAll('{count}', '$count');

String _error(Object error) =>
    _t(error is StackFailure ? error.code : 'stack_request_failed');

List<String> _ratings() {
  final selected = SettingsManager().contentPreferences;
  return selected.isEmpty ? ['safe'] : selected;
}

List<String> _previewRatings() => _ratings()
    .where((rating) => !WidgetUtils.isRatingBlurred(rating))
    .toList(growable: false);

bool _showRating(String rating) => _ratings().contains(rating);

String _title(Series series) =>
    series.getDisplayTitle(SettingsManager().defaultTitleLanguage);

class _StackNotice extends StatelessWidget {
  const _StackNotice(this.message, {this.retry, this.label = 'retry'});

  final String message;
  final VoidCallback? retry;
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Wrap(
      spacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(message),
        if (retry != null) TextButton(onPressed: retry, child: Text(_t(label))),
      ],
    ),
  );
}

class _StackPermission extends StatefulWidget {
  const _StackPermission(this.controller, this.owner, {this.write = false});

  final StackController controller;
  final LibraryCacheLease owner;
  final bool write;

  @override
  State<_StackPermission> createState() => _StackPermissionState();
}

class _StackPermissionState extends State<_StackPermission> {
  bool _busy = false;
  String? _message;

  Future<void> _authorize() async {
    final controller = widget.controller;
    if (_busy || !controller.live(widget.owner)) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await controller.service.auth.upgradeStackPermissions();
      if (mounted &&
          controller.live(widget.owner) &&
          (widget.write ? !controller.canWrite : !controller.canRead)) {
        setState(() => _message = _t('stack_permission_required'));
      }
    } on AuthCancelledException {
      // Cancellation leaves the current authorization available.
    } catch (_) {
      if (mounted && controller.live(widget.owner)) {
        setState(() => _message = _t('stack_authorize_failed'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _StackNotice(
        _t(widget.write ? 'stack_write_permission' : 'stack_read_permission'),
        retry: _busy ? null : _authorize,
        label: 'stack_authorize',
      ),
      if (_busy) const LinearProgressIndicator(),
      if (_message case final message?) _StackNotice(message),
    ],
  );
}

Future<bool> _confirm(
  BuildContext context,
  StackController controller,
  StackAccess access,
  String action,
  String message, {
  bool Function()? available,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final current = controller.liveAccess(access) && controller.canWrite;
          final live = current && (available?.call() ?? true);
          return AlertDialog(
            scrollable: true,
            title: Text(_t(action)),
            content: Text(
              live
                  ? message
                  : _t(
                      current
                          ? 'stack_unavailable'
                          : 'stack_authorization_changed',
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(_t('cancel')),
              ),
              TextButton(
                onPressed: live ? () => Navigator.pop(context, true) : null,
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                child: Text(_t(action)),
              ),
            ],
          );
        },
      ),
    ) ??
    false;

Future<T?> _sheet<T>(BuildContext context, Widget child) =>
    showModalBottomSheet<T>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      constraints: const BoxConstraints(maxWidth: 640),
      backgroundColor: Colors.transparent,
      builder: (_) => child,
    );

Widget _editorSheet(
  BuildContext context, {
  required bool compact,
  required bool Function() canDrag,
  required Future<void> Function() dismiss,
  required Widget Function(ScrollController) body,
}) {
  Widget buildBody(BuildContext _, ScrollController scroll, Widget? handle) =>
      Column(
        mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
        children: [
          ?handle,
          if (compact)
            Flexible(child: body(scroll))
          else
            Expanded(child: body(scroll)),
        ],
      );
  return Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: compact
        ? GuardedDraggableSheet.compact(
            canDrag: canDrag,
            onDismiss: dismiss,
            builder: buildBody,
          )
        : GuardedDraggableSheet(
            openExtent: .94,
            dismissExtent: .4,
            canDrag: canDrag,
            onDismiss: dismiss,
            builder: buildBody,
          ),
  );
}
