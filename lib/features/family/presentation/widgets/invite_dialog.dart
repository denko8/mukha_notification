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
    final joined = await showDialog<bool>(
      context: context,
      builder: (_) => const JoinInviteDialog(),
    );
    if (joined == true && mounted) Navigator.pop(context);
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
                      style: TextStyle(color: AppColors.gold),
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

/// Диалог входа в семью по коду/токену приглашения.
/// Используется и вручную, и при открытии deep link (токен предзаполнен).
class JoinInviteDialog extends ConsumerStatefulWidget {
  final String? initialToken;

  const JoinInviteDialog({super.key, this.initialToken});

  @override
  ConsumerState<JoinInviteDialog> createState() => _JoinInviteDialogState();
}

class _JoinInviteDialogState extends ConsumerState<JoinInviteDialog> {
  late final TextEditingController _codeController;
  late final TextEditingController _nameController;
  final _formKey = GlobalKey<FormState>();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _codeController = TextEditingController(text: widget.initialToken ?? '');
    _nameController = TextEditingController();
  }

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref.read(familyNotifierProvider.notifier).acceptInvite(
            _codeController.text.trim(),
            _nameController.text.trim(),
          );
      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Вы вступили в семью')),
        );
      }
    } on StateError catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Принять приглашение'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _codeController,
              decoration: const InputDecoration(hintText: 'Код из ссылки'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Введите код' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(hintText: 'Ваше имя'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Введите имя' : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('Отмена'),
        ),
        ElevatedButton(
          onPressed: _busy ? null : _join,
          child: _busy
              ? const SizedBox(
                  width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Войти в семью'),
        ),
      ],
    );
  }
}

/// Честное объяснение вместо неработающего межустройственного приглашения.
class FamilyAccessInfoDialog extends StatelessWidget {
  const FamilyAccessInfoDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Семейный доступ пока локальный'),
      content: const Text(
        'Заметки в разделе «Семья» сохранены на этом устройстве. '
        'Подключение других участников пока недоступно. '
        'Чтобы передать заметку сейчас, откройте её и выберите «Поделиться».',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Понятно'),
        ),
      ],
    );
  }
}
