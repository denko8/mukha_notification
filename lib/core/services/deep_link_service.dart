import 'dart:async';

import 'package:app_links/app_links.dart';

/// Слушает входящие ссылки вида https://smartnotes.app/invite/<token>
/// и отдаёт наружу только токены приглашений (P1 семейный доступ).
class DeepLinkService {
  final AppLinks _appLinks = AppLinks();
  final StreamController<String> _inviteTokens = StreamController<String>.broadcast();
  StreamSubscription<Uri>? _sub;

  /// Токены входящих приглашений. UI подписывается и открывает диалог.
  Stream<String> get inviteTokens => _inviteTokens.stream;

  static const _invitePathSegment = 'invite';

  String? _extractToken(Uri? uri) {
    if (uri == null) return null;
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    final i = segments.indexOf(_invitePathSegment);
    if (i == -1 || i + 1 >= segments.length) return null;
    return segments[i + 1];
  }

  Future<void> start() async {
    // Ссылка, которой открыли уже запущенное приложение.
    _sub = _appLinks.uriLinkStream.listen((uri) {
      final token = _extractToken(uri);
      if (token != null) _inviteTokens.add(token);
    }, onError: (_) {});

    // Холодный старт по ссылке.
    try {
      final initial = await _appLinks.getInitialLink();
      final token = _extractToken(initial);
      if (token != null) {
        // Небольшая задержка, чтобы UI успел подняться и подписаться.
        Future.delayed(const Duration(milliseconds: 500), () {
          if (!_inviteTokens.isClosed) _inviteTokens.add(token);
        });
      }
    } catch (_) {
      // Платформа без deep links — не критично.
    }
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    await _inviteTokens.close();
  }
}
