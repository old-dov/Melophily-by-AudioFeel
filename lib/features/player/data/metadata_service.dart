import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:path/path.dart' as p;

import '../../../core/models/track.dart';

/// Reads tags in pure Dart, away from the UI isolate.
///
/// Why not a native plugin: `flutter_media_metadata` answered its platform channel from a worker
/// thread and blocked the platform thread while it did, so importing a big folder froze the window
/// and could crash the app with an access violation (seen on a Windows To Go session with ~2800
/// tracks). Here nothing native is involved and the UI isolate only receives finished results.
class MetadataService {
  /// Files read per isolate hand-off: big enough to amortise the isolate start, small enough for
  /// the progress to move and the playlist to fill in steadily.
  static const chunkSize = 40;

  Future<Uint8List?> coverBytes(String trackPath) async {
    try {
      return await Isolate.run(() => _readCover(trackPath));
    } catch (_) {
      return null;
    }
  }

  Future<Track> fromPath(String trackPath) async {
    final tracks = await fromPaths([trackPath]);
    return tracks.first;
  }

  /// Reads [paths] in order, [chunkSize] at a time, and returns one [Track] per path. A file whose
  /// tags cannot be read still yields a track (titled after the file) instead of failing the lot.
  /// [onBatch] receives each finished chunk, so a caller can show the playlist filling up.
  /// [isCancelled] is asked before each chunk; once it says yes the rest is not read and the
  /// tracks read so far are returned.
  Future<List<Track>> fromPaths(
    List<String> paths, {
    void Function(List<Track> batch, int done, int total)? onBatch,
    bool Function()? isCancelled,
  }) async {
    final all = <Track>[];
    for (var i = 0; i < paths.length; i += chunkSize) {
      if (isCancelled?.call() ?? false) break;
      final chunk = paths.sublist(i, math.min(i + chunkSize, paths.length));
      List<Track> tracks;
      try {
        tracks = await Isolate.run(() => chunk.map(_readTrack).toList());
      } catch (_) {
        tracks = chunk.map(_fallbackTrack).toList();
      }
      all.addAll(tracks);
      onBatch?.call(tracks, all.length, paths.length);
    }
    return all;
  }

  Future<bool> exists(String trackPath) async {
    return File(trackPath).exists();
  }
}

Track _fallbackTrack(String path) => Track(path: path, title: p.basename(path));

Track _readTrack(String path) {
  try {
    final metadata = readMetadata(File(path), getImage: false);
    final title = metadata.title?.trim();
    final artist = metadata.artist?.trim();
    final album = metadata.album?.trim();
    return Track(
      path: path,
      title: (title == null || title.isEmpty) ? p.basename(path) : title,
      artist: (artist == null || artist.isEmpty) ? 'Unknown Artist' : artist,
      album: (album == null || album.isEmpty) ? 'Unknown Album' : album,
      durationMs: metadata.duration?.inMilliseconds ?? 0,
      year: metadata.year?.year,
    );
  } catch (_) {
    return _fallbackTrack(path);
  }
}

Uint8List? _readCover(String path) {
  final pictures = readMetadata(File(path), getImage: true).pictures;
  if (pictures.isEmpty) return null;
  final front = pictures.where((e) => e.pictureType == PictureType.coverFront);
  return (front.isNotEmpty ? front.first : pictures.first).bytes;
}
