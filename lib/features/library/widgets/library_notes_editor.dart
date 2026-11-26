import 'dart:ui' show SemanticsRole;

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:mangabaka_app/core/localization/localization_service.dart';
import 'package:mangabaka_app/core/theme/app_typography.dart';
import 'package:mangabaka_app/core/theme/theme_context.dart';
import 'package:mangabaka_app/core/utils/external_url_launcher.dart';
import 'package:mangabaka_app/core/widgets/app_snack_bar.dart';
import 'package:markdown/markdown.dart' as md;

class LibraryNotesEditor extends StatefulWidget {
  const LibraryNotesEditor({
    super.key,
    required this.controller,
    required this.enabled,
    required this.decoration,
    required this.validator,
  });

  final TextEditingController controller;
  final bool enabled;
  final InputDecoration decoration;
  final FormFieldValidator<String> validator;

  @override
  State<LibraryNotesEditor> createState() => _LibraryNotesEditorState();
}

enum _Format {
  bold(Icons.format_bold, 'notes_bold'),
  italic(Icons.format_italic, 'notes_italic'),
  strike(Icons.format_strikethrough, 'notes_strike'),
  spoiler(Icons.visibility_off_outlined, 'notes_spoiler'),
  link(Icons.link, 'notes_link'),
  heading(Icons.title, 'notes_heading'),
  quote(Icons.format_quote, 'notes_quote'),
  bullets(Icons.format_list_bulleted, 'notes_bullets'),
  ordered(Icons.format_list_numbered, 'notes_ordered'),
  code(Icons.code, 'notes_code'),
  codeBlock(Icons.integration_instructions_outlined, 'notes_code_block'),
  rule(Icons.horizontal_rule, 'notes_rule');

  const _Format(this.icon, this.label);
  final IconData icon;
  final String label;
}

class _LibraryNotesEditorState extends State<LibraryNotesEditor> {
  final _focus = FocusNode();
  bool _preview = false;

  String _t(String key) => LocalizationService().translate(key);

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _format(_Format action) {
    if (!widget.enabled || _preview) return;
    _focus.requestFocus();
    widget.controller.value = _applyFormat(widget.controller.value, action);
  }

  Widget _tab(bool preview) {
    final label = _t(preview ? 'notes_preview' : 'notes_write');
    final active = _preview == preview;
    void select() {
      if (active || !widget.enabled) return;
      if (preview) _focus.unfocus();
      setState(() => _preview = preview);
    }

    return Semantics(
      role: SemanticsRole.tab,
      label: label,
      enabled: widget.enabled,
      selected: active,
      onTap: widget.enabled ? select : null,
      child: ExcludeSemantics(
        child: ChoiceChip(
          label: Text(label),
          selected: active,
          onSelected: widget.enabled ? (_) => select() : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = AppTypography.sans(color: colors.text, fontSize: 14);
    return FormField<String>(
      validator: (_) => widget.validator(widget.controller.text),
      builder: (field) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 6,
        children: [
          Semantics(
            header: true,
            child: Padding(
              padding: const EdgeInsetsDirectional.only(start: 12, end: 12),
              child: Text(_t('library_editor_notes'), style: text),
            ),
          ),
          Semantics(
            role: SemanticsRole.tabBar,
            explicitChildNodes: true,
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [_tab(false), _tab(true)],
            ),
          ),
          if (!_preview)
            FocusTraversalGroup(
              child: Wrap(
                children: [
                  for (final format in _Format.values.take(9))
                    IconButton(
                      tooltip: _t(format.label),
                      onPressed: widget.enabled ? () => _format(format) : null,
                      icon: Icon(format.icon, size: 20),
                    ),
                  PopupMenuButton<_Format>(
                    tooltip: _t('notes_more'),
                    enabled: widget.enabled,
                    onSelected: _format,
                    itemBuilder: (context) => [
                      for (final format in _Format.values.skip(9))
                        PopupMenuItem(
                          value: format,
                          child: Text(_t(format.label)),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          Offstage(
            offstage: _preview,
            child: ExcludeFocus(
              excluding: _preview,
              child: Semantics(
                label: _t('library_editor_notes'),
                child: TextField(
                  key: const ValueKey('library_editor_notes'),
                  controller: widget.controller,
                  focusNode: _focus,
                  enabled: widget.enabled,
                  minLines: 3,
                  maxLines: 6,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  enableIMEPersonalizedLearning: false,
                  style: text,
                  decoration: widget.decoration.copyWith(
                    errorText: _preview ? null : field.errorText,
                  ),
                  onChanged: field.didChange,
                ),
              ),
            ),
          ),
          if (_preview)
            DecoratedBox(
              decoration: BoxDecoration(
                color: colors.surfaceRaised,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 6,
                  children: [
                    if (widget.controller.text.trim().isEmpty)
                      Text(_t('notes_empty_preview'), style: text)
                    else
                      Semantics(
                        role: SemanticsRole.tabPanel,
                        child: _NotePreview(data: widget.controller.text),
                      ),
                    if (field.errorText case final error?)
                      Text(error, style: text.copyWith(color: colors.error)),
                  ],
                ),
              ),
            ),
          ValueListenableBuilder(
            valueListenable: widget.controller,
            builder: (context, value, _) => Padding(
              padding: const EdgeInsetsDirectional.only(start: 12, end: 12),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 8,
                runSpacing: 4,
                children: [
                  Text(_t('notes_markdown_supported')),
                  Text(
                    _t(
                      'notes_character_count',
                    ).replaceAll('{count}', '${value.text.characters.length}'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

TextEditingValue _applyFormat(TextEditingValue value, _Format format) {
  final text = value.text;
  final selection = value.selection;
  final valid = selection.isValid && selection.end <= text.length;
  var start = valid ? selection.start : text.length;
  var end = valid ? selection.end : text.length;
  final reversed = valid && selection.baseOffset > selection.extentOffset;
  final selected = text.substring(start, end);
  final originalStart = start;
  final originalEnd = end;
  TextEditingValue replace(String insert, int from, int to) => TextEditingValue(
    text: text.replaceRange(start, end, insert),
    selection: TextSelection(
      baseOffset: start + (reversed ? to : from),
      extentOffset: start + (reversed ? from : to),
    ),
  );

  // Prefix every affected line while preserving adjacent untouched text.
  if (format == _Format.heading ||
      format == _Format.quote ||
      format == _Format.bullets ||
      format == _Format.ordered) {
    if (start > 0) start = text.lastIndexOf('\n', start - 1) + 1;
    if (selected.isEmpty || end == 0 || text[end - 1] != '\n') {
      final newline = text.indexOf('\n', end);
      end = newline < 0 ? text.length : newline;
    } else {
      end--;
    }
    final lines = text.substring(start, end).split('\n');
    String prefix(int index) => switch (format) {
      _Format.heading => '## ',
      _Format.quote => '> ',
      _Format.bullets => '- ',
      _ => '${index + 1}. ',
    };
    final insert = [
      for (var index = 0; index < lines.length; index++)
        '${prefix(index)}${lines[index]}',
    ].join('\n');
    int updatedOffset(int offset) {
      final relative = offset.clamp(start, end).toInt() - start;
      final index = text.substring(start, start + relative).split('\n').length;
      return relative +
          List.generate(
            index,
            (i) => prefix(i).length,
          ).fold<int>(0, (sum, length) => sum + length);
    }

    return replace(
      insert,
      updatedOffset(originalStart),
      updatedOffset(originalEnd),
    );
  }

  if (format == _Format.rule) {
    start = end;
    final prefix = start == 0 ? '' : '\n\n';
    final insert = '$prefix---\n\n';
    return replace(insert, insert.length, insert.length);
  }
  if (format == _Format.link) {
    final label = selected.isEmpty
        ? 'link'
        : selected
              .replaceAll(r'\', r'\\')
              .replaceAll('[', r'\[')
              .replaceAll(']', r'\]');
    const destination = 'https://';
    final insert = '[$label]($destination)';
    return selected.isEmpty
        ? replace(insert, 1, 1 + label.length)
        : replace(
            insert,
            insert.length - 1 - destination.length,
            insert.length - 1,
          );
  }

  final tick = String.fromCharCode(96);
  final tickRuns = RegExp('$tick+').allMatches(selected);
  final longest = tickRuns.fold<int>(
    0,
    (length, match) =>
        match.end - match.start > length ? match.end - match.start : length,
  );
  if (format == _Format.codeBlock) {
    final fence = tick * (longest >= 3 ? longest + 1 : 3);
    final before = start == 0 || text[start - 1] == '\n' ? '' : '\n';
    final after = end == text.length || text[end] == '\n' ? '' : '\n';
    final opening = '$before$fence\n';
    return replace(
      '$opening$selected\n$fence$after',
      opening.length,
      opening.length + selected.length,
    );
  }
  final marker = switch (format) {
    _Format.bold => '**',
    _Format.italic => '*',
    _Format.strike => '~~',
    _Format.spoiler => '||',
    _ => tick * (longest + 1),
  };
  if (selected.isEmpty) {
    return replace('$marker$marker', marker.length, marker.length);
  }
  if (format == _Format.code) {
    final padding = selected.startsWith(tick) || selected.endsWith(tick)
        ? ' '
        : '';
    final opening = '$marker$padding';
    return replace(
      '$opening$selected$padding$marker',
      opening.length,
      opening.length + selected.length,
    );
  }

  final lines = selected.split('\n');
  final formatted = lines
      .map((line) {
        final content = line.trim();
        if (content.isEmpty) return line;
        final from = line.indexOf(content);
        return line.replaceRange(
          from,
          from + content.length,
          '$marker$content$marker',
        );
      })
      .join('\n');
  if (lines.length > 1 || selected.trim().isEmpty) {
    return replace(formatted, 0, formatted.length);
  }
  final from = selected.indexOf(selected.trim()) + marker.length;
  return replace(formatted, from, from + selected.trim().length);
}

class _NotePreview extends StatelessWidget {
  const _NotePreview({required this.data});

  static final _extensions = md.ExtensionSet(
    const [md.FencedCodeBlockSyntax(), md.TableSyntax()],
    [md.StrikethroughSyntax()],
  );
  final String data;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final t = LocalizationService().translate;
    return MarkdownBody(
      data: data,
      extensionSet: _extensions,
      inlineSyntaxes: [_SpoilerSyntax()],
      builders: {'spoiler': _SpoilerBuilder()},
      softLineBreak: true,
      imageBuilder: (_, _, alt) =>
          Text(alt == null || alt.isEmpty ? t('notes_image_hidden') : alt),
      onTapLink: (_, href, _) async {
        if (href != null && await ExternalUrlLauncher.launch(href)) return;
        if (context.mounted) {
          AppSnackBar.show(context, t('notes_link_unavailable'), isError: true);
        }
      },
      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
        p: AppTypography.sans(color: colors.text, fontSize: 14),
        a: AppTypography.sans(
          color: colors.accentOn(colors.surfaceRaised),
        ).copyWith(decoration: TextDecoration.underline),
      ),
    );
  }
}

/// MangaBaka uses double pipes with no whitespace at the delimiter edges.
class _SpoilerSyntax extends md.InlineSyntax {
  _SpoilerSyntax()
    : super(r'\|\|(?![|\s])([^\r\n]*?[^\s|])\|\|', startCharacter: 124);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.text('spoiler', match[1]!));
    return true;
  }
}

class _SpoilerBuilder extends MarkdownElementBuilder {
  @override
  Widget visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) => _Spoiler(key: ObjectKey(element), data: element.textContent);
}

class _Spoiler extends StatefulWidget {
  const _Spoiler({super.key, required this.data});
  final String data;

  @override
  State<_Spoiler> createState() => _SpoilerState();
}

class _SpoilerState extends State<_Spoiler> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) => _revealed
      ? _NotePreview(data: '\u200B${widget.data}')
      : TextButton(
          onPressed: () => setState(() => _revealed = true),
          child: Text(LocalizationService().translate('notes_reveal_spoiler')),
        );
}
