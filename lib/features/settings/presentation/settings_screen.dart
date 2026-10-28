import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../models/app_settings.dart';
import 'paywall_screen.dart';
import 'widgets/ai_settings_section.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).valueOrNull ??
        const AppSettings();
    final notifier = ref.read(settingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Section(
            title: 'Профиль',
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: AppColors.gold,
                child: Text(
                  settings.profileName.isNotEmpty
                      ? settings.profileName[0].toUpperCase()
                      : '?',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              title: Text(settings.profileName),
              subtitle: Text(settings.email.isEmpty ? 'Email не указан' : settings.email),
              trailing: const Icon(Icons.edit, color: AppColors.gold),
              onTap: () => _editProfile(context, ref),
            ),
          ),
          _Section(
            title: 'Уведомления',
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Напоминания'),
                  value: settings.notificationsEnabled,
                  onChanged: notifier.toggleNotifications,
                ),
                SwitchListTile(
                  title: const Text('Тихие часы'),
                  subtitle: Text(
                    'С ${settings.quietStartHour}:00 до ${settings.quietEndHour}:00',
                  ),
                  value: settings.quietHoursEnabled,
                  onChanged: notifier.toggleQuietHours,
                ),
                if (settings.quietHoursEnabled)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            child: Text('Старт: ${settings.quietStartHour}:00'),
                            onPressed: () async {
                              final h = await _pickHour(context, settings.quietStartHour);
                              if (h != null) {
                                await notifier.setQuietHours(h, settings.quietEndHour);
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton(
                            child: Text('Конец: ${settings.quietEndHour}:00'),
                            onPressed: () async {
                              final h = await _pickHour(context, settings.quietEndHour);
                              if (h != null) {
                                await notifier.setQuietHours(settings.quietStartHour, h);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          _Section(
            title: 'Внешний вид',
            child: Column(
              children: [
                const SizedBox(height: 8),
                SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(value: ThemeMode.light, label: Text('Светлая')),
                    ButtonSegment(value: ThemeMode.dark, label: Text('Тёмная')),
                    ButtonSegment(value: ThemeMode.system, label: Text('Авто')),
                  ],
                  selected: {settings.themeMode},
                  onSelectionChanged: (s) => notifier.updateThemeMode(s.first),
                ),
                const SizedBox(height: 12),
                SegmentedButton<AppFontSize>(
                  segments: [
                    for (final size in AppFontSize.values)
                      ButtonSegment(value: size, label: Text(size.label)),
                  ],
                  selected: {settings.fontSize},
                  onSelectionChanged: (s) => notifier.updateFontSize(s.first),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
          _SyncSection(),
          const AiSettingsSection(),
          _Section(
            title: 'О приложении',
            child: Column(
              children: [
                const ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('Версия'),
                  trailing: Text('0.1.0 (MVP)'),
                ),
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: const Text('Политика конфиденциальности'),
                  onTap: () => _comingSoon(context),
                ),
                ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: const Text('Условия использования'),
                  onTap: () => _comingSoon(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            icon: Icon(settings.proEnabled ? Icons.verified : Icons.workspace_premium),
            label: Text(settings.proEnabled
                ? 'PRO активна'
                : 'Попробовать PRO (5 дней бесплатно)'),
            onPressed: settings.proEnabled
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const PaywallScreen())),
          ),
        ],
      ),
    );
  }

  Future<void> _editProfile(BuildContext context, WidgetRef ref) async {
    final settings = ref.read(settingsProvider).valueOrNull ?? const AppSettings();
    final nameController = TextEditingController(text: settings.profileName);
    final emailController = TextEditingController(text: settings.email);
    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Редактировать профиль'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameController,
                decoration: const InputDecoration(hintText: 'Имя'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Укажите имя' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: emailController,
                decoration: const InputDecoration(hintText: 'Email'),
                keyboardType: TextInputType.emailAddress,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) Navigator.pop(ctx);
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );

    await ref.read(settingsProvider.notifier).updateProfile(
          name: nameController.text.trim(),
          email: emailController.text.trim(),
        );
  }

  Future<int?> _pickHour(BuildContext context, int initial) {
    return showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        children: [
          for (var h = 0; h < 24; h++)
            SimpleDialogOption(
              child: Text('$h:00'),
              onPressed: () => Navigator.pop(ctx, h),
            ),
        ],
      ),
    );
  }

  void _comingSoon(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Документы будут опубликованы к релизу')),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;

  const _Section({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(title, style: theme.textTheme.titleLarge),
          ),
          Container(
            decoration: BoxDecoration(
              color: theme.cardTheme.color,
              borderRadius: BorderRadius.circular(AppColors.radiusCard),
              boxShadow: const [
                BoxShadow(color: AppColors.shadow, blurRadius: 8, offset: Offset(0, 2)),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppColors.radiusCard),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

class _SyncSection extends ConsumerStatefulWidget {
  @override
  ConsumerState<_SyncSection> createState() => _SyncSectionState();
}

class _SyncSectionState extends ConsumerState<_SyncSection> {
  bool _syncing = false;

  @override
  Widget build(BuildContext context) {
    final sync = ref.watch(syncServiceProvider);
    return _Section(
      title: 'Синхронизация',
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.cloud_outlined),
            title: Text(_syncing ? 'Синхронизируется…' : 'Синхронизировано'),
            subtitle: Text(sync.lastSyncAt != null
                ? 'Последняя: ${sync.lastSyncAt!.toLocal().toString().substring(0, 16)}'
                : 'Ещё не выполнялась'),
            trailing: _syncing
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : const Icon(Icons.check_circle, color: AppColors.success),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.sync),
                    label: const Text('Синхронизировать сейчас'),
                    onPressed: _syncing
                        ? null
                        : () async {
                            setState(() => _syncing = true);
                            // Полный цикл: имитация облачной отправки +
                            // снятие флага pendingSync у всех заметок.
                            await ref.read(notesNotifierProvider.notifier).syncNow();
                            if (mounted) setState(() => _syncing = false);
                          },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
