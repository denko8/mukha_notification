# Подключение Firebase — готовый комплект

Файлы в этой папке — рабочие реализации интерфейсов проекта
(`SyncService`, `NotificationService`) и загрузчика вложений.
Они не компилируются сейчас (лежат в `docs/`), чтобы не тянуть Firebase
в локальную сборку без твоего проекта. Папка исключена из `flutter analyze`
через `analyzer.exclude` в `analysis_options.yaml`.
После настройки переноси файлы в `lib/` и поправь относительные импорты
(`../features/...` → `../../features/...` для каталога `lib/core/services/`).

## Шаги

1. Создай проект в console.firebase.google.com, приложения Android/iOS,
   `flutterfire configure` → сгенерирует `lib/firebase_options.dart`
   и положит `google-services.json` / `GoogleService-Info.plist`.

2. Зависимости (свежие версии проверь `flutter pub add`):

```yaml
# pubspec.yaml — добавить
  firebase_core: ^4.1.0
  firebase_auth: ^6.1.1
  cloud_firestore: ^6.0.2
  firebase_messaging: ^16.0.2
  firebase_storage: ^13.0.0
```

3. Перенеси файлы:
   - `firebase_sync_service.dart` → `lib/core/services/`
   - `firebase_messaging_service.dart` → `lib/core/services/`
   - `firebase_attachment_storage.dart` → `lib/core/services/`

4. В `main.dart` замени инициализацию (см. `main_snippet.dart`).

5. Firestore-индексы и Security Rules — в `firestore.rules`.

6. Cloud Function планировщика — `functions_reminder.js` (Node 20).
   Деплой: `firebase deploy --only functions`.

После этого локальный JSON остаётся кэшем и резервной копией,
а источником правды становится Firestore.
