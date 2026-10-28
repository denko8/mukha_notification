import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/settings/models/app_settings.dart';
import '../features/shell/main_scaffold.dart';
import 'providers.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_theme.dart';

class SmartNotesApp extends ConsumerWidget {
  const SmartNotesApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).valueOrNull ??
        const AppSettings();

    // Переназначаем статическую палитру до сборки темы: смена варианта
    // меняет состояние, Riverpod пересобирает MaterialApp целиком.
    AppColors.applyVariant(ThemeVariant.byId(settings.themeVariant));

    return MaterialApp(
      title: 'Smart Notes',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: settings.themeMode,
      locale: const Locale('ru'),
      supportedLocales: const [Locale('ru'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // Размер шрифта из настроек (раздел 2.4 ТЗ).
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(settings.fontSize.scale),
          ),
          child: child!,
        );
      },
      home: const MainScaffold(),
    );
  }
}
