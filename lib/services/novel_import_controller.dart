import 'package:flutter/foundation.dart';

import '../models/novel_book.dart';
import 'novel_library_service.dart';
import 'storage_service.dart';
import 'tts_service.dart';
import 'web_novel_import_service.dart';

class NovelImportController extends ChangeNotifier {
  NovelImportController({
    required StorageService storageService,
    required NovelLibraryService novelLibraryService,
    required WebNovelImportService webNovelImportService,
    required TtsService ttsService,
  })  : _storageService = storageService,
        _novelLibraryService = novelLibraryService,
        _webNovelImportService = webNovelImportService,
        _ttsService = ttsService;

  final StorageService _storageService;
  final NovelLibraryService _novelLibraryService;
  final WebNovelImportService _webNovelImportService;
  final TtsService _ttsService;

  List<NovelBook> _library = const [];
  NovelBook? _activeNovel;
  int _activeChapterIndex = 0;
  bool _isImporting = false;
  String? _importStatus;
  String? _errorMessage;
  double? _importProgress;

  List<NovelBook> get library => _library;
  NovelBook? get activeNovel => _activeNovel;
  int get activeChapterIndex => _activeChapterIndex;
  bool get isImporting => _isImporting;
  String? get importStatus => _importStatus;
  String? get errorMessage => _errorMessage;
  double? get importProgress => _importProgress;

  NovelChapter? get activeChapter =>
      _activeNovel == null || _activeNovel!.chapters.isEmpty
          ? null
          : _activeNovel!.chapters[_activeChapterIndex];

  Future<void> initialize() async {
    _library = await _novelLibraryService.loadLibrary();
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
      await importNovelFromUrl(trimmed);
      return;
    }

    await clearActiveNovel();
    await _ttsService.handleSharedText(trimmed);
  }

  bool _looksLikeUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null) {
      return false;
    }
    return (uri.hasScheme && uri.host.isNotEmpty) ||
        (!uri.hasScheme && uri.host.isNotEmpty);
  }

  Future<void> importNovelFromUrl(String url) async {
    _isImporting = true;
    _importStatus = 'Connecting to source...';
    _importProgress = null;
    _errorMessage = null;
    notifyListeners();

    try {
      final imported = await _webNovelImportService.importNovelFromUrl(
        url,
        onProgress: (current, total, status) {
          _importStatus = status;
          _importProgress = total == null || total == 0
              ? null
              : current / total;
          notifyListeners();
        },
      );

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
      await selectNovel(imported.id, chapterIndex: 0);
      _importStatus = 'Imported ${imported.chapters.length} chapters';
    } catch (error) {
      _errorMessage = error.toString().replaceFirst('Exception: ', '');
    } finally {
      _isImporting = false;
      _importProgress = null;
      notifyListeners();
    }
  }

  Future<void> selectNovel(String novelId, {int? chapterIndex}) async {
    final novelIndex = _library.indexWhere((entry) => entry.id == novelId);
    if (novelIndex < 0 || _library[novelIndex].chapters.isEmpty) {
      return;
    }

    _activeNovel = _library[novelIndex];
    _activeChapterIndex = chapterIndex ??
        _activeNovel!.lastReadChapterIndex
            .clamp(0, _activeNovel!.chapters.length - 1);

    await _storageService.saveActiveNovelId(_activeNovel!.id);
    await _storageService.saveActiveChapterIndex(_activeChapterIndex);
    await _ttsService.stop();
    await _ttsService.updateText(
      _activeNovel!.chapters[_activeChapterIndex].content,
      resetPosition: true,
    );
    notifyListeners();
  }

  Future<void> selectChapter(int chapterIndex) async {
    final novel = _activeNovel;
    if (novel == null || chapterIndex < 0 || chapterIndex >= novel.chapters.length) {
      return;
    }

    _activeChapterIndex = chapterIndex;
    await _storageService.saveActiveChapterIndex(chapterIndex);
    await _updateLastReadChapter(novel.id, chapterIndex);
    await _ttsService.stop();
    await _ttsService.updateText(
      novel.chapters[chapterIndex].content,
      resetPosition: true,
    );
    notifyListeners();
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
}
