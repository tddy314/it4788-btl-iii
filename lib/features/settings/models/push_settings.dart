class PushCategoryConfig {
  const PushCategoryConfig({required this.enabled, this.description = ''});

  final bool enabled;
  final String description;

  PushCategoryConfig copyWith({bool? enabled, String? description}) =>
      PushCategoryConfig(
        enabled: enabled ?? this.enabled,
        description: description ?? this.description,
      );

  factory PushCategoryConfig.fromJson(Map<String, dynamic> json) {
    final enabledVal = json['enabled'];
    final isEnabled =
        enabledVal == true || enabledVal?.toString().toLowerCase() == 'true';
    return PushCategoryConfig(
      enabled: isEnabled,
      description: json['description'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled ? 'true' : 'false',
    'description': description,
  };
}

class PushSettings {
  const PushSettings({
    required this.pushEnabled,
    required this.social,
    required this.academic,
    required this.system,
    required this.soundEnabled,
    required this.vibrationEnabled,
    this.soundType =
        'default', // 'default' hoặc 'voice' theo yêu cầu Slide 26 & 29
  });

  final bool pushEnabled;
  final PushCategoryConfig social;
  final PushCategoryConfig academic;
  final PushCategoryConfig system;
  final bool soundEnabled;
  final bool vibrationEnabled;
  final String soundType;

  PushSettings copyWith({
    bool? pushEnabled,
    PushCategoryConfig? social,
    PushCategoryConfig? academic,
    PushCategoryConfig? system,
    bool? soundEnabled,
    bool? vibrationEnabled,
    String? soundType,
  }) => PushSettings(
    pushEnabled: pushEnabled ?? this.pushEnabled,
    social: social ?? this.social,
    academic: academic ?? this.academic,
    system: system ?? this.system,
    soundEnabled: soundEnabled ?? this.soundEnabled,
    vibrationEnabled: vibrationEnabled ?? this.vibrationEnabled,
    soundType: soundType ?? this.soundType,
  );

  factory PushSettings.defaults() => const PushSettings(
    pushEnabled: true,
    social: PushCategoryConfig(
      enabled: true,
      description: 'Mạng xã hội & Tin nhắn',
    ),
    academic: PushCategoryConfig(
      enabled: true,
      description: 'Ngân hàng câu hỏi & Đề xuất',
    ),
    system: PushCategoryConfig(
      enabled: true,
      description: 'Thông báo hệ thống',
    ),
    soundEnabled: true,
    vibrationEnabled: true,
    soundType: 'default',
  );

  factory PushSettings.fromJson(Map<String, dynamic> json) {
    bool parseBool(dynamic val) =>
        val == true || val?.toString().toLowerCase() == 'true';

    final categories = json['categories'] as Map<String, dynamic>? ?? {};

    return PushSettings(
      pushEnabled: parseBool(json['push_enabled'] ?? true),
      social: categories['social'] is Map<String, dynamic>
          ? PushCategoryConfig.fromJson(
              categories['social'] as Map<String, dynamic>,
            )
          : const PushCategoryConfig(
              enabled: true,
              description: 'Mạng xã hội & Tin nhắn',
            ),
      academic: categories['academic'] is Map<String, dynamic>
          ? PushCategoryConfig.fromJson(
              categories['academic'] as Map<String, dynamic>,
            )
          : const PushCategoryConfig(
              enabled: true,
              description: 'Ngân hàng câu hỏi & Đề xuất',
            ),
      system: categories['system'] is Map<String, dynamic>
          ? PushCategoryConfig.fromJson(
              categories['system'] as Map<String, dynamic>,
            )
          : const PushCategoryConfig(
              enabled: true,
              description: 'Thông báo hệ thống',
            ),
      soundEnabled: parseBool(json['sound_enabled'] ?? true),
      vibrationEnabled: parseBool(json['vibration_enabled'] ?? true),
      soundType: json['sound_type'] as String? ?? 'default',
    );
  }

  Map<String, dynamic> toJson() => {
    'push_enabled': pushEnabled ? 'true' : 'false',
    'categories': {
      'social': social.toJson(),
      'academic': academic.toJson(),
      'system': system.toJson(),
    },
    'sound_enabled': soundEnabled ? 'true' : 'false',
    'vibration_enabled': vibrationEnabled ? 'true' : 'false',
    'sound_type': soundType,
  };
}
