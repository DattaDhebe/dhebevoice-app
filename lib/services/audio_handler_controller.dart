import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

class AudioHandlerController extends ChangeNotifier {
  AudioHandler? _audioHandler;

  AudioHandler? get audioHandler => _audioHandler;
  bool get isReady => _audioHandler != null;

  void attach(AudioHandler handler) {
    if (identical(_audioHandler, handler)) {
      return;
    }
    _audioHandler = handler;
    notifyListeners();
  }
}
