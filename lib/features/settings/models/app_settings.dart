import 'package:flutter/material.dart';

import '../../notes/models/custom_category.dart';

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

  /// id выбранной цветовой темы (см. ThemeVariant в core/theme).
  final String themeVariant;
  final AppFontSize fontSize;
  final bool proEnabled;

  // ИИ-распознавание (облачный LLM).
  final bool aiEnabled;
  final String aiProvider; // имя AiProvider
  final String aiApiKey;
  final String aiBaseUrl;
  final String aiModel;
  // YandexGPT
  final String yandexFolderId;
  // GigaChat
  final String gigaChatAuthKey;
  final String gigaChatScope;

  /// Пользовательские категории (в дополнение к семи встроенным).
  final List<CustomCategory> customCategories;

  const AppSettings({
    this.profileName = 'Я',
    this.email = '',
    this.notificationsEnabled = true,
    this.quietHoursEnabled = false,
    this.quietStartHour = 22,
    this.quietEndHour = 8,
    this.themeMode = ThemeMode.light,
    this.themeVariant = 'japandi',
    this.fontSize = AppFontSize.normal,
    this.proEnabled = false,
    this.aiEnabled = false,
    this.aiProvider = 'openaiCompatible',
    this.aiApiKey = '',
    this.aiBaseUrl = 'https://api.openai.com/v1',
    this.aiModel = 'gpt-4o-mini',
    this.yandexFolderId = '',
    this.gigaChatAuthKey = '',
    this.gigaChatScope = 'GIGACHAT_API_PERS',
    this.customCategories = const [],
  });

  AppSettings copyWith({
    String? profileName,
    String? email,
    bool? notificationsEnabled,
    bool? quietHoursEnabled,
    int? quietStartHour,
    int? quietEndHour,
    ThemeMode? themeMode,
    String? themeVariant,
    AppFontSize? fontSize,
    bool? proEnabled,
    bool? aiEnabled,
    String? aiProvider,
    String? aiApiKey,
    String? aiBaseUrl,
    String? aiModel,
    String? yandexFolderId,
    String? gigaChatAuthKey,
    String? gigaChatScope,
    List<CustomCategory>? customCategories,
  }) {
    return AppSettings(
      profileName: profileName ?? this.profileName,
      email: email ?? this.email,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      quietHoursEnabled: quietHoursEnabled ?? this.quietHoursEnabled,
      quietStartHour: quietStartHour ?? this.quietStartHour,
      quietEndHour: quietEndHour ?? this.quietEndHour,
      themeMode: themeMode ?? this.themeMode,
      themeVariant: themeVariant ?? this.themeVariant,
      fontSize: fontSize ?? this.fontSize,
      proEnabled: proEnabled ?? this.proEnabled,
      aiEnabled: aiEnabled ?? this.aiEnabled,
      aiProvider: aiProvider ?? this.aiProvider,
      aiApiKey: aiApiKey ?? this.aiApiKey,
      aiBaseUrl: aiBaseUrl ?? this.aiBaseUrl,
      aiModel: aiModel ?? this.aiModel,
      yandexFolderId: yandexFolderId ?? this.yandexFolderId,
      gigaChatAuthKey: gigaChatAuthKey ?? this.gigaChatAuthKey,
      gigaChatScope: gigaChatScope ?? this.gigaChatScope,
      customCategories: customCategories ?? this.customCategories,
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
        'themeVariant': themeVariant,
        'fontSize': fontSize.name,
        'proEnabled': proEnabled,
        'aiEnabled': aiEnabled,
        'aiProvider': aiProvider,
        'aiApiKey': aiApiKey,
        'aiBaseUrl': aiBaseUrl,
        'aiModel': aiModel,
        'yandexFolderId': yandexFolderId,
        'gigaChatAuthKey': gigaChatAuthKey,
        'gigaChatScope': gigaChatScope,
        'customCategories': customCategories.map((c) => c.toMap()).toList(),
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
        themeVariant: map['themeVariant'] as String? ?? 'japandi',
        fontSize: AppFontSize.values.firstWhere(
          (m) => m.name == map['fontSize'],
          orElse: () => AppFontSize.normal,
        ),
        proEnabled: map['proEnabled'] as bool? ?? false,
        aiEnabled: map['aiEnabled'] as bool? ?? false,
        aiProvider: map['aiProvider'] as String? ?? 'openaiCompatible',
        aiApiKey: map['aiApiKey'] as String? ?? '',
        aiBaseUrl: map['aiBaseUrl'] as String? ?? 'https://api.openai.com/v1',
        aiModel: map['aiModel'] as String? ?? 'gpt-4o-mini',
        yandexFolderId: map['yandexFolderId'] as String? ?? '',
        gigaChatAuthKey: map['gigaChatAuthKey'] as String? ?? '',
        gigaChatScope: map['gigaChatScope'] as String? ?? 'GIGACHAT_API_PERS',
        customCategories: (map['customCategories'] as List<dynamic>? ?? const [])
            .map((e) => CustomCategory.fromMap(e as Map<String, dynamic>))
            .toList(),
      );
}
