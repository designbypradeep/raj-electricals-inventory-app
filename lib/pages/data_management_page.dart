import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:convert';
import 'dart:io';
import '../widgets/page_header.dart';
import '../data/app_database.dart';
import '../services/supabase_service.dart';
import '../services/connectivity_service.dart';

// Export/Import mode enums
enum ExportMode { full, catalogWithBusiness, catalogTemplate, businessInfo }

enum ImportMode { full, catalogWithBusiness, catalogTemplate, businessInfo }

class DataManagementPage extends StatefulWidget {
  final AppDatabase db;
  const DataManagementPage({super.key, required this.db});

  @override
  State<DataManagementPage> createState() => _DataManagementPageState();
}

class _DataManagementPageState extends State<DataManagementPage> {
  String _confirmText = '';
  bool _isExporting = false;
  bool _isImporting = false;
  bool _isDeleting = false;
  String? _exportPath;
  String? _message;
  bool _isSuccess = false;
  bool _isDryRun = true; // Dry-run preview before actual import
  // Selective import flags (for Full restore)
  bool _impProducts = true;
  bool _impPurchases = true;
  bool _impSales = true;
  bool _impReturns = true;
  bool _impReplacements = true;
  bool _impRequests = true;
  String _repConflictStrategy = 'skip'; // 'skip' | 'suffix'

  bool get _canDelete => _confirmText.trim().toUpperCase() == 'DELETE';

  // Export/Import modes
  ExportMode _exportMode = ExportMode.catalogTemplate; // working now
  ImportMode _importMode = ImportMode.catalogTemplate; // working now

  Future<Directory> _ensureDefaultBackupDir() async {
    final home =
        Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        '.';
    final dir = Directory(
      '$home${Platform.pathSeparator}Documents${Platform.pathSeparator}SmartInventory${Platform.pathSeparator}Backups',
    );
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<bool?> _showImportPreviewDialog(
    Map<String, dynamic> preview,
    String fileName,
  ) async {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    TextStyle rowStyle([bool strong = false]) => TextStyle(
      color: onSurface.withValues(alpha: strong ? 0.95 : 0.85),
      fontWeight: strong ? FontWeight.w600 : FontWeight.w500,
    );

    Widget row(String label, int value) => Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(child: Text(label, style: rowStyle())),
        const SizedBox(width: 16),
        Text(value.toString(), style: rowStyle(true)),
      ],
    );

    final Map<String, dynamic> details = Map<String, dynamic>.from(
      preview['details'] as Map? ?? const {},
    );
    List<String> strList(String key) =>
        ((details[key] as List?)?.map((e) => e.toString()).toList()) ??
        const [];
    Map<String, dynamic> group(String key) =>
        Map<String, dynamic>.from(details[key] as Map? ?? const {});

    String prettyTitle(String key) {
      switch (key) {
        case 'skipped_purchase_items':
          return 'Skipped purchase items (missing mapping)';
        case 'skipped_sales_items':
          return 'Skipped sales items (missing mapping)';
        case 'skipped_return_items':
          return 'Skipped return items (missing mapping)';
        case 'request_items_missing_product':
          return 'Request items missing product mapping';
        case 'replacements_existing_mapped':
          return 'Replacements mapped to existing numbers';
        case 'replacements_deduped_in_batch':
          return 'Replacements de-duplicated within batch';
        case 'replacements_suffixed_created':
          return 'Replacements created with suffix';
        default:
          return key.replaceAll('_', ' ');
      }
    }

    return showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Preview import: $fileName'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'This is a dry run. No data will be written. Review counts and confirm to apply.',
                    style: TextStyle(color: onSurface.withValues(alpha: 0.75)),
                  ),
                  const SizedBox(height: 10),
                  // Preflight warnings section
                  Builder(
                    builder: (context) {
                      final warnings = <String>[];
                      final skippedPurch =
                          (group('skipped_purchase_items')['count'] as int?) ??
                          0;
                      final skippedSales =
                          (group('skipped_sales_items')['count'] as int?) ?? 0;
                      final skippedReturns =
                          (group('skipped_return_items')['count'] as int?) ?? 0;
                      final reqItemsMiss =
                          (group('request_items_missing_product')['count']
                              as int?) ??
                          (preview['request_items_missing_product'] as int? ??
                              0);
                      final reqItemsIns =
                          (preview['request_items_inserted'] as int?) ?? 0;
                      final repExisting =
                          (group('replacements_existing_mapped')['count']
                              as int?) ??
                          0;
                      final repSuffixed =
                          (group('replacements_suffixed_created')['count']
                              as int?) ??
                          0;

                      final noneSelected =
                          !_impProducts &&
                          !_impPurchases &&
                          !_impSales &&
                          !_impReturns &&
                          !_impReplacements &&
                          !_impRequests;
                      if (noneSelected) {
                        warnings.add(
                          'No modules selected. Import will not apply any data.',
                        );
                      }

                      if (!_impProducts) {
                        final totalSkipped =
                            skippedPurch +
                            skippedSales +
                            skippedReturns +
                            reqItemsMiss;
                        if (totalSkipped > 0) {
                          warnings.add(
                            'Products are not selected; $totalSkipped item rows lack product mapping (Purch:$skippedPurch, Sales:$skippedSales, Returns:$skippedReturns, Request Items missing product:$reqItemsMiss).',
                          );
                        }
                      }

                      if (_impReplacements &&
                          _repConflictStrategy == 'skip' &&
                          repExisting > 0) {
                        warnings.add(
                          'Replacements: $repExisting records share existing numbers and will be mapped to existing. Switch to "Create with suffix" to create new rows.',
                        );
                      }
                      if (_impReplacements &&
                          _repConflictStrategy == 'suffix' &&
                          repSuffixed >= 5) {
                        warnings.add(
                          'Replacements: $repSuffixed numbers will be created with suffixes. Ensure this is intended.',
                        );
                      }

                      if (_impRequests && reqItemsIns > 0 && reqItemsMiss > 0) {
                        final ratio =
                            reqItemsMiss / (reqItemsIns + reqItemsMiss);
                        if (ratio >= 0.3) {
                          warnings.add(
                            'Request items: ${(ratio * 100).toStringAsFixed(0)}% of items lack product mapping and will be inserted without product reference.',
                          );
                        }
                      }

                      if (warnings.isEmpty) return const SizedBox.shrink();
                      final warnBg = Theme.of(
                        context,
                      ).colorScheme.error.withValues(alpha: 0.08);
                      final warnBorder = Theme.of(
                        context,
                      ).colorScheme.error.withValues(alpha: 0.25);
                      final warnText = Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.9);
                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 6),
                        decoration: BoxDecoration(
                          color: warnBg,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: warnBorder),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.warning_amber,
                                  color: Theme.of(context).colorScheme.error,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Preflight warnings',
                                  style: rowStyle(true),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            ...warnings.map(
                              (w) => Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text(
                                  '• $w',
                                  style: rowStyle().copyWith(color: warnText),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Theme.of(
                          context,
                        ).colorScheme.outline.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Column(
                      children: [
                        row(
                          'Products inserted',
                          (preview['inserted_products'] as int?) ?? 0,
                        ),
                        const SizedBox(height: 6),
                        row(
                          'Products updated',
                          (preview['updated_products'] as int?) ?? 0,
                        ),
                        const SizedBox(height: 6),
                        row(
                          'Products with images set',
                          (preview['images_set'] as int?) ?? 0,
                        ),
                        const Divider(height: 20),
                        row(
                          'Purchases inserted',
                          (preview['purchases_inserted'] as int?) ?? 0,
                        ),
                        const SizedBox(height: 6),
                        row(
                          'Purchase items inserted',
                          (preview['purchase_items_inserted'] as int?) ?? 0,
                        ),
                        const Divider(height: 20),
                        row(
                          'Sales inserted',
                          (preview['sales_inserted'] as int?) ?? 0,
                        ),
                        const SizedBox(height: 6),
                        row(
                          'Sales items inserted',
                          (preview['sales_items_inserted'] as int?) ?? 0,
                        ),
                        const Divider(height: 20),
                        row(
                          'Returns inserted',
                          (preview['returns_inserted'] as int?) ?? 0,
                        ),
                        const SizedBox(height: 6),
                        row(
                          'Return items inserted',
                          (preview['return_items_inserted'] as int?) ?? 0,
                        ),
                        const Divider(height: 20),
                        row(
                          'Replacements inserted',
                          (preview['replacements_inserted'] as int?) ?? 0,
                        ),
                        const SizedBox(height: 6),
                        row(
                          'Replacement items OUT',
                          (preview['replacement_items_out_inserted'] as int?) ??
                              0,
                        ),
                        const SizedBox(height: 6),
                        row(
                          'Replacement items IN',
                          (preview['replacement_items_in_inserted'] as int?) ??
                              0,
                        ),
                        const SizedBox(height: 6),
                        row(
                          'Replacement movements',
                          (preview['replacement_movements_inserted'] as int?) ??
                              0,
                        ),
                        const Divider(height: 20),
                        row(
                          'Item requests inserted',
                          (preview['item_requests_inserted'] as int?) ?? 0,
                        ),
                        const SizedBox(height: 6),
                        row(
                          'Request items inserted',
                          (preview['request_items_inserted'] as int?) ?? 0,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (details.isNotEmpty) ...[
                    Text('Details', style: rowStyle(true)),
                    const SizedBox(height: 8),
                    if (strList('products_inserted_names').isNotEmpty)
                      ExpansionTile(
                        title: Text(
                          'Products inserted (samples)',
                          style: rowStyle(),
                        ),
                        childrenPadding: const EdgeInsets.only(
                          left: 8,
                          right: 8,
                          bottom: 8,
                        ),
                        children: strList('products_inserted_names')
                            .map(
                              (e) => Align(
                                alignment: Alignment.centerLeft,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 2,
                                  ),
                                  child: Text(e, style: rowStyle()),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    if (strList('products_updated_names').isNotEmpty)
                      ExpansionTile(
                        title: Text(
                          'Products updated (samples)',
                          style: rowStyle(),
                        ),
                        childrenPadding: const EdgeInsets.only(
                          left: 8,
                          right: 8,
                          bottom: 8,
                        ),
                        children: strList('products_updated_names')
                            .map(
                              (e) => Align(
                                alignment: Alignment.centerLeft,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 2,
                                  ),
                                  child: Text(e, style: rowStyle()),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    // Skipped items groups
                    for (final key in const [
                      'skipped_purchase_items',
                      'skipped_sales_items',
                      'skipped_return_items',
                      'request_items_missing_product',
                      'replacements_existing_mapped',
                      'replacements_deduped_in_batch',
                    ])
                      if (group(key).isNotEmpty &&
                          ((group(key)['count'] as int? ?? 0) > 0))
                        ExpansionTile(
                          title: Text(
                            '${prettyTitle(key)} (${(group(key)['count'] as int?)?.toString() ?? '0'})',
                            style: rowStyle(),
                          ),
                          childrenPadding: const EdgeInsets.only(
                            left: 8,
                            right: 8,
                            bottom: 8,
                          ),
                          children:
                              ((group(key)['examples'] as List?)
                                          ?.map((e) => e.toString())
                                          .toList() ??
                                      const <String>[]) // examples
                                  .map(
                                    (e) => Align(
                                      alignment: Alignment.centerLeft,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 2,
                                        ),
                                        child: Text(e, style: rowStyle()),
                                      ),
                                    ),
                                  )
                                  .toList(),
                        ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    'Note: Products are merged by name+brand+size/spec. Other records are inserted with ID remapping to maintain relationships.',
                    style: TextStyle(
                      fontSize: 12,
                      color: onSurface.withValues(alpha: 0.65),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                try {
                  final dir = await _ensureDefaultBackupDir();
                  final stamp = DateTime.now()
                      .toIso8601String()
                      .replaceAll(':', '-')
                      .replaceAll('T', '_')
                      .split('.')
                      .first;

                  // Build summary CSV (all top-level int fields + settings)
                  final bufferSummary = StringBuffer('metric,value\n');
                  // Settings
                  bufferSummary.writeln(
                    'setting.replacement_conflict_strategy,$_repConflictStrategy',
                  );
                  bufferSummary.writeln(
                    'setting.module_products,${_impProducts ? 'true' : 'false'}',
                  );
                  bufferSummary.writeln(
                    'setting.module_purchases,${_impPurchases ? 'true' : 'false'}',
                  );
                  bufferSummary.writeln(
                    'setting.module_sales,${_impSales ? 'true' : 'false'}',
                  );
                  bufferSummary.writeln(
                    'setting.module_returns,${_impReturns ? 'true' : 'false'}',
                  );
                  bufferSummary.writeln(
                    'setting.module_replacements,${_impReplacements ? 'true' : 'false'}',
                  );
                  bufferSummary.writeln(
                    'setting.module_item_requests,${_impRequests ? 'true' : 'false'}',
                  );
                  preview.forEach((key, value) {
                    if (value is int) {
                      bufferSummary.writeln('$key,$value');
                    }
                  });
                  // Also include detail section counts
                  for (final k in const [
                    'skipped_purchase_items',
                    'skipped_sales_items',
                    'skipped_return_items',
                    'request_items_missing_product',
                    'replacements_existing_mapped',
                    'replacements_deduped_in_batch',
                    'replacements_suffixed_created',
                  ]) {
                    final g = group(k);
                    final c = (g['count'] as int?) ?? 0;
                    bufferSummary.writeln('details.$k.count,$c');
                  }
                  final summaryPath =
                      '${dir.path}${Platform.pathSeparator}dry_run_summary_$stamp.csv';
                  await File(
                    summaryPath,
                  ).writeAsString(bufferSummary.toString());

                  // Build details CSV (section,example)
                  final bufferDetails = StringBuffer('section,example\n');
                  // List sections with examples
                  void addExamples(String sectionKey, List list) {
                    for (final e in list) {
                      bufferDetails.writeln(
                        '${sectionKey.replaceAll(',', ' ')},${e.toString().replaceAll(',', ' ')}',
                      );
                    }
                  }

                  // Arrays of strings
                  final insertedNames = strList('products_inserted_names');
                  if (insertedNames.isNotEmpty) {
                    addExamples('products_inserted_names', insertedNames);
                  }
                  final updatedNames = strList('products_updated_names');
                  if (updatedNames.isNotEmpty) {
                    addExamples('products_updated_names', updatedNames);
                  }

                  // Grouped with examples
                  for (final k in [
                    'skipped_purchase_items',
                    'skipped_sales_items',
                    'skipped_return_items',
                    'request_items_missing_product',
                    'replacements_existing_mapped',
                    'replacements_deduped_in_batch',
                  ]) {
                    final g = group(k);
                    final ex = (g['examples'] as List?) ?? const [];
                    if (ex.isNotEmpty) addExamples(k, ex);
                  }

                  final detailsPath =
                      '${dir.path}${Platform.pathSeparator}dry_run_details_$stamp.csv';
                  await File(
                    detailsPath,
                  ).writeAsString(bufferDetails.toString());

                  _showSnack(
                    'Preview report saved to: $summaryPath',
                    success: true,
                  );
                } catch (e) {
                  _showSnack('Failed to export preview: $e', success: false);
                }
              },
              child: const Text('Export CSV'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.secondary,
                foregroundColor: Theme.of(context).colorScheme.onSecondary,
              ),
              child: const Text('Apply Import'),
            ),
          ],
        );
      },
    );
  }

  void _showSnack(String text, {required bool success}) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    // Base brand color for success/error
    final Color base = success ? scheme.primary : scheme.error;
    // Slightly adjust opacity in dark mode to avoid over-saturation glow
    final Color bg = isDark
        ? base.withAlpha((base.alpha * 0.92).toInt())
        : base.withAlpha((base.alpha * 0.97).toInt());

    // Start with onPrimary/onError, but ensure high contrast by checking luminance
    Color fg = success ? scheme.onPrimary : scheme.onError;
    final double bgLum = bg.computeLuminance();
    final double fgLum = fg.computeLuminance();
    final bool lowContrast = (bgLum - fgLum).abs() < 0.35; // heuristic
    if (lowContrast) {
      fg = bgLum < 0.5 ? Colors.white : Colors.black;
    }

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(success ? Icons.check_circle : Icons.error_outline, color: fg),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: TextStyle(color: fg, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        backgroundColor: bg,
        behavior: SnackBarBehavior.floating,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: fg.withValues(alpha: 0.25)),
        ),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Close',
          onPressed: () {},
          textColor: fg,
        ), // <--- Add closing bracket here
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        top: false,
        bottom: true,
        child: SingleChildScrollView(
          child: Column(
            children: [
              PageHeader(
                title: 'Data Management',
                description:
                    'Backup, restore, or permanently delete your business data',
                icon: '💾',
                showBackButton: true,
                backLabel: 'Back to Dashboard',
                wrapInSafeArea: true,
                breadcrumbs: [
                  PageHeaderBreadcrumb(label: 'Dashboard', icon: '🏠'),
                  if (MediaQuery.of(context).size.width >= 450)
                    PageHeaderBreadcrumb(
                      label: 'Data Management',
                      icon: '💾',
                      current: true,
                    ),
                ],
                stats: [
                  PageHeaderStat(
                    label: 'Data Safety',
                    value: 'Secure',
                    description: 'All operations encrypted',
                  ),
                  PageHeaderStat(
                    label: 'Backup Status',
                    value: 'Ready',
                    description: 'Export available',
                  ),
                ],
              ),

              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: MediaQuery.of(context).size.width < 480 ? 12 : 24,
                  vertical: MediaQuery.of(context).size.width < 480 ? 16 : 24,
                ),
                child: Column(
                  children: [
                    // Only show the top banner for errors to avoid duplicate success notifications
                    if (_message != null && !_isSuccess)
                      Container(
                        margin: const EdgeInsets.only(bottom: 24),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Theme.of(
                              context,
                            ).colorScheme.error.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.error,
                              color: Theme.of(context).colorScheme.error,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _message!,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    LayoutBuilder(
                      builder: (context, constraints) {
                        final isDesktop = constraints.maxWidth > 768;
                        return isDesktop
                            ? _buildDesktopLayout()
                            : _buildMobileLayout();
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopLayout() {
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _buildExportCard()),
            const SizedBox(width: 24),
            Expanded(child: _buildDeleteCard()),
          ],
        ),
        const SizedBox(height: 24),
        _buildImportCard(),
      ],
    );
  }

  Widget _buildMobileLayout() {
    return Column(
      children: [
        _buildExportCard(),
        const SizedBox(height: 24),
        _buildDeleteCard(),
        const SizedBox(height: 24),
        _buildImportCard(),
      ],
    );
  }

  Widget _buildExportCard() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1),
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.download,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Export Data',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Export mode selector
            Row(
              children: [
                Text(
                  'Mode:',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButton<ExportMode>(
                    isExpanded: true,
                    value: _exportMode,
                    onChanged: (v) =>
                        setState(() => _exportMode = v ?? _exportMode),
                    items: const [
                      DropdownMenuItem(
                        value: ExportMode.full,
                        child: Text(
                          'Full backup (all data)',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      DropdownMenuItem(
                        value: ExportMode.catalogWithBusiness,
                        child: Text(
                          'Catalog (with business)',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      DropdownMenuItem(
                        value: ExportMode.catalogTemplate,
                        child: Text(
                          'Catalog Template (no business ID)',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      DropdownMenuItem(
                        value: ExportMode.businessInfo,
                        child: Text(
                          'Business info only',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _exportMode == ExportMode.catalogTemplate
                  ? 'Export a business-agnostic catalog template (no business ID). Safe to share/import across businesses.'
                  : _exportMode == ExportMode.businessInfo
                  ? 'Export business information (branding, contact, preferences). Ownership is preserved.'
                  : _exportMode == ExportMode.catalogWithBusiness
                  ? 'Export catalog including product IDs and business ID. Useful for same-business restore or partial migration.'
                  : _exportMode == ExportMode.full
                  ? 'Export a full backup of all business data (products, images, sales, purchases, returns, replacements, requests, and settings).'
                  : 'Download a backup of your data. Selected mode not yet implemented in this build.',
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isExporting ? null : _exportData,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isExporting
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Theme.of(context).colorScheme.onPrimary,
                            ),
                          ),
                          SizedBox(width: 8),
                          Text('Generating Export...'),
                        ],
                      )
                    : const Text('Generate Export'),
              ),
            ),
            if (_exportPath != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(
                      context,
                    ).colorScheme.outline.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle,
                      color: Theme.of(context).colorScheme.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Export saved to: ${_exportPath!.split('/').last}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDeleteCard() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.error.withValues(alpha: 0.2),
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.delete_forever,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Delete Business',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'This permanently deletes your business and all related data. Type DELETE to confirm.',
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
              decoration: InputDecoration(
                labelText: 'Type DELETE',
                labelStyle: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                hintText: 'Type DELETE to confirm',
                hintStyle: TextStyle(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                ),
                border: OutlineInputBorder(
                  borderSide: BorderSide(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(
                    color: Theme.of(
                      context,
                    ).colorScheme.outline.withValues(alpha: 0.6),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(
                    color: Theme.of(context).colorScheme.primary,
                    width: 2,
                  ),
                ),
                filled: true,
                fillColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest,
              ),
              onChanged: (value) => setState(() => _confirmText = value),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: (_canDelete && !_isDeleting) ? _deleteAllData : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isDeleting
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Theme.of(context).colorScheme.onError,
                            ),
                          ),
                          SizedBox(width: 8),
                          Text('Deleting...'),
                        ],
                      )
                    : const Text('Delete Everything'),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'This action cannot be undone.',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.error,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImportCard() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1),
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.secondary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.upload,
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Import Data',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Import mode selector
            Row(
              children: [
                Text(
                  'Mode:',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButton<ImportMode>(
                    isExpanded: true,
                    value: _importMode,
                    onChanged: (v) =>
                        setState(() => _importMode = v ?? _importMode),
                    items: const [
                      DropdownMenuItem(
                        value: ImportMode.full,
                        child: Text(
                          'Full restore',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      DropdownMenuItem(
                        value: ImportMode.catalogWithBusiness,
                        child: Text(
                          'Catalog (with business)',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      DropdownMenuItem(
                        value: ImportMode.catalogTemplate,
                        child: Text(
                          'Catalog Template (no business ID)',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      DropdownMenuItem(
                        value: ImportMode.businessInfo,
                        child: Text(
                          'Business info only',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _importMode == ImportMode.catalogTemplate
                  ? 'Import a catalog template JSON into the current business. New products will be created.'
                  : _importMode == ImportMode.businessInfo
                  ? 'Import business information. If you have no business, a new one will be created. If you own the current business, its info will be updated.'
                  : _importMode == ImportMode.catalogWithBusiness
                  ? 'Import catalog including business-bound products. Default: merge by name+brand+size/spec; updates matching products and inserts new.'
                  : _importMode == ImportMode.full
                  ? 'Restore from a full backup JSON. Restores products, product images, purchases with items, sales with items, returns with items, replacements with items and stock movements, and item requests with request items.'
                  : 'Import for selected mode is not yet implemented in this build.',
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 8),
            if (_importMode == ImportMode.full)
              Row(
                children: [
                  Checkbox(
                    value: _isDryRun,
                    onChanged: (v) =>
                        setState(() => _isDryRun = v ?? _isDryRun),
                    activeColor: Theme.of(context).colorScheme.secondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Dry run (preview only). No data will be written. You can confirm to apply after preview.',
                      style: TextStyle(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.7),
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            if (_importMode == ImportMode.full) ...[
              const SizedBox(height: 6),
              Text(
                'Select modules to import:',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 16,
                runSpacing: 4,
                children: [
                  FilterChip(
                    label: const Text('Products + Images'),
                    selected: _impProducts,
                    onSelected: (v) => setState(() => _impProducts = v),
                  ),
                  FilterChip(
                    label: const Text('Purchases + Items'),
                    selected: _impPurchases,
                    onSelected: (v) => setState(() => _impPurchases = v),
                  ),
                  FilterChip(
                    label: const Text('Sales + Items'),
                    selected: _impSales,
                    onSelected: (v) => setState(() => _impSales = v),
                  ),
                  FilterChip(
                    label: const Text('Returns + Items'),
                    selected: _impReturns,
                    onSelected: (v) => setState(() => _impReturns = v),
                  ),
                  FilterChip(
                    label: const Text('Replacements + Items + Movements'),
                    selected: _impReplacements,
                    onSelected: (v) => setState(() => _impReplacements = v),
                  ),
                  FilterChip(
                    label: const Text('Item Requests + Items'),
                    selected: _impRequests,
                    onSelected: (v) => setState(() => _impRequests = v),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    'If a replacement number already exists:',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(width: 12),
                  DropdownButton<String>(
                    value: _repConflictStrategy,
                    onChanged: (v) =>
                        setState(() => _repConflictStrategy = v ?? 'skip'),
                    items: const [
                      DropdownMenuItem(
                        value: 'skip',
                        child: Text('Link to existing record (no new row)'),
                      ),
                      DropdownMenuItem(
                        value: 'suffix',
                        child: Text(
                          'Create new record with auto-suffix (e.g. -1, -2, ...)',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'When importing replacements, if a replacement number already exists in the database, choose whether to link to it or create a new one using an automatic -1, -2, ... suffix.',
                style: TextStyle(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.65),
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isImporting ? null : _importData,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.secondary,
                  foregroundColor: Theme.of(context).colorScheme.onSecondary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isImporting
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Theme.of(context).colorScheme.onSecondary,
                            ),
                          ),
                          SizedBox(width: 8),
                          Text('Importing...'),
                        ],
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.file_upload),
                          SizedBox(width: 8),
                          Text('Select JSON File'),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Note: Product, purchase, sale, and request IDs will be remapped automatically to maintain relationships.',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.6),
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportData() async {
    if (!ConnectivityService().isOnline.value) {
      if (mounted) {
        _showSnack('You are offline. Cannot export data.', success: false);
      }
      return;
    }
    setState(() => _isExporting = true);

    try {
      final ts = DateTime.now();
      final stamp =
          '${ts.year}-${ts.month.toString().padLeft(2, '0')}-${ts.day.toString().padLeft(2, '0')}_${ts.hour.toString().padLeft(2, '0')}-${ts.minute.toString().padLeft(2, '0')}-${ts.second.toString().padLeft(2, '0')}';

      if (_exportMode == ExportMode.catalogTemplate) {
        final data = await SupabaseService.exportCatalogTemplate();
        final dir = await _ensureDefaultBackupDir();
        final file = File(
          '${dir.path}${Platform.pathSeparator}catalog_template_$stamp.json',
        );
        await file.writeAsString(jsonEncode(data));

        setState(() {
          _exportPath = file.path;
          _message = 'Catalog Template exported successfully!';
          _isSuccess = true;
          _isExporting = false;
        });
        _showSnack('Catalog Template exported successfully!', success: true);
      } else if (_exportMode == ExportMode.businessInfo) {
        final data = await SupabaseService.exportBusinessInfo();
        final dir = await _ensureDefaultBackupDir();
        final file = File(
          '${dir.path}${Platform.pathSeparator}business_info_$stamp.json',
        );
        await file.writeAsString(jsonEncode(data));

        setState(() {
          _exportPath = file.path;
          _message = 'Business info exported successfully!';
          _isSuccess = true;
          _isExporting = false;
        });
        _showSnack('Business info exported successfully!', success: true);
      } else if (_exportMode == ExportMode.catalogWithBusiness) {
        final data = await SupabaseService.exportCatalogWithBusiness();
        final dir = await _ensureDefaultBackupDir();
        final file = File(
          '${dir.path}${Platform.pathSeparator}catalog_with_business_$stamp.json',
        );
        await file.writeAsString(jsonEncode(data));

        setState(() {
          _exportPath = file.path;
          _message = 'Catalog (with business) exported successfully!';
          _isSuccess = true;
          _isExporting = false;
        });
        _showSnack(
          'Catalog (with business) exported successfully!',
          success: true,
        );
      } else if (_exportMode == ExportMode.full) {
        final data = await SupabaseService.exportFullBackup();
        final dir = await _ensureDefaultBackupDir();
        final file = File(
          '${dir.path}${Platform.pathSeparator}full_backup_$stamp.json',
        );
        await file.writeAsString(jsonEncode(data));

        setState(() {
          _exportPath = file.path;
          _message = 'Full backup exported successfully!';
          _isSuccess = true;
          _isExporting = false;
        });
        _showSnack('Full backup exported successfully!', success: true);
      } else {
        setState(() {
          _message = 'Selected export mode is not implemented yet.';
          _isSuccess = false;
          _isExporting = false;
        });
        _showSnack(
          'Selected export mode is not implemented yet.',
          success: false,
        );
      }

      // Clear message after 5 seconds
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted) {
          setState(() => _message = null);
        }
      });
    } catch (e) {
      setState(() {
        _message = 'Export failed: $e';
        _isSuccess = false;
        _isExporting = false;
      });
      _showSnack('Export failed: $e', success: false);
    }
  }

  Future<void> _importData() async {
    if (!ConnectivityService().isOnline.value) {
      if (mounted) {
        _showSnack('You are offline. Cannot import data.', success: false);
      }
      return;
    }
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result != null) {
        setState(() => _isImporting = true);
        final filePath = result.files.single.path;
        if (filePath == null) throw Exception('No file path selected');
        final jsonString = await File(filePath).readAsString();
        final data = jsonDecode(jsonString) as Map<String, dynamic>;

        if (_importMode == ImportMode.catalogTemplate) {
          final inserted = await SupabaseService.importCatalogTemplate(
            data,
            conflictMode: 'insert_new',
          );
          setState(() {
            _message =
                'Imported $inserted products from template (${result.files.first.name}).';
            _isSuccess = true;
            _isImporting = false;
          });
          _showSnack(
            'Imported $inserted products from template.',
            success: true,
          );
        } else if (_importMode == ImportMode.businessInfo) {
          final ok = await SupabaseService.importBusinessInfo(data);
          setState(() {
            _message = ok
                ? 'Business info imported successfully.'
                : 'Business info import did not apply any changes.';
            _isSuccess = ok;
            _isImporting = false;
          });
          _showSnack(
            ok ? 'Business info imported successfully.' : 'No changes applied.',
            success: ok,
          );
        } else if (_importMode == ImportMode.catalogWithBusiness) {
          final res = await SupabaseService.importCatalogWithBusiness(
            data,
            conflictMode: 'merge_name_brand_spec',
            replaceImages: true,
          );
          final inserted = res['inserted'] ?? 0;
          final updated = res['updated'] ?? 0;
          setState(() {
            _message =
                'Catalog imported: Inserted $inserted, Updated $updated.';
            _isSuccess = true;
            _isImporting = false;
          });
          _showSnack(
            'Catalog imported: +$inserted, updated $updated',
            success: true,
          );
        } else if (_importMode == ImportMode.full) {
          if (_isDryRun) {
            // Run dry-run to preview counts
            final preview = await SupabaseService.importFullBackup(
              data,
              replaceImages: true,
              dryRun: true,
              importProducts: _impProducts,
              importPurchases: _impPurchases,
              importSales: _impSales,
              importReturns: _impReturns,
              importReplacements: _impReplacements,
              importItemRequests: _impRequests,
              replacementConflictStrategy: _repConflictStrategy,
            );
            setState(() => _isImporting = false);

            final confirmed = await _showImportPreviewDialog(
              preview,
              result.files.first.name,
            );

            if (confirmed == true) {
              setState(() => _isImporting = true);
              final res = await SupabaseService.importFullBackup(
                data,
                replaceImages: true,
                dryRun: false,
                importProducts: _impProducts,
                importPurchases: _impPurchases,
                importSales: _impSales,
                importReturns: _impReturns,
                importReplacements: _impReplacements,
                importItemRequests: _impRequests,
                replacementConflictStrategy: _repConflictStrategy,
              );
              final inserted = res['inserted_products'] ?? 0;
              final updated = res['updated_products'] ?? 0;
              final images = res['images_set'] ?? 0;
              final purchasesInserted = res['purchases_inserted'] ?? 0;
              final purchaseItemsInserted = res['purchase_items_inserted'] ?? 0;
              final salesInserted = res['sales_inserted'] ?? 0;
              final salesItemsInserted = res['sales_items_inserted'] ?? 0;
              final returnsInserted = res['returns_inserted'] ?? 0;
              final returnItemsInserted = res['return_items_inserted'] ?? 0;
              final replacementsInserted = res['replacements_inserted'] ?? 0;
              final repOut = res['replacement_items_out_inserted'] ?? 0;
              final repIn = res['replacement_items_in_inserted'] ?? 0;
              final repMoves = res['replacement_movements_inserted'] ?? 0;
              final itemRequestsInserted = res['item_requests_inserted'] ?? 0;
              final requestItemsInserted = res['request_items_inserted'] ?? 0;

              final lines = <String>[];
              if (_impProducts) {
                lines.add(
                  '• Products: +$inserted, updated $updated, images $images',
                );
              }
              if (_impPurchases) {
                lines.add(
                  '• Purchases: +$purchasesInserted, items +$purchaseItemsInserted',
                );
              }
              if (_impSales) {
                lines.add(
                  '• Sales: +$salesInserted, items +$salesItemsInserted',
                );
              }
              if (_impReturns) {
                lines.add(
                  '• Returns: +$returnsInserted, items +$returnItemsInserted',
                );
              }
              if (_impReplacements) {
                lines.add(
                  '• Replacements: +$replacementsInserted, out +$repOut, in +$repIn, moves +$repMoves',
                );
              }
              if (_impRequests) {
                lines.add('• Item requests: +$itemRequestsInserted');
                lines.add('• Request items: +$requestItemsInserted');
              }
              setState(() {
                _message = 'Full restore complete:\n${lines.join('\n')}';
                _isSuccess = true;
                _isImporting = false;
              });
              _showSnack('Full restore completed', success: true);
            } else {
              setState(() {
                _message = 'Dry run preview only. No changes applied.';
                _isSuccess = true;
                _isImporting = false;
              });
              _showSnack(
                'Dry run preview only. No changes applied.',
                success: true,
              );
            }
          } else {
            final res = await SupabaseService.importFullBackup(
              data,
              replaceImages: true,
            );
            final inserted = res['inserted_products'] ?? 0;
            final updated = res['updated_products'] ?? 0;
            final images = res['images_set'] ?? 0;
            final purchasesInserted = res['purchases_inserted'] ?? 0;
            final purchaseItemsInserted = res['purchase_items_inserted'] ?? 0;
            final salesInserted = res['sales_inserted'] ?? 0;
            final salesItemsInserted = res['sales_items_inserted'] ?? 0;
            final returnsInserted = res['returns_inserted'] ?? 0;
            final returnItemsInserted = res['return_items_inserted'] ?? 0;
            setState(() {
              _message =
                  'Restore complete:\n'
                  '• Products: +$inserted (updated $updated)\n'
                  '• Purchases: +$purchasesInserted ($purchaseItemsInserted items)\n'
                  '• Sales: +$salesInserted ($salesItemsInserted items)\n'
                  '• Returns: +$returnsInserted ($returnItemsInserted items)\n'
                  '• Images updated: $images';
              _isSuccess = true;
              _isImporting = false;
            });
            _showSnack('Restore completed successfully', success: true);
          }
        }

        // Clear message after 5 seconds
        Future.delayed(const Duration(seconds: 5), () {
          if (mounted) {
            setState(() => _message = null);
          }
        });
      }
    } catch (e) {
      setState(() {
        _message = 'Import failed: $e';
        _isSuccess = false;
        _isImporting = false;
      });
      _showSnack('Import failed: $e', success: false);
    }
  }

  Future<void> _deleteAllData() async {
    if (!ConnectivityService().isOnline.value) {
      if (mounted) {
        _showSnack('You are offline. Cannot delete data.', success: false);
      }
      return;
    }
    setState(() => _isDeleting = true);

    try {
      // Show confirmation dialog
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('⚠️ Final Confirmation'),
          content: const Text(
            'This will permanently delete ALL your business data including:\n\n'
            '• All products and inventory\n'
            '• All sales records\n'
            '• All purchase records\n'
            '• All customer data\n'
            '• All business settings\n\n'
            'This action CANNOT be undone. Are you absolutely sure?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              child: const Text('Yes, Delete Everything'),
            ),
          ],
        ),
      );

      if (confirmed == true) {
        // Perform actual deletion via SupabaseService
        final ok = await SupabaseService.deleteBusinessData();
        if (ok) {
          setState(() {
            _message = 'All business data has been permanently deleted.';
            _isSuccess = true;
            _isDeleting = false;
            _confirmText = '';
          });
          _showSnack('All business data deleted.', success: true);

          // Navigate back to dashboard after showing message
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted) {
              Navigator.of(context).pop();
            }
          });
        } else {
          setState(() {
            _message = 'Deletion failed. Please try again.';
            _isSuccess = false;
            _isDeleting = false;
          });
          _showSnack('Deletion failed. Please try again.', success: false);
        }
      } else {
        setState(() => _isDeleting = false);
      }
    } catch (e) {
      setState(() {
        _message = 'Deletion failed: $e';
        _isSuccess = false;
        _isDeleting = false;
      });
      _showSnack('Deletion failed: $e', success: false);
    }
  }
}
