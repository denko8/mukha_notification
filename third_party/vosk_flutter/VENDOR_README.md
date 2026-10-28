# Vendored copy: vosk_flutter

Это пропатченная копия плагина
[`vosk_flutter`](https://github.com/alphacep/vosk-flutter),
коммит `e655a96f0ce0dadb5ea8900aa1ba23260c3ec904` (ветка master,
2024-10-26). Подключена как path-зависимость из `pubspec.yaml`.

## Зачем копия в репозитории

Опубликованный на pub.dev релиз `vosk_flutter 0.3.48` не собирается на
современном стеке (Flutter 3.29+ / AGP 8.6+ / Gradle 9):

1. жёстко тянет `permission_handler ^10.2.0` и `http ^0.13.5` —
   `permission_handler_android 10.x` использует удалённый v1 embedding
   (`PluginRegistry.Registrar`), ошибка `cannot find symbol Registrar`;
2. не задаёт `namespace` в Gradle — ошибка `Namespace not specified`
   на AGP 8+;
3. манифест содержит устаревший атрибут `package="org.vosk.vosk_flutter"`,
   который при заданном namespace является фатальной ошибкой
   `ProcessLibraryManifest` на AGP 8.6+ (issue #33 апстрима).

В master апстрима пункты 1–2 уже исправлены, но релиз на pub.dev не
выложен, а пункт 3 не исправлен до сих пор.

## Наша правка

Единственное отличие от upstream-коммита `e655a96`:

- `android/src/main/AndroidManifest.xml` — удалён атрибут
  `package="org.vosk.vosk_flutter"` (namespace уже задан в
  `android/build.gradle`, атрибут в манифесте больше не нужен и ломает
  сборку на AGP 8.6+).

## Обновление копии

1. Сверить новую версию апстрима, перенести изменённые файлы в этот
   каталог (кроме `example/` — он содержит модели на ~40 МБ).
2. Повторно применить правку манифеста.
3. Проверить `pubspec.yaml` плагина на совместимость версий
   `permission_handler`/`http` с корневым `pubspec.yaml`.

Лицензия Apache-2.0 — см. `LICENSE` в этом каталоге.
