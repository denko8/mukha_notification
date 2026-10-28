# Smart Notes — MVP v1.0

«Умная напоминалка, которая делает всё за тебя».
Flutter-приложение (iOS + Android) в стиле Japandi: теплый минимализм, золотистый акцент.

Реализация соответствует ТЗ `Smart Notes MVP v1.0`. Текущая версия — **фундамент
релизного MVP (Приоритет 1)**, полностью работающая локально и офлайн, с точками
расширения для Firebase без переписывания UI.

## Что уже работает

| Область | Реализовано |
|---|---|
| Home | блок «Сегодня» (15% экрана, свайп вверх/вниз разворачивает календарь), срочные дела, строка ввода «О чем напомнить?», live-подсветка дат золотым, лента карточек, свайп влево — удаление, нижняя навигация Home/Family/Settings |
| Парсер дат | «завтра в 14:00», «в пятницу», «через 3 часа», «10 декабря», «послезавтра», «в полдень», «в 7 вечера», «10.12.2025», составные длительности; дефолтное время 09:00 |
| Напоминания | локальные push через `flutter_local_notifications`, перепланирование после перезапуска, отмена при удалении/выключении |
| Заметки | создание, редактирование, вычеркивание, удаление с подтверждением, детальный экран, история изменений |
| Вложения | фото (камера/галерея), PDF, аудио — выбор и отображение; экспорт заметки в PDF; шеринг текста |
| Family | аватары-инициалы, фильтр по автору, инвайт-ссылка + QR-код, вход по коду, общая лента с тумблером «Семейная» |
| Settings | профиль, вкл/выкл уведомлений, тихие часы, светлая/тёмная/авто тема, 3 размера шрифта, статус синхронизации, экран PRO (5 дней) |
| Голос | реальный голосовой ввод (`speech_to_text`, ru_RU), текст попадает в строку ввода |
| ИИ | локальная классификация 7 категорий, фильтр на Home, ручная смена категории; облачный LLM-парсер свободных формулировок — нативные клиенты YandexGPT и GigaChat плюс любой OpenAI-совместимый API, кнопка проверки подключения, фолбэк на правила (см. `docs/AI_INTEGRATION.md`, `docs/AI_PROVIDERS_YANDEX_GIGACHAT.md`) |
| OCR | распознавание текста с фото (ML Kit, кириллица), результат добавляется в заметку |
| Аудио | плеер вложений с перемоткой (`audioplayers`) |
| Календарь | добавление события в Google Calendar в один тап |
| Шаблоны | 6 готовых шаблонов в меню «Опции» |
| Покупки | реальный флоу `in_app_purchase` (web — симуляция), восстановление покупки |
| Deep links | приём ссылок `/invite/<token>` через `app_links` |
| Офлайн | все данные в локальном JSON-хранилище, пометка `pendingSync`, 100% функций без сети |
| Дизайн | палитра и типографика точно по разделу 5 ТЗ, скругления 12/8, тени 0.1, анимации 300ms ease-in-out |

## Запуск

Платформенные папки (`android/`, `ios/`) намеренно не закоммичены — они
генерируются одной командой, не затрагивая `lib/`:

```bash
flutter --version            # нужен Flutter >= 3.27 (Dart >= 3.6)
flutter create . \
  --org app.smartnotes \
  --project-name smart_notes \
  --platforms=android,ios
flutter pub get
flutter run
```

Тесты (парсер дат + репозиторий, плагины не нужны):

```bash
flutter test
```

> Если `flutter` не может достучаться до pub.dev (`Got socket error`,
> `Unable to 'pub upgrade' flutter tool`) — пошаговое лечение для Windows/RU:
> [docs/WINDOWS_SETUP_RU.md](docs/WINDOWS_SETUP_RU.md).

### Разрешения, которые нужно добавить в платформенные проекты

**Android** (`android/app/src/main/AndroidManifest.xml`):
```xml
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>
<uses-permission android:name="android.permission.USE_EXACT_ALARM"/>
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
```

**iOS** (`ios/Runner/Info.plist`): `NSMicrophoneUsageDescription`,
`NSPhotoLibraryUsageDescription`, `NSCameraUsageDescription` с описанием на русском.

## Структура

```
lib/
  app/                     # MaterialApp, Riverpod-провайдеры
  core/
    theme/                 # Палитра Japandi, светлая/тёмная тема Material 3
    utils/                 # NL-парсер дат, подсветка, форматтеры
    services/              # Уведомления, JSON-store, интерфейс синхронизации
  features/
    notes/                 # Модели, репозиторий, экраны Home/Detail/Edit, виджеты
    family/                # Члены семьи, инвайты, экран Family
    settings/              # Настройки, paywall
    shell/                 # Bottom Navigation
test/                      # Юнит-тесты парсера и репозитория
docs/
  ARCHITECTURE.md          # Слои, потоки данных, правила offline-first
  BACKEND_SETUP.md         # Пошаговый план подключения Firebase
  ROADMAP.md               # Соответствие приоритетам ТЗ и план v1.1/v1.2
```

## Web-превью (Chrome)

`flutter run -d chrome` работает для просмотра UI: на web автоматически
подключаются `InMemoryJsonStore` (данные живут в памяти вкладки) и
`NoopNotificationService` (нативные уведомления на web недоступны).
Файловые вложения и системный просмотр PDF в браузере ограничены —
полный функционал только на Android/iOS.

## Почему нет Isar/Realm и Firebase прямо сейчас

- Хранилище сознательно реализовано на JSON-файлах **без кодогенерации**:
  проект запускается сразу, без `build_runner`, а интерфейс репозитория
  совместим с Isar — замена не затронет ни один экран.
- Firebase спрятан за интерфейсами `NotificationService` и `SyncService`.
  Локальные реализации полностью функциональны; боевые (`FCM`, Realtime Database,
  Storage) подключаются через подмену провайдеров. См. [docs/BACKEND_SETUP.md](docs/BACKEND_SETUP.md).
