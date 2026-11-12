import 'dart:async';
import 'package:flutter/material.dart';
import '../widgets/page_header.dart';
import '../services/supabase_service.dart';
import '../models/sales_purchase_models.dart' as models;

class SystemHealthPage extends StatefulWidget {
  const SystemHealthPage({super.key});

  @override
  State<SystemHealthPage> createState() => _SystemHealthPageState();
}

class _SystemHealthPageState extends State<SystemHealthPage>
    with TickerProviderStateMixin {
  bool _isLoading = true;
  String _loadingAction = '';
  String? _successMessage;
  String? _errorMessage;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  Timer? _autoRefreshTimer;
  List<Map<String, dynamic>> _stockRecon = [];
  bool _stockReconLoading = false;
  bool _stockReconApplying = false;
  bool _stockReconAllMismatches = false;

  // Real health check data
  Map<String, dynamic> _healthCheck = {
    'productsWithoutPurchases': <Map<String, dynamic>>[],
    'negativeStock': <Map<String, dynamic>>[],
    'incompleteProducts': <Map<String, dynamic>>[],
    'duplicateProducts': <Map<String, dynamic>>[],
    'suspiciousSales': <Map<String, dynamic>>[],
    'invalidPurchases': <Map<String, dynamic>>[],
    'recentProductsWithStock': <Map<String, dynamic>>[],
    'orphanedReturns': <Map<String, dynamic>>[],
    'orphanedReplacements': <Map<String, dynamic>>[],
    'invalidReturnItems': <Map<String, dynamic>>[],
    'invalidReplacementItemsOut': <Map<String, dynamic>>[],
    'invalidReplacementItemsIn': <Map<String, dynamic>>[],
    'problematicReturns': <Map<String, dynamic>>[],
    'duplicateSummary': <String, dynamic>{},
  };
  bool _dupWorking = false;
  Map<String, dynamic>? _dupPreview;
  bool _fixDupProducts = true;
  bool _fixDupPurchases = true;
  bool _fixDupReturns = true;
  bool _fixDupReplacements = true;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
    _loadHealthData(showSkeleton: true);
  }

  Future<void> _runStockReconPreview() async {
    setState(() {
      _stockReconLoading = true;
    });
    try {
      final rows = await SupabaseService.healthStockReconcilePreview(
        includeAllMismatches: _stockReconAllMismatches,
      );
      setState(() {
        _stockRecon = rows;
        _stockReconLoading = false;
      });
    } catch (e) {
      setState(() {
        _stockReconLoading = false;
        _errorMessage = 'Failed to load reconciliation preview: $e';
      });
    }
  }

  Future<void> _applyStockRecon() async {
    setState(() {
      _stockReconApplying = true;
      _successMessage = null;
      _errorMessage = null;
    });
    try {
      final count = await SupabaseService.healthStockReconcileApply(
        onlyZeroToExpected: !_stockReconAllMismatches,
      );
      setState(() {
        _stockReconApplying = false;
        _successMessage = 'Updated $count products';
      });
      await _runStockReconPreview();
      await _loadHealthData();
    } catch (e) {
      setState(() {
        _stockReconApplying = false;
        _errorMessage = 'Failed to apply reconciliation: $e';
      });
    }
  }

  Widget _buildProblematicPurchasesCard() {
    final invalidPurchases = _healthCheck['invalidPurchases'] as List;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isWide = MediaQuery.of(context).size.width > 768;
    final double listHeight = isWide ? 180.0 : 220.0;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border.all(
          color: isDark
              ? Theme.of(context).colorScheme.outline.withValues(alpha: 0.3)
              : Colors.grey.shade200,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.3)
                : Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.amber.shade900.withValues(alpha: 0.3)
                      : Colors.amber.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.receipt_long,
                  color: isDark ? Colors.amber.shade400 : Colors.amber.shade700,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Problematic Purchases',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      'Missing supplier/items or invalid values',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: invalidPurchases.isNotEmpty
                      ? (isDark
                            ? Colors.amber.shade900.withValues(alpha: 0.2)
                            : Colors.amber.shade100)
                      : (isDark
                            ? Colors.green.shade900.withValues(alpha: 0.2)
                            : Colors.green.shade100),
                  border: Border.all(
                    color: invalidPurchases.isNotEmpty
                        ? (isDark
                              ? Colors.amber.shade700
                              : Colors.amber.shade300)
                        : (isDark
                              ? Colors.green.shade700
                              : Colors.green.shade300),
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  invalidPurchases.isNotEmpty
                      ? '${invalidPurchases.length} Issues'
                      : '✅ All Good',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: invalidPurchases.isNotEmpty
                        ? (isDark
                              ? Colors.amber.shade300
                              : Colors.amber.shade700)
                        : (isDark
                              ? Colors.green.shade300
                              : Colors.green.shade700),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (invalidPurchases.isNotEmpty) ...[
            SizedBox(
              height: listHeight,
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(
                  context,
                ).copyWith(scrollbars: false),
                child: ListView.builder(
                  primary: false,
                  padding: EdgeInsets.zero,
                  itemCount: invalidPurchases.length,
                  physics: const ClampingScrollPhysics(),
                  itemBuilder: (context, index) {
                    final row = invalidPurchases[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.amber.shade900.withValues(alpha: 0.2)
                            : Colors.amber.shade50,
                        border: Border(
                          left: BorderSide(
                            color: Colors.amber.shade400,
                            width: 4,
                          ),
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Purchase ID: \\#${row['id'] ?? 'unknown'}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  row['reason'] ?? 'Unknown issue',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark
                                        ? Colors.amber.shade300
                                        : Colors.amber.shade800,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                if (row['created_at'] != null)
                                  Text(
                                    _formatDate(row['created_at'] as String?),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withValues(alpha: 0.6),
                                    ),
                                  ),
                                const SizedBox(height: 8),
                                if ((row['reason'] as String?)
                                        ?.toLowerCase()
                                        .contains('no purchase items') ==
                                    true)
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: ElevatedButton.icon(
                                      onPressed: _isLoading
                                          ? null
                                          : () => _handleAction(
                                              'delete-empty-purchase-${row['id']}',
                                            ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.red.shade600,
                                        foregroundColor: Colors.white,
                                        minimumSize: const Size(0, 36),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 8,
                                        ),
                                      ),
                                      icon: const Icon(Icons.delete, size: 16),
                                      label: const Text('Delete Purchase'),
                                    ),
                                  ),
                                if ((row['reason'] as String?)
                                        ?.toLowerCase()
                                        .contains(
                                          'duplicate purchase (composite match)',
                                        ) ==
                                    true)
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: ElevatedButton.icon(
                                      onPressed: _isLoading
                                          ? null
                                          : () => _handleAction(
                                              'delete-duplicate-purchase-${row['id']}',
                                            ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.red.shade700,
                                        foregroundColor: Colors.white,
                                        minimumSize: const Size(0, 36),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 8,
                                        ),
                                      ),
                                      icon: const Icon(
                                        Icons.delete_forever,
                                        size: 16,
                                      ),
                                      label: const Text('Delete Duplicate'),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ] else
            Center(
              child: Column(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.green.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.check_circle,
                      color: Colors.green.shade600,
                      size: 24,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No problematic purchases found.',
                    style: TextStyle(
                      color: Colors.green.shade600,
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFullPageSkeleton(bool isDesktop) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? Colors.grey.shade800 : Colors.grey.shade200;

    Widget headerSkeleton() => Padding(
      padding: EdgeInsets.all(isDesktop ? 32 : 16),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isDark
                ? Theme.of(context).colorScheme.outline.withValues(alpha: 0.3)
                : const Color(0xFFE2E8F0),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 28,
              width: 260,
              decoration: BoxDecoration(
                color: base,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              height: 16,
              width: 360,
              decoration: BoxDecoration(
                color: base,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: List.generate(
                2,
                (i) => Container(
                  height: 40,
                  width: 140,
                  decoration: BoxDecoration(
                    color: base,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        headerSkeleton(),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: isDesktop ? 32 : 16),
          child: Column(
            children: [
              // Health score section skeleton
              _buildGenericSectionSkeleton(
                isDark,
                base,
                height: 180,
                radius: 24,
              ),
              const SizedBox(height: 32),
              // Critical issues skeleton
              _buildGenericSectionSkeleton(isDark, base, height: 160),
              const SizedBox(height: 32),
              // Duplicates section skeleton (use dedicated one for fidelity)
              _buildDuplicateSectionSkeleton(),
              const SizedBox(height: 32),
              // Other checks grid skeleton
              GridView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: isDesktop ? 4 : 2,
                  mainAxisExtent: 84,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                ),
                children: List.generate(
                  isDesktop ? 4 : 4,
                  (i) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark
                            ? Theme.of(
                                context,
                              ).colorScheme.outline.withValues(alpha: 0.3)
                            : Colors.grey.shade200,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          height: 20,
                          width: 60,
                          decoration: BoxDecoration(
                            color: base,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          height: 12,
                          width: 100,
                          decoration: BoxDecoration(
                            color: base,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGenericSectionSkeleton(
    bool isDark,
    Color base, {
    double height = 160,
    double radius = 16,
  }) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border.all(
          color: isDark
              ? Theme.of(context).colorScheme.outline.withValues(alpha: 0.3)
              : Colors.grey.shade200,
        ),
        borderRadius: BorderRadius.circular(radius),
      ),
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: base,
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  height: 22,
                  width: 240,
                  decoration: BoxDecoration(
                    color: base,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  height: 16,
                  width: 360,
                  decoration: BoxDecoration(
                    color: base,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chipToggle(
    String label,
    bool selected,
    ValueChanged<bool> onChanged,
  ) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: onChanged,
    );
  }

  Future<void> _runDuplicateDryRun() async {
    setState(() {
      _dupWorking = true;
    });
    try {
      final res = await SupabaseService.healthFixDuplicates(
        fixProducts: _fixDupProducts,
        fixPurchases: _fixDupPurchases,
        fixReturns: _fixDupReturns,
        fixReplacements: _fixDupReplacements,
        dryRun: true,
      );
      setState(() {
        _dupPreview = res;
        _dupWorking = false;
      });
      await _showDupPreviewDialog(res);
    } catch (e) {
      setState(() {
        _dupWorking = false;
        _errorMessage = 'Dry run failed: $e';
      });
    }
  }

  Future<void> _applyDuplicateFix() async {
    setState(() {
      _dupWorking = true;
    });
    try {
      final res = await SupabaseService.healthFixDuplicates(
        fixProducts: _fixDupProducts,
        fixPurchases: _fixDupPurchases,
        fixReturns: _fixDupReturns,
        fixReplacements: _fixDupReplacements,
        dryRun: false,
      );
      setState(() {
        _dupWorking = false;
        _successMessage =
            'Merged products: ${res['products_merged']}, purchases: ${res['purchases_merged']}, returns: ${res['returns_merged']}, replacements: ${res['replacements_merged']}';
      });
      await _loadHealthData();
    } catch (e) {
      setState(() {
        _dupWorking = false;
        _errorMessage = 'Apply failed: $e';
      });
    }
  }

  Future<void> _showDupPreviewDialog(Map<String, dynamic> res) async {
    final details = Map<String, dynamic>.from(
      res['details'] as Map? ?? const <String, dynamic>{},
    );
    String sectionLine(String k, String label) {
      final g = Map<String, dynamic>.from(details[k] as Map? ?? const {});
      final c = (g['count'] as int?) ?? 0;
      return '$label: $c';
    }

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Duplicate fix preview'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(sectionLine('products', 'Products merged')),
            Text(sectionLine('purchases', 'Purchases merged')),
            Text(sectionLine('returns', 'Returns merged')),
            Text(sectionLine('replacements', 'Replacements merged')),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadHealthData({bool showSkeleton = false}) async {
    try {
      if (showSkeleton) {
        setState(() {
          _isLoading = true;
          _errorMessage = null;
        });
      }

      final healthData = await _performHealthChecks();

      if (!mounted) return;
      setState(() {
        _healthCheck = healthData;
        _isLoading = false;
      });

      _animationController.forward();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load health data: $e';
      });
    }
  }

  Future<Map<String, dynamic>> _performHealthChecks() async {
    final supabaseService = SupabaseService();

    // 1. Products with negative stock
    final negativeStockProducts = await supabaseService
        .getProductsWithNegativeStock();

    // 2. Products with missing essential data
    final incompleteProducts = await supabaseService.getIncompleteProducts();

    // 3. Products with stock but no purchase history
    final productsWithoutPurchases = await _getProductsWithoutPurchases();

    // 4. Duplicate products
    final duplicateProducts = await _findDuplicateProducts();

    // 5. Suspicious sales (quantities exceeding available stock)
    final suspiciousSales = await _getSuspiciousSales();

    // 6. Invalid purchases
    final invalidPurchases = await _getInvalidPurchases();

    // 7. Recent products created with stock
    final recentProductsWithStock = await _getRecentProductsWithStock();

    // 8. Return/Replace integrity checks
    final returnIntegrityIssues = await _getReturnIntegrityIssues();

    // 9. Duplicates across entities
    final duplicateSummary = await SupabaseService.healthDetectDuplicates();

    return {
      'negativeStock': negativeStockProducts
          .map(
            (p) => {
              'id': p.id,
              'name': p.name,
              'brand': p.brand,
              'current_stock': p.currentStock,
              'unit_type_single': p.unitTypeSingle,
            },
          )
          .toList(),
      'incompleteProducts': incompleteProducts
          .map(
            (p) => {
              'id': p.id,
              'name': p.name,
              'brand': p.brand,
              'unit_type_single': p.unitTypeSingle,
            },
          )
          .toList(),
      'productsWithoutPurchases': productsWithoutPurchases,
      'duplicateProducts': duplicateProducts,
      'suspiciousSales': suspiciousSales,
      'invalidPurchases': invalidPurchases,
      'recentProductsWithStock': recentProductsWithStock,
      ...returnIntegrityIssues,
      'duplicateSummary': duplicateSummary,
    };
  }

  Future<List<Map<String, dynamic>>> _getProductsWithoutPurchases() async {
    final supabaseService = SupabaseService();

    final productsWithStock = await supabaseService.getProductsWithStock();
    final productsWithoutPurchases = <Map<String, dynamic>>[];

    // Check each product for purchase history
    for (final product in productsWithStock) {
      final productId = product.id;
      if (productId != null) {
        final hasPurchases = await supabaseService.productHasPurchaseHistory(
          productId,
        );
        if (!hasPurchases) {
          productsWithoutPurchases.add({
            'id': productId,
            'name': product.name,
            'brand': product.brand,
            'current_stock': product.currentStock,
            'unit_type_single': product.unitTypeSingle,
          });
        }
      }
    }

    return productsWithoutPurchases;
  }

  Future<List<Map<String, dynamic>>> _findDuplicateProducts() async {
    final supabaseService = SupabaseService();
    // Include archived/deleted so we can detect and surface stale duplicates too
    final allProducts = await supabaseService
        .getAllProductsIncludingDeletedArchived();

    // Group by normalized composite key
    final Map<String, List<dynamic>> groups = {};
    for (final p in allProducts) {
      final id = p.id;
      if (id == null) continue;
      final key =
          '${(p.name).toString().trim().toLowerCase()}-'
          '${(p.category ?? '').toString().trim().toLowerCase()}-'
          '${(p.brand ?? '').toString().trim().toLowerCase()}';
      groups.putIfAbsent(key, () => []).add(p);
    }

    int statusScore(String? status) {
      switch ((status ?? '').toLowerCase()) {
        case 'active':
          return 3;
        case 'archived':
          return 2;
        case 'deleted':
          return 1;
        default:
          return 0;
      }
    }

    final duplicates = <Map<String, dynamic>>[];
    for (final entry in groups.entries) {
      final list = entry.value;
      if (list.length <= 1) continue;

      // Choose a canonical record to keep: prefer active, then earliest created
      list.sort((a, b) {
        final as = statusScore(a.status);
        final bs = statusScore(b.status);
        if (bs != as) return bs.compareTo(as); // higher score first
        final at = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bt = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return at.compareTo(bt); // earlier first
      });
      final canonical = list.first;

      for (int i = 1; i < list.length; i++) {
        final d = list[i];
        if (d.id == null) continue;
        duplicates.add({
          'id': d.id,
          'name': d.name,
          'category': d.category,
          'brand': d.brand,
          'current_stock': d.currentStock,
          'duplicate_of': canonical.id,
          'is_duplicate': true,
          'status': d.status,
        });
      }
    }

    return duplicates;
  }

  Future<List<Map<String, dynamic>>> _getSuspiciousSales() async {
    // This would require complex queries - simplified for now
    return <Map<String, dynamic>>[];
  }

  Future<List<Map<String, dynamic>>> _getInvalidPurchases() async {
    final purchases = await SupabaseService.getPurchases();
    final List<Map<String, dynamic>> invalid = [];

    for (final p in purchases) {
      final supplier = (p.supplierName ?? '').trim();
      if (supplier.isEmpty) {
        invalid.add({
          'id': p.id,
          'reason': 'Missing supplier name',
          'created_at': (p.createdAt ?? p.purchaseDate)?.toIso8601String(),
        });
        continue;
      }

      final List<models.PurchaseItem> items;
      try {
        items = p.purchaseItems;
      } catch (_) {
        // Legacy or parse failure
        invalid.add({
          'id': p.id,
          'reason': 'No items (legacy)',
          'created_at': (p.createdAt ?? p.purchaseDate)?.toIso8601String(),
        });
        continue;
      }

      if (items.isEmpty) {
        invalid.add({
          'id': p.id,
          'reason': 'No purchase items',
          'created_at': (p.createdAt ?? p.purchaseDate)?.toIso8601String(),
        });
        continue;
      }

      bool badItem = false;
      for (final it in items) {
        if (it.product == null || it.quantity <= 0 || it.pricePerUnit <= 0) {
          badItem = true;
          break;
        }
      }
      if (badItem) {
        invalid.add({
          'id': p.id,
          'reason': 'Invalid item data',
          'created_at': (p.createdAt ?? p.purchaseDate)?.toIso8601String(),
        });
      }
    }

    // Duplicate detection: group by composite key
    String dtKey(DateTime? dt) {
      if (dt == null) return 'unknown';
      // Round to minute precision to avoid tiny drifts
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}T'
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }

    String sigFor(models.Purchase p) {
      final dt = dtKey(p.createdAt ?? p.purchaseDate);
      final supplier = (p.supplierName ?? '').trim().toLowerCase();
      final total = (p.totalAmount).toStringAsFixed(2);
      final items = <String>[];
      try {
        for (final it in p.purchaseItems) {
          final name = (it.product?.name ?? '').trim().toLowerCase();
          final brand = (it.product?.brand ?? '').trim().toLowerCase();
          final unit = (it.unit ?? '').trim().toLowerCase();
          final qty = it.quantity;
          final price = it.pricePerUnit.toStringAsFixed(2);
          items.add('$name|$brand|$unit|$qty|$price');
        }
      } catch (_) {
        // if items inaccessible, keep empty which will reduce false positives
      }
      items.sort();
      final itemsSig = items.join('|');
      return '$dt|$supplier|$total|$itemsSig';
    }

    final Map<String, List<models.Purchase>> groups = {};
    for (final p in purchases) {
      final k = sigFor(p);
      groups.putIfAbsent(k, () => <models.Purchase>[]).add(p);
    }

    for (final entry in groups.entries) {
      final list = entry.value;
      if (list.length <= 1) continue;
      // Keep the earliest id as canonical, mark others as duplicates
      list.sort((a, b) => (a.id ?? 1 << 30).compareTo(b.id ?? 1 << 30));
      final keep = list.first;
      for (int i = 1; i < list.length; i++) {
        final dup = list[i];
        invalid.add({
          'id': dup.id,
          'reason': 'Duplicate purchase (composite match) of #${keep.id}',
          'created_at': (dup.createdAt ?? dup.purchaseDate)?.toIso8601String(),
        });
      }
    }

    return invalid;
  }

  Future<List<Map<String, dynamic>>> _getRecentProductsWithStock() async {
    final supabaseService = SupabaseService();
    final yesterday = DateTime.now().subtract(const Duration(days: 1));

    final recentProducts = await supabaseService.getProductsCreatedAfter(
      yesterday,
    );
    return recentProducts
        .where((p) => p.currentStock > 0)
        .map(
          (p) => {
            'id': p.id,
            'name': p.name,
            'brand': p.brand,
            'current_stock': p.currentStock,
            'created_at': p.createdAt?.toIso8601String(),
          },
        )
        .toList();
  }

  Future<Map<String, dynamic>> _getReturnIntegrityIssues() async {
    // Simplified return integrity checks
    return {
      'orphanedReturns': <Map<String, dynamic>>[],
      'orphanedReplacements': <Map<String, dynamic>>[],
      'invalidReturnItems': <Map<String, dynamic>>[],
      'invalidReplacementItemsOut': <Map<String, dynamic>>[],
      'invalidReplacementItemsIn': <Map<String, dynamic>>[],
      'problematicReturns': <Map<String, dynamic>>[],
    };
  }

  @override
  void dispose() {
    _animationController.dispose();
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  // Calculate health metrics
  int _dupSummaryCount() {
    final dup = Map<String, dynamic>.from(
      _healthCheck['duplicateSummary'] as Map? ?? const {},
    );
    int c(String k) => (dup[k]?['count'] as int?) ?? 0;
    return c('products') + c('purchases') + c('returns') + c('replacements');
  }

  int get _totalIssues {
    return (_healthCheck['productsWithoutPurchases'] as List).length +
        (_healthCheck['negativeStock'] as List).length +
        (_healthCheck['incompleteProducts'] as List).length +
        (_healthCheck['invalidPurchases'] as List).length +
        (_healthCheck['duplicateProducts'] as List).length +
        _dupSummaryCount();
  }

  int get _healthScore {
    return _totalIssues == 0 ? 100 : (100 - (_totalIssues * 5)).clamp(0, 100);
  }

  String get _healthStatus {
    if (_healthScore >= 90) return 'excellent';
    if (_healthScore >= 70) return 'good';
    if (_healthScore >= 50) return 'warning';
    return 'critical';
  }

  MaterialColor get _healthStatusColor {
    switch (_healthStatus) {
      case 'excellent':
        return Colors.green;
      case 'good':
        return Colors.blue;
      case 'warning':
        return Colors.orange;
      default:
        return Colors.red;
    }
  }

  String get _healthStatusText {
    switch (_healthStatus) {
      case 'excellent':
        return '✅ Excellent';
      case 'good':
        return '🟢 Good';
      case 'warning':
        return '⚠️ Warning';
      default:
        return '🚨 Critical';
    }
  }

  String _formatDate(String? dateString) {
    if (dateString == null) return 'Unknown date';
    try {
      final date = DateTime.parse(dateString);
      return '${date.day}/${date.month}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return 'Invalid date';
    }
  }

  Future<void> _handleAction(String action, {int? productId}) async {
    setState(() {
      _loadingAction = action;
      _successMessage = null;
      _errorMessage = null;
    });

    try {
      final supabaseService = SupabaseService();
      String message = '';

      // Handle duplicate removal actions like 'duplicate-<id>'
      if (action.startsWith('duplicate-')) {
        if (productId != null) {
          final success = await supabaseService.deleteProductSafely(productId);
          message = success
              ? 'Duplicate product removed successfully'
              : 'Failed to remove duplicate product';
        } else {
          message = 'Invalid product selected';
        }

        setState(() {
          _loadingAction = '';
          _successMessage = message;
        });

        // Reload health data after successful action
        await _loadHealthData(showSkeleton: false);

        // Clear messages after 3 seconds
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            setState(() {
              _successMessage = null;
              _errorMessage = null;
            });
          }
        });
        return;
      }

      // Handle deleting duplicate purchase safely (with stock rollback)
      if (action.startsWith('delete-duplicate-purchase-')) {
        final idStr = action.replaceFirst('delete-duplicate-purchase-', '');
        final pid = int.tryParse(idStr);
        if (pid != null) {
          final ok = await SupabaseService.deletePurchaseSafely(pid);
          message = ok
              ? 'Deleted duplicate purchase #$pid'
              : 'Failed to delete duplicate purchase #$pid';
        } else {
          message = 'Invalid purchase id';
        }

        setState(() {
          _loadingAction = '';
          _successMessage = message;
        });

        await _loadHealthData(showSkeleton: false);
        // Clear messages after 3 seconds
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            setState(() {
              _successMessage = null;
              _errorMessage = null;
            });
          }
        });
        return;
      }

      // Handle deleting empty purchase headers
      if (action.startsWith('delete-empty-purchase-')) {
        final idStr = action.replaceFirst('delete-empty-purchase-', '');
        final pid = int.tryParse(idStr);
        if (pid != null) {
          final ok = await SupabaseService.deleteEmptyPurchase(pid);
          message = ok
              ? 'Deleted empty purchase #$pid'
              : 'Cannot delete purchase #$pid (it has items)';
        } else {
          message = 'Invalid purchase id';
        }

        setState(() {
          _loadingAction = '';
          _successMessage = message;
        });

        await _loadHealthData(showSkeleton: false);
        // Clear messages after 3 seconds
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            setState(() {
              _successMessage = null;
              _errorMessage = null;
            });
          }
        });
        return;
      }

      switch (action) {
        case 'correct-stock':
          if (productId != null) {
            final success = await supabaseService.correctProductStock(
              productId,
            );
            message = success
                ? 'Stock corrected successfully'
                : 'Failed to correct stock';
          }
          break;
        case 'delete-product':
          if (productId != null) {
            final success = await supabaseService.deleteProductSafely(
              productId,
            );
            message = success
                ? 'Product processed successfully'
                : 'Failed to process product';
          }
          break;
        case 'reset-all-suspicious':
          final resetCount = await supabaseService.resetAllSuspiciousStock();
          message = 'Reset $resetCount products with suspicious stock';
          break;
        case 'fix-all-negative':
          final fixedCount = await supabaseService.fixAllNegativeStock();
          message = 'Fixed $fixedCount products with negative stock';
          break;
        default:
          message = 'Action completed successfully';
      }

      setState(() {
        _loadingAction = '';
        _successMessage = message;
      });

      // Reload health data after successful action
      await _loadHealthData(showSkeleton: false);
    } catch (e) {
      setState(() {
        _loadingAction = '';
        _errorMessage = 'Action failed: $e';
      });
    }

    // Clear messages after 3 seconds
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _successMessage = null;
          _errorMessage = null;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 768;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).scaffoldBackgroundColor,
              Theme.of(context).colorScheme.surface,
            ],
          ),
        ),
        child: SafeArea(
          top: false,
          bottom: true,
          child: _isLoading
              ? SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: _buildFullPageSkeleton(isDesktop),
                )
              : RefreshIndicator(
                  onRefresh: _loadHealthData,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: Column(
                      children: [
                        // Page Header
                        PageHeader(
                          title: 'System Health Monitor',
                          description:
                              'Monitor and maintain data integrity across your inventory system',
                          icon: '🔍',
                          showBackButton: true,
                          wrapInSafeArea: true,
                          breadcrumbs: [
                            PageHeaderBreadcrumb(label: 'Dashboard', icon: '🏠', href: '/'),
                            if (MediaQuery.of(context).size.width >= 450)
                              PageHeaderBreadcrumb(
                                label: 'System Health',
                                icon: '🔍',
                                current: true,
                              ),
                          ],
                          stats: [
                            PageHeaderStat(
                              label: 'Health Score',
                              value: '$_healthScore%',
                              description:
                                  'System health score based on $_totalIssues total issues found',
                            ),
                            PageHeaderStat(
                              label: 'Total Issues',
                              value: '$_totalIssues',
                              description:
                                  '$_totalIssues issues found across all categories',
                            ),
                          ],
                          actions: [
                            PageHeaderAction(
                              icon: Icons.inventory_2_outlined,
                              label: 'View Inventory',
                              shortLabel: 'Inventory',
                              color: Theme.of(context).colorScheme.primary,
                              onPressed: () =>
                                  Navigator.pushNamed(context, '/inventory'),
                            ),
                            PageHeaderAction(
                              icon: Icons.add_circle_outline,
                              label: 'Add Product',
                              shortLabel: 'Add',
                              color: Theme.of(context).colorScheme.tertiary,
                              onPressed: () =>
                                  Navigator.pushNamed(context, '/add-product'),
                            ),
                          ],
                        ),

                        // Content
                        Padding(
                          padding: EdgeInsets.all(isDesktop ? 32 : 16),
                          child: FadeTransition(
                            opacity: _fadeAnimation,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Success/Error Messages
                                if (_successMessage != null) ...[
                                  _buildSuccessMessage(),
                                  const SizedBox(height: 24),
                                ],
                                if (_errorMessage != null) ...[
                                  _buildErrorMessage(),
                                  const SizedBox(height: 24),
                                ],

                                // Health Score Hero Section
                                _buildHealthScoreSection(isDesktop),
                                const SizedBox(height: 32),

                                // Critical Data Integrity Issues
                                _buildCriticalIssuesSection(isDesktop),
                                const SizedBox(height: 32),

                                // Duplicates detection and fixes
                                _buildDuplicatesSection(isDesktop),
                                const SizedBox(height: 32),

                                // Other Health Checks Grid
                                _buildHealthChecksGrid(isDesktop),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildSuccessMessage() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.green.shade900.withValues(alpha: 0.2)
            : Colors.green.shade50,
        border: Border.all(
          color: isDark ? Colors.green.shade700 : Colors.green.shade200,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.green.shade800.withValues(alpha: 0.3)
                  : Colors.green.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.check_circle,
              color: isDark ? Colors.green.shade400 : Colors.green.shade600,
              size: 20,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Operation Successful',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? Colors.green.shade300
                        : Colors.green.shade700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _successMessage!,
                  style: TextStyle(
                    color: isDark
                        ? Colors.green.shade400
                        : Colors.green.shade600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorMessage() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.red.shade900.withValues(alpha: 0.2)
            : Colors.red.shade50,
        border: Border.all(
          color: isDark ? Colors.red.shade700 : Colors.red.shade200,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.red.shade800.withValues(alpha: 0.3)
                  : Colors.red.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.error,
              color: isDark ? Colors.red.shade400 : Colors.red.shade600,
              size: 20,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Operation Failed',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.red.shade300 : Colors.red.shade700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _errorMessage!,
                  style: TextStyle(
                    color: isDark ? Colors.red.shade400 : Colors.red.shade600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHealthScoreSection(bool isDesktop) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark
              ? Theme.of(context).colorScheme.outline.withValues(alpha: 0.3)
              : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.3)
                : Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: isDesktop
          ? Row(
              children: [
                _buildHealthScoreVisualization(),
                const SizedBox(width: 48),
                Expanded(child: _buildHealthMetrics()),
              ],
            )
          : Column(
              children: [
                _buildHealthScoreVisualization(),
                const SizedBox(height: 32),
                _buildHealthMetrics(),
              ],
            ),
    );
  }

  Widget _buildHealthScoreVisualization() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        SizedBox(
          width: 120,
          height: 120,
          child: Stack(
            children: [
              // Background circle
              SizedBox(
                width: 120,
                height: 120,
                child: CircularProgressIndicator(
                  value: 1.0,
                  strokeWidth: 8,
                  backgroundColor: isDark
                      ? Colors.grey.shade700
                      : Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation(
                    isDark ? Colors.grey.shade700 : Colors.grey.shade200,
                  ),
                ),
              ),
              // Progress circle
              SizedBox(
                width: 120,
                height: 120,
                child: CircularProgressIndicator(
                  value: _healthScore / 100,
                  strokeWidth: 8,
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation(_healthStatusColor),
                ),
              ),
              // Center text
              Center(
                child: Text(
                  '$_healthScore%',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'System Health Score',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Status: ',
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: _healthStatusColor.withValues(alpha: 0.1),
                border: Border.all(
                  color: _healthStatusColor.withValues(alpha: 0.3),
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _healthStatusText,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: isDark
                      ? _healthStatusColor.shade300
                      : _healthStatusColor.shade700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Based on data integrity, stock consistency, and system rule compliance',
          style: TextStyle(
            fontSize: 14,
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.6),
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildHealthMetrics() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 480;
        final cross = compact ? 1 : 2;
        final aspect = compact ? 3.0 : 2.2;
        return GridView.count(
          crossAxisCount: cross,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: aspect,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          children: [
            _buildMetricCard('Total Issues', '$_totalIssues', Colors.red),
            _buildMetricCard(
              'Critical Items',
              '${(_healthCheck['productsWithoutPurchases'] as List).length}',
              Colors.orange,
            ),
            _buildMetricCard(
              'Stock Issues',
              '${(_healthCheck['negativeStock'] as List).length}',
              Colors.blue,
            ),
            _buildMetricCard('Duplicates', _formatDupTotal(), Colors.green),
          ],
        );
      },
    );
  }

  String _formatDupTotal() {
    final dup = Map<String, dynamic>.from(
      _healthCheck['duplicateSummary'] as Map? ?? const {},
    );
    final p = (dup['products']?['count'] as int?) ?? 0;
    final pu = (dup['purchases']?['count'] as int?) ?? 0;
    final r = (dup['returns']?['count'] as int?) ?? 0;
    final rp = (dup['replacements']?['count'] as int?) ?? 0;
    return '${p + pu + r + rp}';
  }

  Widget _buildDuplicatesSection(bool isDesktop) {
    final dup = Map<String, dynamic>.from(
      _healthCheck['duplicateSummary'] as Map? ?? const {},
    );
    int countOf(String k) => (dup[k]?['count'] as int?) ?? 0;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_isLoading) {
      return _buildDuplicateSectionSkeleton();
    }

    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border.all(
          color: isDark
              ? Theme.of(context).colorScheme.outline.withValues(alpha: 0.3)
              : Colors.grey.shade200,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.3)
                : Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer
                      .withValues(alpha: isDark ? 0.25 : 0.6),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  Icons.copy_all_rounded,
                  color: Theme.of(context).colorScheme.primary,
                  size: 28,
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Duplicate Records',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.primary.withValues(alpha: 0.08),
                            border: Border.all(
                              color: Theme.of(
                                context,
                              ).colorScheme.primary.withValues(alpha: 0.3),
                            ),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'Total: ${_formatDupTotal()}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Detect and fix duplicate products, purchases, returns and replacements',
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _chipToggle(
                'Products (${countOf('products')})',
                _fixDupProducts,
                (v) => setState(() => _fixDupProducts = v),
              ),
              _chipToggle(
                'Purchases (${countOf('purchases')})',
                _fixDupPurchases,
                (v) => setState(() => _fixDupPurchases = v),
              ),
              _chipToggle(
                'Returns (${countOf('returns')})',
                _fixDupReturns,
                (v) => setState(() => _fixDupReturns = v),
              ),
              _chipToggle(
                'Replacements (${countOf('replacements')})',
                _fixDupReplacements,
                (v) => setState(() => _fixDupReplacements = v),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: _dupWorking ? null : _runDuplicateDryRun,
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('Dry run'),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _dupWorking ? null : _applyDuplicateFix,
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Apply fixes'),
              ),
              if (_dupWorking) ...[
                const SizedBox(width: 12),
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDuplicateSectionSkeleton() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? Colors.grey.shade800 : Colors.grey.shade200;
    final bar = Container(
      height: 16,
      width: 180,
      decoration: BoxDecoration(
        color: base,
        borderRadius: BorderRadius.circular(6),
      ),
    );

    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border.all(
          color: isDark
              ? Theme.of(context).colorScheme.outline.withValues(alpha: 0.3)
              : Colors.grey.shade200,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: base,
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 22,
                      width: 220,
                      decoration: BoxDecoration(
                        color: base,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(height: 16, child: bar),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: List.generate(
              4,
              (i) => Container(
                height: 36,
                width: 160,
                decoration: BoxDecoration(
                  color: base,
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              Container(
                height: 40,
                width: 120,
                decoration: BoxDecoration(
                  color: base,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              Container(
                height: 40,
                width: 140,
                decoration: BoxDecoration(
                  color: base,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard(String label, String value, Color color) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        border: Border.all(color: color.withValues(alpha: 0.2)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: isDark
                    ? (color is MaterialColor ? color.shade300 : color)
                    : (color is MaterialColor ? color.shade700 : color),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.7),
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCriticalIssuesSection(bool isDesktop) {
    final criticalProducts = _healthCheck['productsWithoutPurchases'] as List;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border.all(
          color: isDark
              ? Theme.of(context).colorScheme.outline.withValues(alpha: 0.3)
              : Colors.grey.shade200,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.3)
                : Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.red.shade900.withValues(alpha: 0.3)
                      : Colors.red.shade100,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  Icons.warning,
                  color: isDark ? Colors.red.shade400 : Colors.red.shade600,
                  size: 28,
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '🚨 Critical Data Integrity Issues',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          fit: FlexFit.loose,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: criticalProducts.isNotEmpty
                                  ? (isDark
                                        ? Colors.red.shade900.withValues(
                                            alpha: 0.2,
                                          )
                                        : Colors.red.shade100)
                                  : (isDark
                                        ? Colors.green.shade900.withValues(
                                            alpha: 0.2,
                                          )
                                        : Colors.green.shade100),
                              border: Border.all(
                                color: criticalProducts.isNotEmpty
                                    ? (isDark
                                          ? Colors.red.shade700
                                          : Colors.red.shade300)
                                    : (isDark
                                          ? Colors.green.shade700
                                          : Colors.green.shade300),
                              ),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              criticalProducts.isNotEmpty
                                  ? '${criticalProducts.length} Issues Found'
                                  : '✅ All Clear',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: criticalProducts.isNotEmpty
                                    ? (isDark
                                          ? Colors.red.shade300
                                          : Colors.red.shade700)
                                    : (isDark
                                          ? Colors.green.shade300
                                          : Colors.green.shade700),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'These products have stock levels but no corresponding purchase history, indicating they were likely created incorrectly or have data integrity issues that need immediate attention.',
                      style: TextStyle(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.7),
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          if (criticalProducts.isNotEmpty) ...[
            const SizedBox(height: 32),

            // Action Alert
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.red.shade900.withValues(alpha: 0.2)
                    : Colors.red.shade50,
                border: Border.all(
                  color: isDark ? Colors.red.shade700 : Colors.red.shade200,
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.red.shade800.withValues(alpha: 0.3)
                              : Colors.red.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.warning,
                          color: isDark
                              ? Colors.red.shade400
                              : Colors.red.shade600,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Immediate Action Required',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? Colors.red.shade300
                                    : Colors.red.shade800,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'These products were created with stock but have no purchase history. This violates system integrity rules and needs correction.',
                              style: TextStyle(
                                color: isDark
                                    ? Colors.red.shade400
                                    : Colors.red.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 16,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _isLoading
                            ? null
                            : () => _handleAction('reset-all-suspicious'),
                        icon:
                            _isLoading &&
                                _loadingAction == 'reset-all-suspicious'
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation(
                                    Colors.white,
                                  ),
                                ),
                              )
                            : const Icon(Icons.refresh),
                        label: Text(
                          _isLoading && _loadingAction == 'reset-all-suspicious'
                              ? 'Resetting All...'
                              : 'Reset All Stock to Zero',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange.shade600,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      Text(
                        'or review and manage individual products below',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Product List
            ...criticalProducts.map(
              (product) => Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.purple.shade900.withValues(alpha: 0.2)
                      : Colors.purple.shade50,
                  border: Border(
                    left: BorderSide(color: Colors.purple.shade400, width: 4),
                  ),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: isDark
                          ? Colors.black.withValues(alpha: 0.3)
                          : Colors.black.withValues(alpha: 0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          product['name'] ?? '',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                        ),
                        if (product['brand'] != null &&
                            product['brand'].toString().isNotEmpty) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.blue.shade900.withValues(alpha: 0.3)
                                  : Colors.blue.shade100,
                              border: Border.all(
                                color: isDark
                                    ? Colors.blue.shade700
                                    : Colors.blue.shade300,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              product['brand'],
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: isDark
                                    ? Colors.blue.shade300
                                    : Colors.blue.shade700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 16),
                    isDesktop
                        ? Row(
                            children: [
                              Expanded(child: _buildProductDetails(product)),
                              const SizedBox(width: 24),
                              _buildProductActions(product),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildProductDetails(product),
                              const SizedBox(height: 16),
                              _buildProductActions(product),
                            ],
                          ),
                  ],
                ),
              ),
            ),
          ] else ...[
            const SizedBox(height: 64),
            Center(
              child: Column(
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.green.shade900.withValues(alpha: 0.3)
                          : Colors.green.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.check_circle,
                      color: isDark
                          ? Colors.green.shade400
                          : Colors.green.shade600,
                      size: 40,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Excellent Data Integrity!',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No critical data integrity issues found. All products have proper purchase history and follow system rules.',
                    style: TextStyle(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 64),
          ],
        ],
      ),
    );
  }

  Widget _buildProductDetails(Map<String, dynamic> product) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 550;
        if (isCompact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDetailItem(
                Icons.inventory_2,
                'Stock Level',
                '${product['current_stock']} ${product['unit_type_single'] ?? 'units'}',
                Colors.red,
              ),
              const SizedBox(height: 10),
              _buildDetailItem(
                Icons.calendar_today,
                'Date Created',
                _formatDate(product['created_at']),
                Colors.blue,
              ),
              const SizedBox(height: 10),
              _buildDetailItem(
                Icons.warning,
                'Status',
                'No Purchase History',
                Colors.orange,
              ),
            ],
          );
        }
        return Row(
          children: [
            Expanded(
              child: _buildDetailItem(
                Icons.inventory_2,
                'Stock Level',
                '${product['current_stock']} ${product['unit_type_single'] ?? 'units'}',
                Colors.red,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildDetailItem(
                Icons.calendar_today,
                'Date Created',
                _formatDate(product['created_at']),
                Colors.blue,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildDetailItem(
                Icons.warning,
                'Status',
                'No Purchase History',
                Colors.orange,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDetailItem(
    IconData icon,
    String label,
    String value,
    Color color,
  ) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            color: color is MaterialColor ? color.shade600 : color,
            size: 16,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.6),
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? (color is MaterialColor ? color.shade300 : color)
                      : (color is MaterialColor ? color.shade700 : color),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProductActions(Map<String, dynamic> product) {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        ElevatedButton.icon(
          onPressed: _isLoading
              ? null
              : () => _handleAction(
                  'correct-${product['id']}',
                  productId: product['id'],
                ),
          icon: _isLoading && _loadingAction == 'correct-${product['id']}'
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  ),
                )
              : const Icon(Icons.refresh, size: 16),
          label: const Text('Reset Stock'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange.shade600,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        ElevatedButton.icon(
          onPressed: _isLoading
              ? null
              : () => _handleAction(
                  'delete-${product['id']}',
                  productId: product['id'],
                ),
          icon: _isLoading && _loadingAction == 'delete-${product['id']}'
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  ),
                )
              : const Icon(Icons.delete, size: 16),
          label: Text(
            _isLoading && _loadingAction == 'delete-${product['id']}'
                ? 'Removing...'
                : 'Remove Product',
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red.shade600,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHealthChecksGrid(bool isDesktop) {
    final cards = [
      _buildStockIssuesCard(),
      _buildDataCompletenessCard(),
      _buildDuplicateProductsCard(),
      _buildProblematicPurchasesCard(),
      _buildStockReconciliationCard(),
    ];

    if (!isDesktop) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < cards.length; i++) ...[
            if (i > 0) const SizedBox(height: 24),
            cards[i],
          ],
        ],
      );
    }

    final hasInvalidPurchases =
        (_healthCheck['invalidPurchases'] as List).isNotEmpty;
    final childAspect = hasInvalidPurchases ? 0.8 : 1.2;

    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: childAspect,
      mainAxisSpacing: 24,
      crossAxisSpacing: 24,
      children: cards,
    );
  }

  Widget _buildStockReconciliationCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isWide = MediaQuery.of(context).size.width > 768;
    final double listHeight = isWide ? 220.0 : 260.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border.all(
          color: isDark
              ? Theme.of(context).colorScheme.outline.withValues(alpha: 0.3)
              : Colors.grey.shade200,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.3)
                : Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.blue.shade900.withValues(alpha: 0.3)
                      : Colors.blue.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.inventory_2_outlined,
                  color: isDark ? Colors.blue.shade300 : Colors.blue.shade700,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Stock Reconciliation',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      _stockReconAllMismatches
                          ? 'All mismatches (advanced)'
                          : 'Fix zeros where history shows stock',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  Switch(
                    value: _stockReconAllMismatches,
                    onChanged: _stockReconLoading || _stockReconApplying
                        ? null
                        : (v) => setState(() => _stockReconAllMismatches = v),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: _stockReconLoading ? null : _runStockReconPreview,
                icon: _stockReconLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.visibility_outlined, size: 16),
                label: Text(_stockReconLoading ? 'Loading...' : 'Preview'),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: (_stockReconApplying || _stockRecon.isEmpty)
                    ? null
                    : _applyStockRecon,
                icon: _stockReconApplying
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_circle_outline, size: 16),
                label: Text(
                  _stockReconApplying ? 'Applying...' : 'Apply fixes',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_stockRecon.isNotEmpty)
            SizedBox(
              height: listHeight,
              child: ListView.separated(
                itemCount: _stockRecon.length.clamp(0, 50),
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final row = _stockRecon[index];
                  final id = row['id'];
                  final name = (row['name'] ?? '').toString();
                  final cur = (row['current_stock'] ?? 0).toString();
                  final exp = (row['expected_units'] ?? 0).toString();
                  final diff = (row['diff'] ?? 0).toString();
                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Theme.of(
                          context,
                        ).colorScheme.outline.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '#$id  $name',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Current: $cur  →  Expected: $exp  (Δ $diff)',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        if (row['should_fix_simple'] == true)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              'Simple fix',
                              style: TextStyle(
                                color: Colors.green,
                                fontSize: 12,
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            )
          else
            Center(
              child: Text(
                'No items to fix. Run preview.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).hintColor,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStockIssuesCard() {
    final negativeStockProducts = _healthCheck['negativeStock'] as List;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border.all(
          color: isDark
              ? Theme.of(context).colorScheme.outline.withValues(alpha: 0.3)
              : Colors.grey.shade200,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.3)
                : Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.red.shade900.withValues(alpha: 0.3)
                      : Colors.red.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.warning,
                  color: isDark ? Colors.red.shade400 : Colors.red.shade600,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Stock Issues',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Negative inventory levels',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: negativeStockProducts.isNotEmpty
                      ? (isDark
                            ? Colors.red.shade900.withValues(alpha: 0.2)
                            : Colors.red.shade100)
                      : (isDark
                            ? Colors.green.shade900.withValues(alpha: 0.2)
                            : Colors.green.shade100),
                  border: Border.all(
                    color: negativeStockProducts.isNotEmpty
                        ? (isDark ? Colors.red.shade700 : Colors.red.shade300)
                        : (isDark
                              ? Colors.green.shade700
                              : Colors.green.shade300),
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  negativeStockProducts.isNotEmpty
                      ? '${negativeStockProducts.length} Critical'
                      : '✅ All Good',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: negativeStockProducts.isNotEmpty
                        ? (isDark ? Colors.red.shade300 : Colors.red.shade700)
                        : (isDark
                              ? Colors.green.shade300
                              : Colors.green.shade700),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (negativeStockProducts.isNotEmpty) ...[
            ...negativeStockProducts.map(
              (product) => Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.red.shade900.withValues(alpha: 0.2)
                      : Colors.red.shade50,
                  border: Border(
                    left: BorderSide(color: Colors.red.shade400, width: 4),
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: LayoutBuilder(
                  builder: (context, c) {
                    final compact = c.maxWidth < 520;
                    final info = Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            product['name'],
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          Text(
                            'Stock: ${product['current_stock']} ${product['unit_type_single'] ?? 'units'}',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? Colors.red.shade400
                                  : Colors.red.shade600,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    );
                    final btn = ElevatedButton(
                      onPressed: _isLoading
                          ? null
                          : () => _handleAction(
                              'fix-negative-stock-${product['id']}',
                              productId: product['id'],
                            ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isDark
                            ? Colors.red.shade600
                            : Colors.red.shade600,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        minimumSize: Size.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        'Fix Stock',
                        style: TextStyle(fontSize: 12),
                      ),
                    );
                    if (compact) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [info]),
                          const SizedBox(height: 8),
                          btn,
                        ],
                      );
                    }
                    return Row(children: [info, btn]);
                  },
                ),
              ),
            ),
          ] else
            Center(
              child: Column(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.green.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.check_circle,
                      color: Colors.green.shade600,
                      size: 24,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No negative stock issues found.',
                    style: TextStyle(
                      color: Colors.green.shade600,
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDataCompletenessCard() {
    final incompleteProducts = _healthCheck['incompleteProducts'] as List;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border.all(
          color: isDark
              ? Theme.of(context).colorScheme.outline.withValues(alpha: 0.3)
              : Colors.grey.shade200,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.3)
                : Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.orange.shade900.withValues(alpha: 0.3)
                      : Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.description,
                  color: isDark
                      ? Colors.orange.shade400
                      : Colors.orange.shade600,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Data Completeness',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      'Missing essential fields',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: incompleteProducts.isNotEmpty
                      ? (isDark
                            ? Colors.orange.shade900.withValues(alpha: 0.2)
                            : Colors.orange.shade100)
                      : (isDark
                            ? Colors.green.shade900.withValues(alpha: 0.2)
                            : Colors.green.shade100),
                  border: Border.all(
                    color: incompleteProducts.isNotEmpty
                        ? (isDark
                              ? Colors.orange.shade700
                              : Colors.orange.shade300)
                        : (isDark
                              ? Colors.green.shade700
                              : Colors.green.shade300),
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  incompleteProducts.isNotEmpty
                      ? '${incompleteProducts.length} Issues'
                      : '✅ All Good',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: incompleteProducts.isNotEmpty
                        ? (isDark
                              ? Colors.orange.shade300
                              : Colors.orange.shade700)
                        : (isDark
                              ? Colors.green.shade300
                              : Colors.green.shade700),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (incompleteProducts.isNotEmpty) ...[
            ...incompleteProducts.map(
              (product) => Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.orange.shade900.withValues(alpha: 0.2)
                      : Colors.orange.shade50,
                  border: Border(
                    left: BorderSide(color: Colors.orange.shade400, width: 4),
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product['name']?.isNotEmpty == true
                          ? product['name']
                          : 'Unnamed Product',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      'Missing: ${_getMissingFields(product)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? Colors.orange.shade400
                            : Colors.orange.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ] else
            Center(
              child: Column(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.green.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.check_circle,
                      color: Colors.green.shade600,
                      size: 24,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'All products have complete essential data.',
                    style: TextStyle(
                      color: Colors.green.shade600,
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDuplicateProductsCard() {
    final duplicateProducts = _healthCheck['duplicateProducts'] as List;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border.all(
          color: isDark
              ? Theme.of(context).colorScheme.outline.withValues(alpha: 0.3)
              : Colors.grey.shade200,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.3)
                : Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.purple.shade900.withValues(alpha: 0.3)
                      : Colors.purple.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.content_copy,
                  color: isDark
                      ? Colors.purple.shade400
                      : Colors.purple.shade600,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Duplicate Products',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      'Potential duplicate entries',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: duplicateProducts.isNotEmpty
                      ? (isDark
                            ? Colors.purple.shade900.withValues(alpha: 0.2)
                            : Colors.purple.shade100)
                      : (isDark
                            ? Colors.green.shade900.withValues(alpha: 0.2)
                            : Colors.green.shade100),
                  border: Border.all(
                    color: duplicateProducts.isNotEmpty
                        ? (isDark
                              ? Colors.purple.shade700
                              : Colors.purple.shade300)
                        : (isDark
                              ? Colors.green.shade700
                              : Colors.green.shade300),
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  duplicateProducts.isNotEmpty
                      ? '${duplicateProducts.length} Duplicates'
                      : '✅ All Good',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: duplicateProducts.isNotEmpty
                        ? (isDark
                              ? Colors.purple.shade300
                              : Colors.purple.shade700)
                        : (isDark
                              ? Colors.green.shade300
                              : Colors.green.shade700),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (duplicateProducts.isNotEmpty) ...[
            ...duplicateProducts.map(
              (product) => Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.purple.shade900.withValues(alpha: 0.2)
                      : Colors.purple.shade50,
                  border: Border(
                    left: BorderSide(color: Colors.purple.shade400, width: 4),
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: LayoutBuilder(
                  builder: (context, c) {
                    final compact = c.maxWidth < 520;
                    final info = Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            product['name'],
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          Text(
                            'Category: ${product['category'] ?? 'None'}, Brand: ${product['brand'] ?? 'None'}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    );
                    final btn = ElevatedButton(
                      onPressed: _isLoading
                          ? null
                          : () => _handleAction(
                              'duplicate-${product['id']}',
                              productId: product['id'],
                            ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade600,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        minimumSize: Size.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        _isLoading &&
                                _loadingAction == 'duplicate-${product['id']}'
                            ? 'Removing...'
                            : 'Remove',
                        style: const TextStyle(fontSize: 12),
                      ),
                    );
                    if (compact) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [info]),
                          const SizedBox(height: 8),
                          btn,
                        ],
                      );
                    }
                    return Row(children: [info, btn]);
                  },
                ),
              ),
            ),
          ] else
            Center(
              child: Column(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.green.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.check_circle,
                      color: Colors.green.shade600,
                      size: 24,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No duplicate products detected.',
                    style: TextStyle(
                      color: Colors.green.shade600,
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _getMissingFields(Map<String, dynamic> product) {
    List<String> missing = [];
    if (product['name'] == null || product['name'].toString().isEmpty) {
      missing.add('Name');
    }
    if (product['unit_type_single'] == null) {
      missing.add('Unit Type');
    }
    return missing.join(', ');
  }
}
