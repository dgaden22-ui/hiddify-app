import 'package:flutter/material.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/settings/overview/sections/routing_options_page.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// DgadenVPN: app-based routing as its own bottom-navigation tab on Android,
/// so choosing which apps use the VPN is one tap away instead of inside Settings.
class AppRoutingTabPage extends ConsumerWidget {
  const AppRoutingTabPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    return Scaffold(
      appBar: AppBar(title: Text(t.pages.settings.routing.appBasedRouting.title)),
      body: ListView(children: const [AppBasedRoutingSection(appListRoute: 'tabAppList')]),
    );
  }
}
