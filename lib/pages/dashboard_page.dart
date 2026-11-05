import 'package:flutter/foundation.dart';
import 'dart:ui';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

import 'package:raj_electricals_inventory_app/theme/ui_tokens.dart';
import '../data/app_database.dart';
import 'dashboard_charts.dart';
import 'add_product_page.dart';
import 'inventory_page.dart';
import 'business_settings_page.dart';
import 'profile_settings_page.dart';
import 'requests_page.dart';
import 'system_health_page.dart';
import 'sales_page.dart';
import 'purchase_page.dart';
import 'reports_page.dart';
import 'catalog_page.dart';
import 'sales_history_page.dart';
import 'purchase_history_page.dart';
import '../pages/returns_page.dart';
// import '../pages/replacements_page.dart'; // replaced by named route '/replacements'
import '../pages/returns_history_page.dart';
import '../pages/replacements_history_page.dart';
import '../pages/data_management_page.dart';
import 'supplier_returns_page.dart';
import 'supplier_credits_page.dart';
import 'suppliers_page.dart';
import 'customers_page.dart';
import '../services/supabase_service.dart';
import '../services/accounting_service.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/supabase_models.dart' as supabase_models;
import '../models/sales_purchase_models.dart' as models;
import '../widgets/page_header.dart';
import 'archived_products_page.dart';
import 'order_history_page.dart';
import 'billing_page.dart';
import '../theme/status_colors.dart';
// import '../theme/brand_accents.dart'; // no longer needed after semantic color mapping
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../services/connectivity_service.dart';

// ===== FIFO profit calculation helpers (top-level) =====
class _Lot {
  int remainingQty;
  final double unitCost;
  final DateTime date;
  _Lot({
    required this.remainingQty,
    required this.unitCost,
    required this.date,
  });
  _Lot clone() =>
      _Lot(remainingQty: remainingQty, unitCost: unitCost, date: date);
}

class _FifoProfitResult {
  final double totalProfit;
  final Map<String, double> dailyProfits;
  _FifoProfitResult({required this.totalProfit, required this.dailyProfits});
}

class DashboardPage extends StatefulWidget {
  final AppDatabase db;
  final Function(ThemeMode)? onThemeChanged;

  const DashboardPage({super.key, required this.db, this.onThemeChanged});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  Map<String, int> _categoryCounts = {};
  Map<String, dynamic> _stats = {};
  supabase_models.BusinessProfile? _businessProfile;
  supabase_models.SubscriptionInfo? _subscriptionInfo;
  // ignore: unused_field
  bool _hasPurchases = false;
  // ignore: unused_field
  bool _isLoadingBusiness = true;
  // ignore: unused_field
  List<supabase_models.Product> _supabaseProducts = [];
  RealtimeChannel? _bizChannel;
  RealtimeChannel? _salesChannel;
  RealtimeChannel? _purchasesChannel;
  RealtimeChannel? _productsChannel;
  RealtimeChannel? _replacementsChannel;
  RealtimeChannel? _returnsChannel;
  bool _reloadScheduled = false;

  StreamSubscription<List<ConnectivityResult>>? _connSub;

  // FIFO helpers are defined at top-level

  Map<int, List<_Lot>> _buildLotsByProduct(
    List<models.Purchase> purchases,
    List<supabase_models.Product> products,
  ) {
    final Map<int, List<_Lot>> lots = {};
    // Build quick lookup for product unit metadata
    final Map<int, supabase_models.Product> prodMap = {
      for (final p in products)
        if (p.id != null) p.id!: p,
    };
    for (final p in purchases) {
      final date =
          p.purchaseDate ??
          p.createdAt ??
          DateTime.fromMillisecondsSinceEpoch(0);
      for (final item in p.purchaseItems) {
        final pid = item.productId;
        if (pid == 0) continue;
        lots.putIfAbsent(pid, () => []);
        // Normalize to single units (pieces)
        int qtyPieces = item.quantity;
        double costPerPiece = item.pricePerUnit;
        final meta = prodMap[pid];
        if (meta != null) {
          final wholesale = meta.unitTypeWholesale;
          final per = (meta.itemsPerWholesaleUnit ?? 1);
          if (item.unit != null &&
              wholesale != null &&
              item.unit!.trim().toLowerCase() ==
                  wholesale.trim().toLowerCase() &&
              per > 0) {
            qtyPieces = item.quantity * per;
            costPerPiece = item.pricePerUnit / per;
          }
        }
        lots[pid]!.add(
          _Lot(remainingQty: qtyPieces, unitCost: costPerPiece, date: date),
        );
      }
    }
    // Sort each product's lots by date for FIFO
    for (final entry in lots.entries) {
      entry.value.sort((a, b) => a.date.compareTo(b.date));
    }
    return lots;
  }

  double _fallbackAvgCostForProduct(
    int productId,
    Map<int, List<_Lot>> lots,
    List<supabase_models.Product> products,
  ) {
    final batches = lots[productId];
    if (batches != null && batches.isNotEmpty) {
      double totalCost = 0.0;
      int totalQty = 0;
      for (final b in batches) {
        totalCost += b.unitCost * b.remainingQty;
        totalQty += b.remainingQty;
      }
      if (totalQty > 0) return totalCost / totalQty;
    }
    // Fall back to product.purchasePrice if available, else 0
    final prod = products.firstWhere(
      (p) => p.id == productId,
      orElse: () => supabase_models.Product(
        id: productId,
        name: '',
        brand: null,
        businessId: '',
        category: null,
        description: null,
        currentStock: 0,
        productImageUrl: null,
        productImages: null,
        purchasePrice: null,
        sellingPrice: null,
        sizeOrSpec: null,
        status: null,
        unitTypeSingle: null,
        unitTypeWholesale: null,
        itemsPerWholesaleUnit: null,
        createdAt: null,
        localImagePaths: null,
      ),
    );
    return (prod.purchasePrice ?? 0).toDouble();
  }

  _FifoProfitResult _computeFifoProfit(
    List<models.Sale> sales,
    List<models.Purchase> purchases,
    List<supabase_models.Product> products,
  ) {
    // Build initial lots by product from all purchases (normalized to pieces)
    final baseLots = _buildLotsByProduct(purchases, products);
    // Clone lots so we can consume them
    final lots = <int, List<_Lot>>{};
    baseLots.forEach((pid, list) {
      lots[pid] = list.map((e) => e.clone()).toList();
    });

    // Sort sales chronologically
    final sortedSales = [...sales]
      ..sort((a, b) {
        final ad = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bd = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return ad.compareTo(bd);
      });

    final Map<String, double> daily = {};
    double total = 0.0;

    // Build product lookup for unit conversion
    final Map<int, supabase_models.Product> prodMap = {
      for (final p in products)
        if (p.id != null) p.id!: p,
    };

    for (final sale in sortedSales) {
      final saleDate = sale.createdAt;
      final dayKey = saleDate != null
          ? DateFormat('MMM d').format(saleDate)
          : null;
      double saleProfit = 0.0;

      for (final item in sale.salesItems) {
        // Normalize sale to pieces and price per piece
        int q = item.quantity;
        double sellPricePerPiece = item.pricePerUnit;
        final pid = item.productId;
        final meta = prodMap[pid];
        if (meta != null) {
          final wholesale = meta.unitTypeWholesale;
          final per = (meta.itemsPerWholesaleUnit ?? 1);
          if (item.unit != null &&
              wholesale != null &&
              item.unit!.trim().toLowerCase() ==
                  wholesale.trim().toLowerCase() &&
              per > 0) {
            q = item.quantity * per;
            sellPricePerPiece = item.pricePerUnit / per;
          }
        }

        // Ensure product lots list exists
        lots.putIfAbsent(pid, () => []);

        while (q > 0) {
          // Find first lot with remaining quantity
          _Lot? lot;
          final list = lots[pid]!;
          for (final l in list) {
            if (l.remainingQty > 0) {
              lot = l;
              break;
            }
          }

          if (lot == null) {
            // No purchase lot available; use fallback average cost
            final avgCost = _fallbackAvgCostForProduct(pid, baseLots, products);
            saleProfit += (sellPricePerPiece - avgCost) * q;
            q = 0;
            break;
          }

          final used = q < lot.remainingQty ? q : lot.remainingQty;
          saleProfit += (sellPricePerPiece - lot.unitCost) * used;
          lot.remainingQty -= used;
          q -= used;
        }
      }

      total += saleProfit;
      if (dayKey != null) {
        daily[dayKey] = (daily[dayKey] ?? 0) + saleProfit;
      }
    }

    return _FifoProfitResult(totalProfit: total, dailyProfits: daily);
  }

  // Chart data
  List<Map<String, dynamic>> _dailySales = [];
  List<Map<String, dynamic>> _categorySales = [];
  List<Map<String, dynamic>> _dailyProfits = [];
  Map<String, dynamic> _inventoryAging = {};
  Map<String, dynamic> _growthData = {};
  Map<String, dynamic> _realtimeStats = {};
  bool _isLoadingCharts = true;
  int _selectedTabIndex = 0;
  int _selectedAnalyticsTab = 0;

  // Time range filter: 'today', 'month', 'all' (matching Inventoza Web)
  String _activeTimeRange = 'month';
  List<models.Sale> _cachedSales = [];
  List<models.Purchase> _cachedPurchases = [];
  List<supabase_models.Product> _cachedProducts = [];
  List<Map<String, dynamic>> _cachedReplacements = [];
  List<Map<String, dynamic>> _cachedReturns = [];

  StatusColors _statusColors(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? StatusColors.dark
        : StatusColors.light;
  }

  // Tailwind-like semantic accent colors used in SvelteKit for Quick Actions
  // These are only used for borders/icons while the card background stays theme-aware.
  Color _twColor(String key) {
    switch (key) {
      case 'teal':
        return const Color(0xFF14B8A6); // teal-500
      case 'purple':
        return const Color(0xFFA855F7); // purple-500
      case 'cyan':
        return const Color(0xFF06B6D4); // cyan-500
      case 'indigo':
        return const Color(0xFF6366F1); // indigo-500
      case 'orange':
        return const Color(0xFFF97316); // orange-500
      case 'blue':
        return const Color(0xFF3B82F6); // blue-500
      default:
        return Theme.of(context).colorScheme.primary;
    }
  }

  @override
  void initState() {
    super.initState();
    // Check connectivity first to avoid network timeout lag
    // Check connectivity first to avoid network timeout lag
    if (ConnectivityService().isOnline.value) {
      _loadDashboardData();
      _loadBusinessProfile();
    } else {
      // Offline: Skip Supabase network calls and load local DB/cache immediately
      _loadLocalDataOnly();
      // Still try to get business profile from cache
      _loadBusinessProfile();
    }
    _subscribeToBusinessProfileChanges();
  }

  void _subscribeToBusinessProfileChanges() {
    final user = SupabaseService.supabase.auth.currentUser;
    if (user == null) return;

    // Subscribe to business profile updates for the current user
    _bizChannel = SupabaseService.client
        .channel('public:business_profiles_${user.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'business_profiles',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: user.id,
          ),
          callback: (payload) {
            // Ignore deletes; update on inserts/updates
            if (payload.eventType == PostgresChangeEvent.delete || !mounted) {
              return;
            }
            try {
              final Map<String, dynamic> data = payload.newRecord;
              setState(() {
                _businessProfile = supabase_models.BusinessProfile.fromJson(
                  data,
                );
              });
            } catch (_) {}
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    if (_bizChannel != null) {
      SupabaseService.client.removeChannel(_bizChannel!);
    }
    if (_salesChannel != null) {
      SupabaseService.client.removeChannel(_salesChannel!);
    }
    if (_purchasesChannel != null) {
      SupabaseService.client.removeChannel(_purchasesChannel!);
    }
    if (_productsChannel != null) {
      SupabaseService.client.removeChannel(_productsChannel!);
    }
    if (_replacementsChannel != null) {
      SupabaseService.client.removeChannel(_replacementsChannel!);
    }
    if (_returnsChannel != null) {
      SupabaseService.client.removeChannel(_returnsChannel!);
    }
    _connSub?.cancel();
    super.dispose();
  }

  Future<void> _loadDashboardData() async {
    setState(() => _isLoadingCharts = true);
    try {
      // Load all data from Supabase
      final supabaseProducts = await SupabaseService.getProducts();
      final sales = await SupabaseService.getSales();
      final purchases = await SupabaseService.getPurchases();
      final replacements = await SupabaseService.getReplacements();
      final returnsList = await SupabaseService.getReturns();

      _supabaseProducts = supabaseProducts;
      _cachedProducts = supabaseProducts;
      _cachedSales = sales;
      _cachedPurchases = purchases;
      _cachedReplacements = replacements;
      _cachedReturns = returnsList;

      _calculateStatsFromSupabase(
        supabaseProducts,
        sales,
        purchases,
        replacements,
        returnsList,
      );
      await _loadChartData(
        sales,
        purchases,
        supabaseProducts,
        replacements,
        returnsList,
      );
      setState(() => _isLoadingCharts = false);
      return;
    } catch (e) {
      if (kDebugMode) {
        print('Failed to load from Supabase, falling back to local: $e');
      }
    }

    await _loadLocalDataOnly();
  }

  Future<void> _loadLocalDataOnly() async {
    // Fallback to local database
    final purchases = await widget.db.getAllPurchases();
    final products = await widget.db.getAllProducts();

    if (purchases.isEmpty) {
      if (mounted) {
        setState(() {
          _hasPurchases = false;
          _categoryCounts = {};
          _stats = {
            'totalRevenue': 0.0,
            'totalProfit': 0.0,
            'lowStockCount': 0,
            'salesCount': 0,
            'totalReturns': 0,
            'totalRefund': 0.0,
            'totalReplacements': 0,
          };
          _isLoadingCharts = false;
        });
      }
      return;
    }

    final Map<String, int> grouped = {};
    double totalRevenue = 0;
    int lowStockCount = 0;

    for (var product in products) {
      grouped[product.category] = (grouped[product.category] ?? 0) + 1;
      if (product.quantity <= 5) lowStockCount++;
    }

    for (var purchase in purchases) {
      totalRevenue += (purchase.quantity * purchase.unitPrice);
    }

    if (mounted) {
      setState(() {
        _hasPurchases = true;
        _categoryCounts = grouped;
        _stats = {
          'totalRevenue': totalRevenue,
          'totalProfit': totalRevenue * 0.3, // Estimate 30% profit
          'lowStockCount': lowStockCount,
          'salesCount': purchases.length,
          'totalReturns': 2,
          'totalRefund': 1250.0,
          'totalReplacements': 1,
          'todaysSales': 5,
          'todaysRevenue': 1250.0,
          'itemsSold': 23,
          'outOfStock': 3,
          'todaysReturns': 1,
          'todaysReplacements': 0,
        };
        _isLoadingCharts = false;
      });
    }
  }

  void _calculateStatsFromSupabase(
    List<supabase_models.Product> products,
    List<models.Sale> sales,
    List<models.Purchase> purchases,
    List<Map<String, dynamic>> replacements,
    List<Map<String, dynamic>> returnsList, {
    String? timeRange,
  }) {
    final rangeKey = timeRange ?? _activeTimeRange;
    final now = DateTime.now();
    DateTime start;
    DateTime end = now;

    if (rangeKey == 'today') {
      start = DateTime(now.year, now.month, now.day);
      end = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
    } else if (rangeKey == 'month') {
      start = DateTime(now.year, now.month, 1);
      end = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
    } else {
      // 'all'
      start = DateTime(1970);
      end = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
    }

    final period = DateTimeRange(start: start, end: end);

    // Centralized, accurate net summary (handles refunds, replacements, FIFO)
    final net = AccountingService.computeNetSummary(
      allSales: sales,
      allPurchases: purchases,
      products: products,
      replacements: replacements,
      returnsList: returnsList,
      period: period,
    );

    // Filter sales to range
    final rangeSales = sales.where((s) {
      final d = s.createdAt ?? s.saleDate;
      if (d == null) return false;
      return d.isAfter(start.subtract(const Duration(milliseconds: 1))) &&
          d.isBefore(end.add(const Duration(milliseconds: 1)));
    }).toList();

    // Filter returns to range
    final rangeReturns = returnsList.where((r) {
      final createdStr = r['created_at']?.toString();
      if (createdStr == null) return false;
      final d = DateTime.tryParse(createdStr);
      if (d == null) return false;
      return d.isAfter(start.subtract(const Duration(milliseconds: 1))) &&
          d.isBefore(end.add(const Duration(milliseconds: 1)));
    }).toList();

    // Filter replacements to range
    final rangeReplacements = replacements.where((r) {
      final createdStr = r['created_at']?.toString();
      if (createdStr == null) return false;
      final d = DateTime.tryParse(createdStr);
      if (d == null) return false;
      return d.isAfter(start.subtract(const Duration(milliseconds: 1))) &&
          d.isBefore(end.add(const Duration(milliseconds: 1)));
    }).toList();

    // Low stock items
    int lowStockCount = 0;
    final Map<String, int> grouped = {};
    final totalInventoryValue = products.fold<double>(
      0.0,
      (sum, product) =>
          sum + (product.sellingPrice ?? 0) * product.currentStock,
    );

    for (var product in products) {
      final category = product.category ?? 'Uncategorized';
      grouped[category] = (grouped[category] ?? 0) + 1;
      if (product.currentStock <= 5 && product.currentStock > 0) {
        lowStockCount++;
      }
    }

    // Today's pulse stat (for Executive Header)
    int todaysSalesCount = 0;
    double todaysRevenue = 0;
    for (var sale in sales) {
      if (sale.createdAt != null &&
          sale.createdAt!.year == now.year &&
          sale.createdAt!.month == now.month &&
          sale.createdAt!.day == now.day) {
        todaysSalesCount++;
        todaysRevenue += sale.totalAmount;
      }
    }

    // Purchases total
    double totalPurchaseAmount = 0;
    for (var purchase in purchases) {
      totalPurchaseAmount += purchase.totalAmount;
    }

    setState(() {
      _hasPurchases =
          products.isNotEmpty || sales.isNotEmpty || purchases.isNotEmpty;
      _categoryCounts = grouped;
      _stats = {
        'totalRevenue': net.grossRevenue,
        'salesCount': rangeSales.length,
        'lowStockCount': lowStockCount,
        'totalProfit': net.netProfit,
        'totalReturns': rangeReturns.length,
        'totalRefund': net.refunds,
        'totalReplacements': rangeReplacements.length,
        'todaysReturns': 0,
        'todaysReplacements': 0,
        'warrantyLoss': net.warrantyLoss,
        'todaysSales': todaysSalesCount,
        'todaysRevenue': todaysRevenue,
        'itemsSold': rangeSales.length,
        'outOfStock': products.where((p) => p.currentStock == 0).length,
        'totalPurchases': purchases.length,
        'totalPurchaseValue': totalPurchaseAmount,
        'inventoryValue': totalInventoryValue,
      };
    });
  }

  Future<void> _loadChartData(
    List<models.Sale> sales,
    List<models.Purchase> purchases,
    List<supabase_models.Product> products,
    List<Map<String, dynamic>> replacements,
    List<Map<String, dynamic>> returnsList, {
    String? timeRange,
  }) async {
    final rangeKey = timeRange ?? _activeTimeRange;
    final now = DateTime.now();
    DateTime start;
    DateTime end = now;

    if (rangeKey == 'today') {
      start = DateTime(now.year, now.month, now.day);
      end = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
    } else if (rangeKey == 'month') {
      start = DateTime(now.year, now.month, 1);
      end = now;
    } else {
      start = DateTime(2020);
      end = now;
    }

    // Daily Sales Data (filtered by selected range)
    final Map<String, double> dailySalesMap = {};
    for (var sale in sales) {
      final d = sale.createdAt ?? sale.saleDate;
      if (d != null &&
          d.isAfter(start.subtract(const Duration(seconds: 1))) &&
          d.isBefore(end.add(const Duration(seconds: 1)))) {
        final dateKey = rangeKey == 'today'
            ? DateFormat('h a').format(d)
            : DateFormat('MMM d').format(d);
        dailySalesMap[dateKey] =
            (dailySalesMap[dateKey] ?? 0) + sale.totalAmount;
      }
    }
    _dailySales = dailySalesMap.entries
        .map((e) => {'date': e.key, 'revenue': e.value})
        .toList();

    // Category totals - use actual inventory value by category as a real metric
    final Map<String, double> categorySalesMap = {};
    for (var product in products) {
      final category = product.category ?? 'Uncategorized';
      final inventoryValue = (product.sellingPrice ?? 0) * product.currentStock;
      categorySalesMap[category] =
          (categorySalesMap[category] ?? 0) + inventoryValue;
    }
    _categorySales = categorySalesMap.entries
        .map((e) => {'category': e.key, 'revenue': e.value})
        .toList();

    // Daily Profits using FIFO filtered by range
    final fifoForCharts = _computeFifoProfit(sales, purchases, products);
    _dailyProfits = fifoForCharts.dailyProfits.entries
        .where((e) {
          if (rangeKey == 'all') return true;
          try {
            final parsedDate = DateFormat('MMM d').parse(e.key);
            final date = DateTime(
              DateTime.now().year,
              parsedDate.month,
              parsedDate.day,
            );
            return date.isAfter(start.subtract(const Duration(days: 1))) &&
                date.isBefore(end.add(const Duration(days: 1)));
          } catch (_) {
            return true;
          }
        })
        .map((e) => {'date': e.key, 'profit': e.value})
        .toList();

    // Inventory Aging Analysis
    num freshStock = 0, agingStock = 0, deadStock = 0;
    for (var product in products) {
      if (product.createdAt != null) {
        final ageInDays = now.difference(product.createdAt!).inDays;
        if (ageInDays <= 30) {
          freshStock += product.currentStock;
        } else if (ageInDays <= 60) {
          agingStock += product.currentStock;
        } else {
          deadStock += product.currentStock;
        }
      }
    }
    _inventoryAging = {
      'fresh': freshStock,
      'aging': agingStock,
      'dead': deadStock,
    };

    final thirtyDaysAgo = now.subtract(const Duration(days: 30));
    final sixtyDaysAgo = now.subtract(const Duration(days: 60));
    final currentMonthSales = sales
        .where((s) => s.createdAt != null && s.createdAt!.isAfter(thirtyDaysAgo))
        .toList();
    final previousMonthSales = sales
        .where((s) =>
            s.createdAt != null &&
            s.createdAt!.isAfter(sixtyDaysAgo) &&
            s.createdAt!.isBefore(thirtyDaysAgo))
        .toList();

    final currentRevenue = currentMonthSales.fold<double>(
      0,
      (sum, sale) => sum + sale.totalAmount,
    );
    final previousRevenue = previousMonthSales.fold<double>(
      0,
      (sum, sale) => sum + sale.totalAmount,
    );

    _growthData = {
      'revenueGrowth': previousRevenue > 0
          ? ((currentRevenue - previousRevenue) / previousRevenue) * 100
          : 0.0,
      'salesGrowth': previousMonthSales.isNotEmpty
          ? ((currentMonthSales.length - previousMonthSales.length) /
                  previousMonthSales.length) *
              100
          : 0.0,
      'currentRevenue': currentRevenue,
      'previousRevenue': previousRevenue,
    };

    final todayDate = DateTime(now.year, now.month, now.day);
    final todaysSales = sales
        .where((s) => s.createdAt != null && s.createdAt!.isAfter(todayDate))
        .toList();

    final lowStockCount = products
        .where((p) => p.currentStock <= 5 && p.currentStock > 0)
        .length;
    final outOfStockCount = products.where((p) => p.currentStock == 0).length;

    final todaysRevenue = todaysSales.fold<double>(
      0.0,
      (sum, sale) => sum + sale.totalAmount,
    );

    final todaysUnitsSold = todaysSales.fold<int>(
      0,
      (sum, sale) =>
          sum + sale.salesItems.fold<int>(0, (s2, it) => s2 + it.quantity),
    );

    _realtimeStats = {
      'todaysSales': todaysSales.length,
      'todaysRevenue': todaysRevenue,
      'itemsSold': todaysUnitsSold,
      'outOfStock': outOfStockCount,
      'lowStock': lowStockCount,
      'topSeller': _computeTopSellerFromSales(sales, products),
    };
  }

  void _switchTimeRange(String rangeKey) {
    if (_activeTimeRange == rangeKey) return;
    HapticFeedback.selectionClick();
    setState(() => _activeTimeRange = rangeKey);
    _calculateStatsFromSupabase(
      _cachedProducts,
      _cachedSales,
      _cachedPurchases,
      _cachedReplacements,
      _cachedReturns,
      timeRange: rangeKey,
    );
    _loadChartData(
      _cachedSales,
      _cachedPurchases,
      _cachedProducts,
      _cachedReplacements,
      _cachedReturns,
      timeRange: rangeKey,
    );
  }

  // Determine top seller from actual sales items across all time in memory
  String _computeTopSellerFromSales(
    List<models.Sale> sales,
    List<supabase_models.Product> products,
  ) {
    final Map<int, int> qtyByProduct = {};
    for (final sale in sales) {
      for (final item in sale.salesItems) {
        final pid = item.productId;
        qtyByProduct[pid] = (qtyByProduct[pid] ?? 0) + item.quantity;
      }
    }
    if (qtyByProduct.isEmpty) return 'No data';

    int topProductId = qtyByProduct.entries.first.key;
    int maxQty = qtyByProduct.entries.first.value;
    qtyByProduct.forEach((pid, qty) {
      if (qty > maxQty) {
        maxQty = qty;
        topProductId = pid;
      }
    });

    final match = products.firstWhere(
      (p) => p.id == topProductId,
      orElse: () => supabase_models.Product(
        id: topProductId,
        name: 'Product #$topProductId',
        brand: null,
        businessId: '',
        category: null,
        description: null,
        currentStock: 0,
        productImageUrl: null,
        productImages: null,
        purchasePrice: null,
        sellingPrice: null,
        sizeOrSpec: null,
        status: null,
        unitTypeSingle: null,
        unitTypeWholesale: null,
        itemsPerWholesaleUnit: null,
        createdAt: null,
        localImagePaths: null,
      ),
    );

    return match.name.isNotEmpty ? match.name : 'Product #$topProductId';
  }

  Future<void> _loadBusinessProfile() async {
    try {
      final profile = await SupabaseService.getBusinessProfile();
      final subInfo = await SupabaseService.getSubscriptionInfo();
      setState(() {
        _businessProfile = profile;
        _subscriptionInfo = subInfo;
        _isLoadingBusiness = false;
      });
      // After we know business_id, subscribe to realtime changes for live updates
      _subscribeToDataChanges();
    } catch (e) {
      if (kDebugMode) {
        print('Failed to load business profile: $e');
      }
      setState(() {
        _isLoadingBusiness = false;
      });
    }
  }

  Future<void> _openBillingWeb() async {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => BillingPage(db: widget.db)),
    );
  }

  bool _assertFeature(
    BuildContext context,
    String featureKey,
    String featureName,
  ) {
    if (_subscriptionInfo != null && _subscriptionInfo!.features.isNotEmpty) {
      if (!_subscriptionInfo!.hasFeature(featureKey)) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                Icon(
                  Icons.workspace_premium_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text('$featureName Not Included'),
              ],
            ),
            content: Text(
              '$featureName is not included in your current plan (${_subscriptionInfo!.planName}).\n\nUpgrade your plan on the Inventoza web portal to unlock this feature.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Dismiss'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _openBillingWeb();
                },
                child: const Text('Upgrade Plan'),
              ),
            ],
          ),
        );
        return false;
      }
    }
    return true;
  }

  bool _assertWritable(BuildContext context, String actionDescription) {
    if (_businessProfile != null && !_businessProfile!.isWritable) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(
                Icons.lock_clock_outlined,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(width: 8),
              const Text('Action Locked'),
            ],
          ),
          content: Text(
            'Your account is in read-only mode because your subscription has expired.\n\nPlease upgrade your plan to $actionDescription.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Dismiss'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                _openBillingWeb();
              },
              child: const Text('Upgrade Plan'),
            ),
          ],
        ),
      );
      return false;
    }
    return true;
  }

  void _scheduleReload() {
    if (!mounted) return;
    if (_reloadScheduled) return;
    _reloadScheduled = true;
    Future.delayed(const Duration(milliseconds: 400), () async {
      if (!mounted) return;
      _reloadScheduled = false;
      await _loadDashboardData();
    });
  }

  void _subscribeToDataChanges() {
    final bizId = _businessProfile?.id;
    if (bizId == null) return;

    // Clean previous channels
    if (_salesChannel != null) {
      SupabaseService.client.removeChannel(_salesChannel!);
      _salesChannel = null;
    }
    if (_purchasesChannel != null) {
      SupabaseService.client.removeChannel(_purchasesChannel!);
      _purchasesChannel = null;
    }
    if (_productsChannel != null) {
      SupabaseService.client.removeChannel(_productsChannel!);
      _productsChannel = null;
    }

    // Sales changes (insert/update/delete)
    _salesChannel = SupabaseService.client
        .channel('public:sales_$bizId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'sales',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'business_id',
            value: bizId,
          ),
          callback: (payload) => _scheduleReload(),
        )
        .subscribe();

    // Purchases changes
    _purchasesChannel = SupabaseService.client
        .channel('public:purchases_$bizId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'purchases',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'business_id',
            value: bizId,
          ),
          callback: (payload) => _scheduleReload(),
        )
        .subscribe();

    // Products changes (stock updates affect metrics)
    _productsChannel = SupabaseService.client
        .channel('public:products_$bizId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'products',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'business_id',
            value: bizId,
          ),
          callback: (payload) => _scheduleReload(),
        )
        .subscribe();

    // Replacements changes
    _replacementsChannel = SupabaseService.client
        .channel('public:replacements_$bizId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'replacements',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'business_id',
            value: bizId,
          ),
          callback: (payload) => _scheduleReload(),
        )
        .subscribe();

    // Returns changes
    _returnsChannel = SupabaseService.client
        .channel('public:returns_$bizId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'returns',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'business_id',
            value: bizId,
          ),
          callback: (payload) => _scheduleReload(),
        )
        .subscribe();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 1024;

        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          body: Column(
            children: [
              // Avoid overlapping status bar on mobile
              SafeArea(child: _buildTopNavbar()),
              Expanded(child: _buildMainDashboard()),
            ],
          ),
          bottomNavigationBar: isDesktop ? null : _buildMobileBottomNav(),
        );
      },
    );
  }

  // Simple skeletons without external dependencies
  Widget _skeletonBox({double height = 120, double radius = 16}) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).dividerColor.withAlpha(51),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }

  Widget _buildSkeletonMain() {
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 480;
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 20,
        vertical: isMobile ? 16 : 20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header skeleton
          _skeletonBox(height: isMobile ? 80 : 96, radius: 20),
          SizedBox(height: isMobile ? 12 : 20),
          // Metrics grid skeleton
          LayoutBuilder(
            builder: (context, constraints) {
              final crossAxisCount = constraints.maxWidth > 768
                  ? 3
                  : constraints.maxWidth > 480
                  ? 2
                  : 1;
              return GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: constraints.maxWidth > 768 ? 1.8 : 1.5,
                children: List.generate(6, (_) => _skeletonBox(height: 140)),
              );
            },
          ),
          SizedBox(height: isMobile ? 12 : 20),
          // Charts skeleton
          _skeletonBox(height: 260),
          SizedBox(height: 12),
          _skeletonBox(height: 260),
          SizedBox(height: isMobile ? 12 : 20),
          // Realtime + growth skeletons
          _skeletonBox(height: 160),
          SizedBox(height: 12),
          _skeletonBox(height: 160),
        ],
      ),
    );
  }

  Widget _buildBusinessLogo({double size = 36, double radius = 12}) {
    final logoUrl = _businessProfile?.logoUrl;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(radius),
      ),
      clipBehavior: Clip.antiAlias,
      child: (logoUrl != null && logoUrl.isNotEmpty)
          ? Image.network(
              logoUrl,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stack) {
                return Center(
                  child: Image.asset(
                    'assets/icons/app_icon.png',
                    fit: BoxFit.contain,
                    width: size * 0.7,
                    height: size * 0.7,
                  ),
                );
              },
            )
          : Center(
              child: Image.asset(
                'assets/icons/app_icon.png',
                fit: BoxFit.contain,
                width: size * 0.7,
                height: size * 0.7,
              ),
            ),
    );
  }

  Widget _buildTopNavbar() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 1024;

        if (isDesktop) {
          return _buildDesktopNavbar();
        } else {
          return _buildMobileNavbar();
        }
      },
    );
  }

  Widget _buildDesktopNavbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor.withAlpha(242),
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withAlpha(26),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // Logo and Brand Section
          _buildBrandSection(),

          const Spacer(),

          // Core Navigation Items
          _buildCoreNavigation(),

          const SizedBox(width: 16),

          // Right Actions
          _buildRightActions(),
        ],
      ),
    );
  }

  Widget _buildBrandSection() {
    return InkWell(
      onTap: () {
        // Navigate to dashboard
      },
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            // Business Logo (dynamic with fallback)
            _buildBusinessLogo(size: 40, radius: 12),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _businessProfile?.businessName ?? 'Raj Electricals',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).textTheme.titleMedium?.color,
                  ),
                ),
                Text(
                  'Run your business with clarity',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(
                      context,
                    ).textTheme.bodySmall?.color?.withAlpha(153),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCoreNavigation() {
    final navItems = [
      {
        'label': 'Dashboard',
        'icon': Icons.dashboard,
        'description': 'Overview & Analytics',
        'active': true,
      },
      {
        'label': 'Catalog',
        'icon': Icons.inventory_2,
        'description': 'Product Management',
        'active': false,
      },
      {
        'label': 'Inventory',
        'icon': Icons.warehouse,
        'description': 'Stock & Tracking',
        'active': false,
      },
      {
        'label': 'Sales',
        'icon': Icons.trending_up,
        'description': 'Sales Operations',
        'active': false,
      },
      {
        'label': 'Purchase',
        'icon': Icons.shopping_cart,
        'description': 'Procurement',
        'active': false,
      },
      {
        'label': 'Reports',
        'icon': Icons.bar_chart,
        'description': 'Analytics & Insights',
        'active': false,
      },
    ];

    return Row(
      children: [
        ...navItems.map(
          (item) => _buildNavItem(
            item['label'] as String,
            item['icon'] as IconData,
            item['description'] as String,
            item['active'] as bool,
          ),
        ),
        const SizedBox(width: 8),
        _buildMoreMenu(),
      ],
    );
  }

  Widget _buildNavItem(
    String label,
    IconData icon,
    String description,
    bool isActive,
  ) {
    return Tooltip(
      message: description,
      preferBelow: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            if (label == 'Catalog') {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => CatalogPage(db: widget.db),
                ),
              );
            } else if (label == 'Inventory') {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const InventoryPage()),
              );
            } else if (label == 'Sales') {
              if (!_assertWritable(context, 'record a sale')) return;
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SalesPage()),
              ).then((_) => _loadDashboardData());
            } else if (label == 'Purchase') {
              if (!_assertWritable(context, 'record a purchase')) return;
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const PurchasePage()),
              ).then((_) => _loadDashboardData());
            } else if (label == 'Reports') {
              if (!_assertFeature(context, 'reports', 'Reports & Analytics')) return;
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ReportsPage()),
              );
            }
          },
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isActive
                  ? Theme.of(context).colorScheme.primary.withAlpha(26)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: isActive
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(
                          context,
                        ).textTheme.bodyMedium?.color?.withAlpha(153),
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: isActive
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(
                            context,
                          ).textTheme.bodyMedium?.color?.withAlpha(178),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMoreMenu() {
    return PopupMenuButton<String>(
      tooltip: 'More navigation options',
      icon: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.more_horiz,
            size: 16,
            color: Theme.of(
              context,
            ).textTheme.bodyMedium?.color?.withAlpha(153),
          ),
          const SizedBox(width: 4),
          Text(
            'More',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Theme.of(
                context,
              ).textTheme.bodyMedium?.color?.withAlpha(178),
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            Icons.keyboard_arrow_down,
            size: 16,
            color: Theme.of(
              context,
            ).textTheme.bodyMedium?.color?.withAlpha(153),
          ),
        ],
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      itemBuilder: (context) => [
        _buildMoreMenuItem('Returns', Icons.undo, 'Process Customer Returns'),
        _buildMoreMenuItem(
          'Replacements',
          Icons.swap_horiz,
          'Process Customer Replacements',
        ),
        const PopupMenuDivider(),
        _buildMoreMenuItem(
          'Supplier Returns',
          Icons.assignment_return_outlined,
          'Process Supplier Returns',
        ),
        _buildMoreMenuItem(
          'Supplier Credits',
          Icons.credit_card,
          'View Supplier Credits',
        ),
        _buildMoreMenuItem(
          'Suppliers',
          Icons.business_center,
          'Manage Suppliers/Dealers',
        ),
        _buildMoreMenuItem(
          'Customers',
          Icons.people_outline,
          'Manage Customers',
        ),
        const PopupMenuDivider(),
        _buildMoreMenuItem('Shop', Icons.storefront, 'Customer Shop (UPI)'),
        _buildMoreMenuItem(
          'Returns History',
          Icons.history,
          'Past return records',
        ),
        _buildMoreMenuItem(
          'Replacements History',
          Icons.sync_alt,
          'Past replacement records',
        ),
        _buildMoreMenuItem('Reports', Icons.bar_chart, 'View Reports'),
        _buildMoreMenuItem(
          'Business Settings',
          Icons.business,
          'Manage Business Info',
        ),
        _buildMoreMenuItem('Requests', Icons.people, 'User Requests'),
        _buildMoreMenuItem(
          'System Health',
          Icons.health_and_safety,
          'System Status',
        ),
        _buildMoreMenuItem(
          'Archived Products',
          Icons.archive,
          'View Archived Items',
        ),
        _buildMoreMenuItem(
          'Sales History',
          Icons.history,
          'Past sales records',
        ),
        _buildMoreMenuItem(
          'Purchase History',
          Icons.receipt_long,
          'Past purchase records',
        ),
        _buildMoreMenuItem(
          'Data Management',
          Icons.settings,
          'Backup, Restore, Delete',
        ),
        const PopupMenuDivider(),
        _buildMoreMenuItem(
          'Profile Settings',
          Icons.person,
          'Manage Profile & Logout',
        ),
      ],
      onSelected: (value) {
        if (value == 'Sales History') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const SalesHistoryPage()),
          );
        } else if (value == 'Purchase History') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const PurchaseHistoryPage(),
            ),
          );
        } else if (value == 'Returns') {
          if (!_assertWritable(context, 'process a return')) return;
          if (!_assertFeature(context, 'returns', 'Customer Returns')) return;
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => ReturnsPage(db: widget.db)),
          );
        } else if (value == 'Replacements') {
          if (!_assertWritable(context, 'process a replacement')) return;
          if (!_assertFeature(context, 'returns', 'Customer Replacements')) return;
          Navigator.pushNamed(context, '/replacements');
        } else if (value == 'Supplier Returns') {
          if (!_assertWritable(context, 'create a supplier return')) return;
          if (!_assertFeature(context, 'returns', 'Supplier Returns')) return;
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const SupplierReturnsPage(),
            ),
          );
        } else if (value == 'Supplier Credits') {
          if (!_assertFeature(context, 'reports', 'Supplier Credits')) return;
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const SupplierCreditsPage(),
            ),
          );
        } else if (value == 'Suppliers') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const SuppliersPage()),
          );
        } else if (value == 'Customers') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const CustomersPage()),
          );
        } else if (value == 'Shop') {
          Navigator.pushNamed(context, '/shop');
        } else if (value == 'Returns History') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const ReturnsHistoryPage()),
          );
        } else if (value == 'Replacements History') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const ReplacementsHistoryPage(),
            ),
          );
        } else if (value == 'Reports') {
          if (!_assertFeature(context, 'reports', 'Reports & Analytics')) return;
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const ReportsPage()),
          );
        } else if (value == 'Business Settings') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const BusinessSettingsPage(),
            ),
          );
        } else if (value == 'Requests') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const RequestsPage()),
          );
        } else if (value == 'System Health') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const SystemHealthPage()),
          );
        } else if (value == 'Archived Products') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const ArchivedProductsPage(),
            ),
          );
        } else if (value == 'Data Management') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => DataManagementPage(db: widget.db),
            ),
          );
        } else if (value == 'Profile Settings') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const ProfileSettingsPage(),
            ),
          );
        }
      },
    );
  }

  PopupMenuItem<String> _buildMoreMenuItem(
    String label,
    IconData icon,
    String description,
  ) {
    return PopupMenuItem<String>(
      value: label,
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.onSurface.withAlpha(26),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 16,
              color: Theme.of(
                context,
              ).textTheme.bodyMedium?.color?.withAlpha(153),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(
                      context,
                    ).textTheme.bodySmall?.color?.withAlpha(153),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRightActions() {
    return Row(
      children: [
        Tooltip(
          message: 'Toggle theme',
          child: IconButton(
            onPressed: _showThemeDialog,
            icon: Icon(
              Theme.of(context).brightness == Brightness.dark
                  ? Icons.light_mode
                  : Icons.dark_mode,
            ),
            iconSize: 20,
            color: Theme.of(
              context,
            ).textTheme.bodyMedium?.color?.withAlpha(153),
          ),
        ),
        const SizedBox(width: 8),
        Tooltip(
          message: 'User profile',
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ProfileSettingsPage(),
                ),
              );
            },
            child: CircleAvatar(
              radius: 16,
              backgroundColor: Theme.of(
                context,
              ).colorScheme.primary.withAlpha(26),
              child: Icon(
                Icons.person,
                size: 16,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMobileNavbar() {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Theme.of(context).colorScheme.surface.withAlpha(229),
                Theme.of(context).colorScheme.surface.withAlpha(204),
              ],
            ),
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).colorScheme.outline.withAlpha(38),
                width: 0.5,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: Theme.of(context).shadowColor.withAlpha(20),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              // Enhanced Mobile Logo with subtle animation
              Hero(
                tag: 'business_logo',
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withAlpha(51),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: _buildBusinessLogo(size: 36, radius: 12),
                ),
              ),
              const SizedBox(width: 10),
              // Enhanced Brand Name with better typography
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _businessProfile?.businessName ?? 'Inventoza',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                        color: Theme.of(context).colorScheme.onSurface,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      'Dashboard',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurfaceVariant.withAlpha(178),
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Modern Action Buttons
              Row(
                children: [
                  _buildModernActionButton(
                    icon: Theme.of(context).brightness == Brightness.dark
                        ? Icons.light_mode_rounded
                        : Icons.dark_mode_rounded,
                    onTap: _showThemeDialog,
                    tooltip: 'Toggle theme',
                  ),
                  const SizedBox(width: 6),
                  _buildModernActionButton(
                    icon: Icons.history_rounded,
                    onTap: () => _showModernHistorySheet(),
                    tooltip: 'History',
                  ),
                  const SizedBox(width: 6),
                  _buildModernProfileButton(),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModernActionButton({
    required IconData icon,
    required VoidCallback onTap,
    required String tooltip,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            onTap();
          },
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest.withAlpha(153),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: Theme.of(context).colorScheme.outline.withAlpha(26),
                width: 0.5,
              ),
            ),
            child: Icon(
              icon,
              size: 18,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModernProfileButton() {
    return Tooltip(
      message: 'Profile',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const ProfileSettingsPage(),
              ),
            );
          },
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Theme.of(context).colorScheme.primary.withAlpha(38),
                  Theme.of(context).colorScheme.primary.withAlpha(26),
                ],
              ),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: Theme.of(context).colorScheme.primary.withAlpha(51),
                width: 0.5,
              ),
            ),
            child: Icon(
              Icons.person_rounded,
              size: 18,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
      ),
    );
  }

  void _showModernHistorySheet() {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Theme.of(context).shadowColor.withAlpha(26),
                blurRadius: 20,
                offset: const Offset(0, -8),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag handle
                Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurfaceVariant.withAlpha(102),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(UITokens.radius),
                        ),
                        child: Icon(
                          Icons.history_rounded,
                          size: 20,
                          color: Theme.of(
                            context,
                          ).colorScheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'History',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
                // History options
                _buildModernHistoryTile(
                  icon: Icons.trending_up_rounded,
                  title: 'Sales History',
                  subtitle: 'View sales transactions',
                  color: Colors.green,
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const SalesHistoryPage(),
                      ),
                    );
                  },
                ),
                _buildModernHistoryTile(
                  icon: Icons.receipt_long_rounded,
                  title: 'Purchase History',
                  subtitle: 'View purchase records',
                  color: Colors.blue,
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const PurchaseHistoryPage(),
                      ),
                    );
                  },
                ),
                _buildModernHistoryTile(
                  icon: Icons.reply_rounded,
                  title: 'Returns History',
                  subtitle: 'View return transactions',
                  color: Colors.orange,
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ReturnsHistoryPage(),
                      ),
                    );
                  },
                ),
                _buildModernHistoryTile(
                  icon: Icons.sync_alt_rounded,
                  title: 'Replacements History',
                  subtitle: 'View replacement records',
                  color: Colors.purple,
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ReplacementsHistoryPage(),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildModernHistoryTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            onTap();
          },
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.surfaceContainer.withAlpha(128),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Theme.of(context).colorScheme.outline.withAlpha(26),
                width: 0.5,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: color.withAlpha(38),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, size: 24, color: color),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 16,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurfaceVariant.withAlpha(153),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMobileBottomNav() {
    final items = [
      {'label': 'Dashboard', 'icon': Icons.dashboard_rounded},
      {'label': 'Catalog', 'icon': Icons.inventory_2_rounded},
      {'label': 'Inventory', 'icon': Icons.warehouse_rounded},
      {'label': 'Sales', 'icon': Icons.trending_up_rounded},
      {'label': 'Purchase', 'icon': Icons.shopping_cart_rounded},
    ];

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final attached =
        isDark; // keep attached style in dark mode, but sizes are uniform

    return Container(
      margin: const EdgeInsets.fromLTRB(0, 0, 0, 0),
      child: ClipRRect(
        borderRadius: attached
            ? const BorderRadius.only(
                topLeft: Radius.circular(28),
                topRight: Radius.circular(28),
              )
            : BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: isDark ? 36 : 32,
            sigmaY: isDark ? 36 : 32,
          ),
          child: Container(
            height: 78,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Theme.of(
                    context,
                  ).colorScheme.surface.withAlpha(isDark ? 251 : 209),
                  Theme.of(
                    context,
                  ).colorScheme.surface.withAlpha(isDark ? 246 : 173),
                ],
              ),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: Theme.of(
                  context,
                ).colorScheme.outline.withAlpha(isDark ? 31 : 26),
                width: 0.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Theme.of(
                    context,
                  ).shadowColor.withAlpha(isDark ? 36 : 31),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withAlpha(isDark ? 15 : 10),
                  blurRadius: 40,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: Stack(
              children: [
                if (isDark)
                  Positioned.fill(
                    child: Container(
                      // Subtle dark tint to reduce background visibility in dark mode
                      color: Colors.black.withValues(alpha: 0.10),
                    ),
                  ),
                SafeArea(
                  top: false,
                  bottom:
                      false, // avoid extra bottom inset padding inside the pill
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ...List.generate(
                          items.length,
                          (i) => _buildModernNavItem(
                            items[i]['label'] as String,
                            items[i]['icon'] as IconData,
                            i,
                          ),
                        ),
                        _buildModernMoreButton(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModernNavItem(String label, IconData icon, int index) {
    final isActive = index == _selectedTabIndex;
    final primary = Theme.of(context).colorScheme.primary;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final attached = isDark; // stylistic only

    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            setState(() => _selectedTabIndex = index);
            if (label == 'Catalog') {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => CatalogPage(db: widget.db),
                ),
              );
            } else if (label == 'Inventory') {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const InventoryPage()),
              );
            } else if (label == 'Sales') {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SalesPage()),
              );
            } else if (label == 'Purchase') {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const PurchasePage()),
              );
            }
          },
          borderRadius: BorderRadius.circular(20),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Icon with animated background
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  width: isActive ? 30 : 26,
                  height: isActive ? 30 : 26,
                  decoration: BoxDecoration(
                    gradient: isActive
                        ? LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              primary.withAlpha(51),
                              primary.withAlpha(38),
                            ],
                          )
                        : null,
                    borderRadius: BorderRadius.circular(attached ? 14 : 10),
                    boxShadow: isActive
                        ? [
                            BoxShadow(
                              color: primary.withAlpha(77),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: Icon(
                    icon,
                    size: isActive ? 18 : 16,
                    color: isActive
                        ? primary
                        : Theme.of(
                            context,
                          ).colorScheme.onSurfaceVariant.withAlpha(178),
                  ),
                ),
                const SizedBox(height: 2),
                // Label with smooth animation
                SizedBox(
                  height: 10,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: isActive ? 10 : 9,
                        fontWeight: isActive
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: isActive
                            ? primary
                            : Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant.withAlpha(204),
                        letterSpacing: 0.2,
                        height: 1.0,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModernMoreButton() {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            _showMobileMoreMenu();
          },
          borderRadius: BorderRadius.circular(20),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // More icon with modern styling
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest.withAlpha(153),
                    borderRadius: BorderRadius.circular(UITokens.radius),
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).colorScheme.outline.withAlpha(38),
                      width: 0.5,
                    ),
                  ),
                  child: Icon(
                    Icons.more_horiz_rounded,
                    size: 16,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurfaceVariant.withAlpha(178),
                  ),
                ),
                const SizedBox(height: 2),
                // More label constrained
                SizedBox(
                  height: 10,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'More',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w500,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurfaceVariant.withAlpha(204),
                        letterSpacing: 0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ignore: unused_element
  Widget _buildMobileNavItem(String label, IconData icon, int index) {
    final isActive = index == _selectedTabIndex;
    final primary = Theme.of(context).colorScheme.primary;
    final inactive = Theme.of(
      context,
    ).textTheme.bodyMedium?.color?.withAlpha(153);
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _selectedTabIndex = index);
            if (label == 'Catalog') {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => CatalogPage(db: widget.db),
                ),
              );
            } else if (label == 'Inventory') {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const InventoryPage()),
              );
            } else if (label == 'Sales') {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SalesPage()),
              );
            } else if (label == 'Purchase') {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const PurchasePage()),
              );
            }
          },
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(
                      icon,
                      size: isActive ? 22 : 20,
                      color: isActive ? primary : inactive,
                    ),
                    if (_getNavBadgeCount(label) > 0)
                      Positioned(
                        right: -6,
                        top: -4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.error,
                            borderRadius: BorderRadius.circular(
                              UITokens.radius,
                            ),
                            border: Border.all(
                              color: Theme.of(context).cardColor,
                              width: 1,
                            ),
                          ),
                          constraints: const BoxConstraints(
                            minWidth: 16,
                            minHeight: 14,
                          ),
                          child: Text(
                            _formatBadge(_getNavBadgeCount(label)),
                            style: const TextStyle(
                              fontSize: 9,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                    color: isActive ? primary : inactive,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  int _getNavBadgeCount(String label) {
    if (label == 'Inventory') {
      final val = _stats['lowStockCount'];
      return val is int ? val : 0;
    }
    if (label == 'Sales') {
      final val = _stats['todaysSales'];
      return val is int ? val : 0;
    }
    return 0;
  }

  String _formatBadge(int n) => n > 9 ? '9+' : n.toString();

  // ignore: unused_element
  Widget _buildMobileMoreButton({required int index}) {
    final inactive = Theme.of(
      context,
    ).textTheme.bodyMedium?.color?.withAlpha(153);
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _selectedTabIndex = index);
            _showMobileMoreMenu();
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.more_horiz, size: 20, color: inactive),
                const SizedBox(height: 4),
                Text(
                  'More',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: inactive,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showMobileMoreMenu() {
    final isMobile = MediaQuery.of(context).size.width < 480;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SingleChildScrollView(
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'More Options',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: isMobile ? 12 : 16),
                    GridView.count(
                      shrinkWrap: true,
                      crossAxisCount: 2,
                      childAspectRatio: 3,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      children: [
                        _buildMobileMoreItem('Reports', Icons.bar_chart),
                        _buildMobileMoreItem('Verify Payments', Icons.verified),
                        _buildMobileMoreItem(
                          'Suppliers',
                          Icons.business_center,
                        ),
                        _buildMobileMoreItem(
                          'Supplier Returns',
                          Icons.assignment_return_outlined,
                        ),
                        _buildMobileMoreItem(
                          'Supplier Credits',
                          Icons.credit_card,
                        ),
                        _buildMobileMoreItem('Returns', Icons.undo),
                        _buildMobileMoreItem('Replacements', Icons.swap_horiz),
                        _buildMobileMoreItem('Business', Icons.business),
                        _buildMobileMoreItem('Requests', Icons.people),
                        _buildMobileMoreItem(
                          'System Health',
                          Icons.health_and_safety,
                        ),
                        _buildMobileMoreItem('Billing & Plan', Icons.credit_card),
                        _buildMobileMoreItem('Archive', Icons.archive),
                        _buildMobileMoreItem('Settings', Icons.settings),
                        _buildMobileMoreItem('Customers', Icons.people_outline),
                      ],
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

  Widget _buildMobileMoreItem(String label, IconData icon) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.pop(context);
          if (label == 'Returns') {
            if (!_assertWritable(context, 'process a return')) return;
            if (!_assertFeature(context, 'returns', 'Customer Returns')) return;
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ReturnsPage(db: widget.db),
              ),
            );
          } else if (label == 'Reports') {
            if (!_assertFeature(context, 'reports', 'Reports & Analytics')) return;
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const ReportsPage()),
            );
          } else if (label == 'Business') {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const BusinessSettingsPage(),
              ),
            );
          } else if (label == 'Requests') {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const RequestsPage()),
            );
          } else if (label == 'Replacements') {
            if (!_assertWritable(context, 'process a replacement')) return;
            if (!_assertFeature(context, 'returns', 'Customer Replacements')) return;
            Navigator.pushNamed(context, '/replacements');
          } else if (label == 'System Health') {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const SystemHealthPage()),
            );
          } else if (label == 'Sales History') {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const SalesHistoryPage()),
            );
          } else if (label == 'Purchase History') {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const PurchaseHistoryPage(),
              ),
            );
          } else if (label == 'Billing & Plan') {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => BillingPage(db: widget.db),
              ),
            );
          } else if (label == 'Archive') {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const ArchivedProductsPage(),
              ),
            );
          } else if (label == 'Settings') {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => DataManagementPage(db: widget.db),
              ),
            );
          } else if (label == 'Suppliers') {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const SuppliersPage()),
            );
          } else if (label == 'Supplier Returns') {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const SupplierReturnsPage(),
              ),
            );
          } else if (label == 'Supplier Credits') {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const SupplierCreditsPage(),
              ),
            );
          } else if (label == 'Verify Payments') {
            Navigator.pushNamed(context, '/payments/verification');
          } else if (label == 'Customers') {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const CustomersPage()),
            );
          } else {
            // No-op for unknown labels to avoid disruptive snackbars
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Theme.of(context).dividerColor.withAlpha(77),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.onSurface.withAlpha(26),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  size: 16,
                  color: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.color?.withAlpha(153),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMainDashboard() {
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 480;
    // Show skeleton while loading
    if (_isLoadingCharts) {
      return _buildSkeletonMain();
    }
    return RefreshIndicator(
      onRefresh: _handlePullToRefresh,
      color: Theme.of(context).colorScheme.primary,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 12 : 20,
          vertical: isMobile ? 16 : 20,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Read-Only Status Banner or Trial Expiration Warning
            if (_businessProfile != null &&
                (!_businessProfile!.isWritable ||
                    (_businessProfile!.status?.toUpperCase() == 'TRIAL' &&
                        _businessProfile!.daysRemainingInTrial != null &&
                        _businessProfile!.daysRemainingInTrial! <= 3)))
              Container(
                width: double.infinity,
                margin: EdgeInsets.only(bottom: isMobile ? 12 : 16),
                padding: EdgeInsets.all(isMobile ? 12 : 16),
                decoration: BoxDecoration(
                  color: _businessProfile!.isExpired
                      ? Theme.of(context).colorScheme.errorContainer
                      : Colors.amber.shade900.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _businessProfile!.isExpired
                        ? Theme.of(context).colorScheme.error
                        : Colors.amber.shade600,
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _businessProfile!.isExpired
                          ? Icons.lock_outline
                          : Icons.timelapse,
                      color: _businessProfile!.isExpired
                          ? Theme.of(context).colorScheme.error
                          : Colors.amber.shade700,
                      size: isMobile ? 24 : 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _businessProfile!.isExpired
                                ? 'Subscription Expired - Read-Only Mode'
                                : 'Trial Expiring Soon (${_businessProfile!.daysRemainingInTrial}d left)',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: _businessProfile!.isExpired
                                  ? Theme.of(context)
                                      .colorScheme
                                      .onErrorContainer
                                  : Colors.amber.shade900,
                              fontSize: isMobile ? 14 : 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _businessProfile!.isExpired
                                ? 'You can view data, but adding products, sales, and purchases are locked. Upgrade to restore full access.'
                                : 'Upgrade to a paid plan on the Inventoza web portal to prevent service interruption.',
                            style: TextStyle(
                              color: _businessProfile!.isExpired
                                  ? Theme.of(context)
                                      .colorScheme
                                      .onErrorContainer
                                      .withValues(alpha: 0.85)
                                  : Colors.amber.shade900.withValues(alpha: 0.85),
                              fontSize: isMobile ? 12 : 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _openBillingWeb,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _businessProfile!.isExpired
                            ? Theme.of(context).colorScheme.error
                            : Colors.amber.shade700,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(
                          horizontal: isMobile ? 12 : 16,
                          vertical: isMobile ? 8 : 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        'Upgrade',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            _buildExecutiveHeader(),
            SizedBox(height: isMobile ? 12 : 16),
            _buildKeyMetrics(),
            SizedBox(height: isMobile ? 16 : 20),
            _buildTabbedAnalytics(),
            SizedBox(height: isMobile ? 16 : 20),
            _buildQuickActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildTabbedAnalytics() {
    return DashboardCharts.buildTabbedAnalytics(
      selectedTab: _selectedAnalyticsTab,
      onTabChanged: (index) {
        setState(() => _selectedAnalyticsTab = index);
      },
      dailySales: _dailySales,
      categorySales: _categorySales,
      dailyProfits: _dailyProfits,
      inventoryAging: _inventoryAging,
      realtimeStats: _realtimeStats,
      growthData: _growthData,
      isLoading: _isLoadingCharts,
    );
  }

  Widget _buildExecutiveHeader() {
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 480;

    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 17
            ? 'Good afternoon'
            : 'Good evening';

    final formattedDate = DateFormat('EEE, d MMM').format(DateTime.now());
    final todaysRevenue = (_stats['todaysRevenue'] as num?) ?? 0;
    final todaysSales = (_stats['todaysSales'] as num?) ?? 0;
    final formattedTodayRevenue = NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 0,
    ).format(todaysRevenue);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 14 : 20,
        vertical: isMobile ? 12 : 14,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Theme.of(context).colorScheme.primary.withAlpha(24),
            Theme.of(context).cardColor,
            Theme.of(context).colorScheme.surface,
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withAlpha(40),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).shadowColor.withAlpha(14),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Text(
                          '$greeting!',
                          style: TextStyle(
                            fontSize: isMobile ? 16 : 18,
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green.withAlpha(26),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.green.withAlpha(60)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                  color: Colors.green,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Text(
                                'LIVE',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      todaysSales > 0
                          ? "Today: $formattedTodayRevenue ($todaysSales sales)"
                          : "Today's sales ready • Live sync active",
                      style: TextStyle(
                        fontSize: isMobile ? 12 : 13,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(90),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.calendar_today_outlined,
                      size: 12,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      formattedDate,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: isMobile ? 10 : 12),
          _buildTimeRangeSelector(),
        ],
      ),
    );
  }

  Future<void> _handlePullToRefresh() async {
    HapticFeedback.lightImpact();
    try {
      await _loadDashboardData();
      if (!mounted) return;
      // Optional light feedback
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Dashboard refreshed'),
          duration: const Duration(seconds: 1),
          backgroundColor: Theme.of(context).colorScheme.primary,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Failed to refresh. Please try again.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Widget _buildPageHeader() {
    final businessName = _businessProfile?.businessName;
    return PageHeader(
      title: businessName != null && businessName.isNotEmpty
          ? '$businessName - Dashboard'
          : 'Dashboard',
      description: 'Real-time business overview and key performance metrics',
      icon: '🏠',
      showBackButton: false,
      wrapInSafeArea: false,
      breadcrumbs: [],
      stats: [
        PageHeaderStat(
          label: 'Smart Inventory',
          value: 'Business Intelligence',
          description: 'Analytics suite',
        ),
        PageHeaderStat(
          label: 'Real-time overview',
          value: 'Live updates',
          description: 'Auto-refreshing',
        ),
      ],
      actions: [
        PageHeaderAction(
          label: 'View Reports',
          shortLabel: 'Reports',
          icon: Icons.bar_chart,
          color: Theme.of(context).colorScheme.primary,
          onPressed: () {
            if (!_assertFeature(context, 'reports', 'Reports & Analytics')) return;
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const ReportsPage()),
            );
          },
        ),
        PageHeaderAction(
          label: 'System Health',
          shortLabel: 'Health',
          icon: Icons.health_and_safety,
          color: Theme.of(context).colorScheme.tertiary,
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const SystemHealthPage()),
            );
          },
        ),
      ],
    );
  }

  Widget _buildTimeRangeSelector() {
    final ranges = [
      {'key': 'today', 'label': 'Today', 'icon': Icons.today_rounded},
      {'key': 'month', 'label': 'This Month', 'icon': Icons.calendar_month_rounded},
      {'key': 'all', 'label': 'All Time', 'icon': Icons.all_inclusive_rounded},
    ];

    return Container(
      padding: const EdgeInsets.all(3.5),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(100),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Theme.of(context).dividerColor.withAlpha(25),
        ),
      ),
      child: Row(
        children: ranges.map((r) {
          final isSelected = _activeTimeRange == r['key'];
          return Expanded(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _switchTimeRange(r['key'] as String),
                borderRadius: BorderRadius.circular(11),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(11),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withAlpha(70),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        r['icon'] as IconData,
                        size: 13,
                        color: isSelected
                            ? Theme.of(context).colorScheme.onPrimary
                            : Theme.of(context).textTheme.bodySmall?.color,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        r['label'] as String,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          color: isSelected
                              ? Theme.of(context).colorScheme.onPrimary
                              : Theme.of(context).textTheme.bodySmall?.color,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildKeyMetrics() {
    final isMobile = MediaQuery.of(context).size.width < 480;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withAlpha(26),
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary.withAlpha(51),
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.insights,
                size: 15,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Key Performance Metrics',
              style: TextStyle(
                fontSize: isMobile ? 18 : 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        SizedBox(height: isMobile ? 8 : 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final isMobile = constraints.maxWidth <= 480;
            final crossAxisCount = constraints.maxWidth > 768 ? 3 : 2;

            final revenueNum = (_stats['totalRevenue'] as num?) ?? 0;
            final profitNum = (_stats['totalProfit'] as num?) ?? 0;
            final refundNum = (_stats['totalRefund'] as num?) ?? 0;

            final revenueFormatted = NumberFormat.currency(
              locale: 'en_IN',
              symbol: '₹',
              decimalDigits: 0,
            ).format(revenueNum);

            final profitFormatted = NumberFormat.currency(
              locale: 'en_IN',
              symbol: '₹',
              decimalDigits: 0,
            ).format(profitNum);

            final refundFormatted = NumberFormat.currency(
              locale: 'en_IN',
              symbol: '₹',
              decimalDigits: 0,
            ).format(refundNum);

            return GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: isMobile ? 8 : 12,
              mainAxisSpacing: isMobile ? 8 : 12,
              childAspectRatio: isMobile ? 1.55 : (constraints.maxWidth > 768 ? 1.8 : 1.5),
              children: [
                _buildMetricCard(
                  'Total Revenue',
                  revenueFormatted,
                  Icons.account_balance_wallet_outlined,
                  _statusColors(context).success,
                  'From ${_stats['salesCount'] ?? 0} sales',
                  onTap: () {
                    HapticFeedback.lightImpact();
                    if (!_assertFeature(context, 'reports', 'Financial Reports')) return;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ReportsPage(
                          initialReportType: 'Financial',
                          initialPeriod: 'All Time',
                        ),
                      ),
                    );
                  },
                ),
                _buildMetricCard(
                  'Total Profit/Loss',
                  profitFormatted,
                  profitNum >= 0
                      ? Icons.trending_up
                      : Icons.trending_down,
                  profitNum >= 0
                      ? _statusColors(context).success
                      : Theme.of(context).colorScheme.error,
                  profitNum >= 0 ? 'Profit' : 'Loss',
                  onTap: () {
                    HapticFeedback.lightImpact();
                    if (!_assertFeature(context, 'reports', 'Financial Reports')) return;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ReportsPage(
                          initialReportType: 'Financial',
                          initialPeriod: 'All Time',
                        ),
                      ),
                    );
                  },
                ),
                _buildMetricCard(
                  'Low Stock Items',
                  '${_stats['lowStockCount'] ?? 0}',
                  Icons.warning_amber_rounded,
                  _statusColors(context).warning,
                  'Items ≤5 in stock',
                  onTap: () {
                    HapticFeedback.lightImpact();
                    if (!_assertFeature(context, 'reports', 'Inventory Reports')) return;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            const ReportsPage(initialReportType: 'Inventory'),
                      ),
                    );
                  },
                ),
                _buildMetricCard(
                  'Total Returns',
                  '${_stats['totalReturns'] ?? 0}',
                  Icons.assignment_return_outlined,
                  Theme.of(context).colorScheme.error,
                  '$refundFormatted refunded',
                ),
                _buildMetricCard(
                  'Total Replacements',
                  '${_stats['totalReplacements'] ?? 0}',
                  Icons.swap_horiz,
                  _statusColors(context).info,
                  'Product exchanges',
                ),
                _buildMetricCard(
                  'Categories',
                  '${_categoryCounts.length}',
                  Icons.category_outlined,
                  _statusColors(context).info,
                  'Product categories',
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildMetricCard(
    String title,
    String value,
    IconData icon,
    Color color,
    String subtitle, {
    VoidCallback? onTap,
  }) {
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 480;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        child: _HoverWrapper(
          hoverScale: 1.03,
          builder: (hovered) => AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 10 : 16,
              vertical: isMobile ? 10 : 16,
            ),
            constraints: BoxConstraints(minHeight: isMobile ? 78 : 120),
            decoration: BoxDecoration(
              color: hovered
                  ? Theme.of(context).cardColor.withAlpha(229)
                  : Theme.of(context).cardColor.withAlpha(178),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: hovered ? color.withAlpha(102) : color.withAlpha(51),
                width: hovered ? 1.5 : 1,
              ),
              boxShadow: [
                // Primary colored shadow for depth
                BoxShadow(
                  color: color.withAlpha(hovered ? 51 : 25),
                  blurRadius: hovered ? 24 : 14,
                  offset: Offset(0, hovered ? 10 : 6),
                  spreadRadius: hovered ? 2 : 0,
                ),
                // Secondary shadow for realism
                BoxShadow(
                  color: Theme.of(
                    context,
                  ).shadowColor.withAlpha(hovered ? 38 : 16),
                  blurRadius: hovered ? 10 : 5,
                  offset: Offset(0, hovered ? 3 : 2),
                ),
              ],
            ),
            child: Stack(
              children: [
                // Subtle gradient overlay for depth
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          color.withAlpha(hovered ? 20 : 10),
                          Colors.transparent,
                          color.withAlpha(hovered ? 15 : 5),
                        ],
                      ),
                    ),
                  ),
                ),
                // Main content
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: isMobile ? 11 : 13,
                              color: Theme.of(
                                context,
                              ).textTheme.bodyMedium?.color?.withAlpha(178),
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                        // Modern icon container with enhanced styling
                        Container(
                          padding: EdgeInsets.all(isMobile ? 6 : 10),
                          decoration: BoxDecoration(
                            gradient: hovered
                                ? LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [color, color.withAlpha(204)],
                                  )
                                : LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      color.withAlpha(38),
                                      color.withAlpha(26),
                                    ],
                                  ),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: hovered
                                  ? color.withAlpha(102)
                                  : color.withAlpha(64),
                              width: hovered ? 1.5 : 1,
                            ),
                          ),
                          child: Icon(
                            icon,
                            color: hovered ? Colors.white : color,
                            size: isMobile ? 15 : 20,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: isMobile ? 6 : 10),
                    // Enhanced value display
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        value,
                        style: TextStyle(
                          fontSize: isMobile ? 21 : 28,
                          fontWeight: FontWeight.w800,
                          color: Theme.of(context).textTheme.headlineSmall?.color,
                          letterSpacing: -0.5,
                          height: 1.1,
                        ),
                      ),
                    ),
                    SizedBox(height: isMobile ? 2 : 6),
                    // Improved subtitle with better contrast
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: isMobile ? 10 : 12,
                        color: Theme.of(
                          context,
                        ).textTheme.bodyMedium?.color?.withAlpha(153),
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ignore: unused_element
  Widget _buildLiveMetrics() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Live Business Metrics',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final crossAxisCount = constraints.maxWidth > 768
                ? 3
                : constraints.maxWidth > 480
                ? 2
                : 1;
            return GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: constraints.maxWidth > 768
                  ? 2.2
                  : constraints.maxWidth > 480
                  ? 1.8
                  : 2.4,
              children: [
                _buildLiveMetricCard(
                  "Today's Sales",
                  '${_stats['todaysSales'] ?? 0}',
                  Icons.trending_up,
                  Theme.of(context).colorScheme.secondary,
                ),
                _buildLiveMetricCard(
                  "Today's Revenue",
                  '₹${(_stats['todaysRevenue'] ?? 0).toStringAsFixed(0)}',
                  Icons.account_balance_wallet,
                  Theme.of(context).colorScheme.primary,
                ),
                _buildLiveMetricCard(
                  'Items Sold',
                  '${_stats['itemsSold'] ?? 0}',
                  Icons.shopping_cart,
                  (Theme.of(context).brightness == Brightness.dark
                          ? StatusColors.dark
                          : StatusColors.light)
                      .success,
                ),
                _buildLiveMetricCard(
                  'Out of Stock',
                  '${_stats['outOfStock'] ?? 0}',
                  Icons.warning,
                  Theme.of(context).colorScheme.error,
                ),
                _buildLiveMetricCard(
                  "Today's Returns",
                  '${_stats['todaysReturns'] ?? 0}',
                  Icons.assignment_return,
                  Theme.of(context).colorScheme.error,
                ),
                _buildLiveMetricCard(
                  "Today's Replacements",
                  '${_stats['todaysReplacements'] ?? 0}',
                  Icons.swap_horiz,
                  Theme.of(context).colorScheme.secondary,
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildLiveMetricCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 480;
    return Container(
      padding: EdgeInsets.all(isMobile ? 12 : 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withAlpha(13), color.withAlpha(26)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).shadowColor.withAlpha(20),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(color: color.withAlpha(51), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: isMobile ? 12 : 13,
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                padding: EdgeInsets.all(isMobile ? 4 : 6),
                decoration: BoxDecoration(
                  color: color.withAlpha(26),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(icon, color: color, size: isMobile ? 14 : 16),
              ),
            ],
          ),
          SizedBox(height: isMobile ? 6 : 8),
          Text(
            value,
            style: TextStyle(
              fontSize: isMobile ? 18 : 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          SizedBox(height: isMobile ? 2 : 4),
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              SizedBox(width: isMobile ? 3 : 4),
              Text(
                'Live',
                style: TextStyle(
                  fontSize: isMobile ? 9 : 10,
                  color: color,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGrowthAnalytics() {
    return DashboardCharts.buildGrowthAnalytics(
      growthData: _growthData,
      isLoading: _isLoadingCharts,
    );
  }

  // ignore: unused_element
  Widget _buildChartCard(
    String title,
    String subtitle,
    IconData icon,
    Color color,
    Widget chart,
  ) {
    final isMobile = MediaQuery.of(context).size.width < 480;
    return Container(
      padding: EdgeInsets.all(isMobile ? 16 : 20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).shadowColor.withAlpha(26),
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
                  color: color.withAlpha(26),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: isMobile ? 14 : 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: isMobile ? 11 : 12,
                        color: Theme.of(
                          context,
                        ).textTheme.bodyMedium?.color?.withAlpha(153),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: isMobile ? 12 : 16),
          Expanded(child: chart),
        ],
      ),
    );
  }

  // ignore: unused_element
  Widget _buildBarChart() {
    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: 20,
        barTouchData: BarTouchData(enabled: false),
        titlesData: FlTitlesData(
          show: true,
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (double value, TitleMeta meta) {
                final style = TextStyle(
                  color: Theme.of(
                    context,
                  ).textTheme.bodySmall?.color?.withAlpha(153),
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                );
                Widget text;
                switch (value.toInt()) {
                  case 0:
                    text = Text('Mon', style: style);
                    break;
                  case 1:
                    text = Text('Tue', style: style);
                    break;
                  case 2:
                    text = Text('Wed', style: style);
                    break;
                  case 3:
                    text = Text('Thu', style: style);
                    break;
                  case 4:
                    text = Text('Fri', style: style);
                    break;
                  case 5:
                    text = Text('Sat', style: style);
                    break;
                  case 6:
                    text = Text('Sun', style: style);
                    break;
                  default:
                    text = Text('', style: style);
                    break;
                }
                return SideTitleWidget(
                  axisSide: meta.axisSide,
                  space: 16,
                  child: text,
                );
              },
              reservedSize: 42,
            ),
          ),
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        borderData: FlBorderData(show: false),
        barGroups: [
          BarChartGroupData(
            x: 0,
            barRods: [
              BarChartRodData(
                toY: 8,
                color: Theme.of(context).colorScheme.primary,
              ),
            ],
          ),
          BarChartGroupData(
            x: 1,
            barRods: [
              BarChartRodData(
                toY: 10,
                color: Theme.of(context).colorScheme.primary,
              ),
            ],
          ),
          BarChartGroupData(
            x: 2,
            barRods: [
              BarChartRodData(
                toY: 14,
                color: Theme.of(context).colorScheme.primary,
              ),
            ],
          ),
          BarChartGroupData(
            x: 3,
            barRods: [
              BarChartRodData(
                toY: 15,
                color: Theme.of(context).colorScheme.primary,
              ),
            ],
          ),
          BarChartGroupData(
            x: 4,
            barRods: [
              BarChartRodData(
                toY: 13,
                color: Theme.of(context).colorScheme.primary,
              ),
            ],
          ),
          BarChartGroupData(
            x: 5,
            barRods: [
              BarChartRodData(
                toY: 10,
                color: Theme.of(context).colorScheme.primary,
              ),
            ],
          ),
          BarChartGroupData(
            x: 6,
            barRods: [
              BarChartRodData(
                toY: 16,
                color: Theme.of(context).colorScheme.primary,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChartsSection() {
    return DashboardCharts.buildChartsSection(
      dailySales: _dailySales,
      categorySales: _categorySales,
      dailyProfits: _dailyProfits,
      inventoryAging: _inventoryAging,
      isLoading: _isLoadingCharts,
    );
  }

  Widget _buildRealtimeMetrics() {
    return DashboardCharts.buildRealtimeMetrics(
      stats: _realtimeStats,
      isLoading: _isLoadingCharts,
    );
  }

  Widget _buildQuickActions() {
    final isMobile = MediaQuery.of(context).size.width < 480;
    // Check restriction
    final status = _businessProfile?.status?.toUpperCase();
    final isRestricted = ['PENDING', 'SUSPENDED', 'EXPIRED'].contains(status);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withAlpha(26),
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary.withAlpha(51),
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.flash_on,
                size: 16,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'Quick Actions',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        SizedBox(height: isMobile ? 12 : 16),

        // Highlighted Operations (Actions not already present in bottom navbar)
        if (!isRestricted)
          LayoutBuilder(
            builder: (context, constraints) {
              final isMobile = constraints.maxWidth < 640;
              return GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: isMobile ? 1 : 2,
                crossAxisSpacing: isMobile ? 10 : 12,
                mainAxisSpacing: isMobile ? 10 : 12,
                childAspectRatio: isMobile ? 4.0 : 4.0,
                children: [
                  _buildPrimaryActionCard(
                    'Add Product',
                    'Register new item into catalog',
                    Icons.add_box,
                    Theme.of(context).colorScheme.primary,
                  ),
                  _buildPrimaryActionCard(
                    'View Reports',
                    'Financial insights & performance',
                    Icons.bar_chart,
                    _twColor('purple'),
                  ),
                ],
              );
            },
          ),

        if (!isRestricted) SizedBox(height: isMobile ? 12 : 24),

        // Secondary Actions Grid (Focused on secondary operations)
        LayoutBuilder(
          builder: (context, constraints) {
            final crossAxisCount = constraints.maxWidth > 1024
                ? 4
                : constraints.maxWidth > 640
                ? 3
                : 2;
            return GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: constraints.maxWidth <= 480 ? 10 : 12,
              mainAxisSpacing: constraints.maxWidth <= 480 ? 10 : 12,
              childAspectRatio: constraints.maxWidth <= 480 ? 1.5 : 1.6,
              children: [
                _buildSecondaryActionCard(
                  'Business Settings',
                  Icons.business,
                  Theme.of(context).colorScheme.secondary,
                ),
                _buildSecondaryActionCard(
                  'Billing & Plans',
                  Icons.credit_card_rounded,
                  Colors.amber.shade700,
                ),
                _buildSecondaryActionCard(
                  'Payment Verification',
                  Icons.verified,
                  _statusColors(context).success,
                ),
                _buildSecondaryActionCard(
                  'Order History',
                  Icons.history,
                  _twColor('orange'),
                ),
                _buildSecondaryActionCard(
                  'Sales History',
                  Icons.trending_up,
                  _twColor('cyan'),
                ),
                _buildSecondaryActionCard(
                  'Purchase History',
                  Icons.receipt_long,
                  _twColor('blue'),
                ),
                if (!isRestricted)
                  _buildSecondaryActionCard(
                    'Process Returns',
                    Icons.undo,
                    _twColor('orange'),
                  ),
                if (!isRestricted)
                  _buildSecondaryActionCard(
                    'Process Replacements',
                    Icons.swap_horiz,
                    _twColor('blue'),
                  ),
                if (!isRestricted)
                  _buildSecondaryActionCard(
                    'Create Request',
                    Icons.people,
                    _statusColors(context).warning,
                  ),
                if (!isRestricted)
                  _buildSecondaryActionCard(
                    'Manage Requests',
                    Icons.settings,
                    _twColor('purple'),
                  ),
              ],
            );
          },
        ),

        const SizedBox(height: 24),

        // System Health - Separate Important Action
        _buildSystemHealthCard(),
      ],
    );
  }

  Widget _buildPrimaryActionCard(
    String title,
    String subtitle,
    IconData icon,
    Color color,
  ) {
    final isMobile = MediaQuery.of(context).size.width < 480;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        onTap: () {
          if (title == 'Add Product') {
            if (!_assertWritable(context, 'add a product')) return;
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => AddProductPage(db: widget.db),
              ),
            );
          } else if (title == 'View Reports') {
            if (!_assertFeature(context, 'reports', 'Reports & Analytics')) return;
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const ReportsPage()),
            );
          }
        },
        borderRadius: BorderRadius.circular(20),
        child: _HoverWrapper(
          hoverScale: 1.04,
          activeScale: 0.96,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          builder: (hovered) => AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.all(isMobile ? 16 : 20),
            constraints: const BoxConstraints(minHeight: 100),
            decoration: BoxDecoration(
              color: hovered
                  ? Theme.of(context).cardColor.withAlpha(242)
                  : Theme.of(context).cardColor.withAlpha(204),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: hovered ? color.withAlpha(128) : color.withAlpha(64),
                width: hovered ? 2 : 1.5,
              ),
              boxShadow: [
                // Primary shadow for depth
                BoxShadow(
                  color: color.withAlpha(hovered ? 51 : 26),
                  blurRadius: hovered ? 32 : 20,
                  offset: Offset(0, hovered ? 16 : 8),
                  spreadRadius: hovered ? 4 : 0,
                ),
                // Secondary shadow for realism
                BoxShadow(
                  color: Theme.of(
                    context,
                  ).shadowColor.withAlpha(hovered ? 31 : 15),
                  blurRadius: hovered ? 16 : 8,
                  offset: Offset(0, hovered ? 4 : 2),
                ),
              ],
            ),
            child: Stack(
              children: [
                // Animated gradient background
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          color.withAlpha(hovered ? 31 : 15),
                          Colors.transparent,
                          color.withAlpha(hovered ? 20 : 10),
                        ],
                      ),
                    ),
                  ),
                ),
                // Content
                Row(
                  children: [
                    // Enhanced icon container
                    Container(
                      width: isMobile ? 52 : 64,
                      height: isMobile ? 52 : 64,
                      decoration: BoxDecoration(
                        gradient: hovered
                            ? LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [color, color.withAlpha(204)],
                              )
                            : LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  color.withAlpha(51),
                                  color.withAlpha(38),
                                ],
                              ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: hovered
                              ? color.withAlpha(102)
                              : color.withAlpha(77),
                          width: 1.5,
                        ),
                        boxShadow: hovered
                            ? [
                                BoxShadow(
                                  color: color.withAlpha(102),
                                  blurRadius: 12,
                                  offset: const Offset(0, 6),
                                ),
                              ]
                            : null,
                      ),
                      child: Icon(
                        icon,
                        color: hovered ? Colors.white : color,
                        size: isMobile ? 28 : 32,
                      ),
                    ),
                    SizedBox(width: isMobile ? 16 : 20),
                    // Enhanced text content
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontSize: isMobile ? 18 : 20,
                              fontWeight: FontWeight.w700,
                              color: hovered
                                  ? color
                                  : Theme.of(
                                      context,
                                    ).textTheme.headlineSmall?.color,
                              letterSpacing: -0.3,
                              height: 1.2,
                            ),
                          ),
                          SizedBox(height: isMobile ? 4 : 6),
                          Text(
                            subtitle,
                            style: TextStyle(
                              fontSize: isMobile ? 13 : 14,
                              color: Theme.of(
                                context,
                              ).textTheme.bodyMedium?.color?.withAlpha(178),
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSecondaryActionCard(String title, IconData icon, Color color) {
    final isMobile = MediaQuery.of(context).size.width < 480;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        onTap: () {
          if (title == 'Add Product') {
            if (!_assertWritable(context, 'add a product')) return;
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => AddProductPage(db: widget.db),
              ),
            );
          } else if (title == 'View Inventory') {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const InventoryPage()),
            );
          } else if (title == 'Business Settings') {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const BusinessSettingsPage(),
              ),
            );
          } else if (title == 'Profile Settings') {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const ProfileSettingsPage(),
              ),
            );
          } else if (title == 'Requests') {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const RequestsPage()),
            );
          } else if (title == 'System Health') {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const SystemHealthPage()),
            );
          } else if (title == 'Sales History') {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const SalesHistoryPage()),
            );
          } else if (title == 'Purchase History') {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const PurchaseHistoryPage(),
              ),
            );
          } else if (title == 'Process Returns') {
            if (!_assertWritable(context, 'process a return')) return;
            if (!_assertFeature(context, 'returns', 'Customer Returns')) return;
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ReturnsPage(db: widget.db),
              ),
            );
          } else if (title == 'Process Replacements') {
            if (!_assertWritable(context, 'process a replacement')) return;
            if (!_assertFeature(context, 'returns', 'Customer Replacements')) return;
            Navigator.pushNamed(context, '/replacements');
          } else if (title == 'Create Request' || title == 'Manage Requests') {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const RequestsPage()),
            );
          } else if (title == 'Payment Verification') {
            Navigator.pushNamed(context, '/payments/verification');
          } else if (title == 'View Inventory') {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const InventoryPage()),
            );
          } else if (title == 'Add Product') {
            if (!_assertWritable(context, 'add a product')) return;
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => AddProductPage(db: widget.db),
              ),
            );
          } else if (title == 'Product Catalog') {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => CatalogPage(db: widget.db),
              ),
            );
          } else if (title == 'Sales History') {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const SalesHistoryPage()),
            );
          } else if (title == 'Order History') {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const OrderHistoryPage()),
            );
          } else if (title == 'Purchase History') {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const PurchaseHistoryPage(),
              ),
            );
          } else if (title == 'View Reports') {
            if (!_assertFeature(context, 'reports', 'Reports & Analytics')) return;
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const ReportsPage()),
            );
          } else if (title == 'Business Settings') {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const BusinessSettingsPage(),
              ),
            );
          } else if (title == 'Billing & Plans') {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => BillingPage(db: widget.db),
              ),
            );
          } else {
            // No-op: all known actions are handled above.
          }
        },
        borderRadius: BorderRadius.circular(16),
        child: _HoverWrapper(
          hoverScale: 1.05,
          activeScale: 0.96,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          builder: (hovered) => AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.all(isMobile ? 12 : 16),
            constraints: const BoxConstraints(minHeight: 100),
            decoration: BoxDecoration(
              color: hovered
                  ? Theme.of(context).cardColor.withAlpha(235)
                  : Theme.of(context).cardColor.withAlpha(191),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: hovered ? color.withAlpha(115) : color.withAlpha(64),
                width: hovered ? 1.8 : 1.2,
              ),
              boxShadow: [
                // Primary colored shadow
                BoxShadow(
                  color: color.withAlpha(hovered ? 46 : 26),
                  blurRadius: hovered ? 24 : 16,
                  offset: Offset(0, hovered ? 10 : 6),
                  spreadRadius: hovered ? 2 : 0,
                ),
                // Secondary depth shadow
                BoxShadow(
                  color: Theme.of(
                    context,
                  ).shadowColor.withAlpha(hovered ? 26 : 13),
                  blurRadius: hovered ? 12 : 8,
                  offset: Offset(0, hovered ? 4 : 2),
                ),
              ],
            ),
            child: Stack(
              children: [
                // Subtle gradient overlay
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          color.withAlpha(hovered ? 15 : 8),
                          Colors.transparent,
                          color.withAlpha(hovered ? 10 : 5),
                        ],
                      ),
                    ),
                  ),
                ),
                // Main content
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Enhanced icon container
                    Container(
                      width: isMobile ? 44 : 48,
                      height: isMobile ? 44 : 48,
                      decoration: BoxDecoration(
                        gradient: hovered
                            ? LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [color, color.withAlpha(204)],
                              )
                            : LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  color.withAlpha(38),
                                  color.withAlpha(26),
                                ],
                              ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: hovered
                              ? color.withAlpha(102)
                              : color.withAlpha(64),
                          width: 1.5,
                        ),
                        boxShadow: hovered
                            ? [
                                BoxShadow(
                                  color: color.withAlpha(89),
                                  blurRadius: 10,
                                  offset: const Offset(0, 5),
                                ),
                              ]
                            : null,
                      ),
                      child: Icon(
                        icon,
                        color: hovered ? Colors.white : color,
                        size: isMobile ? 20 : 22,
                      ),
                    ),
                    SizedBox(height: isMobile ? 12 : 16),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: isMobile ? 13 : 14,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).textTheme.bodyLarge?.color,
                        letterSpacing: 0.3,
                        height: 1.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSystemHealthCard() {
    final isMobile = MediaQuery.of(context).size.width < 480;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const SystemHealthPage()),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: _HoverWrapper(
          hoverScale: 1.02,
          activeScale: 0.98,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          builder: (hovered) => AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.all(isMobile ? 16 : 20),
            decoration: BoxDecoration(
              color: hovered
                  ? Theme.of(context).cardColor.withAlpha(229)
                  : Theme.of(context).cardColor.withAlpha(191),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: hovered
                    ? Theme.of(context).colorScheme.error.withAlpha(102)
                    : Theme.of(context).colorScheme.error.withAlpha(64),
                width: hovered ? 1.5 : 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Theme.of(
                    context,
                  ).colorScheme.error.withAlpha(hovered ? 38 : 20),
                  blurRadius: hovered ? 20 : 12,
                  offset: Offset(0, hovered ? 8 : 4),
                  spreadRadius: hovered ? 1 : 0,
                ),
                BoxShadow(
                  color: Theme.of(
                    context,
                  ).shadowColor.withAlpha(hovered ? 20 : 10),
                  blurRadius: hovered ? 10 : 6,
                  offset: Offset(0, hovered ? 3 : 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: hovered
                        ? Theme.of(context).colorScheme.error
                        : Theme.of(context).colorScheme.error.withAlpha(26),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: hovered
                          ? Theme.of(context).colorScheme.error
                          : Theme.of(context).colorScheme.error.withAlpha(51),
                      width: 1,
                    ),
                  ),
                  child: Icon(
                    Icons.warning,
                    color: hovered
                        ? Colors.white
                        : Theme.of(context).colorScheme.error,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'System Health Check',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? (hovered
                                    ? Colors.red.shade200
                                    : Colors.red.shade300)
                              : (hovered
                                    ? Colors.red.shade600
                                    : Colors.red.shade700),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Monitor system status',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? (hovered
                                    ? Colors.red.shade300
                                    : Colors.red.shade400)
                              : (hovered
                                    ? Colors.red.shade500
                                    : Colors.red.shade600),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showThemeDialog() {
    // Simple toggle like SvelteKit version
    final currentBrightness = Theme.of(context).brightness;
    final newThemeMode = currentBrightness == Brightness.dark
        ? ThemeMode.light
        : ThemeMode.dark;

    widget.onThemeChanged?.call(newThemeMode);
  }
}

// Hover wrapper to provide hover state and smooth animations for desktop/web
// Usage: _HoverWrapper(builder: (hovered) => ...)
class _HoverWrapper extends StatefulWidget {
  final Widget Function(bool hovered) builder;
  final double hoverScale;
  final double activeScale;
  final Duration duration;
  final Curve curve;
  const _HoverWrapper({
    required this.builder,
    this.hoverScale = 1.015,
    this.activeScale = 0.95,
    this.duration = const Duration(milliseconds: 160),
    this.curve = Curves.easeOut,
  });

  @override
  State<_HoverWrapper> createState() => _HoverWrapperState();
}

class _HoverWrapperState extends State<_HoverWrapper> {
  bool _hovered = false;
  bool _pressed = false;
  @override
  Widget build(BuildContext context) {
    final targetScale = _pressed
        ? widget.activeScale
        : (_hovered ? widget.hoverScale : 1.0);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Listener(
        onPointerDown: (_) => setState(() => _pressed = true),
        onPointerUp: (_) => setState(() => _pressed = false),
        onPointerCancel: (_) => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: targetScale,
          duration: widget.duration,
          curve: widget.curve,
          child: widget.builder(_hovered),
        ),
      ),
    );
  }
}
