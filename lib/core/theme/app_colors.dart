import 'package:flutter/material.dart';

/// Оформительская тема (цветовая палитра). Пользователь выбирает её
/// в настройках; выбор хранится в AppSettings.themeVariant.
///
/// Каждый вариант задаёт акцентные цвета и собственные светлые
/// нейтрали (фон/карточки/текст). Тёмные нейтрали общие — на тёмном
/// фоне меняется только акцент.
class ThemeVariant {
  final String id;
  final String label;
  final String description;

  final Color accent;
  final Color accentAlt;
  final Color accentSoft;

  final Color lightBackground;
  final Color lightCard;
  final Color lightText;
  final Color lightSecondaryText;

  const ThemeVariant({
    required this.id,
    required this.label,
    required this.description,
    required this.accent,
    required this.accentAlt,
    required this.accentSoft,
    required this.lightBackground,
    required this.lightCard,
    required this.lightText,
    required this.lightSecondaryText,
  });

  /// Тёмные нейтрали общие для всех вариантов.
  Color get darkBackground => const Color(0xFF191916);
  Color get darkCard => const Color(0xFF24231F);
  Color get darkText => const Color(0xFFE6E6E1);
  Color get darkSecondaryText => const Color(0xFF9C978D);

  static const ThemeVariant japandi = ThemeVariant(
    id: 'japandi',
    label: 'Япанди',
    description: 'Тёплый минимализм, золото и беж',
    accent: Color(0xFFB89A62),
    accentAlt: Color(0xFFC8AA64),
    accentSoft: Color(0x33B89A62),
    lightBackground: Color(0xFFF5F5F0),
    lightCard: Color(0xFFFCFAF5),
    lightText: Color(0xFF323232),
    lightSecondaryText: Color(0xFF8A857C),
  );

  static const ThemeVariant terracotta = ThemeVariant(
    id: 'terracotta',
    label: 'Терракота',
    description: 'Глиняно-оранжевый, тёплый и уютный',
    accent: Color(0xFFC0714F),
    accentAlt: Color(0xFFD08A66),
    accentSoft: Color(0x33C0714F),
    lightBackground: Color(0xFFF7F1EB),
    lightCard: Color(0xFFFDF9F4),
    lightText: Color(0xFF3A2E28),
    lightSecondaryText: Color(0xFF978173),
  );

  static const ThemeVariant sage = ThemeVariant(
    id: 'sage',
    label: 'Шалфей',
    description: 'Приглушённый зелёный, спокойствие природы',
    accent: Color(0xFF6E8F61),
    accentAlt: Color(0xFF86A478),
    accentSoft: Color(0x336E8F61),
    lightBackground: Color(0xFFF2F5EF),
    lightCard: Color(0xFFFAFCF7),
    lightText: Color(0xFF2F352C),
    lightSecondaryText: Color(0xFF7E8876),
  );

  static const ThemeVariant ocean = ThemeVariant(
    id: 'ocean',
    label: 'Океан',
    description: 'Холодный синий, собранность и ясность',
    accent: Color(0xFF4F7DA3),
    accentAlt: Color(0xFF6A95B7),
    accentSoft: Color(0x334F7DA3),
    lightBackground: Color(0xFFEFF3F7),
    lightCard: Color(0xFFFAFCFE),
    lightText: Color(0xFF26303A),
    lightSecondaryText: Color(0xFF77848F),
  );

  static const ThemeVariant lavender = ThemeVariant(
    id: 'lavender',
    label: 'Лаванда',
    description: 'Мягкий фиолетовый, творческое настроение',
    accent: Color(0xFF8A74B8),
    accentAlt: Color(0xFFA08BC9),
    accentSoft: Color(0x338A74B8),
    lightBackground: Color(0xFFF4F1F8),
    lightCard: Color(0xFFFBF9FE),
    lightText: Color(0xFF312C3A),
    lightSecondaryText: Color(0xFF847C92),
  );

  static const ThemeVariant graphite = ThemeVariant(
    id: 'graphite',
    label: 'Графит',
    description: 'Монохром, строго и ничего лишнего',
    accent: Color(0xFF6B6B70),
    accentAlt: Color(0xFF86868C),
    accentSoft: Color(0x336B6B70),
    lightBackground: Color(0xFFF4F4F5),
    lightCard: Color(0xFFFCFCFD),
    lightText: Color(0xFF2B2B2E),
    lightSecondaryText: Color(0xFF86868C),
  );

  static const List<ThemeVariant> all = [
    japandi,
    terracotta,
    sage,
    ocean,
    lavender,
    graphite,
  ];

  static ThemeVariant byId(String? id) => all.firstWhere(
        (v) => v.id == id,
        orElse: () => japandi,
      );
}

/// Палитра Smart Notes. Поля изменяемые: при выборе [ThemeVariant]
/// значения переназначаются через [applyVariant], а MaterialApp
/// пересобирается — все 100+ существующих обращений AppColors.*
/// продолжают работать без миграции на ThemeExtension.
class AppColors {
  AppColors._();

  // Акцент (историческое имя gold сохранено для совместимости).
  static Color gold = ThemeVariant.japandi.accent;
  static Color goldAlt = ThemeVariant.japandi.accentAlt;
  static Color goldSoft = ThemeVariant.japandi.accentSoft;

  // Светлая тема
  static Color lightBackground = ThemeVariant.japandi.lightBackground;
  static Color lightCard = ThemeVariant.japandi.lightCard;
  static Color lightText = ThemeVariant.japandi.lightText;
  static Color lightSecondaryText =
      ThemeVariant.japandi.lightSecondaryText;

  // Тёмная тема
  static Color darkBackground = ThemeVariant.japandi.darkBackground;
  static Color darkCard = ThemeVariant.japandi.darkCard;
  static Color darkText = ThemeVariant.japandi.darkText;
  static Color darkSecondaryText = ThemeVariant.japandi.darkSecondaryText;

  // Статусы / сервис — одинаковы во всех вариантах
  static const Color danger = Color(0xFFB05A4E);
  static const Color success = Color(0xFF7A9B6E);
  static const Color shadow = Color(0x1A000000); // (0,0,0,0.1)

  // Радиусы — раздел 5 ТЗ
  static const double radiusCard = 12;
  static const double radiusButton = 8;

  /// Переназначает палитру под выбранный вариант. Идемпотентна.
  static void applyVariant(ThemeVariant v) {
    gold = v.accent;
    goldAlt = v.accentAlt;
    goldSoft = v.accentSoft;
    lightBackground = v.lightBackground;
    lightCard = v.lightCard;
    lightText = v.lightText;
    lightSecondaryText = v.lightSecondaryText;
    darkBackground = v.darkBackground;
    darkCard = v.darkCard;
    darkText = v.darkText;
    darkSecondaryText = v.darkSecondaryText;
  }
}
