import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../services/novel_import_controller.dart';
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
    final importer = context.read<NovelImportController>();

    _shareSubscription =
        ReceiveSharingIntent.instance.getMediaStream().listen((value) async {
      final sharedText = _extractSharedText(value);
      if (sharedText != null) {
        await importer.handleSharedPayload(sharedText);
      }
    });

    final initialMedia = await ReceiveSharingIntent.instance.getInitialMedia();
    final initialText = _extractSharedText(initialMedia);
    if (initialText != null) {
      await importer.handleSharedPayload(initialText);
      await ReceiveSharingIntent.instance.reset();
    }
  }

  Future<void> _showImportUrlDialog() async {
    final importer = context.read<NovelImportController>();
    final controller = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Import novel link'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              hintText: 'Paste chapter or contents URL',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await importer.importNovelFromUrl(controller.text);
              },
              child: const Text('Import'),
            ),
          ],
        );
      },
    );
  }

  void _showLibrarySheet() {
    final importer = context.read<NovelImportController>();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.72,
            child: importer.library.isEmpty
                ? const Center(
                    child: Text('Imported web novels will appear here.'),
                  )
                : ListView.builder(
                    itemCount: importer.library.length,
                    itemBuilder: (context, index) {
                      final book = importer.library[index];
                      return ListTile(
                        title: Text(book.title),
                        subtitle: Text(
                          '${book.chapters.length} chapters • ${Uri.tryParse(book.sourceUrl)?.host ?? book.sourceUrl}',
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            await importer.deleteNovel(book.id);
                            if (context.mounted) {
                              Navigator.of(context).pop();
                            }
                          },
                        ),
                        onTap: () async {
                          await importer.selectNovel(book.id);
                          if (context.mounted) {
                            Navigator.of(context).pop();
                          }
                        },
                      );
                    },
                  ),
          ),
        );
      },
    );
  }

  void _showChapterSheet() {
    final importer = context.read<NovelImportController>();
    final novel = importer.activeNovel;
    if (novel == null) {
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.72,
            child: ListView.builder(
              itemCount: novel.chapters.length,
              itemBuilder: (context, index) {
                final chapter = novel.chapters[index];
                return ListTile(
                  selected: index == importer.activeChapterIndex,
                  leading: CircleAvatar(child: Text('${index + 1}')),
                  title: Text(chapter.title),
                  onTap: () async {
                    await importer.selectChapter(index);
                    if (context.mounted) {
                      Navigator.of(context).pop();
                    }
                  },
                );
              },
            ),
          ),
        );
      },
    );
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
    return Consumer2<NovelImportController, TtsService>(
      builder: (context, importer, ttsService, _) {
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
                tooltip: 'Import web link',
                onPressed: _showImportUrlDialog,
                icon: const Icon(Icons.link),
              ),
              IconButton(
                tooltip: 'Library',
                onPressed: _showLibrarySheet,
                icon: Badge(
                  isLabelVisible: importer.library.isNotEmpty,
                  label: Text('${importer.library.length}'),
                  child: const Icon(Icons.library_books_outlined),
                ),
              ),
              IconButton(
                tooltip: 'Import .txt file',
                onPressed: () async {
                  await importer.clearActiveNovel();
                  await ttsService.importTextFile();
                },
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
                  if (importer.isImporting ||
                      importer.importStatus != null ||
                      importer.errorMessage != null) ...[
                    const SizedBox(height: 16),
                    _ImportStatusCard(importer: importer),
                  ],
                  if (importer.activeNovel != null) ...[
                    const SizedBox(height: 16),
                    _ActiveNovelCard(
                      importer: importer,
                      onOpenChapters: _showChapterSheet,
                    ),
                  ],
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
                                'Paste text here, import a .txt file, or share a novel link from your browser.',
                            border: InputBorder.none,
                            filled: false,
                            contentPadding: EdgeInsets.zero,
                          ),
                          onChanged: (value) {
                            unawaited(importer.detachIfTextChanged(value));
                            unawaited(ttsService.updateText(value));
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _NowReadingCard(
                    ttsService: ttsService,
                    chapterLabel: importer.activeChapter?.title,
                  ),
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

class _ImportStatusCard extends StatelessWidget {
  const _ImportStatusCard({required this.importer});

  final NovelImportController importer;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              importer.isImporting ? 'Importing web novel' : 'Web import',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (importer.importStatus != null) ...[
              const SizedBox(height: 10),
              Text(importer.importStatus!),
            ],
            if (importer.importProgress != null) ...[
              const SizedBox(height: 14),
              LinearProgressIndicator(value: importer.importProgress),
            ],
            if (importer.errorMessage != null) ...[
              const SizedBox(height: 10),
              Text(
                importer.errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ActiveNovelCard extends StatelessWidget {
  const _ActiveNovelCard({
    required this.importer,
    required this.onOpenChapters,
  });

  final NovelImportController importer;
  final VoidCallback onOpenChapters;

  @override
  Widget build(BuildContext context) {
    final novel = importer.activeNovel!;
    final chapter = importer.activeChapter;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              novel.title,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              '${novel.chapters.length} chapters • ${Uri.tryParse(novel.sourceUrl)?.host ?? novel.sourceUrl}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white70,
                  ),
            ),
            if (chapter != null) ...[
              const SizedBox(height: 12),
              Text(
                'Current chapter: ${chapter.title}',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                FilledButton.tonalIcon(
                  onPressed: importer.activeChapterIndex > 0
                      ? importer.goToPreviousChapter
                      : null,
                  icon: const Icon(Icons.chevron_left),
                  label: const Text('Prev'),
                ),
                const SizedBox(width: 10),
                FilledButton.tonalIcon(
                  onPressed: onOpenChapters,
                  icon: const Icon(Icons.menu_book),
                  label: const Text('Chapters'),
                ),
                const SizedBox(width: 10),
                FilledButton.tonalIcon(
                  onPressed:
                      importer.activeChapterIndex < novel.chapters.length - 1
                          ? importer.goToNextChapter
                          : null,
                  icon: const Icon(Icons.chevron_right),
                  label: const Text('Next'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NowReadingCard extends StatelessWidget {
  const _NowReadingCard({
    required this.ttsService,
    required this.chapterLabel,
  });

  final TtsService ttsService;
  final String? chapterLabel;

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
            if (chapterLabel != null) ...[
              const SizedBox(height: 8),
              Text(
                chapterLabel!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.white70,
                    ),
              ),
            ],
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
