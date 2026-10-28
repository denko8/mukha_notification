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

1. **File → Open** → выбрать папку проекта (ту, где лежит `pubspec.yaml`),
   **не** родительскую.
2. Дождаться индексации и автоматического `pub get` (или выполнить вручную).
3. В терминале IDE в корне проекта:

   ```powershell
   flutter create --org com.smartnotes .
   flutter pub get
   ```

   Команда добавит недостающие папки `android/`, `ios/` и т.д., не трогая
   `lib/`, `test/` и `pubspec.yaml`.

## 3. Правки под плагины проекта (один раз)

Нужны три вещи: разрешения в манифесте, desugaring в модуле `:app` и
единый JVM target 17 для всех плагинов. Делать строго в указанном виде —
в разделе 6 разобрано, почему другие варианты не работают.

### 3.1. AndroidManifest.xml

Файл: `android/app/src/main/AndroidManifest.xml`. Разрешения добавить
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

### 3.2. Модуль :app — desugaring и JVM target 17

Файл `android/app/build.gradle.kts`, внутри блока `android { }`:

```kotlin
android {
    // ...существующие namespace/applicationId/minSdk не трогаем...

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlin {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
```

Desugaring обязателен для `flutter_local_notifications` 17 (использует
`java.time`). JDK 17 в системе уже есть — на нём работает сам Gradle 9.
Старый синтаксис `kotlinOptions { jvmTarget = "1.8" }` не использовать.

### 3.3. Единый JVM target 17 для ВСЕХ плагинов — блок в НАЧАЛО корневого файла

Файл `android/build.gradle.kts` (корневой, не путать с `android/app/...`).
Вставить блок САМЫМИ ПЕРВЫМИ СТРОКАМИ файла — до `allprojects` и
`evaluationDependsOn(":app")`:

```kotlin
subprojects {
    // Срабатывает после оценки каждого модуля, но регистрируется здесь,
    // в начале корневого файла — поэтому опережает и заморозку AGP,
    // и собственные compileOptions плагинов.
    afterEvaluate {
        val androidExt =
            extensions.findByName("android") as? com.android.build.gradle.BaseExtension
        if (androidExt != null) {
            androidExt.compileOptions {
                sourceCompatibility = JavaVersion.VERSION_17
                targetCompatibility = JavaVersion.VERSION_17
            }
        }
        tasks.withType(org.jetbrains.kotlin.gradle.tasks.KotlinCompile::class.java)
            .configureEach {
                compilerOptions {
                    jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
                }
            }
    }
}
```

Groovy-вариант, если сгенерировался `android/build.gradle` (тоже в начало):

```gradle
subprojects {
    afterEvaluate {
        def androidExt = extensions.findByName('android')
        if (androidExt != null) {
            androidExt.compileOptions {
                sourceCompatibility JavaVersion.VERSION_17
                targetCompatibility JavaVersion.VERSION_17
            }
        }
        tasks.withType(org.jetbrains.kotlin.gradle.tasks.KotlinCompile).configureEach {
            kotlinOptions {
                jvmTarget = '17'
            }
        }
    }
}
```

Почему цель именно 17 для всех: `audioplayers_android` зашит под Java 17
(понизить нельзя), а `flutter_timezone`, `share_plus` и остальные
спокойно поднимаются с 8/11 до 17. Другого общего знаменателя нет.

`minSdk` по умолчанию (21) всем плагинам достаточен; если какой-то
потребует выше — поднять `minSdk` в `android/app/build.gradle.kts` до 23.

## 4. Запуск

### Вариант А — реальный телефон (рекомендуется: голос, OCR, покупки)

1. На телефоне: **Настройки → О телефоне → 7 тапов по «Номеру сборки»**
   → включить **Параметры разработчика → Отладка по USB**.
2. Подключить кабелем, на телефоне разрешить отладку (RSA-запрос).
3. Проверить видимость: `flutter devices`.
4. Выбрать телефон в списке устройств на верхней панели Android Studio
   и нажать **Run** (Shift+F10).

### Вариант Б — эмулятор

1. **Device Manager** справа → **Create Virtual Device** → Pixel 7 →
   системный образ API 34/35 → Finish.
2. Запустить эмулятор, дождаться загрузки Android.
3. Выбрать его в списке устройств и нажать **Run**.

Первая сборка идёт 5–15 минут: Gradle качает дистрибутив и зависимости.
Молния на панели — hot reload, круговая стрелка — hot restart.

## 5. Полезное

- Проверка кода и тесты:

  ```powershell
  flutter analyze
  flutter test
  ```

- Логи приложения — вкладка **Logcat**.
- Если сборка падает на сетевых ошибках загрузки Gradle/pub —
  см. `WINDOWS_SETUP_RU.md` (зеркала для RU).
- Безобидные предупреждения, которые игнорируем:
  - `A restricted method ... --enable-native-access=ALL-UNNAMED` — шум
    Gradle 9 на новых JDK;
  - `sdkmanager is deprecated` — информационное сообщение Google;
  - `plugins that apply Kotlin Gradle Plugin (KGP): flutter_timezone,
    share_plus` — предупреждение о будущем миграции Flutter, не ошибка,
    обновится вместе с новыми версиями плагинов;
  - `unchecked or unsafe operations` в ML Kit — внутренние заметки чужого
    кода, на сборку не влияют.

## 6. Разбор ошибок JVM target (почему рецепт именно такой)

Под каждый плагин зашиты свои цели: `share_plus` — Java 1.8/Kotlin 1.8,
`flutter_timezone` — 11/1.8, `audioplayers_android` — 17. Gradle 9
требует, чтобы внутри модуля Java- и Kotlin-цели совпадали, и падает с
`Inconsistent JVM Target Compatibility`. Перебрать все грабли проще, чем
их обойти, поэтому зафиксирован один рабочий рецепт (раздел 3.3) и список
приёмов, которые на шаблоне Flutter 3.35+/Gradle 9/AGP 8.11 НЕ работают:

1. **`afterEvaluate` в конце корневого файла** →
   `Cannot run Project.afterEvaluate ... when the project is already
   evaluated`. Шаблон содержит `evaluationDependsOn(":app")` и к концу
   файла проекты уже оценены. Лечится позицией: тот же `afterEvaluate`,
   но в НАЧАЛЕ файла.
2. **`withPlugin("com.android.base")` в конце файла** →
   `sourceCompatibility has been finalized`: extension уже заморожен.
3. **Тот же `withPlugin` в начале файла** → не падает, но бесполезен:
   колбэк отрабатывает раньше собственного `android { }` плагина, и тот
   затирает наши `compileOptions` обратно (Java остаётся 1.8 — видно по
   предупреждению `source value 8 is obsolete`). Поэтому нужен
   `afterEvaluate`, который выполняется после оценки модуля.
4. **Глобальный `jvmTarget = 11`** → чинит `flutter_timezone`, но ломает
   `audioplayers_android` (Java 17 против Kotlin 11).
5. **Правка задач `JavaCompile` из корня** → AGP перетиравает их
   свойства из своего extension, эффекта нет.
6. **`doFirst { jvmTarget.set(...) }`** →
   `The value for property 'jvmTarget' is final and cannot be changed`:
   на этапе выполнения задачи свойство уже неизменяемо, менять можно
   только на этапе конфигурации (через `configureEach` без `doFirst`).

Итоговый блок из раздела 3.3 обходит все шесть пунктов: регистрируется
до оценки проектов (1, 2), выполняется после собственной конфигурации
плагина (3), унифицирует на 17 (4), пишет в extension, а не в задачи (5),
и меняет `jvmTarget` на этапе конфигурации (6).

## 7. Ошибка «sdkmanager did not install NDK 28.2.13676358»

Свежий шаблон прописывает `ndkVersion = flutter.ndkVersion`, а автодокачка
NDK с Google-серверов в РФ часто обрывается. Нашим плагинам NDK не нужен
(ни один не содержит C/C++-кода), поэтому самый быстрый путь — открыть
`android/app/build.gradle.kts` и удалить строку
`ndkVersion = flutter.ndkVersion`, затем `flutter clean`.

Альтернатива — поставить NDK через **Settings → Android SDK → SDK Tools →
Show Package Details → NDK (Side by side) → 28.2.13676358** (возможно,
потребуется VPN на время загрузки).

## 8. Нужно ли коммитить правки в android/?

Нет. Папки `android/`, `ios/`, `web/` исключены из git (`.gitignore`,
секция «Platform folders are regenerated locally via `flutter create .`»).
Правки Gradle и манифеста локальные, `git status` их не показывает.
Все рабочие сниппеты лежат в этом документе, поэтому после повторной
генерации платформенной папки они применяются заново за пару минут.
