import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/services/json_store.dart';
import '../../notes/models/custom_category.dart';
import '../models/app_settings.dart';

class SettingsNotifier extends AsyncNotifier<AppSettings> {
  static const _fileName = 'settings.json';

  JsonStoreBase get _store => ref.read(jsonStoreProvider);

  @override
  Future<AppSettings> build() async {
    final raw = await _store.readJson(_fileName);
    return raw == null ? const AppSettings() : AppSettings.fromMap(raw);
  }

  Future<void> _save(AppSettings settings) async {
    state = AsyncData(settings);
    await _store.writeJson(_fileName, settings.toMap());
  }

  Future<void> updateThemeMode(ThemeMode mode) =>
      _save(state.value!.copyWith(themeMode: mode));

  Future<void> updateFontSize(AppFontSize size) =>
      _save(state.value!.copyWith(fontSize: size));

  Future<void> toggleNotifications(bool enabled) =>
      _save(state.value!.copyWith(notificationsEnabled: enabled));

  Future<void> toggleQuietHours(bool enabled) =>
      _save(state.value!.copyWith(quietHoursEnabled: enabled));

  Future<void> setQuietHours(int start, int end) =>
      _save(state.value!.copyWith(quietStartHour: start, quietEndHour: end));

  Future<void> updateProfile({String? name, String? email}) => _save(
        state.value!.copyWith(
          profileName: name ?? state.value!.profileName,
          email: email ?? state.value!.email,
        ),
      );

  Future<void> setPro(bool enabled) =>
      _save(state.value!.copyWith(proEnabled: enabled));

  Future<void> toggleAi(bool enabled) =>
      _save(state.value!.copyWith(aiEnabled: enabled));

  // --- Пользовательские категории -------------------------------------

  /// Создаёт категорию. Уникальность названия проверяет UI через
  /// CategoryCatalog; здесь — защита от пустого названия.
  Future<CustomCategory> addCustomCategory({
    required String label,
    List<String> keywords = const [],
  }) async {
    final trimmed = label.trim();
    if (trimmed.isEmpty) throw ArgumentError('Название категории пустое');
    final category = CustomCategory(
      id: ref.read(uuidProvider).v4(),
      label: trimmed,
      keywords: keywords,
    );
    await _save(state.value!.copyWith(
      customCategories: [...state.value!.customCategories, category],
    ));
    return category;
  }

  Future<void> updateCustomCategory(CustomCategory updated) async {
    final list = [
      for (final c in state.value!.customCategories)
        c.id == updated.id ? updated : c,
    ];
    await _save(state.value!.copyWith(customCategories: list));
  }

  Future<void> removeCustomCategory(String id) async {
    final list = state.value!.customCategories
        .where((c) => c.id != id)
        .toList(growable: false);
    await _save(state.value!.copyWith(customCategories: list));
  }

  Future<void> updateAiConfig({
    String? apiKey,
    String? baseUrl,
    String? model,
    String? provider,
    String? yandexFolderId,
    String? gigaChatAuthKey,
    String? gigaChatScope,
  }) =>
      _save(state.value!.copyWith(
        aiApiKey: apiKey,
        aiBaseUrl: baseUrl,
        aiModel: model,
        aiProvider: provider,
        yandexFolderId: yandexFolderId,
        gigaChatAuthKey: gigaChatAuthKey,
        gigaChatScope: gigaChatScope,
      ));
}
