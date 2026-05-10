import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../models/voice_model.dart';
import 'file_import_service.dart';
import 'storage_service.dart';

enum ReaderPlaybackState { idle, playing, paused, stopped, completed, error }

class TtsService extends ChangeNotifier {
  TtsService({
    required StorageService storageService,
    required FileImportService fileImportService,
  })  : _storageService = storageService,
        _fileImportService = fileImportService;

  final StorageService _storageService;
  final FileImportService _fileImportService;
  final FlutterTts _flutterTts = FlutterTts();

  List<VoiceModel> _voices = const [];
  ReaderPlaybackState _playbackState = ReaderPlaybackState.idle;
  String _text = '';
  String _selectedLanguage = 'en-IN';
  VoiceModel? _selectedVoice;
  double _speechRate = 0.48;
  double _pitch = 1.0;
  double _volume = 1.0;
  String? _errorMessage;
  int _currentCharIndex = 0;
  int _currentParagraphIndex = 0;
  int _sessionId = 0;
  int _activeChunkOffset = 0;
  bool _engineReady = false;
  Future<void> Function()? _playbackCompletedHandler;

  List<VoiceModel> get voices => _voices;
  ReaderPlaybackState get playbackState => _playbackState;
  String get text => _text;
  String get selectedLanguage => _selectedLanguage;
  VoiceModel? get selectedVoice => _selectedVoice;
  double get speechRate => _speechRate;
  double get pitch => _pitch;
  double get volume => _volume;
  String? get errorMessage => _errorMessage;
  int get currentCharIndex => _currentCharIndex;
  int get currentParagraphIndex => _currentParagraphIndex;
  List<String> get paragraphs => List.unmodifiable(_paragraphsFromText(_text));
  int get paragraphCount => paragraphs.length;

  bool get isPlaying => _playbackState == ReaderPlaybackState.playing;
  bool get isPaused => _playbackState == ReaderPlaybackState.paused;

  void setPlaybackCompletedHandler(Future<void> Function()? handler) {
    _playbackCompletedHandler = handler;
  }

  String get currentParagraph {
    final items = paragraphs;
    if (items.isEmpty) {
      return 'Paste text, import a .txt file, or share text into the app.';
    }

    final index = min(_currentParagraphIndex, items.length - 1);
    return items[index].trim();
  }

  Future<void> initialize() async {
    _text = _storageService.text;
    _speechRate = _storageService.rate;
    _pitch = _storageService.pitch;
    _volume = _storageService.volume;
    _currentCharIndex = _storageService.position;

    await _configureTts();
    await _loadVoices();
    await _applyStoredSelections();
    await _syncTtsOptions();

    if (_text.isNotEmpty) {
      _currentParagraphIndex = _paragraphIndexForOffset(_currentCharIndex);
    }

    notifyListeners();
  }

  Future<void> _configureTts() async {
    try {
      await _flutterTts.awaitSpeakCompletion(true);
      await _flutterTts.setQueueMode(0);

      _flutterTts.setStartHandler(() {
        _playbackState = ReaderPlaybackState.playing;
        _errorMessage = null;
        notifyListeners();
      });

      _flutterTts.setErrorHandler((message) {
        _playbackState = ReaderPlaybackState.error;
        _errorMessage = 'TTS error: $message';
        notifyListeners();
      });

      _flutterTts.setProgressHandler((text, start, end, word) {
        _currentCharIndex = max(0, _activeChunkOffset + start);
        _currentParagraphIndex = _paragraphIndexForOffset(_currentCharIndex);
        unawaited(_storageService.savePosition(_currentCharIndex));
        notifyListeners();
      });

      _engineReady = true;
    } catch (_) {
      _engineReady = false;
      _errorMessage =
          'No Android text-to-speech engine is available on this device yet.';
    }
  }

  Future<void> _loadVoices() async {
    if (!_engineReady) {
      _voices = const [];
      return;
    }

    final rawVoices = await _flutterTts.getVoices;
    final voiceMaps = (rawVoices as List<dynamic>)
        .whereType<Map<dynamic, dynamic>>()
        .map(
          (entry) => entry.map(
            (key, value) => MapEntry(key.toString(), value),
          ),
        )
        .map(VoiceModel.fromMap)
        .where((voice) => voice.locale.isNotEmpty)
        .toList()
      ..sort((a, b) => a.label.compareTo(b.label));

    _voices = voiceMaps;
  }

  Future<void> _applyStoredSelections() async {
    final storedLanguage = _storageService.language;
    final storedVoiceName = _storageService.voiceName;
    final storedVoiceLocale = _storageService.voiceLocale;
    final defaultLanguage = _preferredLanguageFromVoices();

    _selectedLanguage = storedLanguage ?? defaultLanguage ?? 'en-IN';

    _selectedVoice = _voices.cast<VoiceModel?>().firstWhere(
          (voice) => voice!.matchesIdentity(storedVoiceName, storedVoiceLocale),
          orElse: () => _defaultVoiceForLanguage(_selectedLanguage),
        );

    if (_selectedVoice != null) {
      _selectedLanguage = _selectedVoice!.locale;
    }
  }

  String? _preferredLanguageFromVoices() {
    final preferred = _voices
        .where((voice) => _isEnglishIndia(voice.locale))
        .map((voice) => voice.locale)
        .toList();
    if (preferred.isNotEmpty) {
      return preferred.first;
    }
    return _voices.isNotEmpty ? _voices.first.locale : null;
  }

  VoiceModel? _defaultVoiceForLanguage(String language) {
    if (_voices.isEmpty) {
      return null;
    }

    for (final voice in _voices) {
      if (voice.locale.toLowerCase() == language.toLowerCase()) {
        return voice;
      }
    }

    if (_isEnglishIndia(language)) {
      return _voices.firstWhere(
        (voice) => _isEnglishIndia(voice.locale),
        orElse: () => _voices.first,
      );
    }

    return _voices.first;
  }

  bool _isEnglishIndia(String locale) {
    final normalized = locale.toLowerCase().replaceAll('_', '-');
    return normalized == 'en-in' || normalized.startsWith('en-in-');
  }

  Future<void> _syncTtsOptions() async {
    if (!_engineReady) {
      return;
    }

    await _flutterTts.setLanguage(_selectedLanguage);
    await _flutterTts.setSpeechRate(_speechRate);
    await _flutterTts.setPitch(_pitch);
    await _flutterTts.setVolume(_volume);

    if (_selectedVoice != null) {
      await _flutterTts.setVoice(_selectedVoice!.toTtsMap());
    }
  }

  Future<void> updateText(String value, {bool resetPosition = false}) async {
    _text = value;
    if (resetPosition || _currentCharIndex > _text.length) {
      _currentCharIndex = 0;
      _currentParagraphIndex = 0;
    } else {
      _currentParagraphIndex = _paragraphIndexForOffset(_currentCharIndex);
    }

    await _storageService.saveText(value);
    await _storageService.savePosition(_currentCharIndex);
    notifyListeners();
  }

  Future<void> importTextFile() async {
    final imported = await _fileImportService.importTextFile();
    if (imported == null || imported.trim().isEmpty) {
      return;
    }

    await stop();
    await updateText(imported.trim(), resetPosition: true);
  }

  Future<void> handleSharedText(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return;
    }

    await stop();
    await updateText(trimmed, resetPosition: true);
  }

  Future<void> setLanguage(String value) async {
    _selectedLanguage = value;
    _selectedVoice = _defaultVoiceForLanguage(value);
    await _storageService.saveLanguage(value);
    await _storageService.saveVoice(
      _selectedVoice?.name,
      _selectedVoice?.locale,
    );
    await _syncTtsOptions();
    notifyListeners();
  }

  Future<void> setVoice(VoiceModel? voice) async {
    _selectedVoice = voice;
    if (voice != null) {
      _selectedLanguage = voice.locale;
      await _storageService.saveLanguage(voice.locale);
    }
    await _storageService.saveVoice(voice?.name, voice?.locale);
    await _syncTtsOptions();
    notifyListeners();
  }

  Future<void> setSpeechRate(double value) async {
    _speechRate = value;
    await _storageService.saveRate(value);
    await _flutterTts.setSpeechRate(value);
    notifyListeners();
  }

  Future<void> setPitch(double value) async {
    _pitch = value;
    await _storageService.savePitch(value);
    await _flutterTts.setPitch(value);
    notifyListeners();
  }

  Future<void> setVolume(double value) async {
    _volume = value;
    await _storageService.saveVolume(value);
    await _flutterTts.setVolume(value);
    notifyListeners();
  }

  Future<void> play() async {
    await _playInternal(
      startOffset: _currentCharIndex,
      endOffset: null,
      triggerCompletionHandler: true,
      resetPositionOnComplete: true,
    );
  }

  Future<void> playSelection(TextSelection selection) async {
    final normalizedSelection = _normalizedSelection(selection);
    if (normalizedSelection == null) {
      _errorMessage = 'Select some text before using Play selection.';
      _playbackState = ReaderPlaybackState.error;
      notifyListeners();
      return;
    }

    _currentCharIndex = normalizedSelection.start;
    _currentParagraphIndex = _paragraphIndexForOffset(_currentCharIndex);
    await _storageService.savePosition(_currentCharIndex);
    notifyListeners();

    await _playInternal(
      startOffset: normalizedSelection.start,
      endOffset: normalizedSelection.end,
      triggerCompletionHandler: false,
      resetPositionOnComplete: false,
    );
  }

  Future<void> playFromParagraph(int paragraphIndex) async {
    if (paragraphIndex < 0 || paragraphIndex >= paragraphCount) {
      return;
    }

    final paragraphOffset = _offsetForParagraph(paragraphIndex);
    _currentCharIndex = paragraphOffset;
    _currentParagraphIndex = paragraphIndex;
    await _storageService.savePosition(_currentCharIndex);
    notifyListeners();

    await _playInternal(
      startOffset: paragraphOffset,
      endOffset: null,
      triggerCompletionHandler: true,
      resetPositionOnComplete: true,
    );
  }

  Future<void> _playInternal({
    required int startOffset,
    required int? endOffset,
    required bool triggerCompletionHandler,
    required bool resetPositionOnComplete,
  }) async {
    if (!_engineReady) {
      _errorMessage =
          'Android text-to-speech is not available. Install or enable a TTS engine first.';
      _playbackState = ReaderPlaybackState.error;
      notifyListeners();
      return;
    }

    if (_voices.isEmpty) {
      _errorMessage =
          'No installed TTS voices were found. Add a voice in Android system settings and try again.';
      _playbackState = ReaderPlaybackState.error;
      notifyListeners();
      return;
    }

    final trimmed = _text.trim();
    if (trimmed.isEmpty) {
      _errorMessage = 'Add or import some text before starting playback.';
      _playbackState = ReaderPlaybackState.error;
      notifyListeners();
      return;
    }

    _errorMessage = null;
    final localSession = ++_sessionId;
    _playbackState = ReaderPlaybackState.playing;
    notifyListeners();

    await _syncTtsOptions();
    await _flutterTts.stop();

    final chunks = _buildChunks(
      _text,
      startOffset: startOffset,
      endOffset: endOffset,
    );
    if (chunks.isEmpty) {
      _playbackState = ReaderPlaybackState.completed;
      _currentCharIndex = resetPositionOnComplete ? 0 : startOffset;
      _currentParagraphIndex = _paragraphIndexForOffset(_currentCharIndex);
      await _storageService.savePosition(_currentCharIndex);
      notifyListeners();
      return;
    }

    for (final chunk in chunks) {
      if (localSession != _sessionId ||
          _playbackState != ReaderPlaybackState.playing) {
        return;
      }

      _activeChunkOffset = chunk.start;
      _currentParagraphIndex = chunk.paragraphIndex;
      notifyListeners();

      final result = await _flutterTts.speak(chunk.text);
      if (result != 1) {
        _playbackState = ReaderPlaybackState.error;
        _errorMessage =
            'DhebeVoice could not start the selected voice. Try another installed voice.';
        notifyListeners();
        return;
      }

      _currentCharIndex = chunk.end;
      await _storageService.savePosition(_currentCharIndex);
    }

    if (localSession == _sessionId) {
      _playbackState = ReaderPlaybackState.completed;
      _currentCharIndex = resetPositionOnComplete
          ? 0
          : min(endOffset ?? _currentCharIndex, _text.length);
      _currentParagraphIndex = _paragraphIndexForOffset(_currentCharIndex);
      await _storageService.savePosition(_currentCharIndex);
      notifyListeners();
      final handler = _playbackCompletedHandler;
      if (triggerCompletionHandler && handler != null) {
        unawaited(handler());
      }
    }
  }

  Future<void> pause() async {
    if (!isPlaying) {
      return;
    }

    _sessionId++;
    _playbackState = ReaderPlaybackState.paused;
    await _flutterTts.stop();
    await _storageService.savePosition(_currentCharIndex);
    notifyListeners();
  }

  Future<void> stop() async {
    _sessionId++;
    _playbackState = ReaderPlaybackState.stopped;
    _currentCharIndex = 0;
    _currentParagraphIndex = 0;
    await _flutterTts.stop();
    await _storageService.savePosition(0);
    notifyListeners();
  }

  List<String> availableLanguages() {
    final locales = _voices.map((voice) => voice.locale).toSet().toList()
      ..sort();
    return locales;
  }

  int _paragraphIndexForOffset(int offset) {
    final paragraphs = _paragraphsFromText(_text);
    if (paragraphs.isEmpty) {
      return 0;
    }

    var runningOffset = 0;
    for (var i = 0; i < paragraphs.length; i++) {
      final paragraph = paragraphs[i];
      final end = runningOffset + paragraph.length;
      if (offset <= end) {
        return i;
      }
      runningOffset = end + 2;
    }
    return paragraphs.length - 1;
  }

  List<String> _paragraphsFromText(String source) {
    return source
        .split(RegExp(r'\n\s*\n'))
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty)
        .toList();
  }

  List<_SpeechChunk> _buildChunks(
    String source, {
    required int startOffset,
    int? endOffset,
  }) {
    final chunks = <_SpeechChunk>[];
    final paragraphs = source.split(RegExp(r'\n\s*\n'));
    var paragraphIndex = 0;
    var offset = 0;

    for (final rawParagraph in paragraphs) {
      final paragraph = rawParagraph.trim();
      final paragraphStart = offset;
      offset += rawParagraph.length + 2;

      if (paragraph.isEmpty) {
        continue;
      }

      if (endOffset != null && paragraphStart >= endOffset) {
        break;
      }

      if (paragraphStart + paragraph.length < startOffset) {
        paragraphIndex++;
        continue;
      }

      final localStart = max(0, startOffset - paragraphStart);
      final localEnd = endOffset == null
          ? paragraph.length
          : min(paragraph.length, max(0, endOffset - paragraphStart));
      if (localEnd <= localStart) {
        paragraphIndex++;
        continue;
      }
      final paragraphText = paragraph.substring(
        min(localStart, paragraph.length),
        localEnd,
      );

      final pieces = _splitChunk(paragraphText);
      var chunkOffset = paragraphStart + localStart;
      for (final piece in pieces) {
        chunks.add(
          _SpeechChunk(
            text: piece,
            start: chunkOffset,
            end: chunkOffset + piece.length,
            paragraphIndex: paragraphIndex,
          ),
        );
        chunkOffset += piece.length;
      }

      paragraphIndex++;
    }

    return chunks;
  }

  TextSelection? _normalizedSelection(TextSelection selection) {
    if (!selection.isValid || selection.isCollapsed || _text.isEmpty) {
      return null;
    }

    final start = min(selection.start, selection.end);
    final end = max(selection.start, selection.end);
    if (start < 0 || end > _text.length || start >= end) {
      return null;
    }

    return TextSelection(baseOffset: start, extentOffset: end);
  }

  int _offsetForParagraph(int targetIndex) {
    final rawParagraphs = _text.split(RegExp(r'\n\s*\n'));
    var paragraphIndex = 0;
    var offset = 0;

    for (final rawParagraph in rawParagraphs) {
      final paragraph = rawParagraph.trim();
      final paragraphStart = offset;
      offset += rawParagraph.length + 2;

      if (paragraph.isEmpty) {
        continue;
      }
      if (paragraphIndex == targetIndex) {
        return paragraphStart;
      }
      paragraphIndex++;
    }

    return 0;
  }

  List<String> _splitChunk(String paragraph) {
    const maxChunkLength = 2800;
    if (paragraph.length <= maxChunkLength) {
      return [paragraph];
    }

    final chunks = <String>[];
    var buffer = paragraph;
    while (buffer.length > maxChunkLength) {
      var splitIndex =
          buffer.lastIndexOf(RegExp(r'[.!?]\s'), maxChunkLength);
      splitIndex = splitIndex <= 0
          ? buffer.lastIndexOf(' ', maxChunkLength)
          : splitIndex + 1;
      splitIndex = splitIndex <= 0 ? maxChunkLength : splitIndex;
      chunks.add(buffer.substring(0, splitIndex).trim());
      buffer = buffer.substring(splitIndex).trimLeft();
    }
    if (buffer.isNotEmpty) {
      chunks.add(buffer);
    }
    return chunks;
  }
}

class _SpeechChunk {
  const _SpeechChunk({
    required this.text,
    required this.start,
    required this.end,
    required this.paragraphIndex,
  });

  final String text;
  final int start;
  final int end;
  final int paragraphIndex;
}
