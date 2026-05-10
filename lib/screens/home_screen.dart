import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../models/novel_book.dart';
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
  bool _isImportDialogOpen = false;

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
          scrollable: true,
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
                final chapterBadge = _chapterBadgeLabel(chapter, index);
                return ListTile(
                  selected: index == importer.activeChapterIndex,
                  leading: _ChapterBadge(label: chapterBadge),
                  title: Text(chapter.title),
                  onTap: () {
                    Navigator.of(context).pop();
                    unawaited(importer.selectChapter(index));
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  void _showParagraphSheet() {
    final ttsService = context.read<TtsService>();
    if (ttsService.paragraphCount == 0) {
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
              itemCount: ttsService.paragraphCount,
              itemBuilder: (context, index) {
                final preview = ttsService.paragraphs[index];
                return ListTile(
                  selected: index == ttsService.currentParagraphIndex,
                  leading: _ChapterBadge(label: '#P${index + 1}'),
                  title: Text(
                    'Paragraph ${index + 1}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    preview,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () {
                    Navigator.of(context).pop();
                    unawaited(ttsService.playFromParagraph(index));
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

  String _chapterBadgeLabel(NovelChapter chapter, int index) {
    final chapterNumber = _extractChapterNumber(chapter.title) ??
        _extractChapterNumber(chapter.url) ??
        (index + 1);
    return '#$chapterNumber';
  }

  int? _extractChapterNumber(String value) {
    final match = RegExp(
      r'(?:chapter|chap|episode|ep|part)[\s\-_:]*(\d+)',
      caseSensitive: false,
    ).firstMatch(value);
    if (match != null) {
      return int.tryParse(match.group(1) ?? '');
    }

    final fallback = RegExp(r'(\d+)').firstMatch(value);
    return fallback == null ? null : int.tryParse(fallback.group(1) ?? '');
  }

  void _syncImportDialog(NovelImportController importer) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      if (importer.isImporting && !_isImportDialogOpen) {
        _isImportDialogOpen = true;
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (context) => const _ImportProgressDialog(),
        ).then((_) {
          _isImportDialogOpen = false;
        });
        return;
      }

      if (!importer.isImporting && _isImportDialogOpen) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    });
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
        _syncImportDialog(importer);
        final isKeyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
        final audioHandler = context.read<AudioHandler>();

        if (_textController.text != ttsService.text) {
          _textController.value = TextEditingValue(
            text: ttsService.text,
            selection: TextSelection.collapsed(offset: ttsService.text.length),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('DhebeVoice'),
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
                tooltip: 'Import .txt or .epub file',
                onPressed: () async {
                  await importer.importLocalFile();
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
          bottomNavigationBar: SafeArea(
            top: false,
            minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: PlayerControls(
              isPlaying: ttsService.isPlaying,
              canResume:
                  ttsService.isPaused || ttsService.currentCharIndex > 0,
              onPlay: () => unawaited(audioHandler.play()),
              onPause: () => unawaited(audioHandler.pause()),
              onStop: () => unawaited(audioHandler.stop()),
            ),
          ),
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final editorHeight = isKeyboardOpen
                    ? 220.0
                    : (constraints.maxHeight * 0.38).clamp(260.0, 460.0);

                return ListView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  children: [
                    if (!importer.isImporting &&
                        (importer.importStatus != null ||
                            importer.errorMessage != null)) ...[
                      _ImportStatusCard(importer: importer),
                    ],
                    if (importer.activeNovel != null) ...[
                      const SizedBox(height: 16),
                      _ActiveNovelCard(
                        importer: importer,
                        onOpenChapters: _showChapterSheet,
                        onPreviousChapter: () =>
                            unawaited(audioHandler.skipToPrevious()),
                        onNextChapter: () =>
                            unawaited(audioHandler.skipToNext()),
                      ),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      height: editorHeight,
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: TextField(
                            controller: _textController,
                            maxLines: null,
                            expands: true,
                            textAlignVertical: TextAlignVertical.top,
                            style:
                                Theme.of(context).textTheme.bodyLarge?.copyWith(
                                      height: 1.5,
                                    ),
                            contextMenuBuilder: (context, editableTextState) {
                              final selection =
                                  editableTextState.textEditingValue.selection;
                              final buttonItems = <ContextMenuButtonItem>[
                                ...editableTextState.contextMenuButtonItems,
                                if (selection.isValid && !selection.isCollapsed)
                                  ContextMenuButtonItem(
                                    label: 'Play selection',
                                    onPressed: () {
                                      ContextMenuController.removeAny();
                                      unawaited(
                                        ttsService.playSelection(selection),
                                      );
                                    },
                                  ),
                              ];

                              return AdaptiveTextSelectionToolbar.buttonItems(
                                anchors: editableTextState.contextMenuAnchors,
                                buttonItems: buttonItems,
                              );
                            },
                            decoration: const InputDecoration(
                              hintText:
                                  'Paste text here, import a .txt or .epub file, or share a novel link from your browser.',
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
                    if (!isKeyboardOpen) ...[
                      const SizedBox(height: 16),
                      _NowReadingCard(
                        ttsService: ttsService,
                        chapterLabel: importer.activeChapter?.title,
                        onOpenParagraphs: _showParagraphSheet,
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _ChapterBadge extends StatelessWidget {
  const _ChapterBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 58),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.labelLarge,
      ),
    );
  }
}

class _ImportProgressDialog extends StatelessWidget {
  const _ImportProgressDialog();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: false,
      child: Consumer<NovelImportController>(
        builder: (context, importer, _) {
          final progressPercent = importer.importProgress == null
              ? null
              : (importer.importProgress! * 100).clamp(0, 100).round();

          return AlertDialog(
            title: const Text('Importing web novel'),
            content: SizedBox(
              width: 320,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    importer.importStatus ?? 'Preparing chapters...',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 14),
                  LinearProgressIndicator(value: importer.importProgress),
                  if (progressPercent != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      '$progressPercent% complete',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ] else ...[
                    const SizedBox(height: 10),
                    Text(
                      'Following chapter links and downloading text...',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton.icon(
                onPressed: importer.isCancellingImport
                    ? null
                    : () => unawaited(importer.cancelImport()),
                icon: const Icon(Icons.stop_circle_outlined),
                label: Text(
                  importer.isCancellingImport
                      ? 'Stopping...'
                      : 'Stop download',
                ),
              ),
            ],
          );
        },
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
            if (importer.isImporting || importer.importProgress != null) ...[
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
    required this.onPreviousChapter,
    required this.onNextChapter,
  });

  final NovelImportController importer;
  final VoidCallback onOpenChapters;
  final VoidCallback onPreviousChapter;
  final VoidCallback onNextChapter;

  @override
  Widget build(BuildContext context) {
    final novel = importer.activeNovel!;
    final chapter = importer.activeChapter;
    final actionStyle = FilledButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      visualDensity: VisualDensity.compact,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    final colorScheme = Theme.of(context).colorScheme;

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
                    color: colorScheme.onSurfaceVariant,
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
                Expanded(
                  flex: 9,
                  child: FilledButton.tonalIcon(
                    style: actionStyle,
                    onPressed: importer.activeChapterIndex > 0
                        ? onPreviousChapter
                        : null,
                    icon: const Icon(Icons.chevron_left),
                    label: const Text(
                      'Prev',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 12,
                  child: FilledButton.tonalIcon(
                    style: actionStyle,
                    onPressed: onOpenChapters,
                    icon: const Icon(Icons.menu_book),
                    label: const Text(
                      'Chapters',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 9,
                  child: FilledButton.tonalIcon(
                    style: actionStyle,
                    onPressed:
                        importer.activeChapterIndex < novel.chapters.length - 1
                            ? onNextChapter
                            : null,
                    icon: const Icon(Icons.chevron_right),
                    label: const Text(
                      'Next',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
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
    required this.onOpenParagraphs,
  });

  final TtsService ttsService;
  final String? chapterLabel;
  final VoidCallback onOpenParagraphs;

  @override
  Widget build(BuildContext context) {
    final chapterText = chapterLabel == null || chapterLabel!.trim().isEmpty
        ? 'Manual text'
        : chapterLabel!;
    final colorScheme = Theme.of(context).colorScheme;

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
                        color: colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
            if (chapterLabel != null) ...[
              const SizedBox(height: 8),
              Text(
                chapterText,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
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
                    color: colorScheme.onSurface.withValues(alpha: 0.88),
                  ),
            ),
            if (ttsService.paragraphCount > 0) ...[
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: onOpenParagraphs,
                  icon: const Icon(Icons.format_list_numbered),
                  label: const Text('Play from paragraph'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
