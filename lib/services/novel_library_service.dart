import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/novel_book.dart';

class NovelLibraryService {
  Future<File> _libraryFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}${Platform.pathSeparator}novel_library.json');
  }

  Future<List<NovelBook>> loadLibrary() async {
    final file = await _libraryFile();
    if (!await file.exists()) {
      return const [];
    }

    final raw = await file.readAsString();
    if (raw.trim().isEmpty) {
      return const [];
    }

    final decoded = jsonDecode(raw);
    if (decoded is! List<dynamic>) {
      return const [];
    }

    return decoded
        .whereType<Map<dynamic, dynamic>>()
        .map(
          (entry) => entry.map(
            (key, value) => MapEntry(key.toString(), value),
          ),
        )
        .map(NovelBook.fromJson)
        .toList();
  }

  Future<void> saveLibrary(List<NovelBook> books) async {
    final file = await _libraryFile();
    final payload = jsonEncode(
      books.map((book) => book.toJson()).toList(),
    );
    await file.writeAsString(payload, flush: true);
  }
}
