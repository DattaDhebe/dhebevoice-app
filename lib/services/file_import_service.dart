import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:epub_pro/epub_pro.dart';
import 'package:file_picker/file_picker.dart';
import 'package:html/parser.dart' as html_parser;

import '../models/novel_book.dart';

enum ImportedReaderFileKind { text, epub }

class ImportedReaderFile {
  const ImportedReaderFile._({
    required this.kind,
    required this.name,
    this.text,
    this.book,
  });

  factory ImportedReaderFile.text({
    required String name,
    required String text,
  }) {
    return ImportedReaderFile._(
      kind: ImportedReaderFileKind.text,
      name: name,
      text: text,
    );
  }

  factory ImportedReaderFile.epub({
    required String name,
    required NovelBook book,
  }) {
    return ImportedReaderFile._(
      kind: ImportedReaderFileKind.epub,
      name: name,
      book: book,
    );
  }

  final ImportedReaderFileKind kind;
  final String name;
  final String? text;
  final NovelBook? book;
}

class FileImportService {
  Future<ImportedReaderFile?> importReaderFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['txt', 'epub'],
      withData: true,
    );

    if (result == null || result.files.isEmpty) {
      return null;
    }

    final file = result.files.single;
    final fileName =
        file.name.trim().isEmpty ? 'Imported file' : file.name.trim();
    final extension = _fileExtension(fileName);

    switch (extension) {
      case 'epub':
        final bytes = await _readBytes(file);
        if (bytes == null || bytes.isEmpty) {
          return null;
        }
        final book = await _parseEpub(bytes, fileName);
        return ImportedReaderFile.epub(name: fileName, book: book);
      case 'txt':
      default:
        final text = await _readText(file);
        if (text == null || text.trim().isEmpty) {
          return null;
        }
        return ImportedReaderFile.text(name: fileName, text: text.trim());
    }
  }

  Future<String?> importTextFile() async {
    final imported = await importReaderFile();
    if (imported == null || imported.kind != ImportedReaderFileKind.text) {
      return null;
    }
    return imported.text;
  }

  Future<String?> _readText(PlatformFile file) async {
    if (file.bytes != null) {
      return utf8.decode(file.bytes!, allowMalformed: true);
    }

    final path = file.path;
    if (path == null) {
      return null;
    }

    return File(path).readAsString();
  }

  Future<Uint8List?> _readBytes(PlatformFile file) async {
    if (file.bytes != null) {
      return file.bytes!;
    }

    final path = file.path;
    if (path == null) {
      return null;
    }

    return File(path).readAsBytes();
  }

  Future<NovelBook> _parseEpub(Uint8List bytes, String fileName) async {
    final epubBook = await EpubReader.readBook(bytes);
    final chapters = <NovelChapter>[];

    void visitChapter(EpubChapter chapter, {String? inheritedTitle}) {
      final rawTitle = (chapter.title ?? '').trim();
      final chapterTitle = rawTitle.isNotEmpty
          ? rawTitle
          : (inheritedTitle?.trim().isNotEmpty ?? false)
              ? inheritedTitle!.trim()
              : 'Chapter ${chapters.length + 1}';
      final plainText = _extractPlainText(chapter.htmlContent);

      if (plainText.isNotEmpty) {
        chapters.add(
          NovelChapter(
            title: chapterTitle,
            url: 'local-epub://$fileName#${chapters.length + 1}',
            content: plainText,
            order: chapters.length,
          ),
        );
      }

      for (final subChapter in chapter.subChapters) {
        visitChapter(subChapter, inheritedTitle: chapterTitle);
      }
    }

    for (final chapter in epubBook.chapters) {
      visitChapter(chapter);
    }

    if (chapters.isEmpty) {
      throw Exception(
        'DhebeVoice could not find readable chapter text inside this EPUB.',
      );
    }

    final title = (epubBook.title ?? '').trim().isNotEmpty
        ? epubBook.title!.trim()
        : _fileNameWithoutExtension(fileName);
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    return NovelBook(
      id: 'epub_$timestamp',
      title: title,
      sourceUrl: 'local-epub://$fileName',
      importedAt: DateTime.now(),
      chapters: chapters,
    );
  }

  String _extractPlainText(String? htmlContent) {
    if (htmlContent == null || htmlContent.trim().isEmpty) {
      return '';
    }

    final document = html_parser.parse(htmlContent);
    document
        .querySelectorAll('script, style, nav, footer, header, aside, svg')
        .forEach((element) => element.remove());

    final blocks = document
        .querySelectorAll('h1, h2, h3, h4, p, li, blockquote')
        .map((element) => _normalizeText(element.text))
        .where((text) => text.isNotEmpty)
        .toList();

    if (blocks.isNotEmpty) {
      return blocks.join('\n\n');
    }

    return _normalizeText(document.body?.text ?? document.documentElement?.text);
  }

  String _normalizeText(String? input) {
    if (input == null) {
      return '';
    }
    return input.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _fileExtension(String fileName) {
    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex < 0 || dotIndex == fileName.length - 1) {
      return 'txt';
    }
    return fileName.substring(dotIndex + 1).toLowerCase();
  }

  String _fileNameWithoutExtension(String fileName) {
    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex <= 0) {
      return fileName;
    }
    return fileName.substring(0, dotIndex);
  }
}
