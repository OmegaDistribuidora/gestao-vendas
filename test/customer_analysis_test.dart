import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_vendas/models/customer_analysis.dart';

void main() {
  test('converte busca com distância e bloqueio', () {
    final customer = CustomerAnalysisSearchResult.fromJson({
      'customerCode': 31505,
      'customerName': 'Cliente Teste',
      'tradeName': 'Mercado Teste',
      'city': 'Fortaleza',
      'blocked': true,
      'distanceKm': 1.25,
    });

    expect(customer.code, 31505);
    expect(customer.tradeName, 'Mercado Teste');
    expect(customer.blocked, isTrue);
    expect(customer.distanceKm, 1.25);
  });

  test('converte detalhe, rankings e pedidos', () {
    final detail = CustomerAnalysisDetail.fromJson({
      'customer': {
        'customerCode': 31505,
        'customerName': 'Cliente Teste',
        'blocked': false,
        'creditLimit': 5000,
        'sellerAssignments': [
          {
            'sellerCode': 3057,
            'sellerName': 'Vendedor',
            'supervisorCode': 33,
            'supervisorName': 'Supervisor',
          },
        ],
      },
      'periods': {
        'quarterMonths': ['2026-06-01', '2026-04-01', '2026-03-01'],
        'semesterMonths': [
          '2026-06-01',
          '2026-04-01',
          '2026-03-01',
          '2025-12-01',
        ],
      },
      'quarterlyAverage': 1000,
      'semesterAverage': 900,
      'metricAverages': {
        'financial': {'quarterly': 1000, 'semester': 900},
        'volume': {'quarterly': 80, 'semester': 75},
        'skus': {'quarterly': 22, 'semester': 20},
      },
      'purchaseInsights': {
        'daysWithoutPurchase': 18,
        'averageFrequencyDays': 12,
        'averageTicketLastFiveOrders': 450,
        'currentMonth': '2026-11-01',
        'currentMonthAmount': 35000,
        'previousMonth': '2026-10-01',
        'previousMonthAmount': 50000,
        'monthVariationPercent': -30,
        'averageTickets': {'financial': 450, 'volume': 4.5, 'skus': 8},
        'currentMonthMetrics': {'financial': 35000, 'volume': 320, 'skus': 58},
        'previousMonthMetrics': {'financial': 50000, 'volume': 400, 'skus': 70},
        'monthVariations': {'financial': -30, 'volume': -20, 'skus': -17.14},
        'largestOrders': {
          'volume': {
            'orderNumber': 999,
            'date': '2026-10-10',
            'amount': 1000,
            'volume': 50,
            'quantity': 100,
            'productCount': 12,
          },
        },
        'monthlyEvolution': [
          {'month': '2026-10-01', 'amount': 50000, 'volume': 400, 'skus': 70},
          {'month': '2026-11-01', 'amount': 35000, 'volume': 320, 'skus': 58},
        ],
      },
      'lastPurchase': {
        'orderNumber': 123,
        'date': '2026-11-06',
        'amount': 500,
        'volume': 3.2,
        'quantity': 20,
        'productCount': 4,
      },
      'recentOrders': [],
      'topProducts': [
        {
          'productCode': 10,
          'productName': 'Produto',
          'quantity': 20,
          'boxes': 2,
          'volume': 3.2,
          'amount': 500,
        },
      ],
      'topSuppliers': [
        {
          'supplierCode': 117,
          'supplierName': 'Fornecedor',
          'amount': 500,
          'volume': 3.2,
          'skuCount': 4,
        },
      ],
      'lostProducts': [
        {
          'productCode': 20,
          'productName': 'Produto perdido',
          'lastPurchaseDate': '2026-08-10',
          'previousOrderCount': 3,
          'quantity': 10,
          'boxes': 1,
          'volume': 1,
          'amount': 200,
        },
      ],
      'delinquency': {
        'hasOpenTitles': true,
        'titleCount': 1,
        'totalAmount': 300,
        'titles': [
          {
            'dueDate': '2026-09-10',
            'amount': 300,
            'originalAmount': 300,
            'daysOverdue': 61,
          },
        ],
      },
      'returns': {
        'hasReturns': true,
        'returnCount': 1,
        'totalAmount': 120,
        'totalVolume': 1,
        'totalSkus': 1,
        'latest': [
          {
            'date': '2026-10-20',
            'amount': 120,
            'volume': 1,
            'quantity': 2,
            'itemCount': 1,
          },
        ],
      },
    });

    expect(detail.customer.sellerAssignments, hasLength(1));
    expect(detail.lastPurchase?.orderNumber, 123);
    expect(detail.topProducts.single.boxes, 2);
    expect(detail.topSuppliers.single.supplierCode, 117);
    expect(detail.periods.quarterMonths, [
      DateTime(2026, 6),
      DateTime(2026, 4),
      DateTime(2026, 3),
    ]);
    expect(detail.periods.semesterMonths, hasLength(4));
    expect(detail.purchaseInsights.daysWithoutPurchase, 18);
    expect(detail.purchaseInsights.monthVariationPercent, -30);
    expect(detail.metricAverages.volume.quarterly, 80);
    expect(detail.purchaseInsights.currentMonthMetrics.skus, 58);
    expect(detail.purchaseInsights.averageTickets.volume, 4.5);
    expect(detail.purchaseInsights.largestOrders.volume?.orderNumber, 999);
    expect(detail.purchaseInsights.monthlyEvolution, hasLength(2));
    expect(detail.purchaseInsights.monthlyEvolution.last.volume, 320);
    expect(detail.lostProducts.single.previousOrderCount, 3);
    expect(detail.delinquency.titles.single.daysOverdue, 61);
    expect(detail.returnsSummary.latest.single.amount, 120);
    expect(detail.returnsSummary.totalVolume, 1);
  });

  test('converte itens carregados sob demanda', () {
    final order = CustomerOrderDetail.fromJson({
      'orderNumber': 123,
      'date': '2026-11-06',
      'amount': 500,
      'volume': 3.2,
      'quantity': 20,
      'truncated': false,
      'items': [
        {
          'productCode': 10,
          'productName': 'Produto',
          'supplierCode': 117,
          'supplierName': 'Fornecedor',
          'quantity': 20,
          'boxes': 2,
          'volume': 3.2,
          'amount': 500,
          'unitPrice': 25,
        },
      ],
    });

    expect(order.items, hasLength(1));
    expect(order.items.single.unitPrice, 25);
  });
}
