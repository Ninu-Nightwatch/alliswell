// EE-294 / EE-295's approval surfaces, shot in both themes.
//
//   flutter test --update-goldens --dart-define=screenshots=true \
//       test/features/ee/approvals_screenshot_test.dart
//
// Inert without the dart-define, and the images are NOT committed — the house
// rule set at EE-026: shots are generated, looked at, and thrown away.
//
// What these are FOR: whether a row reads as "who asked, when, what for" at a
// glance; whether the count reads as a count and not as an alarm; whether the
// rail entry sits like a sibling of Requests; whether the correction reads as
// a form about somebody else's words.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/core/day_boundary.dart';
import 'package:alliswell/src/features/ee/approvals_providers.dart';
import 'package:alliswell/src/features/ee/data/approvals_api.dart';
import 'package:alliswell/src/features/ee/data/approvals_models.dart';
import 'package:alliswell/src/features/ee/data/changes_models.dart';
import 'package:alliswell/src/features/ee/data/new_ticket_api.dart';
import 'package:alliswell/src/features/ee/data/ticket_write_api.dart';
import 'package:alliswell/src/features/ee/ui/approval_detail_screen.dart';
import 'package:alliswell/src/features/ee/ui/approvals_entry.dart';
import 'package:alliswell/src/features/ee/ui/approvals_screen.dart';
import 'package:alliswell/src/features/quick_access/pinned.dart';
import 'package:alliswell/src/features/quick_access/providers.dart';
import 'package:alliswell/src/features/quick_access/ui/quick_access_panel.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/widgets/glass.dart';

import '../../design_screenshots_test.dart' show screenshotLocale;
import 'support/shot.dart';

const bool _enabled = bool.fromEnvironment('screenshots');

final _now = DateTime(2026, 9, 30, 14, 30);

class _Fixed extends EeApprovalsController {
  _Fixed(this._items);
  final List<EeApproval> _items;
  @override
  Future<List<EeApproval>> build() async => _items;
}

EeApproval _row(
  String id, {
  required String title,
  required int number,
  required String who,
  required String service,
  required String excerpt,
  String addressedTo = 'me',
  int daysAgo = 1,
  int hoursAsked = 2,
  EeApprovalProgress progress = const EeApprovalProgress(total: 1, pending: 1),
  String kind = 'member',
}) => EeApproval(
  id: id,
  targetType: 'ee_ticket',
  targetId: 'T-$id',
  status: 'pending',
  createdAt: _now.subtract(Duration(hours: hoursAsked)),
  approverUserId: addressedTo == 'me' ? 'U-ME' : null,
  approverRoleKey: addressedTo == 'me' ? null : 'admin',
  requestReason: service,
  target: EeApprovalTarget(
    kind: 'ee_ticket',
    title: title,
    status: 'new',
    number: number,
  ),
  addressedTo: addressedTo,
  canDecide: true,
  live: true,
  requestedByName: who,
  progress: progress,
  context: EeApprovalContext(
    openedAt: _now.subtract(Duration(days: daysAgo)),
    requesterName: who,
    requesterKind: kind,
    serviceName: service,
    unitName: 'Bilgi İşlem',
    excerpt: excerpt,
    priority: 'high',
  ),
);

final _queue = [
  _row(
    'A1',
    title: 'Yeni personel için dizüstü bilgisayar',
    number: 1042,
    who: 'Mehmet Kaya',
    service: 'Donanım talebi',
    excerpt:
        'Pazartesi başlayan iki satın alma uzmanı için 16 GB bellekli, '
        'SSD diskli iki dizüstü gerekiyor; teklif ekte.',
    progress: const EeApprovalProgress(total: 2, approved: 1, pending: 1),
  ),
  _row(
    'A2',
    title: 'ERP rapor ekranına erişim',
    number: 1057,
    who: 'Selin Aydın',
    service: 'Yetki talebi',
    excerpt: 'Aylık kapanış için finans raporlarını okuma yetkisi.',
    daysAgo: 3,
    hoursAsked: 26,
    kind: 'portal',
  ),
  _row(
    'R1',
    title: 'Hat 3 için yedek RAID kartı',
    number: 1061,
    who: 'Burak Demir',
    service: 'Satın alma',
    excerpt: 'Sunucudaki kart uyarı veriyor; yedeğini almak istiyoruz.',
    addressedTo: 'role',
  ),
];

EeApprovalDetail _detail() => EeApprovalDetail(
  approval: _queue.first,
  signatures: [
    EeChangeApproval(
      id: 'A0',
      status: 'approved',
      createdAt: _now.subtract(const Duration(hours: 5)),
      canDecide: false,
      approverUserId: 'U-SEC',
      approverName: 'Güvenlik Ekibi',
      decidedByName: 'Nil Güven',
      decisionReason: 'Standart kurulum, sorun yok',
    ),
    EeChangeApproval(
      id: 'A1',
      status: 'pending',
      createdAt: _now.subtract(const Duration(hours: 2)),
      canDecide: true,
      approverUserId: 'U-ME',
      approverName: 'Mert Yönetici',
    ),
  ],
  access: const EeApprovalAccess(full: true, edit: true),
  request: EeApprovalRequestView(
    id: 'T-A1',
    number: 1042,
    ref: '#1042',
    subject: 'Yeni personel için dizüstü bilgisayar',
    body:
        'Pazartesi başlayan iki satın alma uzmanı için 16 GB bellekli, SSD '
        'diskli iki dizüstü gerekiyor. Tedarikçinin teklifi ekte.',
    status: 'new',
    priority: 'high',
    createdAt: _now.subtract(const Duration(days: 1)),
    requester: const EeApprovalRequester(
      userId: 'U-REP',
      name: 'Mehmet Kaya',
      email: 'mehmet.kaya@example.com',
      kind: 'member',
    ),
    serviceId: 'S1',
    serviceName: 'Donanım talebi',
    unitName: 'Bilgi İşlem',
    fields: const [
      EeFormField(key: 'adet', label: 'Adet', type: 'number', required: true),
      EeFormField(key: 'tutar', label: 'Tahmini tutar (TL)', type: 'number'),
      EeFormField(key: 'neden', label: 'Gerekçe', type: 'text'),
    ],
    answers: const [
      EeTicketAnswer(label: 'Adet', type: 'number', value: '2'),
      EeTicketAnswer(
        label: 'Tahmini tutar (TL)',
        type: 'number',
        value: '84000',
      ),
      EeTicketAnswer(label: 'Gerekçe', type: 'text', value: 'Yeni personel'),
    ],
    answerValues: const {
      'adet': '2',
      'tutar': '84000',
      'neden': 'Yeni personel',
    },
    comments: [
      EeApprovalComment(
        id: 'C1',
        body: 'Stokta bir tane var; ikincisini sipariş ederiz.',
        internal: true,
        authorName: 'Deniz Masa',
        createdAt: _now.subtract(const Duration(hours: 20)),
      ),
      EeApprovalComment(
        id: 'C2',
        body: 'Teklifi ekledim, iki haftalık teslim.',
        internal: false,
        authorName: 'Mehmet Kaya',
        createdAt: _now.subtract(const Duration(hours: 18)),
      ),
    ],
    files: const [
      EeApprovalFile(
        id: 'F1',
        name: 'teklif-2026-09.pdf',
        mime: 'application/pdf',
        sizeBytes: 245760,
        internal: false,
      ),
      EeApprovalFile(
        id: 'F2',
        name: 'stok-durumu.xlsx',
        mime: 'application/vnd.ms-excel',
        sizeBytes: 18432,
        internal: true,
      ),
    ],
  ),
);

void main() {
  if (!_enabled) return;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AwI18n.instance.setActiveCached(screenshotLocale('tr'));
  });

  // The shared harness (support/shot.dart) with this file's clock. Sizes are
  // logical here — phone width — and doubled into eeShoot's physical pixels.
  Future<void> shoot(
    WidgetTester tester,
    Brightness brightness,
    String name,
    List<Override> overrides,
    Widget screen, {
    Size size = const Size(430, 932),
    Future<void> Function(WidgetTester tester)? afterPump,
  }) => eeShoot(
    tester,
    brightness: brightness,
    name: name,
    screen: screen,
    overrides: [nowProvider.overrideWithValue(() => _now), ...overrides],
    size: size * 2,
    afterPump: afterPump,
  );

  const summary = EeApprovalsSummary(
    authority: true,
    answersForRole: true,
    personal: 2,
    role: 1,
  );

  for (final brightness in Brightness.values) {
    testWidgets('the queue — ${brightness.name}', (tester) async {
      await shoot(tester, brightness, 'ee-approvals-queue', [
        eeApprovalsProvider.overrideWith(() => _Fixed(_queue)),
        eeApprovalsSummaryProvider.overrideWith((ref) async => summary),
      ], const EeApprovalsScreen());
    });

    testWidgets('one approval, whole — ${brightness.name}', (tester) async {
      await shoot(
        tester,
        brightness,
        'ee-approval-detail',
        [
          eeApprovalDetailProvider.overrideWith((ref, id) async => _detail()),
          eeApprovalsProvider.overrideWith(() => _Fixed(_queue)),
        ],
        const EeApprovalDetailScreen(approvalId: 'A1'),
        size: const Size(430, 2100),
      );
    });

    testWidgets('the correction — ${brightness.name}', (tester) async {
      await shoot(
        tester,
        brightness,
        'ee-approval-correction',
        [
          eeApprovalDetailProvider.overrideWith((ref, id) async => _detail()),
          eeApprovalsProvider.overrideWith(() => _Fixed(_queue)),
          eeApprovalsApiProvider.overrideWithValue(EeApprovalsApi(Dio())),
        ],
        const EeApprovalDetailScreen(approvalId: 'A1'),
        size: const Size(430, 1100),
        afterPump: (t) => t.tap(find.byKey(const Key('ee-approval-correct'))),
      );
    });

    testWidgets('the rail entry, extended and narrow — ${brightness.name}', (
      tester,
    ) async {
      await shoot(
        tester,
        brightness,
        'ee-approvals-rail',
        [
          eeApprovalsDoorProvider.overrideWith((ref) => true),
          eeApprovalsBadgeProvider.overrideWith((ref) => 3),
        ],
        const Scaffold(
          backgroundColor: Colors.transparent,
          body: Padding(
            padding: EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GlassSurface(
                  floating: true,
                  child: SizedBox(
                    width: 256,
                    child: EeApprovalsRailEntry(extended: true),
                  ),
                ),
                SizedBox(width: 24),
                GlassSurface(
                  floating: true,
                  child: SizedBox(
                    width: 84,
                    child: EeApprovalsRailEntry(extended: false),
                  ),
                ),
              ],
            ),
          ),
        ),
        size: const Size(420, 140),
      );
    });

    testWidgets('the phone panel with the pinned entry — ${brightness.name}', (
      tester,
    ) async {
      await shoot(
        tester,
        brightness,
        'ee-approvals-quick-panel',
        [
          quickAccessRowsProvider.overrideWith((ref) => Stream.value(const [])),
          quickAccessPinsProvider.overrideWith(
            (ref) => [
              QuickAccessPin(
                id: 'approvals',
                icon: kAwApprovalsIcon,
                title: 'ee.approvals.title'.tr(),
                subtitle: 'ee.approvals.navHint'.tr(),
                route: kAwApprovalsPath,
                badge: 3,
                badgeSemantics: '3',
              ),
            ],
          ),
        ],
        const Scaffold(
          backgroundColor: Colors.transparent,
          body: Align(
            alignment: Alignment.bottomCenter,
            child: Material(child: QuickAccessPanel()),
          ),
        ),
        size: const Size(430, 400),
      );
    });
  }
}
