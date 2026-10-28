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
```

> Полный актуальный манифест с `<queries>` и `<application>`-атрибутами
> — в разделе 10.2 (после перехода на Vosk блок RecognitionService из
> queries удалён, остался только дефолтный PROCESS_TEXT).

### 3.2. Модуль :app — desugaring и JVM target 17

Файл `android/app/build.gradle.kts`, внутри блока `android { }`.
Заодно явно фиксируем `compileSdk = 36`: свежие плагины
(`flutter_plugin_android_lifecycle` внутри `file_picker` и др.) требуют
API 36, а шаблонная переменная `flutter.compileSdkVersion` отстаёт.

```kotlin
android {
    // ...существующие namespace/applicationId/minSdk не трогаем...
    compileSdk = 36

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
            // compileSdk 36 для всех плагинов: AAR-метаданные свежих
            // зависимостей требуют API 36 (file_picker и его цепочка).
            androidExt.compileSdkVersion(36)
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
            androidExt.compileSdkVersion(36)
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

Платформа `android-36` скачается автоматически при первой сборке
(лицензии уже приняты через `flutter doctor --android-licenses`); при
обрыве сети — установить вручную в **Settings → Android SDK → SDK
Platforms → Android 16 (API 36)**.

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

## 9. Ошибка AAR metadata «requires ... compile against version 36 or later»

```text
Execution failed for task ':file_picker:checkDebugAarMetadata'.
Dependency ':flutter_plugin_android_lifecycle' requires libraries and
applications that depend on it to compile against version 36 or later.
:file_picker is currently compiled against android-34.
```

Причина: свежие версии плагинов в своих AAR-метаданных требуют
`compileSdk 36`, а модули плагинов по умолчанию собираются против 34
(`flutter.compileSdkVersion` шаблона отстаёт). `targetSdk` и `minSdk`
при этом менять не нужно — речь только об уровне API, против которого
идёт компиляция.

Лечение в два шага:

1. В `android/app/build.gradle.kts` заменить
   `compileSdk = flutter.compileSdkVersion` на `compileSdk = 36`
   (раздел 3.2).
2. В корневом `android/build.gradle.kts` в том же `afterEvaluate`-блоке
   добавить `androidExt.compileSdkVersion(36)` — это поднимает
   `compileSdk` и всем модулям плагинов, включая `:file_picker`
   (раздел 3.3).

Платформа Android API 36 доустановится автоматически при сборке.

## 10. Голосовой ввод: офлайн-модель Vosk

Начиная с текущей версии голос **не зависит от Google-сервисов и
системного RecognitionService**. Распознавание полностью локальное, на
движке [Vosk](https://alphacephei.com/vosk/) через плагин
`vosk_flutter`. Модель русской речи `vosk-model-small-ru-0.22` (~45 МБ
zip, ~90 МБ после распаковки) скачивается один раз при первом тапе по
микрофону и хранится в каталоге документов приложения; в APK модель не
упакована, поэтому установочный файл остаётся лёгким. После загрузки
диктовка работает без интернета.

### 10.1. Gradle: репозитории alphacephei и движка Flutter (обязательно)

Нужны два нестандартных Maven-репозитория:

1. `https://alphacephei.com/maven/` — нативный движок Vosk
   (`com.alphacephei:vosk-android`) и JNA;
2. репозиторий движка Flutter — оттуда берутся `io.flutter:flutter_embedding_*`
   и `io.flutter:arm64_v8a_*`. По умолчанию это
   `https://storage.googleapis.com/download.flutter.io`, а при заданной
   переменной `FLUTTER_STORAGE_BASE_URL` (зеркало, в т.ч. китайское) —
   `$FLUTTER_STORAGE_BASE_URL/download.flutter.io`.

Тонкость: Flutter Gradle-плагин регистрирует репозиторий движка
**проектным** (`rootProject.allprojects { repositories { ... } }`).
Режим `PREFER_SETTINGS` проектные репозитории игнорирует — поэтому
движковый репозиторий надо явно продублировать на уровне settings,
иначе сборка падает (см. 10.1.2). Готовый блок для
`android/settings.gradle.kts`:

```kotlin
dependencyResolutionManagement {
    // PREFER_SETTINGS, а не FAIL_ON_PROJECT_REPOS: vosk_flutter в своём
    // build.gradle объявляет проектный allprojects-репозиторий, который
    // при FAIL-режиме роняет сборку.
    repositoriesMode.set(RepositoriesMode.PREFER_SETTINGS)
    repositories {
        google()
        mavenCentral()

        // Локальный кэш движка Flutter — первый по списку: точная ревизия
        // движка уже скачана, резолв без сети и не зависит от блокировок.
        val localProps = java.util.Properties().apply {
            val f = file("local.properties")
            if (f.exists()) f.inputStream().use { load(it) }
        }
        val flutterSdk = localProps.getProperty("flutter.sdk")
            ?: System.getenv("FLUTTER_ROOT")
        if (flutterSdk != null) {
            val engineMaven =
                file("$flutterSdk/bin/cache/artifacts/engine/android")
            if (engineMaven.exists()) {
                maven { url = uri(engineMaven) }
            }
        }

        // Удалённый репозиторий движка (fallback), с учётом зеркала.
        val storageBase = System.getenv("FLUTTER_STORAGE_BASE_URL")
            ?: "https://storage.googleapis.com"
        maven { url = uri("$storageBase/download.flutter.io") }

        // Нативный Vosk и JNA.
        maven { url = uri("https://alphacephei.com/maven/") }
    }
}
```

Groovy-вариант (`android/settings.gradle`):

```groovy
def localProps = new Properties()
def lpFile = new File(settingsDir, 'local.properties')
if (lpFile.exists()) lpFile.withReader('UTF-8') { localProps.load(it) }
def flutterSdk = localProps.getProperty('flutter.sdk') ?: System.getenv('FLUTTER_ROOT')
def storageBase = System.getenv('FLUTTER_STORAGE_BASE_URL') ?: 'https://storage.googleapis.com'

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.PREFER_SETTINGS)
    repositories {
        google()
        mavenCentral()
        if (flutterSdk != null) {
            def engineMaven = new File(flutterSdk, 'bin/cache/artifacts/engine/android')
            if (engineMaven.exists()) {
                maven { url engineMaven }
            }
        }
        maven { url "$storageBase/download.flutter.io" }
        maven { url 'https://alphacephei.com/maven/' }
    }
}
```

После правки — `flutter clean && flutter run`.

#### 10.1.2. Ошибка «Could not find io.flutter:flutter_embedding_debug…»

Симптом:

```
Execution failed for task ':app:mergeDebugAssets'.
> Could not find io.flutter:flutter_embedding_debug:1.0.0-<хэш>.
  Searched in: dl.google.com, repo.maven.apache.org, alphacephei.com
```

В списке локаций нет репозитория движка Flutter — значит settings
собраны в режиме `PREFER_SETTINGS`, но `download.flutter.io` (и/или
локальный кэш SDK) в `repositories` не добавлены, а проектный
репозиторий Flutter-плагина проигнорирован. Лечение — блок из 10.1
целиком (локальный кэш + `download.flutter.io`). Проверить, не задано
ли зеркало:

```powershell
echo $env:FLUTTER_STORAGE_BASE_URL
```

Если переменная указывает на зеркало — блок 10.1 сам подставит её в
URL, дополнительных действий не нужно.

### 10.1.1. Ошибка «Namespace not specified» у vosk_flutter (AGP 8+)

Симптом при сборке:

```
A problem occurred configuring project ':vosk_flutter'.
> Could not create an instance of type ...LibraryVariantBuilderImpl.
  > Namespace not specified. Specify a namespace in the module's build
    file ...vosk_flutter-0.3.48\android\build.gradle
```

Причина: опубликованный `vosk_flutter 0.3.48` написан под AGP 4–7
(в master namespace уже добавлен, но новый релиз на pub.dev не
выложен), а у вас AGP 8+ (compileSdk 36, Gradle 9). AGP 8 не умеет
брать namespace из атрибута `package` манифеста — его нужно
проставить в Gradle. Решение — тот же **корневой
`android/build.gradle.kts`**, где уже стоит блок из раздела 3.3
(JVM 17, compileSdk 36). Дополните его `afterEvaluate` инъекцией
namespace.

ВАЖНО: скрипт только ЧИТАЕТ манифест в pub-кэше, но никогда его не
перезаписывает. Ранняя версия этого рецепта удаляла атрибут `package`
прямо в кэше — первая сборка проходила, но правка оставалась на диске
(`flutter clean` кэш не чистит), и все следующие сборки снова падали
с той же ошибкой: брать namespace уже было неоткуда. Ниже —
идемпототентный вариант с жёстким фолбэком, который чинит и уже
испорченный кэш.

KTS, полный совмещённый блок:

```kotlin
subprojects {
    // Срабатывает после оценки каждого модуля, но регистрируется здесь,
    // в начале корневого файла — поэтому опережает и заморозку AGP,
    // и собственные compileOptions плагинов.
    afterEvaluate {
        val androidExt =
            extensions.findByName("android") as? com.android.build.gradle.BaseExtension
        if (androidExt != null) {
            androidExt.compileSdkVersion(36)
            androidExt.compileOptions {
                sourceCompatibility = JavaVersion.VERSION_17
                targetCompatibility = JavaVersion.VERSION_17
            }
        }

        // === namespace легаси-плагинов без него в build.gradle (AGP 8+) ===
        if (plugins.hasPlugin("com.android.library")) {
            extensions.configure<com.android.build.gradle.LibraryExtension>("android") {
                if (namespace == null) {
                    // 1) основной путь: пакет из манифеста плагина (read-only!)
                    val manifestFile = sourceSets.getByName("main").manifest.srcFile
                    val fromManifest = if (manifestFile.exists()) {
                        Regex("""package="([^"]+)"""")
                            .find(manifestFile.readText())
                            ?.groupValues?.get(1)
                    } else null
                    // 2) фолбэк: манифест в pub-кэше мог быть изменён
                    //    прежней версией скрипта — тогда пакет известен явно.
                    val knownNamespaces = mapOf(
                        ":vosk_flutter" to "org.vosk.vosk_flutter",
                    )
                    namespace = fromManifest ?: knownNamespaces[project.path]
                }
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

Groovy-вариант (тот же модуль, `android/build.gradle`):

```gradle
subprojects {
    afterEvaluate {
        def androidExt = extensions.findByName('android')
        if (androidExt != null) {
            androidExt.compileSdkVersion(36)
            androidExt.compileOptions {
                sourceCompatibility JavaVersion.VERSION_17
                targetCompatibility JavaVersion.VERSION_17
            }
        }
        if (plugins.hasPlugin('com.android.library')) {
            extensions.configure('android') { android ->
                if (android.namespace == null) {
                    def manifestFile = android.sourceSets.main.manifest.srcFile
                    def fromManifest = null
                    if (manifestFile.exists()) {
                        def matcher = (manifestFile.getText('UTF-8') =~ /package="([^"]+)"/)
                        if (matcher.find()) fromManifest = matcher.group(1)
                    }
                    def knownNamespaces = [
                        ':vosk_flutter': 'org.vosk.vosk_flutter',
                    ]
                    android.namespace = fromManifest ?: knownNamespaces[project.path]
                }
            }
        }
        tasks.withType(org.jetbrains.kotlin.gradle.tasks.KotlinCompile).configureEach {
            kotlinOptions { jvmTarget = '17' }
        }
    }
}
```

Блок универсален: сработает для любого плагина без namespace, а не
только для Vosk, и не меняет файлы в pub-кэше — поэтому повторные
сборки и `flutter pub get` его не ломают.

#### Если кэш уже испорчен прошлой версией скрипта

Фолбэк с явным пакетом покрывает этот случай, но для чистоты можно
восстановить исходный манифест плагина — удалить каталог пакета и
заново подтянуть зависимости:

```powershell
Remove-Item -Recurse -Force "$env:LOCALAPPDATA\Pub\Cache\hosted\pub.dev\vosk_flutter-0.3.48"
flutter pub get
```

После правки:

```
flutter clean
flutter run
```

### 10.2. Манифест (раздел 3.1)

Для Vosk нужны только `RECORD_AUDIO` (запись) и `INTERNET` (одноразовая
загрузка модели). Блок `<queries>` под RecognitionService больше не
нужен — системный сервис речи не используется; дефолтный `PROCESS_TEXT`
от Flutter сохраняем. Готовый манифест:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
    <uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>
    <uses-permission android:name="android.permission.USE_EXACT_ALARM"/>
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
    <uses-permission android:name="android.permission.VIBRATE"/>
    <uses-permission android:name="android.permission.RECORD_AUDIO"/>

    <!-- enableOnBackInvokedCallback убирает системное предупреждение
         WindowOnBackDispatcher в Logcat -->
    <application
        android:enableOnBackInvokedCallback="true"
        ...> ... </application>

    <queries>
        <!-- дефолтный запрос Flutter (ProcessTextPlugin), не удалять -->
        <intent>
            <action android:name="android.intent.action.PROCESS_TEXT"/>
            <data android:mimeType="text/plain"/>
        </intent>
    </queries>
</manifest>
```

После правки манифеста — полностью переустановить приложение
(`flutter run` заново, hot reload манифест не подхватывает).

### 10.3. Как это работает у пользователя и в логах

1. Первый тап по микрофону открывает BottomSheet с объяснением и
   кнопкой «Скачать модель»; прогресс показывается в МБ, при обрыве
   сети доступен повтор, частичные файлы удаляются автоматически.
2. После скачивания шит закрывается сам и сразу стартует запись.
3. Приложение запрашивает разрешение на микрофон; при отказе — снэкбар
   с кнопкой «Настройки» (открывает системный экран разрешений).
4. Дальше микрофон работает офлайн: Vosk отдаёт «живые» partial-результаты
   и финальные фразы, текст подставляется в поле ввода.

Диагностика в Logcat — по тегу `[VOSK]`:

- `модель уже на месте` / `модель готова` — файлы модели в порядке;
- `загрузка модели в память…` — разовый этап 1–3 секунды при первой
  записи после запуска приложения;
- `запись начата` / `стоп` — жизненный цикл сессии;
- `ошибка записи` / `старт записи не удался` — текст ошибки рядом.

### 10.4. Прошивка vivo (Funtouch OS)

- Настройки → Приложения → Smart Notes → Разрешения → Микрофон →
  Разрешить.
- там же → Батарея → снять ограничения фоновой активности, иначе
  запись может останавливаться сразу после старта.

### 10.5. Почему ушёл speech_to_text

Системный RecognitionService на этой прошивке либо отсутствовал, либо
зависал на вызове `locales()`: в Logcat инициализация завершалась
успешно (`initialize -> true`), но до `listen()` дело не доходило —
микрофон загорался и молчал. Офлайн-движок устранил целый класс таких
проблем: ни Google-приложений, ни сервиса речи, ни сетевой модели
системы после одноразовой загрузки не требуется.

## 11. RenderFlex overflow у тумблера «Семейная» и аватаров семьи

Ошибка вида `A RenderFlex overflowed by X pixels` в строке ввода
возникала на узких экранах: четыре IconButton по 48 dp, подпись и Switch
не помещались. Лечение уже в коде — кнопки компактные (40 dp), подпись
обёрнута в `Flexible` с `ellipsis`, Switch со `shrinkWrap`. Аналогично
исправлен блок участников семьи (`_MemberAvatar`): высота списка 92 dp,
аватар 46 dp, у подписи фиксированный межстрочный интервал. Если
повторится при изменении системного масштаба шрифта — уменьшить масштаб
в настройках телефона или проверить, что правка не откачена.

## 12. Не приходят локальные уведомления

Код планирует уведомления через `flutter_local_notifications`: на Android
13+ запрашивает POST_NOTIFICATIONS, на Android 12+ — право на точные
будильники, при отказе в точном планировании автоматически откатывается
на неточное (доставка с возможной задержкой в режиме Doze). Если
напоминание всё равно не приходит, порядок проверки:

1. **Разрешения приложения** (vivo): Настройки → Приложения → Smart Notes
   → Уведомления → включить все категории, особенно канал «Напоминания».
2. **Точные будильники**: Настройки → Приложения → Smart Notes →
   Разрешения → Будильники и напоминания → Разрешить
   (на Funtouch OS пункт может называться «Точные сигналы»).
3. **Автозапуск и фон**: Настройки → Приложения → Smart Notes →
   Автозапуск → включить; Батарея → «Нет ограничений». После очистки
   списка недавних приложений vivo иначе убивает процесс.
4. **Закрепить в «Недавних»**: свайп вниз по карточке приложения —
   иконка замка, система перестанет выгружать его из памяти.
5. Проверить, что время напоминания в будущем: прошедшие даты
   намеренно не планируются.
6. **Встроенная самопроверка**: Настройки → Уведомления →
   «Проверить уведомление». Приложение покажет диалог со статусами
   разрешений (уведомления, точные будильники, длина очереди) и
   поставит тест через 10 секунд — заметку создавать не нужно.
   В Logcat видны строки `[NOTIFY]`: разрешения, планирование каждого
   id, выбор exact/inexact и результат диагностики.
7. Быстрый сквозной тест заметкой: «тест через 2 минуты» —
   правило `через 2 минуты` поставит ближайшее время, не трогая Doze.

## 13. Производительность debug-сборки и предупреждение OnBackInvokedCallback

- `Skipped 76 frames` и общая «топорность» анимаций в `flutter run` —
  нормальное поведение debug-режима (JIT, asserts, отключённые
  оптимизации Impeller). Реальная плавность проверяется командой
  `flutter run --profile` или релизной сборкой `flutter build apk`.
- Предупреждение
  `OnBackInvokedCallback is not enabled ... set
  android:enableOnBackInvokedCallback="true"` убирается добавлением
  этого атрибута в тег `<application>` манифеста — он включён в готовый
  манифест раздела 10.1.
- Краш `E/AndroidRuntime ... Process: com.android.vending` с
  `IllegalStateException: Unsupported RecoveryScreenButton` — это падение
  самого приложения Google Play (чужой процесс, другой PID), к Smart Notes
  отношения не имеет; лечится обновлением/очисткой кэша Play Market.
- Overflow пустого состояния ленты при открытой клавиатуре исправлен в
  коде: `_EmptyState` обёрнут в SingleChildScrollView, жёлто-чёрная
  полоса больше не появляется.
