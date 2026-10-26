import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_vendas/models/app_profile.dart';
import 'package:gestao_vendas/models/coach_market.dart';

void main() {
  test('Coach Mercado usa somente diretoria como acesso local seguro', () {
    for (final slug in <String>{
      AppProfile.adminSlug,
      AppProfile.sellerSlug,
      AppProfile.supervisorSlug,
      AppProfile.coordinatorSlug,
      AppProfile.othersSlug,
      AppProfile.managementSlug,
    }) {
      final profile = AppProfile(id: slug, name: slug, slug: slug);
      expect(profile.canAccessCoachMarket, isFalse, reason: slug);
    }
    const board = AppProfile(
      id: 'diretoria',
      name: 'Diretoria',
      slug: AppProfile.boardSlug,
    );
    expect(board.canAccessCoachMarket, isTrue);
  });

  test('envio contém resposta explícita para as onze seções', () {
    final submission = CoachMarketSubmission(
      submissionId: '17b09019-2739-4c25-b332-0bd83cf2314f',
      customer: const CoachMarketCustomer(
        code: 123,
        name: 'Cliente Teste',
        neverPurchased: true,
      ),
      customerDataSource: 'api',
      customerLookupSucceeded: false,
      location: CoachMarketLocation(
        latitude: -3.72,
        longitude: -38.54,
        accuracyMeters: 8,
        capturedAt: DateTime.utc(2026, 10, 23, 12),
      ),
      filledAt: DateTime.utc(2026, 10, 23, 12, 1),
      appVersion: '0.9.22+38',
      answers: {for (final section in coachMarketSections) section.code: true},
    );

    final answers = submission.toJson()['answers']! as List<dynamic>;
    expect(answers, hasLength(11));
    expect(answers.every((answer) => answer['hasSection'] == true), isTrue);
  });

  test('consulta converte vendedores, supervisores e histórico', () {
    final customer = CoachMarketCustomer.fromJson({
      'customerCode': 31505,
      'customerName': 'Cliente Teste',
      'customerNeverPurchased': false,
      'lastPurchaseDate': '2026-10-20',
      'sellerAssignments': [
        {
          'sellerCode': 3057,
          'sellerName': 'Vendedor Um',
          'supervisorCode': 33,
          'supervisorName': 'Supervisor Um',
        },
        {
          'sellerCode': 1595,
          'sellerName': 'Vendedor Dois',
          'supervisorCode': 33,
          'supervisorName': 'Supervisor Um',
        },
      ],
      'history': [
        {
          'submissionId': 'd1e66e3f-b501-4c37-b744-830a1b37b2aa',
          'filledAt': '2026-10-23T16:43:46-03:00',
          'filledByName': 'Diretoria',
          'supplierName': 'Bombril',
          'yesCount': 7,
          'totalCount': 11,
          'yesPercentage': 63.6,
          'answers': [
            {
              'sectionCode': 1,
              'sectionName': 'Detergente Limpol',
              'hasSection': true,
            },
          ],
        },
      ],
    });

    expect(customer.sellerAssignments, hasLength(2));
    expect(customer.sellerAssignments.last.sellerName, 'Vendedor Dois');
    expect(customer.history, hasLength(1));
    expect(customer.history.single.yesPercentage, 63.6);
    expect(customer.history.single.answers.single.hasSection, isTrue);
  });
}
