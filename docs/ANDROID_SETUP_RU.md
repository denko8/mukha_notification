# Запуск на Android через Android Studio (Windows)

В репозитории намеренно нет папок `android/`, `ios/`, `web/` — они
генерируются локально командой `flutter create .` (см. `.gitignore`).
Для Chrome генерация уже выполнена, для Android нужно добавить платформу.

## 1. Однократная настройка Android Studio

1. Установить Android Studio, при первом запуске пройти Setup Wizard —
   он поставит Android SDK, Platform-Tools, эмулятор.
2. **File → Settings → Plugins → Marketplace** — установить плагин
   **Flutter** (Dart подтянется автоматически), перезапустить IDE.
3. **File → Settings → Languages & Frameworks → Flutter** — указать путь
   к SDK, например `D:\_NeiroRazrabotka\flutter`.
4. В терминале (PowerShell) принять лицензии SDK:

   ```powershell
   flutter doctor --android-licenses
   ```

   На все вопросы — `y`. Затем проверить стенд:

   ```powershell
   flutter doctor
   ```

   Должны быть зелёными Flutter, Android toolchain, Chrome.

## 2. Открыть проект и сгенерировать Android-обвязку

1. **File → Open** → выбрать папку проекта (ту, где лежит `pubspec.yaml`,
   например `D:\_NeiroRazrabotka\SmartNotes`), **не** родительскую.
2. Дождаться индексации и автоматического `pub get` (или выполнить вручную).
3. В терминале IDE в корне проекта:

   ```powershell
   flutter create --org com.smartnotes .
   flutter pub get
   ```

   Команда добавит недостающие папки `android/`, `ios/` и т.д., не трогая
   `lib/`, `test/` и `pubspec.yaml`. `--org` задаёт applicationId
   (`com.smartnotes.smart_notes`) — потом его можно поменять.

## 3. Правки под плагины проекта (один раз)

### 3.1. AndroidManifest.xml

Файл: `android/app/src/main/AndroidManifest.xml`. Добавить разрешения
**над** тегом `<application>`:

```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>
<uses-permission android:name="android.permission.USE_EXACT_ALARM"/>
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
<uses-permission android:name="android.permission.VIBRATE"/>
<uses-permission android:name="android.permission.RECORD_AUDIO"/>

<queries>
    <!-- нужен плагину speech_to_text для голосового ввода -->
    <intent>
        <action android:name="android.speech.RecognitionService" />
    </intent>
</queries>
```

Зачем что: `POST_NOTIFICATIONS` — напоминания на Android 13+;
`RECORD_AUDIO` — голосовой ввод; `INTERNET` — облачные ИИ-запросы
(в debug-режиме добавляется автоматически, для release нужен явно);
`RECEIVE_BOOT_COMPLETED` — восстановление напоминаний после перезагрузки.

### 3.2. Core library desugaring (обязательно для flutter_local_notifications 17)

Файл `android/app/build.gradle` (Groovy, Flutter 3.27). В блок `android { }`:

```gradle
android {
    compileOptions {
        coreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }
    kotlinOptions {
        jvmTarget = '1.8'
    }
}

dependencies {
    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'
}
```

Если сгенерировался Kotlin DSL (`build.gradle.kts`), синтаксис такой:

```kotlin
android {
    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }
    kotlinOptions {
        jvmTarget = "1.8"
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
```

`minSdk` по умолчанию (21) всем плагинам проекта достаточен; если какой-то
плагин потребует выше — поднять `minSdk` в том же файле до 23.

## 4. Запуск

### Вариант А — реальный телефон (рекомендуется: голос, OCR, покупки)

1. На телефоне: **Настройки → О телефоне → 7 тапов по «Номер сборки»**
   → включить **Параметры разработчика → Отладка по USB**.
2. Подключить кабелем, на телефоне разрешить отладку (RSA-запрос).
3. Убедиться, что устройство видно: `flutter devices`.
4. Выбрать телефон в выпадающем списке устройств на верхней панели
   Android Studio и нажать **Run** (Shift+F10).

### Вариант Б — эмулятор

1. Иконка **Device Manager** справа → **Create Virtual Device** →
   Pixel 7 → системный образ API 34/35 → Finish.
2. Запустить эмулятор кнопкой ▶, дождаться загрузки Android.
3. Выбрать его в списке устройств и нажать **Run**.

## 5. Полезное

- Первая сборка идёт 5–15 минут: Gradle качает дистрибутив и зависимости —
  это нормально, последующие запуски быстрые.
- Молния на панели инструментов — **hot reload** (правки UI без перезапуска),
  круговая стрелка — **hot restart** (полный перезапуск состояния).
- Если сборка падает на сетевых ошибках загрузки Gradle/pub —
  см. `WINDOWS_SETUP_RU.md` (зеркала для RU).
- Логи приложения — вкладка **Logcat** внизу Android Studio.
- Проверить, что все плагины собрались без конфликтов:

  ```powershell
  flutter analyze
  flutter test
  ```

## 6. Ошибка «sdkmanager did not install NDK 28.2.13676358»

Свежий шаблон Flutter прописывает в `android/app/build.gradle.kts`
строку `ndkVersion = flutter.ndkVersion`, и Gradle пытается сам скачать
NDK r28b. В РФ автодокачка с Google-серверов часто обрывается, тогда
сборка падает на конфигурации проекта. Два пути решения.

### Путь А — установить NDK через Android Studio (надёжнее)

1. **File → Settings → Languages & Frameworks → Android SDK**.
2. Вкладка **SDK Tools**, включить галочку **Show Package Details**
   внизу окна.
3. В дереве раскрыть **NDK (Side by side)** → отметить версию
   **28.2.13676358** (заодно можно отметить последнюю CMake).
4. **Apply → OK**, дождаться загрузки, затем:

   ```powershell
   flutter clean
   flutter run
   ```

Если загрузка в Studio тоже обрывается — включить VPN/прокси на время
установки либо повторить позднее: это разовая операция, дальше NDK
живёт локально в `%LOCALAPPDATA%\Android\sdk\ndk\`.

### Путь Б — убрать требование NDK (быстрый, нашему проекту он не нужен)

Ни один плагин Smart Notes не содержит собственного C/C++-кода
(`speech_to_text`, ML Kit, уведомления и остальные поставляются
готовыми AAR), поэтому NDK для сборки не требуется.

1. Открыть `android/app/build.gradle.kts`, внутри блока `android { }`
   удалить строку:

   ```kotlin
   ndkVersion = flutter.ndkVersion
   ```

2. Если рядом есть ссылка на NDK в `android/build.gradle.kts` — её не
   трогать, там только версии плагинов.
3. Перезапустить сборку:

   ```powershell
   flutter clean
   flutter run
   ```

### Про безобидные предупреждения в логе

- `A restricted method in java.lang.System has been called` /
  `--enable-native-access=ALL-UNNAMED` — предупреждения Gradle 9 на новых
  JDK, на сборку не влияют.
- `sdkmanager is deprecated. Android CLI will be used` — информационное
  сообщение Google, действий не требует.
