> **Обновление:** начат self-hosted backend FastAPI + PostgreSQL в `backend/`.
> Актуальный запуск и ограничения: `../backend/README.md`.
> Ниже — прежний альтернативный план Firebase, не текущая реализация.

# План подключения Firebase (раздел 3.1 ТЗ)

Приложение спроектировано так, чтобы миграция на Firebase не затрагивала
экраны: все внешние эффекты идут через интерфейсы `SyncService` и
`NotificationService`, а данные — через репозитории.

## 1. Проект Firebase

1. Создать проект в [console.firebase.google.com](https://console.firebase.google.com),
   добавить приложения iOS (`bundle id`) и Android (`applicationId`).
2. `flutter pub add firebase_core firebase_auth cloud_firestore firebase_storage
   firebase_messaging cloud_functions` (или заменить БД на `firebase_database`).
3. Положить `firebase_options.dart` через `flutterfire configure` и
   инициализировать в `main()` до `runApp`.

## 2. Аутентификация (Firebase Auth)

- Email/пароль + Google Sign-In; на iOS — Sign in with Apple (требование App Store).
- В `AppSettings` заменить заглушку профиля на `FirebaseAuth.instance.currentUser`:
  `uid` → `AppNote.authorId`, displayName → `authorName`.
- Гость: поддержать анонимную авторизацию, чтобы офлайн-заметки не терялись
  до регистрации (миграция по uid при первом входе).

## 3. База данных и правила доступа

Рекомендация — Cloud Firestore (клиентская офлайн-очередь уже встроена):

```
users/{uid}/notes/{noteId}        личные заметки
families/{familyId}/notes/{id}   общие семейные заметки
families/{familyId}/members/{uid}
invites/{token}
```

Security Rules: пользователь видит свои заметки и только те семьи,
в которых состоит (раздел 7 ТЗ «Приватность семьи»):

```
match /families/{familyId}/notes/{id} {
  allow read, write: if request.auth.uid in
    get(/databases/$(database)/documents/families/$(familyId)).data.members;
}
```

## 4. Реализация SyncService

Создать `FirebaseSyncService implements SyncService`:

- `add/update/remove` в репозитории после локальной записи вызывает
  upsert в Firestore с полем `updatedAt`; успешная запись снимает `pendingSync`
  (метод `NotesRepository.markSynced` уже готов).
- Снапшоты Firestore разруливают конфликты по правилу «побеждает больший
  `updatedAt`», удаления — через tombstone-флаг.
- Офлайн: Firestore сам кэширует записи; наш JSON остаётся резервной копией
  и источником для холодного старта без сети.
- Провайдер заменяется одной строкой:
  `syncServiceProvider.overrideWithValue(FirebaseSyncService(...))`.

## 5. Push-напоминания (FCM + Functions)

Локальные уведомления остаются для офлайна, серверные — страховка:

1. Планировщик `Cloud Scheduler` → Cloud Function раз в минуту выбирает
   заметки с `reminderAt == now` и шлёт `messaging.sendEachForMulticast`.
2. Токены устройств хранить в `users/{uid}/tokens`.
3. Тихие часы из настроек учитывать в функции (сдвиг на конец окна).
4. `FirebaseNotificationService implements NotificationService` для
   серверного пути; локальный сервис остаётся fallback'ом.

## 6. Файлы (Firebase Storage)

- Путь `families/{familyId}/notes/{noteId}/{uuid}`.
- `AttachmentPicker` уже возвращает локальный путь; добавить загрузчик,
  который после успешного upload заменяет `path` на download URL
  (модель `NoteAttachment` не меняется).
- PDF-превью первой страницы — через `pdf` пакет на клиенте или
  Cloud Function + Vision API (Приоритет 3, OCR).

## 7. Инвайты

- `invites/{token}` хранит `familyId`, автора, срок жизни (7 дней).
- Вход по ссылке: Firebase Dynamic Link / App Link → экран приложения
  диплинком → транзакция добавления в `members`.
- Текущий локальный флоу (диалог «Ввести код») — точная копия будущего
  серверного сценария с точки зрения UI.

## Порядок миграции

1. Auth + миграция uid (1 спринт).
2. Firestore + Rules + `FirebaseSyncService` (1 спринт).
3. Storage для вложений.
4. FCM + Functions-планировщик.
5. Динамические ссылки для инвайтов.
