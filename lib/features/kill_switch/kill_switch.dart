import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/core/utils/preferences_utils.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// DgadenVPN Kill Switch: no traffic leaves the device outside the VPN when the
/// VPN drops unexpectedly.
///
/// * Android: the system's own kill switch ("Always-on VPN" + "Block connections
///   without VPN"). Android enforces it even if the app crashes. The app cannot
///   switch it on by itself, so it opens VPN settings and reads the state back.
/// * Windows: Windows Firewall. While engaged, outbound traffic is blocked by
///   policy and allowed only for DgadenVPN itself (it talks to the VPN server),
///   for the VPN tunnel's addresses and for the home network. It is engaged when
///   the VPN connects and stays engaged when the VPN drops or the app crashes;
///   it is released only when the user disconnects, quits or turns it off.
abstract final class KillSwitchPrefs {
  /// Windows only: engage the firewall block whenever the VPN connects.
  static final enabled = PreferencesNotifier.create<bool, bool>("dgaden-kill-switch", false);
}

bool get killSwitchSupported => Platform.isAndroid || Platform.isWindows;

// ---------------------------------------------------------------- Android

class AndroidKillSwitchStatus {
  const AndroidKillSwitchStatus({required this.sdk, required this.vpnRunning, this.alwaysOn, this.lockdown});

  final int sdk;
  final bool vpnRunning;

  /// null when it cannot be read: the VPN is not running, or Android is older than 10.
  final bool? alwaysOn;
  final bool? lockdown;

  bool get active => alwaysOn == true && lockdown == true;
}

abstract final class AndroidKillSwitch {
  static const _channel = MethodChannel('com.dgaden.vpn/device');

  static Future<AndroidKillSwitchStatus?> status() async {
    try {
      final map = await _channel.invokeMapMethod<String, dynamic>('killSwitchStatus');
      if (map == null) return null;
      return AndroidKillSwitchStatus(
        sdk: map['sdk'] as int? ?? 0,
        vpnRunning: map['vpnRunning'] as bool? ?? false,
        alwaysOn: map['alwaysOn'] as bool?,
        lockdown: map['lockdown'] as bool?,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<bool> openVpnSettings() async {
    try {
      return await _channel.invokeMethod<bool>('openVpnSettings') ?? false;
    } catch (_) {
      return false;
    }
  }
}

final androidKillSwitchStatusProvider = FutureProvider.autoDispose<AndroidKillSwitchStatus?>(
  (ref) => AndroidKillSwitch.status(),
);

// ---------------------------------------------------------------- Windows

class WindowsKillSwitchState {
  const WindowsKillSwitchState({required this.engaged, this.error});

  /// The firewall block is in place right now.
  final bool engaged;

  /// Why the last attempt to change the firewall failed, if it did.
  final String? error;
}

final windowsKillSwitchProvider = NotifierProvider<WindowsKillSwitch, WindowsKillSwitchState>(WindowsKillSwitch.new);

class WindowsKillSwitch extends Notifier<WindowsKillSwitchState> with InfraLogger {
  static const _engagedKey = 'dgaden-kill-switch-engaged';
  static const _policyKey = 'dgaden-kill-switch-saved-policy';
  static const _rulePrefix = 'DgadenVPN Kill Switch';
  static const _ruleNames = [
    '$_rulePrefix - app',
    '$_rulePrefix - core',
    '$_rulePrefix - tunnel',
    '$_rulePrefix - home network',
    '$_rulePrefix - dhcp',
    '$_rulePrefix - private networks',
    '$_rulePrefix - tailscale',
  ];
  static const _profiles = ['domainprofile', 'privateprofile', 'publicprofile'];

  /// Networks that never go through the VPN anyway: other LANs behind the router and
  /// Tailscale (100.64.0.0/10). Without this the block cut off a Synology reached over Tailscale.
  static const _privateAddresses = '10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,100.64.0.0/10';

  /// The core's TUN addresses (172.19.0.1/30, fdfe:dcba:9876::1/126), with room to spare.
  static const _tunnelAddresses = '172.19.0.0/16,fdfe:dcba:9876::/48';

  /// Windows Firewall can be changed only by an elevated process.
  static Future<bool> isElevated() async {
    if (!Platform.isWindows) return false;
    try {
      return (await Process.run('net', ['session'])).exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider).requireValue;

  @override
  WindowsKillSwitchState build() =>
      WindowsKillSwitchState(engaged: Platform.isWindows && (_prefs.getBool(_engagedKey) ?? false));

  /// Called when the VPN has connected.
  Future<void> onConnected() async {
    if (!Platform.isWindows || !ref.read(KillSwitchPrefs.enabled) || state.engaged) return;
    await engage();
  }

  /// Blocks all outbound traffic except DgadenVPN, the tunnel and the home network.
  Future<void> engage() async {
    if (!Platform.isWindows) return;
    try {
      if (!(_prefs.getBool(_engagedKey) ?? false)) {
        // remember the policy to give back; only the first time, so a crash
        // and a second engage never save our own blocking policy as "original"
        await _prefs.setString(_policyKey, jsonEncode(await _readPolicies()));
      }
      await _deleteRules();
      final exe = Platform.resolvedExecutable;
      final core = File('${File(exe).parent.path}${Platform.pathSeparator}HiddifyCli.exe');
      await _netsh(['advfirewall', 'firewall', 'add', 'rule', 'name=${_ruleNames[0]}', 'dir=out', 'action=allow', 'program=$exe', 'enable=yes', 'profile=any']);
      if (core.existsSync()) {
        await _netsh(['advfirewall', 'firewall', 'add', 'rule', 'name=${_ruleNames[1]}', 'dir=out', 'action=allow', 'program=${core.path}', 'enable=yes', 'profile=any']);
      }
      await _netsh(['advfirewall', 'firewall', 'add', 'rule', 'name=${_ruleNames[2]}', 'dir=out', 'action=allow', 'localip=$_tunnelAddresses', 'enable=yes', 'profile=any']);
      await _netsh(['advfirewall', 'firewall', 'add', 'rule', 'name=${_ruleNames[3]}', 'dir=out', 'action=allow', 'remoteip=LocalSubnet', 'enable=yes', 'profile=any']);
      await _netsh(['advfirewall', 'firewall', 'add', 'rule', 'name=${_ruleNames[4]}', 'dir=out', 'action=allow', 'protocol=UDP', 'localport=68', 'remoteport=67', 'enable=yes', 'profile=any']);
      await _netsh(['advfirewall', 'firewall', 'add', 'rule', 'name=${_ruleNames[5]}', 'dir=out', 'action=allow', 'remoteip=$_privateAddresses', 'enable=yes', 'profile=any']);
      // Tailscale's own WireGuard traffic, so its peers stay reachable while the VPN is down
      final tailscaled = File('${Platform.environment['ProgramFiles'] ?? r'C:\Program Files'}\\Tailscale\\tailscaled.exe');
      if (tailscaled.existsSync()) {
        await _netsh(['advfirewall', 'firewall', 'add', 'rule', 'name=${_ruleNames[6]}', 'dir=out', 'action=allow', 'program=${tailscaled.path}', 'enable=yes', 'profile=any']);
      }
      final saved = _savedPolicies();
      for (var i = 0; i < _profiles.length; i++) {
        await _netsh(['advfirewall', 'set', _profiles[i], 'firewallpolicy', '${saved[i].inbound},BlockOutbound']);
      }
      await _prefs.setBool(_engagedKey, true);
      state = const WindowsKillSwitchState(engaged: true);
      loggy.info('kill switch engaged');
    } catch (e) {
      loggy.warning('could not engage the kill switch', e);
      // never leave half of it in place: a blocking policy without the allow rules
      await _restore();
      state = WindowsKillSwitchState(engaged: false, error: '$e');
    }
  }

  /// Gives back the firewall policy that was there before and removes the rules.
  Future<void> release({required String reason}) async {
    if (!Platform.isWindows || !(_prefs.getBool(_engagedKey) ?? false)) return;
    try {
      await _restore();
      loggy.info('kill switch released: $reason');
      state = const WindowsKillSwitchState(engaged: false);
    } catch (e) {
      loggy.warning('could not release the kill switch', e);
      state = WindowsKillSwitchState(engaged: true, error: '$e');
    }
  }

  Future<void> _restore() async {
    final saved = _savedPolicies();
    for (var i = 0; i < _profiles.length; i++) {
      await _netsh(['advfirewall', 'set', _profiles[i], 'firewallpolicy', '${saved[i].inbound},${saved[i].outbound}']);
    }
    await _deleteRules();
    await _prefs.setBool(_engagedKey, false);
  }

  Future<void> _deleteRules() async {
    for (final name in _ruleNames) {
      // fails harmlessly when the rule is not there
      await Process.run('netsh', ['advfirewall', 'firewall', 'delete', 'rule', 'name=$name'], stdoutEncoding: latin1, stderrEncoding: latin1);
    }
  }

  /// Policies for the domain, private and public profiles, in that order.
  Future<List<_Policy>> _readPolicies() async {
    final result = await Process.run('netsh', ['advfirewall', 'show', 'allprofiles', 'firewallpolicy'], stdoutEncoding: latin1, stderrEncoding: latin1);
    // the labels are translated, the policy tokens are not
    final found = RegExp(r'(BlockInboundAlways|BlockInbound|AllowInbound),(AllowOutbound|BlockOutbound)', caseSensitive: false)
        .allMatches('${result.stdout}')
        .map((m) => _Policy(m.group(1)!, m.group(2)!))
        .toList();
    return found.length == _profiles.length ? found : List.filled(_profiles.length, _Policy.windowsDefault);
  }

  List<_Policy> _savedPolicies() {
    try {
      final list = (jsonDecode(_prefs.getString(_policyKey) ?? '[]') as List).map((e) => _Policy.fromJson(e as Map<String, dynamic>)).toList();
      if (list.length == _profiles.length) {
        // never "restore" to blocking: that is our own policy, saved by mistake
        return [for (final p in list) p.outbound.toLowerCase() == 'blockoutbound' ? _Policy(p.inbound, 'AllowOutbound') : p];
      }
    } catch (_) {}
    return List.filled(_profiles.length, _Policy.windowsDefault);
  }

  Future<void> _netsh(List<String> args) async {
    final result = await Process.run('netsh', args, stdoutEncoding: latin1, stderrEncoding: latin1);
    if (result.exitCode != 0) {
      throw ProcessException('netsh', args, '${result.stdout}${result.stderr}'.trim(), result.exitCode);
    }
  }
}

class _Policy {
  const _Policy(this.inbound, this.outbound);

  factory _Policy.fromJson(Map<String, dynamic> json) => _Policy(json['in'] as String, json['out'] as String);

  static const windowsDefault = _Policy('BlockInbound', 'AllowOutbound');

  final String inbound;
  final String outbound;

  Map<String, dynamic> toJson() => {'in': inbound, 'out': outbound};
}
