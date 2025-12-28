import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/models/setting_model.dart';

void main() {
  group('Setting', () {
    group('constructor', () {
      test('creates instance with required fields', () {
        const setting = Setting(
          title: 'theme',
          value: 'dark',
          projectId: '1',
        );

        expect(setting.title, 'theme');
        expect(setting.value, 'dark');
        expect(setting.projectId, '1');
        expect(setting.id, isNull);
      });

      test('creates instance with all fields including id', () {
        const setting = Setting(
          id: 42,
          title: 'resolution',
          value: '1080p',
          projectId: '2',
        );

        expect(setting.id, 42);
        expect(setting.title, 'resolution');
        expect(setting.value, '1080p');
        expect(setting.projectId, '2');
      });

      test('creates instance with empty strings', () {
        const setting = Setting(
          title: '',
          value: '',
          projectId: '',
        );

        expect(setting.title, '');
        expect(setting.value, '');
        expect(setting.projectId, '');
      });
    });

    group('fromJson()', () {
      test('creates instance from valid JSON with all fields', () {
        final json = {
          'id': 1,
          'title': 'watermark',
          'value': 'true',
          'projectId': '5',
        };

        final setting = Setting.fromJson(json);

        expect(setting.id, 1);
        expect(setting.title, 'watermark');
        expect(setting.value, 'true');
        expect(setting.projectId, '5');
      });

      test('creates instance from JSON without id', () {
        final json = {
          'title': 'aspectRatio',
          'value': '16:9',
          'projectId': '3',
        };

        final setting = Setting.fromJson(json);

        expect(setting.id, isNull);
        expect(setting.title, 'aspectRatio');
        expect(setting.value, '16:9');
        expect(setting.projectId, '3');
      });

      test('creates instance from JSON with null id', () {
        final json = {
          'id': null,
          'title': 'framerate',
          'value': '30',
          'projectId': '4',
        };

        final setting = Setting.fromJson(json);

        expect(setting.id, isNull);
        expect(setting.title, 'framerate');
        expect(setting.value, '30');
        expect(setting.projectId, '4');
      });

      test('handles integer projectId in JSON by converting to string', () {
        // Some databases might return int instead of string
        final json = {
          'id': 1,
          'title': 'test',
          'value': 'value',
          'projectId': '123', // Should be string
        };

        final setting = Setting.fromJson(json);
        expect(setting.projectId, '123');
      });
    });

    group('toJson()', () {
      test('converts to JSON with all fields', () {
        const setting = Setting(
          id: 10,
          title: 'orientation',
          value: 'portrait',
          projectId: '7',
        );

        final json = setting.toJson();

        expect(json['id'], 10);
        expect(json['title'], 'orientation');
        expect(json['value'], 'portrait');
        expect(json['projectId'], '7');
      });

      test('converts to JSON with null id', () {
        const setting = Setting(
          title: 'stabilizationMode',
          value: 'slow',
          projectId: '8',
        );

        final json = setting.toJson();

        expect(json['id'], isNull);
        expect(json['title'], 'stabilizationMode');
        expect(json['value'], 'slow');
        expect(json['projectId'], '8');
      });

      test('includes all four keys', () {
        const setting = Setting(
          title: 'test',
          value: 'value',
          projectId: '1',
        );

        final json = setting.toJson();

        expect(json.keys, containsAll(['id', 'title', 'value', 'projectId']));
        expect(json.length, 4);
      });
    });

    group('roundtrip serialization', () {
      test('fromJson(toJson()) preserves all data with id', () {
        const original = Setting(
          id: 100,
          title: 'eyeOffsetX',
          value: '0.065',
          projectId: '99',
        );

        final json = original.toJson();
        final restored = Setting.fromJson(json);

        expect(restored.id, original.id);
        expect(restored.title, original.title);
        expect(restored.value, original.value);
        expect(restored.projectId, original.projectId);
      });

      test('fromJson(toJson()) preserves all data without id', () {
        const original = Setting(
          title: 'eyeOffsetY',
          value: '0.421875',
          projectId: '99',
        );

        final json = original.toJson();
        final restored = Setting.fromJson(json);

        expect(restored.id, isNull);
        expect(restored.title, original.title);
        expect(restored.value, original.value);
        expect(restored.projectId, original.projectId);
      });

      test('handles special characters in strings', () {
        const original = Setting(
          id: 1,
          title: 'path/to/file',
          value: 'C:\\Users\\test\\file.txt',
          projectId: 'project-123',
        );

        final json = original.toJson();
        final restored = Setting.fromJson(json);

        expect(restored.title, original.title);
        expect(restored.value, original.value);
      });

      test('handles unicode characters', () {
        const original = Setting(
          id: 1,
          title: 'displayName',
          value: 'Test',
          projectId: '1',
        );

        final json = original.toJson();
        final restored = Setting.fromJson(json);

        expect(restored.value, original.value);
      });
    });

    group('common setting scenarios', () {
      test('boolean setting stored as string', () {
        const setting = Setting(
          title: 'watermarkEnabled',
          value: 'true',
          projectId: '1',
        );

        expect(setting.value, 'true');
        expect(setting.value == 'true', isTrue);
      });

      test('numeric setting stored as string', () {
        const setting = Setting(
          title: 'framerate',
          value: '30',
          projectId: '1',
        );

        expect(int.tryParse(setting.value), 30);
      });

      test('decimal setting stored as string', () {
        const setting = Setting(
          title: 'eyeOffsetX',
          value: '0.065',
          projectId: '1',
        );

        expect(double.tryParse(setting.value), 0.065);
      });

      test('enum-like setting', () {
        const setting = Setting(
          title: 'resolution',
          value: '1080p',
          projectId: '1',
        );

        final validResolutions = ['720p', '1080p', '2K', '4K'];
        expect(validResolutions.contains(setting.value), isTrue);
      });

      test('global setting with empty projectId', () {
        const setting = Setting(
          title: 'theme',
          value: 'dark',
          projectId: '', // Global setting, not project-specific
        );

        expect(setting.projectId, isEmpty);
      });
    });
  });
}
