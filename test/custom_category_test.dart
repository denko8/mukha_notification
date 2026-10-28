import 'package:flutter_test/flutter_test.dart';
import 'package:smart_notes/features/notes/models/custom_category.dart';
import 'package:smart_notes/features/notes/models/note_category.dart';
import 'package:smart_notes/features/notes/utils/category_catalog.dart';
import 'package:smart_notes/features/settings/models/app_settings.dart';

void main() {
  group('CategoryKeys', () {
    test('ключи пользовательских категорий имеют префикс custom:', () {
      final key = CategoryKeys.forCustom('abc-123');
      expect(key, 'custom:abc-123');
      expect(CategoryKeys.isCustom(key), isTrue);
      expect(CategoryKeys.customIdOf(key), 'abc-123');
      expect(CategoryKeys.isCustom('work'), isFalse);
    });

    test('встроенные категории резолвятся по имени enum', () {
      expect(CategoryKeys.builtInByKey('shopping'), NoteCategory.shopping);
      expect(CategoryKeys.builtInByKey('custom:xyz'), isNull);
      expect(CategoryKeys.builtInByKey('nope'), isNull);
    });
  });

  group('CustomCategory', () {
    test('сериализация в Map и обратно сохраняет все поля', () {
      const original = CustomCategory(
        id: 'id-1',
        label: 'Рыбалка',
        keywords: ['рыбалк', 'спиннинг'],
      );
      final restored = CustomCategory.fromMap(original.toMap());
      expect(restored.id, 'id-1');
      expect(restored.label, 'Рыбалка');
      expect(restored.keywords, ['рыбалк', 'спиннинг']);
    });

    test('терпит отсутствие keywords в старых данных', () {
      final restored = CustomCategory.fromMap({'id': 'x', 'label': 'Тест'});
      expect(restored.keywords, isEmpty);
    });

    test('copyWith меняет только переданные поля', () {
      const c = CustomCategory(id: 'id', label: 'Старое');
      final updated = c.copyWith(label: 'Новое', keywords: ['ключ']);
      expect(updated.id, 'id');
      expect(updated.label, 'Новое');
      expect(updated.keywords, ['ключ']);
    });
  });

  group('CategoryCatalog', () {
    const customs = [
      CustomCategory(id: 'fish', label: 'Рыбалка', keywords: ['рыбалк']),
      CustomCategory(id: 'car', label: 'Машина', keywords: []),
    ];
    const catalog = CategoryCatalog(customs);

    test('allKeys: сначала встроенные, затем пользовательские', () {
      final keys = catalog.allKeys;
      expect(keys.first, NoteCategory.general.name);
      expect(keys, contains('work'));
      expect(keys, contains('custom:fish'));
      expect(keys, contains('custom:car'));
      expect(keys.length, NoteCategory.values.length + 2);
    });

    test('labelOf/iconOf резолвят оба вида ключей', () {
      expect(catalog.labelOf('work'), 'Работа');
      expect(catalog.labelOf('custom:fish'), 'Рыбалка');
      expect(catalog.iconOf('custom:fish'), isNotNull);
    });

    test('ключ удалённой категории безопасно превращается в «Общее»', () {
      expect(catalog.labelOf('custom:deleted'), 'Общее');
      expect(catalog.contains('custom:deleted'), isFalse);
      expect(catalog.contains('custom:fish'), isTrue);
      expect(catalog.contains('health'), isTrue);
    });

    test('keyByLabel находит и встроенные, и свои категории', () {
      expect(catalog.keyByLabel('Работа'), 'work');
      expect(catalog.keyByLabel('рыбалка'), 'custom:fish');
      expect(catalog.keyByLabel('  Машина '), 'custom:car');
      expect(catalog.keyByLabel('Несуществующее'), isNull);
      expect(catalog.keyByLabel(''), isNull);
    });

    test('названия не должны дублироваться', () {
      expect(catalog.isLabelTaken('Работа'), isTrue); // встроенная
      expect(catalog.isLabelTaken('рыбалка'), isTrue); // своя, любой регистр
      expect(catalog.isLabelTaken('Рыбалка', excludeId: 'fish'), isFalse);
      expect(catalog.isLabelTaken('Огород'), isFalse);
      expect(catalog.isLabelTaken(''), isFalse);
    });
  });

  group('AppSettings.customCategories', () {
    test('полный roundtrip через toMap/fromMap', () {
      const settings = AppSettings(
        customCategories: [
          CustomCategory(id: 'a', label: 'Дача', keywords: ['дач', 'грядк']),
        ],
      );
      final restored = AppSettings.fromMap(settings.toMap());
      expect(restored.customCategories.single.id, 'a');
      expect(restored.customCategories.single.label, 'Дача');
      expect(restored.customCategories.single.keywords, ['дач', 'грядк']);
    });

    test('старые настройки без поля читаются с пустым списком', () {
      final restored = AppSettings.fromMap({'profileName': 'Я'});
      expect(restored.customCategories, isEmpty);
    });

    test('copyWith заменяет список целиком', () {
      const settings = AppSettings(
        customCategories: [CustomCategory(id: 'a', label: 'A')],
      );
      final updated = settings.copyWith(
        customCategories: const [
          CustomCategory(id: 'b', label: 'B'),
          CustomCategory(id: 'c', label: 'C'),
        ],
      );
      expect(updated.customCategories.map((e) => e.id), ['b', 'c']);
      // Неизменённые поля сохранились.
      expect(updated.profileName, settings.profileName);
    });
  });
}
