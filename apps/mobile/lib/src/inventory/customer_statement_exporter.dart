import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:pdf/pdf.dart' as pdf;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import 'inventory_repository.dart';

class CustomerStatementRow {
  const CustomerStatementRow({
    required this.date,
    required this.title,
    required this.description,
    required this.debit,
    required this.credit,
    required this.balance,
  });

  final DateTime date;
  final String title;
  final String description;
  final num debit;
  final num credit;
  final num balance;
}

class CustomerStatementReport {
  const CustomerStatementReport({
    required this.customerName,
    required this.phone,
    required this.companyName,
    required this.startDate,
    required this.endDate,
    required this.openingBalance,
    required this.rows,
    required this.closingBalance,
  });

  final String customerName;
  final String? phone;
  final String? companyName;
  final DateTime startDate;
  final DateTime endDate;
  final num openingBalance;
  final List<CustomerStatementRow> rows;
  final num closingBalance;

  factory CustomerStatementReport.build({
    required CustomerRecord customer,
    required DateTime startDate,
    required DateTime endDate,
    required List<SaleRecord> sales,
    required List<CustomerReceiptRecord> receipts,
  }) {
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    final endExclusive = DateTime(endDate.year, endDate.month, endDate.day + 1);
    final events = <_StatementEvent>[
      for (final sale in sales)
        _StatementEvent(
          date: sale.confirmedAt ?? sale.createdAt,
          title: 'فاکتور ${sale.saleNumber}',
          description: '${sale.items.length} قلم کالا و خدمت',
          amount: sale.grandTotal,
          isReceipt: false,
        ),
      for (final receipt in receipts)
        _StatementEvent(
          date: receipt.receivedAt,
          title: 'دریافت فاکتور ${receipt.saleNumber}',
          description: '${_paymentLabel(receipt.paymentMethod)}'
              '${receipt.reference == null ? '' : ' • ${receipt.reference}'}',
          amount: receipt.amount,
          isReceipt: true,
        ),
    ]..sort((a, b) {
        final byDate = a.date.compareTo(b.date);
        if (byDate != 0) return byDate;
        return a.isReceipt == b.isReceipt ? 0 : (a.isReceipt ? 1 : -1);
      });

    var opening = 0.0;
    for (final event in events.where((event) => event.date.isBefore(start))) {
      opening += event.isReceipt ? -event.amount : event.amount;
    }

    var balance = opening;
    final rows = <CustomerStatementRow>[];
    for (final event in events.where((event) =>
        !event.date.isBefore(start) && event.date.isBefore(endExclusive))) {
      final debit = event.isReceipt ? 0 : event.amount;
      final credit = event.isReceipt ? event.amount : 0;
      balance += debit - credit;
      rows.add(CustomerStatementRow(
        date: event.date,
        title: event.title,
        description: event.description,
        debit: debit,
        credit: credit,
        balance: balance,
      ));
    }

    return CustomerStatementReport(
      customerName: customer.name,
      phone: customer.phone,
      companyName: customer.companyName,
      startDate: start,
      endDate: DateTime(endDate.year, endDate.month, endDate.day),
      openingBalance: opening,
      rows: List.unmodifiable(rows),
      closingBalance: balance,
    );
  }
}

class CustomerStatementExporter {
  static Future<void> shareExcel(CustomerStatementReport report) async {
    final workbook = Excel.createExcel();
    final sheet = workbook['صورت حساب'];
    sheet.appendRow([TextCellValue('کسبمن | صورت‌حساب مشتری')]);
    sheet.appendRow([TextCellValue('نام مشتری'), TextCellValue(report.customerName)]);
    sheet.appendRow([TextCellValue('تلفن'), TextCellValue(report.phone ?? '—')]);
    sheet.appendRow([TextCellValue('شرکت'), TextCellValue(report.companyName ?? '—')]);
    sheet.appendRow([
      TextCellValue('بازه گزارش'),
      TextCellValue('${_date(report.startDate)} تا ${_date(report.endDate)}'),
    ]);
    sheet.appendRow([
      TextCellValue('مانده اول دوره'),
      DoubleCellValue(report.openingBalance.toDouble()),
    ]);
    sheet.appendRow([]);
    sheet.appendRow([
      TextCellValue('تاریخ'),
      TextCellValue('شرح'),
      TextCellValue('جزئیات'),
      TextCellValue('بدهکار (تومان)'),
      TextCellValue('بستانکار (تومان)'),
      TextCellValue('مانده (تومان)'),
    ]);
    for (final row in report.rows) {
      sheet.appendRow([
        TextCellValue(_date(row.date)),
        TextCellValue(row.title),
        TextCellValue(row.description),
        DoubleCellValue(row.debit.toDouble()),
        DoubleCellValue(row.credit.toDouble()),
        DoubleCellValue(row.balance.toDouble()),
      ]);
    }
    sheet.appendRow([]);
    sheet.appendRow([
      TextCellValue('مانده پایان دوره'),
      DoubleCellValue(report.closingBalance.toDouble()),
    ]);
    final bytes = workbook.encode();
    if (bytes == null || bytes.isEmpty) {
      throw StateError('ساخت فایل Excel ناموفق بود.');
    }
    final name = 'customer-statement-${_safeName(report.customerName)}.xlsx';
    await SharePlus.instance.share(ShareParams(
      files: [XFile.fromData(
        Uint8List.fromList(bytes),
        mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        name: name,
      )],
      subject: 'صورت‌حساب ${report.customerName}',
    ));
  }

  static Future<void> sharePdf(CustomerStatementReport report) async {
    final font = await PdfGoogleFonts.notoSansArabicRegular();
    final document = pw.Document(
      theme: pw.ThemeData.withFont(base: font, bold: font),
    );
    final rows = <pw.TableRow>[
      _pdfRow(
        ['تاریخ', 'شرح', 'جزئیات', 'بدهکار', 'بستانکار', 'مانده'],
        header: true,
      ),
      for (final row in report.rows)
        _pdfRow([
          _date(row.date),
          row.title,
          row.description,
          _number(row.debit),
          _number(row.credit),
          _number(row.balance),
        ]),
    ];
    document.addPage(pw.MultiPage(
      pageFormat: pdf.PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(28),
      theme: pw.ThemeData.withFont(base: font, bold: font),
      build: (context) => [
        pw.Directionality(
          textDirection: pw.TextDirection.rtl,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Text('کسبمن | صورت‌حساب مشتری',
                  style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 8),
              pw.Text('نام مشتری: ${report.customerName}'),
              pw.Text('تلفن: ${report.phone ?? '—'}    شرکت: ${report.companyName ?? '—'}'),
              pw.Text('بازه گزارش: ${_date(report.startDate)} تا ${_date(report.endDate)}'),
              pw.SizedBox(height: 8),
              pw.Text('مانده اول دوره: ${_signed(report.openingBalance)} تومان'),
              pw.SizedBox(height: 14),
              pw.Table(
                border: pw.TableBorder.all(color: const pdf.PdfColor(0.78, 0.82, 0.87), width: 0.5),
                columnWidths: const {
                  0: pw.FixedColumnWidth(72),
                  1: pw.FlexColumnWidth(1.3),
                  2: pw.FlexColumnWidth(1.5),
                  3: pw.FixedColumnWidth(76),
                  4: pw.FixedColumnWidth(76),
                  5: pw.FixedColumnWidth(82),
                },
                children: rows,
              ),
              pw.SizedBox(height: 12),
              pw.Text('مانده پایان دوره: ${_signed(report.closingBalance)} تومان',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
              pw.SizedBox(height: 8),
              pw.Text('این گزارش بر اساس فاکتورهای تأییدشده و دریافت‌های ثبت‌شده تهیه شده است.',
                  style: const pw.TextStyle(fontSize: 8)),
            ],
          ),
        ),
      ],
    ));
    final bytes = await document.save();
    final name = 'customer-statement-${_safeName(report.customerName)}.pdf';
    await SharePlus.instance.share(ShareParams(
      files: [XFile.fromData(
        bytes,
        mimeType: 'application/pdf',
        name: name,
      )],
      subject: 'صورت‌حساب ${report.customerName}',
    ));
  }

  static pw.TableRow _pdfRow(List<String> cells, {bool header = false}) {
    return pw.TableRow(
      decoration: header
          ? const pw.BoxDecoration(color: pdf.PdfColor(0.88, 0.93, 0.97))
          : null,
      children: [
        for (final value in cells)
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 6),
            child: pw.Text(
              value,
              textDirection: pw.TextDirection.rtl,
              style: pw.TextStyle(
                fontSize: header ? 8.5 : 8,
                fontWeight: header ? pw.FontWeight.bold : pw.FontWeight.normal,
              ),
            ),
          ),
      ],
    );
  }
}

class _StatementEvent {
  const _StatementEvent({
    required this.date,
    required this.title,
    required this.description,
    required this.amount,
    required this.isReceipt,
  });

  final DateTime date;
  final String title;
  final String description;
  final num amount;
  final bool isReceipt;
}

String _paymentLabel(String method) => switch (method) {
  'cash' => 'نقدی',
  'card' => 'کارت‌خوان',
  'bank_transfer' => 'انتقال بانکی',
  'cheque' => 'چک',
  _ => 'سایر',
};

String _date(DateTime value) =>
    '${value.year}/${value.month.toString().padLeft(2, '0')}/${value.day.toString().padLeft(2, '0')}';

String _number(num value) => value.toStringAsFixed(0).replaceAllMapped(
  RegExp(r'\B(?=(\d{3})+(?!\d))'),
  (match) => ',',
);

String _signed(num value) =>
    value < 0 ? 'بستانکار ${_number(value.abs())}' : 'بدهکار ${_number(value)}';

String _safeName(String value) =>
    value.replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '-').replaceAll(RegExp(r'-+'), '-');
