import 'package:flutter_test/flutter_test.dart';
import 'package:it4788_btl/features/settings/models/push_settings.dart';

void main() {
  group('Push Settings Model (Yêu cầu IT4788 Slide 26, 29, 197-200)', () {
    test('PushSettings parses server JSON correctly', () {
      final json = {
        'push_enabled': 'true',
        'categories': {
          'social': {'enabled': 'true', 'description': 'Mạng xã hội'},
          'academic': {'enabled': 'false', 'description': 'Ngân hàng đề'},
          'system': {'enabled': 'true', 'description': 'Hệ thống'},
        },
        'sound_enabled': 'true',
        'vibration_enabled': 'false',
        'sound_type': 'voice',
      };

      final settings = PushSettings.fromJson(json);

      expect(settings.pushEnabled, isTrue);
      expect(settings.social.enabled, isTrue);
      expect(settings.academic.enabled, isFalse);
      expect(settings.system.enabled, isTrue);
      expect(settings.soundEnabled, isTrue);
      expect(settings.vibrationEnabled, isFalse);
      expect(settings.soundType, 'voice');
    });

    test('PushSettings serializes to valid server format', () {
      final settings = PushSettings.defaults().copyWith(
        soundType: 'voice',
        pushEnabled: false,
      );

      final json = settings.toJson();

      expect(json['push_enabled'], 'false');
      expect(json['sound_type'], 'voice');
      expect(json['categories'], isA<Map<String, dynamic>>());
    });
  });
}
