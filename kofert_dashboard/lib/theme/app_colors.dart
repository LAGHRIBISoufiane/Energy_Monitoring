import 'package:flutter/material.dart';

/// Semantic color palette registered in both light and dark [ThemeData].
///
/// Usage:
///   final c = AppColors.of(context);
///   Container(color: c.card)
class AppColors extends ThemeExtension<AppColors> {
  final Color bg;
  final Color sidebar;
  final Color card;
  final Color cardAlt; // slightly lighter/darker than card for nested containers
  final Color textPri;
  final Color textSec;
  final Color divider;
  final Color inputFill;
  final Color dropdownBg;

  const AppColors({
    required this.bg,
    required this.sidebar,
    required this.card,
    required this.cardAlt,
    required this.textPri,
    required this.textSec,
    required this.divider,
    required this.inputFill,
    required this.dropdownBg,
  });

  // ── Dark palette ────────────────────────────────────────────────────────────
  static const dark = AppColors(
    bg:         Color(0xFF1E1E2E),
    sidebar:    Color(0xFF16162A),
    card:       Color(0xFF252535),
    cardAlt:    Color(0xFF1A2538),
    textPri:    Color(0xFFFFFFFF),
    textSec:    Color(0x99FFFFFF),
    divider:    Color(0x1FFFFFFF),
    inputFill:  Color(0xFF252535),
    dropdownBg: Color(0xFF252535),
  );

  // ── Light palette ───────────────────────────────────────────────────────────
  static const light = AppColors(
    bg:         Color(0xFFF0F4F8),
    sidebar:    Color(0xFFE2EBF5),
    card:       Color(0xFFFFFFFF),
    cardAlt:    Color(0xFFEDF2F8),
    textPri:    Color(0xFF1A2030),
    textSec:    Color(0xFF64748B),
    divider:    Color(0xFFDDE3ED),
    inputFill:  Color(0xFFF8FAFC),
    dropdownBg: Color(0xFFFFFFFF),
  );

  /// Returns [AppColors] from the current [Theme], falling back to [dark].
  static AppColors of(BuildContext context) =>
      Theme.of(context).extension<AppColors>() ?? dark;

  @override
  AppColors copyWith({
    Color? bg,
    Color? sidebar,
    Color? card,
    Color? cardAlt,
    Color? textPri,
    Color? textSec,
    Color? divider,
    Color? inputFill,
    Color? dropdownBg,
  }) =>
      AppColors(
        bg:         bg         ?? this.bg,
        sidebar:    sidebar    ?? this.sidebar,
        card:       card       ?? this.card,
        cardAlt:    cardAlt    ?? this.cardAlt,
        textPri:    textPri    ?? this.textPri,
        textSec:    textSec    ?? this.textSec,
        divider:    divider    ?? this.divider,
        inputFill:  inputFill  ?? this.inputFill,
        dropdownBg: dropdownBg ?? this.dropdownBg,
      );

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other == null) return this;
    return AppColors(
      bg:         Color.lerp(bg,         other.bg,         t)!,
      sidebar:    Color.lerp(sidebar,    other.sidebar,    t)!,
      card:       Color.lerp(card,       other.card,       t)!,
      cardAlt:    Color.lerp(cardAlt,    other.cardAlt,    t)!,
      textPri:    Color.lerp(textPri,    other.textPri,    t)!,
      textSec:    Color.lerp(textSec,    other.textSec,    t)!,
      divider:    Color.lerp(divider,    other.divider,    t)!,
      inputFill:  Color.lerp(inputFill,  other.inputFill,  t)!,
      dropdownBg: Color.lerp(dropdownBg, other.dropdownBg, t)!,
    );
  }
}
