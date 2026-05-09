import 'package:flutter/material.dart';

import '../models/voice_model.dart';

class TtsSettingsPanel extends StatelessWidget {
  const TtsSettingsPanel({
    super.key,
    required this.languages,
    required this.selectedLanguage,
    required this.selectedVoice,
    required this.voices,
    required this.rate,
    required this.pitch,
    required this.volume,
    required this.onLanguageChanged,
    required this.onVoiceSelected,
    required this.onRateChanged,
    required this.onPitchChanged,
    required this.onVolumeChanged,
  });

  final List<String> languages;
  final String selectedLanguage;
  final VoiceModel? selectedVoice;
  final List<VoiceModel> voices;
  final double rate;
  final double pitch;
  final double volume;
  final ValueChanged<String?> onLanguageChanged;
  final ValueChanged<VoiceModel?> onVoiceSelected;
  final ValueChanged<double> onRateChanged;
  final ValueChanged<double> onPitchChanged;
  final ValueChanged<double> onVolumeChanged;

  @override
  Widget build(BuildContext context) {
    final languageVoices = voices
        .where((voice) => voice.locale == selectedLanguage)
        .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Language',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: languages.contains(selectedLanguage)
                      ? selectedLanguage
                      : (languages.isEmpty ? null : languages.first),
                  items: languages
                      .map(
                        (language) => DropdownMenuItem(
                          value: language,
                          child: Text(language),
                        ),
                      )
                      .toList(),
                  onChanged: onLanguageChanged,
                  decoration: const InputDecoration(
                    hintText: 'Select a language',
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Voice',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: languageVoices.isEmpty
                      ? null
                      : () async {
                          final result = await showSearch<VoiceModel?>(
                            context: context,
                            delegate: _VoiceSearchDelegate(
                              voices: languageVoices,
                              selectedVoice: selectedVoice,
                            ),
                          );
                          if (result != null) {
                            onVoiceSelected(result);
                          }
                        },
                  icon: const Icon(Icons.record_voice_over),
                  label: Text(
                    selectedVoice?.label ?? 'Choose installed voice',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
        _SettingSlider(
          title: 'Speech rate',
          value: rate,
          min: 0.1,
          max: 1.0,
          divisions: 18,
          valueText: rate.toStringAsFixed(2),
          onChanged: onRateChanged,
        ),
        _SettingSlider(
          title: 'Pitch',
          value: pitch,
          min: 0.5,
          max: 2.0,
          divisions: 15,
          valueText: pitch.toStringAsFixed(2),
          onChanged: onPitchChanged,
        ),
        _SettingSlider(
          title: 'Volume',
          value: volume,
          min: 0.0,
          max: 1.0,
          divisions: 10,
          valueText: volume.toStringAsFixed(2),
          onChanged: onVolumeChanged,
        ),
      ],
    );
  }
}

class _SettingSlider extends StatelessWidget {
  const _SettingSlider({
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.valueText,
    required this.onChanged,
  });

  final String title;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String valueText;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(top: 16),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(valueText),
              ],
            ),
            Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              label: valueText,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _VoiceSearchDelegate extends SearchDelegate<VoiceModel?> {
  _VoiceSearchDelegate({
    required this.voices,
    required this.selectedVoice,
  });

  final List<VoiceModel> voices;
  final VoiceModel? selectedVoice;

  @override
  ThemeData appBarTheme(BuildContext context) => Theme.of(context);

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(
          onPressed: () => query = '',
          icon: const Icon(Icons.clear),
        ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      onPressed: () => close(context, null),
      icon: const Icon(Icons.arrow_back),
    );
  }

  @override
  Widget buildResults(BuildContext context) => _buildVoiceList(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildVoiceList(context);

  Widget _buildVoiceList(BuildContext context) {
    final normalizedQuery = query.trim().toLowerCase();
    final filtered = voices.where((voice) {
      if (normalizedQuery.isEmpty) {
        return true;
      }
      return voice.label.toLowerCase().contains(normalizedQuery) ||
          voice.name.toLowerCase().contains(normalizedQuery) ||
          voice.locale.toLowerCase().contains(normalizedQuery);
    }).toList();

    if (filtered.isEmpty) {
      return const Center(
        child: Text('No installed voices match that search.'),
      );
    }

    return ListView.builder(
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final voice = filtered[index];
        final isSelected = selectedVoice?.name == voice.name &&
            selectedVoice?.locale == voice.locale;
        return ListTile(
          title: Text(voice.label),
          subtitle: Text(voice.name),
          trailing: isSelected ? const Icon(Icons.check_circle) : null,
          onTap: () => close(context, voice),
        );
      },
    );
  }
}
