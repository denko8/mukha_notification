import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import '../data/cloud_files.dart';
import '../data/cloud_background.dart';
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/providers.dart';
import '../data/cloud_alarms.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';

import '../data/cloud_api.dart';
import '../data/cloud_session.dart';
import '../data/cloud_store.dart';
import '../data/cloud_workspace.dart';

/// Deliberately separate from local notes until explicit migration is available.
class CloudScreen extends ConsumerStatefulWidget {
  const CloudScreen({super.key});
  @override
  ConsumerState<CloudScreen> createState() => _CloudScreenState();
}

class _CloudScreenState extends ConsumerState<CloudScreen> with WidgetsBindingObserver {
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
  CloudAlarms? _alarms;
  CloudStore? _store;
  bool _background = false;
  List<Map<String, Object?>> _uploads = [];
  String? _backgroundStatus;
  Timer? _timer;
  bool _auto = false;
  bool _editing = false;
  int _failures = 0;
  DateTime? _lastSync;
  List<Map<String, dynamic>> _families = [];
  String? _familyId;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _timer?.cancel();
    if (state == AppLifecycleState.resumed && _auto) _scheduleAuto(immediate: true);
  }

  void _scheduleAuto({bool immediate = false}) {
    _timer?.cancel();
    if (!mounted || !_auto || _workspace == null) return;
    if (WidgetsBinding.instance.lifecycleState != null &&
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) return;
    final seconds = 30 * (1 << _failures.clamp(0, 4).toInt());
    _timer = Timer(immediate ? Duration.zero : Duration(seconds: seconds), () async {
      if (!mounted || !_auto) return;
      if (!_busy && !_editing) await _run(_sync);
      _scheduleAuto();
    });
  }

  Future<void> _sync() async {
    try {
      await _workspace!.sync();
      await CloudFiles(_store!, _workspace!.api).uploadPending(_workspace!);
      await _workspace!.sync();
      final families = await _workspace!.api.request('GET', '/families') as List;
      _families = families.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (!_families.any((f) => f['id'] == _familyId)) _familyId = null;
      _failures = 0;
      _lastSync = DateTime.now();
    } on CloudApiException catch (error) {
      _failures++;
      if (error.status == 401) { _auto = false; _timer?.cancel(); }
      rethrow;
    } catch (_) { _failures++; rethrow; }
  }


  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    Future<void> reconcile() async {
      if (_workspace == null || _alarms == null || _store == null) return;
      _uploads = await CloudFiles(_store!, _workspace!.api).pending();
      final statuses = await _store!.database.query('cloud_background_status',
        where: 'namespace = ?', whereArgs: [_store!.namespace]);
      _backgroundStatus = statuses.isEmpty ? null : statuses.single['message'] as String;
      try {
        await _alarms!.reconcile(_workspace!.notes);
      } catch (_) {
        throw StateError('Данные сохранены, но обновить локальные напоминания не удалось. '
          'Проверьте разрешения уведомлений и точных будильников Android.');
      }
    }
    try {
      final activeStore = _store;
      if (activeStore != null && _workspace != null) {
        await activeStore.withLease(() async {
          _workspace!.state = await activeStore.read();
          await action();
          await reconcile();
        });
      } else {
        await action();
        final opened = _store;
        if (opened != null && _workspace != null) {
          await opened.withLease(() async {
            _workspace!.state = await opened.read();
            await reconcile();
          });
        }
      }
    } catch (error) {
      if (mounted) setState(() => _message = error is CloudApiException
          ? error.message : error is FormatException ? error.message
          : error is StateError ? error.message.toString()
          : 'Не удалось выполнить действие. Проверьте сеть и адрес сервера. '
            'Подтверждённые локальные данные и очередь сохранены.');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        if (_auto) _scheduleAuto();
      }
    }
  }

  Future<void> _open(CloudSession session) async {
    final store = await CloudStore.open(session.namespace);
    final state = await store.read();
    final background = await CloudSession.backgroundEnabled();
    final api = CloudApi(session.origin, token: session.token);
    if (!mounted) { api.close(); return; }
    _workspace?.api.close();
    setState(() {
      _store = store;
      _background = background;
      _alarms = CloudAlarms(store.database, ref.read(notificationServiceProvider), session.namespace);
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
      await _alarms?.cancel();
      await CloudBackground.disable();
      _background = false;
      await CloudSession.forget();
      _timer?.cancel();
      _auto = false;
      _families = [];
      _familyId = null;
      _workspace!.api.close();
      if (mounted) setState(() { _session = null; _workspace = null; _store = null; _alarms = null; _uploads = []; _draft = ''; });
    });
  }

  Future<String?> _textDialog(String initial, {String? title, int maxLength = 20000}) async {
    _editing = true;
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: Text(title ?? (initial.isEmpty ? 'Облачная заметка' : 'Изменить текст')),
      content: TextField(controller: controller, autofocus: true, minLines: 3,
        maxLines: 8, maxLength: maxLength,
        decoration: const InputDecoration(hintText: 'Текст заметки')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
        FilledButton(onPressed: () {
          if (controller.text.trim().isNotEmpty) Navigator.pop(ctx, controller.text.trim());
        }, child: const Text('Сохранить на телефоне')),
      ],
    ));
    _editing = false;
    // Dialog's reverse transition can still reference its controller.
    Future<void>.delayed(const Duration(seconds: 1), controller.dispose);
    return result;
  }

  Future<void> _create() async {
    final text = await _textDialog(_draft);
    if (text != null && mounted) {
      _draft = text;
      await _run(() async {
        await _workspace!.create(text, familyId: _familyId);
        _draft = '';
      });
    }
  }

  Future<void> _edit(String id, String text) async {
    final version = _workspace!.notes[id]['note']['version'];
    final result = await _textDialog(text);
    if (result != null && mounted) await _run(() async {
      if (_workspace!.notes[id]?['note']['version'] != version) {
        _draft = result;
        throw StateError('Заметка изменилась в фоне. Ваш текст оставлен в черновике новой заметки.');
      }
      await _workspace!.edit(id, result);
    });
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
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
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
          'не переносятся. Семейные заметки можно изменять. '
          'Напоминания локальные. Вложения: PDF и изображения до 5 МиБ. '),
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
          FilledButton.icon(onPressed: _busy ? null : () => _run(_sync),
            icon: const Icon(Icons.sync), label: const Text('Синхронизировать')),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Автосинхронизация'),
            subtitle: const Text('Пока открыт этот раздел, каждые 30 секунд. '
              'При ошибках — реже. Закрытое приложение Android пока не синхронизируется.'),
            value: _auto,
            onChanged: _busy ? null : (v) {
              setState(() => _auto = v);
              if (v) { _scheduleAuto(immediate: true); } else { _timer?.cancel(); }
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Фоновый обмен Android'),
            subtitle: const Text('WorkManager, от 15 минут при наличии сети. '
              'Android может откладывать запуск; Force stop блокирует работу до открытия приложения.'),
            value: _background,
            onChanged: _busy ? null : (enabled) => _run(() async {
              if (enabled) { await CloudBackground.enable(); }
              else { await CloudBackground.disable(); }
              _background = enabled;
            }),
          ),
          if (_backgroundStatus != null) Text('Последний фоновый запуск: $_backgroundStatus'),
          if (_lastSync != null) Text('Последний обмен: ${_lastSync!.toLocal()}'),
          Wrap(spacing: 8, children: [
            TextButton(onPressed: _busy ? null : () => _familyAction('create'), child: const Text('Создать семью')),
            TextButton(onPressed: _busy ? null : () => _familyAction('join'), child: const Text('Вступить по коду')),
          ]),
          DropdownButtonFormField<String>(
            value: _familyId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Куда сохранять новые заметки'),
            items: [const DropdownMenuItem<String>(value: null, child: Text('Личные')),
              for (final f in _families) DropdownMenuItem(value: f['id'] as String, child: Text(f['name'] as String))],
            onChanged: _busy ? null : (value) => setState(() => _familyId = value),
          ),
          if (_familyId != null) TextButton.icon(
            onPressed: _busy ? null : () => _familyAction('invite'),
            icon: const Icon(Icons.person_add_outlined), child: const Text('Создать приглашение (владелец)')),
          OutlinedButton.icon(onPressed: _busy ? null : _create,
            icon: const Icon(Icons.add), label: Text(_draft.isEmpty ? 'Новая облачная заметка' : 'Продолжить черновик')),
          const Text('Без сети изменения сохраняются в очереди на телефоне. '
            'Для отправки нажмите «Синхронизировать» или включите автообмен. Первый вход требует интернет.'),
          if (workspace.notes.isEmpty) const Padding(padding: EdgeInsets.all(24),
            child: Text('Кэш пока пуст. Загрузите заметки с сервера или создайте первую.')),
          for (final upload in _uploads) ListTile(
            leading: const Icon(Icons.upload_file),
            title: Text(upload['name'] as String),
            subtitle: const Text('В очереди загрузки'),
            trailing: IconButton(tooltip: 'Убрать вложение из очереди', icon: const Icon(Icons.close),
              onPressed: _busy ? null : () => _run(() =>
                CloudFiles(_store!, workspace.api).discard(upload['id'] as String))),
          ),
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
    final isFamily = note['family_id'] != null;
    final blocked = entry['blocked'] != null;
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (isFamily) const Text('Семейная'),
        if (note['reminder_at'] != null) Text('Напоминание: ${DateTime.parse(note['reminder_at'] as String).toLocal()}'),
        if (blocked) Text(entry['blocked'] as String),
        if (blocked) TextButton(onPressed: _busy ? null : () => _editAsNew(note['text'] as String),
          child: const Text('Скопировать в новую личную заметку')),
        Text(note['text'] as String? ?? 'Удалено на сервере'),
        Text(blocked ? 'Локальный черновик · не отправляется' : remote != null ? 'Конфликт — требуется ваш выбор'
          : pending ? (deleted ? 'Удаление в очереди' : 'Ожидает отправки') : 'Подтверждено сервером'),
        for (final attachment in (note['attachments'] as List? ?? []))
          TextButton.icon(icon: const Icon(Icons.attach_file),
            label: Text('${attachment['name']} · ${attachment['size']} байт'),
            onPressed: _busy ? null : () => _run(() async {
              final file = await CloudFiles(_store!, _workspace!.api).download(id, attachment as Map);
              final result = await OpenFilex.open(file.path);
              if (result.type != ResultType.done) throw StateError('Не удалось открыть файл: ${result.message}');
            })),
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
        if (!pending && !deleted && !blocked) Wrap(children: [
          TextButton(onPressed: _busy ? null : () => _edit(id, note['text'] as String), child: const Text('Изменить')),
          TextButton(onPressed: _busy ? null : () => _attach(id), child: const Text('Прикрепить файл')),
          TextButton(onPressed: _busy ? null : () => _reminder(id), child: const Text('Напоминание')),
          if (note['reminder_at'] != null) TextButton(onPressed: _busy ? null :
            () => _run(() => _workspace!.setReminder(id, null)), child: const Text('Убрать напоминание')),
          TextButton(onPressed: _busy ? null : () => _delete(id, note['text'] as String), child: const Text('Удалить')),
        ]),
      ],
    )));
  }

  Future<void> _reminder(String id) async {
    final version = _workspace!.notes[id]['note']['version'];
    _editing = true;
    try {
    final now = DateTime.now();
    final date = await showDatePicker(context: context, initialDate: now,
      firstDate: now, lastDate: now.add(const Duration(days: 3650)));
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (time == null || !mounted) return;
    final when = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    if (!when.isAfter(DateTime.now())) {
      setState(() => _message = 'Выберите время в будущем.');
      return;
    }
    await _run(() async {
      if (_workspace!.notes[id]?['note']['version'] != version) {
        throw StateError('Заметка обновилась в фоне. Выберите напоминание заново.');
      }
      await _workspace!.setReminder(id, when);
    });
    } finally { _editing = false; }
  }

  Future<void> _familyAction(String kind) async {
    String? value;
    if (kind != 'invite') {
      value = await _textDialog(kind == 'join' ? '' : 'Моя семья',
        title: kind == 'join' ? 'Код приглашения' : 'Название семьи',
        maxLength: kind == 'join' ? 100 : 80);
      if (value == null || !mounted) return;
    }
    await _run(() async {
      final api = _workspace!.api;
      if (kind == 'invite') {
        final invite = await api.request('POST', '/families/$_familyId/invites');
        if (!mounted) return;
        await showDialog<void>(context: context, builder: (ctx) => AlertDialog(
          title: const Text('Одноразовое приглашение'),
          content: SelectableText('Код: ${invite['token']}\nДействует до ${invite['expires_at']}'),
          actions: [
            TextButton(onPressed: () async {
              await Clipboard.setData(ClipboardData(text: invite['token'] as String));
              if (ctx.mounted) Navigator.pop(ctx);
            }, child: const Text('Скопировать код')),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Закрыть')),
          ],
        ));
      } else {
        await api.request('POST', kind == 'join' ? '/families/join' : '/families',
          body: kind == 'join' ? {'token': value!.trim()} : {'name': value!.trim()});
      }
      await _sync();
    });
  }

  Future<void> _attach(String id) async {
    _editing = true;
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'webp']);
      if (result == null || !mounted) return;
      final item = result.files.single;
      if (item.path == null) {
        setState(() => _message = 'Файл недоступен. Выберите другой файл.');
        return;
      }
      await _run(() async {
        final entry = _workspace!.notes[id] as Map?;
        if (entry == null || entry['blocked'] != null || entry['operation'] != null ||
            entry['note']['deleted'] == true) {
          throw StateError('Сначала синхронизируйте заметку.');
        }
        await CloudFiles(_store!, _workspace!.api).enqueue(id, File(item.path!), item.name);
      });
    } catch (error) {
      if (mounted) setState(() => _message = 'Не удалось выбрать вложение. Попробуйте другой файл.');
    } finally { _editing = false; }
  }

  Future<void> _editAsNew(String text) async {
    final result = await _textDialog(text);
    if (result != null && mounted) await _run(() => _workspace!.create(result));
  }
}
