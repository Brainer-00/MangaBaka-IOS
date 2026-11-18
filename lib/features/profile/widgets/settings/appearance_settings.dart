import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mangabaka_app/core/localization/localization_service.dart';
import 'package:mangabaka_app/core/settings/settings_enums.dart';
import 'package:mangabaka_app/core/settings/settings_manager.dart';
import 'package:mangabaka_app/core/theme/eirenyu_palette.dart';
import 'package:mangabaka_app/core/theme/ios_home_icon.dart';
import 'package:mangabaka_app/core/theme/theme_context.dart';
import 'package:mangabaka_app/core/theme/theme_presets.dart';
import 'package:mangabaka_app/core/widgets/design/eirenyu_mark.dart';
import 'package:mangabaka_app/features/profile/widgets/settings/theme_miniature_preview.dart';

/// One settings surface shared by portrait, landscape dialog, and desktop.
/// The application root remains the sole owner of ThemeController.
class AppearanceSettings extends StatelessWidget {
  const AppearanceSettings({super.key});

  static const _names = <String, String>{
    'eirenyu': 'EirenYu',
    'default': 'MangaBaka',
    'amoled': 'AMOLED',
    'monochrome': 'Monochrome',
    'catppuccin': 'Catppuccin',
    'dracula': 'Dracula',
    'nord': 'Nord',
    'midnight_dusk': 'Midnight Dusk',
    'strawberry': 'Strawberry',
    'tako': 'Tako',
    'yotsuba': 'Yotsuba',
    'green_apple': 'Green Apple',
    'teal': 'Teal',
    'tidal_wave': 'Tidal Wave',
    'lavender': 'Lavender',
  };

  static const _accentNameKeys = <String>[
    'appearance_swatch_emerald',
    'appearance_swatch_amber',
    'appearance_swatch_orange',
    'appearance_swatch_rose',
    'appearance_swatch_pink',
    'appearance_swatch_violet',
    'appearance_swatch_blue',
    'appearance_swatch_cyan',
    'appearance_swatch_teal',
    'appearance_swatch_lime',
    'appearance_swatch_crimson_moon',
    'appearance_swatch_twilight_lavender',
    'appearance_swatch_horizon_blue',
  ];

  String _t(String key) => LocalizationService().translate(key);

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([SettingsManager(), LocalizationService()]),
    builder: (context, _) {
      final settings = SettingsManager();
      final colors = context.colors;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _heading(_t('appearance_mode'), colors.text),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final mode in AppThemeMode.values)
                ChoiceChip(
                  key: Key('appearance_mode_${mode.name}'),
                  label: Text(_t('appearance_mode_${mode.name}')),
                  selected: settings.themeMode == mode,
                  onSelected: (_) {
                    settings.setThemeMode(mode);
                    IosHomeIconScope.request(context);
                  },
                ),
            ],
          ),
          const SizedBox(height: 26),
          if (settings.themeMode != AppThemeMode.light) ...[
            _gallery(context, settings, Brightness.dark),
            const SizedBox(height: 24),
          ],
          if (settings.themeMode != AppThemeMode.dark) ...[
            _gallery(context, settings, Brightness.light),
            const SizedBox(height: 24),
          ],
          _heading(_t('appearance_accent'), colors.text),
          const SizedBox(height: 8),
          Text(
            _t('appearance_accent_hint'),
            style: TextStyle(color: colors.textMuted),
          ),
          const SizedBox(height: 12),
          _accents(context, settings),
          const SizedBox(height: 26),
          _heading(_t('appearance_logo'), colors.text),
          const SizedBox(height: 10),
          SwitchListTile(
            key: const Key('appearance_logo_match'),
            contentPadding: EdgeInsets.zero,
            title: Text(_t('appearance_logo_match_accent')),
            secondary: const ExcludeSemantics(
              child: EirenYuMark(key: Key('appearance_logo_preview'), size: 56),
            ),
            value: settings.matchLogoToAccent,
            onChanged: (value) {
              settings.setMatchLogoToAccent(value);
              IosHomeIconScope.request(context);
            },
          ),
          if (!settings.matchLogoToAccent) ...[
            const SizedBox(height: 12),
            Text(
              _t('appearance_logo_colour'),
              style: TextStyle(color: colors.text, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            _logoGallery(context, settings),
          ],
          if (Theme.of(context).platform == TargetPlatform.iOS) ...[
            const SizedBox(height: 20),
            Text(
              _t('home_screen_icon_title'),
              style: TextStyle(color: colors.text, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              _t('home_screen_icon_description'),
              style: TextStyle(color: colors.textMuted),
            ),
          ],
        ],
      );
    },
  );

  Widget _logoGallery(BuildContext context, SettingsManager settings) {
    final selected = settings.manualLogoColor;
    return SingleChildScrollView(
      key: const PageStorageKey('appearance_logo_gallery'),
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        spacing: 10,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (index, color) in ThemePresets.accentSwatches.indexed)
            _logoOption(
              context,
              index,
              color,
              selected: selected == color.toARGB32(),
              onPressed: () {
                settings.setManualLogoColor(color.toARGB32());
                IosHomeIconScope.request(context);
              },
            ),
        ],
      ),
    );
  }

  Widget _logoOption(
    BuildContext context,
    int index,
    Color color, {
    required bool selected,
    required VoidCallback onPressed,
  }) {
    final colors = context.colors;
    return SizedBox(
      width: 128,
      child: ChoiceChip(
        key: Key('appearance_logo_swatch_$index'),
        selected: selected,
        onSelected: (_) => onPressed(),
        padding: const EdgeInsets.all(10),
        labelPadding: EdgeInsets.zero,
        labelStyle: TextStyle(color: colors.text),
        color: WidgetStatePropertyAll(colors.surface),
        showCheckmark: false,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        side: selected
            ? BorderSide(color: colors.text, width: 2)
            : BorderSide(color: colors.border),
        label: Column(
          children: [
            Stack(
              children: [
                Center(
                  child: ExcludeSemantics(
                    child: EirenYuMark(size: 56, color: color),
                  ),
                ),
                if (selected)
                  const PositionedDirectional(
                    top: 0,
                    end: 0,
                    child: Icon(Icons.check_circle, size: 16),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(_t(_accentNameKeys[index]), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _heading(String label, Color color) => Text(
    label.toUpperCase(),
    style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w700),
  );

  Widget _gallery(
    BuildContext context,
    SettingsManager settings,
    Brightness brightness,
  ) {
    final colors = context.colors;
    final dark = brightness == Brightness.dark;
    final presets = ThemePresets.all
        .where((p) => dark ? p.dark != null : p.light != null)
        .toList();
    final selected = dark ? settings.darkThemeId : settings.lightThemeId;
    final accentOverride = settings.accentOverride;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(
          _t(dark ? 'appearance_dark_themes' : 'appearance_light_themes'),
          colors.text,
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final cardWidth = (constraints.maxWidth * 0.47)
                .clamp(146.0, 175.0)
                .toDouble();
            return SingleChildScrollView(
              key: PageStorageKey('appearance_gallery_${brightness.name}'),
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  for (var index = 0; index < presets.length; index++) ...[
                    if (index > 0) const SizedBox(width: 12),
                    SizedBox(
                      width: cardWidth,
                      child: _presetCard(
                        context,
                        presets[index],
                        accentOverride == null
                            ? (dark
                                  ? presets[index].dark!
                                  : presets[index].light!)
                            : (dark
                                      ? presets[index].dark!
                                      : presets[index].light!)
                                  .withAccent(Color(accentOverride)),
                        selected == presets[index].id,
                        accentOverride == null
                            ? null
                            : (dark
                                      ? presets[index].dark!
                                      : presets[index].light!)
                                  .accent,
                        () {
                          if (dark) {
                            settings.setDarkThemeId(presets[index].id);
                          } else {
                            settings.setLightThemeId(presets[index].id);
                          }
                          IosHomeIconScope.request(context);
                        },
                        brightness,
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _presetCard(
    BuildContext context,
    ThemePreset preset,
    MbPalette palette,
    bool selected,
    Color? nativeAccent,
    VoidCallback onTap,
    Brightness brightness,
  ) {
    final colors = context.colors;
    return Semantics(
      button: true,
      selected: selected,
      label: '${_names[preset.id] ?? preset.id}, ${brightness.name}',
      child: InkWell(
        key: Key('appearance_preset_${brightness.name}_${preset.id}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: palette.background,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? colors.accentForeground : palette.border,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ThemeMiniaturePreview(
                key: Key('appearance_preview_${brightness.name}_${preset.id}'),
                palette: palette,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _names[preset.id] ?? preset.id,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.text,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (nativeAccent != null) ...[
                    Container(
                      key: Key(
                        'appearance_native_accent_${brightness.name}_${preset.id}',
                      ),
                      width: 11,
                      height: 11,
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(
                        color: nativeAccent,
                        shape: BoxShape.circle,
                        border: Border.all(color: palette.border),
                      ),
                    ),
                  ],
                  if (selected)
                    Icon(
                      Icons.check_circle,
                      size: 16,
                      color: MbPalette.ensureContrast(
                        colors.accentForeground,
                        palette.background,
                        minimum: 3,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _accents(BuildContext context, SettingsManager settings) {
    final colors = context.colors;
    final selected = settings.accentOverride;
    final curated = ThemePresets.accentSwatches
        .map((c) => c.toARGB32())
        .toSet();
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ChoiceChip(
          key: const Key('appearance_accent_default'),
          label: Text(_t('appearance_theme_default')),
          selected: selected == null,
          onSelected: (_) {
            settings.setAccentOverride(null);
            IosHomeIconScope.request(context);
          },
        ),
        for (var i = 0; i < ThemePresets.accentSwatches.length; i++)
          _swatch(
            context,
            settings,
            ThemePresets.accentSwatches[i],
            selected,
            _t(_accentNameKeys[i]),
            'appearance_accent_$i',
          ),
        IconButton(
          key: const Key('appearance_custom_accent'),
          tooltip: _t('appearance_custom_accent'),
          onPressed: () => _showPicker(context, settings),
          icon: Icon(
            Icons.colorize,
            color: selected != null && !curated.contains(selected)
                ? colors.accentForeground
                : colors.text,
          ),
        ),
      ],
    );
  }

  Widget _swatch(
    BuildContext context,
    SettingsManager settings,
    Color swatch,
    int? selected,
    String label,
    String key,
  ) {
    final active = selected == swatch.toARGB32();
    final colors = context.colors;
    return Semantics(
      label:
          '$label, #${swatch.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
      selected: active,
      button: true,
      child: InkWell(
        key: Key(key),
        onTap: () {
          settings.setAccentOverride(swatch.toARGB32());
          IosHomeIconScope.request(context);
        },
        borderRadius: BorderRadius.circular(24),
        child: Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: swatch,
              border: Border.all(
                color: active ? colors.text : colors.border,
                width: active ? 3 : 1,
              ),
            ),
            child: active
                ? Icon(
                    Icons.check,
                    color: MbPalette.readableOn(swatch),
                    size: 22,
                  )
                : null,
          ),
        ),
      ),
    );
  }

  Future<void> _showPicker(
    BuildContext context,
    SettingsManager settings,
  ) async {
    final color = await showDialog<Color>(
      context: context,
      builder: (_) => _AccentPicker(
        initial: Color(
          settings.accentOverride ?? context.colors.accent.toARGB32(),
        ),
      ),
    );
    if (color != null && context.mounted) {
      settings.setAccentOverride(color.toARGB32());
      IosHomeIconScope.request(context);
    }
  }
}

class _AccentPicker extends StatefulWidget {
  const _AccentPicker({required this.initial});
  final Color initial;
  @override
  State<_AccentPicker> createState() => _AccentPickerState();
}

class _AccentPickerState extends State<_AccentPicker> {
  late HSVColor hsv = HSVColor.fromColor(widget.initial);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = hsv.toColor().withValues(alpha: 1);
    final viewport = MediaQuery.sizeOf(context);
    final width = math.min(360.0, viewport.width - 32);
    final height = math.min(400.0, viewport.height - 24);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: SizedBox(
        width: width,
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
              child: Text(
                LocalizationService().translate('appearance_custom_accent'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
                      style: TextStyle(color: colors.text),
                    ),
                    const SizedBox(height: 8),
                    for (final channel in ['hue', 'saturation', 'value'])
                      _channelSlider(channel),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 4,
                children: [
                  TextButton(
                    key: const Key('appearance_picker_cancel'),
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      MaterialLocalizations.of(context).cancelButtonLabel,
                    ),
                  ),
                  FilledButton(
                    key: const Key('appearance_picker_apply'),
                    onPressed: () => Navigator.pop(context, color),
                    child: Text(
                      LocalizationService().translate('appearance_apply'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _channelSlider(String channel) => Row(
    children: [
      SizedBox(
        width: 80,
        child: Text(LocalizationService().translate('appearance_$channel')),
      ),
      Expanded(
        child: Slider(
          key: Key('appearance_picker_$channel'),
          value: switch (channel) {
            'hue' => hsv.hue,
            'saturation' => hsv.saturation,
            _ => hsv.value,
          },
          min: 0,
          max: channel == 'hue' ? 360 : 1,
          onChanged: (v) => setState(
            () => hsv = switch (channel) {
              'hue' => hsv.withHue(v),
              'saturation' => hsv.withSaturation(v),
              _ => hsv.withValue(v),
            },
          ),
        ),
      ),
    ],
  );
}
