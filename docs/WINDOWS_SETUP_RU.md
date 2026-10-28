# Установка на Windows при заблокированном pub.dev (RU)

Симптом:

```text
Building flutter tool...
Got socket error trying to find package coverage at https://pub.dev.
Error (69): Unable to 'pub upgrade' flutter tool. Retrying in five seconds...
```

Причина — сетевая недоступность `pub.dev` / `storage.googleapis.com`
(DPI провайдера, DNS или TLS-перехват антивируса). К коду проекта отношения
не имеет: падает даже сборка собственного инструмента Flutter.

## 1. Снять зависшие процессы

```powershell
taskkill /F /IM dart.exe 2>$null
taskkill /F /IM flutter.exe 2>$null
```

## 2. Прописать зеркала

На время сессии (PowerShell):

```powershell
$env:PUB_HOSTED_URL="https://pub.flutter-io.cn"
$env:FLUTTER_STORAGE_BASE_URL="https://storage.flutter-io.cn"
```

Постоянно (после setx открыть НОВЫЙ терминал):

```powershell
setx PUB_HOSTED_URL "https://pub.flutter-io.cn"
setx FLUTTER_STORAGE_BASE_URL "https://storage.flutter-io.cn"
```

Проверка:

```powershell
echo $env:PUB_HOSTED_URL
echo $env:FLUTTER_STORAGE_BASE_URL
```

## 3. Сбросить битый кэш инструмента (если сборки прерывались)

Удалить папку `<flutter_sdk>\bin\cache`, затем:

```powershell
flutter doctor
flutter --version   # нужен Flutter >= 3.27
```

## 4. Собрать проект

```powershell
flutter create . --org app.smartnotes --project-name smart_notes --platforms=android,ios
flutter pub get
flutter analyze
flutter test
```

## Запасные варианты

- Браузер не открывает https://pub.dev → VPN на время установки,
  либо DNS 1.1.1.1 / 8.8.8.8 в свойствах сетевого адаптера.
- Браузер открывает, CLI — нет → отключить HTTPS-сканирование в антивирусе
  или добавить pub.dev и pub.dartlang.org в доверенную зону (Kaspersky:
  Privacy → Threats → Trusted Zone → Trusted web addresses).
- Проверить, что в значении переменной нет пробела перед `https://`
  (pub падает с `invalid url: Scheme not starting with alphabetic character`).

## Если есть только SOCKS5-прокси (pub не умеет SOCKS)

Dart/pub поддерживает только HTTP-прокси через `HTTP_PROXY`/`HTTPS_PROXY`.
Схема `socks5://` его HTTP-клиентом не поддерживается — переменная с SOCKS
молча игнорируется, и pub снова идёт напрямую и виснет на
«Resolving dependencies». Нужен локальный мост HTTP → SOCKS5.

### Шаг 0. Проверить, нет ли HTTP-порта у того же клиента

v2rayN/Xray/Clash/Shadowsocks обычно слушают и HTTP/mixed-порт рядом с
SOCKS (v2rayN — часто 10809, Clash mixed — 7890):

```powershell
curl.exe -x http://172.20.7.244:10809 -I https://pub.dev
curl.exe -x http://172.20.7.244:7890 -I https://pub.dev
```

Рабочий порт можно использовать сразу без моста.

### Шаг 1. Мост через gost (один .exe)

```powershell
mkdir C:\tools\gost; cd C:\tools\gost
curl.exe -x socks5h://172.20.7.244:1080 -L -o gost.zip `
  https://github.com/ginuerzh/gost/releases/download/v2.11.5/gost-windows-amd64-2.11.5.zip
Expand-Archive gost.zip -DestinationPath .
# в отдельном окне, не закрывать:
C:\tools\gost\gost.exe -L http://127.0.0.1:8080 -F socks5://172.20.7.244:1080
```

Проверка:

```powershell
curl.exe -x http://127.0.0.1:8080 -I https://pub.dev
```

Альтернатива при наличии Python:

```powershell
pip install pproxy
python -m pproxy -l http://127.0.0.1:8080 -r socks5://172.20.7.244:1080
```

### Шаг 2. Переменные со схемой http:// (схема обязательна)

```powershell
$env:HTTPS_PROXY="http://127.0.0.1:8080"
$env:HTTP_PROXY="http://127.0.0.1:8080"
# зеркала при рабочем прокси не нужны:
Remove-Item Env:PUB_HOSTED_URL -ErrorAction SilentlyContinue
Remove-Item Env:FLUTTER_STORAGE_BASE_URL -ErrorAction SilentlyContinue
flutter doctor
```

Диагностика: `flutter pub get -v`. Коннект напрямую на `pub.dev:443` —
переменные не подхватились; ошибка к `127.0.0.1:8080` — проблема моста.

## Чек-лист после успешного `flutter doctor`

1. Сгенерировать платформенные папки (существующие файлы не перезаписываются,
   поэтому дефолтный widget_test.dart в проект не попадёт):

   ```powershell
   flutter create . --org app.smartnotes --project-name smart_notes --platforms=android,ios
   flutter pub get
   flutter analyze
   flutter test
   ```

2. Прокси для Gradle (он не читает HTTPS_PROXY) — скопировать шаблон:

   ```powershell
   Get-Content docs\gradle.properties.template | Add-Content android\gradle.properties
   ```

   На время скачивания самого Gradle wrapper дополнительно в той же сессии:

   ```powershell
   $env:GRADLE_OPTS="-Dhttp.proxyHost=127.0.0.1 -Dhttp.proxyPort=8080 -Dhttps.proxyHost=127.0.0.1 -Dhttps.proxyPort=8080"
   ```

3. Постоянные переменные, чтобы не задавать их в каждом окне:

   ```powershell
   setx HTTPS_PROXY "http://127.0.0.1:8080"
   setx HTTP_PROXY  "http://127.0.0.1:8080"
   setx NO_PROXY    "localhost,127.0.0.1,::1"
   ```

4. Запуск на эмуляторе или телефоне: `flutter run`.

## Следующий возможный барьер — Gradle

При `flutter run` Android-сборка тянет артефакты с `dl.google.com`
(Google Maven) и `services.gradle.org`. Gradle НЕ читает `HTTPS_PROXY`,
поэтому при прокси в `android/gradle.properties` нужны отдельные строки:

```properties
systemProp.http.proxyHost=127.0.0.1
systemProp.http.proxyPort=8080
systemProp.https.proxyHost=127.0.0.1
systemProp.https.proxyPort=8080
```

Если Google Maven недоступен даже через прокси — в
`android/build.gradle` добавляются Aliyun-зеркала:

```groovy
repositories {
    maven { url 'https://maven.aliyun.com/repository/google' }
    maven { url 'https://maven.aliyun.com/repository/gradle-plugin' }
    maven { url 'https://maven.aliyun.com/repository/public' }
    google()
    mavenCentral()
}
```

Тот же блок — в `pluginManagement.repositories` (`android/settings.gradle`).
