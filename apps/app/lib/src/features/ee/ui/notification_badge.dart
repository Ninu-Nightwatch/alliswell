import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../i18n/i18n.dart';
import '../../../widgets/count_badge.dart';
import '../notifications_providers.dart';

/// The unread badge (EE-077).
///
/// LIVE FROM THE REPLICA'S OWN STREAM, not from a fetch: the count is a drift
/// `watch` over the notification table, so it moves the instant a pull writes a
/// row and it is correct with no signal. Nothing polls, and nothing has to be
/// told to refresh it.
///
/// How it LOOKS is `AwCountBadge`'s (EE-294 moved the pill there so the
/// approvals badge is the same widget): the theme's `error`/`onError` pair,
/// nothing at zero, "99+" beyond [max].
class AwNotificationBadge extends ConsumerWidget {
  const AwNotificationBadge({super.key, this.max = 99});

  /// Beyond this it reads "99+". A four-digit badge is not information, it is
  /// a layout problem.
  final int max;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(unreadNotificationCountProvider).value ?? 0;
    return AwCountBadge(
      badgeKey: const Key('notif-badge'),
      count: count,
      max: max,
      // The number alone tells a screen reader nothing about what it counts.
      semanticsLabel: 'ee.notif.unreadBadge'.tr(args: {'count': '$count'}),
    );
  }
}
