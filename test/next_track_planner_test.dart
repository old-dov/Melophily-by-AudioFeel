import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:onlyaudio_by_audiofeel/features/player/logic/next_track_planner.dart';

void main() {
  int? plan(NextTrackPlanner p, {int current = 3, int length = 50, bool shuffled = true}) =>
      p.plan(current: current, length: length, shuffled: shuffled);

  test('the answer does not change between reads (the "lottery" bug)', () {
    final p = NextTrackPlanner(random: Random(1));
    final first = plan(p);
    for (var i = 0; i < 1000; i++) {
      expect(plan(p), first);
    }
  });

  test('sequential mode is the next index, wrapping at the end', () {
    final p = NextTrackPlanner();
    expect(plan(p, current: 0, length: 5, shuffled: false), 1);
    expect(plan(p, current: 4, length: 5, shuffled: false), 0);
  });

  test('shuffle never returns the current track and stays in range', () {
    final p = NextTrackPlanner(random: Random(7));
    for (var current = 0; current < 8; current++) {
      for (var round = 0; round < 200; round++) {
        p.invalidate();
        final n = plan(p, current: current, length: 8)!;
        expect(n, isNot(current));
        expect(n, inInclusiveRange(0, 7));
      }
    }
  });

  test('shuffle reaches every other track (not stuck on a few)', () {
    final p = NextTrackPlanner(random: Random(3));
    final seen = <int>{};
    for (var i = 0; i < 600; i++) {
      p.invalidate();
      seen.add(plan(p, current: 2, length: 6)!);
    }
    expect(seen, {0, 1, 3, 4, 5});
  });

  test('it decides again when the current track changes', () {
    final p = NextTrackPlanner(random: Random(5));
    final a = plan(p, current: 1, length: 30);
    final stable = plan(p, current: 1, length: 30);
    expect(stable, a);
    final b = plan(p, current: 2, length: 30)!;
    expect(b, isNot(2));
    expect(plan(p, current: 2, length: 30), b);
  });

  test('toggling shuffle re-plans, and the new answer is stable too', () {
    final p = NextTrackPlanner(random: Random(11));
    expect(plan(p, current: 4, length: 20, shuffled: false), 5);
    final s = plan(p, current: 4, length: 20, shuffled: true)!;
    expect(s, isNot(4));
    expect(plan(p, current: 4, length: 20, shuffled: true), s);
    expect(plan(p, current: 4, length: 20, shuffled: false), 5);
  });

  test('a changed playlist length re-plans, and a stale index is never returned', () {
    final p = NextTrackPlanner(random: Random(2));
    plan(p, current: 0, length: 40, shuffled: true);
    final n = plan(p, current: 0, length: 3, shuffled: true)!;
    expect(n, inInclusiveRange(1, 2));
  });

  test('invalidate forces a new decision', () {
    final p = NextTrackPlanner(random: Random(9));
    final seen = <int?>{};
    for (var i = 0; i < 200; i++) {
      p.invalidate();
      seen.add(plan(p, current: 0, length: 100));
    }
    expect(seen.length, greaterThan(20));
  });

  test('fewer than two tracks: nothing to plan', () {
    final p = NextTrackPlanner();
    expect(plan(p, current: 0, length: 0), isNull);
    expect(plan(p, current: 0, length: 1), isNull);
    expect(plan(p, current: 0, length: 1, shuffled: false), isNull);
    expect(plan(p, current: 0, length: 2, shuffled: true), 1);
  });

  test('a playlist that keeps growing (batched import) does not re-roll the shuffle choice', () {
    final p = NextTrackPlanner(random: Random(4));
    final first = plan(p, current: 0, length: 40)!;
    for (var length = 41; length <= 2800; length += 40) {
      expect(plan(p, current: 0, length: length), first);
    }
  });

  test('in order, a longer playlist is still followed correctly at the end of the list', () {
    final p = NextTrackPlanner();
    expect(plan(p, current: 4, length: 5, shuffled: false), 0);
    expect(plan(p, current: 4, length: 9, shuffled: false), 5);
  });
}
