import 'dart:io';

/// DgadenVPN: sending a subscription from a phone to a TV over the home network.
///
/// The TV shows a QR code with `http://<its LAN address>:<port>/dgaden-receive?t=<token>`
/// and listens on that port while the dialog is open (see ReceiveProfileDialog).
/// The phone scans it and POSTs the subscription link as plain text.
const receivePath = '/dgaden-receive';

final _receiveCode = RegExp(r'^http://[0-9.]+:\d+/dgaden-receive\?t=[A-Za-z0-9]{16,}$');

/// Whether [text] is the QR code a TV shows to receive a subscription.
bool isTvReceiveCode(String text) => _receiveCode.hasMatch(text.trim());

/// Sends [link] to the TV behind [code]. True when the TV accepted it.
Future<bool> sendSubscriptionToTv(String code, String link) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8)
    // straight to the TV on the local network, never through a proxy
    ..findProxy = (_) => 'DIRECT';
  try {
    final request = await client.postUrl(Uri.parse(code.trim()));
    request.headers.contentType = ContentType.text;
    request.write(link);
    final response = await request.close().timeout(const Duration(seconds: 10));
    await response.drain<void>();
    return response.statusCode == HttpStatus.ok;
  } catch (_) {
    return false;
  } finally {
    client.close(force: true);
  }
}

/// The address other devices on the home network can reach this one at, or null.
///
/// Private IPv4 addresses only, preferring 192.168.x.x, then 10.x.x.x, then
/// 172.16-31.x.x. VPN interfaces are skipped: the tunnel's own address (Hiddify
/// uses 172.19.0.1) is private too but unreachable from other devices.
Future<String?> lanIPv4Address() async {
  final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
  String? best;
  var bestRank = 99;
  for (final interface in interfaces) {
    final name = interface.name.toLowerCase();
    if (name.contains('tun') || name.contains('vpn') || name.contains('hiddify') || name.contains('wg') ||
        name.startsWith('ppp')) {
      continue;
    }
    for (final address in interface.addresses) {
      final ip = address.address;
      if (address.isLoopback || ip.startsWith('172.19.0.')) continue;
      final rank = _privateRank(ip);
      if (rank < bestRank) {
        best = ip;
        bestRank = rank;
      }
    }
  }
  return best;
}

int _privateRank(String ip) {
  if (ip.startsWith('192.168.')) return 0;
  if (ip.startsWith('10.')) return 1;
  final parts = ip.split('.');
  if (parts.length == 4 && parts[0] == '172') {
    final second = int.tryParse(parts[1]) ?? 0;
    if (second >= 16 && second <= 31) return 2;
  }
  return 99;
}
