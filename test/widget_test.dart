// Этот файл намеренно существует до `flutter create`: генератор не
// перезаписывает существующие файлы, поэтому дефолтный widget_test.dart
// с несуществующим MyApp в проект не попадёт.
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_notes/core/utils/date_parser.dart';

void main() {
  testWidgets('smoke: приложение и его парсер собираются в test-окружении',
      (tester) async {
    final parser = NaturalDateParser(now: DateTime(2024, 12, 5, 10));
    expect(
      parser.parseReminder('завтра в 14:00'),
      DateTime(2024, 12, 6, 14),
    );
  });
}
