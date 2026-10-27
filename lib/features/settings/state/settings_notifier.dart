import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/json_store.dart';
import '../models/app_settings.dart';

class SettingsNotifier extends AsyncNotifier<AppSettings> {
  static const _fileName = 'settings.json';

  JsonStore get _store => ref.read(jsonStoreProvider);

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
}
