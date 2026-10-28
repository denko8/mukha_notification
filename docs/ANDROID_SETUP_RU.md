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
Общая цель всего проекта — **17**: это общий знаменатель плагинов
(`audioplayers_android` требует Java 17, остальные спокойно с 11
поднимаются до 17). JDK 17+ в системе уже есть — на нём работает сам
Gradle 9.

#### Kotlin DSL (`android/app/build.gradle.kts`) — актуальный шаблон

```kotlin
android {
    // ...существующие namespace/applicationId/minSdk...

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

Важно: старый блок `kotlinOptions { jvmTarget = "1.8" }` НЕ применять —
Kotlin 2.x считает его обособленным и конфликтует с Java-целью.

#### Groovy (`android/app/build.gradle`), если шаблон старый

```gradle
android {
    compileOptions {
        coreLibraryDesugaringEnabled = true
        sourceCompatibility JavaVersion.VERSION_17
        targetCompatibility JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = '17'
    }
}

dependencies {
    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'
}
```

### 3.3. Выравнивание JVM target во ВСЕХ модулях — блок в НАЧАЛО корневого файла

Разные плагины проекта зашиты под разные цели: `flutter_timezone` и
`share_plus` — Kotlin 1.8 при Java 11, `audioplayers_android` — Java 17.
Единый безопасный знаменатель — **17 для всех**: понижать audioplayers
нельзя, а остальные модули спокойно поднимаются.

Ключевой нюанс нового шаблона Flutter: корневой `android/build.gradle.kts`
содержит `subprojects { project.evaluationDependsOn(":app") }`, из-за
чего к КОНЦУ файла часть проектов уже оценена. Поэтому блок выравнивания
нужно ставить в САМОЕ НАЧАЛО файла (сразу после `plugins { }`, если он
есть, до `allprojects`/`evaluationDependsOn`) — тогда колбэки
`withPlugin` регистрируются раньше оценки проектов, extension ещё не
заморожен, а `jvmTarget` ещё не стал final.

Полный список способов, которые НЕ работают на Gradle 9 / AGP 8.11:

1. `afterEvaluate {}` — `Cannot run Project.afterEvaluate ... when the
   project is already evaluated`.
2. `withPlugin("com.android.base")` в конце файла —
   `sourceCompatibility has been finalized` (extension уже заморожен).
3. Глобальный `jvmTarget = JVM_11` — чинит timezone, ломает audioplayers
   (Java 17 против Kotlin 11).
4. Правка `JavaCompile`-задач — AGP перетирает её из своего extension.
5. `doFirst { jvmTarget.set(...) }` —
   `The value for property 'jvmTarget' is final and cannot be changed`:
   к запуску задачи свойство неизменяемо.

Рабочий вариант — ранняя регистрация через `withPlugin` (Android-extension
правим пока он не заморожен) плюс конфигурация Kotlin-задач на этапе
конфигурации (пока `jvmTarget` не final).

Файл `android/build.gradle.kts` (корневой), ПЕРВЫМИ строками:

```kotlin
subprojects {
    // Java всех Android-модулей -> 17 (регистрация до оценки проектов,
    // поэтому compileOptions ещё не заморожен).
    pluginManager.withPlugin("com.android.base") {
        extensions.configure<com.android.build.gradle.BaseExtension>("android") {
            compileOptions {
                sourceCompatibility = JavaVersion.VERSION_17
                targetCompatibility = JavaVersion.VERSION_17
            }
        }
    }
    // Kotlin всех модулей -> 17 на этапе конфигурации (jvmTarget ещё не final).
    tasks.withType(org.jetbrains.kotlin.gradle.tasks.KotlinCompile::class.java)
        .configureEach {
            compilerOptions {
                jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
            }
        }
}
```

Groovy-вариант (корневой `android/build.gradle`), также в начало файла:

```gradle
subprojects {
    pluginManager.withPlugin('com.android.base') {
        extensions.configure('android') {
            compileOptions {
                sourceCompatibility JavaVersion.VERSION_17
                targetCompatibility JavaVersion.VERSION_17
            }
        }
    }
    tasks.withType(org.jetbrains.kotlin.gradle.tasks.KotlinCompile).configureEach {
        kotlinOptions {
            jvmTarget = '17'
        }
    }
}
```

Если ранее уже был вставлен любой из нерабочих вариантов
(`afterEvaluate`, `withPlugin` в конце файла, глобальный `jvmTarget = 11`,
правка `JavaCompile`, `doFirst`) — удалить его полностью, а новый блок
разместить именно в начале файла.

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
  последствия jvmTarget 1.8; после перехода на 17 (раздел 3.2/3.3)
  предупреждения исчезают.

## 7. Ошибка «Inconsistent JVM Target Compatibility»

```text
Execution failed for task ':flutter_timezone:compileDebugKotlin'.
Inconsistent JVM-target compatibility detected for tasks
'compileDebugJavaWithJavac' (11) and 'compileDebugKotlin' (1.8).
```

Причина: AGP 8+ компилирует Java по умолчанию в 11, а старые плагины
(`flutter_timezone`, `share_plus`) внутри своих модулей задают Kotlin
1.8. Gradle 9 считает такое рассогласование фатальным. Лечится общим
выравниванием всех модулей на 17 — раздел 3.2 (модуль `:app`) и 3.3
(все плагины, блок в начало корневого `build.gradle.kts`).

## 8. Ошибка «Cannot run Project.afterEvaluate when the project is already evaluated»

Возникает, если блок выравнивания с `afterEvaluate` стоит после
шаблонного `subprojects { project.evaluationDependsOn(":app") }`: к этому
моменту модуль `:app` уже оценён, регистрация нового `afterEvaluate`
запрещена. Решение — блок через `withPlugin` в НАЧАЛЕ файла (раздел 3.3).

## 9. Нужно ли коммитить правки в android/?

Нет. Папки `android/`, `ios/`, `web/` намеренно исключены из git
(см. `.gitignore`, секция «Platform folders are regenerated locally via
`flutter create .`»). Правки Gradle и манифеста — локальные, специфичные
для машины разработчика, и в репозиторий не попадают: `git status` их
не покажет. Все рабочие сниппеты зафиксированы в этом документе, поэтому
после повторной генерации платформенной папки их можно применить заново
за пару минут.

## 10. Ошибка «sourceCompatibility has been finalized»

Возникает при попытке менять `android { compileOptions { ... } }` из
корневого файла ПОЗДНО (в конце файла, в `afterEvaluate` или в
`withPlugin`, когда проект уже оценён): в AGP 8.11+ свойства
Android-extension'а замораживаются после создания вариантов. Решение —
зарегистрировать тот же `withPlugin("com.android.base")` в НАЧАЛЕ
корневого файла, до `evaluationDependsOn(":app")`: колбэк отработает в
момент применения плагина, когда extension ещё не заморожен (раздел 3.3).

## 11. Обратный рассинхрон: Java 17 против Kotlin 11 (audioplayers_android)

```text
Execution failed for task ':audioplayers_android:compileDebugKotlin'.
Inconsistent JVM-target compatibility detected for tasks
'compileDebugJavaWithJavac' (17) and 'compileDebugKotlin' (11).
```

Возникает после принудительного `jvmTarget = 11` на все модули:
`audioplayers_android` зашивает Java-цель 17, поэтому единое значение 11
ломает уже его. Правильный общий знаменатель — 17 для всех модулей
(раздел 3.3). Запись `sourceCompatibility` в `JavaCompile`-задачи при
этом бесполезна: AGP перетирает её из своего extension.

## 12. Предупреждение про KGP-плагины (flutter_timezone, share_plus)

```text
Your app uses plugins that apply Kotlin Gradle Plugin (KGP):
flutter_timezone, share_plus. Future versions of Flutter will fail to
build...
```

Это предупреждение, а не ошибка: Flutter готовит переход на Built-in
Kotlin. Собирать и выпускаться оно не мешает. На будущее — следить за
обновлениями `flutter_timezone` и `share_plus` и обновляться по
`flutter pub upgrade`, когда выйдут версии без KGP.

## 13. Ошибка «The value for property 'jvmTarget' is final and cannot be changed»

Возникает, если менять `jvmTarget` в `doFirst` Kotlin-задачи: к моменту
запуска задачи свойство уже неизменяемо (`final`). Менять `jvmTarget`
можно только на этапе КОНФИГУРАЦИИ — через
`tasks.withType(KotlinCompile).configureEach { compilerOptions { ... } }`
без оборачивания в `doFirst`. Рабочий сниппет — раздел 3.3, он ставит
17 всем модулям на этапе конфигурации, пока свойство ещё доступно для
записи.
