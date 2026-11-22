import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/kill_switch/kill_switch.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class KillSwitchPage extends HookConsumerWidget {
  const KillSwitchPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final k = t.pages.settings.killSwitch;

    return Scaffold(
      appBar: AppBar(title: Text(k.title)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(k.description, style: Theme.of(context).textTheme.bodyLarge),
          ),
          if (Platform.isAndroid) const _AndroidSection(),
          if (Platform.isWindows) const _WindowsSection(),
        ],
      ),
    );
  }
}

class _Steps extends StatelessWidget {
  const _Steps(this.steps);

  final List<String> steps;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (i, step) in steps.indexed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 24, child: Text('${i + 1}.', style: style)),
                  Expanded(child: Text(step, style: style)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _AndroidSection extends HookConsumerWidget {
  const _AndroidSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final k = t.pages.settings.killSwitch;
    final status = ref.watch(androidKillSwitchStatusProvider);

    // the switches are changed in system settings: read them again on return
    useOnAppLifecycleStateChange((_, state) {
      if (state == AppLifecycleState.resumed) ref.invalidate(androidKillSwitchStatusProvider);
    });
    ref.listen(serviceRunningProvider, (_, __) => ref.invalidate(androidKillSwitchStatusProvider));

    String present(bool? value) => switch (value) {
      true => k.statusOn,
      false => k.statusOff,
      null => '—',
    };

    final s = status.valueOrNull;
    final String? hint = switch (s) {
      AndroidKillSwitchStatus(vpnRunning: false) => k.android.statusUnknown,
      AndroidKillSwitchStatus(alwaysOn: null) => k.android.statusOld,
      _ => null,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Steps([k.android.step1, k.android.step2, k.android.step3]),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: FilledButton.icon(
            autofocus: true,
            icon: const Icon(Icons.settings_rounded),
            label: Text(k.android.openSettings),
            onPressed: () => AndroidKillSwitch.openVpnSettings(),
          ),
        ),
        ListTile(
          leading: Icon(s?.active == true ? Icons.shield_rounded : Icons.shield_outlined),
          title: Text(k.android.alwaysOn),
          trailing: Text(present(s?.alwaysOn)),
        ),
        ListTile(
          leading: const Icon(Icons.block_rounded),
          title: Text(k.android.lockdown),
          trailing: Text(present(s?.lockdown)),
        ),
        if (hint != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(hint, style: Theme.of(context).textTheme.bodySmall),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Text(k.android.note, style: Theme.of(context).textTheme.bodySmall),
        ),
      ],
    );
  }
}

class _WindowsSection extends HookConsumerWidget {
  const _WindowsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final k = t.pages.settings.killSwitch;
    final enabled = ref.watch(KillSwitchPrefs.enabled);
    final ks = ref.watch(windowsKillSwitchProvider);
    final elevated = useFuture(useMemoized(WindowsKillSwitch.isElevated)).data;
    final busy = useState(false);

    Future<void> toggle(bool value) async {
      busy.value = true;
      try {
        await ref.read(KillSwitchPrefs.enabled.notifier).update(value);
        final notifier = ref.read(windowsKillSwitchProvider.notifier);
        if (!value) {
          await notifier.release(reason: 'turned off by the user');
        } else if (ref.read(serviceRunningProvider)) {
          await notifier.engage();
        }
      } finally {
        busy.value = false;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile.adaptive(
          secondary: const Icon(Icons.shield_rounded),
          title: Text(k.windows.enable),
          subtitle: Text(k.windows.enableSubtitle),
          value: enabled,
          onChanged: busy.value || (elevated == false && !enabled) ? null : toggle,
        ),
        if (elevated == false)
          ListTile(
            leading: Icon(Icons.admin_panel_settings_rounded, color: Theme.of(context).colorScheme.error),
            title: Text(k.windows.needsAdmin),
          ),
        if (ks.engaged)
          ListTile(
            leading: const Icon(Icons.block_rounded),
            title: Text(k.windows.engaged),
          ),
        if (ks.error != null)
          ListTile(
            leading: Icon(Icons.error_rounded, color: Theme.of(context).colorScheme.error),
            title: Text(k.windows.failed),
            subtitle: Text(ks.error!, maxLines: 4, overflow: TextOverflow.ellipsis),
          ),
        _Steps([k.windows.step1, k.windows.step2, k.windows.step3]),
      ],
    );
  }
}

/// Shown on the home screen while Windows blocks the internet and the VPN is
/// not connected, with a way out.
class KillSwitchBanner extends HookConsumerWidget {
  const KillSwitchBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!Platform.isWindows) return const SizedBox.shrink();
    final ks = ref.watch(windowsKillSwitchProvider);
    final connected = ref.watch(serviceRunningProvider);
    if (!ks.engaged || connected) return const SizedBox.shrink();
    final t = ref.watch(translationsProvider).requireValue;
    final k = t.pages.settings.killSwitch;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: scheme.errorContainer,
      child: ListTile(
        leading: Icon(Icons.block_rounded, color: scheme.onErrorContainer),
        title: Text(k.windows.engaged, style: TextStyle(color: scheme.onErrorContainer)),
        trailing: TextButton(
          onPressed: () => ref.read(windowsKillSwitchProvider.notifier).release(reason: 'unblocked from the home screen'),
          child: Text(k.windows.unblock),
        ),
      ),
    );
  }
}
