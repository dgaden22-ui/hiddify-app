import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/profile/notifier/profile_notifier.dart';
import 'package:hiddify/features/profile/receive/phone_transfer.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// DgadenVPN: receives a subscription from a phone, so nothing is typed on a TV.
///
/// While open, it serves [receivePath] on the home network with a one-time token
/// and shows the address as a QR code. DgadenVPN on a phone scans it and POSTs the
/// link (Share > Send to TV); a phone camera opens a small page with a link field
/// instead. The first link received is added like a pasted one and the dialog closes.
class ReceiveProfileDialog extends ConsumerStatefulWidget {
  const ReceiveProfileDialog({super.key});

  @override
  ConsumerState<ReceiveProfileDialog> createState() => _ReceiveProfileDialogState();
}

class _ReceiveProfileDialogState extends ConsumerState<ReceiveProfileDialog> with PresLogger {
  static const _maxBody = 64 * 1024;
  static const _tokenAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789';

  final _token = List.generate(24, (_) => _tokenAlphabet[Random.secure().nextInt(_tokenAlphabet.length)]).join();
  HttpServer? _server;
  String? _url;
  bool _noNetwork = false;
  bool _received = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _server?.close(force: true);
    super.dispose();
  }

  Future<void> _start() async {
    try {
      final ip = await lanIPv4Address();
      if (ip == null) {
        if (mounted) setState(() => _noNetwork = true);
        return;
      }
      final server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      if (!mounted) {
        await server.close(force: true);
        return;
      }
      _server = server;
      server.listen(_handle, onError: (Object e) => loggy.warning('receive server error', e));
      loggy.info('waiting for a subscription from a phone on port ${server.port}');
      setState(() => _url = 'http://$ip:${server.port}$receivePath?t=$_token');
    } catch (e) {
      loggy.warning('could not start receiving from a phone', e);
      if (mounted) setState(() => _noNetwork = true);
    }
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    try {
      if (request.uri.path != receivePath || request.uri.queryParameters['t'] != _token) {
        response.statusCode = HttpStatus.forbidden;
        return;
      }
      final t = ref.read(translationsProvider).requireValue;
      if (request.method == 'GET') {
        _writePage(response, _formPage(t));
        return;
      }
      if (request.method != 'POST') {
        response.statusCode = HttpStatus.methodNotAllowed;
        return;
      }

      final bytes = <int>[];
      await for (final chunk in request) {
        bytes.addAll(chunk);
        if (bytes.length > _maxBody) {
          response.statusCode = HttpStatus.requestEntityTooLarge;
          return;
        }
      }
      final body = utf8.decode(bytes, allowMalformed: true);
      final fromForm = request.headers.contentType?.mimeType == 'application/x-www-form-urlencoded';
      final link = (fromForm ? Uri.splitQueryString(body)['link'] ?? '' : body).trim();
      if (link.isEmpty || _received || !mounted) {
        response.statusCode = HttpStatus.badRequest;
        return;
      }

      _received = true;
      if (fromForm) {
        _writePage(response, _donePage(t));
      } else {
        response.write('OK');
      }
      loggy.info('subscription received from a phone');
      // read before closing: the dialog's ref is gone once it is popped
      final notifier = ref.read(addProfileNotifierProvider.notifier);
      Navigator.of(context).pop();
      notifier.addClipboard(link);
    } catch (e) {
      loggy.warning('failed to handle a request from a phone', e);
      try {
        response.statusCode = HttpStatus.internalServerError;
      } catch (_) {}
    } finally {
      try {
        await response.close();
      } catch (_) {}
    }
  }

  void _writePage(HttpResponse response, String html) {
    response.headers.contentType = ContentType.html;
    response.write(html);
  }

  String _page(String title, String body) {
    const esc = HtmlEscape();
    return '<!doctype html><html><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width,initial-scale=1">'
        '<title>${esc.convert(title)}</title><style>'
        'body{font-family:system-ui,sans-serif;background:#0B0F1A;color:#E6EAF2;margin:0;padding:24px}'
        'h1{font-size:20px;margin:0 0 16px}label{display:block;margin-bottom:8px;color:#9AA4B8}'
        'textarea{width:100%;box-sizing:border-box;min-height:120px;font-size:16px;padding:12px;'
        'border-radius:12px;border:1px solid #1C2944;background:#121A2B;color:#E6EAF2}'
        'button{margin-top:16px;width:100%;padding:14px;font-size:17px;border:0;border-radius:12px;'
        'background:#1E88FF;color:#fff}p{font-size:17px}'
        '</style></head><body>$body</body></html>';
  }

  String _formPage(Translations t) {
    const esc = HtmlEscape();
    final r = t.pages.profiles.receive;
    return _page(
      r.pageTitle,
      '<h1>${esc.convert(r.pageTitle)}</h1>'
      '<form method="post" action="$receivePath?t=$_token">'
      '<label for="link">${esc.convert(r.pageLink)}</label>'
      '<textarea id="link" name="link" required autofocus></textarea>'
      '<button type="submit">${esc.convert(r.pageSend)}</button></form>',
    );
  }

  String _donePage(Translations t) {
    const esc = HtmlEscape();
    final r = t.pages.profiles.receive;
    return _page(r.pageTitle, '<h1>${esc.convert(r.pageTitle)}</h1><p>${esc.convert(r.pageDone)}</p>');
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider).requireValue;
    final theme = Theme.of(context);
    final r = t.pages.profiles.receive;

    final Widget content;
    if (_noNetwork) {
      content = Text(r.noNetwork, style: theme.textTheme.bodyLarge);
    } else if (_url == null) {
      content = const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()));
    } else {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
            child: QrImageView(data: _url!, size: 240, padding: EdgeInsets.zero, backgroundColor: Colors.white),
          ),
          const Gap(16),
          Text(r.hint, style: theme.textTheme.bodyLarge, textAlign: TextAlign.center),
          const Gap(8),
          Text(r.browserHint, style: theme.textTheme.bodyMedium, textAlign: TextAlign.center),
          const Gap(8),
          Text(_url!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
        ],
      );
    }

    return AlertDialog(
      title: Text(r.title),
      content: SizedBox(width: 420, child: SingleChildScrollView(child: content)),
      actions: [TextButton(autofocus: true, onPressed: () => Navigator.of(context).pop(), child: Text(t.common.close))],
    );
  }
}
