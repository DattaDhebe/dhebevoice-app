class VoiceModel {
  const VoiceModel({
    required this.name,
    required this.locale,
    required this.label,
    this.personaLabel,
    this.metadataLabels = const [],
  });

  final String name;
  final String locale;
  final String label;
  final String? personaLabel;
  final List<String> metadataLabels;

  String get selectionLabel {
    if (metadataLabels.isEmpty) {
      return label;
    }
    return '$label • ${metadataLabels.join(' • ')}';
  }

  String get detailsLabel {
    final details = [
      ?personaLabel,
      if (locale.isNotEmpty) locale,
      name,
    ];
    return details.join(' • ');
  }

  factory VoiceModel.fromMap(Map<String, dynamic> map) {
    final rawName = (map['name'] ?? map['voice'] ?? 'Unknown voice').toString();
    final rawLocale = (map['locale'] ?? map['language'] ?? '').toString();
    final segments = rawName
        .split(RegExp(r'[-_,]'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    final localePart = rawLocale.isEmpty ? 'Unknown locale' : rawLocale;
    final label = [
      if (segments.isNotEmpty) segments.first,
      if (segments.length > 1) ...segments.skip(1).take(2),
      localePart,
    ].join(', ');
    final personaLabel = _extractPersonaLabel(map, rawName);
    final metadataLabels = <String>[
      ?personaLabel,
      ..._extractMetadataLabels(map),
    ];

    return VoiceModel(
      name: rawName,
      locale: rawLocale,
      label: label,
      personaLabel: personaLabel,
      metadataLabels: metadataLabels,
    );
  }

  Map<String, String> toTtsMap() => {
        'name': name,
        'locale': locale,
      };

  bool matchesIdentity(String? voiceName, String? voiceLocale) {
    return name == voiceName && locale == (voiceLocale ?? locale);
  }

  static String? _extractPersonaLabel(
    Map<String, dynamic> map,
    String rawName,
  ) {
    final explicitGender = _normalizePersonaValue(
      map['gender']?.toString() ?? map['sex']?.toString(),
    );
    if (explicitGender != null) {
      return explicitGender;
    }

    final ageHint = _normalizePersonaValue(
      map['age']?.toString() ?? map['ageGroup']?.toString(),
    );
    if (ageHint == 'Child') {
      return ageHint;
    }

    final loweredName = rawName.toLowerCase();
    if (loweredName.contains('female') || loweredName.contains('woman')) {
      return 'Female';
    }
    if (loweredName.contains('male') || loweredName.contains('man')) {
      return 'Male';
    }
    if (loweredName.contains('child') ||
        loweredName.contains('kid') ||
        loweredName.contains('boy') ||
        loweredName.contains('girl')) {
      return 'Child';
    }
    return null;
  }

  static List<String> _extractMetadataLabels(Map<String, dynamic> map) {
    final labels = <String>{};
    final quality = _normalizeMetadataValue(map['quality']);
    final latency = _normalizeMetadataValue(map['latency']);
    final engine = _normalizeMetadataValue(map['engine']);

    if (quality != null) {
      labels.add(quality);
    }
    if (latency != null) {
      labels.add(latency);
    }
    if (engine != null) {
      labels.add(engine);
    }

    return labels.toList();
  }

  static String? _normalizePersonaValue(String? raw) {
    if (raw == null) {
      return null;
    }
    final normalized = raw.trim().toLowerCase();
    if (normalized.isEmpty) {
      return null;
    }
    if (normalized.contains('female') || normalized == 'f') {
      return 'Female';
    }
    if (normalized.contains('male') || normalized == 'm') {
      return 'Male';
    }
    if (normalized.contains('child') ||
        normalized.contains('kid') ||
        normalized.contains('boy') ||
        normalized.contains('girl')) {
      return 'Child';
    }
    return null;
  }

  static String? _normalizeMetadataValue(dynamic raw) {
    final value = raw?.toString().trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    if (value == 'null') {
      return null;
    }
    return value;
  }
}
