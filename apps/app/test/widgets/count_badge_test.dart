import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/theme/theme.dart';
import 'package:alliswell/src/widgets/count_badge.dart';

/// EE-294 — the one count badge the app has (the notification centre's,
/// extracted so the approvals entry wears the same pill).
///
///   1. ZERO DRAWS NOTHING — a badge that is always there stops being a signal.
///   2. BEYOND THE CAP IT READS "99+".
///   3. THE THEME'S `error`/`onError` PAIR in both themes — the pair the
///      contrast gate measures, never a hand-picked red.
///   4. A SCREEN READER HEARS WHAT IT COUNTS, not a bare number.
Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Brightness b = Brightness.light,
}) => tester.pumpWidget(
  MaterialApp(
    theme: buildAwTheme(b),
    home: Scaffold(body: Center(child: child)),
  ),
);

void main() {
  testWidgets('zero draws nothing', (tester) async {
    await _pump(
      tester,
      const AwCountBadge(count: 0, semanticsLabel: 'none', badgeKey: Key('b')),
    );
    expect(find.byKey(const Key('b')), findsNothing);
  });

  testWidgets('the number, capped at 99+', (tester) async {
    await _pump(
      tester,
      const AwCountBadge(
        count: 7,
        semanticsLabel: '7 waiting',
        badgeKey: Key('b'),
      ),
    );
    expect(find.text('7'), findsOneWidget);
    await _pump(
      tester,
      const AwCountBadge(
        count: 250,
        semanticsLabel: '250 waiting',
        badgeKey: Key('b'),
      ),
    );
    expect(find.text('99+'), findsOneWidget);
    expect(awCountLabel(100), '99+');
    expect(awCountLabel(99), '99');
  });

  for (final brightness in Brightness.values) {
    testWidgets('the error/onError pair in $brightness', (tester) async {
      await _pump(
        tester,
        const AwCountBadge(count: 3, semanticsLabel: '3', badgeKey: Key('b')),
        b: brightness,
      );
      final scheme = buildAwTheme(brightness).colorScheme;
      final box = tester.widget<Container>(find.byKey(const Key('b')));
      expect((box.decoration! as BoxDecoration).color, scheme.error);
      expect(tester.widget<Text>(find.text('3')).style?.color, scheme.onError);
    });
  }

  testWidgets('a screen reader hears what it counts', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(
      tester,
      const AwCountBadge(
        count: 3,
        semanticsLabel: '3 waiting on your decision',
      ),
    );
    expect(
      find.bySemanticsLabel(RegExp('3 waiting on your decision')),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('on an icon, the badge sits outside the glyph', (tester) async {
    await _pump(
      tester,
      const AwBadgedIcon(
        icon: Icons.how_to_reg_outlined,
        count: 2,
        semanticsLabel: '2',
        badgeKey: Key('b'),
      ),
    );
    final icon = tester.getRect(find.byIcon(Icons.how_to_reg_outlined));
    final badge = tester.getRect(find.byKey(const Key('b')));
    expect(badge.right, greaterThan(icon.right));
    expect(badge.top, lessThan(icon.top));
  });
}
