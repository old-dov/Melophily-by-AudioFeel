import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:onlyaudio_by_audiofeel/core/models/track.dart';
import 'package:onlyaudio_by_audiofeel/features/player/data/metadata_service.dart';

/// A minimal MP3: an ID3v2.3 tag (the given text frames and an optional cover) followed by a few
/// silent MPEG-1 Layer III frames, enough for the parser to find tags and a duration.
Uint8List _mp3({String? title, String? artist, String? album, Uint8List? cover}) {
  final frames = BytesBuilder();
  void text(String id, String? value) {
    if (value == null) return;
    final data = [0, ...latin1.encode(value)];
    frames.add(ascii.encode(id));
    frames.add(_be32(data.length));
    frames.add([0, 0]);
    frames.add(data);
  }

  text('TIT2', title);
  text('TPE1', artist);
  text('TALB', album);
  if (cover != null) {
    final data = [0, ...ascii.encode('image/png'), 0, 3, 0, ...cover];
    frames.add(ascii.encode('APIC'));
    frames.add(_be32(data.length));
    frames.add([0, 0]);
    frames.add(data);
  }
  final body = frames.toBytes();
  final out = BytesBuilder();
  out.add(ascii.encode('ID3'));
  out.add([3, 0, 0]);
  out.add(_syncSafe(body.length));
  out.add(body);
  for (var i = 0; i < 12; i++) {
    out.add([0xFF, 0xFB, 0x90, 0x00]);
    out.add(Uint8List(413)); // 417-byte frame at 128 kbit/s, 44.1 kHz
  }
  return out.toBytes();
}

List<int> _be32(int n) => [(n >> 24) & 0xFF, (n >> 16) & 0xFF, (n >> 8) & 0xFF, n & 0xFF];
List<int> _syncSafe(int n) => [(n >> 21) & 0x7F, (n >> 14) & 0x7F, (n >> 7) & 0x7F, n & 0x7F];

void main() {
  late Directory dir;
  final service = MetadataService();

  setUp(() => dir = Directory.systemTemp.createTempSync('melophily_meta_'));
  tearDown(() => dir.deleteSync(recursive: true));

  String write(String name, List<int> bytes) {
    final f = File('${dir.path}${Platform.pathSeparator}$name')..writeAsBytesSync(bytes);
    return f.path;
  }

  test('reads title, artist and album from the tags', () async {
    final path = write('a.mp3', _mp3(title: 'Pieces', artist: 'Sum 41', album: 'Chuck'));
    final t = await service.fromPath(path);
    expect(t.path, path);
    expect(t.title, 'Pieces');
    expect(t.artist, 'Sum 41');
    expect(t.album, 'Chuck');
  });

  test('missing tags fall back to the file name and the Unknown labels', () async {
    final path = write('no_tags.mp3', _mp3());
    final t = await service.fromPath(path);
    expect(t.title, 'no_tags.mp3');
    expect(t.artist, 'Unknown Artist');
    expect(t.album, 'Unknown Album');
  });

  test('an unreadable or missing file still yields a track, never an error', () async {
    final garbage = write('garbage.mp3', List<int>.filled(64, 7));
    expect((await service.fromPath(garbage)).title, 'garbage.mp3');
    final missing = '${dir.path}${Platform.pathSeparator}gone.mp3';
    expect((await service.fromPath(missing)).title, 'gone.mp3');
  });

  test('coverBytes returns the embedded picture, null when there is none', () async {
    final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2, 3, 4]);
    final withCover = write('c.mp3', _mp3(title: 'C', cover: png));
    expect(await service.coverBytes(withCover), png);
    expect(await service.coverBytes(write('n.mp3', _mp3(title: 'N'))), isNull);
    expect(await service.coverBytes('${dir.path}${Platform.pathSeparator}absent.mp3'), isNull);
  });

  test('a folder as big as the one that crashed (2800 files) is read in order, in chunks', () async {
    const count = 2800;
    final paths = <String>[
      for (var i = 0; i < count; i++)
        write('t${i.toString().padLeft(4, '0')}.mp3', _mp3(title: 'Track $i', artist: 'A${i % 7}')),
    ];
    final progress = <int>[];
    var seen = 0;
    var biggestBatch = 0;
    final tracks = await service.fromPaths(paths, onBatch: (batch, done, total) {
      seen += batch.length;
      if (batch.length > biggestBatch) biggestBatch = batch.length;
      expect(total, count);
      progress.add(done);
    });
    expect(tracks.length, count);
    expect(seen, count);
    expect(biggestBatch, lessThanOrEqualTo(MetadataService.chunkSize));
    expect(progress.last, count);
    expect(progress, orderedEquals([...progress]..sort()));
    for (var i = 0; i < count; i += 331) {
      expect(tracks[i].path, paths[i]);
      expect(tracks[i].title, 'Track $i');
    }
    expect(tracks.map((Track t) => t.path).toSet().length, count);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
