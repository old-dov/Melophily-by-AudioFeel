import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onlyaudio_by_audiofeel/features/library/data/library_service.dart';

void main() {
  test('dropped folders and files expand to playable paths only', () async {
    final tmp = await Directory.systemTemp.createTemp('mel_drop');
    addTearDown(() => tmp.delete(recursive: true));
    final album = Directory('${tmp.path}/album/sub')..createSync(recursive: true);
    File('${album.path}/b.mp3').writeAsStringSync('x');
    File('${album.path}/cover.jpg').writeAsStringSync('x');
    File('${tmp.path}/album/a.FLAC').writeAsStringSync('x');
    final single = File('${tmp.path}/single.wav')..writeAsStringSync('x');
    final notes = File('${tmp.path}/notes.txt')..writeAsStringSync('x');

    final out = await LibraryService().expandDropped(
        ['${tmp.path}/album', single.path, notes.path, '${tmp.path}/missing.mp3']);
    expect(out.map((p) => p.split(RegExp(r'[\\/]')).last).toList(),
        ['a.FLAC', 'b.mp3', 'single.wav']);
  });
}
