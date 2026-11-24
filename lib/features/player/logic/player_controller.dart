import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../../core/models/player_state.dart';
import '../../../core/models/track.dart';
import '../../../core/services/storage_service.dart';
import '../../library/data/library_service.dart';
import '../data/audio_service.dart';
import '../data/metadata_service.dart';
import 'next_track_planner.dart';

class PlayerController extends ChangeNotifier {
  PlayerController({
    required AudioService audioService,
    required MetadataService metadataService,
    required StorageService storageService,
    required LibraryService libraryService,
  })  : _audioService = audioService,
        _metadataService = metadataService,
        _storageService = storageService,
        _libraryService = libraryService;

  final AudioService _audioService;
  final MetadataService _metadataService;
  final StorageService _storageService;
  final LibraryService _libraryService;

  final List<Track> _playlist = [];
  PlayerStateModel _state = PlayerStateModel();
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<bool>? _playingStateSub;
  StreamSubscription<void>? _completionSub;
  StreamSubscription<Duration>? _durationSub;

  bool _ready = false;
  bool _isPaused = true;
  Duration _currentPosition = Duration.zero;
  Duration _currentDuration = Duration.zero;
  final NextTrackPlanner _nextPlanner = NextTrackPlanner();
  bool _hasPlayed = false; // something was loaded: a re-decided next track is worth pre-loading
  String _cachedCoverPath = '';
  String _cachedCoverB64 = '';

  List<Track> get playlist => List.unmodifiable(_playlist);
  bool get ready => _ready;
  bool get isPaused => _isPaused;
  bool get isShuffled => _state.isShuffled;
  bool get isRepeat => _state.isRepeat;
  int get currentIndex => _state.currentIndex;
  double get volume => _state.volume;
  String get searchQuery => _state.searchQuery;
  String get sortMode => _state.sortMode;
  Duration get currentPosition => _currentPosition;
  // Fall back to the metadata duration if the stream hasn't fired yet
  Duration get currentDuration {
    if (_currentDuration.inMilliseconds > 0) return _currentDuration;
    final ms = currentTrack?.durationMs ?? 0;
    return ms > 0 ? Duration(milliseconds: ms) : Duration.zero;
  }

  Track? get currentTrack =>
      _playlist.isNotEmpty && _state.currentIndex < _playlist.length
          ? _playlist[_state.currentIndex]
          : null;

  // La piste que jouera le bouton "suivant" (ou la fin naturelle du titre) :
  // en mode Répéter c'est la piste courante qui rejoue, sinon celle retenue par
  // le planificateur. Le choix est stable (même réponse à chaque lecture) : l'UI
  // relit cette valeur à chaque rafraîchissement, un tirage aléatoire par lecture
  // faisait défiler « À suivre » comme une loterie.
  Track? get nextTrack {
    if (_playlist.length < 2) return null;
    if (_state.isRepeat) return currentTrack;
    final idx = _planNext();
    return idx == null ? null : _playlist[idx];
  }

  int? _planNext() => _nextPlanner.plan(
        current: _state.currentIndex,
        length: _playlist.length,
        shuffled: _state.isShuffled,
      );

  List<int> get visibleIndices {
    final indices = List<int>.generate(_playlist.length, (i) => i);
    switch (_state.sortMode) {
      case 'title':
        indices.sort((a, b) => _playlist[a]
            .title
            .toLowerCase()
            .compareTo(_playlist[b].title.toLowerCase()));
      case 'folder':
        indices.sort((a, b) => p
            .dirname(_playlist[a].path)
            .toLowerCase()
            .compareTo(p.dirname(_playlist[b].path).toLowerCase()));
      default:
        break;
    }
    final q = _state.searchQuery.toLowerCase().trim();
    if (q.isEmpty) return indices;
    return indices.where((i) {
      final t = _playlist[i];
      return t.title.toLowerCase().contains(q) ||
          t.path.toLowerCase().contains(q) ||
          t.album.toLowerCase().contains(q) ||
          t.artist.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> init() async {
    _playlist
      ..clear()
      ..addAll(await _storageService.loadPlaylist());
    _state = await _storageService.loadState();
    if (_state.currentIndex >= _playlist.length) {
      _state.currentIndex = _playlist.isEmpty ? 0 : _playlist.length - 1;
    }
    await _audioService.setVolume(_state.volume);
    _positionSub = _audioService.positionStream.listen((pos) {
      _currentPosition = pos;
      _state.positionMs = pos.inMilliseconds;
      notifyListeners();
    });
    _durationSub = _audioService.durationStream.listen((dur) {
      if (dur != _currentDuration) {
        _currentDuration = dur;
        notifyListeners();
      }
    });
    _playingStateSub = _audioService.playingStream.listen((playing) {
      _isPaused = !playing;
      notifyListeners();
    });
    _completionSub = _audioService.completionStream.listen((_) {
      if (_state.isRepeat) {
        unawaited(playAt(_state.currentIndex));
      } else {
        unawaited(next());
      }
    });

    // Restore the current track (without auto-playing) so that the duration
    // stream is populated and pressing PLAY actually produces sound.
    if (_playlist.isNotEmpty) {
      final seekTo = _state.positionMs > 0
          ? Duration(milliseconds: _state.positionMs)
          : null;
      try {
        await _audioService.playTrack(
          _playlist[_state.currentIndex],
          initialPosition: seekTo,
          autoPlay: false,
        );
      } catch (e, st) {
        // ignore: avoid_print
        print('[PlayerController] init restore error: $e\n$st');
      }
    }

    _ready = true;
    _isPaused = true;
    notifyListeners();
  }

  Future<void> disposeController() async {
    await _persist();
    await _positionSub?.cancel();
    await _playingStateSub?.cancel();
    await _completionSub?.cancel();
    await _durationSub?.cancel();
    await _audioService.dispose();
  }

  // Full persist: playlist (with cover art) + state. Only call when playlist changes.
  Future<void> _persist() async {
    await _storageService.savePlaylist(_playlist);
    await _storageService.saveState(_state);
  }

  // Fast persist: state only (no cover art serialization). Use for playback changes.
  Future<void> _persistState() async {
    await _storageService.saveState(_state);
  }

  Future<void> addFiles() async {
    final paths = await _libraryService.pickFiles();
    await _addTrackPaths(paths);
  }

  Future<void> addFolder() async {
    final paths = await _libraryService.pickFolderAndScan();
    await _addTrackPaths(paths);
  }

  /// Files and folders dropped on the window: the way in when the system folder dialog fails.
  Future<void> addDropped(List<String> dropped) async {
    if (_isImporting) return;
    final paths = await _libraryService.expandDropped(dropped);
    await _addTrackPaths(paths);
  }

  // Import progress, for the UI (a big folder takes a while: tags are read off the UI isolate).
  bool _isImporting = false;
  int _importDone = 0;
  int _importTotal = 0;
  bool get isImporting => _isImporting;
  int get importDone => _importDone;
  int get importTotal => _importTotal;

  Future<void> _addTrackPaths(List<String> paths) async {
    if (paths.isEmpty || _isImporting) return;
    final known = _playlist.map((e) => e.path).toSet();
    final fresh = <String>[];
    for (final path in paths) {
      if (known.add(path)) fresh.add(path);
    }
    if (fresh.isEmpty) return;
    _isImporting = true;
    _importDone = 0;
    _importTotal = fresh.length;
    notifyListeners();
    try {
      await _metadataService.fromPaths(
        fresh,
        onBatch: (batch, done, total) {
          _playlist.addAll(batch);
          _importDone = done;
          notifyListeners();
        },
      );
    } finally {
      _isImporting = false;
    }
    await _persist();
    notifyListeners();
    if (_playlist.length == 1) {
      await playAt(0);
    }
  }

  Future<void> playAt(int index, {bool restorePosition = false}) async {
    if (_playlist.isEmpty) return;
    _state.currentIndex = index.clamp(0, _playlist.length - 1);
    final track = _playlist[_state.currentIndex];
    final seekTo =
        restorePosition ? Duration(milliseconds: _state.positionMs) : null;
    _currentDuration = Duration.zero;
    _currentPosition = Duration.zero;
    _isPaused = false;
    _hasPlayed = true;
    notifyListeners(); // Met à jour l'UI immédiatement (titre, pochette)
    try {
      await _audioService.playTrack(track, initialPosition: seekTo);
    } catch (e, st) {
      // ignore: avoid_print
      print('[PlayerController] playAt error: $e\n$st');
    }
    unawaited(_persistState());
    _schedulePreload();
  }

  void _schedulePreload() {
    final nextIdx = _planNext();
    if (nextIdx == null) return;
    unawaited(_audioService.preloadNext(_playlist[nextIdx]));
  }

  Future<void> playPause() async {
    if (_playlist.isEmpty) return;
    if (_isPaused) {
      await _audioService.play();
      _isPaused = false;
    } else {
      await _audioService.pause();
      _isPaused = true;
    }
    await _persistState();
    notifyListeners();
  }

  Future<void> next() async {
    if (_playlist.isEmpty) return;
    final idx = _planNext() ??
        _audioService.nextIndex(
          currentIndex: _state.currentIndex,
          length: _playlist.length,
          shuffled: _state.isShuffled,
        );
    await playAt(idx);
  }

  Future<void> prev() async {
    if (_playlist.isEmpty) return;
    final idx = _audioService.prevIndex(
      currentIndex: _state.currentIndex,
      length: _playlist.length,
    );
    await playAt(idx);
  }

  Future<void> setVolume(double value) async {
    _state.volume = value.clamp(0, 1);
    await _audioService.setVolume(_state.volume);
    await _persistState();
    notifyListeners();
  }

  Future<void> seek(Duration position) async {
    await _audioService.seek(position);
    _state.positionMs = position.inMilliseconds;
    await _persistState();
    notifyListeners();
  }

  Future<void> toggleShuffle() async {
    _state.isShuffled = !_state.isShuffled;
    await _persist();
    notifyListeners();
    // Le choix du suivant change avec le mode : on recharge celui qui sera réellement joué.
    if (_hasPlayed) _schedulePreload();
  }

  Future<void> toggleRepeat() async {
    _state.isRepeat = !_state.isRepeat;
    await _persist();
    notifyListeners();
  }

  Future<void> cycleSortMode() async {
    const modes = ['added', 'title', 'folder'];
    final pos = modes.indexOf(_state.sortMode);
    _state.sortMode = modes[(pos + 1) % modes.length];
    await _persist();
    notifyListeners();
  }

  Future<void> setSearchQuery(String value) async {
    _state.searchQuery = value;
    await _persist();
    notifyListeners();
  }

  Future<void> removeCurrent() async {
    if (_playlist.isEmpty) return;
    final removed = _state.currentIndex;
    _playlist.removeAt(removed);
    _nextPlanner.invalidate(); // les index ont bougé
    if (_playlist.isEmpty) {
      _state.currentIndex = 0;
      _state.positionMs = 0;
      await _audioService.stop();
      _isPaused = true;
    } else {
      if (_state.currentIndex >= _playlist.length) {
        _state.currentIndex = _playlist.length - 1;
      }
      await playAt(_state.currentIndex);
    }
    await _persist();
    notifyListeners();
  }

  Future<void> clearPlaylist() async {
    _playlist.clear();
    _nextPlanner.invalidate();
    _state.currentIndex = 0;
    _state.positionMs = 0;
    _isPaused = true;
    await _audioService.stop();
    await _persist();
    notifyListeners();
  }

  void jumpToNowPlaying() {
    notifyListeners();
  }

  Future<Map<String, dynamic>> remoteStatusPayload() async {
    final current = currentTrack;
    if (current == null) {
      _cachedCoverPath = '';
      _cachedCoverB64 = '';
    } else if (current.path != _cachedCoverPath) {
      _cachedCoverPath = current.path;
      final bytes = await _metadataService.coverBytes(current.path);
      _cachedCoverB64 = bytes != null ? base64Encode(bytes) : '';
    }
    final next = nextTrack; // une seule lecture : titre et artiste du même morceau
    return {
      'title': current?.title ?? '',
      'artist': current?.artist ?? '',
      'album': current?.album ?? '',
      'year': current?.year,
      'pos': _currentPosition.inMilliseconds,
      'dur': currentDuration.inMilliseconds,
      'cover_b64': _cachedCoverB64,
      'is_playing': !_isPaused,
      'index': _state.currentIndex,
      'next_title': next?.title ?? '',
      'next_artist': next?.artist ?? '',
    };
  }

  Map<String, dynamic> remotePlaylistPayload() {
    return {
      'tracks': List.generate(
          _playlist.length,
          (i) => {
                'index': i,
                'title': _playlist[i].title,
                'folder': p.basename(p.dirname(_playlist[i].path)),
              }),
      'current_index': _state.currentIndex,
      'is_shuffled': _state.isShuffled,
      'is_repeat': _state.isRepeat,
      'volume': _state.volume,
    };
  }

  String exportPlaylistJson() =>
      jsonEncode(_playlist.map((t) => t.toJson()).toList());
}
