import 'dart:io';

import 'package:file_picker/file_picker.dart';

class LibraryService {
  static const supportedExtensions = {
    '.mp3',
    '.wav',
    '.flac',
    '.ogg',
    '.m4a',
    '.aac',
  };

  Future<List<String>> pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions:
          supportedExtensions.map((e) => e.replaceFirst('.', '')).toList(),
    );
    if (result == null) return [];
    return result.paths.whereType<String>().toList();
  }

  Future<List<String>> pickFolderAndScan() async {
    final dirPath = await FilePicker.platform.getDirectoryPath();
    if (dirPath == null) return [];
    return scanFolder(dirPath);
  }

  /// Everything playable under [dirPath], sorted. Also used for folders dropped on the window.
  Future<List<String>> scanFolder(String dirPath) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) return [];
    // Asynchronous listing: a synchronous walk of a big tree on a slow disk froze the window.
    // A sub-folder we cannot read (permissions, recycle bin...) is skipped, not fatal.
    final files = <String>[];
    await for (final entity in dir
        .list(recursive: true, followLinks: false)
        .handleError((_) {}, test: (e) => e is FileSystemException)) {
      if (entity is! File) continue;
      final lower = entity.path.toLowerCase();
      if (supportedExtensions.any(lower.endsWith)) files.add(entity.path);
    }
    files.sort();
    return files;
  }

  /// Turns dropped paths (files and/or folders) into playable file paths.
  Future<List<String>> expandDropped(List<String> dropped) async {
    final out = <String>[];
    for (final path in dropped) {
      try {
        if (await FileSystemEntity.isDirectory(path)) {
          out.addAll(await scanFolder(path));
        } else if (supportedExtensions.any(path.toLowerCase().endsWith) &&
            await File(path).exists()) {
          out.add(path);
        }
      } on FileSystemException {
        // unreadable: skip it
      }
    }
    return out;
  }
}
