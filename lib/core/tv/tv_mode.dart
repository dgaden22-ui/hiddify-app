import 'dart:io';

import 'package:flutter/services.dart';

/// DgadenVPN: whether the app runs on Android TV / Google TV.
///
/// Read once at startup (see bootstrap) and then used synchronously: the TV
/// gets a remote-friendly home screen and no navigation rail.
abstract final class TvMode {
  static bool isTv = false;

  static Future<void> detect() async {
    if (!Platform.isAndroid) return;
    try {
      isTv = await const MethodChannel('com.dgaden.vpn/device').invokeMethod<bool>('isTv') ?? false;
    } catch (_) {
      isTv = false;
    }
  }
}
