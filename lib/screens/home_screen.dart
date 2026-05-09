import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../services/tts_service.dart';
import '../widgets/player_controls.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final TextEditingController _textController;
  StreamSubscription<List<SharedMediaFile>>? _shareSubscription;

  @override
  void initState() {
    super.initState();
    final service = context.read<TtsService>();
    _textController = TextEditingController(text: service.text);
    _listenForSharedText();
  }

  Future<void> _listenForSharedText() async {
    final service = context.read<TtsService>();

    _shareSubscription =
        ReceiveSharingIntent.instance.getMediaStream().listen((value) async {
      final sharedText = _extractSharedText(value);
      if (sharedText != null) {
        await service.handleSharedText(sharedText);
      }
    });

    final initialMedia = await ReceiveSharingIntent.instance.getInitialMedia();
    final initialText = _extractSharedText(initialMedia);
    if (initialText != null) {
      await service.handleSharedText(initialText);
      await ReceiveSharingIntent.instance.reset();
    }
  }

  String? _extractSharedText(List<SharedMediaFile> sharedItems) {
    for (final item in sharedItems) {
      final candidate = switch (item.type) {
        SharedMediaType.text || SharedMediaType.url => item.path,
        SharedMediaType.file || SharedMediaType.image || SharedMediaType.video =>
          item.message,
      };

      if (candidate != null && candidate.trim().isNotEmpty) {
        return candidate.trim();
      }
    }

    return null;
  }

  @override
  void dispose() {
    _shareSubscription?.cancel();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<TtsService>(
      builder: (context, ttsService, _) {
        if (_textController.text != ttsService.text) {
          _textController.value = TextEditingValue(
            text: ttsService.text,
            selection: TextSelection.collapsed(offset: ttsService.text.length),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Text Reader'),
            actions: [
              IconButton(
                tooltip: 'Import .txt file',
                onPressed: ttsService.importTextFile,
                icon: const Icon(Icons.upload_file),
              ),
              IconButton(
                tooltip: 'Settings',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const SettingsScreen(),
                    ),
                  );
                },
                icon: const Icon(Icons.tune),
              ),
            ],
          ),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                children: [
                  _HeaderCard(ttsService: ttsService),
                  const SizedBox(height: 16),
                  Expanded(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: TextField(
                          controller: _textController,
                          maxLines: null,
                          expands: true,
                          textAlignVertical: TextAlignVertical.top,
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                height: 1.5,
                              ),
                          decoration: const InputDecoration(
                            hintText:
                                'Paste text here, import a .txt file, or share text from another app.',
                            border: InputBorder.none,
                            filled: false,
                            contentPadding: EdgeInsets.zero,
                          ),
                          onChanged: (value) {
                            ttsService.updateText(value);
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _NowReadingCard(ttsService: ttsService),
                  const SizedBox(height: 16),
                  PlayerControls(
                    isPlaying: ttsService.isPlaying,
                    canResume: ttsService.isPaused ||
                        ttsService.currentCharIndex > 0,
                    onPlay: ttsService.play,
                    onPause: ttsService.pause,
                    onStop: ttsService.stop,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.ttsService});

  final TtsService ttsService;

  @override
  Widget build(BuildContext context) {
    final stateText = switch (ttsService.playbackState) {
      ReaderPlaybackState.playing => 'Reading aloud',
      ReaderPlaybackState.paused => 'Paused',
      ReaderPlaybackState.completed => 'Finished',
      ReaderPlaybackState.error => 'Needs attention',
      ReaderPlaybackState.stopped => 'Stopped',
      ReaderPlaybackState.idle => 'Ready',
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.graphic_eq),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    stateText,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Language: ${ttsService.selectedLanguage} | Voice: ${ttsService.selectedVoice?.label ?? 'Not selected'}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.white70,
                        ),
                  ),
                  if (ttsService.errorMessage != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      ttsService.errorMessage!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NowReadingCard extends StatelessWidget {
  const _NowReadingCard({required this.ttsService});

  final TtsService ttsService;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Now reading',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                Text(
                  'Paragraph ${ttsService.currentParagraphIndex + 1}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.white60,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              ttsService.currentParagraph,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    height: 1.45,
                    color: Colors.white.withValues(alpha: 0.88),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
