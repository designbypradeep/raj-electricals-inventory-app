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

class ReplacementItemOutReceipt {
  final String name;
  final int quantity;
  final double pricePerUnit;
  final String condition;
  final bool restocked;

  const ReplacementItemOutReceipt({
    required this.name,
    required this.quantity,
    required this.pricePerUnit,
    this.condition = 'resellable',
    this.restocked = true,
  });
}

class ReplacementItemInReceipt {
  final String name;
  final int quantity;
  final double pricePerUnit;

  const ReplacementItemInReceipt({
    required this.name,
    required this.quantity,
    required this.pricePerUnit,
  });
}

class ReplacementReceiptData {
  final String replacementNumber;
  final String? originalSaleId;
  final String customerName;
  final String? customerPhone;
  final DateTime date;
  final List<ReplacementItemOutReceipt> itemsReturned;
  final List<ReplacementItemInReceipt> itemsIssued;
  final double returnedTotal;
  final double issuedTotal;
  final double priceDifference;
  final bool isWaived;
  final String? waiverNote;
  final String settlementMethod;
  final double amountPaid;
  final double balanceDue;
  final String reason;
  final String? notes;

  const ReplacementReceiptData({
    required this.replacementNumber,
    this.originalSaleId,
    required this.customerName,
    this.customerPhone,
    required this.date,
    required this.itemsReturned,
    required this.itemsIssued,
    required this.returnedTotal,
    required this.issuedTotal,
    required this.priceDifference,
    this.isWaived = false,
    this.waiverNote,
    required this.settlementMethod,
    required this.amountPaid,
    required this.balanceDue,
    required this.reason,
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

                pw.SizedBox(width: 16),

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

                pw.SizedBox(width: 16),

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

  /// Generates a professional A4 Product Exchange / Replacement PDF invoice.
  static Future<Uint8List> generateReplacementInvoicePdf(ReplacementReceiptData r) async {
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

    final profile = await SupabaseService.getCurrentBusinessProfile();
    String businessName = 'Raj Electricals And Hardware';
    String address = '';
    String phone = '';
    String email = '';
    String gst = '';
    String? upiVpa;
    String? upiPayee;
    PdfColor brandColor = const PdfColor.fromInt(0xFFEA580C); // Warm amber-orange

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

    pw.MemoryImage? logoImage;
    if (profile != null && profile.logoUrl != null && profile.logoUrl!.trim().isNotEmpty) {
      try {
        final uri = Uri.parse(profile.logoUrl!.trim());
        final res = await http.get(uri).timeout(const Duration(seconds: 3));
        if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
          logoImage = pw.MemoryImage(res.bodyBytes);
        }
      } catch (_) {}
    }

    final dateStr = DateFormat('dd MMM yyyy, hh:mm a').format(r.date);
    final hasDue = r.balanceDue > 0;

    final pdf = pw.Document(theme: theme);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // 1. Top Brand Accent Bar
              pw.Container(
                height: 5,
                decoration: pw.BoxDecoration(
                  color: brandColor,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
                ),
              ),
              pw.SizedBox(height: 18),

              // 2. Header: Logo/Name on Left, Exchange Badge on Right
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Expanded(
                    child: pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        if (logoImage != null) ...[
                          pw.Container(
                            width: 48,
                            height: 48,
                            decoration: pw.BoxDecoration(
                              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                              image: pw.DecorationImage(image: logoImage, fit: pw.BoxFit.contain),
                            ),
                          ),
                          pw.SizedBox(width: 14),
                        ],
                        pw.Expanded(
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(
                                businessName,
                                style: pw.TextStyle(
                                  fontSize: 16,
                                  fontWeight: pw.FontWeight.bold,
                                  color: const PdfColor.fromInt(0xFF0F172A),
                                ),
                              ),
                              if (address.isNotEmpty) ...[
                                pw.SizedBox(height: 2),
                                pw.Text(
                                  address,
                                  style: const pw.TextStyle(fontSize: 8.5, color: PdfColor.fromInt(0xFF64748B)),
                                ),
                              ],
                              if (phone.isNotEmpty || gst.isNotEmpty) ...[
                                pw.SizedBox(height: 2),
                                pw.Row(
                                  children: [
                                    if (phone.isNotEmpty)
                                      pw.Text('Ph: $phone   ', style: const pw.TextStyle(fontSize: 8, color: PdfColor.fromInt(0xFF64748B))),
                                    if (gst.isNotEmpty)
                                      pw.Text('GSTIN: $gst', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: const PdfColor.fromInt(0xFF475569))),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 16),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: pw.BoxDecoration(
                          color: hasDue ? const PdfColor.fromInt(0xFFFFFBEB) : const PdfColor.fromInt(0xFFF0FDF4),
                          border: pw.Border.all(
                            color: hasDue ? const PdfColor.fromInt(0xFFF59E0B) : const PdfColor.fromInt(0xFF22C55E),
                            width: 1,
                          ),
                          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                        ),
                        child: pw.Text(
                          hasDue ? 'BALANCE DUE' : (r.isWaived ? 'COURTESY EXCHANGE' : 'COMPLETED'),
                          style: pw.TextStyle(
                            fontSize: 9.5,
                            fontWeight: pw.FontWeight.bold,
                            color: hasDue ? const PdfColor.fromInt(0xFFB45309) : const PdfColor.fromInt(0xFF15803D),
                          ),
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'EXCHANGE INVOICE',
                        style: pw.TextStyle(
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold,
                          color: brandColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 16),

              // 3. Exchange Meta Card
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: const PdfColor.fromInt(0xFFF8FAFC),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                  border: pw.Border.all(color: const PdfColor.fromInt(0xFFE2E8F0)),
                ),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('CUSTOMER DETAILS', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: const PdfColor.fromInt(0xFF94A3B8))),
                          pw.SizedBox(height: 3),
                          pw.Text(r.customerName, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: const PdfColor.fromInt(0xFF0F172A))),
                          if (r.customerPhone != null && r.customerPhone!.isNotEmpty)
                            pw.Text('Phone: ${r.customerPhone}', style: const pw.TextStyle(fontSize: 8.5, color: PdfColor.fromInt(0xFF475569))),
                          if (r.originalSaleId != null) ...[
                            pw.SizedBox(height: 2),
                            pw.Text('Original Bill Ref: #${r.originalSaleId}', style: const pw.TextStyle(fontSize: 8.5, color: PdfColor.fromInt(0xFF64748B))),
                          ],
                        ],
                      ),
                    ),
                    pw.Container(width: 1, height: 42, color: const PdfColor.fromInt(0xFFE2E8F0), margin: const pw.EdgeInsets.symmetric(horizontal: 16)),
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('REFERENCE & DATE', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: const PdfColor.fromInt(0xFF94A3B8))),
                          pw.SizedBox(height: 3),
                          pw.Text(r.replacementNumber, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: const PdfColor.fromInt(0xFF0F172A))),
                          pw.Text('Date: $dateStr', style: const pw.TextStyle(fontSize: 8.5, color: PdfColor.fromInt(0xFF475569))),
                          pw.Text('Reason: ${r.reason}', style: const pw.TextStyle(fontSize: 8.5, color: PdfColor.fromInt(0xFF64748B))),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 14),

              // 4. Section: Returned Items
              pw.Text(
                'RETURNED PRODUCT(S)',
                style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: const PdfColor.fromInt(0xFFDC2626)),
              ),
              pw.SizedBox(height: 6),
              pw.Table(
                border: pw.TableBorder(
                  bottom: const pw.BorderSide(color: PdfColor.fromInt(0xFFE2E8F0)),
                  horizontalInside: const pw.BorderSide(color: PdfColor.fromInt(0xFFF1F5F9)),
                ),
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFFEF2F2)),
                    children: [
                      _th('Item Description'),
                      _th('Condition', align: pw.TextAlign.center),
                      _th('Qty', align: pw.TextAlign.center),
                      _th('Rate', align: pw.TextAlign.right),
                      _th('Credit Total', align: pw.TextAlign.right),
                    ],
                  ),
                  for (final it in r.itemsReturned)
                    pw.TableRow(
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                          child: pw.Text(it.name, style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: const PdfColor.fromInt(0xFF0F172A))),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                          child: pw.Text(
                            it.condition == 'defective' || it.condition == 'damaged'
                                ? 'Defective (Quarantined)'
                                : 'Resellable (Restocked)',
                            textAlign: pw.TextAlign.center,
                            style: pw.TextStyle(
                              fontSize: 7.5,
                              color: it.condition == 'defective' || it.condition == 'damaged'
                                  ? const PdfColor.fromInt(0xFFDC2626)
                                  : const PdfColor.fromInt(0xFF15803D),
                            ),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                          child: pw.Text('${it.quantity}', textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 8.5)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                          child: pw.Text('₹${it.pricePerUnit.toStringAsFixed(2)}', textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 8.5)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                          child: pw.Text('-₹${(it.quantity * it.pricePerUnit).toStringAsFixed(2)}', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: const PdfColor.fromInt(0xFFDC2626))),
                        ),
                      ],
                    ),
                ],
              ),
              pw.SizedBox(height: 12),

              // 5. Section: New Items Issued
              pw.Text(
                'NEW PRODUCT(S) ISSUED',
                style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: const PdfColor.fromInt(0xFF16A34A)),
              ),
              pw.SizedBox(height: 6),
              pw.Table(
                border: pw.TableBorder(
                  bottom: const pw.BorderSide(color: PdfColor.fromInt(0xFFE2E8F0)),
                  horizontalInside: const pw.BorderSide(color: PdfColor.fromInt(0xFFF1F5F9)),
                ),
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF0FDF4)),
                    children: [
                      _th('Item Description'),
                      _th('Qty', align: pw.TextAlign.center),
                      _th('Rate', align: pw.TextAlign.right),
                      _th('Line Total', align: pw.TextAlign.right),
                    ],
                  ),
                  for (final it in r.itemsIssued)
                    pw.TableRow(
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                          child: pw.Text(it.name, style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: const PdfColor.fromInt(0xFF0F172A))),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                          child: pw.Text('${it.quantity}', textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 8.5)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                          child: pw.Text('₹${it.pricePerUnit.toStringAsFixed(2)}', textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 8.5)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                          child: pw.Text('₹${(it.quantity * it.pricePerUnit).toStringAsFixed(2)}', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: const PdfColor.fromInt(0xFF0F172A))),
                        ),
                      ],
                    ),
                ],
              ),
              pw.SizedBox(height: 16),

              // 6. Totals Breakdown Card
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  // Left side: UPI QR (if balance due) or Settlement note
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Container(
                          padding: const pw.EdgeInsets.all(10),
                          decoration: pw.BoxDecoration(
                            color: const PdfColor.fromInt(0xFFF8FAFC),
                            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                            border: pw.Border.all(color: const PdfColor.fromInt(0xFFE2E8F0)),
                          ),
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text('SETTLEMENT DETAILS', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: const PdfColor.fromInt(0xFF64748B))),
                              pw.SizedBox(height: 4),
                              pw.Text('Payment Mode: ${r.settlementMethod.toUpperCase()}', style: const pw.TextStyle(fontSize: 8.5, color: PdfColor.fromInt(0xFF0F172A))),
                              if (r.isWaived)
                                pw.Text('Notice: Difference was waived as customer courtesy.', style: const pw.TextStyle(fontSize: 8, color: PdfColor.fromInt(0xFF16A34A))),
                              if (r.notes != null && r.notes!.isNotEmpty)
                                pw.Text('Notes: ${r.notes}', style: const pw.TextStyle(fontSize: 8, color: PdfColor.fromInt(0xFF64748B))),
                            ],
                          ),
                        ),
                        if (hasDue && upiVpa != null) ...[
                          pw.SizedBox(height: 10),
                          pw.Row(
                            children: [
                              pw.BarcodeWidget(
                                barcode: pw.Barcode.qrCode(),
                                data: _buildUpiString(
                                  vpa: upiVpa,
                                  payeeName: upiPayee ?? businessName,
                                  amount: r.balanceDue,
                                  saleId: r.replacementNumber,
                                ),
                                width: 56,
                                height: 56,
                              ),
                              pw.SizedBox(width: 10),
                              pw.Column(
                                crossAxisAlignment: pw.CrossAxisAlignment.start,
                                children: [
                                  pw.Text('Scan to Pay Due Balance', style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: const PdfColor.fromInt(0xFF0F172A))),
                                  pw.Text('UPI: $upiVpa', style: const pw.TextStyle(fontSize: 7.5, color: PdfColor.fromInt(0xFF64748B))),
                                  pw.Text('Due: ₹${r.balanceDue.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: const PdfColor.fromInt(0xFFDC2626))),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 24),

                  // Right side: Math breakdown
                  pw.Container(
                    width: 210,
                    padding: const pw.EdgeInsets.all(12),
                    decoration: pw.BoxDecoration(
                      color: const PdfColor.fromInt(0xFFF8FAFC),
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                      border: pw.Border.all(color: const PdfColor.fromInt(0xFFE2E8F0)),
                    ),
                    child: pw.Column(
                      children: [
                        _buildSummaryRow('New Items Total', '₹${r.issuedTotal.toStringAsFixed(2)}'),
                        pw.SizedBox(height: 5),
                        _buildSummaryRow('Returned Credit', '-₹${r.returnedTotal.toStringAsFixed(2)}', valueColor: const PdfColor.fromInt(0xFFDC2626)),
                        if (r.isWaived) ...[
                          pw.SizedBox(height: 5),
                          _buildSummaryRow('Courtesy Waived', '-₹${r.priceDifference.toStringAsFixed(2)}', valueColor: const PdfColor.fromInt(0xFF16A34A)),
                        ],
                        pw.Divider(color: const PdfColor.fromInt(0xFFCBD5E1), thickness: 0.8),
                        _buildSummaryRow(
                          'Price Difference',
                          r.isWaived ? '₹0.00' : '₹${r.priceDifference.toStringAsFixed(2)}',
                          isBold: true,
                          valueColor: const PdfColor.fromInt(0xFF0F172A),
                        ),
                        pw.SizedBox(height: 5),
                        _buildSummaryRow(
                          'Amount Paid',
                          '₹${r.amountPaid.toStringAsFixed(2)}',
                          valueColor: const PdfColor.fromInt(0xFF16A34A),
                        ),
                        if (hasDue) ...[
                          pw.SizedBox(height: 5),
                          _buildSummaryRow(
                            'Balance Due',
                            '₹${r.balanceDue.toStringAsFixed(2)}',
                            isBold: true,
                            valueColor: const PdfColor.fromInt(0xFFDC2626),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              pw.Spacer(),

              // 7. Footer
              pw.Container(
                padding: const pw.EdgeInsets.only(top: 10),
                decoration: const pw.BoxDecoration(
                  border: pw.Border(top: pw.BorderSide(color: PdfColor.fromInt(0xFFE2E8F0))),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Thank you for shopping with us!', style: const pw.TextStyle(fontSize: 8, color: PdfColor.fromInt(0xFF64748B))),
                    pw.Text('Computer Generated Exchange Invoice', style: const pw.TextStyle(fontSize: 7.5, color: PdfColor.fromInt(0xFF94A3B8))),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  static pw.Widget _th(String text, {pw.TextAlign align = pw.TextAlign.left}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 8),
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(
          fontSize: 8,
          fontWeight: pw.FontWeight.bold,
          color: const PdfColor.fromInt(0xFF475569),
        ),
      ),
    );
  }

  /// Formats the product exchange receipt for sharing via WhatsApp.
  static String getReplacementWhatsAppMessage(
    ReplacementReceiptData r, {
    String? businessName,
  }) {
    final bizName = (businessName != null && businessName.trim().isNotEmpty)
        ? businessName.trim()
        : 'Raj Electricals';
    final dateStr = DateFormat('dd/MM/yyyy, hh:mm a').format(r.date);

    final sb = StringBuffer();
    sb.writeln('*Product Exchange Receipt*');
    sb.writeln('*$bizName*');
    sb.writeln('--------------------------------');
    sb.writeln('Ref: ${r.replacementNumber} | Date: $dateStr');
    if (r.originalSaleId != null) {
      sb.writeln('Original Bill: #${r.originalSaleId}');
    }
    sb.writeln('Customer: ${r.customerName}');
    sb.writeln('--------------------------------');
    sb.writeln('*RETURNED ITEM(S):*');
    for (final it in r.itemsReturned) {
      final condStr = it.condition == 'defective' || it.condition == 'damaged'
          ? ' [Defective - Not Restocked]'
          : ' [Resellable]';
      sb.writeln('- ${it.name} x${it.quantity} (₹${(it.quantity * it.pricePerUnit).toStringAsFixed(2)})$condStr');
    }
    sb.writeln('Credit: -₹${r.returnedTotal.toStringAsFixed(2)}');
    sb.writeln('--------------------------------');
    sb.writeln('*NEW ITEM(S) ISSUED:*');
    for (final it in r.itemsIssued) {
      sb.writeln('- ${it.name} x${it.quantity} (₹${(it.quantity * it.pricePerUnit).toStringAsFixed(2)})');
    }
    sb.writeln('Value: ₹${r.issuedTotal.toStringAsFixed(2)}');
    sb.writeln('--------------------------------');
    if (r.isWaived) {
      sb.writeln('*Price Difference: ₹0.00 (Waived as Courtesy)*');
    } else {
      sb.writeln('*Net Difference: ₹${r.priceDifference.abs().toStringAsFixed(2)}*');
      if (r.priceDifference >= 0) {
        sb.writeln('Settlement: ${r.settlementMethod.toUpperCase()} (₹${r.amountPaid.toStringAsFixed(2)})');
        if (r.balanceDue > 0) {
          sb.writeln('*BALANCE DUE: ₹${r.balanceDue.toStringAsFixed(2)}*');
        }
      } else {
        sb.writeln('Refund to Customer: ₹${r.priceDifference.abs().toStringAsFixed(2)} (${r.settlementMethod.toUpperCase()})');
      }
    }
    sb.writeln('--------------------------------');
    sb.writeln('Thank you for shopping with us!');
    return sb.toString();
  }

  /// Opens the system share sheet with the generated replacement PDF.
  static Future<void> shareReplacementReceiptPdf(ReplacementReceiptData r) async {
    final bytes = await generateReplacementInvoicePdf(r);
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'Exchange-${r.replacementNumber}.pdf',
    );
  }

  /// Opens native print preview dialog for replacement invoice.
  static Future<void> printReplacementReceipt(ReplacementReceiptData r) async {
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => await generateReplacementInvoicePdf(r),
      name: 'Exchange-${r.replacementNumber}',
    );
  }
}
