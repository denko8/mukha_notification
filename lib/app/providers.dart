import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../core/services/billing_service.dart';
import '../core/services/deep_link_service.dart';
import '../core/services/json_store.dart';
import '../core/services/notification_service.dart';
import '../core/services/ocr_service.dart';
import '../core/services/share_service.dart';
import '../core/services/sync_service.dart';
import '../core/services/voice_input_service.dart';
import '../core/services/voice_model_service.dart';
import '../core/services/vosk_voice_service_stub.dart'
    if (dart.library.io) '../core/services/vosk_voice_service.dart';
import '../features/ai/ai_connection_service.dart';
import '../features/ai/ai_reminder_parser.dart';
import '../features/ai/llm/ai_client_factory.dart';
import '../features/ai/llm/llm_reminder_parser.dart';
import '../features/ai/rule_based_ai_parser.dart';
import '../features/family/data/family_repository.dart';
import '../features/family/state/family_notifier.dart';
import '../features/notes/data/notes_repository.dart';
import '../features/notes/models/note.dart';
import '../features/notes/state/notes_notifier.dart';
import '../features/settings/models/app_settings.dart';
import '../features/settings/state/settings_notifier.dart';

/// Инфраструктурные провайдеры.
/// [jsonStoreProvider] и [notificationServiceProvider] переопределяются
/// в main() (боевой запуск) и в тестах (временный каталог / заглушка).
final jsonStoreProvider = Provider<JsonStoreBase>(
  (ref) => throw UnimplementedError('JsonStore must be overridden in main()'),
);

final uuidProvider = Provider<Uuid>((ref) => const Uuid());

final notificationServiceProvider = Provider<NotificationService>(
  (ref) => LocalNotificationService(),
);

final syncServiceProvider = Provider<SyncService>(
  (ref) => LocalSyncService(),
);

final shareServiceProvider = Provider<ShareService>((ref) => ShareService());

/// Состояние и загрузка офлайн-модели распознавания речи.
final voiceModelServiceProvider =
    StateNotifierProvider<VoiceModelService, VoiceModelState>(
  (ref) => VoiceModelService()..checkExisting(),
);

/// Офлайн Vosk — только на Android; на остальных платформах Noop,
/// чтобы web-сборка не тянула плагин без нативной реализации.
final voiceInputServiceProvider = Provider<VoiceInputService>((ref) {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    return NoopVoiceService();
  }
  return VoskVoiceService(
    ref.watch(voiceModelServiceProvider.notifier),
  );
});

final ocrServiceProvider = Provider<OcrService>(
  (ref) => kIsWeb ? NoopOcrService() : MlKitOcrService(),
);

final billingServiceProvider = Provider<BillingService>(
  (ref) => kIsWeb ? SimulatedBillingService() : InAppPurchaseBillingService(),
);

final deepLinkServiceProvider = Provider<DeepLinkService>(
  (ref) => DeepLinkService(),
);

final aiConnectionServiceProvider =
    Provider<AiConnectionService>((ref) => AiConnectionService());

/// «Умный» разбор заметки. По умолчанию — правила; при включённом ИИ
/// в настройках и валидной конфигурации — облачная LLM (YandexGPT,
/// GigaChat или OpenAI-совместимый провайдер) с фолбэком на правила.
final aiParserProvider = Provider<AiReminderParser>((ref) {
  final settings = ref.watch(settingsProvider).valueOrNull;
  final customs = settings?.customCategories ?? const [];
  final ruleParser = RuleBasedAiParser(customCategories: customs);
  if (settings == null || !AiClientFactory.isConfigured(settings)) {
    return ruleParser;
  }
  return LlmReminderParser(
    client: AiClientFactory.build(settings),
    customCategories: customs,
    fallback: ruleParser,
  );
});

final notesRepositoryProvider = Provider<NotesRepository>(
  (ref) => NotesRepository(
    ref.watch(jsonStoreProvider),
    ref.watch(notificationServiceProvider),
  ),
);

final familyRepositoryProvider = Provider<FamilyRepository>(
  (ref) => FamilyRepository(ref.watch(jsonStoreProvider)),
);

/// Состояние приложения.
final notesNotifierProvider =
    AsyncNotifierProvider<NotesNotifier, List<AppNote>>(NotesNotifier.new);

final settingsProvider =
    AsyncNotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

final familyNotifierProvider =
    AsyncNotifierProvider<FamilyBoardNotifier, List<FamilyMemberState>>(
        FamilyBoardNotifier.new);

/// UI-фильтры.
final homeDateFilterProvider = StateProvider<DateTime?>((ref) => null);
final familyAuthorFilterProvider = StateProvider<String?>((ref) => null);
final homeSearchQueryProvider = StateProvider<String>((ref) => '');
final homeCategoryFilterProvider = StateProvider<String?>((ref) => null);
