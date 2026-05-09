import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';

class FileImportService {
  Future<String?> importTextFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['txt'],
      withData: true,
    );

    if (result == null || result.files.isEmpty) {
      return null;
    }

    final file = result.files.single;
    if (file.bytes != null) {
      return utf8.decode(file.bytes!, allowMalformed: true);
    }

    final path = file.path;
    if (path == null) {
      return null;
    }

    return File(path).readAsString();
  }
}
