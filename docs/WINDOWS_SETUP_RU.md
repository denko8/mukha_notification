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

## Следующий возможный барьер — Gradle

При `flutter run` Android-сборка тянет артефакты с `dl.google.com`
(Google Maven) и `services.gradle.org`. Если они недоступны — в
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
