import 'package:flutter/services.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'supabase_service.dart';

class ReceiptItem {
  final String name;
  final int quantity;
  final double pricePerUnit;
  final String? itemCode;
  const ReceiptItem({
    required this.name,
    required this.quantity,
    required this.pricePerUnit,
    this.itemCode,
  });
}

class ReceiptData {
  final String saleId;
  final String customerName;
  final String? customerPhone;
  final String? transactionId;
  final List<ReceiptItem> items;
  final double subTotal;
  final double discount;
  final double finalTotal;
  final String paymentMethod;
  final DateTime saleDate;
  final String status;

  const ReceiptData({
    required this.saleId,
    required this.customerName,
    this.customerPhone,
    this.transactionId,
    required this.items,
    required this.subTotal,
    required this.discount,
    required this.finalTotal,
    required this.paymentMethod,
    required this.saleDate,
    this.status = 'completed',
  });
}

class ReceiptService {
  static Future<void> shareReceiptPdf(ReceiptData r) async {
    // Load custom fonts (Poppins from assets)
    final fontRegular = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Poppins-Regular.ttf'),
    );
    final fontBold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Poppins-Bold.ttf'),
    );

    final doc = pw.Document(
      theme: pw.ThemeData.withFont(base: fontRegular, bold: fontBold),
    );

    // Business profile for header
    final profile = await SupabaseService.getCurrentBusinessProfile();
    String? businessName;
    String address = '';
    String phone = '';
    String gst = '';
    if (profile != null) {
      final bn = profile.businessName.trim();
      businessName = bn.isEmpty ? null : bn;
      final parts = <String>[
        profile.address?.trim() ?? '',
        profile.city?.trim() ?? '',
        profile.state?.trim() ?? '',
        profile.postalCode?.trim() ?? '',
      ]..removeWhere((s) => s.isEmpty);
      address = parts.join(', ');
      final ph = profile.phone?.trim() ?? '';
      if (ph.isNotEmpty) phone = ph;
      final gstNum = profile.gstNumber?.trim() ?? '';
      if (gstNum.isNotEmpty) gst = 'GSTIN: $gstNum';
    }

    // Build items table rows
    final itemRows = r.items.asMap().entries.map((e) {
      final i = e.key;
      final it = e.value;
      return [
        '${i + 1}',
        it.itemCode != null && it.itemCode!.isNotEmpty
            ? '${it.name} (${it.itemCode})'
            : it.name,
        '${it.quantity}',
        it.pricePerUnit.toStringAsFixed(2),
        (it.quantity * it.pricePerUnit).toStringAsFixed(2),
      ];
    }).toList();

    // Add totals
    itemRows.add(['', '', '', 'Subtotal:', r.subTotal.toStringAsFixed(2)]);
    itemRows.add([
      '',
      '',
      '',
      'Discount:',
      '- ${r.discount.toStringAsFixed(2)}',
    ]);
    itemRows.add([
      '',
      '',
      '',
      'GRAND TOTAL:',
      '₹${r.finalTotal.toStringAsFixed(2)}',
    ]);

    // Header and content
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          // Header (conditionally render available fields only)
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              if (businessName != null)
                pw.Text(
                  businessName,
                  style: pw.TextStyle(
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                  ),
                  textAlign: pw.TextAlign.center,
                ),
              if (address.isNotEmpty) ...[
                pw.SizedBox(height: 4),
                pw.Text(
                  address,
                  style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                  textAlign: pw.TextAlign.center,
                ),
              ],
              if (phone.isNotEmpty || gst.isNotEmpty) ...[
                pw.SizedBox(height: 2),
                pw.Text(
                  [
                    if (phone.isNotEmpty) 'Phone: $phone',
                    if (gst.isNotEmpty) gst,
                  ].join(' | '),
                  style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                  textAlign: pw.TextAlign.center,
                ),
              ],
              pw.SizedBox(height: 8),
              pw.Divider(),
            ],
          ),

          // Bill details
          pw.SizedBox(height: 8),
          pw.Row(
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Invoice No: ${r.saleId}',
                      style: const pw.TextStyle(fontSize: 12),
                    ),
                    pw.Text(
                      'Bill To: ${r.customerName}',
                      style: const pw.TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    'Date: ${r.saleDate.toLocal().toString().split('.').first}',
                    style: const pw.TextStyle(fontSize: 12),
                  ),
                  if (r.transactionId != null &&
                      r.transactionId!.trim().isNotEmpty) ...[
                    pw.SizedBox(height: 2),
                    pw.Row(
                      mainAxisSize: pw.MainAxisSize.min,
                      children: [
                        pw.Text(
                          'Transaction ID: ',
                          style: pw.TextStyle(font: fontBold, fontSize: 12),
                        ),
                        pw.Text(
                          r.transactionId!,
                          style: const pw.TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ],
          ),

          // Pending Warning
          if (r.status == 'payment_pending' || r.status == 'pending') ...[
            pw.SizedBox(height: 10),
            pw.Center(
              child: pw.Text(
                'Payment received. Order under verification.',
                style: pw.TextStyle(
                  color: PdfColors.blue700,
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
          ],

          pw.SizedBox(height: 10),

          // Items table
          pw.Table(
            border: pw.TableBorder.all(width: 0.5, color: PdfColors.grey400),
            columnWidths: const {
              0: pw.FlexColumnWidth(1),
              1: pw.FlexColumnWidth(5),
              2: pw.FlexColumnWidth(2),
              3: pw.FlexColumnWidth(2),
              4: pw.FlexColumnWidth(2),
            },
            children: [
              // header
              pw.TableRow(
                decoration: const pw.BoxDecoration(
                  color: PdfColor.fromInt(0xFF262626),
                ),
                children: [
                  for (final h in [
                    'S.No.',
                    'Item Description',
                    'Qty',
                    'Rate (₹)',
                    'Amount (₹)',
                  ])
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text(
                        h,
                        style: pw.TextStyle(
                          color: PdfColors.white,
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 10,
                        ),
                      ),
                    ),
                ],
              ),
              // body
              ...itemRows.asMap().entries.map((entry) {
                final idx = entry.key;
                final row = entry.value;
                final isTotalRow = idx >= r.items.length;
                final isGrand = isTotalRow && row[3] == 'GRAND TOTAL:';
                return pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.white),
                  children: [
                    for (var c = 0; c < row.length; c++)
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text(
                          row[c],
                          style: pw.TextStyle(
                            fontWeight: isTotalRow
                                ? pw.FontWeight.bold
                                : pw.FontWeight.normal,
                            fontSize: isGrand ? 12 : 10,
                          ),
                        ),
                      ),
                  ],
                );
              }),
            ],
          ),

          pw.SizedBox(height: 16),
          pw.Center(
            child: pw.Text(
              'Thank you for your business!',
              style: pw.TextStyle(color: PdfColors.grey700, fontSize: 10),
            ),
          ),
        ],
      ),
    );

    await Printing.sharePdf(
      bytes: await doc.save(),
      filename: 'Invoice-${r.saleId}.pdf',
    );
  }
}
