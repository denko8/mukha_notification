# Подключение YandexGPT и GigaChat

В приложении три готовых реализации `ChatCompletionClient`:
`YandexGptClient`, `GigaChatClient`, `OpenAiCompatibleClient`. Выбор —
в Настройки → ИИ-распознавание, там же кнопка «Проверить подключение».
При любой ошибке модели заметки продолжают создаваться на локальных правилах.

## YandexGPT (рекомендуется первым)

1. Заведи каталог в [Yandex Cloud](https://console.cloud.yandex.ru/) и запиши
   его **Folder ID** (вид в URL каталога: `b1g...`).
2. Создай сервисный аккаунт с ролью `ai.languageModels.user`
   (или `editor` на каталог).
3. Для сервисного аккаунта выпусти **API-ключ**
   (раздел «Ключи» → «Создать API-ключ»). Это статический ключ,
   токен обновлять не нужно.
4. В приложении:
   - Провайдер: **YandexGPT**
   - Api-Key: ключ из шага 3
   - Folder ID: идентификатор каталога
   - Модель: `yandexgpt-lite` (для старта; есть `yandexgpt`, `yandexgpt-pro`)
5. «Проверить подключение» — должно прийти «Подключение работает».

Запрос уходит на
`https://llm.api.cloud.yandex.net/foundationModels/v1/completion`,
заголовок `Authorization: Api-Key <ключ>`, modelUri
`gpt://<folderId>/<модель>/latest`. Можно вписать и полный modelUri целиком —
клиент использует его без изменений.

Биллинг: оплата российскими картами, посимвольная тарификация токенов;
`yandexgpt-lite` — самый дешёвый вариант для подсказок в заметках.

## GigaChat (Сбер)

1. Зарегистрируй проект на [developers.sber.ru](https://developers.sber.ru/),
   получи **ключ авторизации** (client secret) для выбранного пространства:
   - `GIGACHAT_API_PERS` — физическим лицам;
   - `GIGACHAT_API_CORP` / `GIGACHAT_API_B2B` — бизнесу.
2. В приложении:
   - Провайдер: **GigaChat**
   - Ключ авторизации (Basic): ключ из кабинета
   - Scope: соответствующий пространству
   - Модель: `GigaChat` (или `GigaChat-Pro`, если доступна)
3. Клиент сам обменивает ключ на access_token через
   `POST .../api/v2/oauth` (заголовки `Authorization: Basic`, `RqUID: <uuid>`),
   кэширует его на ~30 минут и обновляет заранее.

### Важно про сертификаты Минцифры

Боевые хосты GigaChat (`ngw.devices.sberbank.ru:9443`,
`gigachat.devices.sberbank.ru`) используют TLS-сертификаты Российского
корневого центра. Стандартные Android/iOS им не доверяют, поэтому «из коробки»
возможна ошибка handshake. Варианты:

1. **Прокси-шлюз** (рекомендуется для продуктива): подними лёгкий сервис
   с `russiantrustedca.pem` на стороне сервера, а в приложении укажи его URL
   через OpenAI-совместимый провайдер — клиент остаётся штатным.
2. **Бандл сертификата в приложении**: положи `russiantrustedca.pem`
   в `assets/`, создай `SecurityContext`/`HttpClient` с этим корнем и
   передай кастомный `http.Client` (IOClient) в `GigaChatClient`.
3. Для разработки и тестов можно использовать песочницу, если она доступна
   на момент интеграции.

## OpenAI-совместимый провайдер

Универсальный вариант: любой эндпоинт `/v1/chat/completions` с Bearer-ключом —
OpenAI, прокси, локальная Ollama (`http://<host>:11434/v1`),
совместимые шлюзы Yandex/GigaChat. Поля: Base URL, API-ключ, модель.

## Где это в коде

```
features/ai/
  ai_reminder_parser.dart          контракт
  rule_based_ai_parser.dart        офлайн-фолбэк
  ai_connection_service.dart       кнопка проверки
  llm/
    ai_provider.dart               enum провайдеров
    ai_client_factory.dart         выбор реализации по настройкам
    yandex_gpt_client.dart         нативный Yandex Cloud API
    gigachat_client.dart           OAuth + кэш токена
    openai_compatible_client.dart  универсальный OpenAI-формат
    llm_reminder_parser.dart       JSON-схема, валидация, фолбэк
```

Поток сохранения заметки: `NotesNotifier.addFromText` →
`aiParserProvider` → LLM с автоматическим откатом на правила.
Ручной выбор даты и категории всегда имеет приоритет над ответом модели.
