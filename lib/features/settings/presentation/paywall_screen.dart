import 'package:flutter/material.dart';

import '../../cloud/presentation/cloud_screen.dart';

/// Billing is not activated until a server-verified payment channel is configured.
class PaywallScreen extends StatelessWidget {
  const PaywallScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Облачная копия и тарифы')),
    body: ListView(padding: const EdgeInsets.all(20), children: [
      Text('Бесплатно на устройстве', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      const Text('Локальные заметки, голосовой ввод и файлы на телефоне остаются '
        'доступны без подписки. Основная лента не загружается в облако автоматически.'),
      const SizedBox(height: 24),
      Text('Облачная копия файлов', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      const Text('Отдельный облачный тариф оплачивает хранение вложений и их передачу '
        'между устройствами. Текущая серверная квота тестового тарифа — 1 ГиБ, '
        'файл до 5 МиБ. Доступ и оставшееся место проверяются сервером.'),
      const SizedBox(height: 16),
      const Text('Продажа и автоматическое продление пока не подключены. '
        'Цена и условия пробного периода будут опубликованы перед включением оплаты. '
        'В тестовой сборке тариф выдаёт администратор сервера. '
        'Нажатие кнопки ниже не оформляет покупку и не списывает деньги.'),
      const SizedBox(height: 20),
      FilledButton.icon(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => const CloudScreen())),
        icon: const Icon(Icons.cloud_outlined), label: const Text('Открыть облачное пространство')),
    ]),
  );
}
