import 'package:flutter_test/flutter_test.dart';

import 'package:kasbeman_mobile/src/inventory/customer_statement_exporter.dart';
import 'package:kasbeman_mobile/src/inventory/inventory_repository.dart';

void main() {
  test('statement calculates opening, period totals and closing balance', () {
    const customer = CustomerRecord(
      id: 'customer-1',
      businessId: 'business-1',
      name: 'مشتری آزمایشی',
      phone: null,
      email: null,
      companyName: null,
      address: null,
      notes: null,
      status: 'active',
      purchaseCount: 2,
      totalPurchases: 1500,
      totalReceived: 300,
      balanceDue: 1200,
    );
    final sales = [
      SaleRecord(
        id: 'sale-before',
        saleNumber: '100',
        customerName: customer.name,
        status: 'confirmed',
        grandTotal: 1000,
        createdAt: DateTime(2026, 1, 2),
        confirmedAt: DateTime(2026, 1, 2),
        items: const [],
      ),
      SaleRecord(
        id: 'sale-period',
        saleNumber: '101',
        customerName: customer.name,
        status: 'confirmed',
        grandTotal: 500,
        createdAt: DateTime(2026, 2, 5),
        confirmedAt: DateTime(2026, 2, 5),
        items: const [],
      ),
    ];
    final receipts = [
      CustomerReceiptRecord(
        id: 'receipt-before',
        saleNumber: '100',
        amount: 200,
        paymentMethod: 'cash',
        reference: null,
        notes: null,
        receivedAt: DateTime(2026, 1, 10),
        reversedAt: DateTime(2026, 1, 15),
        reversalReason: 'اشتباه در ثبت',
      ),
      CustomerReceiptRecord(
        id: 'receipt-period',
        saleNumber: '101',
        amount: 100,
        paymentMethod: 'card',
        reference: null,
        notes: null,
        receivedAt: DateTime(2026, 2, 10),
      ),
    ];

    final report = CustomerStatementReport.build(
      customer: customer,
      startDate: DateTime(2026, 2, 1),
      endDate: DateTime(2026, 2, 28),
      sales: sales,
      receipts: receipts,
    );

    expect(report.openingBalance, 1000);
    expect(report.totalDebit, 500);
    expect(report.totalCredit, 100);
    expect(report.closingBalance, 1400);
    expect(report.rows, hasLength(2));
  });
}
