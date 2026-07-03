// RouteTimeline.onOpenStop — the full-route sheet's "any stop row opens
// that stop" behaviour (iOS RouteTimeline parity). See soft_bus_screen.dart's
// _openRouteCard, which wires this on the embedded, non-selectable sheet
// instance.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lyne/theme.dart';
import 'package:lyne/widgets/v2/route_timeline.dart';

Widget _host(Widget child) => MaterialApp(
  theme: LyneTheme.light.materialTheme(),
  darkTheme: LyneTheme.dark.materialTheme(),
  home: Scaffold(body: child),
);

void main() {
  testWidgets('onOpenStop set: every row is tappable regardless of state', (
    tester,
  ) async {
    final tapped = <String>[];
    const stops = [
      SoftRouteStop(
        id: 'A',
        name: 'Origin Stop',
        state: SoftRouteStopState.past,
      ),
      SoftRouteStop(
        id: 'B',
        name: 'Here Now Stop',
        state: SoftRouteStopState.here,
      ),
      SoftRouteStop(
        id: 'C',
        name: 'Upcoming Stop',
        state: SoftRouteStopState.next,
      ),
    ];

    // Not pumpAndSettle: the "here" state's bus dot runs a repeating pulse
    // animation (by design — it never settles), so a single pump suffices
    // once the first frame has laid out.
    await tester.pumpWidget(
      _host(
        RouteTimeline(
          svc: '10',
          stops: stops,
          alightId: null,
          onAlight: (_) {},
          selectable: false,
          embedded: true,
          onOpenStop: tapped.add,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Origin Stop'));
    await tester.tap(find.text('Here Now Stop'));
    await tester.tap(find.text('Upcoming Stop'));
    await tester.pump();

    expect(tapped, ['A', 'B', 'C']);
  });

  testWidgets(
    'onOpenStop absent: past/here rows stay non-tappable, alight still '
    'works for upcoming rows',
    (tester) async {
      String? alighted;
      const stops = [
        SoftRouteStop(
          id: 'A',
          name: 'Origin Stop',
          state: SoftRouteStopState.past,
        ),
        SoftRouteStop(
          id: 'C',
          name: 'Upcoming Stop',
          state: SoftRouteStopState.next,
        ),
      ];

      await tester.pumpWidget(
        _host(
          RouteTimeline(
            svc: '10',
            stops: stops,
            alightId: null,
            onAlight: (id) => alighted = id,
          ),
        ),
      );
      await tester.pump();

      // Tapping the past stop must not throw and must not set an alight.
      await tester.tap(find.text('Origin Stop'));
      await tester.pump();
      expect(alighted, isNull);

      // Tapping the upcoming stop still arms the existing alight-selection
      // behaviour when onOpenStop isn't provided.
      await tester.tap(find.text('Upcoming Stop'));
      await tester.pump();
      expect(alighted, 'C');
    },
  );
}
