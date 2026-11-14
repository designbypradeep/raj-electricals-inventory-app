import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import 'supabase_service.dart';

class ReceiptItem {
  final String name;
  final int quantity;
  final double pricePerUnit;
  final String? itemCode;
  final String? unit;

  const ReceiptItem({
    required this.name,
    required this.quantity,
    required this.pricePerUnit,
    this.itemCode,
    this.unit,
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
  final double? amountPaid;
  final String paymentMethod;
  final DateTime saleDate;
  final String status;
  final String? notes;

  const ReceiptData({
    required this.saleId,
    required this.customerName,
    this.customerPhone,
    this.transactionId,
    required this.items,
    required this.subTotal,
    required this.discount,
    required this.finalTotal,
    this.amountPaid,
    required this.paymentMethod,
    required this.saleDate,
    this.status = 'completed',
    this.notes,
  });
}

class ReceiptService {
  /// Generates a professional A4 invoice PDF matching the web version design and layout.
  static Future<Uint8List> generateInvoicePdf(ReceiptData r) async {
    // 1. Load custom Poppins fonts from assets
    final fontRegular = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Poppins-Regular.ttf'),
    );
    final fontBold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Poppins-Bold.ttf'),
    );

    final theme = pw.ThemeData.withFont(
      base: fontRegular,
      bold: fontBold,
    );

    // 2. Load business profile
    final profile = await SupabaseService.getCurrentBusinessProfile();
    String businessName = 'Business Name';
    String address = '';
    String phone = '';
    String email = '';
    String gst = '';
    String? upiVpa;
    String? upiPayee;
    PdfColor brandColor = const PdfColor.fromInt(0xFF0F172A); // Default dark slate

    if (profile != null) {
      if (profile.businessName.trim().isNotEmpty) {
        businessName = profile.businessName.trim();
      }
      final parts = <String>[
        profile.address?.trim() ?? '',
        profile.city?.trim() ?? '',
        profile.state?.trim() ?? '',
        profile.postalCode?.trim() ?? '',
      ]..removeWhere((s) => s.isEmpty);
      address = parts.join(', ');

      if (profile.phone != null && profile.phone!.trim().isNotEmpty) {
        phone = profile.phone!.trim();
      }
      if (profile.email != null && profile.email!.trim().isNotEmpty) {
        email = profile.email!.trim();
      }
      if (profile.gstNumber != null && profile.gstNumber!.trim().isNotEmpty) {
        gst = profile.gstNumber!.trim();
      }
      if (profile.upiVpa != null && profile.upiVpa!.trim().isNotEmpty) {
        upiVpa = profile.upiVpa!.trim();
      }
      if (profile.upiPayeeName != null && profile.upiPayeeName!.trim().isNotEmpty) {
        upiPayee = profile.upiPayeeName!.trim();
      }

      if (profile.primaryColor != null && profile.primaryColor!.trim().isNotEmpty) {
        try {
          final hex = profile.primaryColor!.replaceAll('#', '').trim();
          if (hex.length == 6) {
            final intVal = int.parse('FF$hex', radix: 16);
            brandColor = PdfColor.fromInt(intVal);
          }
        } catch (_) {}
      }
    }

    // 3. Attempt to fetch business logo image
    pw.MemoryImage? logoImage;
    if (profile != null && profile.logoUrl != null && profile.logoUrl!.trim().isNotEmpty) {
      try {
        final uri = Uri.parse(profile.logoUrl!.trim());
        final res = await http.get(uri).timeout(const Duration(seconds: 3));
        if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
          logoImage = pw.MemoryImage(res.bodyBytes);
        }
      } catch (_) {
        // Fallback gracefully without logo
      }
    }

    // Formatted date string
    final dateStr = DateFormat('dd MMM yyyy').format(r.saleDate);
    final isPending = r.status.toLowerCase() == 'pending' ||
        r.status.toLowerCase() == 'payment_pending';

    final doc = pw.Document(theme: theme);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (context) {
          return [
            // Top Brand Accent Bar
            pw.Container(
              height: 4,
              color: brandColor,
              margin: const pw.EdgeInsets.only(bottom: 20),
            ),

            // Header Row: Business Info on Left, Invoice Details on Right
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                // Left: Logo + Business Details
                pw.Expanded(
                  flex: 3,
                  child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      if (logoImage != null)
                        pw.Container(
                          width: 48,
                          height: 48,
                          margin: const pw.EdgeInsets.only(right: 12),
                          child: pw.Image(logoImage, fit: pw.BoxFit.contain),
                        ),
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              businessName,
                              style: pw.TextStyle(
                                fontSize: 18,
                                fontWeight: pw.FontWeight.bold,
                                color: brandColor,
                              ),
                            ),
                            if (address.isNotEmpty) ...[
                              pw.SizedBox(height: 3),
                              pw.Text(
                                address,
                                style: const pw.TextStyle(
                                  fontSize: 8.5,
                                  color: PdfColor.fromInt(0xFF64748B),
                                ),
                              ),
                            ],
                            pw.SizedBox(height: 2),
                            pw.Text(
                              [
                                if (phone.isNotEmpty) 'Tel: $phone',
                                if (email.isNotEmpty) 'Email: $email',
                              ].join('  |  '),
                              style: const pw.TextStyle(
                                fontSize: 8.5,
                                color: PdfColor.fromInt(0xFF64748B),
                              ),
                            ),
                            if (gst.isNotEmpty) ...[
                              pw.SizedBox(height: 2),
                              pw.Text(
                                'GSTIN: $gst',
                                style: pw.TextStyle(
                                  fontSize: 8.5,
                                  fontWeight: pw.FontWeight.bold,
                                  color: const PdfColor.fromInt(0xFF334155),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const pw.SizedBox(width: 16),

                // Right: Invoice Meta & Status
                pw.Expanded(
                  flex: 2,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        'INVOICE',
                        style: pw.TextStyle(
                          fontSize: 24,
                          fontWeight: pw.FontWeight.bold,
                          color: brandColor,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'Invoice No: INV-${r.saleId}',
                        style: const pw.TextStyle(
                          fontSize: 9,
                          color: PdfColor.fromInt(0xFF64748B),
                        ),
                      ),
                      pw.Text(
                        'Date: $dateStr',
                        style: const pw.TextStyle(
                          fontSize: 9,
                          color: PdfColor.fromInt(0xFF64748B),
                        ),
                      ),
                      pw.Text(
                        'Payment: ${r.paymentMethod.toUpperCase()}',
                        style: const pw.TextStyle(
                          fontSize: 9,
                          color: PdfColor.fromInt(0xFF64748B),
                        ),
                      ),
                      if (r.transactionId != null && r.transactionId!.trim().isNotEmpty)
                        pw.Text(
                          'Txn ID: ${r.transactionId!.trim()}',
                          style: const pw.TextStyle(
                            fontSize: 8.5,
                            color: PdfColor.fromInt(0xFF64748B),
                          ),
                        ),
                      pw.SizedBox(height: 6),
                      // Status Badge
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: pw.BoxDecoration(
                          color: isPending
                              ? const PdfColor.fromInt(0xFFFEF3C7)
                              : const PdfColor.fromInt(0xFFDCFCE7),
                          borderRadius: pw.BorderRadius.circular(4),
                        ),
                        child: pw.Text(
                          isPending ? 'PENDING' : 'PAID',
                          style: pw.TextStyle(
                            fontSize: 8.5,
                            fontWeight: pw.FontWeight.bold,
                            color: isPending
                                ? const PdfColor.fromInt(0xFFD97706)
                                : const PdfColor.fromInt(0xFF16A34A),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            pw.SizedBox(height: 14),
            pw.Divider(color: const PdfColor.fromInt(0xFFE2E8F0), thickness: 0.8),
            pw.SizedBox(height: 10),

            // BILL TO Box
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: pw.BoxDecoration(
                color: const PdfColor.fromInt(0xFFF8FAFC),
                borderRadius: pw.BorderRadius.circular(6),
                border: pw.Border.all(
                  color: const PdfColor.fromInt(0xFFE2E8F0),
                  width: 0.6,
                ),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'BILL TO',
                    style: pw.TextStyle(
                      fontSize: 7.5,
                      fontWeight: pw.FontWeight.bold,
                      color: const PdfColor.fromInt(0xFF64748B),
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    r.customerName.isEmpty ? 'Walk-in Customer' : r.customerName,
                    style: pw.TextStyle(
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                      color: const PdfColor.fromInt(0xFF0F172A),
                    ),
                  ),
                  if (r.customerPhone != null && r.customerPhone!.trim().isNotEmpty) ...[
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'Ph: +91-${r.customerPhone!.trim()}',
                      style: const pw.TextStyle(
                        fontSize: 8.5,
                        color: PdfColor.fromInt(0xFF64748B),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            pw.SizedBox(height: 14),

            // Items Table
            pw.Table(
              border: const pw.TableBorder(
                horizontalInside: pw.BorderSide(
                  color: PdfColor.fromInt(0xFFE2E8F0),
                  width: 0.5,
                ),
                bottom: pw.BorderSide(
                  color: PdfColor.fromInt(0xFFCBD5E1),
                  width: 0.8,
                ),
              ),
              columnWidths: const {
                0: pw.FixedColumnWidth(28),
                1: pw.FlexColumnWidth(5),
                2: pw.FixedColumnWidth(45),
                3: pw.FixedColumnWidth(70),
                4: pw.FixedColumnWidth(75),
              },
              children: [
                // Table Header
                pw.TableRow(
                  decoration: pw.BoxDecoration(
                    color: brandColor,
                  ),
                  children: [
                    _buildTableCell('S.No.', isHeader: true, align: pw.TextAlign.center),
                    _buildTableCell('Item Description', isHeader: true),
                    _buildTableCell('Qty', isHeader: true, align: pw.TextAlign.center),
                    _buildTableCell('Rate (₹)', isHeader: true, align: pw.TextAlign.right),
                    _buildTableCell('Amount (₹)', isHeader: true, align: pw.TextAlign.right),
                  ],
                ),
                // Table Body
                ...r.items.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final item = entry.value;
                  final isEven = idx % 2 == 0;
                  final rowBg = isEven
                      ? const PdfColor.fromInt(0xFFFFFFFF)
                      : const PdfColor.fromInt(0xFFF8FAFC);

                  final amount = item.quantity * item.pricePerUnit;
                  final hasCodeOrUnit = (item.itemCode != null && item.itemCode!.isNotEmpty) ||
                      (item.unit != null && item.unit!.isNotEmpty);

                  return pw.TableRow(
                    decoration: pw.BoxDecoration(color: rowBg),
                    children: [
                      _buildTableCell(
                        '${idx + 1}',
                        align: pw.TextAlign.center,
                        color: const PdfColor.fromInt(0xFF64748B),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              item.name,
                              style: pw.TextStyle(
                                fontSize: 9,
                                fontWeight: pw.FontWeight.bold,
                                color: const PdfColor.fromInt(0xFF1E293B),
                              ),
                            ),
                            if (hasCodeOrUnit)
                              pw.Text(
                                [
                                  if (item.itemCode != null && item.itemCode!.isNotEmpty)
                                    'Code: ${item.itemCode}',
                                  if (item.unit != null && item.unit!.isNotEmpty)
                                    'Unit: ${item.unit}',
                                ].join(' • '),
                                style: const pw.TextStyle(
                                  fontSize: 7.5,
                                  color: PdfColor.fromInt(0xFF94A3B8),
                                ),
                              ),
                          ],
                        ),
                      ),
                      _buildTableCell(
                        '${item.quantity}',
                        align: pw.TextAlign.center,
                        color: const PdfColor.fromInt(0xFF1E293B),
                      ),
                      _buildTableCell(
                        '₹${item.pricePerUnit.toStringAsFixed(2)}',
                        align: pw.TextAlign.right,
                        color: const PdfColor.fromInt(0xFF1E293B),
                      ),
                      _buildTableCell(
                        '₹${amount.toStringAsFixed(2)}',
                        align: pw.TextAlign.right,
                        isBold: true,
                        color: const PdfColor.fromInt(0xFF0F172A),
                      ),
                    ],
                  );
                }),
              ],
            ),

            pw.SizedBox(height: 14),

            // Summary & Payment Section
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Left: UPI QR Code / Payment instruction
                pw.Expanded(
                  flex: 3,
                  child: upiVpa != null && upiVpa.isNotEmpty
                      ? pw.Row(
                          crossAxisAlignment: pw.CrossAxisAlignment.center,
                          children: [
                            pw.Container(
                              padding: const pw.EdgeInsets.all(4),
                              decoration: pw.BoxDecoration(
                                border: pw.Border.all(
                                  color: const PdfColor.fromInt(0xFFE2E8F0),
                                  width: 0.8,
                                ),
                                borderRadius: pw.BorderRadius.circular(6),
                              ),
                              child: pw.BarcodeWidget(
                                barcode: pw.Barcode.qrCode(),
                                data: _buildUpiString(
                                  vpa: upiVpa,
                                  payeeName: upiPayee ?? businessName,
                                  amount: (r.amountPaid != null && r.amountPaid! < r.finalTotal)
                                      ? (r.finalTotal - r.amountPaid!)
                                      : r.finalTotal,
                                  saleId: r.saleId,
                                ),
                                width: 56,
                                height: 56,
                              ),
                            ),
                            pw.SizedBox(width: 10),
                            pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                pw.Text(
                                  'Scan & Pay via UPI',
                                  style: pw.TextStyle(
                                    fontSize: 8.5,
                                    fontWeight: pw.FontWeight.bold,
                                    color: const PdfColor.fromInt(0xFF1E293B),
                                  ),
                                ),
                                pw.SizedBox(height: 2),
                                pw.Text(
                                  upiVpa,
                                  style: const pw.TextStyle(
                                    fontSize: 8,
                                    color: PdfColor.fromInt(0xFF64748B),
                                  ),
                                ),
                                pw.SizedBox(height: 2),
                                pw.Text(
                                  'GPay • PhonePe • Paytm • BHIM',
                                  style: const pw.TextStyle(
                                    fontSize: 7,
                                    color: PdfColor.fromInt(0xFF94A3B8),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        )
                      : pw.SizedBox(),
                ),

                const pw.SizedBox(width: 16),

                // Right: Boxed Totals
                pw.Expanded(
                  flex: 3,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                    children: [
                      // Subtotal
                      _buildSummaryRow('Subtotal:', '₹${r.subTotal.toStringAsFixed(2)}'),
                      // Discount
                      if (r.discount > 0) ...[
                        pw.SizedBox(height: 4),
                        _buildSummaryRow(
                          'Discount:',
                          '- ₹${r.discount.toStringAsFixed(2)}',
                          valueColor: const PdfColor.fromInt(0xFF16A34A),
                        ),
                      ],
                      pw.SizedBox(height: 6),
                      // Grand Total Box
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: pw.BoxDecoration(
                          color: const PdfColor.fromInt(0xFF0F172A),
                          borderRadius: pw.BorderRadius.circular(4),
                        ),
                        child: pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text(
                              'GRAND TOTAL',
                              style: pw.TextStyle(
                                color: PdfColors.white,
                                fontWeight: pw.FontWeight.bold,
                                fontSize: 9.5,
                              ),
                            ),
                            pw.Text(
                              '₹${r.finalTotal.toStringAsFixed(2)}',
                              style: pw.TextStyle(
                                color: PdfColors.white,
                                fontWeight: pw.FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Partial Payment (Amount Paid & Due)
                      if (r.amountPaid != null && r.amountPaid! < r.finalTotal) ...[
                        pw.SizedBox(height: 6),
                        _buildSummaryRow(
                          'Amount Paid:',
                          '₹${r.amountPaid!.toStringAsFixed(2)}',
                        ),
                        pw.SizedBox(height: 4),
                        _buildSummaryRow(
                          'Balance Due:',
                          '₹${(r.finalTotal - r.amountPaid!).toStringAsFixed(2)}',
                          valueColor: const PdfColor.fromInt(0xFFDC2626),
                          isBold: true,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),

            // Pending Notice Banner
            if (isPending) ...[
              pw.SizedBox(height: 16),
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                decoration: pw.BoxDecoration(
                  color: const PdfColor.fromInt(0xFFFEF3C7),
                  borderRadius: pw.BorderRadius.circular(6),
                  border: pw.Border.all(
                    color: const PdfColor.fromInt(0xFFF59E0B),
                    width: 0.8,
                  ),
                ),
                child: pw.Center(
                  child: pw.Text(
                    'Payment received. Order under verification.',
                    style: pw.TextStyle(
                      fontSize: 8.5,
                      fontWeight: pw.FontWeight.bold,
                      color: const PdfColor.fromInt(0xFFB45309),
                    ),
                  ),
                ),
              ),
            ],

            pw.SizedBox(height: 24),
            pw.Divider(color: const PdfColor.fromInt(0xFFE2E8F0), thickness: 0.8),
            pw.SizedBox(height: 8),

            // Footer
            pw.Center(
              child: pw.Text(
                'Thank you for your business!',
                style: const pw.TextStyle(
                  fontSize: 9,
                  color: PdfColor.fromInt(0xFF64748B),
                ),
              ),
            ),
            pw.SizedBox(height: 3),
            pw.Center(
              child: pw.Text(
                'Powered by Inventoza  |  This is a computer-generated invoice.',
                style: const pw.TextStyle(
                  fontSize: 7,
                  color: PdfColor.fromInt(0xFF94A3B8),
                ),
              ),
            ),
          ];
        },
      ),
    );

    return doc.save();
  }

  static pw.Widget _buildTableCell(
    String text, {
    bool isHeader = false,
    pw.TextAlign align = pw.TextAlign.left,
    bool isBold = false,
    PdfColor? color,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(
          color: isHeader
              ? PdfColors.white
              : (color ?? const PdfColor.fromInt(0xFF1E293B)),
          fontSize: isHeader ? 8.5 : 9,
          fontWeight: (isHeader || isBold) ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  static pw.Widget _buildSummaryRow(
    String label,
    String value, {
    PdfColor? valueColor,
    bool isBold = false,
  }) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          label,
          style: const pw.TextStyle(
            fontSize: 9,
            color: PdfColor.fromInt(0xFF64748B),
          ),
        ),
        pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: 9,
            fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
            color: valueColor ?? const PdfColor.fromInt(0xFF0F172A),
          ),
        ),
      ],
    );
  }

  static String _buildUpiString({
    required String vpa,
    required String payeeName,
    required double amount,
    required String saleId,
  }) {
    final encName = Uri.encodeComponent(payeeName);
    final amtStr = amount.toStringAsFixed(2);
    return 'upi://pay?pa=$vpa&pn=$encName&am=$amtStr&cu=INR&tn=Invoice%20$saleId';
  }

  /// Formats the itemized sale receipt for sharing directly via WhatsApp matching web format.
  static String getWhatsAppMessage(
    ReceiptData r, {
    String? businessName,
  }) {
    final bizName = (businessName != null && businessName.trim().isNotEmpty)
        ? businessName.trim()
        : 'Inventoza';
    final dateStr = DateFormat('dd/MM/yyyy, hh:mm a').format(r.saleDate);

    final sb = StringBuffer();
    sb.writeln('*Receipt from $bizName*');
    sb.writeln('--------------------------------');
    sb.writeln('Inv: ${r.saleId} | Date: $dateStr');
    sb.writeln('--------------------------------');

    for (final item in r.items) {
      final lineTotal = (item.quantity * item.pricePerUnit).toStringAsFixed(2);
      final unitStr = (item.unit != null && item.unit!.isNotEmpty) ? ' ${item.unit}' : '';
      sb.writeln('${item.name} x ${item.quantity}$unitStr = ₹$lineTotal');
    }

    sb.writeln('--------------------------------');
    sb.writeln('*Subtotal: ₹${r.subTotal.toStringAsFixed(2)}*');
    if (r.discount > 0) {
      sb.writeln('Discount: - ₹${r.discount.toStringAsFixed(2)}');
    }
    sb.writeln('*Final Total: ₹${r.finalTotal.toStringAsFixed(2)}*');

    if (r.amountPaid != null && r.amountPaid! < r.finalTotal) {
      final due = r.finalTotal - r.amountPaid!;
      sb.writeln('Paid: ₹${r.amountPaid!.toStringAsFixed(2)} | Due: ₹${due.toStringAsFixed(2)}');
    }

    sb.writeln('--------------------------------');
    sb.writeln('Thank you for your business!');

    return sb.toString();
  }

  /// Opens the system share sheet with the generated invoice PDF.
  static Future<void> shareReceiptPdf(ReceiptData r) async {
    final bytes = await generateInvoicePdf(r);
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'Invoice-${r.saleId}.pdf',
    );
  }

  /// Opens native print preview dialog (supports thermal printers, laser, or PDF save).
  static Future<void> printReceipt(ReceiptData r) async {
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => await generateInvoicePdf(r),
      name: 'Invoice-${r.saleId}',
    );
  }
}
