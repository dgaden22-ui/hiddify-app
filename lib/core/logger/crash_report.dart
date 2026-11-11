import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';

/// DgadenVPN: shows in the logs why the app died last time (Android).
///
/// The Android side (CrashRecorder.kt) writes the reason to this file in filesDir:
/// an uncaught exception's stack trace, or the exit reason Android recorded.
/// Read once at startup, logged as errors so they reach the logs page and app.log,
/// then removed so the same crash is not reported twice.
const _reportFile = 'dgaden_last_exit.txt';

Future<void> reportPreviousExit() async {
  if (!Platform.isAndroid) return;
  final log = Logger('app.CrashReport');
  try {
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/$_reportFile');
    if (!await file.exists()) return;
    final text = (await file.readAsString()).trim();
    await file.delete();
    if (text.isEmpty) return;
    for (final entry in text.split(RegExp(r'\n(?=app exit at |uncaught exception)'))) {
      log.severe('previous run ended: $entry');
    }
  } catch (e) {
    log.warning('could not read the previous crash report: $e');
  }
}
