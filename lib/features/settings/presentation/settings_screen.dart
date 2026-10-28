import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../app/providers.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/theme/app_colors.dart';
import '../models/app_settings.dart';
import 'paywall_screen.dart';
import 'widgets/ai_settings_section.dart';
import 'widgets/category_manage_screen.dart';

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
              trailing: Icon(Icons.edit, color: AppColors.gold),
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
                const Divider(height: 1),
                ListTile(
                  leading:  Icon(Icons.notification_important_outlined,
                      color: AppColors.gold),
                  title: const Text('Проверить уведомление'),
                  subtitle: const Text(
                    'Тест через 10 секунд и статус разрешений',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _runNotificationTest(context, ref),
                ),
              ],
            ),
          ),
          _Section(
            title: 'Внешний вид',
            child: Column(
              children: [
                const SizedBox(height: 8),
                _ThemeVariantPicker(
                  selectedId: settings.themeVariant,
                  onSelected: notifier.updateThemeVariant,
                ),
                const SizedBox(height: 12),
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
          _Section(
            title: 'Категории',
            child: ListTile(
              leading: Icon(Icons.label_outline, color: AppColors.gold),
              title: const Text('Мои категории'),
              subtitle: Text(settings.customCategories.isEmpty
                  ? 'Создать свою категорию для заметок'
                  : 'Своих категорий: ${settings.customCategories.length}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const CategoryManageScreen(),
                ),
              ),
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

  Future<void> _runNotificationTest(
      BuildContext context, WidgetRef ref) async {
    final service = ref.read(notificationServiceProvider);
    final messenger = ScaffoldMessenger.of(context);
    if (service is NoopNotificationService) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('На этой платформе локальные уведомления недоступны'),
        ),
      );
      return;
    }

    // Просим исключить приложение из энергосбережения: на vivo это
    // частая причина, по которой точные будильники не срабатывают.
    try {
      await Permission.ignoreBatteryOptimizations.request();
    } catch (_) {
      // Часть прошивок не показывает системный диалог — не критично,
      // ниже даём ручной чек-лист и кнопку настроек.
    }

    final diag = await service.diagnose();
    // Два теста: немедленный проверяет сам канал уведомлений,
    // отложенный (10 с) — работу AlarmManager в фоне.
    await service.showImmediateTest();
    await service.scheduleTest();

    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Проверка уведомлений'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DiagRow(
              ok: diag.notificationsAllowed,
              text: 'Разрешение на уведомления',
            ),
            _DiagRow(
              ok: diag.exactAlarmsAllowed,
              text: 'Точные будильники',
            ),
            _DiagRow(
              ok: diag.pendingCount > 0,
              text: 'Уведомлений в очереди: ${diag.pendingCount}',
            ),
            const SizedBox(height: 10),
            const Text(
              '1. Немедленное уведомление должно быть видно прямо сейчас.\n'
              '2. Второе придёт через 10 секунд.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 8),
            const Text(
              'Если первого нет — система блокирует канал: Настройки → '
              'Приложения → Smart Notes → Уведомления, включить все '
              'категории. Если первый есть, а второй нет — это '
              'энергосбережение vivo: Автозапуск включить, Батарея → '
              '«Нет ограничений», закрепить приложение замком в '
              'недавних.',
              style: TextStyle(fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              openAppSettings();
            },
            child: const Text('Открыть настройки'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Понятно'),
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

/// Выбор цветовой темы: кружок-образец акцента на фоне светлой
/// карточки варианта, подпись и галочка у выбранного.
class _ThemeVariantPicker extends StatelessWidget {
  final String selectedId;
  final ValueChanged<String> onSelected;

  const _ThemeVariantPicker({
    required this.selectedId,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text('Цветовая тема', style: theme.textTheme.bodySmall),
        ),
        Wrap(
          spacing: 14,
          runSpacing: 12,
          children: [
            for (final v in ThemeVariant.all)
              Tooltip(
                message: v.description,
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => onSelected(v.id),
                  child: SizedBox(
                    width: 64,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: v.lightCard,
                            border: Border.all(
                              color: selectedId == v.id
                                  ? v.accent
                                  : theme.dividerColor,
                              width: selectedId == v.id ? 2.5 : 1,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: v.accent,
                            ),
                            child: selectedId == v.id
                                ? const Icon(Icons.check,
                                    size: 14, color: Colors.white)
                                : null,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          v.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: selectedId == v.id
                                ? FontWeight.w700
                                : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _DiagRow extends StatelessWidget {
  final bool ok;
  final String text;

  const _DiagRow({required this.ok, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            ok ? Icons.check_circle : Icons.cancel,
            size: 18,
            color: ok ? AppColors.success : AppColors.danger,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14))),
        ],
      ),
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
          // Тень — на внешнем Container, фон — на Material: иначе
          // DecoratedBox перекрыл бы чернильные сплэши вложенных ListTile
          // (assert «ListTile background color or ink splashes may be
          // invisible»).
          Container(
            decoration: const BoxDecoration(
              borderRadius: BorderRadius.all(
                Radius.circular(AppColors.radiusCard),
              ),
              boxShadow: [
                BoxShadow(
                    color: AppColors.shadow,
                    blurRadius: 8,
                    offset: Offset(0, 2)),
              ],
            ),
            child: Material(
              color: theme.cardTheme.color,
              borderRadius:
                  BorderRadius.circular(AppColors.radiusCard),
              clipBehavior: Clip.antiAlias,
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
                : Icon(Icons.check_circle, color: AppColors.success),
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
