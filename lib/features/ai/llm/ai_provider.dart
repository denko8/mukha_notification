/// Поддерживаемые облачные LLM-провайдеры.
enum AiProvider {
  openaiCompatible('OpenAI-совместимый'),
  yandexGpt('YandexGPT'),
  gigaChat('GigaChat');

  final String label;
  const AiProvider(this.label);

  static AiProvider fromName(String? name) => AiProvider.values.firstWhere(
        (p) => p.name == name,
        orElse: () => AiProvider.openaiCompatible,
      );
}
