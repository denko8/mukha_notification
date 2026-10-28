import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Распознавание текста на изображениях (P3 ТЗ: счета, билеты, документы).
abstract class OcrService {
  /// Возвращает распознанный текст либо бросает [OcrUnsupportedException].
  Future<String> extractTextFromImage(String imagePath);
}

class OcrUnsupportedException implements Exception {
  final String message;
  OcrUnsupportedException([this.message = 'OCR недоступен на этой платформе']);
  @override
  String toString() => message;
}

class MlKitOcrService implements OcrService {
  @override
  Future<String> extractTextFromImage(String imagePath) async {
    // ML Kit — только нативные мобильные платформы.
    if (kIsWeb) {
      throw OcrUnsupportedException('OCR работает только в Android/iOS приложении');
    }
    final recognizer = TextRecognizer(script: TextRecognitionScript.cyrillic);
    try {
      final input = InputImage.fromFilePath(imagePath);
      final result = await recognizer.processImage(input);
      return result.text.trim();
    } finally {
      await recognizer.close();
    }
  }
}

class NoopOcrService implements OcrService {
  @override
  Future<String> extractTextFromImage(String imagePath) async =>
      throw OcrUnsupportedException();
}
