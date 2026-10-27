import 'package:flutter/material.dart';

enum AppFontSize {
  small(0.9, 'Маленький'),
  normal(1.0, 'Нормальный'),
  large(1.15, 'Большой');

  final double scale;
  final String label;
  const AppFontSize(this.scale, this.label);
}

/// Все пользовательские настройки экрана Settings (раздел 2.4 ТЗ).
class AppSettings {
  final String profileName;
  final String email;
  final bool notificationsEnabled;
  final bool quietHoursEnabled;
  final int quietStartHour;
  final int quietEndHour;
  final ThemeMode themeMode;
  final AppFontSize fontSize;
  final bool proEnabled;

  const AppSettings({
    this.profileName = 'Я',
    this.email = '',
    this.notificationsEnabled = true,
    this.quietHoursEnabled = false,
    this.quietStartHour = 22,
    this.quietEndHour = 8,
    this.themeMode = ThemeMode.light,
    this.fontSize = AppFontSize.normal,
    this.proEnabled = false,
  });

  AppSettings copyWith({
    String? profileName,
    String? email,
    bool? notificationsEnabled,
    bool? quietHoursEnabled,
    int? quietStartHour,
    int? quietEndHour,
    ThemeMode? themeMode,
    AppFontSize? fontSize,
    bool? proEnabled,
  }) {
    return AppSettings(
      profileName: profileName ?? this.profileName,
      email: email ?? this.email,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      quietHoursEnabled: quietHoursEnabled ?? this.quietHoursEnabled,
      quietStartHour: quietStartHour ?? this.quietStartHour,
      quietEndHour: quietEndHour ?? this.quietEndHour,
      themeMode: themeMode ?? this.themeMode,
      fontSize: fontSize ?? this.fontSize,
      proEnabled: proEnabled ?? this.proEnabled,
    );
  }

  Map<String, dynamic> toMap() => {
        'profileName': profileName,
        'email': email,
        'notificationsEnabled': notificationsEnabled,
        'quietHoursEnabled': quietHoursEnabled,
        'quietStartHour': quietStartHour,
        'quietEndHour': quietEndHour,
        'themeMode': themeMode.name,
        'fontSize': fontSize.name,
        'proEnabled': proEnabled,
      };

  factory AppSettings.fromMap(Map<String, dynamic> map) => AppSettings(
        profileName: map['profileName'] as String? ?? 'Я',
        email: map['email'] as String? ?? '',
        notificationsEnabled: map['notificationsEnabled'] as bool? ?? true,
        quietHoursEnabled: map['quietHoursEnabled'] as bool? ?? false,
        quietStartHour: map['quietStartHour'] as int? ?? 22,
        quietEndHour: map['quietEndHour'] as int? ?? 8,
        themeMode: ThemeMode.values.firstWhere(
          (m) => m.name == map['themeMode'],
          orElse: () => ThemeMode.light,
        ),
        fontSize: AppFontSize.values.firstWhere(
          (m) => m.name == map['fontSize'],
          orElse: () => AppFontSize.normal,
        ),
        proEnabled: map['proEnabled'] as bool? ?? false,
      );
}
