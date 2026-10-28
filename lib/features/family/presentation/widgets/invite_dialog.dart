import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../../app/providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../models/family_member.dart';

/// Диалог приглашения: уникальная ссылка + QR-код (раздел 2.2 ТЗ).
class InviteDialog extends ConsumerStatefulWidget {
  const InviteDialog({super.key});

  @override
  ConsumerState<InviteDialog> createState() => _InviteDialogState();
}

class _InviteDialogState extends ConsumerState<InviteDialog> {
  FamilyInvite? _invite;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final invite = await ref.read(familyNotifierProvider.notifier).createInvite();
      if (mounted) setState(() => _invite = invite);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _acceptByCode() async {
    final codeController = TextEditingController();
    final nameController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Принять приглашение'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: codeController,
                decoration: const InputDecoration(hintText: 'Код из ссылки'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Введите код' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: nameController,
                decoration: const InputDecoration(hintText: 'Ваше имя'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Введите имя' : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) Navigator.pop(ctx, true);
            },
            child: const Text('Войти в семью'),
          ),
        ],
      ),
    );

    if (ok == true) {
      try {
        await ref.read(familyNotifierProvider.notifier).acceptInvite(
              codeController.text.trim(),
              nameController.text.trim(),
            );
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Новый участник добавлен в семью')),
          );
        }
      } on StateError catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Пригласить в семью'),
      content: _error != null
          ? Text(_error!)
          : _invite == null
              ? const SizedBox(
                  height: 80,
                  child: Center(child: CircularProgressIndicator()),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    QrImageView(
                      data: _invite!.link,
                      version: QrVersions.auto,
                      size: 180,
                      backgroundColor: Colors.white,
                    ),
                    const SizedBox(height: 12),
                    SelectableText(
                      _invite!.link,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.gold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Отправьте ссылку в Telegram, WhatsApp или SMS. '
                      'Код: ${_invite!.token}',
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
      actions: [
        if (_invite != null) ...[
          TextButton.icon(
            icon: const Icon(Icons.login),
            label: const Text('Ввести код'),
            onPressed: _acceptByCode,
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('Скопировать'),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: _invite!.link));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Ссылка скопирована')),
                );
              }
            },
          ),
        ],
      ],
    );
  }
}
