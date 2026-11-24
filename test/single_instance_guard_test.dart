import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onlyaudio_by_audiofeel/core/single_instance_guard.dart';

SocketException _err(int code) =>
    SocketException('bind failed', osError: OSError('test', code));

/// A bind that fails with [codes] for the first ports, then really binds an ephemeral port.
Future<ServerSocket> Function(int) _scripted(Map<int, int> codesByPort, List<int> tried) {
  return (int port) async {
    tried.add(port);
    final code = codesByPort[port];
    if (code != null) throw _err(code);
    return ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  };
}

void main() {
  tearDown(() => SingleInstanceGuard.release());

  Future<bool> nobodyAnswers(int port) async => false;

  test('a port Windows forbids with nobody on it (10013, reserved range) is skipped, not taken for another instance', () async {
    final tried = <int>[];
    final r = await SingleInstanceGuard.acquire(
      ports: [100, 200, 300],
      bind: _scripted({100: 10013}, tried),
      probe: nobodyAnswers,
    );
    expect(r, GuardResult.acquired);
    expect(tried, [100, 200]);
  });

  test('a 10013 where a Melophily answers is another instance (Windows reports exclusive-bind clashes that way)', () async {
    final tried = <int>[];
    final r = await SingleInstanceGuard.acquire(
      ports: [100, 200],
      bind: _scripted({100: 10013}, tried),
      probe: (port) async => port == 100,
    );
    expect(r, GuardResult.alreadyRunning);
    expect(tried, [100]);
  });

  test('"address already in use" means another instance (Windows, Linux, macOS codes)', () async {
    for (final code in [10048, 98, 48]) {
      final tried = <int>[];
      final r = await SingleInstanceGuard.acquire(
        ports: [100, 200],
        bind: _scripted({100: code}, tried),
      );
      expect(r, GuardResult.alreadyRunning, reason: 'code $code');
      expect(tried, [100]);
    }
  });

  test('a second instance finds the same port taken even when the first port was forbidden', () async {
    // First instance: port 100 forbidden, holds 200. Second instance: 100 forbidden, 200 in use.
    final r = await SingleInstanceGuard.acquire(
      ports: [100, 200],
      bind: _scripted({100: 10013, 200: 10048}, <int>[]),
      probe: nobodyAnswers,
    );
    expect(r, GuardResult.alreadyRunning);
  });

  test('every port forbidden: run anyway rather than refuse to start', () async {
    final tried = <int>[];
    final r = await SingleInstanceGuard.acquire(
      ports: [100, 200, 300],
      bind: _scripted({100: 10013, 200: 10013, 300: 5}, tried),
      probe: nobodyAnswers,
    );
    expect(r, GuardResult.unavailable);
    expect(tried, [100, 200, 300]);
  });

  test('isAddressInUse only matches the in-use codes', () {
    expect(SingleInstanceGuard.isAddressInUse(_err(10048)), isTrue);
    expect(SingleInstanceGuard.isAddressInUse(_err(10013)), isFalse);
    expect(SingleInstanceGuard.isAddressInUse(const SocketException('no os error')), isFalse);
  });

  test('for real: the second acquire on the same port sees the first, release frees it', () async {
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = probe.port;
    await probe.close();

    expect(await SingleInstanceGuard.acquire(ports: [port]), GuardResult.acquired);
    // A second process would call acquire() while the first holds the port; simulate with a
    // direct second bind through the default binder.
    final held = await SingleInstanceGuard.acquire(ports: [port]);
    expect(held, GuardResult.alreadyRunning);
    await SingleInstanceGuard.release();
    expect(await SingleInstanceGuard.acquire(ports: [port]), GuardResult.acquired);
  });

  test('for real: an unrelated program holding the port is not mistaken for another Melophily', () async {
    final foreign = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    foreign.listen((c) {
      c.write('hello from something else');
      c.destroy();
    });
    final spare = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final sparePort = spare.port;
    await spare.close();
    // The foreign port is refused on Windows with 10013 and answers with the wrong greeting:
    // skip it and use the spare one. (On other systems the in-use code is taken at face value.)
    final r = await SingleInstanceGuard.acquire(ports: [foreign.port, sparePort]);
    await foreign.close();
    expect(r, anyOf(GuardResult.acquired, GuardResult.alreadyRunning));
    if (Platform.isWindows) expect(r, GuardResult.acquired);
  });
}
