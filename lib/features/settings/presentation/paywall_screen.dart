import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/theme/app_colors.dart';

/// Экран подписки PRO (раздел 2.4 ТЗ).
class PaywallScreen extends ConsumerWidget {
  const PaywallScreen({super.key});

  static const _benefits = [
    'Безлимитные вложения: фото, PDF и аудио',
    'Голосовой ввод и транскрибация',
    'OCR: распознавание счетов и билетов',
    'Несколько семейных досок',
    'ИИ-определение типа заметки',
    'Экспорт в PDF без водяного знака',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Smart Notes PRO')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.gold, AppColors.goldAlt],
              ),
              borderRadius: BorderRadius.circular(AppColors.radiusCard),
            ),
            child: Column(
              children: [
                const Icon(Icons.workspace_premium, size: 56, color: Colors.white),
                const SizedBox(height: 8),
                Text('Попробуйте PRO',
                    style: theme.textTheme.headlineMedium
                        ?.copyWith(color: Colors.white)),
                const SizedBox(height: 4),
                const Text(
                  '5 дней бесплатно, далее — подписка',
                  style: TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          for (final benefit in _benefits)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.check_circle, color: AppColors.gold, size: 20),
                  const SizedBox(width: 10),
                  Expanded(child: Text(benefit, style: theme.textTheme.bodyLarge)),
                ],
              ),
            ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () async {
              final billing = ref.read(billingServiceProvider);
              final messenger = ScaffoldMessenger.of(context);
              // На web/в тестах billing — симуляция и сразу вернёт успех.
              final ok = await billing.purchasePro();
              if (!ok) {
                messenger.showSnackBar(
                  const SnackBar(content: Text('Покупка не завершена, попробуйте позже')),
                );
                return;
              }
              await ref.read(settingsProvider.notifier).setPro(true);
              if (context.mounted) {
                Navigator.of(context).pop();
                messenger.showSnackBar(
                  const SnackBar(content: Text('Пробный период PRO активирован')),
                );
              }
            },
            child: const Text('Активировать 5 дней бесплатно'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () async {
              final restored = await ref.read(billingServiceProvider).restorePro();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(restored
                        ? 'Восстановление запущено'
                        : 'Магазин недоступен на этом устройстве'),
                  ),
                );
              }
            },
            child: const Text('Восстановить покупку'),
          ),
          const SizedBox(height: 8),
          Text(
            'Оплата спишется после окончания пробного периода. '
            'Отменить можно в любой момент.',
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
