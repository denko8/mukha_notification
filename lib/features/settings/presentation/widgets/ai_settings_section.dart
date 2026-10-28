import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../models/app_settings.dart';

/// Настройки облачного ИИ-распознавания (P3 ТЗ).
/// Ключ хранится только локально на устройстве.
class AiSettingsSection extends ConsumerStatefulWidget {
  const AiSettingsSection({super.key});

  @override
  ConsumerState<AiSettingsSection> createState() => _AiSettingsSectionState();
}

class _AiSettingsSectionState extends ConsumerState<AiSettingsSection> {
  late final TextEditingController _keyController;
  late final TextEditingController _urlController;
  late final TextEditingController _modelController;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider).valueOrNull ??
        const AppSettings();
    _keyController = TextEditingController(text: settings.aiApiKey);
    _urlController = TextEditingController(text: settings.aiBaseUrl);
    _modelController = TextEditingController(text: settings.aiModel);
  }

  @override
  void dispose() {
    _keyController.dispose();
    _urlController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider).valueOrNull ??
        const AppSettings();
    final notifier = ref.read(settingsProvider.notifier);
    final theme = Theme.of(context);

    return _Section(
      title: 'ИИ-распознавание',
      child: Column(
        children: [
          SwitchListTile(
            title: const Text('Понимать свободные формулировки'),
            subtitle: const Text('Облачная модель вместо жёстких правил'),
            value: settings.aiEnabled,
            onChanged: notifier.toggleAi,
          ),
          if (settings.aiEnabled)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
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
                      labelText: 'Base URL (OpenAI-совместимый)',
                      hintText: 'https://api.openai.com/v1',
                    ),
                    onChanged: (v) => notifier.updateAiConfig(baseUrl: v),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _modelController,
                    decoration: const InputDecoration(
                      labelText: 'Модель',
                      hintText: 'gpt-4o-mini',
                    ),
                    onChanged: (v) => notifier.updateAiConfig(model: v),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(Icons.shield_outlined,
                          size: 16, color: AppColors.gold),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Ключ хранится только на устройстве. При ошибке модели '
                          'приложение автоматически работает на правилах.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
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
          Container(
            decoration: BoxDecoration(
              color: theme.cardTheme.color,
              borderRadius: BorderRadius.circular(AppColors.radiusCard),
              boxShadow: const [
                BoxShadow(
                    color: AppColors.shadow, blurRadius: 8, offset: Offset(0, 2)),
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
