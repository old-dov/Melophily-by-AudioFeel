import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// What [SingleInstanceGuard.acquire] found out.
enum GuardResult {
  /// We hold the guard: we are the only instance.
  acquired,

  /// Another instance already holds it.
  alreadyRunning,

  /// No port could be reserved for another reason (forbidden, firewall...): run anyway.
  unavailable,
}

/// Keeps a second Melophily from starting, by holding a loopback port.
///
/// Windows reports WSAEACCES (10013) in two very different cases: the port is already held by
/// another socket bound exclusively (a second instance), or it sits in a range reserved by
/// Hyper-V, WSL or Docker (those ranges move at every boot). Treating every error as "already
/// running" made the app quit without a window, leaving an invisible process behind, as soon as
/// the reserved range covered our port. So an ambiguous refusal is checked: the holder greets
/// whoever connects, and only a Melophily greeting counts as another instance. A port nobody
/// answers on is skipped and the next one tried; every instance walks the same list in the same
/// order, so they still agree.
class SingleInstanceGuard {
  /// Far apart on purpose: reserved ranges are contiguous blocks of about 100 ports.
  static const defaultPorts = [43157, 47123, 51931, 39811];

  /// What the holder says to whoever connects.
  static const greeting = 'melophily-by-audiofeel';

  static ServerSocket? _held;

  /// "Address already in use": WSAEADDRINUSE on Windows, EADDRINUSE on Linux and macOS.
  static bool isAddressInUse(SocketException e) {
    final code = e.osError?.errorCode;
    return code == 10048 || code == 98 || code == 48;
  }

  static Future<GuardResult> acquire({
    List<int> ports = defaultPorts,
    Future<ServerSocket> Function(int port) bind = _bindLoopback,
    Future<bool> Function(int port) probe = _isMelophilyListening,
  }) async {
    for (final port in ports) {
      try {
        final server = await bind(port);
        _held = server;
        server.listen((client) {
          client.write(greeting);
          client.destroy();
        }, onError: (_) {});
        return GuardResult.acquired;
      } on SocketException catch (e) {
        if (isAddressInUse(e)) return GuardResult.alreadyRunning;
        // Refused for another reason (10013...): another instance, or a reserved port?
        if (await probe(port)) return GuardResult.alreadyRunning;
      }
    }
    return GuardResult.unavailable;
  }

  static Future<void> release() async {
    final held = _held;
    _held = null;
    await held?.close();
  }

  static Future<ServerSocket> _bindLoopback(int port) =>
      ServerSocket.bind(InternetAddress.loopbackIPv4, port, shared: false);

  /// True when something on [port] answers with [greeting].
  static Future<bool> _isMelophilyListening(int port) async {
    Socket? socket;
    try {
      socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        port,
        timeout: const Duration(milliseconds: 500),
      );
      final said = await utf8.decoder
          .bind(socket)
          .join()
          .timeout(const Duration(milliseconds: 500));
      return said == greeting;
    } catch (_) {
      return false;
    } finally {
      socket?.destroy();
    }
  }
}
