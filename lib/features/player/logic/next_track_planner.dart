import 'dart:math' as math;

/// Decides which track plays after the current one, and keeps that decision.
///
/// The choice must be stable: the UI reads "up next" on every rebuild and the audio layer
/// pre-loads that same track, so a fresh random draw per read made the line spin like a lottery
/// until playback fixed it, and could even show a title and an artist of two different tracks.
/// The answer only changes when the current track, the shuffle flag or the playlist length does,
/// or when [invalidate] is called.
class NextTrackPlanner {
  NextTrackPlanner({math.Random? random}) : _random = random ?? math.Random();

  final math.Random _random;
  int? _next;
  int _current = -1;
  int _length = 0;
  bool _shuffled = false;

  /// Index to play after [current], or null when there is no other track to play.
  /// In shuffle mode it is never [current] itself.
  int? plan({
    required int current,
    required int length,
    required bool shuffled,
  }) {
    if (length < 2) {
      _next = null;
      return null;
    }
    final stale = _next == null ||
        _current != current ||
        _length != length ||
        _shuffled != shuffled ||
        _next! >= length;
    if (stale) {
      _current = current;
      _length = length;
      _shuffled = shuffled;
      _next = shuffled ? _pickOther(current, length) : (current + 1) % length;
    }
    return _next;
  }

  /// Forgets the decision (a track was removed, the list was cleared...): the next [plan] decides again.
  void invalidate() => _next = null;

  int _pickOther(int current, int length) {
    final i = _random.nextInt(length - 1);
    return i >= current ? i + 1 : i;
  }
}
