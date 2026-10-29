import 'dart:convert';

import 'package:http/http.dart' as http;

class CloudApiException implements Exception {
  final int status;
  final String message;
  CloudApiException(this.status, this.message);
  @override
  String toString() => message;
}

/// No global token: each API instance belongs to a single origin/session.
class CloudApi {
  final Uri origin;
  final String? token;
  final http.Client client;

  CloudApi(String address, {this.token, http.Client? client})
      : origin = validateOrigin(address), client = client ?? http.Client();

  static Uri validateOrigin(String address) {
    final uri = Uri.parse(address.trim());
    const allowHttp = bool.fromEnvironment('ALLOW_INSECURE_BACKEND');
    if ((!uri.isScheme('https') && !(allowHttp && uri.isScheme('http'))) ||
        uri.host.isEmpty || uri.userInfo.isNotEmpty || uri.hasQuery ||
        uri.hasFragment || (uri.path.isNotEmpty && uri.path != '/')) {
      throw const FormatException('Укажите HTTPS-адрес сервера без пути и параметров.');
    }
    return uri.replace(path: '', fragment: null, query: null);
  }

  Future<dynamic> request(String method, String path,
      {Map<String, dynamic>? body, String? operationId}) async {
    final request = http.Request(method, origin.resolve(path));
    request.headers['Content-Type'] = 'application/json';
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    if (operationId != null) request.headers['Idempotency-Key'] = operationId;
    // Never forward credentials to a redirect destination.
    request.followRedirects = false;
    if (body != null) request.body = jsonEncode(body);
    final response = await http.Response.fromStream(await client.send(request)
        .timeout(const Duration(seconds: 20))).timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = switch (response.statusCode) {
        401 => 'Сессия истекла. Выйдите и войдите снова. Очередь сохранена.',
        403 => 'Недостаточно прав. Приглашения может создавать только владелец семьи.',
        404 => 'Запись не найдена или доступ отозван.',
        409 => path == '/auth/register'
            ? 'Регистрация с этим email недоступна. Попробуйте войти.'
            : 'Конфликт версий. Выберите, какой текст сохранить.',
        410 => 'Снимок устарел. Повторите синхронизацию.',
        429 => 'Достигнут лимит запросов. Подождите и повторите позже.',
        413 => 'Превышен размер снимка или запроса. Нужна проверка сервера.',
        422 => 'Сервер отклонил данные. Проверьте заполненные поля.',
        _ => 'Сервер недоступен (${response.statusCode}). Очередь сохранена.',
      };
      throw CloudApiException(response.statusCode, message);
    }
    return response.body.isEmpty ? null : jsonDecode(utf8.decode(response.bodyBytes));
  }

  void close() => client.close();
}
