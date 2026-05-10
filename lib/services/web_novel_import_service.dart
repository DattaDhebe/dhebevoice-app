import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

import '../models/novel_book.dart';

class WebNovelImportService {
  static const _maxChapters = 200;
  static const _headers = {
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 16) AppleWebKit/537.36 Chrome/136.0 Mobile Safari/537.36',
    'Accept-Language': 'en-US,en;q=0.9',
  };

  final http.Client _client = http.Client();

  Future<NovelBook> importNovelFromUrl(
    String rawUrl, {
    void Function(int current, int? total, String status)? onProgress,
  }) async {
    final startingUri = _normalizeUri(rawUrl);
    final firstPage = await _fetchPage(startingUri);
    final firstContent = _extractReadableText(firstPage.document);
    final looksLikeChapter = _looksLikeChapterPage(firstContent);

    final chapters = looksLikeChapter
        ? await _crawlChapterSequence(firstPage, onProgress: onProgress)
        : await _crawlChapterIndex(firstPage, onProgress: onProgress);

    if (chapters.isEmpty) {
      throw Exception(
        'Text Reader could not detect readable chapter content on this page.',
      );
    }

    final title = _extractBookTitle(firstPage.document, chapters.first.title);
    return NovelBook(
      id: '${DateTime.now().millisecondsSinceEpoch}_${startingUri.host.hashCode.abs()}',
      title: title,
      sourceUrl: firstPage.uri.toString(),
      importedAt: DateTime.now(),
      chapters: chapters,
    );
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

  Future<_FetchedPage> _fetchPage(Uri uri) async {
    final response = await _client.get(uri, headers: _headers);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Could not open ${uri.host} (${response.statusCode}).');
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
    void Function(int current, int? total, String status)? onProgress,
  }) async {
    final chapters = <NovelChapter>[];
    final visited = <String>{};
    _FetchedPage? current = firstPage;
    var index = 0;

    while (current != null && chapters.length < _maxChapters) {
      final key = current.uri.toString();
      if (!visited.add(key)) {
        break;
      }

      final content = _extractReadableText(current.document);
      if (content.trim().isEmpty) {
        break;
      }

      final title = _extractChapterTitle(current.document, index + 1);
      chapters.add(
        NovelChapter(
          title: title,
          url: current.uri.toString(),
          content: content,
          order: index,
        ),
      );
      index++;
      onProgress?.call(index, null, 'Downloaded $title');

      final nextUri = _findNextChapterUri(
        current.document,
        current.uri,
        visited,
      );
      if (nextUri == null) {
        break;
      }
      current = await _fetchPage(nextUri);
    }

    return chapters;
  }

  Future<List<NovelChapter>> _crawlChapterIndex(
    _FetchedPage firstPage, {
    void Function(int current, int? total, String status)? onProgress,
  }) async {
    final links = _extractChapterLinks(firstPage.document, firstPage.uri);
    if (links.isEmpty) {
      return _crawlChapterSequence(firstPage, onProgress: onProgress);
    }

    final chapters = <NovelChapter>[];
    for (var i = 0; i < links.length && i < _maxChapters; i++) {
      final entry = links[i];
      final page = await _fetchPage(entry.uri);
      final content = _extractReadableText(page.document);
      if (content.trim().isEmpty) {
        continue;
      }

      final title = entry.text.isNotEmpty
          ? entry.text
          : _extractChapterTitle(page.document, i + 1);
      chapters.add(
        NovelChapter(
          title: title,
          url: page.uri.toString(),
          content: content,
          order: chapters.length,
        ),
      );
      onProgress?.call(chapters.length, links.length, 'Downloaded $title');
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

  String _cleanTitle(String title, {required String fallback}) {
    final normalized = _normalizeText(title)
        .replaceAll(RegExp(r'\s*\|\s*.*$'), '')
        .replaceAll(RegExp(r'\s*-\s*.*$'), '');
    return normalized.isEmpty ? fallback : normalized;
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
