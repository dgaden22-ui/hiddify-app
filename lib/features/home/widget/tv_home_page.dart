import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/router/bottom_sheets/bottom_sheets_notifier.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/home/widget/connection_button.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/gen/assets.gen.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// DgadenVPN: the home screen on Android TV / Google TV.
///
/// Built for a remote: the connect button has focus as soon as the screen opens,
/// so OK connects at once; three large tiles below it are one press down; the
/// focused item gets a thick white ring and grows a little, so it is easy to
/// see from the sofa. The full app (profiles, settings) is one tile away, and
/// Back returns here.
class TvHomePage extends HookConsumerWidget {
  const TvHomePage({super.key});

  static const _connected = Color(0xFF22C55E);
  static const _busy = Color(0xFF1E88FF);
  static const _off = Color(0xFFEF4444);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final theme = Theme.of(context);
    final status = ref.watch(connectionNotifierProvider);
    final profile = ref.watch(activeProfileProvider).valueOrNull;
    final hasAnyProfile = ref.watch(hasAnyProfileProvider).valueOrNull ?? false;

    final (label, color) = switch (status) {
      AsyncData(value: Connected()) => (t.connection.connected, _connected),
      AsyncData(value: Connecting()) => (t.connection.connecting, _busy),
      AsyncData(value: Disconnecting()) => (t.connection.disconnecting, _busy),
      AsyncData(value: Disconnected()) => (t.connection.tapToConnect, _off),
      AsyncError() => (t.connection.failed, _off),
      _ => ('', theme.colorScheme.outline),
    };
    final onConnect = switch (status) {
      AsyncData(value: Disconnected()) || AsyncError() => () => connectOrAddProfile(ref),
      AsyncData(value: Connected()) => () => ref.read(connectionNotifierProvider.notifier).toggleConnection(),
      _ => null,
    };

    return Scaffold(
      body: SafeArea(
        child: FocusTraversalGroup(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Assets.images.logo.svg(height: 32),
                      const Gap(12),
                      Text(t.common.appTitle, style: theme.textTheme.headlineSmall),
                    ],
                  ),
                  const Gap(28),
                  _TvFocusable(
                    autofocus: true,
                    onPressed: onConnect,
                    builder: (focused) => Container(
                      width: 200,
                      height: 200,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color.withValues(alpha: 0.14),
                        border: Border.all(color: focused ? Colors.white : color, width: focused ? 7 : 3),
                        boxShadow: focused
                            ? [BoxShadow(color: color.withValues(alpha: 0.55), blurRadius: 36, spreadRadius: 4)]
                            : null,
                      ),
                      alignment: Alignment.center,
                      child: Assets.images.logo.svg(
                        width: 108,
                        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
                      ),
                    ),
                  ),
                  const Gap(20),
                  Text(label, style: theme.textTheme.headlineSmall?.copyWith(color: color)),
                  if (profile != null) ...[
                    const Gap(6),
                    Text(profile.name, style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.outline)),
                  ],
                  const Gap(36),
                  Wrap(
                    spacing: 20,
                    runSpacing: 20,
                    alignment: WrapAlignment.center,
                    children: [
                      _TvTile(
                        icon: Icons.qr_code_2_rounded,
                        title: t.pages.profiles.receive.title,
                        onPressed: () => ref.read(dialogNotifierProvider.notifier).showReceiveFromPhone(),
                      ),
                      if (hasAnyProfile)
                        _TvTile(
                          icon: Icons.list_alt_rounded,
                          title: t.pages.profiles.title,
                          onPressed: () => context.goNamed('profiles'),
                        )
                      else
                        _TvTile(
                          icon: Icons.add_rounded,
                          title: t.pages.profiles.add,
                          onPressed: () => ref.read(bottomSheetsNotifierProvider.notifier).showAddProfile(),
                        ),
                      _TvTile(
                        icon: Icons.settings_rounded,
                        title: t.pages.settings.title,
                        onPressed: () => context.goNamed('settings'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TvTile extends StatelessWidget {
  const _TvTile({required this.icon, required this.title, required this.onPressed});

  final IconData icon;
  final String title;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _TvFocusable(
      onPressed: onPressed,
      builder: (focused) => Container(
        width: 250,
        height: 88,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: focused ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: focused ? Colors.white : Colors.transparent, width: 4),
        ),
        child: Row(
          children: [
            Icon(icon, size: 32, color: focused ? Colors.white : theme.colorScheme.primary),
            const Gap(14),
            Expanded(
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(color: focused ? Colors.white : null),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A remote-friendly button: OK / Enter / Space activates it, focus is drawn by
/// [builder] and the button grows slightly while focused. It stays focusable
/// even while [onPressed] is null (e.g. while connecting), so focus never jumps.
class _TvFocusable extends HookWidget {
  const _TvFocusable({required this.onPressed, required this.builder, this.autofocus = false});

  final VoidCallback? onPressed;
  final Widget Function(bool focused) builder;
  final bool autofocus;

  static const _activate = <ShortcutActivator, Intent>{
    SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
  };

  @override
  Widget build(BuildContext context) {
    final focused = useState(false);
    return FocusableActionDetector(
      autofocus: autofocus,
      shortcuts: _activate,
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            onPressed?.call();
            return null;
          },
        ),
      },
      onFocusChange: (value) => focused.value = value,
      mouseCursor: onPressed == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onPressed,
        child: AnimatedScale(
          scale: focused.value ? 1.07 : 1,
          duration: const Duration(milliseconds: 140),
          child: builder(focused.value),
        ),
      ),
    );
  }
}
