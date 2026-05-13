import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

import '../models/novel_book.dart';

class WebNovelImportService {
  static const _maxChapters = 200;
  static const defaultAccessModeId = 'mobile_browser';
  static const accessModes = [
    WebAccessMode(
      id: defaultAccessModeId,
      label: 'Mobile browser (Current)',
      description: 'Keeps the current Android Chrome-style import behavior.',
    ),
    WebAccessMode(
      id: 'desktop_browser',
      label: 'Desktop browser',
      description: 'Uses desktop Chrome headers for sites that block mobile requests.',
    ),
    WebAccessMode(
      id: 'browser_with_referer',
      label: 'Browser + referer',
      description: 'Adds a matching site referer and broader browser headers.',
    ),
    WebAccessMode(
      id: 'googlebot',
      label: 'Googlebot',
      description: 'Tries crawler-style headers for strict 403 or anti-bot blocks.',
    ),
  ];

  final http.Client _client = http.Client();

  Future<NovelBook> importNovelFromUrl(
    String rawUrl, {
    String accessModeId = defaultAccessModeId,
    void Function(int current, int? total, String status)? onProgress,
    bool Function()? shouldCancel,
  }) async {
    final result = await importNovelResultFromUrl(
      rawUrl,
      accessModeId: accessModeId,
      onProgress: onProgress,
      shouldCancel: shouldCancel,
    );
    if (result.book != null) {
      return result.book!;
    }
    throw Exception('Import stopped before any chapters were imported.');
  }

  Future<NovelImportResult> importNovelResultFromUrl(
    String rawUrl, {
    String accessModeId = defaultAccessModeId,
    void Function(int current, int? total, String status)? onProgress,
    bool Function()? shouldCancel,
  }) async {
    final resolvedAccessModeId = normalizeAccessModeId(accessModeId);
    final startingUri = _normalizeUri(rawUrl);
    final firstPage = await _fetchPage(
      startingUri,
      accessModeId: resolvedAccessModeId,
    );
    if (_shouldStop(shouldCancel)) {
      return const NovelImportResult(wasCancelled: true);
    }
    final firstContent = _extractReadableText(firstPage.document);
    final looksLikeChapter = _looksLikeChapterPage(firstContent);

    if (looksLikeChapter) {
      final firstChapterLabel = _resolveChapterTitle(
        uri: firstPage.uri,
        index: 1,
        rawTitle: _extractChapterTitle(firstPage.document, 1),
      );
      onProgress?.call(1, null, 'Importing $firstChapterLabel');
    }

    final chapters = looksLikeChapter
        ? await _crawlChapterSequence(
            firstPage,
            accessModeId: resolvedAccessModeId,
            onProgress: onProgress,
            shouldCancel: shouldCancel,
          )
        : await _crawlChapterIndex(
            firstPage,
            accessModeId: resolvedAccessModeId,
            onProgress: onProgress,
            shouldCancel: shouldCancel,
          );

    if (chapters.isEmpty) {
      if (_shouldStop(shouldCancel)) {
        return const NovelImportResult(wasCancelled: true);
      }
      throw Exception(
        'DhebeVoice could not detect readable chapter content on this page.',
      );
    }

    final title = _extractBookTitle(firstPage.document, chapters.first.title);
    return NovelImportResult(
      book: NovelBook(
        id:
            '${DateTime.now().millisecondsSinceEpoch}_${startingUri.host.hashCode.abs()}',
        title: title,
        sourceUrl: firstPage.uri.toString(),
        importedAt: DateTime.now(),
        chapters: chapters,
      ),
      wasCancelled: _shouldStop(shouldCancel),
    );
  }

  static String normalizeAccessModeId(String? value) {
    if (value == null || value.trim().isEmpty) {
      return defaultAccessModeId;
    }

    final normalized = value.trim();
    return accessModes.any((mode) => mode.id == normalized)
        ? normalized
        : defaultAccessModeId;
  }

  Uri _normalizeUri(String input) {
    final trimmed = input.trim();
    final candidate = trimmed.startsWith('http')
        ? trimmed
        : 'https://$trimmed';
    final uri = Uri.tryParse(candidate);
    if (uri == null || (!uri.hasScheme || uri.host.isEmpty)) {
      throw Exception('That shared text is not a valid web link.');
    }
    return uri;
  }

  Future<_FetchedPage> _fetchPage(
    Uri uri, {
    required String accessModeId,
  }) async {
    final resolvedAccessModeId = normalizeAccessModeId(accessModeId);
    final response = await _client.get(
      uri,
      headers: _headersForMode(uri, resolvedAccessModeId),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == 403) {
        throw Exception(
          '${uri.host} blocked ${_accessModeLabel(resolvedAccessModeId)} with a 403 error. Choose another website access mode and try again.',
        );
      }
      throw Exception(
        'Could not open ${uri.host} (${response.statusCode}) using ${_accessModeLabel(resolvedAccessModeId)}.',
      );
    }

    final decoded = utf8.decode(response.bodyBytes, allowMalformed: true);
    final document = html_parser.parse(decoded);
    return _FetchedPage(
      uri: response.request?.url ?? uri,
      document: document,
    );
  }

  Future<List<NovelChapter>> _crawlChapterSequence(
    _FetchedPage firstPage, {
    required String accessModeId,
    void Function(int current, int? total, String status)? onProgress,
    bool Function()? shouldCancel,
  }) async {
    final chapters = <NovelChapter>[];
    final visited = <String>{};
    _FetchedPage? current = firstPage;
    var index = 0;

    while (current != null && chapters.length < _maxChapters) {
      if (_shouldStop(shouldCancel) && chapters.isNotEmpty) {
        break;
      }

      final key = current.uri.toString();
      if (!visited.add(key)) {
        break;
      }

      final content = _extractReadableText(current.document);
      if (content.trim().isEmpty) {
        break;
      }

      final chapterNumber = index + 1;
      final title = _resolveChapterTitle(
        uri: current.uri,
        index: chapterNumber,
        rawTitle: _extractChapterTitle(current.document, chapterNumber),
      );
      chapters.add(
        NovelChapter(
          title: title,
          url: current.uri.toString(),
          content: content,
          order: index,
        ),
      );
      index++;

      final nextUri = _findNextChapterUri(
        current.document,
        current.uri,
        visited,
      );
      if (nextUri == null) {
        break;
      }
      if (_shouldStop(shouldCancel)) {
        break;
      }
      final nextChapterLabel = _resolveChapterTitle(
        uri: nextUri,
        index: index + 1,
      );
      onProgress?.call(index + 1, null, 'Importing $nextChapterLabel');
      current = await _fetchPage(nextUri, accessModeId: accessModeId);
    }

    return chapters;
  }

  Future<List<NovelChapter>> _crawlChapterIndex(
    _FetchedPage firstPage, {
    required String accessModeId,
    void Function(int current, int? total, String status)? onProgress,
    bool Function()? shouldCancel,
  }) async {
    final links = _extractChapterLinks(firstPage.document, firstPage.uri);
    if (links.isEmpty) {
      return _crawlChapterSequence(
        firstPage,
        accessModeId: accessModeId,
        onProgress: onProgress,
        shouldCancel: shouldCancel,
      );
    }

    final chapters = <NovelChapter>[];
    for (var i = 0; i < links.length && i < _maxChapters; i++) {
      if (_shouldStop(shouldCancel) && chapters.isNotEmpty) {
        break;
      }

      final entry = links[i];
      final chapterNumber = i + 1;
      final chapterLabel = _resolveChapterTitle(
        uri: entry.uri,
        index: chapterNumber,
        rawTitle: entry.text,
      );
      onProgress?.call(
        chapterNumber,
        links.length,
        'Importing $chapterLabel',
      );
      final page = await _fetchPage(entry.uri, accessModeId: accessModeId);
      final content = _extractReadableText(page.document);
      if (content.trim().isEmpty) {
        continue;
      }

      final title = _resolveChapterTitle(
        uri: page.uri,
        index: chapterNumber,
        rawTitle: entry.text.isNotEmpty
            ? entry.text
            : _extractChapterTitle(page.document, chapterNumber),
      );
      chapters.add(
        NovelChapter(
          title: title,
          url: page.uri.toString(),
          content: content,
          order: chapters.length,
        ),
      );
    }

    return chapters;
  }

  bool _looksLikeChapterPage(String content) {
    final words = content.split(RegExp(r'\s+')).where((word) => word.isNotEmpty);
    return words.length >= 120;
  }

  String _extractReadableText(dom.Document document) {
    for (final selector in const [
      'article',
      'main',
      '[id*=chapter]',
      '[class*=chapter]',
      '[class*=content]',
      '[class*=entry-content]',
      '[class*=post-content]',
      '[class*=reading-content]',
    ]) {
      final candidate = document.querySelector(selector);
      final text = _textFromNode(candidate);
      if (_looksLikeChapterPage(text)) {
        return text;
      }
    }

    String best = '';
    for (final element in document.querySelectorAll('div, section, article, main')) {
      final text = _textFromNode(element);
      if (text.length > best.length) {
        best = text;
      }
    }
    return best.trim();
  }

  String _textFromNode(dom.Element? node) {
    if (node == null) {
      return '';
    }

    node.querySelectorAll(
      'script, style, nav, footer, header, aside, form, noscript, iframe',
    ).forEach((element) => element.remove());

    final paragraphs = node
        .querySelectorAll('p, blockquote, li')
        .map((element) => _normalizeText(element.text))
        .where((text) => text.length > 20)
        .toList();

    if (paragraphs.length >= 3) {
      return paragraphs.join('\n\n');
    }

    return _normalizeText(node.text);
  }

  String _extractBookTitle(dom.Document document, String fallback) {
    final title = document.querySelector('meta[property="og:title"]')?.attributes['content'] ??
        document.querySelector('h1')?.text ??
        document.querySelector('title')?.text ??
        fallback;
    return _cleanTitle(title, fallback: fallback);
  }

  String _extractChapterTitle(dom.Document document, int index) {
    final title = document.querySelector('h1')?.text ??
        document.querySelector('title')?.text ??
        'Chapter $index';
    return _cleanTitle(title, fallback: 'Chapter $index');
  }

  String _resolveChapterTitle({
    required Uri uri,
    required int index,
    String? rawTitle,
  }) {
    final cleanedTitle = rawTitle == null
        ? ''
        : _cleanTitle(rawTitle, fallback: '');
    final slugTitle = _titleFromPath(uri);

    if (_looksLikeChapterLabel(cleanedTitle)) {
      return cleanedTitle;
    }
    if (_looksLikeChapterLabel(slugTitle)) {
      return slugTitle;
    }
    if (cleanedTitle.isNotEmpty) {
      return cleanedTitle;
    }
    if (slugTitle.isNotEmpty) {
      return slugTitle;
    }
    return 'Chapter $index';
  }

  String _cleanTitle(String title, {required String fallback}) {
    final normalized = _normalizeText(title)
        .replaceAll(RegExp(r'\s*\|\s*.*$'), '')
        .replaceAll(RegExp(r'\s*-\s*.*$'), '');
    return normalized.isEmpty ? fallback : normalized;
  }

  bool _looksLikeChapterLabel(String value) {
    final normalized = value.toLowerCase();
    return normalized.contains('chapter') ||
        normalized.contains('episode') ||
        normalized.contains('prologue') ||
        normalized.contains('part ');
  }

  String _titleFromPath(Uri uri) {
    if (uri.pathSegments.isEmpty) {
      return '';
    }

    final slug = uri.pathSegments.last.replaceAll(
      RegExp(r'\.[a-zA-Z0-9]+$'),
      '',
    );
    final normalized = _normalizeText(slug.replaceAll(RegExp(r'[-_]+'), ' '));
    if (normalized.isEmpty) {
      return '';
    }

    return normalized
        .split(' ')
        .map(_titleCaseWord)
        .join(' ');
  }

  String _titleCaseWord(String word) {
    if (word.isEmpty || RegExp(r'^\d+$').hasMatch(word)) {
      return word;
    }
    return '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}';
  }

  Uri? _findNextChapterUri(
    dom.Document document,
    Uri baseUri,
    Set<String> visited,
  ) {
    for (final selector in const ['a[rel=next]', 'link[rel=next]']) {
      final href = document.querySelector(selector)?.attributes['href'];
      final resolved = _resolveLink(baseUri, href);
      if (_isCandidateNext(baseUri, resolved, visited)) {
        return resolved;
      }
    }

    final anchors = document.querySelectorAll('a[href]');
    final candidates = <_ChapterLink>[];
    for (final anchor in anchors) {
      final href = anchor.attributes['href'];
      final resolved = _resolveLink(baseUri, href);
      if (!_isCandidateNext(baseUri, resolved, visited)) {
        continue;
      }

      final text = _normalizeText(anchor.text).toLowerCase();
      var score = 0;
      if (text.contains('next chapter')) score += 20;
      if (text.contains('next')) score += 8;
      if (text.contains('continue')) score += 6;
      if ((href ?? '').toLowerCase().contains('next')) score += 5;
      if ((href ?? '').toLowerCase().contains('chapter')) score += 3;
      if (score > 0) {
        candidates.add(_ChapterLink(uri: resolved!, text: text, score: score));
      }
    }

    candidates.sort((a, b) => b.score.compareTo(a.score));
    return candidates.isEmpty ? null : candidates.first.uri;
  }

  List<_ChapterLink> _extractChapterLinks(dom.Document document, Uri baseUri) {
    final seen = <String>{};
    final candidates = <_ChapterLink>[];

    for (final anchor in document.querySelectorAll('a[href]')) {
      final href = anchor.attributes['href'];
      final resolved = _resolveLink(baseUri, href);
      if (resolved == null || resolved.host != baseUri.host) {
        continue;
      }

      final text = _normalizeText(anchor.text);
      final textLower = text.toLowerCase();
      final hrefLower = href!.toLowerCase();
      final looksLikeChapter = textLower.contains('chapter') ||
          textLower.contains('episode') ||
          textLower.contains('prologue') ||
          hrefLower.contains('chapter') ||
          hrefLower.contains('episode');

      if (!looksLikeChapter || !seen.add(resolved.toString())) {
        continue;
      }

      candidates.add(
        _ChapterLink(
          uri: resolved,
          text: text,
          score: _chapterOrderScore(text, resolved.path),
        ),
      );
    }

    candidates.sort((a, b) => a.score.compareTo(b.score));
    return candidates;
  }

  int _chapterOrderScore(String text, String path) {
    final match = RegExp(r'(\d+)').firstMatch('$text $path');
    if (match == null) {
      return 1 << 20;
    }
    return int.tryParse(match.group(1) ?? '') ?? (1 << 20);
  }

  bool _isCandidateNext(Uri baseUri, Uri? candidate, Set<String> visited) {
    if (candidate == null) {
      return false;
    }
    if (!{'http', 'https'}.contains(candidate.scheme)) {
      return false;
    }
    if (candidate.host != baseUri.host) {
      return false;
    }
    if (candidate.toString() == baseUri.toString()) {
      return false;
    }
    if (visited.contains(candidate.toString())) {
      return false;
    }
    return true;
  }

  Uri? _resolveLink(Uri baseUri, String? href) {
    if (href == null || href.trim().isEmpty) {
      return null;
    }
    final trimmed = href.trim();
    if (trimmed.startsWith('#') || trimmed.startsWith('javascript:')) {
      return null;
    }
    return baseUri.resolve(trimmed);
  }

  String _normalizeText(String input) {
    return input.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  Map<String, String> _headersForMode(Uri uri, String accessModeId) {
    final referer = _rootUri(uri).toString();
    const common = {
      'Accept':
          'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
      'Accept-Language': 'en-US,en;q=0.9',
      'Cache-Control': 'no-cache',
      'Pragma': 'no-cache',
    };

    switch (normalizeAccessModeId(accessModeId)) {
      case 'desktop_browser':
        return {
          ...common,
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/136.0.0.0 Safari/537.36',
          'Upgrade-Insecure-Requests': '1',
        };
      case 'browser_with_referer':
        return {
          ...common,
          'User-Agent':
              'Mozilla/5.0 (Linux; Android 16) AppleWebKit/537.36 Chrome/136.0 Mobile Safari/537.36',
          'Referer': referer,
          'Origin': referer.endsWith('/')
              ? referer.substring(0, referer.length - 1)
              : referer,
          'Upgrade-Insecure-Requests': '1',
        };
      case 'googlebot':
        return {
          ...common,
          'User-Agent':
              'Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)',
          'Referer': referer,
        };
      case defaultAccessModeId:
      default:
        return {
          ...common,
          'User-Agent':
              'Mozilla/5.0 (Linux; Android 16) AppleWebKit/537.36 Chrome/136.0 Mobile Safari/537.36',
        };
    }
  }

  String _accessModeLabel(String accessModeId) {
    return accessModes
        .firstWhere(
          (mode) => mode.id == normalizeAccessModeId(accessModeId),
          orElse: () => accessModes.first,
        )
        .label;
  }

  Uri _rootUri(Uri uri) {
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: '/',
    );
  }

  bool _shouldStop(bool Function()? shouldCancel) {
    return shouldCancel?.call() ?? false;
  }
}

class NovelImportResult {
  const NovelImportResult({
    this.book,
    this.wasCancelled = false,
  });

  final NovelBook? book;
  final bool wasCancelled;
}

class _FetchedPage {
  const _FetchedPage({
    required this.uri,
    required this.document,
  });

  final Uri uri;
  final dom.Document document;
}

class _ChapterLink {
  const _ChapterLink({
    required this.uri,
    required this.text,
    required this.score,
  });

  final Uri uri;
  final String text;
  final int score;
}

class WebAccessMode {
  const WebAccessMode({
    required this.id,
    required this.label,
    required this.description,
  });

  final String id;
  final String label;
  final String description;
}
