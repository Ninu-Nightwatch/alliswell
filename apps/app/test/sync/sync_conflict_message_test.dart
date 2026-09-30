import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/screens/home_shell.dart';
import 'package:alliswell/src/sync/sync_engine.dart';

SyncConflict _rejected(String? code) => SyncConflict(
  entityType: 'task',
  entityId: 'T1',
  operation: 'delete',
  status: 'rejected',
  at: DateTime.utc(2026, 9, 30),
  errorCode: code,
);

/// EE-297 — a refused write says what happened, in the app's own words.
///
/// The snackbar used to print "rejected by the server (TICKET_WORK_BOUND)" —
/// a code nobody on the floor can read — while every other screen already had
/// a sentence for it under `error.<CODE>`.
void main() {
  setUp(() => AwI18n.instance.setActiveCached(const Locale('en')));

  test('a code the app has words for is said in those words', () {
    expect(
      syncConflictMessage(_rejected('TICKET_WORK_BOUND')),
      'error.TICKET_WORK_BOUND'.tr(),
    );
    expect(
      syncConflictMessage(_rejected('TICKET_TERMINAL')),
      'error.TICKET_TERMINAL'.tr(),
    );
  });

  test('an unknown code keeps the generic line, code included', () {
    expect(
      syncConflictMessage(_rejected('SOMETHING_NEW')),
      'sync.rejected'.tr(args: {'code': ' (SOMETHING_NEW)'}),
    );
    expect(
      syncConflictMessage(_rejected(null)),
      'sync.rejected'.tr(args: {'code': ''}),
    );
  });
}
