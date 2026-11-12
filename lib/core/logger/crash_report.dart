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
    // the VPN core (Go) writes why it died to stderr, which the app redirects
    // to stderr2.log. This runs before the core starts again, so the crashed
    // run's text is still in stderr2.log (.old holds the run before it).
    if (text.contains('CRASH_NATIVE')) await _reportCoreStderr(log);
    // how far starting the VPN got before the crash (ServiceTrace.kt)
    await _reportServiceTrace(log, dir);
  } catch (e) {
    log.warning('could not read the previous crash report: $e');
  }
}

Future<void> _reportServiceTrace(Logger log, Directory dir) async {
  try {
    final file = File('${dir.path}/dgaden_service_trace.txt');
    if (!await file.exists()) return;
    final lines = (await file.readAsLines()).where((l) => l.trim().isNotEmpty).toList();
    final last = lines.length > 20 ? lines.sublist(lines.length - 20) : lines;
    log.severe('VPN start steps before the crash:\n${last.join('\n')}');
  } catch (_) {}
}

Future<void> _reportCoreStderr(Logger log) async {
  final dirs = <Directory?>[];
  try {
    dirs.add(await getExternalStorageDirectory());
  } catch (_) {}
  try {
    dirs.add(await getApplicationDocumentsDirectory());
  } catch (_) {}
  final marker = RegExp(r'^(panic:|fatal error:|SIG[A-Z]+|runtime:|unexpected fault)', multiLine: true);
  for (final dir in dirs.whereType<Directory>()) {
    for (final name in ['stderr2.log', 'stderr2.log.old']) {
      try {
        final file = File('${dir.path}/$name');
        if (!await file.exists()) continue;
        final text = await file.readAsString();
        final start = marker.firstMatch(text)?.start;
        if (start == null) continue;
        final excerpt = text.substring(start);
        log.severe('core error ($name): ${excerpt.length > 3000 ? excerpt.substring(0, 3000) : excerpt}');
        return;
      } catch (_) {}
    }
  }
  log.warning('the VPN core left no error text in stderr2.log');
}
