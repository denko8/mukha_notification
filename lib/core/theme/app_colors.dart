import 'package:flutter/material.dart';

/// Палитра Smart Notes — раздел 5 ТЗ (стиль Japandi, теплый минимализм).
class AppColors {
  AppColors._();

  // Светлая тема
  static const Color lightBackground = Color(0xFFF5F5F0); // (245,245,240)
  static const Color lightCard = Color(0xFFFCFAF5);
  static const Color lightText = Color(0xFF323232); // (50,50,50)
  static const Color lightSecondaryText = Color(0xFF8A857C);

  // Тёмная тема
  static const Color darkBackground = Color(0xFF191916); // (25,25,22)
  static const Color darkCard = Color(0xFF24231F);
  static const Color darkText = Color(0xFFE6E6E1); // (230,230,225)
  static const Color darkSecondaryText = Color(0xFF9C978D);

  // Акцент
  static const Color gold = Color(0xFFB89A62); // (184,154,98)
  static const Color goldAlt = Color(0xFFC8AA64); // (200,170,100)
  static const Color goldSoft = Color(0x33B89A62); // акцент с прозрачностью

  // Статусы / сервис
  static const Color danger = Color(0xFFB05A4E);
  static const Color success = Color(0xFF7A9B6E);
  static const Color shadow = Color(0x1A000000); // (0,0,0,0.1)

  // Радиусы — раздел 5 ТЗ
  static const double radiusCard = 12;
  static const double radiusButton = 8;
}
