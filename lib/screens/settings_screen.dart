import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/tts_service.dart';
import '../widgets/tts_settings_panel.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<TtsService>(
      builder: (context, ttsService, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Settings'),
          ),
          body: TtsSettingsPanel(
            languages: ttsService.availableLanguages(),
            selectedLanguage: ttsService.selectedLanguage,
            selectedVoice: ttsService.selectedVoice,
            voices: ttsService.voices,
            rate: ttsService.speechRate,
            pitch: ttsService.pitch,
            volume: ttsService.volume,
            onLanguageChanged: (value) {
              if (value != null) {
                ttsService.setLanguage(value);
              }
            },
            onVoiceSelected: ttsService.setVoice,
            onRateChanged: ttsService.setSpeechRate,
            onPitchChanged: ttsService.setPitch,
            onVolumeChanged: ttsService.setVolume,
          ),
        );
      },
    );
  }
}
