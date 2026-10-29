import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';

import '../data/cloud_api.dart';
import '../data/cloud_session.dart';
import '../data/cloud_store.dart';
import '../data/cloud_workspace.dart';

/// Deliberately separate from local notes until explicit migration is available.
class CloudScreen extends StatefulWidget {
  const CloudScreen({super.key});
  @override
  State<CloudScreen> createState() => _CloudScreenState();
}

class _CloudScreenState extends State<CloudScreen> {
  final _address = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  CloudSession? _session;
  CloudWorkspace? _workspace;
  bool _busy = false;
  bool _register = false;
  String? _message;
  String _draft = '';

  @override
  void initState() {
    super.initState();
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      _run(() async {
        final session = await CloudSession.restore();
        if (session != null) await _open(session);
      });
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() { _busy = true; _message = null; });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _message = error is CloudApiException
          ? error.message : error is FormatException ? error.message
          : 'Не удалось выполнить действие. Проверьте сеть и адрес сервера. '
            'Подтверждённые локальные данные и очередь сохранены.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(CloudSession session) async {
    final store = await CloudStore.open(session.namespace);
    final state = await store.read();
    final api = CloudApi(session.origin, token: session.token);
    if (!mounted) { api.close(); return; }
    _workspace?.api.close();
    setState(() {
      _session = session;
      _workspace = CloudWorkspace(api, state, store.write);
    });
  }

  Future<void> _login() async {
    if (_password.text.length < 12 || _email.text.trim().isEmpty ||
        (_register && _name.text.trim().isEmpty)) {
      setState(() => _message = 'Укажите email и пароль от 12 символов. Для регистрации нужно имя.');
      return;
    }
    await _run(() async {
      final session = await CloudSession.signIn(_address.text, _email.text,
        _password.text, name: _register ? _name.text : null);
      _password.clear();
      await _open(session);
    });
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Выйти из облака?'),
      content: const Text('Кэш и неотправленные заметки останутся на этом телефоне '
        'для этого аккаунта. Если сети нет, серверная сессия останется действительной до истечения срока.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Остаться')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Выйти')),
      ],
    ));
    if (confirmed != true || !mounted) return;
    await _run(() async {
      try { await _workspace!.api.request('POST', '/auth/logout'); } catch (_) {}
      await CloudSession.forget();
      _workspace!.api.close();
      if (mounted) setState(() { _session = null; _workspace = null; _draft = ''; });
    });
  }

  Future<String?> _textDialog(String initial) async {
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: Text(initial.isEmpty ? 'Облачная заметка' : 'Изменить текст'),
      content: TextField(controller: controller, autofocus: true, minLines: 3,
        maxLines: 8, maxLength: 20000,
        decoration: const InputDecoration(hintText: 'Текст заметки')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
        FilledButton(onPressed: () {
          if (controller.text.trim().isNotEmpty) Navigator.pop(ctx, controller.text.trim());
        }, child: const Text('Сохранить на телефоне')),
      ],
    ));
    // Dialog's reverse transition can still reference its controller.
    Future<void>.delayed(const Duration(seconds: 1), controller.dispose);
    return result;
  }

  Future<void> _create() async {
    final text = await _textDialog(_draft);
    if (text != null && mounted) {
      _draft = text;
      await _run(() async {
        await _workspace!.create(text);
        _draft = '';
      });
    }
  }

  Future<void> _edit(String id, String text) async {
    final result = await _textDialog(text);
    if (result != null && mounted) await _run(() => _workspace!.edit(id, result));
  }

  Future<void> _delete(String id, String text) async {
    final yes = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Удалить облачную заметку?'),
      content: const Text('Удаление будет отправлено на сервер при следующей синхронизации.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Удалить')),
      ],
    ));
    if (yes == true && mounted) await _run(() => _workspace!.edit(id, text, delete: true));
  }

  @override
  void dispose() {
    _address.dispose(); _email.dispose(); _password.dispose(); _name.dispose();
    _workspace?.api.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return Scaffold(appBar: AppBar(title: const Text('Облако')), body: const Padding(
        padding: EdgeInsets.all(24), child: Text('Облачный клиент пока доступен только на Android. '
          'Браузер остаётся превью интерфейса. Локальные заметки работают как раньше.')));
    }
    final workspace = _workspace;
    return Scaffold(
      appBar: AppBar(title: const Text('Облако · тестовый режим'), actions: [
        if (_session != null) IconButton(tooltip: 'Выйти из аккаунта',
          onPressed: _busy ? null : _logout, icon: const Icon(Icons.logout)),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Отдельное облачное пространство. Заметки из основной ленты сюда '
          'не переносятся. Пока поддерживается текст; семейные записи — только просмотр. '
          'Напоминания и вложения в этом разделе пока не подключены.'),
        const SizedBox(height: 16),
        if (_busy) const LinearProgressIndicator(),
        if (_message != null) Padding(padding: const EdgeInsets.symmetric(vertical: 12),
          child: Semantics(liveRegion: true, child: Text(_message!))),
        if (workspace == null) ...[
          TextField(controller: _address, enabled: !_busy, autocorrect: false,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(labelText: 'Адрес вашего сервера', hintText: 'https://api.example.ru')),
          TextField(controller: _email, enabled: !_busy, autocorrect: false,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email')),
          if (_register) TextField(controller: _name, enabled: !_busy,
            decoration: const InputDecoration(labelText: 'Имя')),
          TextField(controller: _password, enabled: !_busy, obscureText: true,
            enableSuggestions: false, autocorrect: false,
            decoration: const InputDecoration(labelText: 'Пароль — от 12 символов')),
          const SizedBox(height: 16),
          FilledButton(onPressed: _busy ? null : _login,
            child: Text(_register ? 'Создать аккаунт' : 'Войти')),
          TextButton(onPressed: _busy ? null : () => setState(() => _register = !_register),
            child: Text(_register ? 'Уже есть аккаунт' : 'Зарегистрироваться')),
        ] else ...[
          Text('${_session!.name}\n${_session!.origin}'),
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: _busy ? null : () => _run(workspace.sync),
            icon: const Icon(Icons.sync), label: const Text('Синхронизировать')),
          OutlinedButton.icon(onPressed: _busy ? null : _create,
            icon: const Icon(Icons.add), label: Text(_draft.isEmpty ? 'Новая облачная заметка' : 'Продолжить черновик')),
          const Text('Без сети изменения сохраняются в очереди на телефоне. '
            'Для отправки нажмите «Синхронизировать». Вход впервые требует интернет.'),
          if (workspace.notes.isEmpty) const Padding(padding: EdgeInsets.all(24),
            child: Text('Кэш пока пуст. Загрузите заметки с сервера или создайте первую.')),
          for (final id in workspace.notes.keys)
            if (workspace.notes[id]['note']['deleted'] != true ||
                workspace.notes[id]['operation'] != null)
              _note(id, workspace.notes[id] as Map),
        ],
      ]),
    );
  }

  Widget _note(String id, Map entry) {
    final note = entry['note'] as Map;
    final pending = entry['operation'] != null;
    final remote = entry['conflict'] as Map?;
    final deleted = note['deleted'] == true;
    final readOnly = note['family_id'] != null;
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (readOnly) const Text('Семейная · только просмотр'),
        Text(note['text'] as String? ?? 'Удалено на сервере'),
        Text(remote != null ? 'Конфликт — требуется ваш выбор'
          : pending ? (deleted ? 'Удаление в очереди' : 'Ожидает отправки') : 'Подтверждено сервером'),
        if (remote != null) ...[
          const Divider(),
          Text('На сервере: ${remote['deleted'] == true ? 'удалено' : remote['text']}'),
          Wrap(spacing: 8, children: [
            TextButton(onPressed: _busy ? null : () => _run(() => _workspace!.resolve(id, keepLocal: false)),
              child: const Text('Принять серверную версию')),
            if (remote['deleted'] != true) TextButton(
              onPressed: _busy ? null : () => _run(() => _workspace!.resolve(id, keepLocal: true)),
              child: const Text('Отправить мой вариант')),
            if (remote['deleted'] == true) TextButton(
              onPressed: _busy ? null : () => _editAsNew(note['text'] as String? ?? ''),
              child: const Text('Сохранить текст новой заметкой')),
          ]),
        ],
        if (!pending && !deleted && !readOnly) Wrap(children: [
          TextButton(onPressed: _busy ? null : () => _edit(id, note['text'] as String), child: const Text('Изменить')),
          TextButton(onPressed: _busy ? null : () => _delete(id, note['text'] as String), child: const Text('Удалить')),
        ]),
      ],
    )));
  }

  Future<void> _editAsNew(String text) async {
    final result = await _textDialog(text);
    if (result != null && mounted) await _run(() => _workspace!.create(result));
  }
}
