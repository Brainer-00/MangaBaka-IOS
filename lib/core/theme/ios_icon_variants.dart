/// Exact bundled iOS icon colors. Null selects the existing primary icon.
const iosIconVariants = <(int, String?)>[
  (0xFF5BBD74, 'IconEmerald'),
  (0xFFFBD24B, 'IconAmber'),
  (0xFFFB923C, 'IconOrange'),
  (0xFFF43F5E, 'IconRose'),
  (0xFFF472B6, 'IconPink'),
  (0xFFA78BFA, 'IconViolet'),
  (0xFF60A5FA, 'IconBlue'),
  (0xFF22D3EE, 'IconCyan'),
  (0xFF2DD4BF, 'IconTeal'),
  (0xFFA3E635, 'IconLime'),
  (0xFFA82F4F, null),
  (0xFF8B7CF6, 'IconTwilightLavender'),
  (0xFF4CC9FF, 'IconHorizonBlue'),
];

String? iosIconForColor(int argb) {
  for (final (color, name) in iosIconVariants) {
    if (argb == color) return name;
  }
  return null;
}
