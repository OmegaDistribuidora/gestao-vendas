import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_vendas/models/daily_routing.dart';
import 'package:gestao_vendas/widgets/daily_routing_card.dart';

DailyRouting sample({
  int planned = 20,
  int purchased = 8,
  bool applicable = true,
  String profile = 'supervisor',
  bool details = false,
}) => DailyRouting.fromJson({
  'available': true,
  'applicable': applicable,
  'planned': planned,
  'purchased': purchased,
  'percent': planned == 0 ? null : purchased * 100 / planned,
  'filtered_count': details ? 1 : planned,
  'effective_profile_slug': profile,
  'snapshot_id': 'test',
  'source_updated_at': '2026-09-10T12:00:00Z',
  'items': details
      ? [
          {
            'customer_code': '100',
            'customer_name': 'Cliente exemplo',
            'seller_code': '200',
            'seller_name': 'Vendedor exemplo',
            'purchased': true,
          },
        ]
      : [],
});

void main() {
  test(
    'percentage is actual effectiveness, not progress toward a monthly goal',
    () {
      expect(sample().percent, 40);
      expect(sample().pending, 12);
      expect(sample(planned: 0, purchased: 0).percent, isNull);
      expect(sample(purchased: 0).percent, 0);
    },
  );

  testWidgets(
    'shows percentage, opens detail and filters with the selected scope',
    (tester) async {
      final calls = <String>[];
      Future<DailyRouting> loader({
        required String day,
        String? profile,
        String? code,
        bool details = false,
        String filter = 'all',
        int offset = 0,
        String? snapshotId,
      }) async {
        calls.add('$profile/$code/$details/$filter');
        return sample(details: details);
      }

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DailyRoutingCard(
              day: '2026-09-10',
              revision: 1,
              profile: 'supervisor',
              code: '20',
              loader: loader,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('40%'), findsOneWidget);
      await tester.tap(find.text('40%'));
      await tester.pumpAndSettle();
      expect(
        find.text('20 previstos • 8 com compra • 12 sem compra'),
        findsOneWidget,
      );
      expect(find.text('Vendedor: 200 - Vendedor exemplo'), findsOneWidget);
      await tester.tap(find.text('Sem compra'));
      await tester.pumpAndSettle();
      expect(calls.last, 'supervisor/20/true/pending');
    },
  );

  testWidgets('late response cannot overwrite a newly selected network scope', (
    tester,
  ) async {
    final old = Completer<DailyRouting>();
    Future<DailyRouting> loader({
      required String day,
      String? profile,
      String? code,
      bool details = false,
      String filter = 'all',
      int offset = 0,
      String? snapshotId,
    }) {
      return code == '20'
          ? old.future
          : Future.value(sample(applicable: false));
    }

    Widget page(String code) => MaterialApp(
      home: Scaffold(
        body: DailyRoutingCard(
          day: '2026-09-10',
          revision: 1,
          profile: 'supervisor',
          code: code,
          loader: loader,
        ),
      ),
    );
    await tester.pumpWidget(page('20'));
    await tester.pumpWidget(page('33'));
    await tester.pumpAndSettle();
    old.complete(sample());
    await tester.pumpAndSettle();
    expect(find.text('Efetividade de hoje'), findsNothing);
    expect(find.text('40%'), findsNothing);
  });

  testWidgets('no route is distinct from zero purchases', (tester) async {
    Future<DailyRouting> loader({
      required String day,
      String? profile,
      String? code,
      bool details = false,
      String filter = 'all',
      int offset = 0,
      String? snapshotId,
    }) async => sample(planned: 0, purchased: 0);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DailyRoutingCard(
            day: '2026-09-10',
            revision: 1,
            loader: loader,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Sem roteiro hoje'), findsOneWidget);
    expect(find.text('0%'), findsNothing);
  });
}
