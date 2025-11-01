import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class ReportPdfService {
  static Future<void> generateAndPrintReport({
    required String title,
    required String description,
    required String periodLabel,
    required List<Map<String, String>> metrics,
    String? itemsTitle,
    List<Map<String, String>>? items,
    // Optional structured table (e.g., Product-wise Sales)
    String? tableTitle,
    List<String>? tableHeaders,
    List<List<String>>? tableRows,
  }) async {
    final doc = pw.Document();
    // Load Unicode-capable fonts from assets (Poppins Regular/Bold)
    final base = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Poppins-Regular.ttf'),
    );
    final bold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Poppins-Bold.ttf'),
    );
    final theme = pw.ThemeData.withFont(base: base, bold: bold);
    // Keep standard A4 portrait per your requirement
    final pageFormat = PdfPageFormat.a4;
    final generatedAt = DateTime.now();

    doc.addPage(
      pw.MultiPage(
        maxPages: 200,
        pageTheme: pw.PageTheme(
          // Slightly tighter margins to use more width/height
          margin: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          pageFormat: pageFormat,
          theme: theme,
        ),
        footer: (context) => pw.Container(
          alignment: pw.Alignment.centerRight,
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Generated: ${_fmtDt(generatedAt)}',
                style: const pw.TextStyle(
                  color: PdfColors.grey700,
                  fontSize: 10,
                ),
              ),
              pw.Text(
                'Page ${context.pageNumber} / ${context.pagesCount}',
                style: const pw.TextStyle(
                  color: PdfColors.grey700,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
        build: (context) {
          return [
            // Header
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  title,
                  style: pw.TextStyle(
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(description, style: const pw.TextStyle(fontSize: 12)),
                pw.SizedBox(height: 8),
                pw.Container(
                  padding: const pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(
                    borderRadius: pw.BorderRadius.circular(6),
                    color: PdfColors.grey200,
                  ),
                  child: pw.RichText(
                    text: pw.TextSpan(
                      children: [
                        pw.TextSpan(
                          text: 'Period: ',
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                        ),
                        pw.TextSpan(text: periodLabel.replaceAll('→', 'to')),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 16),

            // Metrics with proper formatting and dividers
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                    vertical: 6,
                    horizontal: 8,
                  ),
                  color: PdfColors.indigo,
                  child: pw.Text(
                    'Summary',
                    style: pw.TextStyle(
                      color: PdfColors.white,
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                pw.SizedBox(height: 6),
                ...metrics.map((m) {
                  final title = m['title'] ?? '-';
                  final value = m['value'] ?? '-';
                  // Detect divider rows
                  if (title.startsWith('====')) {
                    return pw.Container(
                      margin: const pw.EdgeInsets.symmetric(vertical: 4),
                      decoration: const pw.BoxDecoration(
                        border: pw.Border(
                          bottom: pw.BorderSide(
                            color: PdfColors.grey400,
                            width: 1.5,
                          ),
                        ),
                      ),
                    );
                  }
                  // Empty spacer row
                  if (title.isEmpty && value.isEmpty) {
                    return pw.SizedBox(height: 4);
                  }
                  // Bold formatting for key metrics
                  final isBold = title.contains('(BOLD)');
                  final cleanTitle = title.replaceAll(' (BOLD)', '');
                  return pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 2),
                    child: pw.Row(
                      children: [
                        pw.Expanded(
                          child: pw.Text(
                            cleanTitle,
                            style: pw.TextStyle(
                              color: isBold
                                  ? PdfColors.black
                                  : PdfColors.grey700,
                              fontWeight: isBold
                                  ? pw.FontWeight.bold
                                  : pw.FontWeight.normal,
                              fontSize: isBold ? 13 : 11,
                            ),
                          ),
                        ),
                        pw.Text(
                          value,
                          style: pw.TextStyle(
                            fontWeight: isBold
                                ? pw.FontWeight.bold
                                : pw.FontWeight.normal,
                            fontSize: isBold ? 13 : 11,
                            color: isBold ? PdfColors.black : PdfColors.grey800,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
            if ((items ?? []).isNotEmpty) pw.SizedBox(height: 16),
            if ((items ?? []).isNotEmpty)
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    itemsTitle ?? 'Items',
                    style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 8),
                  ..._buildItemRows(_limitItems(items!, 100)),
                  if (items.length > 100)
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(top: 8),
                      child: pw.Text(
                        'Note: Output truncated to first 100 rows for PDF export.',
                      ),
                    ),
                ],
              ),

            // Optional structured table section
            if ((tableHeaders ?? const []).isNotEmpty &&
                (tableRows ?? const []).isNotEmpty) ...[
              pw.SizedBox(height: 16),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                  vertical: 6,
                  horizontal: 8,
                ),
                color: PdfColors.blueGrey800,
                child: pw.Text(
                  tableTitle ?? 'Details',
                  style: pw.TextStyle(
                    color: PdfColors.white,
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Table(
                border: const pw.TableBorder(
                  horizontalInside: pw.BorderSide(
                    color: PdfColors.grey300,
                    width: 0.5,
                  ),
                  bottom: pw.BorderSide(color: PdfColors.grey400, width: 0.8),
                  top: pw.BorderSide(color: PdfColors.grey400, width: 0.8),
                ),
                columnWidths: {
                  0: const pw.FlexColumnWidth(0.7),
                  1: const pw.FlexColumnWidth(3.0),
                  2: const pw.FlexColumnWidth(1.8),
                  3: const pw.FlexColumnWidth(0.8),
                  4: const pw.FlexColumnWidth(1.2),
                  5: const pw.FlexColumnWidth(1.4),
                  6: const pw.FlexColumnWidth(2.0),
                  7: const pw.FlexColumnWidth(1.6),
                },
                children: [
                  // Header row
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(
                      color: PdfColors.grey200,
                    ),
                    children: tableHeaders!
                        .map(
                          (h) => pw.Padding(
                            padding: const pw.EdgeInsets.all(6),
                            child: pw.Text(
                              h,
                              style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  // Data rows (cap to 500 rows to avoid huge PDFs)
                  ...tableRows!
                      .take(500)
                      .map(
                        (r) => pw.TableRow(
                          children: r
                              .map(
                                (cell) => pw.Padding(
                                  padding: const pw.EdgeInsets.all(6),
                                  child: pw.Text(
                                    cell,
                                    style: const pw.TextStyle(fontSize: 10),
                                    softWrap: true,
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                ],
              ),
              if (tableRows.length > 500)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 6),
                  child: pw.Text(
                    'Note: Table truncated to first 500 rows.',
                    style: const pw.TextStyle(
                      fontSize: 10,
                      color: PdfColors.grey700,
                    ),
                  ),
                ),
            ],
          ];
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => doc.save(),
      name: _buildFileName(title, periodLabel, generatedAt),
    );
  }
}

List<Map<String, String>> _limitItems(
  List<Map<String, String>> items,
  int maxCount,
) {
  if (items.length <= maxCount) return items;
  return items.sublist(0, maxCount);
}

List<pw.Widget> _buildItemRows(List<Map<String, String>> src) {
  return src.asMap().entries.map((entry) {
    final i = entry.key;
    final it = entry.value;
    final bg = i.isEven ? PdfColors.grey100 : PdfColors.white;
    return pw.Container(
      color: bg,
      padding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 6),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 18,
            child: pw.Text(
              '${i + 1}.',
              style: const pw.TextStyle(color: PdfColors.grey600),
            ),
          ),
          pw.Expanded(child: pw.Text(it['name'] ?? '-', softWrap: true)),
          pw.SizedBox(width: 6),
          pw.SizedBox(
            width: 50,
            child: pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(
                it['stock'] ?? '-',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }).toList();
}

String _buildFileName(String title, String periodLabel, DateTime dt) {
  final base = _sanitizeFileName(title);
  final period = _sanitizeFileName(periodLabel.replaceAll(' ', ''));
  return '${base}_${period}_${_timestamp(dt)}.pdf';
}

String _sanitizeFileName(String s) {
  return s.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
}

String _timestamp(DateTime dt) =>
    '${dt.year}${_two(dt.month)}${_two(dt.day)}_${_two(dt.hour)}${_two(dt.minute)}';

String _fmtDt(DateTime dt) =>
    '${dt.year}-${_two(dt.month)}-${_two(dt.day)} ${_two(dt.hour)}:${_two(dt.minute)}';

String _two(int n) => n.toString().padLeft(2, '0');
