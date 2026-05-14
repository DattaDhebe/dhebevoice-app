import 'package:flutter/foundation.dart';

import '../models/novel_book.dart';
import 'file_import_service.dart';
import 'novel_library_service.dart';
import 'storage_service.dart';
import 'tts_service.dart';
import 'web_novel_import_service.dart';

class NovelImportController extends ChangeNotifier {
  NovelImportController({
    required StorageService storageService,
    required FileImportService fileImportService,
    required NovelLibraryService novelLibraryService,
    required WebNovelImportService webNovelImportService,
    required TtsService ttsService,
  })  : _storageService = storageService,
        _fileImportService = fileImportService,
        _novelLibraryService = novelLibraryService,
        _webNovelImportService = webNovelImportService,
        _ttsService = ttsService {
    _ttsService.setPlaybackCompletedHandler(_handlePlaybackCompleted);
  }

  final StorageService _storageService;
  final FileImportService _fileImportService;
  final NovelLibraryService _novelLibraryService;
  final WebNovelImportService _webNovelImportService;
  final TtsService _ttsService;

  List<NovelBook> _library = const [];
  NovelBook? _activeNovel;
  int _activeChapterIndex = 0;
  bool _isImporting = false;
  bool _isCancellingImport = false;
  String? _importStatus;
  String? _errorMessage;
  double? _importProgress;
  String _selectedWebAccessModeId = WebNovelImportService.defaultAccessModeId;
  String? _pendingSharedUrl;

  List<NovelBook> get library => _library;
  NovelBook? get activeNovel => _activeNovel;
  int get activeChapterIndex => _activeChapterIndex;
  bool get isImporting => _isImporting;
  bool get isCancellingImport => _isCancellingImport;
  String? get importStatus => _importStatus;
  String? get errorMessage => _errorMessage;
  double? get importProgress => _importProgress;
  String get selectedWebAccessModeId => _selectedWebAccessModeId;
  String? get pendingSharedUrl => _pendingSharedUrl;
  bool get hasPendingSharedUrl =>
      _pendingSharedUrl != null && _pendingSharedUrl!.trim().isNotEmpty;
  List<WebAccessMode> get availableWebAccessModes =>
      WebNovelImportService.accessModes;

  NovelChapter? get activeChapter =>
      _activeNovel == null || _activeNovel!.chapters.isEmpty
          ? null
          : _activeNovel!.chapters[_activeChapterIndex];

  Future<void> initialize() async {
    _library = await _novelLibraryService.loadLibrary();
    _selectedWebAccessModeId = WebNovelImportService.normalizeAccessModeId(
      _storageService.webAccessModeId,
    );
    final savedNovelId = _storageService.activeNovelId;
    if (savedNovelId == null || savedNovelId.isEmpty) {
      notifyListeners();
      return;
    }

    final novelIndex = _library.indexWhere((entry) => entry.id == savedNovelId);
    if (novelIndex < 0) {
      notifyListeners();
      return;
    }

    _activeNovel = _library[novelIndex];
    _activeChapterIndex = _storageService.activeChapterIndex
        .clamp(0, _activeNovel!.chapters.length - 1);
    notifyListeners();
  }

  Future<void> handleSharedPayload(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return;
    }

    if (_looksLikeUrl(trimmed)) {
      await queueSharedUrl(trimmed);
      return;
    }

    await clearActiveNovel();
    await _ttsService.handleSharedText(trimmed);
  }

  Future<void> queueSharedUrl(String url) async {
    _pendingSharedUrl = url.trim();
    _errorMessage = null;
    _importProgress = null;
    _importStatus = 'Shared link ready. Review it, then start import.';
    notifyListeners();
  }

  Future<void> clearPendingSharedUrl() async {
    if (!hasPendingSharedUrl) {
      return;
    }

    _pendingSharedUrl = null;
    if (!_isImporting) {
      _importStatus = null;
      _errorMessage = null;
      _importProgress = null;
    }
    notifyListeners();
  }

  Future<void> importPendingSharedUrl({String? accessModeId}) async {
    final url = _pendingSharedUrl;
    if (url == null || url.trim().isEmpty) {
      return;
    }
    await importNovelFromUrl(url, accessModeId: accessModeId);
  }

  Future<void> setWebAccessMode(String modeId) async {
    final resolvedModeId = WebNovelImportService.normalizeAccessModeId(modeId);
    if (_selectedWebAccessModeId == resolvedModeId) {
      return;
    }

    _selectedWebAccessModeId = resolvedModeId;
    await _storageService.saveWebAccessModeId(resolvedModeId);
    notifyListeners();
  }

  Future<void> importLocalFile() async {
    _errorMessage = null;
    _importStatus = null;
    notifyListeners();

    try {
      final imported = await _fileImportService.importReaderFile();
      if (imported == null) {
        return;
      }

      switch (imported.kind) {
        case ImportedReaderFileKind.text:
          await clearActiveNovel();
          await _ttsService.stop();
          await _ttsService.updateText(imported.text!, resetPosition: true);
          _importStatus = 'Imported text file ${imported.name}.';
          break;
        case ImportedReaderFileKind.epub:
        case ImportedReaderFileKind.pdf:
          final book = imported.book!;
          final updated = [..._library];
          final existingIndex = updated.indexWhere(
            (entry) => entry.sourceUrl == book.sourceUrl,
          );
          if (existingIndex >= 0) {
            updated[existingIndex] = book;
          } else {
            updated.insert(0, book);
          }

          _library = updated;
          await _novelLibraryService.saveLibrary(updated);
          await selectNovel(book.id, chapterIndex: 0);
          final importType = switch (imported.kind) {
            ImportedReaderFileKind.epub => 'EPUB',
            ImportedReaderFileKind.pdf => 'PDF',
            ImportedReaderFileKind.text => 'text',
          };
          _importStatus =
              'Imported $importType ${book.title} with ${book.chapters.length} sections.';
          break;
      }
    } catch (error) {
      _errorMessage = error.toString().replaceFirst('Exception: ', '');
    } finally {
      notifyListeners();
    }
  }

  bool _looksLikeUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null) {
      return false;
    }
    return (uri.hasScheme && uri.host.isNotEmpty) ||
        (!uri.hasScheme && uri.host.isNotEmpty);
  }

  Future<void> importNovelFromUrl(String url, {String? accessModeId}) async {
    final resolvedAccessModeId = WebNovelImportService.normalizeAccessModeId(
      accessModeId ?? _selectedWebAccessModeId,
    );
    if (_selectedWebAccessModeId != resolvedAccessModeId) {
      _selectedWebAccessModeId = resolvedAccessModeId;
      await _storageService.saveWebAccessModeId(resolvedAccessModeId);
    }

    _isImporting = true;
    _isCancellingImport = false;
    _importStatus = 'Connecting to source...';
    _importProgress = null;
    _errorMessage = null;
    notifyListeners();
    var completedWithoutCancellation = false;

    try {
      final result = await _webNovelImportService.importNovelResultFromUrl(
        url,
        accessModeId: resolvedAccessModeId,
        onProgress: (current, total, status) {
          _importStatus = status;
          _importProgress = total == null || total == 0
              ? null
              : current / total;
          notifyListeners();
        },
        shouldCancel: () => _isCancellingImport,
      );

      final imported = result.book;
      final shouldAutoSelectImported = imported != null && !result.wasCancelled;

      if (imported != null) {
        final updated = [..._library];
        final existingIndex = updated.indexWhere(
          (book) => book.sourceUrl == imported.sourceUrl,
        );
        if (existingIndex >= 0) {
          updated[existingIndex] = imported;
        } else {
          updated.insert(0, imported);
        }
        _library = updated;
        await _novelLibraryService.saveLibrary(updated);
        if (shouldAutoSelectImported) {
          await selectNovel(imported.id, chapterIndex: 0);
        }
      }

      if (result.wasCancelled) {
        _importStatus = imported == null
            ? 'Import stopped.'
            : 'Stopped after ${imported.chapters.length} chapters. Saved to Books List.';
      } else if (imported != null) {
        _importStatus = 'Imported ${imported.chapters.length} chapters.';
        completedWithoutCancellation = true;
      }
    } catch (error) {
      _importStatus = 'Could not import that web page.';
      _errorMessage = _friendlyImportError(error);
    } finally {
      if (completedWithoutCancellation &&
          _pendingSharedUrl?.trim() == url.trim()) {
        _pendingSharedUrl = null;
      }
      _isImporting = false;
      _isCancellingImport = false;
      _importProgress = null;
      notifyListeners();
    }
  }

  Future<void> cancelImport() async {
    if (!_isImporting || _isCancellingImport) {
      return;
    }

    _isCancellingImport = true;
    _importStatus = 'Stopping import after the current chapter...';
    notifyListeners();
  }

  String _friendlyImportError(Object error) {
    final raw = error.toString().replaceFirst('Exception: ', '').trim();
    if (raw.isEmpty) {
      return 'Something went wrong while importing that web page. Please try again.';
    }

    return raw;
  }

  Future<void> selectNovel(String novelId, {int? chapterIndex}) async {
    final novelIndex = _library.indexWhere((entry) => entry.id == novelId);
    if (novelIndex < 0 || _library[novelIndex].chapters.isEmpty) {
      return;
    }

    final novel = _library[novelIndex];
    final resolvedChapterIndex = chapterIndex ??
        novel.lastReadChapterIndex.clamp(0, novel.chapters.length - 1);

    await _activateChapter(
      novel: novel,
      chapterIndex: resolvedChapterIndex,
      persistLastRead: false,
    );
  }

  Future<void> selectChapter(int chapterIndex) async {
    final novel = _activeNovel;
    if (novel == null || chapterIndex < 0 || chapterIndex >= novel.chapters.length) {
      return;
    }

    await _activateChapter(
      novel: novel,
      chapterIndex: chapterIndex,
      persistLastRead: true,
    );
  }

  Future<void> clearActiveNovel() async {
    _activeNovel = null;
    _activeChapterIndex = 0;
    await _storageService.saveActiveNovelId(null);
    await _storageService.saveActiveChapterIndex(0);
    notifyListeners();
  }

  Future<void> deleteNovel(String novelId) async {
    _library = _library.where((book) => book.id != novelId).toList();
    await _novelLibraryService.saveLibrary(_library);

    if (_activeNovel?.id == novelId) {
      await clearActiveNovel();
    } else {
      notifyListeners();
    }
  }

  Future<void> detachIfTextChanged(String value) async {
    final chapter = activeChapter;
    if (chapter == null) {
      return;
    }
    if (value == chapter.content) {
      return;
    }
    await clearActiveNovel();
  }

  Future<void> goToNextChapter() async {
    if (_activeNovel == null) {
      return;
    }
    if (_activeChapterIndex >= _activeNovel!.chapters.length - 1) {
      return;
    }
    await selectChapter(_activeChapterIndex + 1);
  }

  Future<void> goToPreviousChapter() async {
    if (_activeNovel == null || _activeChapterIndex <= 0) {
      return;
    }
    await selectChapter(_activeChapterIndex - 1);
  }

  Future<void> _updateLastReadChapter(String novelId, int chapterIndex) async {
    _library = _library.map((book) {
      if (book.id != novelId) {
        return book;
      }
      return book.copyWith(lastReadChapterIndex: chapterIndex);
    }).toList();

    final novelIndex = _library.indexWhere((entry) => entry.id == novelId);
    if (novelIndex >= 0) {
      _activeNovel = _library[novelIndex];
    }

    await _novelLibraryService.saveLibrary(_library);
  }

  Future<void> _handlePlaybackCompleted() async {
    final novel = _activeNovel;
    if (novel == null) {
      return;
    }
    if (_activeChapterIndex >= novel.chapters.length - 1) {
      return;
    }

    final nextIndex = _activeChapterIndex + 1;
    await selectChapter(nextIndex);
    await _ttsService.play();
  }

  Future<void> _activateChapter({
    required NovelBook novel,
    required int chapterIndex,
    required bool persistLastRead,
  }) async {
    _activeNovel = novel;
    _activeChapterIndex = chapterIndex;
    notifyListeners();

    await _storageService.saveActiveNovelId(novel.id);
    await _storageService.saveActiveChapterIndex(chapterIndex);
    if (persistLastRead) {
      await _updateLastReadChapter(novel.id, chapterIndex);
    }
    await _ttsService.stop();
    await _ttsService.updateText(
      novel.chapters[chapterIndex].content,
      resetPosition: true,
    );
    notifyListeners();
  }
}
