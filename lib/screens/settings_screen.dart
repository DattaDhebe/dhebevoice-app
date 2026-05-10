import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/tts_service.dart';
import '../widgets/tts_settings_panel.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _confirmResetSettings(
    BuildContext context,
    TtsService ttsService,
  ) async {
    final shouldReset = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Reset TTS settings'),
          content: const Text(
            'Reset language, voice, speech rate, pitch, and volume back to the default English India settings?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Reset'),
            ),
          ],
        );
      },
    );

    if (shouldReset == true) {
      await ttsService.resetSettings();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<TtsService>(
      builder: (context, ttsService, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Settings'),
            actions: [
              IconButton(
                tooltip: 'Reset settings',
                onPressed: () => _confirmResetSettings(context, ttsService),
                icon: const Icon(Icons.restart_alt),
              ),
            ],
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
