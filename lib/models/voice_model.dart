class VoiceModel {
  const VoiceModel({
    required this.name,
    required this.locale,
    required this.label,
  });

  final String name;
  final String locale;
  final String label;

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

    return VoiceModel(
      name: rawName,
      locale: rawLocale,
      label: label,
    );
  }

  Map<String, String> toTtsMap() => {
        'name': name,
        'locale': locale,
      };

  bool matchesIdentity(String? voiceName, String? voiceLocale) {
    return name == voiceName && locale == (voiceLocale ?? locale);
  }
}
