import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';
import '../theme/ui_tokens.dart';
import '../models/sales_purchase_models.dart' as models;
import '../services/supabase_service.dart';
import '../services/connectivity_service.dart';
import '../widgets/page_header.dart';
import '../widgets/search_bar_widget.dart';

class PurchaseHistoryPage extends StatefulWidget {
  const PurchaseHistoryPage({super.key});

  @override
  State<PurchaseHistoryPage> createState() => _PurchaseHistoryPageState();
}

class _PurchaseHistoryPageState extends State<PurchaseHistoryPage> {
  // Search and filter states
  String _searchTerm = '';
  String _dealerFilter = '';
  String _minAmount = '';
  String _maxAmount = '';
  String _statusFilter = 'all'; // all, problematic, normal

  // Pagination and performance optimizations
  final ScrollController _scrollController = ScrollController();
  Timer? _searchDebounce;
  int _currentPage = 1;
  int _itemsPerPage = 25;

  // UI states
  bool _showFilters = false;
  bool _showBulkActions = false;
  int? _expandedPurchaseId;

  // Selection states
  Set<int> _selectedPurchases = <int>{};

  // Data states
  List<models.Purchase> _purchases = [];
  List<models.Purchase> _filteredPurchases = [];
  bool _isLoading = true;
  String? _error;
  DateTimeRange? _dateRange;
  final String _sortBy = 'Date';

  @override
  void initState() {
    super.initState();
    _loadPurchases();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _searchTerm = query;
          _currentPage = 1;
          _filterAndSortPurchases();
        });
      }
    });
  }

  Future<void> _confirmAndDeletePurchase(models.Purchase purchase) async {
    if (!ConnectivityService().isOnline.value) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You are offline. Cannot delete purchase.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final items = _safePurchaseItems(purchase);
    final hasItems = items.isNotEmpty;
    final rootContext = context; // keep a stable context
    final messenger = ScaffoldMessenger.of(rootContext); // cache messenger
    bool isDeleting = false;
    await showDialog(
      context: rootContext,
      barrierDismissible: !isDeleting,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: const Text('Delete Purchase'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'PUR-${purchase.id} • ${purchase.supplierName ?? 'Unknown Supplier'}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    hasItems
                        ? 'This will delete the purchase and its items, and roll back product stock accordingly.'
                        : 'This purchase has no items. It will be deleted.',
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isDeleting
                      ? null
                      : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: isDeleting
                      ? null
                      : () async {
                          setLocalState(() => isDeleting = true);
                          bool ok = false;
                          try {
                            if (hasItems) {
                              ok = await SupabaseService.deletePurchaseSafely(
                                purchase.id!,
                              );
                            } else {
                              ok = await SupabaseService.deleteEmptyPurchase(
                                purchase.id!,
                              );
                            }
                          } catch (_) {
                            ok = false;
                          }
                          if (!mounted) return;
                          Navigator.of(rootContext).pop();
                          if (ok) {
                            await _loadPurchases();
                            if (mounted) {
                              messenger.showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Purchase deleted successfully',
                                  ),
                                ),
                              );
                            }
                          } else {
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text('Failed to delete purchase'),
                              ),
                            );
                          }
                        },
                  icon: isDeleting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.delete_outline),
                  label: const Text('Delete'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                    foregroundColor: Theme.of(context).colorScheme.onError,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Defensive fallback for legacy runtime instances after hot reload
  List<models.PurchaseItem> _safePurchaseItems(models.Purchase p) {
    try {
      final list = p.purchaseItems;
      return list;
    } catch (_) {
      return const <models.PurchaseItem>[];
    }
  }

  Future<void> _loadPurchases() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      if (mounted) {
        final purchases = await SupabaseService.getPurchases();
        setState(() {
          _purchases = purchases;
          _isLoading = false;
        });
        _filterAndSortPurchases();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _filterAndSortPurchases() {
    List<models.Purchase> filtered = _purchases;

    // Apply search filter
    if (_searchTerm.isNotEmpty) {
      final searchLower = _searchTerm.toLowerCase().trim();
      filtered = filtered.where((purchase) {
        return (purchase.supplierName?.toLowerCase().contains(searchLower) ??
                false) ||
            (purchase.supplierPhone?.toLowerCase().contains(searchLower) ??
                false) ||
            (purchase.billNumber?.toLowerCase().contains(searchLower) ??
                false) ||
            'pur-${purchase.id}'.toLowerCase().contains(searchLower) ||
            '${purchase.id}'.contains(searchLower) ||
            (purchase.paymentMethod.toLowerCase().contains(searchLower));
      }).toList();
    }

    // Apply dealer filter
    if (_dealerFilter.isNotEmpty) {
      final dealerLower = _dealerFilter.toLowerCase();
      filtered = filtered.where((purchase) {
        return purchase.supplierName?.toLowerCase().contains(dealerLower) ??
            false;
      }).toList();
    }

    // Apply amount filters
    if (_minAmount.isNotEmpty) {
      final minAmt = double.tryParse(_minAmount) ?? 0;
      filtered = filtered
          .where((purchase) => purchase.totalAmount >= minAmt)
          .toList();
    }
    if (_maxAmount.isNotEmpty) {
      final maxAmt = double.tryParse(_maxAmount) ?? double.infinity;
      filtered = filtered
          .where((purchase) => purchase.totalAmount <= maxAmt)
          .toList();
    }

    // Apply date range filter
    if (_dateRange != null) {
      filtered = filtered.where((purchase) {
        final purchaseDate = purchase.createdAt ?? DateTime.now();
        return purchaseDate.isAfter(
              _dateRange!.start.subtract(const Duration(days: 1)),
            ) &&
            purchaseDate.isBefore(_dateRange!.end.add(const Duration(days: 1)));
      }).toList();
    }

    // Apply status filter
    if (_statusFilter == 'problematic') {
      filtered = filtered
          .where((purchase) => _isProblematicPurchase(purchase))
          .toList();
    } else if (_statusFilter == 'normal') {
      filtered = filtered
          .where((purchase) => !_isProblematicPurchase(purchase))
          .toList();
    }

    // Apply sorting
    switch (_sortBy) {
      case 'Date':
        filtered.sort(
          (a, b) => (b.createdAt ?? DateTime.now()).compareTo(
            a.createdAt ?? DateTime.now(),
          ),
        );
        break;
      case 'Amount':
        filtered.sort((a, b) => b.totalAmount.compareTo(a.totalAmount));
        break;
      case 'Supplier':
        filtered.sort(
          (a, b) => (a.supplierName ?? '').compareTo(b.supplierName ?? ''),
        );
        break;
    }

    setState(() {
      _filteredPurchases = filtered;
      _currentPage = 1;
    });
  }

  int get _totalPages => (_filteredPurchases.length / _itemsPerPage).ceil();

  List<models.Purchase> get _paginatedPurchases {
    final startIndex = (_currentPage - 1) * _itemsPerPage;
    if (startIndex >= _filteredPurchases.length) return [];
    final endIndex = startIndex + _itemsPerPage;
    return _filteredPurchases.sublist(
      startIndex,
      endIndex > _filteredPurchases.length
          ? _filteredPurchases.length
          : endIndex,
    );
  }

  void _changePage(int page) {
    if (page < 1 || (page > _totalPages && _totalPages > 0)) return;
    setState(() {
      _currentPage = page;
    });
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  bool _isProblematicPurchase(models.Purchase purchase) {
    // Match SvelteKit problematic purchase detection logic
    // Check for missing or empty supplier name
    if (purchase.supplierName == null ||
        purchase.supplierName!.trim().isEmpty) {
      return true;
    }

    // Check for missing purchase items (use safe fallback in case of legacy instances)
    final items = _safePurchaseItems(purchase);
    if (items.isEmpty) {
      return true;
    }

    // Check for missing product relations or invalid quantities/prices
    for (final item in items) {
      if (item.product == null) return true;
      if (item.quantity <= 0 || item.pricePerUnit <= 0) return true;
    }

    return false;
  }

  double _calculateTotalValue() {
    return _filteredPurchases.fold(
      0.0,
      (sum, purchase) => sum + purchase.totalAmount,
    );
  }

  int _getUniqueDealersCount() {
    return _purchases.map((p) => p.supplierName ?? 'Unknown').toSet().length;
  }

  List<String> _getUniqueDealers() {
    return _purchases
        .map((p) => p.supplierName)
        .where((name) => name != null && name.trim().isNotEmpty)
        .map((name) => name!)
        .toSet()
        .toList();
  }

  Widget _buildSkeletonLoading(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? (Colors.grey[850] ?? Colors.grey[800]!) : Colors.grey[300]!;
    final highlight = isDark ? Colors.grey[700]! : Colors.grey[100]!;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        top: false,
        bottom: true,
        child: SingleChildScrollView(
          child: Column(
            children: [
              PageHeader(
                title: 'Purchase History',
                description: 'Track, manage, and analyze purchase records',
                icon: '🛒',
                showBackButton: true,
                backLabel: 'Back to Dashboard',
                wrapInSafeArea: true,
                breadcrumbs: [
                  PageHeaderBreadcrumb(label: 'Dashboard', icon: '🏠', href: '/'),
                  if (MediaQuery.of(context).size.width >= 450)
                    PageHeaderBreadcrumb(
                      label: 'Purchase History',
                      icon: '🛒',
                      current: true,
                    ),
                ],
                stats: [
                  PageHeaderStat(
                    label: 'Total Purchases',
                    value: '...',
                    description: 'Loading...',
                  ),
                  PageHeaderStat(
                    label: 'Status',
                    value: 'Syncing',
                    description: 'Fetching live data',
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1100),
                    child: Column(
                      children: [
                        // Skeleton 2x2 grid stats
                        GridView.count(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisCount: 2,
                          childAspectRatio: 2.1,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          children: List.generate(
                            4,
                            (_) => Shimmer.fromColors(
                              baseColor: base,
                              highlightColor: highlight,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Theme.of(context).cardColor,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Skeleton search bar
                        Shimmer.fromColors(
                          baseColor: base,
                          highlightColor: highlight,
                          child: Container(
                            height: 52,
                            decoration: BoxDecoration(
                              color: Theme.of(context).cardColor,
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        // Skeleton purchase cards
                        ...List.generate(
                          3,
                          (_) => Shimmer.fromColors(
                            baseColor: base,
                            highlightColor: highlight,
                            child: Container(
                              height: 140,
                              margin: const EdgeInsets.only(bottom: 16),
                              decoration: BoxDecoration(
                                color: Theme.of(context).cardColor,
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return _buildSkeletonLoading(context);
    }
    if (_error != null) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: _buildErrorState(),
      );
    }
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        top: false,
        bottom: true,
        child: SingleChildScrollView(
          controller: _scrollController,
          child: _buildContent(),
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 64,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 16),
          Text(
            'Error loading purchases',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _error!,
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loadPurchases,
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
            ),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return Column(
      children: [
        // Page Header
        PageHeader(
          title: 'Purchase History',
          description: 'Track, manage, and analyze purchase records',
          icon: '🛒',
          showBackButton: true,
          backLabel: 'Back to Dashboard',
          wrapInSafeArea: true,
          breadcrumbs: [
            PageHeaderBreadcrumb(label: 'Dashboard', icon: '🏠', href: '/'),
            if (MediaQuery.of(context).size.width >= 450)
              PageHeaderBreadcrumb(
                label: 'Purchase History',
                icon: '🛒',
                current: true,
              ),
          ],
          stats: [
            PageHeaderStat(
              label: 'Total Purchases',
              value: '${_purchases.length}',
              description: 'All purchase records',
            ),
            PageHeaderStat(
              label: 'Status',
              value: 'Live Data',
              description: 'Real-time tracking',
            ),
          ],
          actions: [
            PageHeaderAction(
              label: 'New Purchase',
              shortLabel: 'Add Purchase',
              icon: Icons.add,
              color: Theme.of(context).colorScheme.primary,
              onPressed: () => Navigator.pushNamed(context, '/purchase'),
            ),
          ],
        ),

        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: MediaQuery.of(context).size.width < 480 ? 12 : 16,
            vertical: MediaQuery.of(context).size.width < 480 ? 12 : 16,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: Column(
                children: [
                  // Action Buttons
                  _buildActionButtons(),
                  const SizedBox(height: 16),

                  // Search Bar
                  SearchBarWidget(
                    placeholder:
                        'Search by dealer, bill, phone, or payment...',
                    entityName: 'purchases',
                    onSearchChanged: _onSearchChanged,
                    resultCount: _searchTerm.isNotEmpty
                        ? _filteredPurchases.length
                        : null,
                    totalCount: _searchTerm.isNotEmpty
                        ? _purchases.length
                        : null,
                  ),
                  const SizedBox(height: 16),

                  // Statistics Cards (2x2 grid on mobile)
                  _buildStatisticsCards(),
                  const SizedBox(height: 20),

                  // Filters Panel
                  if (_showFilters) ...[
                    _buildFiltersPanel(),
                    const SizedBox(height: 20),
                  ],

                  // Bulk Actions Panel
                  if (_showBulkActions) ...[
                    _buildBulkActionsPanel(),
                    const SizedBox(height: 20),
                  ],

                  // Purchase Cards
                  _buildPurchaseCards(),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        // Filters Button
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () {
              setState(() {
                _showFilters = !_showFilters;
              });
            },
            icon: Icon(
              Icons.filter_list,
              size: 18,
              color: _showFilters
                  ? Theme.of(context).colorScheme.onPrimary
                  : Theme.of(context).colorScheme.primary,
            ),
            label: Text(
              'Filters',
              style: TextStyle(
                color: _showFilters
                    ? Theme.of(context).colorScheme.onPrimary
                    : Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: _showFilters
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(
                      context,
                    ).colorScheme.primaryContainer.withValues(alpha: 0.3),
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.3),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Bulk Actions Button
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () {
              setState(() {
                _showBulkActions = !_showBulkActions;
              });
            },
            icon: Icon(
              Icons.checklist,
              size: 18,
              color: _showBulkActions
                  ? Theme.of(context).colorScheme.onSecondary
                  : Theme.of(context).colorScheme.secondary,
            ),
            label: Text(
              _selectedPurchases.isNotEmpty
                  ? 'Bulk (${_selectedPurchases.length})'
                  : 'Bulk Actions',
              style: TextStyle(
                color: _showBulkActions
                    ? Theme.of(context).colorScheme.onSecondary
                    : Theme.of(context).colorScheme.secondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: _showBulkActions
                  ? Theme.of(context).colorScheme.secondary
                  : Theme.of(
                      context,
                    ).colorScheme.secondaryContainer.withValues(alpha: 0.3),
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: Theme.of(
                    context,
                  ).colorScheme.secondary.withValues(alpha: 0.3),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatisticsCards() {
    final totalVal = _calculateTotalValue();
    final uniqueDealers = _getUniqueDealersCount();

    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final cross = w >= 900
            ? 4
            : w >= 550
            ? 4
            : 2; // Always at least 2 columns on mobile (2x2 grid)
        final aspect = w < 380
            ? 2.0
            : w < 550
            ? 2.2
            : 2.4;
        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: cross,
          childAspectRatio: aspect,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          children: [
            _buildStatCard(
              'Total Purchases',
              '${_purchases.length}',
              Icons.shopping_cart,
              Colors.blue,
            ),
            _buildStatCard(
              'Filtered',
              '${_filteredPurchases.length}',
              Icons.filter_list,
              Colors.green,
            ),
            _buildStatCard(
              'Unique Dealers',
              '$uniqueDealers',
              Icons.people,
              Colors.orange,
            ),
            _buildStatCard(
              'Total Value',
              NumberFormat.currency(
                symbol: '₹',
                decimalDigits: 0,
                locale: 'en_IN',
              ).format(totalVal),
              Icons.trending_up,
              Colors.purple,
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Live',
                  style: TextStyle(
                    fontSize: 9,
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFiltersPanel() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.05),
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
              Icon(
                Icons.filter_list,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'Filter Purchases',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, c) {
              final w = c.maxWidth;
              final cols = w >= 1000
                  ? 4
                  : w >= 700
                  ? 3
                  : w >= 480
                  ? 2
                  : 1;
              final aspect = w < 360
                  ? 2.2
                  : w < 480
                  ? 2.6
                  : 3.0;
              return GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: cols,
                childAspectRatio: aspect,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                children: [
                  _buildDealerFilterField(),
                  _buildFilterField(
                    'Min Amount',
                    _minAmount,
                    (value) => setState(() => _minAmount = value),
                  ),
                  _buildFilterField(
                    'Max Amount',
                    _maxAmount,
                    (value) => setState(() => _maxAmount = value),
                  ),
                  _buildStatusFilter(),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, c) {
              final narrow = c.maxWidth < 480;
              final clearButton = ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _dealerFilter = '';
                    _minAmount = '';
                    _maxAmount = '';
                    _statusFilter = 'all';
                    _dateRange = null;
                  });
                  _filterAndSortPurchases();
                },
                icon: const Icon(Icons.clear),
                label: const Text('Clear Filters'),
              );
              final summaryText = Text(
                'Showing ${_filteredPurchases.length} of ${_purchases.length} purchases',
              );
              if (narrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    clearButton,
                    const SizedBox(height: 12),
                    summaryText,
                  ],
                );
              }
              return Row(children: [clearButton, const Spacer(), summaryText]);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDealerFilterField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Dealer Name',
          style: TextStyle(
            fontWeight: FontWeight.w500,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 4),
        LayoutBuilder(
          builder: (context, constraints) {
            return Autocomplete<String>(
              optionsBuilder: (TextEditingValue textEditingValue) {
                if (textEditingValue.text.isEmpty) {
                  return const Iterable<String>.empty();
                }
                return _getUniqueDealers().where((String option) {
                  return option.toLowerCase().contains(
                    textEditingValue.text.toLowerCase(),
                  );
                });
              },
              onSelected: (String selection) {
                setState(() {
                  _dealerFilter = selection;
                });
                _filterAndSortPurchases();
              },
              fieldViewBuilder:
                  (
                    context,
                    textEditingController,
                    focusNode,
                    onFieldSubmitted,
                  ) {
                    // Keep controller in sync if filter is cleared externally
                    if (textEditingController.text != _dealerFilter) {
                      // Only update if they differ significantly (avoid cursor jump issues if we were editing)
                      // But here, _dealerFilter is the source of truth when cleared.
                      // If user types, _dealerFilter updates via onChanged.
                      // If we clear filter, _dealerFilter becomes empty.
                      // So we should safe sync.
                      if (_dealerFilter.isEmpty &&
                          textEditingController.text.isNotEmpty) {
                        textEditingController.text = '';
                      }
                    }

                    return TextField(
                      controller: textEditingController,
                      focusNode: focusNode,
                      onChanged: (val) {
                        setState(() => _dealerFilter = val);
                        _filterAndSortPurchases();
                      },
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        suffixIcon: _dealerFilter.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () {
                                  setState(() => _dealerFilter = '');
                                  textEditingController.clear();
                                  _filterAndSortPurchases();
                                },
                              )
                            : null,
                      ),
                    );
                  },
            );
          },
        ),
      ],
    );
  }

  Widget _buildFilterField(
    String label,
    String value,
    Function(String) onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w500,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: TextEditingController(text: value),
          onChanged: (val) {
            onChanged(val);
            _filterAndSortPurchases();
          },
          decoration: InputDecoration(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusFilter() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Status',
          style: TextStyle(
            fontWeight: FontWeight.w500,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 4),
        DropdownButtonFormField<String>(
          initialValue: _statusFilter,
          onChanged: (value) {
            setState(() => _statusFilter = value!);
            _filterAndSortPurchases();
          },
          decoration: InputDecoration(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
          ),
          items: const [
            DropdownMenuItem(value: 'all', child: Text('All Purchases')),
            DropdownMenuItem(
              value: 'problematic',
              child: Text('Problematic Only'),
            ),
            DropdownMenuItem(value: 'normal', child: Text('Normal Only')),
          ],
        ),
      ],
    );
  }

  Widget _buildBulkActionsPanel() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.05),
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
              Icon(
                Icons.checklist,
                color: Theme.of(context).colorScheme.secondary,
              ),
              const SizedBox(width: 8),
              Text(
                'Bulk Actions',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const Spacer(),
              Text(
                '${_selectedPurchases.length} selected',
                style: TextStyle(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_selectedPurchases.isNotEmpty)
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: () {
                    // Implement bulk delete
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Bulk delete feature coming soon'),
                      ),
                    );
                  },
                  icon: const Icon(Icons.delete),
                  label: const Text('Delete Selected'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.errorContainer,
                    foregroundColor: Theme.of(
                      context,
                    ).colorScheme.onErrorContainer,
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: () => setState(() => _selectedPurchases.clear()),
                  icon: const Icon(Icons.clear),
                  label: const Text('Clear Selection'),
                ),
              ],
            )
          else
            const Text('Select purchases to perform bulk actions'),
        ],
      ),
    );
  }

  Widget _buildPurchaseCards() {
    if (_filteredPurchases.isEmpty) {
      return Center(
        child: Column(
          children: [
            Icon(
              Icons.shopping_cart_outlined,
              size: 64,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              'No purchases found',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Try adjusting your filters or add a new purchase',
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      );
    }

    final paginated = _paginatedPurchases;

    return Column(
      children: [
        // Bulk select header
        if (_showBulkActions) _buildBulkSelectHeader(),

        // Purchase cards (paginated)
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: paginated.length,
          itemBuilder: (context, index) {
            final purchase = paginated[index];
            return _buildPurchaseCard(purchase);
          },
        ),

        // Pagination controls
        if (_filteredPurchases.isNotEmpty) ...[
          const SizedBox(height: 20),
          _buildPaginationControls(),
        ],
      ],
    );
  }

  Widget _buildPaginationControls() {
    final startIndex = (_currentPage - 1) * _itemsPerPage;
    final startItem = _filteredPurchases.isEmpty ? 0 : startIndex + 1;
    final endItem = (_currentPage * _itemsPerPage > _filteredPurchases.length)
        ? _filteredPurchases.length
        : _currentPage * _itemsPerPage;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(
            context,
          ).colorScheme.outline.withValues(alpha: 0.1),
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(
              context,
            ).colorScheme.shadow.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Items per page:',
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(width: 8),
                  DropdownButton<int>(
                    value: _itemsPerPage,
                    underline: Container(),
                    items: [10, 25, 50, 100].map((int value) {
                      return DropdownMenuItem<int>(
                        value: value,
                        child: Text('$value'),
                      );
                    }).toList(),
                    onChanged: (int? newValue) {
                      if (newValue != null) {
                        setState(() {
                          _itemsPerPage = newValue;
                          _currentPage = 1;
                        });
                      }
                    },
                  ),
                ],
              ),
              Text(
                'Showing $startItem-$endItem of ${_filteredPurchases.length} purchases',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
          if (_totalPages > 1) ...[
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    onPressed: _currentPage > 1
                        ? () => _changePage(1)
                        : null,
                    icon: const Icon(Icons.first_page),
                    tooltip: 'First page',
                  ),
                  IconButton(
                    onPressed: _currentPage > 1
                        ? () => _changePage(_currentPage - 1)
                        : null,
                    icon: const Icon(Icons.chevron_left),
                    tooltip: 'Previous page',
                  ),
                  const SizedBox(width: 8),
                  ...List.generate(_totalPages, (index) {
                    final pageNum = index + 1;
                    final isCurrentPage = pageNum == _currentPage;
                    final showPage =
                        pageNum == 1 ||
                        pageNum == _totalPages ||
                        (pageNum >= _currentPage - 2 &&
                            pageNum <= _currentPage + 2);

                    if (!showPage) {
                      if (pageNum == _currentPage - 3 ||
                          pageNum == _currentPage + 3) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 4),
                          child: Text('...'),
                        );
                      }
                      return const SizedBox.shrink();
                    }

                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: isCurrentPage
                              ? null
                              : () => _changePage(pageNum),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: isCurrentPage
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isCurrentPage
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(
                                        context,
                                      ).colorScheme.outline.withValues(alpha: 0.2),
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              '$pageNum',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isCurrentPage
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: isCurrentPage
                                    ? Theme.of(context).colorScheme.onPrimary
                                    : Theme.of(
                                        context,
                                      ).colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _currentPage < _totalPages
                        ? () => _changePage(_currentPage + 1)
                        : null,
                    icon: const Icon(Icons.chevron_right),
                    tooltip: 'Next page',
                  ),
                  IconButton(
                    onPressed: _currentPage < _totalPages
                        ? () => _changePage(_totalPages)
                        : null,
                    icon: const Icon(Icons.last_page),
                    tooltip: 'Last page',
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBulkSelectHeader() {
    final allSelected =
        _selectedPurchases.length == _filteredPurchases.length &&
        _filteredPurchases.isNotEmpty;
    final someSelected =
        _selectedPurchases.isNotEmpty &&
        _selectedPurchases.length < _filteredPurchases.length;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Checkbox(
            value: allSelected,
            tristate: true,
            onChanged: (value) {
              setState(() {
                if (allSelected) {
                  _selectedPurchases.clear();
                } else {
                  _selectedPurchases = _filteredPurchases
                      .map((p) => p.id!)
                      .toSet();
                }
              });
            },
          ),
          Text(
            allSelected
                ? 'All ${_filteredPurchases.length} purchases selected'
                : someSelected
                ? '${_selectedPurchases.length} of ${_filteredPurchases.length} purchases selected'
                : 'Select all purchases',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPurchaseCard(models.Purchase purchase) {
    final isProblematic = _isProblematicPurchase(purchase);
    final isSelected = _selectedPurchases.contains(purchase.id);
    final isExpanded = _expandedPurchaseId == purchase.id;
    final List<models.PurchaseItem> items = _safePurchaseItems(purchase);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isProblematic
              ? Theme.of(context).colorScheme.error
              : Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Status indicator - gradient strip (red if problematic, blue if normal)
          Container(
            width: double.infinity,
            height: 4,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isProblematic
                    ? [
                        Theme.of(context).colorScheme.error,
                        Theme.of(
                          context,
                        ).colorScheme.error.withValues(alpha: 0.8),
                        Theme.of(context).colorScheme.error,
                      ]
                    : [Colors.blue, Colors.lightBlueAccent, Colors.blue],
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
          ),

          // Card content
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Header
                Row(
                  children: [
                    if (_showBulkActions)
                      Checkbox(
                        value: isSelected,
                        onChanged: (value) {
                          setState(() {
                            if (value!) {
                              _selectedPurchases.add(purchase.id!);
                            } else {
                              _selectedPurchases.remove(purchase.id!);
                            }
                          });
                        },
                      ),

                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.shopping_cart,
                        color: Colors.blue,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'PUR-${purchase.id}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                              if (isProblematic) ...[
                                const SizedBox(width: 6),
                                const Icon(
                                  Icons.warning,
                                  color: Colors.red,
                                  size: 16,
                                ),
                              ],
                            ],
                          ),
                          Text(
                            DateFormat('d/M/yyyy, h:mm:ss a').format(
                              (purchase.createdAt ?? DateTime.now()).toLocal(),
                            ),
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withValues(alpha: 0.6),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Status badge (green for normal, red for problematic)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: isProblematic
                            ? Colors.red.withValues(alpha: 0.12)
                            : Colors.green.withValues(alpha: 0.12),
                        border: Border.all(
                          color: isProblematic
                              ? Colors.red.withValues(alpha: 0.3)
                              : Colors.green.withValues(alpha: 0.3),
                        ),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isProblematic ? Icons.warning_amber : Icons.check,
                            size: 14,
                            color: isProblematic ? Colors.red : Colors.green,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            isProblematic ? 'Issues Found' : 'Normal',
                            style: TextStyle(
                              color: isProblematic ? Colors.red : Colors.green,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                // Content grid
                LayoutBuilder(
                  builder: (context, c) {
                    final isWide = c.maxWidth >= 900;

                    final col1 = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'DEALER DETAILS',
                          style: TextStyle(
                            fontSize: 10,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.6),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(
                              Icons.person,
                              size: 15,
                              color: Colors.brown,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                purchase.supplierName ?? 'Unknown Supplier',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.receipt_long,
                              size: 14,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Bill: ${purchase.billNumber ?? 'N/A'}',
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.7),
                                fontSize: 12,
                              ),
                            ),
                            if (purchase.supplierPhone != null &&
                                purchase.supplierPhone!.isNotEmpty) ...[
                              const SizedBox(width: 12),
                              Icon(
                                Icons.phone,
                                size: 13,
                                color: Theme.of(context).colorScheme.secondary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                purchase.supplierPhone!,
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface.withValues(alpha: 0.7),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    );

                    final actionRow = Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => setState(
                              () => _expandedPurchaseId =
                                  isExpanded ? null : purchase.id,
                            ),
                            icon: Icon(
                              isExpanded ? Icons.visibility_off : Icons.visibility,
                              size: 14,
                            ),
                            label: Text(
                              isExpanded ? 'Hide' : 'Details',
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _showEditDialog(purchase),
                            icon: const Icon(Icons.edit, size: 14),
                            label: const Text(
                              'Edit',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              foregroundColor: Colors.white,
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () =>
                                _confirmAndDeletePurchase(purchase),
                            icon: const Icon(Icons.delete_outline, size: 14),
                            label: const Text(
                              'Delete',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Theme.of(context).colorScheme.error,
                              foregroundColor:
                                  Theme.of(context).colorScheme.onError,
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );

                    if (isWide) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(flex: 3, child: col1),
                          const SizedBox(width: 16),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                NumberFormat.currency(
                                  locale: 'en_IN',
                                  symbol: '₹',
                                  decimalDigits: 2,
                                ).format(purchase.totalAmount),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue,
                                  fontSize: 18,
                                ),
                              ),
                              const SizedBox(height: 4),
                              InkWell(
                                onTap: () => setState(
                                  () => _expandedPurchaseId =
                                      isExpanded ? null : purchase.id,
                                ),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.purple.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    isExpanded
                                        ? 'Hide items'
                                        : 'View items (${items.length})',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.purple,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(width: 24),
                          Expanded(flex: 3, child: actionRow),
                        ],
                      );
                    } else {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: col1),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    NumberFormat.currency(
                                      locale: 'en_IN',
                                      symbol: '₹',
                                      decimalDigits: 2,
                                    ).format(purchase.totalAmount),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue,
                                      fontSize: 18,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  InkWell(
                                    onTap: () => setState(
                                      () => _expandedPurchaseId =
                                          isExpanded ? null : purchase.id,
                                    ),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.purple.withValues(
                                          alpha: 0.08,
                                        ),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        isExpanded
                                            ? 'Hide items'
                                            : 'View items (${items.length})',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.purple,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          actionRow,
                        ],
                      );
                    }
                  },
                ),

                // Expanded details
                if (isExpanded) ...[
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 16),
                  _buildExpandedDetails(purchase),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(models.Purchase purchase) {
    final formKey = GlobalKey<FormState>();
    final dealerCtrl = TextEditingController(text: purchase.supplierName ?? '');
    final billCtrl = TextEditingController(text: purchase.billNumber ?? '');
    DateTime createdAt = purchase.createdAt ?? DateTime.now();
    final items = _safePurchaseItems(purchase);
    // Mutable local copy for editing
    final List<Map<String, dynamic>> editItems = items
        .map(
          (it) => {
            'id': it.id,
            'product_id': it.productId,
            'name': it.product?.name ?? '',
            'brand': it.product?.brand ?? '',
            'quantity': it.quantity,
            'price_per_unit': it.pricePerUnit,
          },
        )
        .toList();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        bool isSaving = false;
        return StatefulBuilder(
          builder: (context, setLocalState) {
            double total = editItems.fold<double>(
              0.0,
              (sum, e) =>
                  sum +
                  ((e['quantity'] as num).toDouble() *
                      (e['price_per_unit'] as num).toDouble()),
            );
            return AlertDialog(
              title: Text('Edit Purchase PUR-${purchase.id}'),
              content: Form(
                key: formKey,
                child: SizedBox(
                  width: 560,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Dealer and Bill
                        TextFormField(
                          controller: dealerCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Dealer Name *',
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Required'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: billCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Bill Number',
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Purchase Date: ${DateFormat('d/M/yyyy, h:mm a').format(createdAt)}',
                              ),
                            ),
                            TextButton(
                              onPressed: () async {
                                final date = await showDatePicker(
                                  context: context,
                                  initialDate: createdAt,
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime(2100),
                                );
                                if (date != null) {
                                  final time = await showTimePicker(
                                    context: context,
                                    initialTime: TimeOfDay.fromDateTime(
                                      createdAt,
                                    ),
                                  );
                                  if (time != null) {
                                    setLocalState(() {
                                      createdAt = DateTime(
                                        date.year,
                                        date.month,
                                        date.day,
                                        time.hour,
                                        time.minute,
                                      );
                                    });
                                  }
                                }
                              },
                              child: const Text('Change'),
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),
                        Text(
                          'Purchase Items',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        ...editItems.asMap().entries.map((entry) {
                          final e = entry.value;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.surfaceContainer,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Theme.of(
                                  context,
                                ).dividerColor.withValues(alpha: 0.2),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${e['brand']} ${e['name']}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        initialValue: (e['quantity'])
                                            .toString(),
                                        decoration: const InputDecoration(
                                          labelText: 'Quantity',
                                        ),
                                        keyboardType:
                                            const TextInputType.numberWithOptions(
                                              decimal: false,
                                            ),
                                        onChanged: (val) {
                                          final q = int.tryParse(val) ?? 0;
                                          setLocalState(
                                            () => e['quantity'] = q < 0 ? 0 : q,
                                          );
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: TextFormField(
                                        initialValue: (e['price_per_unit'])
                                            .toString(),
                                        decoration: const InputDecoration(
                                          labelText: 'Price per Unit (₹)',
                                        ),
                                        keyboardType:
                                            const TextInputType.numberWithOptions(
                                              decimal: true,
                                            ),
                                        onChanged: (val) {
                                          final p = double.tryParse(val) ?? 0.0;
                                          setLocalState(
                                            () => e['price_per_unit'] = p < 0
                                                ? 0.0
                                                : p,
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        }),

                        Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'Total: ₹${total.toStringAsFixed(2)}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving
                      ? null
                      : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) return;
                          setLocalState(() => isSaving = true);
                          final ok =
                              await SupabaseService.updatePurchaseWithItems(
                                purchaseId: purchase.id!,
                                dealerName: dealerCtrl.text.trim(),
                                billNumber: billCtrl.text.trim().isEmpty
                                    ? null
                                    : billCtrl.text.trim(),
                                createdAt: createdAt,
                                items: editItems
                                    .map(
                                      (e) => {
                                        if (e['id'] != null) 'id': e['id'],
                                        'product_id': e['product_id'],
                                        'quantity': e['quantity'],
                                        'price_per_unit': e['price_per_unit'],
                                      },
                                    )
                                    .toList(),
                              );
                          setLocalState(() => isSaving = false);
                          if (ok) {
                            if (mounted) Navigator.of(context).pop();
                            await _loadPurchases();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Purchase updated successfully',
                                  ),
                                ),
                              );
                            }
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Failed to update purchase'),
                              ),
                            );
                          }
                        },
                  child: isSaving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save Changes'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildExpandedDetails(models.Purchase purchase) {
    final items = _safePurchaseItems(purchase);
    final double storedTotal = purchase.totalAmount;
    final double calculatedTotal = items.fold<double>(
      0.0,
      (sum, it) => sum + (it.quantity * it.pricePerUnit),
    );
    final bool hasAmountMismatch = (calculatedTotal - storedTotal).abs() > 0.01;

    return LayoutBuilder(
      builder: (context, c) {
        final isWide = c.maxWidth >= 900;

        final left = Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
            ),
          ),
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
                      ).colorScheme.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.shopping_cart,
                      color: Theme.of(context).colorScheme.primary,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Purchase Information',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildDetailRow('Purchase ID', 'PUR-${purchase.id}'),
              _buildDetailRow(
                'Date & Time',
                DateFormat(
                  'd/M/yyyy, h:mm:ss a',
                ).format(purchase.createdAt ?? DateTime.now()),
              ),
              _buildDetailRow(
                'Dealer Name',
                purchase.supplierName ?? 'Unknown',
              ),
              _buildDetailRow('Bill Number', purchase.billNumber ?? 'N/A'),
              if (purchase.supplierPhone != null)
                _buildDetailRow('Phone Number', purchase.supplierPhone!),
              const Divider(height: 24),
              _buildDetailRow(
                'Stored Total',
                '₹${storedTotal.toStringAsFixed(2)}',
              ),
              _buildDetailRow(
                'Calculated Total',
                '₹${calculatedTotal.toStringAsFixed(2)}',
              ),
              _buildDetailRow('Items Count', '${items.length} items'),
              if (hasAmountMismatch)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.red.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.warning_amber,
                        color: Colors.red,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Amount mismatch detected! Difference: ₹${(calculatedTotal - storedTotal).abs().toStringAsFixed(2)}',
                          style: const TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );

        final right = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.secondary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.inventory_2,
                    color: Theme.of(context).colorScheme.secondary,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Items Purchased (${items.length})',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...items.asMap().entries.map((entry) {
              final idx = entry.key;
              final item = entry.value;
              final lineTotal = item.quantity * item.pricePerUnit;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(
                      context,
                    ).dividerColor.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Colors.purple, Colors.deepPurpleAccent],
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${idx + 1}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (item.product != null)
                            Text(
                              '${item.product!.brand ?? ''} ${item.product!.name}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                              overflow: TextOverflow.ellipsis,
                            )
                          else
                            Row(
                              children: const [
                                Icon(
                                  Icons.error_outline,
                                  color: Colors.red,
                                  size: 16,
                                ),
                                SizedBox(width: 6),
                                Text(
                                  'Product reference missing',
                                  style: TextStyle(color: Colors.red),
                                ),
                              ],
                            ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Text(
                                'Qty: ',
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).textTheme.bodySmall?.color,
                                ),
                              ),
                              Text(
                                '${item.quantity}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: Colors.orange,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Rate: ',
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).textTheme.bodySmall?.color,
                                ),
                              ),
                              Text(
                                '₹${item.pricePerUnit.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: Colors.green,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '₹${lineTotal.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        );

        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: left),
              const SizedBox(width: 16),
              Expanded(child: right),
            ],
          );
        } else {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [left, const SizedBox(height: 12), right],
          );
        }
      },
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
