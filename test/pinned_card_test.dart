// PinnedCard widget tests — header rendering, hidden-services filter,
// loading state, rename via long-press bottom sheet, and service-row tap.

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
      // Stop code + walk-min are concatenated into one mono meta line.
      expect(find.text('STOP 53239 · 4 MIN WALK'), findsOneWidget);
    });

    testWidgets('renders all visible services (no 3-service cap)',
        (tester) async {
      final services = [
        for (var i = 100; i <= 104; i++) _svc('$i', 60 * (i - 99) + 60),
      ];
      await tester.pumpWidget(_wrap(PinnedCard(
        card: _card(services: services),
        isNew: false,
        onOpen: (_) {},
        onRename: (_) {},
      )));
      for (var i = 100; i <= 104; i++) {
        expect(find.text('$i'), findsOneWidget);
      }
      expect(find.textContaining('+'), findsNothing);
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
    testWidgets('long-press opens a rename bottom sheet with a TextField',
        (tester) async {
      await tester.pumpWidget(_wrap(PinnedCard(
        card: _card(services: [_svc('156', 240)]),
        isNew: false,
        onOpen: (_) {},
        onRename: (_) {},
      )));
      // No TextField initially.
      expect(find.byType(TextField), findsNothing);
      // Long-press the card.
      await tester.longPress(find.text('Opp Bishan Stn'));
      await tester.pumpAndSettle();
      // Sheet now has a TextField + Save button.
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('committing a new label calls onRename', (tester) async {
      String? renamedTo;
      await tester.pumpWidget(_wrap(PinnedCard(
        card: _card(services: [_svc('156', 240)]),
        isNew: false,
        onOpen: (_) {},
        onRename: (v) => renamedTo = v,
      )));
      await tester.longPress(find.text('Opp Bishan Stn'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Home stop');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
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
      await tester.tap(find.text('156'));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(openedBus, '156');
    });
  });
}
