import 'package:flutter/material.dart';
import 'package:mangabaka_app/core/localization/localization_service.dart';
import 'package:mangabaka_app/features/library/widgets/library_status_dropdown.dart';

class StateSelectionSection extends StatefulWidget {
  final String? currentState;
  final Function(String) onStateChanged;

  const StateSelectionSection({
    super.key,
    required this.currentState,
    required this.onStateChanged,
  });

  @override
  State<StateSelectionSection> createState() => _StateSelectionSectionState();
}

class _StateSelectionSectionState extends State<StateSelectionSection> {
  String? _tempState;

  @override
  void initState() {
    super.initState();
    _tempState = widget.currentState;
  }

  @override
  void didUpdateWidget(covariant StateSelectionSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentState != oldWidget.currentState) {
      _tempState = widget.currentState;
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeState = _tempState;
    if (activeState == null) {
      return const SizedBox.shrink();
    }

    return ListenableBuilder(
      listenable: LocalizationService(),
      builder: (context, _) => LibraryStatusDropdown(
        value: activeState,
        onChanged: (value) {
          setState(() => _tempState = value);
          widget.onStateChanged(value);
        },
      ),
    );
  }
}
