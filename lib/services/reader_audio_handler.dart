import 'package:audio_service/audio_service.dart';

import '../models/novel_book.dart';
import 'novel_import_controller.dart';
import 'tts_service.dart';

class ReaderAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  ReaderAudioHandler({
    required TtsService ttsService,
    required NovelImportController novelImportController,
  })  : _ttsService = ttsService,
        _novelImportController = novelImportController {
    _ttsService.addListener(_broadcastPlaybackState);
    _novelImportController.addListener(_broadcastLibraryState);
    _broadcastLibraryState();
    _broadcastPlaybackState();
  }

  final TtsService _ttsService;
  final NovelImportController _novelImportController;

  @override
  Future<void> play() => _ttsService.play();

  @override
  Future<void> pause() => _ttsService.pause();

  @override
  Future<void> click([MediaButton button = MediaButton.media]) async {
    final isPlaying = playbackState.value.playing;
    switch (button) {
      case MediaButton.media:
        if (isPlaying) {
          await pause();
        } else {
          await play();
        }
        break;
      case MediaButton.next:
        await skipToNext();
        break;
      case MediaButton.previous:
        await skipToPrevious();
        break;
    }
  }

  @override
  Future<void> stop() async {
    await _ttsService.stop();
    playbackState.add(
      playbackState.value.copyWith(
        playing: false,
        processingState: AudioProcessingState.idle,
      ),
    );
  }

  @override
  Future<void> skipToNext() async {
    final canAdvance = _novelImportController.activeNovel != null &&
        _novelImportController.activeChapterIndex <
            _novelImportController.activeNovel!.chapters.length - 1;
    if (!canAdvance) {
      return;
    }

    final shouldResume = _ttsService.isPlaying;
    await _novelImportController.goToNextChapter();
    if (shouldResume) {
      await _ttsService.play();
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (_novelImportController.activeNovel == null ||
        _novelImportController.activeChapterIndex <= 0) {
      return;
    }

    final shouldResume = _ttsService.isPlaying;
    await _novelImportController.goToPreviousChapter();
    if (shouldResume) {
      await _ttsService.play();
    }
  }

  void _broadcastLibraryState() {
    final activeNovel = _novelImportController.activeNovel;

    if (activeNovel == null || activeNovel.chapters.isEmpty) {
      queue.add(const <MediaItem>[]);
      mediaItem.add(
        MediaItem(
          id: 'manual-text',
          album: 'DhebeVoice',
          title: 'Manual text',
          artist: _ttsService.selectedLanguage,
        ),
      );
      _broadcastPlaybackState();
      return;
    }

    final items = activeNovel.chapters
        .map(
          (chapter) => _chapterToMediaItem(
            novel: activeNovel,
            chapter: chapter,
          ),
        )
        .toList(growable: false);
    queue.add(items);

    final selectedIndex = _novelImportController.activeChapterIndex.clamp(
      0,
      items.length - 1,
    );
    mediaItem.add(items[selectedIndex]);
    _broadcastPlaybackState();
  }

  MediaItem _chapterToMediaItem({
    required NovelBook novel,
    required NovelChapter chapter,
  }) {
    return MediaItem(
      id: chapter.url.isEmpty ? '${novel.id}:${chapter.order}' : chapter.url,
      album: novel.title,
      title: chapter.title,
      artist: 'DhebeVoice',
      displayTitle: chapter.title,
    );
  }

  void _broadcastPlaybackState() {
    final activeNovel = _novelImportController.activeNovel;
    final hasPrevious =
        activeNovel != null && _novelImportController.activeChapterIndex > 0;
    final hasNext = activeNovel != null &&
        _novelImportController.activeChapterIndex <
            activeNovel.chapters.length - 1;

    final controls = <MediaControl>[
      if (hasPrevious) MediaControl.skipToPrevious,
      _ttsService.isPlaying ? MediaControl.pause : MediaControl.play,
      MediaControl.stop,
      if (hasNext) MediaControl.skipToNext,
    ];

    final processingState = switch (_ttsService.playbackState) {
      ReaderPlaybackState.idle => AudioProcessingState.idle,
      ReaderPlaybackState.playing ||
      ReaderPlaybackState.paused ||
      ReaderPlaybackState.stopped => AudioProcessingState.ready,
      ReaderPlaybackState.completed => AudioProcessingState.completed,
      ReaderPlaybackState.error => AudioProcessingState.error,
    };

    final compactActionIndices = <int>[];
    for (var i = 0; i < controls.length && compactActionIndices.length < 3; i++) {
      compactActionIndices.add(i);
    }

    playbackState.add(
      playbackState.value.copyWith(
        controls: controls,
        systemActions: const {
          MediaAction.play,
          MediaAction.pause,
          MediaAction.playPause,
          MediaAction.stop,
          MediaAction.skipToNext,
          MediaAction.skipToPrevious,
        },
        androidCompactActionIndices: compactActionIndices,
        processingState: processingState,
        playing: _ttsService.isPlaying,
        queueIndex: activeNovel == null
            ? 0
            : _novelImportController.activeChapterIndex,
      ),
    );
  }
}
