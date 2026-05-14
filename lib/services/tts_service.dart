import 'dart:async';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../models/voice_model.dart';
import 'file_import_service.dart';
import 'storage_service.dart';

enum ReaderPlaybackState { idle, playing, paused, stopped, completed, error }

class TtsService extends ChangeNotifier {
  static const _defaultLanguage = 'en-IN';
  static const _defaultVoicePattern = 'en-in-x-ene-local';
  static const _defaultSpeechRate = 0.48;
  static const _defaultPitch = 1.0;
  static const _defaultVolume = 1.0;
  static const _watchdogCheckInterval = Duration(seconds: 4);
  static const _watchdogTimeout = Duration(seconds: 12);

  TtsService({
    required StorageService storageService,
    required FileImportService fileImportService,
  })  : _storageService = storageService,
        _fileImportService = fileImportService;

  final StorageService _storageService;
  final FileImportService _fileImportService;
  final FlutterTts _flutterTts = FlutterTts();
  AudioSession? _audioSession;
  StreamSubscription<AudioInterruptionEvent>? _interruptionSubscription;
  StreamSubscription<void>? _becomingNoisySubscription;

  List<VoiceModel> _voices = const [];
  List<_SpeechChunk> _queuedChunks = const [];
  ReaderPlaybackState _playbackState = ReaderPlaybackState.idle;
  String _text = '';
  String _selectedLanguage = _defaultLanguage;
  VoiceModel? _selectedVoice;
  double _speechRate = _defaultSpeechRate;
  double _pitch = _defaultPitch;
  double _volume = _defaultVolume;
  String? _errorMessage;
  int _currentCharIndex = 0;
  int _currentParagraphIndex = 0;
  int _pausedCharIndex = 0;
  int _sessionId = 0;
  int _activeChunkOffset = 0;
  int _queuedChunkIndex = 0;
  int? _queuedEndOffset;
  bool _queuedResetPositionOnComplete = true;
  bool _queuedTriggerCompletionHandler = true;
  bool _engineReady = false;
  bool _resumeAfterInterruption = false;
  bool _isRecoveringFromStall = false;
  int _stallRecoveryAttempts = 0;
  DateTime? _lastPlaybackActivityAt;
  Future<void> Function()? _playbackCompletedHandler;
  Timer? _playbackWatchdog;

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
      return 'Paste text, import a .txt or .epub file, or share text into the app.';
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
    await _configureAudioSession();
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
      await _flutterTts.awaitSpeakCompletion(false);
      await _flutterTts.setQueueMode(0);

      _flutterTts.setStartHandler(() {
        _markPlaybackActivity(resetRecoveryAttempts: true);
        _playbackState = ReaderPlaybackState.playing;
        _errorMessage = null;
        notifyListeners();
      });

      _flutterTts.setCompletionHandler(() {
        _markPlaybackActivity(resetRecoveryAttempts: true);
        unawaited(_handleChunkCompleted());
      });

      _flutterTts.setPauseHandler(() {
        _stopPlaybackWatchdog();
        _playbackState = ReaderPlaybackState.paused;
        notifyListeners();
      });

      _flutterTts.setContinueHandler(() {
        _markPlaybackActivity(resetRecoveryAttempts: true);
        _startPlaybackWatchdog();
        _playbackState = ReaderPlaybackState.playing;
        _errorMessage = null;
        notifyListeners();
      });

      _flutterTts.setErrorHandler((message) {
        unawaited(_handlePlaybackError(message));
      });

      _flutterTts.setProgressHandler((text, start, end, word) {
        _markPlaybackActivity(resetRecoveryAttempts: true);
        final activeChunk = _queuedChunks.isEmpty
            ? null
            : _queuedChunks[min(_queuedChunkIndex, _queuedChunks.length - 1)];
        _activeChunkOffset = activeChunk?.start ?? _activeChunkOffset;
        _currentCharIndex = max(0, _activeChunkOffset + start);
        _pausedCharIndex = _currentCharIndex;
        _currentParagraphIndex = activeChunk?.paragraphIndex ??
            _paragraphIndexForOffset(_currentCharIndex);
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

  Future<void> _configureAudioSession() async {
    final session = await AudioSession.instance;
    await session.configure(
      const AudioSessionConfiguration.speech().copyWith(
        androidWillPauseWhenDucked: false,
      ),
    );
    _audioSession = session;

    _interruptionSubscription =
        session.interruptionEventStream.listen((event) {
          if (event.begin) {
            if (!isPlaying) {
              return;
            }

            switch (event.type) {
              case AudioInterruptionType.pause:
              case AudioInterruptionType.unknown:
                _resumeAfterInterruption = true;
                unawaited(pause(fromSystemInterruption: true));
              case AudioInterruptionType.duck:
                break;
            }
            return;
          }

          switch (event.type) {
            case AudioInterruptionType.pause:
            case AudioInterruptionType.unknown:
              if (_resumeAfterInterruption && isPaused) {
                _resumeAfterInterruption = false;
                unawaited(play());
              } else {
                _resumeAfterInterruption = false;
              }
            case AudioInterruptionType.duck:
              break;
          }
        });

    _becomingNoisySubscription =
        session.becomingNoisyEventStream.listen((_) {
      if (isPlaying) {
        unawaited(pause());
      }
    });
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

    _selectedLanguage = storedLanguage ?? defaultLanguage ?? _defaultLanguage;

    _selectedVoice = _voices.cast<VoiceModel?>().firstWhere(
          (voice) => voice!.matchesIdentity(storedVoiceName, storedVoiceLocale),
          orElse: () => _defaultVoiceForLanguage(_selectedLanguage),
        );

    if (_selectedVoice != null) {
      _selectedLanguage = _selectedVoice!.locale;
    }
  }

  String? _preferredLanguageFromVoices() {
    final exactEnglishIndia = _voices.firstWhere(
      (voice) => _normalizeLocale(voice.locale) == _normalizeLocale(_defaultLanguage),
      orElse: () => const VoiceModel(name: '', locale: '', label: ''),
    );
    if (exactEnglishIndia.locale.isNotEmpty) {
      return exactEnglishIndia.locale;
    }

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

    final normalizedLanguage = _normalizeLocale(language);
    final candidates = _voices.where((voice) {
      final voiceLocale = _normalizeLocale(voice.locale);
      return voiceLocale == normalizedLanguage ||
          voiceLocale.startsWith('$normalizedLanguage-');
    }).toList();

    if (candidates.isEmpty) {
      if (_isEnglishIndia(language)) {
        return _voices.firstWhere(
          (voice) => _isEnglishIndia(voice.locale),
          orElse: () => _voices.first,
        );
      }
      return _voices.first;
    }

    candidates.sort((a, b) {
      return _voicePreferenceScore(
        b,
        normalizedLanguage,
      ).compareTo(_voicePreferenceScore(a, normalizedLanguage));
    });
    return candidates.first;
  }

  bool _isEnglishIndia(String locale) {
    final normalized = _normalizeLocale(locale);
    return normalized == 'en-in' || normalized.startsWith('en-in-');
  }

  String _normalizeLocale(String locale) {
    return locale.toLowerCase().replaceAll('_', '-');
  }

  String _normalizeVoiceName(String name) {
    return name.toLowerCase().replaceAll('_', '-');
  }

  int _voicePreferenceScore(VoiceModel voice, String normalizedLanguage) {
    final normalizedLocale = _normalizeLocale(voice.locale);
    final normalizedName = _normalizeVoiceName(voice.name);
    var score = 0;

    if (normalizedLocale == normalizedLanguage) {
      score += 1000;
    }
    if (normalizedLocale.startsWith('$normalizedLanguage-')) {
      score += 250;
    }

    if (normalizedLanguage == _normalizeLocale(_defaultLanguage)) {
      if (normalizedName.contains(_defaultVoicePattern)) {
        score += 5000;
      }
      if (normalizedName.contains('en-in-x-ene')) {
        score += 4000;
      }
      if (normalizedName.contains('en-in-x')) {
        score += 3000;
      }
      if (normalizedName.contains('local')) {
        score += 300;
      }
      if (normalizedName.contains('google')) {
        score += 200;
      }
    }

    for (final label in voice.metadataLabels) {
      final normalizedLabel = label.toLowerCase();
      if (normalizedLabel.contains('high')) {
        score += 80;
      }
      if (normalizedLabel.contains('low')) {
        score -= 10;
      }
    }

    return score;
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
    _errorMessage = null;
    if (resetPosition || _currentCharIndex > _text.length) {
      _currentCharIndex = 0;
      _currentParagraphIndex = 0;
      _activeChunkOffset = 0;
      _pausedCharIndex = 0;
    } else {
      _currentParagraphIndex = _paragraphIndexForOffset(_currentCharIndex);
      _pausedCharIndex = min(_currentCharIndex, _text.length);
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
    _errorMessage = null;
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
    _errorMessage = null;
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

  Future<void> resetSettings() async {
    _selectedLanguage = _preferredLanguageFromVoices() ?? _defaultLanguage;
    _selectedVoice = _defaultVoiceForLanguage(_selectedLanguage);
    _speechRate = _defaultSpeechRate;
    _pitch = _defaultPitch;
    _volume = _defaultVolume;
    _errorMessage = null;

    await _storageService.resetTtsSettings();
    await _storageService.saveLanguage(_selectedLanguage);
    await _storageService.saveVoice(
      _selectedVoice?.name,
      _selectedVoice?.locale,
    );
    await _storageService.saveRate(_speechRate);
    await _storageService.savePitch(_pitch);
    await _storageService.saveVolume(_volume);
    await _syncTtsOptions();
    notifyListeners();
  }

  Future<void> play() async {
    if (isPaused) {
      await _resumePlayback();
      return;
    }

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

  Future<void> playPreviousParagraph() async {
    if (paragraphCount == 0 || _currentParagraphIndex <= 0) {
      return;
    }
    await playFromParagraph(_currentParagraphIndex - 1);
  }

  Future<void> playNextParagraph() async {
    if (paragraphCount == 0 || _currentParagraphIndex >= paragraphCount - 1) {
      return;
    }
    await playFromParagraph(_currentParagraphIndex + 1);
  }

  Future<void> _resumePlayback() async {
    final resumeOffset = min(
      max(_pausedCharIndex, _activeChunkOffset),
      _text.length,
    );
    await _playInternal(
      startOffset: resumeOffset,
      endOffset: _queuedEndOffset,
      triggerCompletionHandler: _queuedTriggerCompletionHandler,
      resetPositionOnComplete: _queuedResetPositionOnComplete,
      shouldStopBeforeQueueing: false,
    );
  }

  Future<void> _playInternal({
    required int startOffset,
    required int? endOffset,
    required bool triggerCompletionHandler,
    required bool resetPositionOnComplete,
    bool shouldStopBeforeQueueing = true,
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

    if (!await _activateAudioSession()) {
      _errorMessage =
          'DhebeVoice could not take audio focus right now. Try again after other audio stops.';
      _playbackState = ReaderPlaybackState.error;
      notifyListeners();
      return;
    }

    _errorMessage = null;
    final localSession = ++_sessionId;
    _playbackState = ReaderPlaybackState.playing;
    _queuedChunks = chunks;
    _queuedChunkIndex = 0;
    _queuedEndOffset = endOffset;
    _queuedResetPositionOnComplete = resetPositionOnComplete;
    _queuedTriggerCompletionHandler = triggerCompletionHandler;
    _activeChunkOffset = chunks.first.start;
    _pausedCharIndex = startOffset;
    _currentParagraphIndex = chunks.first.paragraphIndex;
    _markPlaybackActivity(resetRecoveryAttempts: true);
    _startPlaybackWatchdog();
    notifyListeners();

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      unawaited(AudioService.androidForceEnableMediaButtons());
    }

    await _syncTtsOptions();
    if (shouldStopBeforeQueueing) {
      await _flutterTts.stop();
    }

    final started = await _startCurrentChunk(localSession);
    if (!started && _isPlaybackSessionActive(localSession)) {
      await _handlePlaybackError(
        'DhebeVoice could not start the selected voice. Try another installed voice.',
      );
    }
  }

  Future<bool> _startCurrentChunk(int sessionId) async {
    if (_queuedChunks.isEmpty || _queuedChunkIndex >= _queuedChunks.length) {
      return false;
    }
    if (!_isPlaybackSessionActive(sessionId)) {
      return false;
    }

    final chunk = _queuedChunks[_queuedChunkIndex];
    _activeChunkOffset = chunk.start;
    _currentParagraphIndex = chunk.paragraphIndex;

    await _flutterTts.setQueueMode(0);
    final result = await _flutterTts.speak(
      chunk.text,
      focus: false,
    );
    return _isPlaybackSessionActive(sessionId) && result == 1;
  }

  Future<void> _handleChunkCompleted() async {
    if (_queuedChunks.isEmpty || _playbackState != ReaderPlaybackState.playing) {
      return;
    }

    final completedIndex = min(_queuedChunkIndex, _queuedChunks.length - 1);
    final completedChunk = _queuedChunks[completedIndex];
    _currentCharIndex = completedChunk.end;
    _pausedCharIndex = min(_currentCharIndex, _text.length);
    _currentParagraphIndex = completedChunk.paragraphIndex;
    await _storageService.savePosition(_currentCharIndex);

    if (completedIndex < _queuedChunks.length - 1) {
      _queuedChunkIndex = completedIndex + 1;
      final nextChunk = _queuedChunks[_queuedChunkIndex];
      _activeChunkOffset = nextChunk.start;
      _currentParagraphIndex = nextChunk.paragraphIndex;
      notifyListeners();
      final localSession = _sessionId;
      final started = await _startCurrentChunk(localSession);
      if (!started && _isPlaybackSessionActive(localSession)) {
        await _recoverFromPlaybackStall();
      }
      return;
    }

    final triggerCompletionHandler = _queuedTriggerCompletionHandler;
    final resetPositionOnComplete = _queuedResetPositionOnComplete;
    final finalOffset = _queuedEndOffset ?? _queuedChunks.last.end;

    _queuedChunks = const [];
    _queuedChunkIndex = 0;
    _queuedEndOffset = null;
    _resumeAfterInterruption = false;
    _stopPlaybackWatchdog();
    await _audioSession?.setActive(false);

    _playbackState = ReaderPlaybackState.completed;
    _currentCharIndex =
        resetPositionOnComplete ? 0 : min(finalOffset, _text.length);
    _pausedCharIndex = _currentCharIndex;
    _currentParagraphIndex = _paragraphIndexForOffset(_currentCharIndex);
    await _storageService.savePosition(_currentCharIndex);
    notifyListeners();

    final handler = _playbackCompletedHandler;
    if (triggerCompletionHandler && handler != null) {
      unawaited(handler());
    }
  }

  Future<void> _handlePlaybackError(dynamic message) async {
    if (_playbackState == ReaderPlaybackState.paused ||
        _playbackState == ReaderPlaybackState.stopped) {
      return;
    }

    _queuedChunks = const [];
    _queuedChunkIndex = 0;
    _queuedEndOffset = null;
    _resumeAfterInterruption = false;
    _stopPlaybackWatchdog();
    await _audioSession?.setActive(false);

    _playbackState = ReaderPlaybackState.error;
    _errorMessage = _friendlyPlaybackError(message);
    _pausedCharIndex = min(
      max(_currentCharIndex, _activeChunkOffset),
      _text.length,
    );
    notifyListeners();
  }

  String _friendlyPlaybackError(dynamic message) {
    final raw = message?.toString().trim() ?? '';
    if (raw.isEmpty) {
      return 'DhebeVoice could not continue playback. Try another installed voice.';
    }
    if (raw.toLowerCase().contains('selected voice')) {
      return raw;
    }
    if (raw.toLowerCase().contains('error from texttospeech')) {
      return 'DhebeVoice could not continue with the selected voice. Try another installed voice.';
    }
    return raw;
  }

  Future<bool> _activateAudioSession() async {
    final session = _audioSession;
    if (session == null) {
      return true;
    }
    return session.setActive(true);
  }

  bool _isPlaybackSessionActive(int sessionId) {
    return sessionId == _sessionId &&
        _playbackState == ReaderPlaybackState.playing;
  }

  Future<void> pause({bool fromSystemInterruption = false}) async {
    if (!isPlaying) {
      return;
    }

    if (!fromSystemInterruption) {
      _resumeAfterInterruption = false;
    }
    _sessionId++;
    _pausedCharIndex = min(
      max(_currentCharIndex, _activeChunkOffset),
      _text.length,
    );
    _currentCharIndex = _pausedCharIndex;
    _stopPlaybackWatchdog();
    _playbackState = ReaderPlaybackState.paused;
    _errorMessage = null;
    await _flutterTts.pause();
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      unawaited(AudioService.androidForceEnableMediaButtons());
    }
    await _storageService.savePosition(_currentCharIndex);
    notifyListeners();
  }

  Future<void> stop() async {
    _sessionId++;
    _queuedChunks = const [];
    _queuedChunkIndex = 0;
    _queuedEndOffset = null;
    _resumeAfterInterruption = false;
    _stopPlaybackWatchdog();
    _playbackState = ReaderPlaybackState.stopped;
    _errorMessage = null;
    _currentCharIndex = 0;
    _currentParagraphIndex = 0;
    _activeChunkOffset = 0;
    _pausedCharIndex = 0;
    await _flutterTts.stop();
    await _audioSession?.setActive(false);
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

  void _markPlaybackActivity({bool resetRecoveryAttempts = false}) {
    _lastPlaybackActivityAt = DateTime.now();
    if (resetRecoveryAttempts) {
      _stallRecoveryAttempts = 0;
    }
  }

  void _startPlaybackWatchdog() {
    _playbackWatchdog?.cancel();
    _playbackWatchdog = Timer.periodic(_watchdogCheckInterval, (_) {
      unawaited(_handlePlaybackWatchdogTick());
    });
  }

  void _stopPlaybackWatchdog() {
    _playbackWatchdog?.cancel();
    _playbackWatchdog = null;
    _lastPlaybackActivityAt = null;
    _stallRecoveryAttempts = 0;
    _isRecoveringFromStall = false;
  }

  Future<void> _handlePlaybackWatchdogTick() async {
    if (!isPlaying || _queuedChunks.isEmpty || _isRecoveringFromStall) {
      return;
    }

    final lastPlaybackActivityAt = _lastPlaybackActivityAt;
    if (lastPlaybackActivityAt == null) {
      return;
    }

    if (DateTime.now().difference(lastPlaybackActivityAt) < _watchdogTimeout) {
      return;
    }

    if (_stallRecoveryAttempts >= 2) {
      await _handlePlaybackError(
        'DhebeVoice lost playback unexpectedly. Tap Resume to continue from the last paragraph.',
      );
      return;
    }

    await _recoverFromPlaybackStall();
  }

  Future<void> _recoverFromPlaybackStall() async {
    if (_isRecoveringFromStall) {
      return;
    }

    _isRecoveringFromStall = true;
    _stallRecoveryAttempts++;

    try {
      final resumeOffset = min(
        max(_currentCharIndex, _activeChunkOffset),
        _text.length,
      );

      await _playInternal(
        startOffset: resumeOffset,
        endOffset: _queuedEndOffset,
        triggerCompletionHandler: _queuedTriggerCompletionHandler,
        resetPositionOnComplete: _queuedResetPositionOnComplete,
      );
    } finally {
      _isRecoveringFromStall = false;
    }
  }

  @override
  void dispose() {
    _interruptionSubscription?.cancel();
    _becomingNoisySubscription?.cancel();
    _playbackWatchdog?.cancel();
    unawaited(_flutterTts.stop());
    super.dispose();
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
