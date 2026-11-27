import 'package:flutter/material.dart';
import 'package:mangabaka_app/core/localization/localization_service.dart';

/// Shared by the compact header and the wide navigation search slot.
class CollectionHeaderSearch extends ChangeNotifier {
  final text = TextEditingController();
  final focus = FocusNode();
  bool _available = true;
  bool _expanded = false;

  bool get available => _available;
  bool get expanded => _available && _expanded;

  void setAvailable(bool value) {
    if (_available == value) return;
    focus.unfocus();
    _available = value;
    notifyListeners();
  }

  void open() {
    if (!_available) return;
    _expanded = true;
    notifyListeners();
    focus.requestFocus();
  }

  void close() {
    focus.unfocus();
    text.clear();
    _expanded = false;
    notifyListeners();
  }

  @override
  void dispose() {
    focus.dispose();
    text.dispose();
    super.dispose();
  }
}

class CollectionSearchField extends StatelessWidget {
  const CollectionSearchField({
    super.key,
    required this.search,
    required this.label,
    this.onChanged,
  });

  final CollectionHeaderSearch search;
  final String label;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) => TextField(
    controller: search.text,
    focusNode: search.focus,
    textInputAction: TextInputAction.search,
    onChanged: onChanged,
    onSubmitted: (_) => search.focus.unfocus(),
    decoration: InputDecoration(
      hintText: label,
      isDense: true,
      prefixIcon: IconButton(
        tooltip: MaterialLocalizations.of(context).backButtonTooltip,
        onPressed: () {
          search.close();
          onChanged?.call('');
        },
        icon: const Icon(Icons.arrow_back_rounded),
      ),
    ),
  );
}

/// The wide chrome has a search slot of its own and never duplicates the field.
class CollectionSearchSlot extends StatelessWidget {
  const CollectionSearchSlot({super.key, required this.search});

  final CollectionHeaderSearch search;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: search,
    builder: (context, _) {
      final label = LocalizationService().translate('collection_search_lists');
      if (search.expanded) {
        return CollectionSearchField(search: search, label: label);
      }
      return IconButton(
        tooltip: label,
        onPressed: search.available ? search.open : null,
        icon: const Icon(Icons.search),
      );
    },
  );
}
