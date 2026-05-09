import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static const _textKey = 'reader_text';
  static const _languageKey = 'reader_language';
  static const _voiceNameKey = 'reader_voice_name';
  static const _voiceLocaleKey = 'reader_voice_locale';
  static const _rateKey = 'reader_rate';
  static const _pitchKey = 'reader_pitch';
  static const _volumeKey = 'reader_volume';
  static const _positionKey = 'reader_position';

  late final SharedPreferences _prefs;

  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
  }

  String get text => _prefs.getString(_textKey) ?? '';
  String? get language => _prefs.getString(_languageKey);
  String? get voiceName => _prefs.getString(_voiceNameKey);
  String? get voiceLocale => _prefs.getString(_voiceLocaleKey);
  double get rate => _prefs.getDouble(_rateKey) ?? 0.48;
  double get pitch => _prefs.getDouble(_pitchKey) ?? 1.0;
  double get volume => _prefs.getDouble(_volumeKey) ?? 1.0;
  int get position => _prefs.getInt(_positionKey) ?? 0;

  Future<void> saveText(String value) => _prefs.setString(_textKey, value);
  Future<void> saveLanguage(String value) =>
      _prefs.setString(_languageKey, value);

  Future<void> saveVoice(String? name, String? locale) async {
    if (name == null || locale == null) {
      await _prefs.remove(_voiceNameKey);
      await _prefs.remove(_voiceLocaleKey);
      return;
    }

    await _prefs.setString(_voiceNameKey, name);
    await _prefs.setString(_voiceLocaleKey, locale);
  }

  Future<void> saveRate(double value) => _prefs.setDouble(_rateKey, value);
  Future<void> savePitch(double value) => _prefs.setDouble(_pitchKey, value);
  Future<void> saveVolume(double value) => _prefs.setDouble(_volumeKey, value);
  Future<void> savePosition(int value) => _prefs.setInt(_positionKey, value);
}
