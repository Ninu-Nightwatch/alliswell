import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../theme/tokens.dart';
import '../../widgets/count_badge.dart';
import '../ee/ui/approvals_entry.dart';

/// An entry the APP pins at the top of Quick Access (DESIGN §23 Q10).
///
/// Not a shortcut: it is not in `quick_links`, it does not sync, it counts
/// against no cap, and it has no menu — it cannot be renamed, moved or
/// removed, because the person did not put it there and has nowhere else to
/// find it on a phone. It exists while its owner says so (today: the
/// Approvals entry, for somebody with approval authority), and it may carry
/// a count.
class QuickAccessPin {
  const QuickAccessPin({
    required this.id,
    required this.icon,
    required this.title,
    required this.route,
    this.subtitle,
    this.badge = 0,
    this.badgeSemantics,
  });

  final String id;
  final IconData icon;
  final String title;
  final String? subtitle;

  /// Pushed above the shell, like a detail screen.
  final String route;
  final int badge;
  final String? badgeSemantics;
}

/// Every pin, in the order the panel draws them. Empty on a plain build and
/// for anybody the pins are not for — which is what keeps the bubble's
/// "nothing to shortcut to, no button" rule (Q5) true for them.
final quickAccessPinsProvider = Provider.autoDispose<List<QuickAccessPin>>(
  (ref) => [?ref.watch(eeApprovalsPinProvider)],
);

/// The sum the floating button and the ⚡ fallback wear.
final quickAccessPinsBadgeProvider = Provider.autoDispose<int>(
  (ref) => ref
      .watch(quickAccessPinsProvider)
      .fold<int>(0, (sum, pin) => sum + pin.badge),
);

/// The pins, as the phone panel's first rows: the same row shape as a
/// shortcut (identity, name, hint) with a count where a shortcut has its
/// menu — and no drag handle, because a pin is not in the order.
class QuickAccessPinnedRows extends ConsumerWidget {
  const QuickAccessPinnedRows({super.key, this.onNavigate});

  /// Called before navigating, so the sheet can close itself first.
  final VoidCallback? onNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pins = ref.watch(quickAccessPinsProvider);
    if (pins.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final pin in pins)
          ListTile(
            key: Key('quick-pin-${pin.id}'),
            contentPadding: const EdgeInsets.symmetric(horizontal: AwSpace.x3),
            minLeadingWidth: 24,
            leading: Icon(
              pin.icon,
              size: 20,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            title: Text(
              pin.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
            subtitle: pin.subtitle == null
                ? null
                : Text(
                    pin.subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
            trailing: AwCountBadge(
              badgeKey: Key('quick-pin-${pin.id}-badge'),
              count: pin.badge,
              semanticsLabel: pin.badgeSemantics ?? '${pin.badge}',
            ),
            onTap: () {
              // The router is read BEFORE the sheet starts closing: after
              // that, this context is on its way out of the tree.
              final router = GoRouter.of(context);
              onNavigate?.call();
              router.push(pin.route);
            },
          ),
        const Divider(height: AwSpace.x3),
      ],
    );
  }
}
