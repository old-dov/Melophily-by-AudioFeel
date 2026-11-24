import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'app/only_audio_app.dart';
import 'core/single_instance_guard.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  switch (await SingleInstanceGuard.acquire()) {
    case GuardResult.alreadyRunning:
      debugPrint('Melophily is already running. Exiting duplicate instance.');
      exit(0); // a plain `return` left a windowless process behind
    case GuardResult.unavailable:
      debugPrint('Single-instance guard unavailable on this machine: starting anyway.');
    case GuardResult.acquired:
      break;
  }
  MediaKit.ensureInitialized();
  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      title: 'Melophily by AudioFeel',
      minimumSize: Size(700, 480),
    ),
    () async {
      await windowManager.show();
      await windowManager.focus();
    },
  );
  runApp(const OnlyAudioApp());
}
