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

### 3.2. Core library desugaring + единый JVM target (обязательно)

Нужно для `flutter_local_notifications` 17 (использует `java.time`).
AGP 8+ по умолчанию компилирует Java в 11, поэтому и Java, и Kotlin
выравниваем на **11** — иначе Gradle 9 падает с
`Inconsistent JVM Target Compatibility` (в т.ч. внутри плагинов вроде
`flutter_timezone`).

#### Kotlin DSL (`android/app/build.gradle.kts`) — актуальный шаблон

```kotlin
android {
    // ...существующие namespace/applicationId/minSdk...

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
    kotlin {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11)
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
```

Важно: старый блок `kotlinOptions { jvmTarget = "1.8" }` НЕ применять —
Kotlin 2.x считает его обособленным и конфликтует с Java 11.

#### Groovy (`android/app/build.gradle`), если шаблон старый

```gradle
android {
    compileOptions {
        coreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
    kotlinOptions {
        jvmTarget = '11'
    }
}

dependencies {
    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'
}
```

### 3.3. Выравнивание JVM target во ВСЕХ модулях (если ошибка в плагине)

Ошибка вида
`compileDebugJavaWithJavac (11) ... compileDebugKotlin (1.8)` в модуле
`:flutter_timezone` (или другом плагине) означает: свой `build.gradle`
плагина зашит под Kotlin 1.8, а Java вокруг уже 11 (дефолт AGP 8+).
Принудительно выравниваем все подпроекты.

ВАЖНО (история граблей нового шаблона Flutter/Gradle 9):

1. `afterEvaluate {}` в конце корневого файла падает с
   `Cannot run Project.afterEvaluate ... when the project is already
   evaluated` — шаблон заранее форсирует оценку `:app`.
2. Попытка менять `android { compileOptions { ... } }` через
   `pluginManager.withPlugin` падает с
   `sourceCompatibility has been finalized` — в AGP 8.11+ свойства
   Android-extension'а замораживаются после создания вариантов.

Поэтому НЕ трогаем Android-extension и НЕ используем afterEvaluate.
Конфигурируем сами задачи (task-level), лениво через `configureEach` —
это не зависит ни от порядка оценки проектов, ни от заморозки extension'а.
Java по умолчанию и так на 11, ключевое — заставить Kotlin плагинов
собираться в 11.

Файл `android/build.gradle.kts` (корневой), в конец файла:

```kotlin
subprojects {
    // Kotlin-цели всех модулей (включая плагины вроде flutter_timezone) -> 11
    tasks.withType(org.jetbrains.kotlin.gradle.tasks.KotlinCompile::class.java)
        .configureEach {
            compilerOptions {
                jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11)
            }
        }
    // Подстраховка: если какой-то модуль всё же зашил Java в 1.8,
    // выравниваем на уровне задач — свойства задачи не финализируются AGP.
    tasks.withType(JavaCompile::class.java).configureEach {
        sourceCompatibility = JavaVersion.VERSION_11.toString()
        targetCompatibility = JavaVersion.VERSION_11.toString()
    }
}
```

Groovy-вариант (корневой `android/build.gradle`):

```gradle
subprojects {
    tasks.withType(org.jetbrains.kotlin.gradle.tasks.KotlinCompile).configureEach {
        kotlinOptions {
            jvmTarget = '11'
        }
    }
    tasks.withType(JavaCompile).configureEach {
        sourceCompatibility = JavaVersion.VERSION_11.toString()
        targetCompatibility = JavaVersion.VERSION_11.toString()
    }
}
```

Если ранее уже был вставлен вариант с `afterEvaluate` или
`pluginManager.withPlugin("com.android.base")` — удалить его полностью
и заменить этим блоком.

`minSdk` по умолчанию (21) всем плагинам проекта достаточен; если какой-то
плагин потребует выше — поднять `minSdk` в `android/app/build.gradle.kts`
до 23.

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
- `source value 8 is obsolete` / `target value 8 is obsolete` — это
  последствия jvmTarget 1.8; после перехода на 11 (раздел 3.2/3.3)
  предупреждения исчезают.

## 7. Ошибка «Inconsistent JVM Target Compatibility»

```text
Execution failed for task ':flutter_timezone:compileDebugKotlin'.
Inconsistent JVM-target compatibility detected for tasks
'compileDebugJavaWithJavac' (11) and 'compileDebugKotlin' (1.8).
```

Причина: AGP 8+ компилирует Java по умолчанию в 11, а старые плагины
(`flutter_timezone`, часть ML Kit/речевых) внутри своих модулей задают
Kotlin 1.8 — новый Gradle 9 считает такое рассогласование фатальным.

Лечение:

1. В `android/app/build.gradle.kts` привести обе цели к 11 и включить
   desugaring — см. раздел 3.2.
2. В корневой `android/build.gradle.kts` добавить блок `subprojects`
   выравнивания на уровне задач (`tasks.withType(...).configureEach`) —
   см. раздел 3.3. Важно: ни `afterEvaluate`, ни
   `pluginManager.withPlugin("com.android.base")` с правкой
   `android.compileOptions` на новом шаблоне не работают (см. разделы 8
   и 10).
3. Собрать заново:

   ```powershell
   flutter clean
   flutter run
   ```

## 8. Ошибка «Cannot run Project.afterEvaluate when the project is already evaluated»

Возникает в корневом `android/build.gradle.kts`, если блок выравнивания
JVM-целей написан через `subprojects { afterEvaluate { ... } }` и стоит
после шаблонного `subprojects { project.evaluationDependsOn(":app") }`:
к моменту выполнения колбэка модуль `:app` уже оценён, и регистрация
нового `afterEvaluate` запрещена.

Решение — заменить весь блок на task-level вариант из раздела 3.3.

## 9. Нужно ли коммитить правки в android/?

Нет. Папки `android/`, `ios/`, `web/` намеренно исключены из git
(см. `.gitignore`, секция «Platform folders are regenerated locally via
`flutter create .`»). Правки Gradle и манифеста — локальные, специфичные
для машины разработчика, и в репозиторий не попадают: `git status` их
не покажет. Все рабочие сниппеты зафиксированы в этом документе, поэтому
после повторной генерации платформенной папки их можно применить заново
за пару минут.

## 10. Ошибка «sourceCompatibility has been finalized»

Возникает, если в корневом `android/build.gradle.kts` через
`pluginManager.withPlugin("com.android.base")` или `afterEvaluate`
менять `android { compileOptions { ... } }`: в AGP 8.11+ свойства
Android-extension'а замораживаются («финализируются») сразу после
создания вариантов сборки, и поздняя запись в них запрещена.

Решение — вообще не трогать Android-extension из корневого файла,
а конфигурировать задачи напрямую через
`tasks.withType(KotlinCompile/JavaCompile).configureEach` — рабочий
сниппет в разделе 3.3. Свойства самих задач AGP не финализирует, поэтому
такой вариант стабилен и не зависит от порядка оценки проектов.
