import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../ai/ai_connection_service.dart';
import '../../../ai/llm/ai_provider.dart';
import '../../models/app_settings.dart';
import '../../state/settings_notifier.dart';

/// Настройки облачного ИИ: выбор провайдера (YandexGPT/GigaChat/OpenAI-совм.),
/// динамические поля и проверка подключения.
class AiSettingsSection extends ConsumerStatefulWidget {
  const AiSettingsSection({super.key});

  @override
  ConsumerState<AiSettingsSection> createState() => _AiSettingsSectionState();
}

class _AiSettingsSectionState extends ConsumerState<AiSettingsSection> {
  late final TextEditingController _keyController;
  late final TextEditingController _urlController;
  late final TextEditingController _modelController;
  late final TextEditingController _folderController;
  late final TextEditingController _gigaKeyController;
  bool _testing = false;
  AiConnectionResult? _testResult;

  @override
  void initState() {
    super.initState();
    final s =
        ref.read(settingsProvider).valueOrNull ?? const AppSettings();
    _keyController = TextEditingController(text: s.aiApiKey);
    _urlController = TextEditingController(text: s.aiBaseUrl);
    _modelController = TextEditingController(text: s.aiModel);
    _folderController = TextEditingController(text: s.yandexFolderId);
    _gigaKeyController = TextEditingController(text: s.gigaChatAuthKey);
  }

  @override
  void dispose() {
    _keyController.dispose();
    _urlController.dispose();
    _modelController.dispose();
    _folderController.dispose();
    _gigaKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings =
        ref.watch(settingsProvider).valueOrNull ?? const AppSettings();
    final notifier = ref.read(settingsProvider.notifier);
    final provider = AiProvider.fromName(settings.aiProvider);
    final theme = Theme.of(context);

    return _Section(
      title: 'ИИ-распознавание',
      child: Column(
        children: [
          SwitchListTile(
            title: const Text('Понимать свободные формулировки'),
            subtitle: const Text('Облачная модель, при сбое — правила'),
            value: settings.aiEnabled,
            onChanged: notifier.toggleAi,
          ),
          if (settings.aiEnabled) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<AiProvider>(
                    initialValue: provider,
                    decoration: const InputDecoration(labelText: 'Провайдер'),
                    items: [
                      for (final p in AiProvider.values)
                        DropdownMenuItem(value: p, child: Text(p.label)),
                    ],
                    onChanged: (p) {
                      if (p == null) return;
                      notifier.updateAiConfig(
                        provider: p.name,
                        // Разумные дефолты под каждого провайдера.
                        model: _defaultModel(p),
                      );
                      setState(() => _testResult = null);
                    },
                  ),
                  const SizedBox(height: 12),
                  ..._fieldsFor(provider, notifier, theme),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                       Icon(Icons.shield_outlined,
                          size: 16, color: AppColors.gold),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Ключи хранятся только на устройстве. Ошибка модели '
                          'не блокирует приложение — оно работает на правилах.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    icon: _testing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.wifi_tethering, size: 18),
                    label: Text(_testing ? 'Проверяю…' : 'Проверить подключение'),
                    onPressed: _testing ? null : () => _runTest(notifier),
                  ),
                  if (_testResult != null) ...[
                    const SizedBox(height: 8),
                    _TestResultBanner(result: _testResult!),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _defaultModel(AiProvider p) {
    switch (p) {
      case AiProvider.yandexGpt:
        return 'yandexgpt-lite';
      case AiProvider.gigaChat:
        return 'GigaChat';
      case AiProvider.openaiCompatible:
        return 'gpt-4o-mini';
    }
  }

  List<Widget> _fieldsFor(
    AiProvider provider,
    SettingsNotifier notifier,
    ThemeData theme,
  ) {
    switch (provider) {
      case AiProvider.yandexGpt:
        return [
          TextField(
            controller: _keyController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Api-Key сервисного аккаунта',
              hintText: 'AQVN…',
            ),
            onChanged: (v) => notifier.updateAiConfig(apiKey: v),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _folderController,
            decoration: const InputDecoration(
              labelText: 'Folder ID (каталог Yandex Cloud)',
              hintText: 'b1gxxxxxxxxxxxx',
            ),
            onChanged: (v) => notifier.updateAiConfig(yandexFolderId: v),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _modelController,
            decoration: const InputDecoration(
              labelText: 'Модель',
              hintText: 'yandexgpt-lite',
            ),
            onChanged: (v) => notifier.updateAiConfig(model: v),
          ),
        ];
      case AiProvider.gigaChat:
        return [
          TextField(
            controller: _gigaKeyController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Ключ авторизации (Basic)',
              hintText: 'из личного кабинета GigaChat',
            ),
            onChanged: (v) => notifier.updateAiConfig(gigaChatAuthKey: v),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: ref.read(settingsProvider).valueOrNull?.gigaChatScope ??
                'GIGACHAT_API_PERS',
            decoration: const InputDecoration(labelText: 'Scope (версия API)'),
            items: const [
              DropdownMenuItem(
                  value: 'GIGACHAT_API_PERS',
                  child: Text('GIGACHAT_API_PERS (физлица)')),
              DropdownMenuItem(
                  value: 'GIGACHAT_API_CORP',
                  child: Text('GIGACHAT_API_CORP (бизнес)')),
              DropdownMenuItem(
                  value: 'GIGACHAT_API_B2B',
                  child: Text('GIGACHAT_API_B2B')),
            ],
            onChanged: (v) {
              if (v != null) notifier.updateAiConfig(gigaChatScope: v);
            },
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _modelController,
            decoration: const InputDecoration(
              labelText: 'Модель',
              hintText: 'GigaChat',
            ),
            onChanged: (v) => notifier.updateAiConfig(model: v),
          ),
        ];
      case AiProvider.openaiCompatible:
        return [
          TextField(
            controller: _keyController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'API-ключ',
              hintText: 'sk-...',
            ),
            onChanged: (v) => notifier.updateAiConfig(apiKey: v),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _urlController,
            decoration: const InputDecoration(
              labelText: 'Base URL',
              hintText: 'https://api.openai.com/v1',
            ),
            onChanged: (v) => notifier.updateAiConfig(baseUrl: v),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _modelController,
            decoration: const InputDecoration(labelText: 'Модель'),
            onChanged: (v) => notifier.updateAiConfig(model: v),
          ),
        ];
    }
  }

  Future<void> _runTest(SettingsNotifier notifier) async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    // Дать последним onChanged долететь до состояния.
    await Future<void>.delayed(const Duration(milliseconds: 150));
    final settings = ref.read(settingsProvider).valueOrNull!;
    final result =
        await ref.read(aiConnectionServiceProvider).test(settings);
    if (mounted) {
      setState(() {
        _testResult = result;
        _testing = false;
      });
    }
  }
}

class _TestResultBanner extends StatelessWidget {
  final AiConnectionResult result;
  const _TestResultBanner({required this.result});

  @override
  Widget build(BuildContext context) {
    final color = result.ok ? AppColors.success : AppColors.danger;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppColors.radiusButton),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(result.ok ? Icons.check_circle_outline : Icons.error_outline,
              color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(result.message,
                style: TextStyle(color: color, fontSize: 13)),
          ),
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
          // DecoratedBox перекрыл бы чернильные сплэши вложенных ListTile.
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
