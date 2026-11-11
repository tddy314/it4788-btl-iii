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
    'enabled': enabled,
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
    final socialRaw = categories['SOCIAL'] ?? categories['social'];
    final academicRaw = categories['ACADEMIC'] ?? categories['academic'];
    final systemRaw = categories['SYSTEM'] ?? categories['system'];

    return PushSettings(
      pushEnabled: parseBool(json['push_enabled'] ?? true),
      social: socialRaw is Map<String, dynamic>
          ? PushCategoryConfig.fromJson(socialRaw)
          : const PushCategoryConfig(
              enabled: true,
              description: 'Mạng xã hội & Tin nhắn',
            ),
      academic: academicRaw is Map<String, dynamic>
          ? PushCategoryConfig.fromJson(academicRaw)
          : const PushCategoryConfig(
              enabled: true,
              description: 'Ngân hàng câu hỏi & Đề xuất',
            ),
      system: systemRaw is Map<String, dynamic>
          ? PushCategoryConfig.fromJson(systemRaw)
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
    'push_enabled': pushEnabled,
    'categories': {
      'SOCIAL': social.toJson(),
      'ACADEMIC': academic.toJson(),
      'SYSTEM': system.toJson(),
    },
    'sound_enabled': soundEnabled,
    'vibration_enabled': vibrationEnabled,
    'sound_type': soundType,
  };
}
