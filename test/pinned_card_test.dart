// PinnedCard widget tests — header rendering, ARRIVING badge gating,
// 3-service cap + "+N more" overflow, hidden-services filter, edit
// mode toggle on label tap.
//
// Constructs CardModel directly so the test doesn't depend on
// DataStore / AppModel state.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lyne/data/models.dart';
import 'package:lyne/widgets/pinned_card.dart';

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(body: child),
    );

Service _svc(String no, int eta, {Load load = Load.sea, bool wab = true}) =>
    Service(
      no: no,
      dest: 'Dest $no',
      etaSec: eta,
      followingSec: eta + 600,
      load: load,
      wab: wab,
      deck: Deck.sd,
    );

CardModel _card({
  String label = 'Opp Bishan Stn',
  String stopName = 'Opp Bishan Stn',
  String stopCode = '53239',
  int walkMin = 4,
  required List<Service> services,
}) =>
    CardModel(
      id: stopCode,
      label: label,
      stopName: stopName,
      stopCode: stopCode,
      walkMin: walkMin,
      services: services,
    );

void main() {
  group('PinnedCard rendering', () {
    testWidgets('shows label, stop code, walk-min', (tester) async {
      await tester.pumpWidget(_wrap(PinnedCard(
        card: _card(services: [_svc('156', 300)]),
        isNew: false,
        onOpen: (_) {},
        onRename: (_) {},
      )));
      expect(find.text('Opp Bishan Stn'), findsOneWidget);
      expect(find.text('STOP 53239'), findsOneWidget);
      expect(find.text('4 MIN WALK'), findsOneWidget);
    });

    testWidgets('caps at 3 services and shows "+N more" overflow chip',
        (tester) async {
      // Use 3-digit service numbers so they don't collide with EtaPill
      // minute counts (e.g. fmtEta(240) renders "4", which would match
      // single-digit service nos).
      final services = [
        for (var i = 100; i <= 104; i++) _svc('$i', 60 * (i - 99) + 60),
      ];
      await tester.pumpWidget(_wrap(PinnedCard(
        card: _card(services: services),
        isNew: false,
        onOpen: (_) {},
        onRename: (_) {},
      )));
      // Three service rows visible.
      expect(find.text('100'), findsOneWidget);
      expect(find.text('101'), findsOneWidget);
      expect(find.text('102'), findsOneWidget);
      // The fourth + fifth are absorbed by the overflow chip.
      expect(find.text('103'), findsNothing);
      expect(find.text('104'), findsNothing);
      expect(find.text('+2 more'), findsOneWidget);
    });

    testWidgets('shows ARRIVING badge when any service is ≤ 60s out',
        (tester) async {
      await tester.pumpWidget(_wrap(PinnedCard(
        card: _card(services: [_svc('156', 30), _svc('88', 400)]),
        isNew: false,
        onOpen: (_) {},
        onRename: (_) {},
      )));
      expect(find.text('ARRIVING'), findsOneWidget);
    });

    testWidgets('no ARRIVING badge when all services > 60s out',
        (tester) async {
      await tester.pumpWidget(_wrap(PinnedCard(
        card: _card(services: [_svc('156', 240), _svc('88', 540)]),
        isNew: false,
        onOpen: (_) {},
        onRename: (_) {},
      )));
      expect(find.text('ARRIVING'), findsNothing);
    });

    testWidgets('hiddenServices filter excludes those rows', (tester) async {
      await tester.pumpWidget(_wrap(PinnedCard(
        card: _card(services: [_svc('156', 60), _svc('88', 180)]),
        isNew: false,
        hiddenServices: const {'88'},
        onOpen: (_) {},
        onRename: (_) {},
      )));
      expect(find.text('156'), findsOneWidget);
      expect(find.text('88'), findsNothing);
    });

    testWidgets('empty visible services renders "Loading arrivals…" body',
        (tester) async {
      await tester.pumpWidget(_wrap(PinnedCard(
        card: _card(services: const []),
        isNew: false,
        onOpen: (_) {},
        onRename: (_) {},
      )));
      expect(find.text('Loading arrivals…'), findsOneWidget);
    });
  });

  group('PinnedCard interactions', () {
    testWidgets('tapping label switches to an editing TextField',
        (tester) async {
      await tester.pumpWidget(_wrap(PinnedCard(
        card: _card(services: [_svc('156', 240)]),
        isNew: false,
        onOpen: (_) {},
        onRename: (_) {},
      )));
      // No TextField initially.
      expect(find.byType(TextField), findsNothing);
      // Tap the label.
      await tester.tap(find.text('Opp Bishan Stn'));
      await tester.pump();
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('committing a new label calls onRename', (tester) async {
      String? renamedTo;
      await tester.pumpWidget(_wrap(PinnedCard(
        card: _card(services: [_svc('156', 240)]),
        isNew: false,
        onOpen: (_) {},
        onRename: (v) => renamedTo = v,
      )));
      await tester.tap(find.text('Opp Bishan Stn'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'Home stop');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(renamedTo, 'Home stop');
    });

    testWidgets('tapping a service row calls onOpen with that busNo',
        (tester) async {
      String? openedBus;
      await tester.pumpWidget(_wrap(PinnedCard(
        card: _card(services: [_svc('156', 240), _svc('88', 540)]),
        isNew: false,
        onOpen: (no) => openedBus = no,
        onRename: (_) {},
      )));
      // Find the "156" pill in the service row and tap it.
      // (The card label / stop code don't contain "156".)
      await tester.tap(find.text('156'));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(openedBus, '156');
    });
  });
}
