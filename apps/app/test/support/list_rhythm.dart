import 'package:alliswell/src/widgets/status_views.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// DESIGN §4 as a measurement (OPH-353): consecutive card rows of a list sit
/// exactly [kAwListRowPadding]'s total apart — 6 px, never 0 (the ticket
/// queue's cards once touched) and never a list's own number.
///
/// [cards] are finders for the CARDS, in the order they are drawn. A row whose
/// key sits on something inside the card is found with [cardAround].
void expectCardRhythm(WidgetTester tester, List<Finder> cards) {
  expect(
    cards.length,
    greaterThanOrEqualTo(2),
    reason: 'a rhythm needs two rows',
  );
  for (var i = 1; i < cards.length; i++) {
    final above = tester.getRect(cards[i - 1]);
    final below = tester.getRect(cards[i]);
    expect(
      below.top - above.bottom,
      moreOrLessEquals(kAwListRowPadding.vertical),
      reason: 'the gap between row ${i - 1} and row $i',
    );
  }
}

/// The card a keyed row lives in, when the key is on its tile.
Finder cardAround(Key key) =>
    find.ancestor(of: find.byKey(key), matching: find.byType(Card)).first;
