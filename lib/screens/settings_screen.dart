import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/novel_import_controller.dart';
import '../services/theme_controller.dart';
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
    return Consumer3<ThemeController, TtsService, NovelImportController>(
      builder: (context, themeController, ttsService, importer, _) {
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
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Theme',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      SegmentedButton<ThemeMode>(
                        segments: const [
                          ButtonSegment(
                            value: ThemeMode.light,
                            icon: Icon(Icons.light_mode),
                            label: Text('Light'),
                          ),
                          ButtonSegment(
                            value: ThemeMode.dark,
                            icon: Icon(Icons.dark_mode),
                            label: Text('Dark'),
                          ),
                        ],
                        selected: {themeController.themeMode},
                        onSelectionChanged: (selection) {
                          if (selection.isNotEmpty) {
                            themeController.setThemeMode(selection.first);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Website Access Mode',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Use the current mobile browser mode by default, or switch to another profile when a site returns 403.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: importer.selectedWebAccessModeId,
                        items: importer.availableWebAccessModes
                            .map(
                              (mode) => DropdownMenuItem(
                                value: mode.id,
                                child: Text(mode.label),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value != null) {
                            importer.setWebAccessMode(value);
                          }
                        },
                        decoration: const InputDecoration(
                          hintText: 'Select a website access mode',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        importer.availableWebAccessModes
                            .firstWhere(
                              (mode) =>
                                  mode.id == importer.selectedWebAccessModeId,
                              orElse: () =>
                                  importer.availableWebAccessModes.first,
                            )
                            .description,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TtsSettingsPanel(
                languages: ttsService.availableLanguages(),
                selectedLanguage: ttsService.selectedLanguage,
                selectedVoice: ttsService.selectedVoice,
                voices: ttsService.voices,
                rate: ttsService.speechRate,
                pitch: ttsService.pitch,
                volume: ttsService.volume,
                padding: EdgeInsets.zero,
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
            ],
          ),
        );
      },
    );
  }
}
