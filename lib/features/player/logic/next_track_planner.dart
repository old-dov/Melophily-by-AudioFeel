import 'dart:math' as math;

/// Decides which track plays after the current one, and keeps that decision.
///
/// The choice must be stable: the UI reads "up next" on every rebuild and the audio layer
/// pre-loads that same track, so a fresh random draw per read made the line spin like a lottery
/// until playback fixed it, and could even show a title and an artist of two different tracks.
/// The answer only changes when the current track or the shuffle flag does, when the playlist shrinks
/// below it (or, in order, changes length), or when [invalidate] is called. In shuffle a longer list
/// keeps the choice already made.
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
    // A longer playlist (a big folder being imported in batches while a track already plays)
    // must not re-roll a shuffle choice that is still valid, or "up next" would spin at every
    // batch. In order, the answer is a plain function of the length, so it is recomputed.
    final grew = _length != length;
    final stale = _next == null ||
        _current != current ||
        _shuffled != shuffled ||
        _next! >= length ||
        (grew && !shuffled);
    if (stale) {
      _next = shuffled ? _pickOther(current, length) : (current + 1) % length;
    }
    _current = current;
    _length = length;
    _shuffled = shuffled;
    return _next;
  }

  /// Forgets the decision (a track was removed, the list was cleared...): the next [plan] decides again.
  void invalidate() => _next = null;

  int _pickOther(int current, int length) {
    final i = _random.nextInt(length - 1);
    return i >= current ? i + 1 : i;
  }
}
