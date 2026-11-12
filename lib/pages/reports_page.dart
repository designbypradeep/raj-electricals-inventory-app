import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:raj_electricals_inventory_app/theme/ui_tokens.dart';
import '../widgets/page_header.dart';
import '../services/supabase_service.dart';
import '../services/accounting_service.dart';
import '../services/report_pdf_service.dart';
import '../models/supabase_models.dart' as supabase_models;
import '../models/sales_purchase_models.dart';
import 'billing_page.dart';

class ReportsPage extends StatefulWidget {
  final String? initialReportType;
  final String? initialPeriod;

  const ReportsPage({
    super.key,
    this.initialReportType,
    this.initialPeriod,
  });

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  String _selectedPeriod = 'This Month';
  String _selectedReportType = 'All';
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _endDate = DateTime.now();
  bool _isLoading = true;
  supabase_models.SubscriptionInfo? _subscriptionInfo;
  List<supabase_models.Product> _products = [];
  List<Sale> _sales = [];
  List<Purchase> _purchases = [];
  List<Map<String, dynamic>> _returns = [];
  List<Map<String, dynamic>> _replacements = [];

  @override
  void initState() {
    super.initState();
    if (widget.initialReportType != null) {
      _selectedReportType = widget.initialReportType!;
    }
    if (widget.initialPeriod != null) {
      _selectedPeriod = widget.initialPeriod!;
    }
    _loadData();
  }

  double _computeEffectiveUnitPriceForPurchaseItem(
    Purchase p,
    PurchaseItem it,
  ) {
    final double disc = p.discountAmount ?? 0.0;
    final double gross = p.purchaseItems.fold<double>(
      0.0,
      (sum, l) => sum + (l.quantity * l.pricePerUnit),
    );
    final double rawAmount = it.quantity * it.pricePerUnit;
    final double lineDisc = gross > 0 ? (disc * (rawAmount / gross)) : 0.0;
    final double netAmount = (rawAmount - lineDisc).clamp(0.0, double.infinity);
    // Normalize to per-piece if item unit is wholesale (e.g., box of 30)
    double singlesQty = it.quantity.toDouble();
    try {
      final supabase_models.Product prod = _products.firstWhere(
        (p0) => p0.id == it.productId,
      );
      final double perWholesale =
          ((prod.itemsPerWholesaleUnit ?? 1) > 0
                  ? (prod.itemsPerWholesaleUnit ?? 1)
                  : 1)
              .toDouble();
      final String? wholesaleLabel = prod.unitTypeWholesale
          ?.trim()
          .toLowerCase();
      final String? itemUnit = it.unit?.trim().toLowerCase();
      if (wholesaleLabel != null &&
          itemUnit != null &&
          itemUnit == wholesaleLabel) {
        singlesQty = it.quantity.toDouble() * perWholesale;
      }
    } catch (_) {
      // product lookup failed; fall back to raw quantity
    }
    if (singlesQty <= 0) {
      singlesQty = it.quantity > 0 ? it.quantity.toDouble() : 1.0;
    }
    return netAmount / singlesQty;
  }

  Map<int, double> _computeUnitCostMapForRange(DateTimeRange range) {
    bool inRange(DateTime? dt) {
      if (dt == null) return false;
      return dt.isAfter(range.start.subtract(const Duration(days: 1))) &&
          dt.isBefore(range.end.add(const Duration(days: 1)));
    }

    final purchasesSorted = [..._purchases]
      ..sort((a, b) {
        final da =
            a.createdAt ??
            a.purchaseDate ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final db =
            b.createdAt ??
            b.purchaseDate ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return da.compareTo(db);
      });

    final Map<int, double> unitCost = {};

    // First pass: last purchase within period
    for (final p in purchasesSorted) {
      final dt = p.createdAt ?? p.purchaseDate;
      if (!inRange(dt)) continue;
      for (final it in p.purchaseItems) {
        final cost = _computeEffectiveUnitPriceForPurchaseItem(p, it);
        unitCost[it.productId] = cost; // ascending => last overwrite
      }
    }

    // Second pass: if missing, last purchase overall
    for (final p in purchasesSorted) {
      for (final it in p.purchaseItems) {
        unitCost.putIfAbsent(
          it.productId,
          () => _computeEffectiveUnitPriceForPurchaseItem(p, it),
        );
      }
    }

    return unitCost;
  }

  Widget _buildPurchaseProductsTable(
    List<Purchase> purchases,
    DateTimeRange range,
  ) {
    supabase_models.Product? findProduct(int productId) {
      try {
        return _products.firstWhere((p) => p.id == productId);
      } catch (_) {
        return null;
      }
    }

    int sno = 1;
    final rows = <DataRow>[];
    for (final p in purchases) {
      final date = p.createdAt ?? p.purchaseDate;
      final disc = p.discountAmount ?? 0.0;
      final gross = p.purchaseItems.fold<double>(
        0.0,
        (sum, it) => sum + (it.quantity * it.pricePerUnit),
      );
      for (final it in p.purchaseItems) {
        final prod = findProduct(it.productId);
        final name =
            it.product?.name ?? prod?.name ?? 'Product #${it.productId}';
        final size = prod?.sizeOrSpec ?? '-';
        final qty = it.quantity;
        final unitPrice = it.pricePerUnit;
        final rawAmount = qty * unitPrice;
        final lineDisc = gross > 0 ? (disc * (rawAmount / gross)) : 0.0;
        double netAmount = rawAmount - lineDisc;
        if (netAmount < 0) netAmount = 0.0;
        final effectiveUnitPrice = qty > 0 ? netAmount / qty : 0.0;

        rows.add(
          DataRow(
            cells: [
              DataCell(Text('${sno++}')),
              DataCell(Text(name)),
              DataCell(Text(size)),
              DataCell(Text('$qty')),
              DataCell(Text(_formatCurrency(effectiveUnitPrice))),
              DataCell(Text(_formatCurrency(netAmount))),
              DataCell(Text(date != null ? _formatDateTime(date) : '-')),
              const DataCell(Text('—')),
            ],
          ),
        );
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('SNO')),
            DataColumn(label: Text('Product Name')),
            DataColumn(label: Text('Size/Spec')),
            DataColumn(label: Text('Qty')),
            DataColumn(label: Text('Unit Price')),
            DataColumn(label: Text('Total')),
            DataColumn(label: Text('Date')),
            DataColumn(label: Text('Status')),
          ],
          rows: rows,
        ),
      ),
    );
  }

  Widget _buildInventoryProductsTable(
    List<supabase_models.Product> products, {
    Map<int, double>? unitCostByProduct,
  }) {
    int sno = 1;
    final rows = <DataRow>[];
    for (final p in products) {
      final name = p.name;
      final size = p.sizeOrSpec ?? '-';
      final qty = p.currentStock;
      final unitPrice =
          (p.id != null
              ? (unitCostByProduct?[p.id!] ?? p.purchasePrice)
              : p.purchasePrice) ??
          0.0;
      final total = unitPrice * qty;
      rows.add(
        DataRow(
          cells: [
            DataCell(Text('${sno++}')),
            DataCell(Text(name)),
            DataCell(Text(size)),
            DataCell(Text('$qty')),
            DataCell(Text(_formatCurrency(unitPrice))),
            DataCell(Text(_formatCurrency(total))),
            const DataCell(Text('—')),
            const DataCell(Text('—')),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('SNO')),
            DataColumn(label: Text('Product Name')),
            DataColumn(label: Text('Size/Spec')),
            DataColumn(label: Text('Qty')),
            DataColumn(label: Text('Unit Price')),
            DataColumn(label: Text('Total')),
            DataColumn(label: Text('Date')),
            DataColumn(label: Text('Status')),
          ],
          rows: rows,
        ),
      ),
    );
  }

  Widget _buildSalesProductsTable(List<Sale> sales, DateTimeRange range) {
    // Build quick lookup for returns and replacements in range
    bool inRange(DateTime? dt) {
      if (dt == null) return false;
      return dt.isAfter(range.start.subtract(const Duration(days: 1))) &&
          dt.isBefore(range.end.add(const Duration(days: 1)));
    }

    final Map<int, int> returnedQtyByProduct = {};
    final Map<int, String> returnedBestCondition = {}; // e.g., Excellent/Good
    final Map<int, int> replacedQtyByProduct = {};

    for (final ret in _returns) {
      final createdAtStr = ret['created_at'] as String?;
      final createdAt = createdAtStr != null
          ? DateTime.tryParse(createdAtStr)
          : null;
      if (!inRange(createdAt)) continue;
      final items = (ret['return_items'] as List?) ?? const [];
      for (final it in items) {
        final pid =
            (it['product_id'] as num?)?.toInt() ??
            (it['products'] is Map
                ? (it['products']['id'] as num?)?.toInt()
                : null);
        if (pid == null) continue;
        final qty = (it['quantity_returned'] as num?)?.toInt() ?? 1;
        returnedQtyByProduct[pid] = (returnedQtyByProduct[pid] ?? 0) + qty;
        final cond = (it['item_condition'] as String?)?.trim();
        if (cond != null && cond.isNotEmpty) {
          // Prefer "Excellent" over others if multiple
          final existing = returnedBestCondition[pid];
          if (existing == null || existing.toLowerCase() != 'excellent') {
            returnedBestCondition[pid] = cond;
          }
        }
      }
    }

    for (final rep in _replacements) {
      final createdAtStr = rep['created_at'] as String?;
      final createdAt = createdAtStr != null
          ? DateTime.tryParse(createdAtStr)
          : null;
      if (!inRange(createdAt)) continue;
      final itemsIn = (rep['replacement_items_in'] as List?) ?? const [];
      for (final it in itemsIn) {
        final pid =
            (it['product_id'] as num?)?.toInt() ??
            (it['products'] is Map
                ? (it['products']['id'] as num?)?.toInt()
                : null);
        if (pid == null) continue;
        final qty = (it['quantity_given'] as num?)?.toInt() ?? 1;
        replacedQtyByProduct[pid] = (replacedQtyByProduct[pid] ?? 0) + qty;
      }
    }

    supabase_models.Product? findProduct(int productId) {
      try {
        return _products.firstWhere((p) => p.id == productId);
      } catch (_) {
        return null;
      }
    }

    int sno = 1;
    final rows = <DataRow>[];
    for (final sale in sales) {
      final date = sale.createdAt ?? sale.saleDate;
      final double saleDiscount = sale.discountAmount ?? 0.0;
      final double grossSum = sale.salesItems.fold<double>(
        0.0,
        (sum, it) => sum + (it.quantity * it.pricePerUnit),
      );
      for (final item in sale.salesItems) {
        final prod = findProduct(item.productId);
        final name =
            item.product?.name ?? prod?.name ?? _productNameById(item.productId);
        final size = prod?.sizeOrSpec ?? '-';
        final qty = item.quantity;
        final rawUnitPrice = item.pricePerUnit; // recorded at sale time
        final rawAmount = qty * rawUnitPrice;
        // Distribute sale-level discount proportionally by line amount
        final lineDiscount = grossSum > 0
            ? (saleDiscount * (rawAmount / grossSum))
            : 0.0;
        double netAmount = rawAmount - lineDiscount;
        if (netAmount < 0) netAmount = 0.0;
        final effectiveUnitPrice = qty > 0 ? netAmount / qty : 0.0;
        final retQty = returnedQtyByProduct[item.productId] ?? 0;
        final repQty = replacedQtyByProduct[item.productId] ?? 0;
        String status = '—';
        if (repQty > 0) {
          status = 'Replaced $repQty';
        } else if (retQty > 0) {
          final cond = returnedBestCondition[item.productId];
          status = cond != null && cond.isNotEmpty
              ? 'Returned $retQty ($cond)'
              : 'Returned $retQty';
        }

        rows.add(
          DataRow(
            cells: [
              DataCell(Text('${sno++}')),
              DataCell(Text(name)),
              DataCell(Text(size)),
              DataCell(Text('$qty')),
              DataCell(Text(_formatCurrency(effectiveUnitPrice))),
              DataCell(Text(_formatCurrency(netAmount))),
              DataCell(Text(date != null ? _formatDateTime(date) : '-')),
              DataCell(Text(status)),
            ],
          ),
        );
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('SNO')),
            DataColumn(label: Text('Product Name')),
            DataColumn(label: Text('Size/Spec')),
            DataColumn(label: Text('Qty')),
            DataColumn(label: Text('Unit Price')),
            DataColumn(label: Text('Total')),
            DataColumn(label: Text('Date')),
            DataColumn(label: Text('Status')),
          ],
          rows: rows,
        ),
      ),
    );
  }

  Widget _kvRow(String key, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              key,
              style: TextStyle(
                color: Theme.of(
                  context,
                ).textTheme.bodyMedium?.color?.withValues(alpha: 0.8),
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          const SizedBox(width: 8),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  List<MapEntry<String, double>> _topEntries(
    Map<String, double> src,
    int limit,
  ) {
    final list = src.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return list.take(limit).toList();
  }

  String _productNameById(int pid) {
    for (final p in _products) {
      if (p.id == pid) return p.name;
    }
    return 'Product #$pid';
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      // Ensure business profile is loaded and fetch data
      await SupabaseService.getCurrentBusinessProfile();
      final subInfo = await SupabaseService.getSubscriptionInfo();
      final products = await SupabaseService.getProducts();
      final sales =
          await SupabaseService.getSales(); // already typed with sales_items
      final purchases =
          await SupabaseService.getPurchases(); // already typed with purchase_items
      final returnsList = await SupabaseService.getReturns();
      final replacements = await SupabaseService.getReplacements();

      // Debug: Print data counts
      if (kDebugMode) {
        print(
          'Loaded ${products.length} products, ${sales.length} sales, ${purchases.length} purchases, ${returnsList.length} returns, ${replacements.length} replacements',
        );
      }
      if (sales.isNotEmpty) {
        if (kDebugMode) {
          print('First sale: ${sales.first.toJson()}');
        }
      }
      if (purchases.isNotEmpty) {
        if (kDebugMode) {
          print('First purchase: ${purchases.first.toJson()}');
        }
      }

      setState(() {
        _products = products;
        _sales = sales;
        _purchases = purchases;
        _returns = returnsList;
        _replacements = replacements;
        _subscriptionInfo = subInfo;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load reports data: $e')),
        );
      }
    }
  }

  // Determine a readable foreground color for a given background color
  Color _onColor(Color bg) {
    // Simple luminance check for contrast
    return bg.computeLuminance() > 0.6 ? Colors.black : Colors.white;
  }

  final List<Map<String, dynamic>> _mockReports = [
    {
      'id': 1,
      'name': 'Sales Summary Report',
      'description': 'Comprehensive sales performance analysis',
      'type': 'Sales',
      'period': 'Monthly',
      'last_generated': '2024-01-15',
      'status': 'Ready',
      'icon': '📊',
      'color': Colors.blue,
    },
    {
      'id': 2,
      'name': 'Inventory Status Report',
      'description': 'Current stock levels and movement analysis',
      'type': 'Inventory',
      'period': 'Weekly',
      'last_generated': '2024-01-14',
      'status': 'Ready',
      'icon': '📦',
      'color': Colors.green,
    },
    {
      'id': 3,
      'name': 'Purchase Analysis Report',
      'description': 'Supplier performance and purchase trends',
      'type': 'Purchase',
      'period': 'Monthly',
      'last_generated': '2024-01-12',
      'status': 'Ready',
      'icon': '🛒',
      'color': Colors.orange,
    },
    {
      'id': 4,
      'name': 'Financial Summary Report',
      'description': 'Revenue, profit, and expense breakdown',
      'type': 'Financial',
      'period': 'Monthly',
      'last_generated': 'Never',
      'status': 'Ready',
      'icon': '💰',
      'color': Colors.orange,
    },
    {
      'id': 5,
      'name': 'Customer Analysis Report',
      'description': 'Customer behavior and sales patterns',
      'type': 'Customer',
      'period': 'Quarterly',
      'last_generated': '2024-01-08',
      'status': 'Ready',
      'icon': '👥',
      'color': Colors.teal,
    },
    {
      'id': 6,
      'name': 'Low Stock Alert Report',
      'description': 'Products requiring immediate attention',
      'type': 'Inventory',
      'period': 'Daily',
      'last_generated': '2024-01-15',
      'status': 'Ready',
      'icon': '⚠️',
      'color': Colors.red,
    },
  ];

  List<Map<String, dynamic>> get _quickStatsComputed {
    final range = _getPeriodRange();
    final filteredSales = _sales.where((s) {
      final createdAt = s.createdAt ?? s.saleDate;
      if (createdAt == null) return false;
      return createdAt.isAfter(range.start.subtract(const Duration(days: 1))) &&
          createdAt.isBefore(range.end.add(const Duration(days: 1)));
    }).toList();

    // Debug: Print quick stats data
    if (kDebugMode) {
      print('Quick Stats - Period: $_selectedPeriod');
    }
    if (kDebugMode) {
      print('Total sales: ${_sales.length}, Filtered: ${filteredSales.length}');
    }
    if (filteredSales.isNotEmpty) {
      if (kDebugMode) {
        print(
          'Sales data sample: ${filteredSales.take(3).map((s) => '${s.totalAmount} on ${s.createdAt ?? s.saleDate}').toList()}',
        );
      }
    }

    // Use NetSummary for accurate calculations matching Dashboard
    final netSummary = AccountingService.computeNetSummary(
      allSales: _sales,
      allPurchases: _purchases,
      products: _products,
      replacements: _replacements,
      returnsList: _returns,
      period: _getPeriodRange(),
    );
    final totalRevenue = netSummary.netRevenue;
    final totalProfit = netSummary.netProfit;
    final totalOrders = filteredSales.length;
    final activeProducts = _products.length;
    final lowStockItems = _products.where((p) => p.currentStock <= 5 && p.currentStock > 0).length;

    return [
      {
        'title': 'Net Revenue',
        'value': _formatCurrency(totalRevenue),
        'change': '-',
        'trend': 'up',
        'icon': '💰',
      },
      {
        'title': 'Net Profit',
        'value': _formatCurrency(totalProfit),
        'change': '-',
        'trend': 'up',
        'icon': '📈',
      },
      {
        'title': 'Total Orders',
        'value': '$totalOrders',
        'change': '-',
        'trend': 'up',
        'icon': '📋',
      },
      {
        'title': 'Active Products',
        'value': '$activeProducts',
        'change': '-',
        'trend': 'up',
        'icon': '📦',
      },
    ];
  }

  List<Map<String, dynamic>> get _filteredReports {
    return _mockReports.where((report) {
      if (_selectedReportType == 'All') return true;
      return report['type'] == _selectedReportType;
    }).toList();
  }

  Color _statBaseColor(String title) {
    // Use a richer palette
    if (title.contains('Revenue')) return _accentColor('indigo');
    if (title.contains('Orders')) return _accentColor('blue');
    if (title.contains('Active Products')) return _accentColor('teal');
    if (title.contains('Low Stock')) return _accentColor('orange');
    return Theme.of(context).colorScheme.primary;
  }

  Color _reportBaseColor(Map<String, dynamic> report) {
    final cs = Theme.of(context).colorScheme;
    final type = (report['type'] ?? '').toString();
    switch (type) {
      case 'Sales':
        return _accentColor('purple');
      case 'Inventory':
        return _accentColor('teal');
      case 'Purchase':
        return _accentColor('cyan');
      case 'Financial':
        return _accentColor('pink');
      case 'Customer':
        return _accentColor('blue');
      default:
        return cs.primary;
    }
  }

  Color _reportTypeAccent(String type) {
    switch (type) {
      case 'Sales':
        return _accentColor('purple');
      case 'Inventory':
        return _accentColor('teal');
      case 'Purchase':
        return _accentColor('cyan');
      case 'Financial':
        return _accentColor('pink');
      case 'Customer':
        return _accentColor('blue');
      default:
        return Theme.of(context).colorScheme.primary;
    }
  }

  // Helpers
  Color _accentColor(String key) {
    switch (key) {
      case 'teal':
        return const Color(0xFF14B8A6);
      case 'purple':
        return const Color(0xFFA855F7);
      case 'cyan':
        return const Color(0xFF06B6D4);
      case 'indigo':
        return const Color(0xFF6366F1);
      case 'orange':
        return const Color(0xFFF97316);
      case 'blue':
        return const Color(0xFF3B82F6);
      case 'pink':
        return const Color(0xFFEC4899);
      case 'amber':
        return const Color(0xFFF59E0B);
      default:
        return Theme.of(context).colorScheme.primary;
    }
  }

  String _formatCurrency(double value) {
    if (value >= 10000000) {
      return '₹${(value / 10000000).toStringAsFixed(1)}Cr';
    } else if (value >= 100000) {
      return '₹${(value / 100000).toStringAsFixed(1)}L';
    } else if (value >= 1000) {
      return '₹${(value / 1000).toStringAsFixed(1)}k';
    }
    return '₹${value.toStringAsFixed(0)}';
  }

  String _formatCurrencyPlain(double value) {
    return '₹${value.toStringAsFixed(0)}';
  }

  // Simple date-time formatter without extra dependencies
  String _formatDateTime(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
  }

  // Period label helpers
  String _formatDateYMD(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)}';
  }

  String _buildPeriodLabel(DateTimeRange range) {
    return '$_selectedPeriod: ${_formatDateYMD(range.start)} → ${_formatDateYMD(range.end)}';
  }

  String _currentPeriodChipLabel() {
    if (_selectedPeriod == 'Custom') {
      return '${_formatDateYMD(_startDate)} → ${_formatDateYMD(_endDate)}';
    }
    return _selectedPeriod;
  }

  DateTimeRange _getPeriodRange() {
    final now = DateTime.now();
    switch (_selectedPeriod) {
      case 'Today':
        final start = DateTime(now.year, now.month, now.day);
        return DateTimeRange(
          start: start,
          end: now.add(const Duration(seconds: 1)),
        );
      case 'This Week':
        final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
        final start = DateTime(
          startOfWeek.year,
          startOfWeek.month,
          startOfWeek.day,
        );
        return DateTimeRange(
          start: start,
          end: now.add(const Duration(seconds: 1)),
        );
      case 'This Month':
        final start = DateTime(now.year, now.month, 1);
        return DateTimeRange(
          start: start,
          end: now.add(const Duration(seconds: 1)),
        );
      case 'This Quarter':
        final q = ((now.month - 1) ~/ 3) * 3 + 1;
        final start = DateTime(now.year, q, 1);
        return DateTimeRange(
          start: start,
          end: now.add(const Duration(seconds: 1)),
        );
      case 'This Year':
        final start = DateTime(now.year, 1, 1);
        return DateTimeRange(
          start: start,
          end: now.add(const Duration(seconds: 1)),
        );
      case 'Custom':
        return DateTimeRange(start: _startDate, end: _endDate);
      case 'All Time':
        return DateTimeRange(
          start: DateTime(2000, 1, 1),
          end: now.add(const Duration(seconds: 1)),
        );
      default:
        final start = DateTime(now.year, now.month, 1);
        return DateTimeRange(
          start: start,
          end: now.add(const Duration(seconds: 1)),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        top: false,
        bottom: true,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: PageHeader(
                title: 'Reports & Analytics',
                description: 'Generate insights and track performance',
                icon: '📈',
                showBackButton: true,
                wrapInSafeArea: true,
                breadcrumbs: [
                  PageHeaderBreadcrumb(label: 'Dashboard', icon: '🏠'),
                  if (MediaQuery.of(context).size.width >= 450)
                    PageHeaderBreadcrumb(
                      label: 'Reports',
                      icon: '📈',
                      current: true,
                    ),
                ],
                actions: [
                  PageHeaderAction(
                    label: 'Refresh Data',
                    shortLabel: 'Refresh',
                    icon: Icons.refresh,
                    color: Theme.of(context).colorScheme.secondary,
                    onPressed: _loadData,
                  ),
                  PageHeaderAction(
                    label: 'Create Report',
                    shortLabel: 'Create',
                    icon: Icons.add_chart,
                    color: Theme.of(context).colorScheme.tertiary,
                    onPressed: () => _showCustomReportDialog(),
                  ),
                ],
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: MediaQuery.of(context).size.width < 480 ? 12 : 24,
                  vertical: MediaQuery.of(context).size.width < 480 ? 16 : 24,
                ),
                child: Column(
                  children: [
                    if (_subscriptionInfo != null &&
                        !_subscriptionInfo!.hasFeature('reports'))
                      _buildPlanFeatureBanner(),
                    _buildQuickStats(),
                    const SizedBox(height: 24),
                    _buildFinancialBreakdown(),
                    if (_selectedReportType == 'All' ||
                        _selectedReportType == 'Inventory') ...[
                      const SizedBox(height: 24),
                      _buildLowStockAlert(),
                    ],
                    const SizedBox(height: 24),
                    _buildFiltersAndPeriod(),
                    const SizedBox(height: 16),
                    _buildReportsGrid(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlanFeatureBanner() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C1B10) : const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFF97316).withValues(alpha: 0.4),
          width: 1.5,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFF97316).withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.workspace_premium,
              color: Color(0xFFF97316),
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Analytics Gated on ${_subscriptionInfo?.planName ?? 'Current'} Plan',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF9A3412),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Your current subscription has limited analytics access. Upgrade to Standard or Premium on the web to export PDF audits and unlock detailed margins.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isDark ? Colors.white70 : const Color(0xFFC2410C),
                  ),
                ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const BillingPage()),
                    );
                  },
                  icon: const Icon(Icons.arrow_upward, size: 16),
                  label: const Text('Upgrade Plan'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEA580C),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickStats() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.12),
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).shadowColor.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('📊', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              const Text(
                'Quick Overview',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              _chip(
                '📅 ${_currentPeriodChipLabel()}',
                Theme.of(context).colorScheme.secondaryContainer,
                Theme.of(context).colorScheme.onSecondaryContainer,
              ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final maxW = constraints.maxWidth;
              // Determine columns
              int crossAxisCount = 1;
              if (maxW >= 1200) {
                crossAxisCount = 4;
              } else if (maxW >= 768) {
                crossAxisCount = 2;
              }

              if (_isLoading) {
                return const Padding(
                  padding: EdgeInsets.all(24.0),
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              final stats = _quickStatsComputed;
              const spacing = 16.0;
              final available = maxW - (spacing * (crossAxisCount - 1));
              final double tileWidth = ((available / crossAxisCount).clamp(
                220.0,
                600.0,
              )).toDouble();

              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: stats
                    .map(
                      (stat) => SizedBox(
                        width: tileWidth,
                        child: _buildStatCard(stat),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(Map<String, dynamic> stat) {
    final isPositive = stat['trend'] == 'up';
    final Color base = _statBaseColor(stat['title']);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [base.withValues(alpha: 0.15), base.withValues(alpha: 0.08)]
              : [base.withValues(alpha: 0.12), base.withValues(alpha: 0.06)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: base.withValues(alpha: isDark ? 0.4 : 0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: base.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: base.withValues(alpha: isDark ? 0.25 : 0.18),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: base.withValues(alpha: 0.3)),
            ),
            child: Center(
              child: Text(stat['icon'], style: const TextStyle(fontSize: 18)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  stat['title'],
                  style: TextStyle(
                    color: Theme.of(context).textTheme.titleMedium?.color,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        stat['value'],
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: Theme.of(context).textTheme.titleLarge?.color,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: isPositive
                              ? base.withValues(alpha: isDark ? 0.2 : 0.12)
                              : Theme.of(context).colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isPositive
                                ? base.withValues(alpha: 0.4)
                                : Theme.of(
                                    context,
                                  ).colorScheme.error.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isPositive
                                  ? Icons.trending_up
                                  : Icons.trending_down,
                              size: 12,
                              color: isPositive
                                  ? base
                                  : Theme.of(context).colorScheme.error,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              stat['change'],
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: isPositive
                                    ? base
                                    : Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFinancialBreakdown() {
    if (_isLoading) return const SizedBox.shrink();
    if (_selectedReportType != 'All' && _selectedReportType != 'Financial') {
      return const SizedBox.shrink();
    }

    final range = _getPeriodRange();
    final net = AccountingService.computeNetSummary(
      allSales: _sales,
      allPurchases: _purchases,
      products: _products,
      replacements: _replacements,
      returnsList: _returns,
      period: range,
    );

    if (kDebugMode) {
      print('=== Financial Breakdown Debug ===');
      print('Gross Revenue: ₹${net.grossRevenue}');
      print('FIFO Gross Profit: ₹${net.fifoGrossProfit}');
      print('Refunds: ₹${net.refunds}');
      print('Warranty Loss: ₹${net.warrantyLoss}');
      print('Price Difference: ₹${net.priceDifference}');
      print('Return Profit Reversal: ₹${net.returnsProfitReversal}');
      print('Net Revenue: ₹${net.netRevenue}');
      print('Net Profit: ₹${net.netProfit}');
      print('================================');
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.12),
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).shadowColor.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('💰', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Text(
                'Financial Breakdown',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).textTheme.titleLarge?.color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Summary Card
          if (net.warrantyLoss > 0 ||
              net.refunds > 0 ||
              net.returnsProfitReversal > 0)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.errorContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(
                    context,
                  ).colorScheme.error.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: Theme.of(context).colorScheme.error,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Includes adjustments for returns, replacements, and warranty costs',
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).textTheme.bodySmall?.color,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          // Revenue Section
          _buildSectionHeader('REVENUE CALCULATION', isDark),
          const SizedBox(height: 8),
          _buildBreakdownRow(
            'Gross Sales Revenue',
            net.grossRevenue,
            Colors.blue,
            isDark,
          ),
          _buildBreakdownRow(
            'Less: Refunds (Returns)',
            -net.refunds,
            Colors.red,
            isDark,
          ),
          _buildBreakdownRow(
            'Add: Replacement Price Adj.',
            net.priceDifference,
            net.priceDifference >= 0 ? Colors.green : Colors.red,
            isDark,
          ),
          const Divider(height: 20, thickness: 1.5),
          _buildBreakdownRow(
            'Net Revenue',
            net.netRevenue,
            _accentColor('indigo'),
            isDark,
            isBold: true,
          ),
          const SizedBox(height: 20),
          // Profit Section
          _buildSectionHeader('PROFIT CALCULATION', isDark),
          const SizedBox(height: 8),
          _buildBreakdownRow(
            'FIFO Gross Profit (Sales)',
            net.fifoGrossProfit,
            Colors.green,
            isDark,
          ),
          _buildBreakdownRow(
            'Less: Return Profit Reversal',
            -net.returnsProfitReversal,
            Colors.orange,
            isDark,
          ),
          _buildBreakdownRow(
            'Less: Warranty/Replacement Cost',
            -net.warrantyLoss,
            Colors.red,
            isDark,
            subtitle: 'Cost of replacement items given',
          ),
          _buildBreakdownRow(
            'Add: Replacement Price Adj.',
            net.priceDifference,
            net.priceDifference >= 0 ? Colors.green : Colors.red,
            isDark,
            subtitle: 'Extra payment from customer',
          ),
          const Divider(height: 20, thickness: 1.5),
          _buildBreakdownRow(
            'Net Profit / Loss',
            net.netProfit,
            net.netProfit >= 0 ? Colors.green : Colors.red,
            isDark,
            isBold: true,
            isLarge: true,
          ),
        ],
      ),
    );
  }

  Widget _buildLowStockAlert() {
    if (_isLoading) return const SizedBox.shrink();
    if (_selectedReportType != 'All' && _selectedReportType != 'Inventory') {
      return const SizedBox.shrink();
    }

    final lowStockItems = _products.where((p) => p.currentStock <= 5 && p.currentStock > 0).toList();
    if (lowStockItems.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.12),
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).shadowColor.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('⚠️', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Text(
                'Low Stock Alert',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).textTheme.titleLarge?.color,
                ),
              ),
              const Spacer(),
              _chip(
                '${lowStockItems.length} items',
                Theme.of(context).colorScheme.errorContainer,
                Theme.of(context).colorScheme.error,
              ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: DataTable(
                    headingRowHeight: 40,
                    dataRowMinHeight: 48,
                    columns: const [
                      DataColumn(label: Text('Product')),
                      DataColumn(label: Text('Stock')),
                      DataColumn(label: Text('Status')),
                    ],
                    rows: lowStockItems.take(10).map((p) {
                      return DataRow(
                        cells: [
                          DataCell(
                            Container(
                              constraints: const BoxConstraints(maxWidth: 200),
                              child: Text(
                                p.name,
                                style: const TextStyle(fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          DataCell(
                            Text(
                              '${p.currentStock}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: p.currentStock == 0
                                    ? Theme.of(context).colorScheme.error
                                    : Colors.orange,
                              ),
                            ),
                          ),
                          DataCell(
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: p.currentStock == 0
                                    ? Theme.of(context).colorScheme.errorContainer
                                    : Colors.orange.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                p.currentStock == 0 ? 'Out of Stock' : 'Low',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: p.currentStock == 0
                                      ? Theme.of(context).colorScheme.error
                                      : Colors.orange[800],
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              );
            },
          ),
          if (lowStockItems.length > 10)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                '+ ${lowStockItems.length - 10} more items...',
                style: TextStyle(
                  fontStyle: FontStyle.italic,
                  color: Theme.of(context).textTheme.bodySmall?.color,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildBreakdownRow(
    String label,
    double amount,
    Color color,
    bool isDark, {
    bool isBold = false,
    bool isLarge = false,
    String? subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: isLarge ? 16 : 14,
                    fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
                    color: Theme.of(context).textTheme.bodyLarge?.color,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                      color: Theme.of(
                        context,
                      ).textTheme.bodySmall?.color?.withValues(alpha: 0.7),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: isDark ? 0.2 : 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: color.withValues(alpha: isDark ? 0.4 : 0.3),
                width: 1.2,
              ),
            ),
            child: Text(
              _formatCurrency(amount),
              style: TextStyle(
                fontSize: isLarge ? 16 : 14,
                fontWeight: isBold ? FontWeight.w900 : FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFiltersAndPeriod() {
    final width = MediaQuery.of(context).size.width;
    final compact = width < 640;

    Widget chips = Wrap(
      spacing: 8,
      runSpacing: 8,
      children:
          [
            'All',
            'Sales',
            'Inventory',
            'Purchase',
            'Financial',
            'Customer',
          ].map((type) {
            final selected = _selectedReportType == type;
            final base = type == 'All'
                ? Theme.of(context).colorScheme.primary
                : _reportTypeAccent(type);
            final isDark = Theme.of(context).brightness == Brightness.dark;
            return ChoiceChip(
              label: Text(type),
              selected: selected,
              onSelected: (_) => setState(() => _selectedReportType = type),
              selectedColor: base.withValues(alpha: isDark ? 0.18 : 0.12),
              backgroundColor: Theme.of(context).cardColor,
              labelStyle: TextStyle(
                color: selected
                    ? base
                    : Theme.of(context).textTheme.bodyMedium?.color,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                fontSize: 14,
              ),
              side: BorderSide(
                color: selected
                    ? base.withValues(alpha: 0.5)
                    : Theme.of(context).dividerColor.withValues(alpha: 0.5),
                width: selected ? 1.5 : 1,
              ),
              elevation: selected ? 2 : 0,
              shadowColor: selected ? base.withValues(alpha: 0.3) : null,
            );
          }).toList(),
    );

    Widget periodDropdown = Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.8),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).shadowColor.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedPeriod,
          isExpanded: true,
          items:
              [
                'Today',
                'This Week',
                'This Month',
                'This Quarter',
                'This Year',
                'All Time',
                'Custom',
              ].map((period) {
                return DropdownMenuItem(
                  value: period,
                  child: Text(
                    period,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
          onChanged: (value) {
            if (value != null) {
              setState(() {
                _selectedPeriod = value;
                if (value == 'Custom') {
                  _showDateRangePicker();
                }
              });
            }
          },
          icon: Icon(
            Icons.arrow_drop_down,
            color: Theme.of(context).colorScheme.primary,
            size: 28,
          ),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Theme.of(context).textTheme.bodyLarge?.color,
          ),
          dropdownColor: Theme.of(context).cardColor,
        ),
      ),
    );

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          chips,
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, child: periodDropdown),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Flexible(
          flex: 1,
          fit: FlexFit.loose,
          child: Align(alignment: Alignment.topLeft, child: chips),
        ),
        const SizedBox(width: 16),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 200, maxWidth: 300),
          child: periodDropdown,
        ),
      ],
    );
  }

  Widget _buildReportsGrid() {
    final reports = _filteredReports;

    final width = MediaQuery.of(context).size.width;
    int crossAxisCount = 1;
    double aspect = 1.1; // make cards taller on phones
    if (width >= 1200) {
      crossAxisCount = 3;
      aspect = 1.25;
    } else if (width >= 768) {
      crossAxisCount = 2;
      aspect = 1.2;
    }

    if (_isLoading) {
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          childAspectRatio: aspect,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
        ),
        itemCount: crossAxisCount * 2,
        itemBuilder: (context, index) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
            ),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 120,
                height: 16,
                decoration: BoxDecoration(
                  color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                height: 12,
                decoration: BoxDecoration(
                  color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const Spacer(),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 36,
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).dividerColor.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      height: 36,
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).dividerColor.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    if (reports.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.6),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              Icons.bar_chart,
              size: 40,
              color: Theme.of(
                context,
              ).textTheme.bodyMedium?.color?.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 8),
            Text(
              'No reports match the selected filter',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: Theme.of(context).textTheme.bodyLarge?.color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Try choosing a different type or period.',
              style: TextStyle(
                color: Theme.of(
                  context,
                ).textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        childAspectRatio: aspect,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: reports.length,
      itemBuilder: (context, index) => _buildReportCard(reports[index]),
    );
  }

  Widget _buildReportCard(Map<String, dynamic> report) {
    final isReady = report['status'] == 'Ready';
    final Color base = _reportBaseColor(report);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: base.withValues(alpha: isDark ? 0.4 : 0.25),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: base.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Theme.of(
              context,
            ).shadowColor.withValues(alpha: isDark ? 0.1 : 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        base.withValues(alpha: isDark ? 0.2 : 0.15),
                        base.withValues(alpha: isDark ? 0.15 : 0.1),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: base.withValues(alpha: isDark ? 0.5 : 0.4),
                      width: 1.5,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      report['icon'],
                      style: const TextStyle(fontSize: 22),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        report['name'],
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                          color: Theme.of(context).textTheme.titleMedium?.color,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                      const SizedBox(height: 2),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: isReady
                              ? base.withValues(alpha: isDark ? 0.2 : 0.12)
                              : Theme.of(context).colorScheme.tertiaryContainer,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isReady
                                ? base.withValues(alpha: 0.5)
                                : Theme.of(
                                    context,
                                  ).colorScheme.tertiary.withValues(alpha: 0.4),
                            width: 1.2,
                          ),
                        ),
                        child: Text(
                          report['status'],
                          style: TextStyle(
                            color: isReady
                                ? base
                                : Theme.of(context).colorScheme.tertiary,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              report['description'],
              style: TextStyle(
                color: Theme.of(context).textTheme.bodyMedium?.color,
                fontSize: 14,
                height: 1.5,
                fontWeight: FontWeight.w700,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _chip(
                  '📅 ${_currentPeriodChipLabel()}',
                  cs.secondaryContainer,
                  cs.onSecondaryContainer,
                ),
                const SizedBox(width: 8),
                _chip(
                  '📂 ${report['type']}',
                  base.withValues(alpha: isDark ? 0.18 : 0.12),
                  base,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Last generated: ${report['last_generated']}',
                    style: TextStyle(
                      color: Theme.of(context).textTheme.bodySmall?.color,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Export PDF',
                  icon: const Icon(Icons.download),
                  color: base,
                  onPressed: () => _exportReportQuick(report),
                ),
              ],
            ),
            // Removed Spacer to avoid flex-in-unbounded errors
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _generateReport(report),
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Generate'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(UITokens.radius),
                      ),
                      side: BorderSide(
                        color: base.withValues(alpha: 0.6),
                        width: 1.5,
                      ),
                      foregroundColor: base,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _viewReport(report),
                    icon: const Icon(Icons.visibility, size: 16),
                    label: const Text('View'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: base,
                      foregroundColor: _onColor(base),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(UITokens.radius),
                      ),
                      elevation: 2,
                      shadowColor: base.withValues(alpha: 0.3),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String text, Color bg, Color fg) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: fg.withValues(alpha: isDark ? 0.4 : 0.3),
          width: 1.2,
        ),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, color: fg, fontWeight: FontWeight.w700),
      ),
    );
  }

  void _showCustomReportDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create Custom Report'),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Custom report builder functionality will be implemented here.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Custom report functionality coming soon!'),
                ),
              );
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showDateRangePicker() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
    }
  }

  void _generateReport(Map<String, dynamic> report) {
    final range = _getPeriodRange();
    final type = (report['type'] as String).toLowerCase();
    final filteredSales = _sales.where((s) {
      final createdAt = s.createdAt ?? s.saleDate;
      if (createdAt == null) return false;
      return createdAt.isAfter(range.start.subtract(const Duration(days: 1))) &&
          createdAt.isBefore(range.end.add(const Duration(days: 1)));
    }).toList();
    final filteredPurchases = _purchases.where((p) {
      final createdAt = p.createdAt ?? p.purchaseDate;
      if (createdAt == null) return false;
      return createdAt.isAfter(range.start.subtract(const Duration(days: 1))) &&
          createdAt.isBefore(range.end.add(const Duration(days: 1)));
    }).toList();

    // Debug: Print filtering results
    if (kDebugMode) {
      print('Period: $_selectedPeriod, Range: ${range.start} to ${range.end}');
    }
    if (kDebugMode) {
      print(
        'Filtered ${filteredSales.length} sales, ${filteredPurchases.length} purchases',
      );
    }
    if (filteredSales.isNotEmpty) {
      if (kDebugMode) {
        print(
          'Sales amounts: ${filteredSales.map((s) => s.totalAmount).toList()}',
        );
      }
    }
    if (filteredPurchases.isNotEmpty) {
      if (kDebugMode) {
        print(
          'Purchase amounts: ${filteredPurchases.map((p) => p.totalAmount).toList()}',
        );
      }
    }

    // Compute financial metrics using NetSummary for accurate calculations
    final netSummary = AccountingService.computeNetSummary(
      allSales: _sales,
      allPurchases: _purchases,
      products: _products,
      replacements: _replacements,
      returnsList: _returns,
      period: range,
    );
    final fifo = AccountingService.computeFifoSummary(
      allSales: _sales,
      allPurchases: _purchases,
      products: _products,
      period: range,
    );
    final revenue = netSummary.netRevenue;
    final cogs = fifo.cogs;
    final profit = netSummary.netProfit;

    final orders = filteredSales.length;
    final avgOrder = orders > 0 ? revenue / orders : 0.0;

    final unitsSold = fifo.unitsSold;
    final avgSellPrice = fifo.avgSellPrice;
    final avgCostPrice = fifo.avgCostPrice;
    final purchaseTotal = filteredPurchases.fold<double>(
      0.0,
      (sum, p) => sum + p.totalAmount,
    );
    final uniqueCustomers = filteredSales
        .map((s) => (s.customerName ?? '').trim())
        .where((name) => name.isNotEmpty)
        .toSet()
        .length;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Generating ${report['name']}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Period label with better contrast
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.date_range,
                    color: Theme.of(context).colorScheme.onSecondaryContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _buildPeriodLabel(range),
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSecondaryContainer,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text('Please wait while we generate your report...'),
            const SizedBox(height: 12),
            if (type == 'sales') ...[
              Text('Revenue: ${_formatCurrency(revenue)}'),
              Text('Orders: $orders'),
              Text('Avg Order Value: ${_formatCurrency(avgOrder)}'),
            ] else if (type == 'inventory') ...[
              // Live inventory: products with purchase history and stock > 0
              Builder(
                builder: (context) {
                  final Set<int> purchasedIds = {
                    for (final p in _purchases)
                      ...p.purchaseItems.map((it) => it.productId),
                  };
                  final inventoryList = _products
                      .where(
                        (p) =>
                            (p.id != null &&
                            purchasedIds.contains(p.id!) &&
                            p.currentStock > 0),
                      )
                      .toList();
                  final totalUnits = inventoryList.fold<num>(
                    0,
                    (sum, p) => sum + p.currentStock,
                  );
                  final invValue = inventoryList.fold<double>(
                    0.0,
                    (sum, p) => sum + (p.purchasePrice ?? 0) * p.currentStock,
                  );
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Products in Inventory: ${inventoryList.length}'),
                      Text('Total Units in Stock: $totalUnits'),
                      Text(
                        'Inventory Value (at cost): ${_formatCurrency(invValue)}',
                      ),
                    ],
                  );
                },
              ),
            ] else if (type == 'purchase') ...[
              Text('Purchases: ${filteredPurchases.length}'),
              Text('Total Purchase Value: ${_formatCurrency(purchaseTotal)}'),
              Text(
                'Avg Purchase: ${_formatCurrency(filteredPurchases.isNotEmpty ? (purchaseTotal / filteredPurchases.length) : 0)}',
              ),
            ] else if (type == 'financial') ...[
              Text(
                'Gross Revenue: ${_formatCurrency(netSummary.grossRevenue)}',
              ),
              Text('Net Revenue: ${_formatCurrency(netSummary.netRevenue)}'),
              Text('Net Profit: ${_formatCurrency(netSummary.netProfit)}'),
              Text('Refunds: ${_formatCurrency(netSummary.refunds)}'),
              Text(
                'Warranty Loss: ${_formatCurrency(netSummary.warrantyLoss)}',
              ),
              Text(
                'Net Margin: ${revenue > 0 ? ((profit / revenue) * 100).toStringAsFixed(1) : '0.0'}%',
              ),
            ] else if (type == 'customer') ...[
              Text('Unique Customers: $uniqueCustomers'),
              Text('Orders: $orders'),
              Text('Revenue: ${_formatCurrency(revenue)}'),
              Text(
                'Avg Revenue per Customer: ${_formatCurrency(uniqueCustomers > 0 ? revenue / uniqueCustomers : 0)}',
              ),
            ],
          ],
        ),
      ),
    );

    // Simulate report generation
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        Navigator.pop(context);
        // Update dynamic fields on completion
        setState(() {
          final stamp = _formatDateTime(DateTime.now());
          final idx = _mockReports.indexWhere((r) => r['id'] == report['id']);
          if (idx != -1) {
            _mockReports[idx]['last_generated'] = stamp;
            _mockReports[idx]['period'] = _selectedPeriod;
            _mockReports[idx]['status'] = 'Ready';
          }
          report['last_generated'] = stamp;
          report['period'] = _selectedPeriod;
          report['status'] = 'Ready';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ ${report['name']} generated successfully!'),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
        );
      }
    });
  }

  void _viewReport(Map<String, dynamic> report) {
    final range = _getPeriodRange();
    final type = (report['type'] as String).toLowerCase();
    final filteredSales = _sales.where((s) {
      final createdAt = s.createdAt ?? s.saleDate;
      if (createdAt == null) return false;
      return createdAt.isAfter(range.start.subtract(const Duration(days: 1))) &&
          createdAt.isBefore(range.end.add(const Duration(days: 1)));
    }).toList();
    final filteredPurchases = _purchases.where((p) {
      final createdAt = p.createdAt ?? p.purchaseDate;
      if (createdAt == null) return false;
      return createdAt.isAfter(range.start.subtract(const Duration(days: 1))) &&
          createdAt.isBefore(range.end.add(const Duration(days: 1)));
    }).toList();

    // Debug: Print view report data
    if (kDebugMode) {
      print('View Report - Period: $_selectedPeriod');
    }
    if (kDebugMode) {
      print(
        'Filtered ${filteredSales.length} sales, ${filteredPurchases.length} purchases',
      );
    }
    final netSummary = AccountingService.computeNetSummary(
      allSales: _sales,
      allPurchases: _purchases,
      products: _products,
      replacements: _replacements,
      returnsList: _returns,
      period: range,
    );
    final revenue = netSummary.netRevenue;
    final profit = netSummary.netProfit;

    final orders = filteredSales.length;
    final avgOrder = orders > 0 ? revenue / orders : 0.0;

    final purchaseTotal = filteredPurchases.fold<double>(
      0.0,
      (sum, p) => sum + p.totalAmount,
    );
    final uniqueCustomers = filteredSales
        .map((s) => (s.customerName ?? '').trim())
        .where((name) => name.isNotEmpty)
        .toSet()
        .length;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Text(report['icon'], style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 8),
            Expanded(child: Text(report['name'])),
          ],
        ),
        content: SizedBox(
          width: 600,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(report['description']),
                const SizedBox(height: 16),
                if (type == 'sales') ...[
                  Text('Total Revenue: ${_formatCurrency(revenue)}'),
                  Text('Orders: $orders'),
                  Text('Avg Order Value: ${_formatCurrency(avgOrder)}'),
                  const SizedBox(height: 12),
                ] else if (type == 'inventory') ...[
                  Text('Active Products: ${_products.length}'),
                  Text(
                    'Low Stock Items: ${_products.where((p) => p.currentStock <= 5).length}',
                  ),
                  Text(
                    'Inventory Value (at cost): ${_formatCurrency(_products.fold<double>(0.0, (sum, p) => sum + (p.purchasePrice ?? 0) * p.currentStock))}',
                  ),
                  const SizedBox(height: 12),
                ] else if (type == 'purchase') ...[
                  Text('Purchases: ${filteredPurchases.length}'),
                  Text(
                    'Total Purchase Value: ${_formatCurrency(purchaseTotal)}',
                  ),
                  Text(
                    'Avg Purchase: ${_formatCurrency(filteredPurchases.isNotEmpty ? (purchaseTotal / filteredPurchases.length) : 0)}',
                  ),
                  const SizedBox(height: 12),
                ] else if (type == 'financial') ...[
                  _buildMetricCard(
                    '💰',
                    'Gross Sales Revenue',
                    _formatCurrency(netSummary.grossRevenue),
                  ),
                  _buildMetricCard(
                    '🔵',
                    'Net Revenue',
                    _formatCurrency(netSummary.netRevenue),
                  ),
                  _buildMetricCard(
                    '📈',
                    'Net Profit',
                    _formatCurrency(netSummary.netProfit),
                  ),
                  _buildMetricCard(
                    '📊',
                    'Net Margin',
                    '${revenue > 0 ? ((profit / revenue) * 100).toStringAsFixed(1) : '0.0'}%',
                  ),
                  _buildMetricCard(
                    '↩️',
                    'Refunds (Returns)',
                    _formatCurrency(netSummary.refunds),
                  ),
                  _buildMetricCard(
                    '⚠️',
                    'Warranty Loss',
                    _formatCurrency(netSummary.warrantyLoss),
                  ),
                  _buildMetricCard(
                    '📦',
                    'Total Transactions',
                    '${filteredSales.length + filteredPurchases.length}',
                  ),
                  _buildMetricCard(
                    '💳',
                    'Avg Transaction Value',
                    _formatCurrency(
                      (filteredSales.length + filteredPurchases.length) > 0
                          ? (revenue + purchaseTotal) /
                                (filteredSales.length +
                                    filteredPurchases.length)
                          : 0,
                    ),
                  ),
                  if (filteredSales.isNotEmpty ||
                      filteredPurchases.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Financial Breakdown:',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: profit >= 0
                            ? Theme.of(context).colorScheme.primaryContainer
                            : Theme.of(context).colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '📊 Financial Summary for $_selectedPeriod',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '• Gross Revenue: ${_formatCurrency(netSummary.grossRevenue)}',
                          ),
                          Text('• Net Revenue: ${_formatCurrency(revenue)}'),
                          Text('• Net Profit: ${_formatCurrency(profit)}'),
                          Text(
                            '• Refunds: ${_formatCurrency(netSummary.refunds)}',
                          ),
                          Text(
                            '• Net Margin: ${revenue > 0 ? ((profit / revenue) * 100).toStringAsFixed(1) : '0.0'}%',
                          ),
                        ],
                      ),
                    ),
                  ],
                ] else if (type == 'customer') ...[
                  Text('Unique Customers: $uniqueCustomers'),
                  Text('Orders: $orders'),
                  Text('Revenue: ${_formatCurrency(revenue)}'),
                  Text(
                    'Avg Revenue per Customer: ${_formatCurrency(uniqueCustomers > 0 ? revenue / uniqueCustomers : 0)}',
                  ),
                  const SizedBox(height: 12),
                ],
                const SizedBox(height: 16),
                _buildReportChart(
                  type,
                  netSummary,
                  revenue,
                  profit,
                  orders,
                  filteredSales,
                  filteredPurchases,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              // Show detailed report data instead of placeholder
              _showDetailedReport(report, {
                'revenue': revenue,
                'orders': orders,
                'avgOrder': avgOrder,
                'purchaseTotal': purchaseTotal,
                'netProfit': profit,
                'grossRevenue': netSummary.grossRevenue,
                'refunds': netSummary.refunds,
                'warrantyLoss': netSummary.warrantyLoss,
                'uniqueCustomers': uniqueCustomers,
                'filteredSales': filteredSales,
                'filteredPurchases': filteredPurchases,
              });
            },
            icon: const Icon(Icons.analytics),
            label: const Text('View Details'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
            ),
          ),
        ],
      ),
    );
  }

  void _showDetailedReport(
    Map<String, dynamic> report,
    Map<String, dynamic> data,
  ) {
    final range = _getPeriodRange();
    final type = (report['type'] as String).toLowerCase();

    // Use up-to-date calculations for the selected period
    final net = AccountingService.computeNetSummary(
      allSales: _sales,
      allPurchases: _purchases,
      products: _products,
      replacements: _replacements,
      returnsList: _returns,
      period: range,
    );
    final fifo = AccountingService.computeFifoSummary(
      allSales: _sales,
      allPurchases: _purchases,
      products: _products,
      period: range,
    );
    // Profit breakdown removed in dialog

    final double revenue = net.netRevenue;
    final int orders = (data['orders'] as int);
    final double avgOrder = orders > 0 ? revenue / orders : 0.0;
    final double purchaseTotal = (data['purchaseTotal'] as double);
    final double cogs = fifo.cogs;
    final double profit = net.netProfit;
    final int uniqueCustomers = (data['uniqueCustomers'] as int);
    final List<Sale> filteredSales = data['filteredSales'] as List<Sale>;
    final List<Purchase> filteredPurchases =
        data['filteredPurchases'] as List<Purchase>;

    // Inventory details no longer shows low stock breakdown here

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Text(report['icon'], style: const TextStyle(fontSize: 28)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '${report['name']} - Details',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Period Info (theme-aware)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.date_range,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSecondaryContainer,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _buildPeriodLabel(range),
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSecondaryContainer,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Key Metrics
                if (type == 'sales') ...[
                  _buildMetricCard(
                    '💰',
                    'Total Revenue',
                    _formatCurrency(revenue),
                  ),
                  _buildMetricCard('📦', 'Total Orders', '$orders'),
                  _buildMetricCard(
                    '💳',
                    'Average Order Value',
                    _formatCurrency(avgOrder),
                  ),
                  if (filteredSales.isNotEmpty) ...[
                    Builder(
                      builder: (context) {
                        final Map<String, double> salesByProd = {};
                        for (final s in filteredSales) {
                          for (final it in s.salesItems) {
                            final pName =
                                it.product?.name ?? _productNameById(it.productId);
                            salesByProd[pName] =
                                (salesByProd[pName] ?? 0.0) +
                                (it.quantity * it.pricePerUnit);
                          }
                        }
                        if (salesByProd.isEmpty) return const SizedBox.shrink();
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 12),
                            const Text(
                              'Top Performing Products:',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Theme.of(context).cardColor,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Theme.of(context).dividerColor,
                                ),
                              ),
                              child: Column(
                                children: _topEntries(salesByProd, 3)
                                    .map(
                                      (e) => _kvRow(
                                        e.key,
                                        _formatCurrency(e.value),
                                      ),
                                    )
                                    .toList(),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Recent Sales:',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...filteredSales
                        .take(5)
                        .map((sale) => _buildSaleItem(sale)),

                    const SizedBox(height: 16),
                    Text(
                      'Product-wise Sales (within period):',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildSalesProductsTable(filteredSales, range),
                  ],
                ] else if (type == 'inventory') ...[
                  Builder(
                    builder: (context) {
                      // Build inventory set: products with purchase history and current stock > 0
                      final Set<int> purchasedIds = {
                        for (final p in _purchases)
                          ...p.purchaseItems.map((it) => it.productId),
                      };
                      final inventoryList = _products
                          .where(
                            (p) =>
                                (p.id != null &&
                                purchasedIds.contains(p.id!) &&
                                p.currentStock > 0),
                          )
                          .toList();
                      final unitCostByProduct = _computeUnitCostMapForRange(
                        range,
                      );
                      final totalUnits = inventoryList.fold<num>(
                        0,
                        (sum, p) => sum + p.currentStock,
                      );
                      final invValue = inventoryList.fold<double>(0.0, (
                        sum,
                        p,
                      ) {
                        final unit =
                            (p.id != null
                                ? (unitCostByProduct[p.id!] ?? p.purchasePrice)
                                : p.purchasePrice) ??
                            0.0;
                        return sum + unit * p.currentStock;
                      });
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildMetricCard(
                            '📦',
                            'Products in Inventory',
                            '${inventoryList.length}',
                          ),
                          _buildMetricCard(
                            '📊',
                            'Total Units in Stock',
                            '$totalUnits',
                          ),
                          _buildMetricCard(
                            '💎',
                            'Inventory Value (at cost)',
                            _formatCurrency(invValue),
                          ),
                          if (inventoryList.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            Text(
                              'Current Inventory:',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 8),
                            _buildInventoryProductsTable(
                              inventoryList,
                              unitCostByProduct: unitCostByProduct,
                            ),
                          ],
                          Builder(
                            builder: (context) {
                              final lowStock = _products
                                  .where((p) => p.currentStock <= 5 && p.currentStock > 0)
                                  .toList();
                              if (lowStock.isEmpty) return const SizedBox.shrink();
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 16),
                                  const Text(
                                    'Low Stock Warnings:',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  ...lowStock
                                      .take(5)
                                      .map((p) => _buildProductItem(p)),
                                ],
                              );
                            },
                          ),
                        ],
                      );
                    },
                  ),
                ] else if (type == 'purchase') ...[
                  _buildMetricCard(
                    '🛒',
                    'Total Purchases',
                    '${filteredPurchases.length}',
                  ),
                  _buildMetricCard(
                    '💰',
                    'Total Purchase Value',
                    _formatCurrency(purchaseTotal),
                  ),
                  _buildMetricCard(
                    '📊',
                    'Average Purchase',
                    _formatCurrency(
                      filteredPurchases.isNotEmpty
                          ? (purchaseTotal / filteredPurchases.length)
                          : 0,
                    ),
                  ),
                  if (filteredPurchases.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Recent Purchases:',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...filteredPurchases
                        .take(5)
                        .map((purchase) => _buildPurchaseItem(purchase)),

                    const SizedBox(height: 16),
                    Text(
                      'Product-wise Purchases (within period):',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildPurchaseProductsTable(filteredPurchases, range),
                  ],
                ] else if (type == 'financial') ...[
                  _buildMetricCard(
                    '💰',
                    'Net Revenue',
                    _formatCurrency(revenue),
                  ),
                  _buildMetricCard('💸', 'COGS (FIFO)', _formatCurrency(cogs)),
                  _buildMetricCard('📈', 'Net Profit', _formatCurrency(profit)),
                  _buildMetricCard(
                    '📊',
                    'Net Margin',
                    '${revenue > 0 ? ((profit / revenue) * 100).toStringAsFixed(1) : '0.0'}%',
                  ),
                ] else if (type == 'customer') ...[
                  _buildMetricCard(
                    '👥',
                    'Unique Customers',
                    '$uniqueCustomers',
                  ),
                  _buildMetricCard('📦', 'Total Orders', '$orders'),
                  _buildMetricCard(
                    '💰',
                    'Total Revenue',
                    _formatCurrency(revenue),
                  ),
                  _buildMetricCard(
                    '💳',
                    'Avg Revenue per Customer',
                    _formatCurrency(
                      uniqueCustomers > 0 ? revenue / uniqueCustomers : 0,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              Navigator.pop(context);
              await _exportReport(report, data, range);
            },
            icon: const Icon(Icons.download),
            label: const Text('Export'),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard(String icon, String title, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        children: [
          Text(icon, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSaleItem(Sale sale) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              sale.customerName?.isNotEmpty == true
                  ? sale.customerName!
                  : 'Walk-in Customer',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Text(
            _formatCurrency(sale.totalAmount),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildPurchaseItem(Purchase purchase) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              purchase.supplierName?.isNotEmpty == true
                  ? purchase.supplierName!
                  : 'Unknown Supplier',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Text(
            _formatCurrency(purchase.totalAmount),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildProductItem(supabase_models.Product product) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.error.withValues(alpha: 0.5), width: 1),
      ),
      child: Row(
        children: [
          // Thumbnail
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: cs.onSurface.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: cs.error.withValues(alpha: 0.3)),
            ),
            clipBehavior: Clip.antiAlias,
            child:
                (product.productImageUrl != null &&
                    product.productImageUrl!.isNotEmpty)
                ? Image.network(
                    product.productImageUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stack) => Icon(
                      Icons.image_not_supported,
                      size: 18,
                      color: cs.error,
                    ),
                  )
                : Icon(Icons.inventory_2, size: 18, color: cs.error),
          ),
          const SizedBox(width: 10),
          // Name
          Expanded(
            child: Text(
              product.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: cs.onErrorContainer,
              ),
            ),
          ),
          // Stock badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: cs.error.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: cs.error.withValues(alpha: 0.5)),
            ),
            child: Text(
              'Stock: ${product.currentStock}',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: cs.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportReport(
    Map<String, dynamic> report,
    Map<String, dynamic> data,
    DateTimeRange range,
  ) async {
    final type = (report['type'] as String).toLowerCase();
    final title = report['name'] as String;
    final description = report['description'] as String;
    final periodLabel = _buildPeriodLabel(range);

    final List<Map<String, String>> metrics = [];
    String? itemsTitle;
    List<Map<String, String>>? items;

    switch (type) {
      case 'sales':
        metrics.addAll([
          {
            'title': 'Total Revenue',
            'value': _formatCurrencyPlain(data['netRevenue'] as double),
          },
          {'title': 'Orders', 'value': (data['orders'] as int).toString()},
          {
            'title': 'Avg Order',
            'value': _formatCurrencyPlain(data['avgOrder'] as double),
          },
        ]);
        break;
      case 'inventory':
        final Set<int> purchasedIds = {
          for (final p in _purchases)
            ...p.purchaseItems.map((it) => it.productId),
        };
        final inventoryList = _products
            .where(
              (p) =>
                  (p.id != null &&
                  purchasedIds.contains(p.id!) &&
                  p.currentStock > 0),
            )
            .toList();
        final unitCostByProduct = _computeUnitCostMapForRange(range);
        final totalUnits = inventoryList.fold<num>(
          0,
          (sum, p) => sum + p.currentStock,
        );
        final invValue = inventoryList.fold<double>(0.0, (sum, p) {
          final unit =
              (p.id != null
                  ? (unitCostByProduct[p.id!] ?? p.purchasePrice)
                  : p.purchasePrice) ??
              0.0;
          return sum + unit * p.currentStock;
        });
        metrics.addAll([
          {
            'title': 'Products in Inventory',
            'value': inventoryList.length.toString(),
          },
          {'title': 'Total Units in Stock', 'value': totalUnits.toString()},
          {
            'title': 'Inventory Value (BOLD)',
            'value': _formatCurrencyPlain(invValue),
          },
        ]);
        break;
      case 'purchase':
        metrics.addAll([
          {
            'title': 'Total Purchases',
            'value': (data['filteredPurchases'] as List).length.toString(),
          },
          {
            'title': 'Total Purchase Value',
            'value': _formatCurrencyPlain(data['purchaseTotal'] as double),
          },
          {
            'title': 'Avg Purchase',
            'value': _formatCurrencyPlain(
              (data['filteredPurchases'] as List).isNotEmpty
                  ? (data['purchaseTotal'] as double) /
                        (data['filteredPurchases'] as List).length
                  : 0,
            ),
          },
        ]);
        break;
      case 'financial':
        // Recompute fresh to avoid stale keys
        final net = AccountingService.computeNetSummary(
          allSales: _sales,
          allPurchases: _purchases,
          products: _products,
          replacements: _replacements,
          returnsList: _returns,
          period: range,
        );
        final fifo = AccountingService.computeFifoSummary(
          allSales: _sales,
          allPurchases: _purchases,
          products: _products,
          period: range,
        );
        // Profit breakdown removed from export
        final grossRevenue = net.grossRevenue;
        final netRevenue = net.netRevenue;
        final netProfit = net.netProfit;
        final refunds = net.refunds;
        final warrantyLoss = net.warrantyLoss;
        final priceDiff = net.priceDifference;
        final returnsProfitReversal = net.returnsProfitReversal;
        final fifoGrossProfit = fifo.grossProfit;
        metrics.addAll([
          {
            'title': 'Gross Sales Revenue',
            'value': _formatCurrencyPlain(grossRevenue),
          },
          {
            'title': 'Refunds (Returns)',
            'value': '- ${_formatCurrencyPlain(refunds)}',
          },
          {
            'title': 'Replacement Price Adj.',
            'value':
                '${priceDiff >= 0 ? '+ ' : ''}${_formatCurrencyPlain(priceDiff)}',
          },
          {'title': '============================', 'value': ''},
          {'title': 'Net Revenue', 'value': _formatCurrencyPlain(netRevenue)},
          {'title': '', 'value': ''},
          {
            'title': 'FIFO Gross Profit',
            'value': _formatCurrencyPlain(fifoGrossProfit),
          },
          {
            'title': 'Return Profit Reversal',
            'value': '- ${_formatCurrencyPlain(returnsProfitReversal)}',
          },
          {
            'title': 'Warranty Loss',
            'value': '- ${_formatCurrencyPlain(warrantyLoss)}',
          },
          {
            'title': 'Replacement Price Adj.',
            'value':
                '${priceDiff >= 0 ? '+ ' : ''}${_formatCurrencyPlain(priceDiff)}',
          },
          {'title': '============================', 'value': ''},
          {
            'title': 'Net Profit (BOLD)',
            'value': _formatCurrencyPlain(netProfit),
          },
          {
            'title': 'Net Margin',
            'value':
                '${netRevenue > 0 ? ((netProfit / netRevenue) * 100).toStringAsFixed(1) : '0.0'}%',
          },
        ]);
        // No breakdown items in export
        break;
    }

    // Optional product-wise table for Sales reports
    String? tableTitle;
    List<String>? tableHeaders;
    List<List<String>>? tableRows;

    if (type == 'sales') {
      final List<Sale> filteredSales = (data['filteredSales'] as List)
          .cast<Sale>();
      bool inRange(DateTime? dt) {
        if (dt == null) return false;
        return dt.isAfter(range.start.subtract(const Duration(days: 1))) &&
            dt.isBefore(range.end.add(const Duration(days: 1)));
      }

      // Build return/replace maps for the same period
      final Map<int, int> returnedQtyByProduct = {};
      final Map<int, String> returnedBestCondition = {};
      final Map<int, int> replacedQtyByProduct = {};

      for (final ret in _returns) {
        final createdAtStr = ret['created_at'] as String?;
        final createdAt = createdAtStr != null
            ? DateTime.tryParse(createdAtStr)
            : null;
        if (!inRange(createdAt)) continue;
        final items = (ret['return_items'] as List?) ?? const [];
        for (final it in items) {
          final pid =
              (it['product_id'] as num?)?.toInt() ??
              (it['products'] is Map
                  ? (it['products']['id'] as num?)?.toInt()
                  : null);
          if (pid == null) continue;
          final qty = (it['quantity_returned'] as num?)?.toInt() ?? 1;
          returnedQtyByProduct[pid] = (returnedQtyByProduct[pid] ?? 0) + qty;
          final cond = (it['item_condition'] as String?)?.trim();
          if (cond != null && cond.isNotEmpty) {
            final existing = returnedBestCondition[pid];
            if (existing == null || existing.toLowerCase() != 'excellent') {
              returnedBestCondition[pid] = cond;
            }
          }
        }
      }

      for (final rep in _replacements) {
        final createdAtStr = rep['created_at'] as String?;
        final createdAt = createdAtStr != null
            ? DateTime.tryParse(createdAtStr)
            : null;
        if (!inRange(createdAt)) continue;
        final itemsIn = (rep['replacement_items_in'] as List?) ?? const [];
        for (final it in itemsIn) {
          final pid =
              (it['product_id'] as num?)?.toInt() ??
              (it['products'] is Map
                  ? (it['products']['id'] as num?)?.toInt()
                  : null);
          if (pid == null) continue;
          final qty = (it['quantity_given'] as num?)?.toInt() ?? 1;
          replacedQtyByProduct[pid] = (replacedQtyByProduct[pid] ?? 0) + qty;
        }
      }

      supabase_models.Product? findProduct(int productId) {
        try {
          return _products.firstWhere((p) => p.id == productId);
        } catch (_) {
          return null;
        }
      }

      tableTitle = 'Product-wise Sales (within period)';
      tableHeaders = const [
        'SNO',
        'Product Name',
        'Size/Spec',
        'Qty',
        'Unit Price',
        'Total',
        'Date',
        'Status',
      ];
      tableRows = <List<String>>[];

      int sno = 1;
      for (final sale in filteredSales) {
        final date = sale.createdAt ?? sale.saleDate;
        final double saleDiscount = sale.discountAmount ?? 0.0;
        final double grossSum = sale.salesItems.fold<double>(
          0.0,
          (sum, it) => sum + (it.quantity * it.pricePerUnit),
        );
        for (final item in sale.salesItems) {
          final prod = findProduct(item.productId);
          final name =
              item.product?.name ?? prod?.name ?? 'Product #${item.productId}';
          final size = prod?.sizeOrSpec ?? '-';
          final qty = item.quantity;
          final rawUnitPrice = item.pricePerUnit;
          final rawAmount = qty * rawUnitPrice;
          final lineDiscount = grossSum > 0
              ? (saleDiscount * (rawAmount / grossSum))
              : 0.0;
          double netAmount = rawAmount - lineDiscount;
          if (netAmount < 0) netAmount = 0.0;
          final effectiveUnitPrice = qty > 0 ? netAmount / qty : 0.0;
          final retQty = returnedQtyByProduct[item.productId] ?? 0;
          final repQty = replacedQtyByProduct[item.productId] ?? 0;
          String status = '—';
          if (repQty > 0) {
            status = 'Replaced $repQty';
          } else if (retQty > 0) {
            final cond = returnedBestCondition[item.productId];
            status = cond != null && cond.isNotEmpty
                ? 'Returned $retQty ($cond)'
                : 'Returned $retQty';
          }

          tableRows.add([
            '${sno++}',
            name,
            size,
            '$qty',
            _formatCurrencyPlain(effectiveUnitPrice),
            _formatCurrencyPlain(netAmount),
            date != null ? _formatDateTime(date) : '-',
            status,
          ]);
        }
      }
    } else if (type == 'inventory') {
      final Set<int> purchasedIds = {
        for (final p in _purchases)
          ...p.purchaseItems.map((it) => it.productId),
      };
      final inventoryList = _products
          .where(
            (p) =>
                (p.id != null &&
                purchasedIds.contains(p.id!) &&
                p.currentStock > 0),
          )
          .toList();
      final unitCostByProduct = _computeUnitCostMapForRange(range);

      tableTitle = 'Current Inventory (purchased products)';
      tableHeaders = const [
        'SNO',
        'Product Name',
        'Size/Spec',
        'Qty',
        'Unit Price',
        'Total',
        'Date',
        'Status',
      ];
      tableRows = <List<String>>[];

      int sno = 1;
      for (final p in inventoryList) {
        final name = p.name;
        final size = p.sizeOrSpec ?? '-';
        final qty = p.currentStock;
        final unitPrice =
            (p.id != null
                ? (unitCostByProduct[p.id!] ?? p.purchasePrice)
                : p.purchasePrice) ??
            0.0;
        final total = unitPrice * qty;
        tableRows.add([
          '${sno++}',
          name,
          size,
          '$qty',
          _formatCurrencyPlain(unitPrice),
          _formatCurrencyPlain(total),
          '—',
          '—',
        ]);
      }
    } else if (type == 'purchase') {
      final List<Purchase> filteredPurchases =
          (data['filteredPurchases'] as List).cast<Purchase>();

      supabase_models.Product? findProduct(int productId) {
        try {
          return _products.firstWhere((p) => p.id == productId);
        } catch (_) {
          return null;
        }
      }

      tableTitle = 'Product-wise Purchases (within period)';
      tableHeaders = const [
        'SNO',
        'Product Name',
        'Size/Spec',
        'Qty',
        'Unit Price',
        'Total',
        'Date',
        'Status',
      ];
      tableRows = <List<String>>[];

      int sno = 1;
      for (final p in filteredPurchases) {
        final date = p.createdAt ?? p.purchaseDate;
        final double disc = p.discountAmount ?? 0.0;
        final double gross = p.purchaseItems.fold<double>(
          0.0,
          (sum, it) => sum + (it.quantity * it.pricePerUnit),
        );
        for (final it in p.purchaseItems) {
          final prod = findProduct(it.productId);
          final name =
              it.product?.name ?? prod?.name ?? 'Product #${it.productId}';
          final size = prod?.sizeOrSpec ?? '-';
          final qty = it.quantity;
          final rawAmount = qty * it.pricePerUnit;
          final lineDisc = gross > 0 ? (disc * (rawAmount / gross)) : 0.0;
          double netAmount = rawAmount - lineDisc;
          if (netAmount < 0) netAmount = 0.0;
          final effectiveUnitPrice = qty > 0 ? netAmount / qty : 0.0;

          tableRows.add([
            '${sno++}',
            name,
            size,
            '$qty',
            _formatCurrencyPlain(effectiveUnitPrice),
            _formatCurrencyPlain(netAmount),
            date != null ? _formatDateTime(date) : '-',
            '—',
          ]);
        }
      }
    }

    await ReportPdfService.generateAndPrintReport(
      title: title,
      description: description,
      periodLabel: periodLabel,
      metrics: metrics,
      itemsTitle: itemsTitle,
      items: items,
      tableTitle: tableTitle,
      tableHeaders: tableHeaders,
      tableRows: tableRows,
    );
  }

  Future<void> _exportReportQuick(Map<String, dynamic> report) async {
    final range = _getPeriodRange();
    final type = (report['type'] as String).toLowerCase();
    final filteredSales = _sales.where((s) {
      final createdAt = s.createdAt ?? s.saleDate;
      if (createdAt == null) return false;
      return createdAt.isAfter(range.start.subtract(const Duration(days: 1))) &&
          createdAt.isBefore(range.end.add(const Duration(days: 1)));
    }).toList();
    final filteredPurchases = _purchases.where((p) {
      final createdAt = p.createdAt ?? p.purchaseDate;
      if (createdAt == null) return false;
      return createdAt.isAfter(range.start.subtract(const Duration(days: 1))) &&
          createdAt.isBefore(range.end.add(const Duration(days: 1)));
    }).toList();

    final netSummary = AccountingService.computeNetSummary(
      allSales: _sales,
      allPurchases: _purchases,
      products: _products,
      replacements: _replacements,
      returnsList: _returns,
      period: range,
    );
    final revenue = netSummary.netRevenue;
    final profit = netSummary.netProfit;
    final orders = filteredSales.length;
    final avgOrder = orders > 0 ? revenue / orders : 0.0;
    final purchaseTotal = filteredPurchases.fold<double>(
      0.0,
      (sum, p) => sum + p.totalAmount,
    );
    final uniqueCustomers = filteredSales
        .map((s) => (s.customerName ?? '').trim())
        .where((name) => name.isNotEmpty)
        .toSet()
        .length;

    final data = <String, dynamic>{
      'grossRevenue': netSummary.grossRevenue,
      'netRevenue': revenue,
      'netProfit': profit,
      'refunds': netSummary.refunds,
      'priceDifference': netSummary.priceDifference,
      'warrantyLoss': netSummary.warrantyLoss,
      'returnsProfitReversal': netSummary.returnsProfitReversal,
      'fifoGrossProfit': netSummary.fifoGrossProfit,
      'orders': orders,
      'avgOrder': avgOrder,
      'purchaseTotal': purchaseTotal,
      'uniqueCustomers': uniqueCustomers,
      'filteredSales': filteredSales,
      'filteredPurchases': filteredPurchases,
      'type': type,
    };

    await _exportReport(report, data, range);
  }

  Widget _buildReportChart(
    String type,
    dynamic netSummary,
    double revenue,
    double profit,
    int orders,
    List filteredSales,
    List filteredPurchases,
  ) {
    if (type == 'financial') {
      return _buildFinancialSummaryChart(
        netSummary.netRevenue,
        netSummary.grossRevenue - netSummary.netRevenue,
        netSummary.netProfit,
      );
    } else if (type == 'sales') {
      return _buildSalesChart(revenue, orders, filteredSales);
    } else if (type == 'inventory') {
      return _buildInventoryChart();
    } else if (type == 'purchase') {
      return _buildPurchaseChart(filteredPurchases);
    } else if (type == 'customer') {
      return _buildCustomerChart(filteredSales);
    }
    // Fallback
    return Container(
      width: double.infinity,
      height: 200,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.insert_chart,
              size: 48,
              color: Theme.of(
                context,
              ).textTheme.bodyMedium?.color?.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 8),
            Text(
              'Report Chart Preview',
              style: TextStyle(
                color: Theme.of(
                  context,
                ).textTheme.bodyMedium?.color?.withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSalesChart(double revenue, int orders, List sales) {
    final cs = Theme.of(context).colorScheme;
    final avgOrder = orders > 0 ? revenue / orders : 0.0;

    return _buildSimpleBarChart('Sales Overview', [
      {'label': 'Revenue', 'value': revenue, 'color': cs.primary},
      {
        'label': 'Orders',
        'value': orders.toDouble() * 10,
        'color': cs.secondary,
      },
      {'label': 'Avg Order', 'value': avgOrder, 'color': cs.tertiary},
    ]);
  }

  Widget _buildInventoryChart() {
    final lowStock = _products.where((p) => p.currentStock <= 5).length;
    final outOfStock = _products.where((p) => p.currentStock == 0).length;
    final inStock = _products.length - lowStock;
    final cs = Theme.of(context).colorScheme;

    return _buildSimpleBarChart('Inventory Status', [
      {'label': 'In Stock', 'value': inStock.toDouble(), 'color': Colors.green},
      {
        'label': 'Low Stock',
        'value': lowStock.toDouble(),
        'color': Colors.orange,
      },
      {
        'label': 'Out of Stock',
        'value': outOfStock.toDouble(),
        'color': cs.error,
      },
    ]);
  }

  Widget _buildPurchaseChart(List purchases) {
    final total = purchases.fold<double>(
      0.0,
      (sum, p) => sum + (p.totalAmount ?? 0.0),
    );
    final avg = purchases.isNotEmpty ? total / purchases.length : 0.0;
    final cs = Theme.of(context).colorScheme;

    return _buildSimpleBarChart('Purchase Analysis', [
      {'label': 'Total Value', 'value': total, 'color': cs.primary},
      {
        'label': 'Count',
        'value': purchases.length.toDouble() * 10,
        'color': cs.secondary,
      },
      {'label': 'Avg Purchase', 'value': avg, 'color': cs.tertiary},
    ]);
  }

  Widget _buildCustomerChart(List sales) {
    final uniqueCustomers = sales
        .map((s) => (s.customerName ?? '').trim())
        .where((name) => name.isNotEmpty)
        .toSet()
        .length;
    final totalOrders = sales.length;
    final ordersPerCustomer = uniqueCustomers > 0
        ? totalOrders / uniqueCustomers
        : 0.0;
    final cs = Theme.of(context).colorScheme;

    return _buildSimpleBarChart('Customer Analysis', [
      {
        'label': 'Customers',
        'value': uniqueCustomers.toDouble() * 5,
        'color': cs.primary,
      },
      {
        'label': 'Orders',
        'value': totalOrders.toDouble(),
        'color': cs.secondary,
      },
      {
        'label': 'Orders/Customer',
        'value': ordersPerCustomer * 10,
        'color': cs.tertiary,
      },
    ]);
  }

  Widget _buildSimpleBarChart(
    String title,
    List<Map<String, dynamic>> chartData,
  ) {
    final maxVal = chartData.fold<double>(0.0, (max, item) {
      final val = (item['value'] as double).abs();
      return val > max ? val : max;
    });
    final yMax = (maxVal == 0 ? 10.0 : maxVal) * 1.2;

    return Container(
      width: double.infinity,
      height: 220,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: Theme.of(context).textTheme.titleMedium?.color,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: BarChart(
              BarChartData(
                maxY: yMax,
                gridData: FlGridData(show: true, drawVerticalLine: false),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        if (idx >= 0 && idx < chartData.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              chartData[idx]['label'] as String,
                              style: TextStyle(
                                fontSize: 10,
                                color: Theme.of(
                                  context,
                                ).textTheme.bodySmall?.color,
                              ),
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: (value, meta) => Text(
                        value.toStringAsFixed(0),
                        style: TextStyle(
                          fontSize: 9,
                          color: Theme.of(context).textTheme.bodySmall?.color,
                        ),
                      ),
                    ),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                borderData: FlBorderData(show: false),
                barGroups: chartData.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final map = entry.value;
                  return BarChartGroupData(
                    x: idx,
                    barRods: [
                      BarChartRodData(
                        toY: (map['value'] as double).abs(),
                        color: (map['color'] as Color).withValues(alpha: 0.85),
                        width: 18,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(4),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFinancialSummaryChart(
    double revenue,
    double adjustments,
    double profit,
  ) {
    final cs = Theme.of(context).colorScheme;
    final maxVal = [
      revenue.abs(),
      adjustments.abs(),
      profit.abs(),
    ].fold<double>(0.0, (a, b) => a > b ? a : b);
    final yMax = (maxVal == 0 ? 100.0 : maxVal) * 1.2;

    String label(double v) {
      if (yMax < 1000) return '₹${v.toStringAsFixed(0)}';
      if (yMax < 100000) return '₹${(v / 1000).toStringAsFixed(0)}k';
      if (yMax < 10000000) return '₹${(v / 100000).toStringAsFixed(1)}L';
      return '₹${(v / 10000000).toStringAsFixed(1)}Cr';
    }

    final data = [
      {'label': 'Net Revenue', 'value': revenue, 'color': cs.primary},
      {'label': 'Adjustments', 'value': adjustments.abs(), 'color': cs.error},
      {'label': 'Net Profit', 'value': profit, 'color': cs.secondary},
    ];

    return Container(
      width: double.infinity,
      height: 220,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Financial Summary Chart',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: Theme.of(context).textTheme.titleMedium?.color,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 160,
            child: BarChart(
              BarChartData(
                maxY: yMax,
                gridData: FlGridData(show: true),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        if (idx >= 0 && idx < data.length) {
                          return Text(
                            data[idx]['label'] as String,
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(
                                context,
                              ).textTheme.bodySmall?.color,
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 48,
                      getTitlesWidget: (value, meta) => Text(
                        label(value),
                        style: TextStyle(
                          fontSize: 10,
                          color: Theme.of(context).textTheme.bodySmall?.color,
                        ),
                      ),
                    ),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                borderData: FlBorderData(show: false),
                barGroups: data.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final map = entry.value;
                  return BarChartGroupData(
                    x: idx,
                    barRods: [
                      BarChartRodData(
                        toY: (map['value'] as double),
                        color: (map['color'] as Color).withValues(alpha: 0.9),
                        width: 22,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(4),
                          topRight: Radius.circular(4),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
