import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../widgets/page_header.dart';
import '../widgets/search_bar_widget.dart';
import '../services/supabase_service.dart';
import '../services/receipt_service.dart';
import '../services/connectivity_service.dart';
import '../models/sales_purchase_models.dart' as models;
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

class SalesHistoryPage extends StatefulWidget {
  const SalesHistoryPage({super.key});

  @override
  State<SalesHistoryPage> createState() => _SalesHistoryPageState();
}

class _SalesHistoryPageState extends State<SalesHistoryPage> {
  // Core state
  bool _isLoading = true;
  String _errorMessage = '';
  List<models.Sale> _sales = [];
  List<models.Sale> _filteredSales = [];

  // Search and filtering state
  String _searchTerm = '';
  final String _sortBy = 'Date';
  String _customerFilter = '';
  String _minAmount = '';
  String _maxAmount = '';
  String _statusFilter = 'all'; // all, problematic, normal
  DateTimeRange? _dateRange;

  // UI state
  bool _showFilters = false;
  bool _showBulkActions = false;
  Set<int> _selectedSales = <int>{};
  int? _expandedSaleId;

  // Pagination and performance optimizations
  final ScrollController _scrollController = ScrollController();
  Timer? _searchDebounce;
  int _currentPage = 1;
  int _itemsPerPage = 25;

  // Precomputed statistics
  int _uniqueCustomersCount = 0;
  double _totalRevenue = 0.0;
  int _problematicCount = 0;

  List<models.Sale> get _paginatedSales {
    final startIndex = (_currentPage - 1) * _itemsPerPage;
    if (startIndex >= _filteredSales.length) {
      if (_filteredSales.isEmpty) return [];
      return _filteredSales.take(_itemsPerPage).toList();
    }
    final endIndex = startIndex + _itemsPerPage;
    return _filteredSales.sublist(
      startIndex,
      endIndex > _filteredSales.length ? _filteredSales.length : endIndex,
    );
  }

  int get _totalPages => _filteredSales.isEmpty
      ? 1
      : (_filteredSales.length / _itemsPerPage).ceil();

  void _changePage(int newPage) {
    setState(() {
      _currentPage = newPage;
    });
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        380.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) {
        _searchTerm = value;
        _filterAndSortSales();
      }
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _checkAuthAndLoadData();
  }

  List<models.SaleItem> _safeSalesItems(models.Sale s) {
    try {
      final list = s.salesItems;
      return list;
    } catch (_) {
      return const <models.SaleItem>[];
    }
  }

  Future<void> _checkAuthAndLoadData() async {
    final user = SupabaseService.supabase.auth.currentUser;
    if (user == null) {
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/login');
      }
      return;
    }
    await _loadSales();
  }

  Future<void> _loadSales({bool forceRefresh = false}) async {
    try {
      final cached = SupabaseService.cachedSales;
      if (cached != null && cached.isNotEmpty && !forceRefresh) {
        // Fast instant render from memory cache
        _sales = cached;
        _filterAndSortSales();
        _isLoading = false;
      } else if (_sales.isEmpty) {
        setState(() {
          _isLoading = true;
          _errorMessage = '';
        });
      }

      final sales = await SupabaseService.getSales(forceRefresh: forceRefresh);

      if (mounted) {
        setState(() {
          _sales = sales;
          _filterAndSortSales();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load sales: ${e.toString()}';
          _isLoading = false;
        });
      }
    }
  }

  void _filterAndSortSales() {
    List<models.Sale> filtered = _sales;

    // Apply search filter
    if (_searchTerm.isNotEmpty) {
      final searchLower = _searchTerm.toLowerCase().trim();
      filtered = filtered.where((sale) {
        final idStr = sale.id?.toString() ?? '';
        final invStr = 'inv-$idStr'.toLowerCase();
        return (sale.customerName?.toLowerCase().contains(searchLower) ??
                false) ||
            (sale.customerPhone?.toLowerCase().contains(searchLower) ??
                false) ||
            sale.paymentMethod.toLowerCase().contains(searchLower) ||
            idStr.contains(searchLower) ||
            invStr.contains(searchLower);
      }).toList();
    }

    // Apply customer filter
    if (_customerFilter.isNotEmpty) {
      final customerLower = _customerFilter.toLowerCase();
      filtered = filtered.where((sale) {
        return sale.customerName?.toLowerCase().contains(customerLower) ??
            false;
      }).toList();
    }

    // Apply amount range filters
    if (_minAmount.isNotEmpty) {
      final minAmt = double.tryParse(_minAmount) ?? 0;
      filtered = filtered.where((sale) => sale.totalAmount >= minAmt).toList();
    }
    if (_maxAmount.isNotEmpty) {
      final maxAmt = double.tryParse(_maxAmount) ?? double.infinity;
      filtered = filtered.where((sale) => sale.totalAmount <= maxAmt).toList();
    }

    // Apply date range filter
    if (_dateRange != null) {
      filtered = filtered.where((sale) {
        final saleDate = sale.saleDate ?? sale.createdAt;
        if (saleDate == null) return false;
        return saleDate.isAfter(
              _dateRange!.start.subtract(const Duration(days: 1)),
            ) &&
            saleDate.isBefore(_dateRange!.end.add(const Duration(days: 1)));
      }).toList();
    }

    // Apply status filter
    if (_statusFilter == 'problematic') {
      filtered = filtered.where((sale) => _isProblematicSale(sale)).toList();
    } else if (_statusFilter == 'normal') {
      filtered = filtered.where((sale) => !_isProblematicSale(sale)).toList();
    }

    // Apply sorting
    switch (_sortBy) {
      case 'Date':
        filtered.sort((a, b) {
          final dateA = a.saleDate ?? a.createdAt ?? DateTime.now();
          final dateB = b.saleDate ?? b.createdAt ?? DateTime.now();
          return dateB.compareTo(dateA);
        });
        break;
      case 'Amount':
        filtered.sort((a, b) => b.totalAmount.compareTo(a.totalAmount));
        break;
      case 'Customer':
        filtered.sort(
          (a, b) => (a.customerName ?? '').compareTo(b.customerName ?? ''),
        );
        break;
    }

    // Precompute statistics for O(1) rendering in build()
    final uniqueCustomers = filtered
        .map((sale) => sale.customerName ?? 'Unknown')
        .toSet()
        .length;
    final totalRev = filtered.fold<double>(
      0.0,
      (sum, sale) => sum + sale.totalAmount,
    );
    final probCount = filtered
        .where((sale) => _isProblematicSale(sale))
        .length;

    setState(() {
      _filteredSales = filtered;
      _uniqueCustomersCount = uniqueCustomers;
      _totalRevenue = totalRev;
      _problematicCount = probCount;
      _currentPage = 1;
    });
  }

  bool _isProblematicSale(models.Sale sale) {
    // Check for missing customer info
    if (sale.customerName == null || sale.customerName!.trim().isEmpty) {
      return true;
    }

    // Check for zero or negative amounts
    if (sale.totalAmount <= 0) {
      return true;
    }

    // Check for missing payment method
    if (sale.paymentMethod.trim().isEmpty) {
      return true;
    }

    return false;
  }

  void _toggleSaleSelection(int saleId) {
    setState(() {
      if (_selectedSales.contains(saleId)) {
        _selectedSales.remove(saleId);
      } else {
        _selectedSales.add(saleId);
      }
    });
  }

  void _toggleSelectAll() {
    setState(() {
      if (_selectedSales.length == _filteredSales.length) {
        _selectedSales.clear();
      } else {
        _selectedSales = _filteredSales.map((sale) => sale.id!).toSet();
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedSales.clear();
    });
  }

  Future<void> _handleBulkDelete() async {
    if (!ConnectivityService().isOnline.value) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You are offline. Cannot delete sales.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_selectedSales.isEmpty) return;

    final selectedSalesData = _filteredSales
        .where((sale) => _selectedSales.contains(sale.id))
        .toList();
    final totalAmount = selectedSalesData.fold(
      0.0,
      (sum, sale) => sum + sale.totalAmount,
    );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Selected Sales'),
        content: Text(
          'Are you sure you want to delete ${_selectedSales.length} selected sale(s)?\n\n'
          'Total value: ₹${totalAmount.toStringAsFixed(2)}\n\n'
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final ids = _selectedSales.toList();
      final result = await SupabaseService.bulkDeleteSales(ids);
      await _loadSales();
      _clearSelection();
      final success = result['success'] ?? 0;
      final failed = result['failed'] ?? 0;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            failed == 0
                ? 'Successfully deleted $success sale${success == 1 ? '' : 's'} and adjusted inventory.'
                : (success > 0
                      ? 'Deleted $success sale${success == 1 ? '' : 's'}. $failed failed.'
                      : 'Failed to delete all selected sales ($failed failed).'),
          ),
          backgroundColor: failed == 0
              ? Colors.green
              : (success > 0
                    ? Colors.orange
                    : Theme.of(context).colorScheme.error),
        ),
      );
    }
  }

  Future<void> _shareOnWhatsApp(models.Sale sale) async {
    final profile = await SupabaseService.getCurrentBusinessProfile();
    final String businessName = profile?.businessName ?? 'Inventoza';

    if (sale.customerPhone == null || sale.customerPhone!.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No phone number available for this customer.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    final dateStr = DateFormat(
      'dd/MM/yyyy',
    ).format(sale.createdAt ?? DateTime.now());

    // Build the receipt text
    final StringBuffer sb = StringBuffer();
    sb.writeln('*Receipt from $businessName*');
    sb.writeln('--------------------------------');
    sb.writeln('Inv: ${sale.id} | Date: $dateStr');
    sb.writeln('--------------------------------');

    final items = _safeSalesItems(sale);
    for (final item in items) {
      final name = item.product?.name ?? 'Unknown Product';
      final qty = item.quantity;
      final price = item.pricePerUnit;
      final total = qty * price;
      // Using toStringAsFixed(2) roughly matches logic, ignoring potential int/double precision nuances for display
      sb.writeln('$name x $qty = ₹${total.toStringAsFixed(2)}');
    }

    sb.writeln('--------------------------------');

    // Calculate totals locally
    final subTotal = items.fold<double>(
      0.0,
      (sum, item) => sum + (item.quantity * item.pricePerUnit),
    );
    final discount = sale.discountAmount ?? 0.0;
    final finalTotal = sale.totalAmount;

    sb.writeln('*Subtotal: ₹${subTotal.toStringAsFixed(2)}*');
    if (discount > 0) {
      sb.writeln('Discount: - ₹${discount.toStringAsFixed(2)}');
    }
    sb.writeln('*Final Total: ₹${finalTotal.toStringAsFixed(2)}*');
    sb.writeln('--------------------------------');
    sb.writeln('Thank you for your business!');

    final text = Uri.encodeComponent(sb.toString());
    String phone = sale.customerPhone!.replaceAll(RegExp(r'\D'), '');
    if (phone.length == 10) {
      phone = '91$phone'; // Prepend 91 if likely Indian mobile
    }

    final url = Uri.parse('https://wa.me/$phone?text=$text');

    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not launch WhatsApp.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error launching WhatsApp: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _generatePdf(models.Sale sale) async {
    try {
      final items = _safeSalesItems(sale)
          .map(
            (i) => ReceiptItem(
              name: i.product?.name ?? 'Unknown',
              quantity: i.quantity,
              pricePerUnit: i.pricePerUnit,
              itemCode: null,
            ),
          )
          .toList();

      // Calculate subtotal from items to ensure consistency
      final subTotal = items.fold<double>(
        0,
        (sum, i) => sum + (i.quantity * i.pricePerUnit),
      );

      final data = ReceiptData(
        saleId: sale.id.toString(),
        customerName: sale.customerName ?? 'Walk-in Customer',
        customerPhone: sale.customerPhone,
        transactionId: null,
        items: items,
        subTotal: subTotal,
        discount: sale.discountAmount ?? 0.0,
        finalTotal: sale.totalAmount,
        paymentMethod: sale.paymentMethod,
        saleDate: sale.createdAt ?? DateTime.now(),
        status: sale.status,
      );

      await ReceiptService.shareReceiptPdf(data);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to generate PDF: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildSkeletonLoading(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? Colors.grey[850]! : Colors.grey[300]!;
    final highlight = isDark ? Colors.grey[750]! : Colors.grey[100]!;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        top: true,
        bottom: true,
        child: SingleChildScrollView(
          child: Column(
            children: [
              PageHeader(
                title: 'Sales History',
                description: 'Track, manage, and analyze sales records',
                icon: '🛍️',
                showBackButton: true,
                backLabel: 'Back to Dashboard',
                wrapInSafeArea: false,
                breadcrumbs: [
                  PageHeaderBreadcrumb(label: 'Dashboard', icon: '🏠'),
                  if (MediaQuery.of(context).size.width >= 450)
                    PageHeaderBreadcrumb(
                      label: 'Sales History',
                      icon: '🛍️',
                      current: true,
                    ),
                ],
                stats: [
                  PageHeaderStat(
                    label: 'Total Sales',
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
                        const SizedBox(height: 20),
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
                        // Skeleton sales cards
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
                                borderRadius: BorderRadius.circular(16),
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
    if (_isLoading && _sales.isEmpty) {
      return _buildSkeletonLoading(context);
    }

    if (_errorMessage.isNotEmpty) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              const SizedBox(height: 16),
              Text(
                'Failed to load sales history',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => _checkAuthAndLoadData(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                ),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final uniqueCustomers = _uniqueCustomersCount;
    final totalRevenue = _totalRevenue;
    final problematicCount = _problematicCount;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        top: true,
        bottom: true,
        child: RefreshIndicator(
          onRefresh: () => _loadSales(forceRefresh: true),
          child: SingleChildScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
            children: [
              PageHeader(
                title: 'Sales History',
                description: 'Track, manage, and analyze sales records',
                icon: '🛍️',
                showBackButton: true,
                backLabel: 'Back to Dashboard',
                wrapInSafeArea: false,
                breadcrumbs: [
                  PageHeaderBreadcrumb(label: 'Dashboard', icon: '🏠'),
                  if (MediaQuery.of(context).size.width >= 450)
                    PageHeaderBreadcrumb(
                      label: 'Sales History',
                      icon: '🛍️',
                      current: true,
                    ),
                ],
                stats: [
                  PageHeaderStat(
                    label: 'Total Sales',
                    value: '${_sales.length}',
                    description: 'All sales records',
                  ),
                  PageHeaderStat(
                    label: 'Status',
                    value: 'Live Data',
                    description: 'Real-time tracking',
                  ),
                ],
                actions: [
                  PageHeaderAction(
                    label: 'New Sale',
                    shortLabel: 'Add Sale',
                    icon: Icons.add,
                    color: Theme.of(context).colorScheme.primary,
                    onPressed: () {
                      Navigator.of(context).pushNamed('/sales');
                    },
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

                        const SizedBox(height: 24),

                        // Statistics Cards
                        _buildStatisticsCards(
                          uniqueCustomers,
                          totalRevenue,
                          problematicCount,
                        ),

                        const SizedBox(height: 24),

                        // Search Bar
                        SearchBarWidget(
                          placeholder:
                              'Search by customer, phone, invoice, or payment...',
                          entityName: 'sales',
                          onSearchChanged: _onSearchChanged,
                          resultCount: _searchTerm.isNotEmpty
                              ? _filteredSales.length
                              : null,
                          totalCount: _searchTerm.isNotEmpty
                              ? _sales.length
                              : null,
                        ),

                        const SizedBox(height: 24),

                        // Filters Panel
                        if (_showFilters) _buildFiltersPanel(),
                        if (_showFilters) const SizedBox(height: 24),

                        // Bulk Actions Panel
                        if (_showBulkActions && _selectedSales.isNotEmpty)
                          _buildBulkActionsPanel(),
                        if (_showBulkActions && _selectedSales.isNotEmpty)
                          const SizedBox(height: 24),

                        // Sales List
                        _buildSalesList(),
                      ],
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
              'Bulk Actions',
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

  Widget _buildStatisticsCards(
    int uniqueCustomers,
    double totalRevenue,
    int problematicCount,
  ) {
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
              'Total Sales',
              '${_sales.length}',
              Icons.receipt_long,
              Colors.blue,
            ),
            _buildStatCard(
              'Filtered',
              '${_filteredSales.length}',
              Icons.filter_list,
              Colors.green,
            ),
            _buildStatCard(
              'Unique Customers',
              '$uniqueCustomers',
              Icons.people,
              Colors.orange,
            ),
            _buildStatCard(
              'Total Revenue',
              NumberFormat.currency(
                symbol: '₹',
                decimalDigits: 0,
                locale: 'en_IN',
              ).format(totalRevenue),
              Icons.currency_rupee,
              problematicCount > 0 ? Colors.red : Colors.purple,
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
            softWrap: false,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: Theme.of(
                context,
              ).textTheme.bodySmall?.color?.withValues(alpha: 0.75),
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
                'Filter Sales',
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
              final cross = w >= 1000
                  ? 4
                  : w >= 700
                  ? 3
                  : w >= 480
                  ? 2
                  : 1;
              final aspect = w < 480 ? 2.1 : 3.0;
              return GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: cross,
                childAspectRatio: aspect,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                children: [
                  _buildFilterField(
                    'Customer Name',
                    _customerFilter,
                    (value) => setState(() => _customerFilter = value),
                  ),
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
              final isNarrow = c.maxWidth < 480;
              final clearBtn = ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _customerFilter = '';
                    _minAmount = '';
                    _maxAmount = '';
                    _statusFilter = 'all';
                    _dateRange = null;
                  });
                  _filterAndSortSales();
                },
                icon: const Icon(Icons.clear),
                label: const Text('Clear Filters'),
              );
              final summary = Text(
                'Showing ${_filteredSales.length} of ${_sales.length} sales',
              );
              if (isNarrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [clearBtn, const SizedBox(height: 8), summary],
                );
              } else {
                return Row(children: [clearBtn, const Spacer(), summary]);
              }
            },
          ),
        ],
      ),
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
            _filterAndSortSales();
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
            _filterAndSortSales();
          },
          decoration: InputDecoration(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
          ),
          items: const [
            DropdownMenuItem(value: 'all', child: Text('All Sales')),
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
      child: Row(
        children: [
          Icon(Icons.checklist, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            '${_selectedSales.length} selected',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const Spacer(),
          TextButton(onPressed: _clearSelection, child: const Text('Clear')),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: _handleBulkDelete,
            icon: const Icon(Icons.delete, size: 16),
            label: const Text('Delete Selected'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSalesList() {
    if (_filteredSales.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(48),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1),
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
            const Text('🛍️', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 16),
            Text(
              _searchTerm.isNotEmpty ||
                      _customerFilter.isNotEmpty ||
                      _statusFilter != 'all'
                  ? 'No sales match your filters'
                  : 'No sales recorded yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _searchTerm.isNotEmpty ||
                      _customerFilter.isNotEmpty ||
                      _statusFilter != 'all'
                  ? 'Try adjusting your filters or search terms.'
                  : 'Sales will appear here once recorded.',
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              textAlign: TextAlign.center,
            ),
            if (_searchTerm.isNotEmpty ||
                _customerFilter.isNotEmpty ||
                _statusFilter != 'all') ...[
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _searchTerm = '';
                    _customerFilter = '';
                    _minAmount = '';
                    _maxAmount = '';
                    _statusFilter = 'all';
                    _dateRange = null;
                    _filterAndSortSales();
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                ),
                child: const Text('Clear All Filters'),
              ),
            ],
          ],
        ),
      );
    }

    return Column(
      children: [
        // Bulk selection header
        if (_showBulkActions)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
              border: Border.all(
                color: Theme.of(
                  context,
                ).colorScheme.outline.withValues(alpha: 0.1),
              ),
            ),
            child: Row(
              children: [
                Checkbox(
                  value:
                      _selectedSales.length == _filteredSales.length &&
                      _filteredSales.isNotEmpty,
                  tristate: true,
                  onChanged: (value) => _toggleSelectAll(),
                ),
                const SizedBox(width: 8),
                Text(
                  _selectedSales.isEmpty
                      ? 'Select all sales'
                      : '${_selectedSales.length} of ${_filteredSales.length} selected',
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        // Sales cards (paginated for smooth 60fps performance)
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _paginatedSales.length,
          separatorBuilder: (_, __) => const SizedBox(height: 16),
          itemBuilder: (context, index) {
            final sale = _paginatedSales[index];
            return _buildSaleCard(sale, index);
          },
        ),
        if (_filteredSales.isNotEmpty) ...[
          const SizedBox(height: 20),
          _buildPaginationControls(),
        ],
      ],
    );
  }

  Widget _buildPaginationControls() {
    final startIndex = (_currentPage - 1) * _itemsPerPage;
    final startItem = _filteredSales.isEmpty ? 0 : startIndex + 1;
    final endItem = (_currentPage * _itemsPerPage > _filteredSales.length)
        ? _filteredSales.length
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
                'Showing $startItem-$endItem of ${_filteredSales.length} sales',
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
                            child: Center(
                              child: Text(
                                '$pageNum',
                                style: TextStyle(
                                  fontSize: 14,
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

  Widget _buildSaleCard(models.Sale sale, int index) {
    final isProblematic = _isProblematicSale(sale);
    final isExpanded = _expandedSaleId == sale.id;
    final isSelected = _selectedSales.contains(sale.id);
    final List<models.SaleItem> items = _safeSalesItems(sale);
    final double calculatedTotal = items.fold<double>(
      0.0,
      (sum, models.SaleItem it) => sum + (it.quantity * it.pricePerUnit),
    );
    final double storedTotal = sale.totalAmount;
    final bool hasAmountMismatch = (calculatedTotal - storedTotal).abs() > 0.01;

    return Stack(
      children: [
        // Card shell
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
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
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header row (Invoice + Date + Status) and summary columns are below
                    // Header + summary built just like before
                    // Reuse the block we already built
                    // Header row (Invoice + Date + Status)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_showBulkActions)
                          Checkbox(
                            value: isSelected,
                            onChanged: (value) =>
                                _toggleSaleSelection(sale.id!),
                          ),
                        if (_showBulkActions) const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color:
                                (isProblematic
                                        ? Theme.of(context).colorScheme.error
                                        : Theme.of(context).colorScheme.primary)
                                    .withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color:
                                  (isProblematic
                                          ? Theme.of(context).colorScheme.error
                                          : Theme.of(
                                              context,
                                            ).colorScheme.primary)
                                      .withValues(alpha: 0.2),
                            ),
                          ),
                          child: Icon(
                            Icons.receipt_long,
                            size: 20,
                            color: isProblematic
                                ? Theme.of(context).colorScheme.error
                                : Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'INV-${sale.id ?? 'N/A'}',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _formatDateTime(
                                  sale.saleDate ??
                                      sale.createdAt ??
                                      DateTime.now(),
                                ),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context).colorScheme.onSurface
                                      .withValues(alpha: 0.6),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: (isProblematic ? Colors.red : Colors.green)
                                .withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: (isProblematic ? Colors.red : Colors.green)
                                  .withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isProblematic
                                    ? Icons.warning_amber
                                    : Icons.check,
                                size: 14,
                                color: isProblematic
                                    ? Colors.red
                                    : Colors.green,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                isProblematic ? 'Issues Found' : 'Normal',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: isProblematic
                                      ? Colors.red
                                      : Colors.green,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Three columns: Customer | Amount | Actions
                    LayoutBuilder(
                      builder: (context, c) {
                        final isWide = c.maxWidth >= 900;

                        final col1 = Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'CUSTOMER DETAILS',
                              style: TextStyle(
                                fontSize: 11,
                                letterSpacing: 0.6,
                                fontWeight: FontWeight.w700,
                                color: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.color
                                    ?.withValues(alpha: 0.7),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Icon(
                                  Icons.person,
                                  size: 16,
                                  color: Colors.blue,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    sale.customerName?.isNotEmpty == true
                                        ? sale.customerName!
                                        : 'Walk-in',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(
                                  Icons.phone,
                                  size: 16,
                                  color: Colors.green,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  sale.customerPhone?.isNotEmpty == true
                                      ? sale.customerPhone!
                                      : 'N/A',
                                  style: TextStyle(
                                    color: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.color
                                        ?.withValues(alpha: 0.8),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        );

                        final col2 = Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'AMOUNT DETAILS',
                              style: TextStyle(
                                fontSize: 11,
                                letterSpacing: 0.6,
                                fontWeight: FontWeight.w700,
                                color: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.color
                                    ?.withValues(alpha: 0.7),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Total: ₹${sale.totalAmount.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.blue,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Items: ${items.length}',
                              style: TextStyle(
                                color: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.color
                                    ?.withValues(alpha: 0.8),
                              ),
                            ),
                          ],
                        );

                        final actionRow1 = Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  setState(() {
                                    _expandedSaleId = isExpanded
                                        ? null
                                        : sale.id;
                                  });
                                },
                                icon: Icon(
                                  isExpanded ? Icons.visibility_off : Icons.visibility,
                                  size: 14,
                                ),
                                label: Text(
                                  isExpanded ? 'Hide' : 'Details',
                                  style: const TextStyle(fontSize: 11),
                                ),
                                style: OutlinedButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 6,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              flex: 2,
                              child: ElevatedButton.icon(
                                onPressed: () => _generatePdf(sale),
                                icon: const Icon(Icons.picture_as_pdf, size: 14),
                                label: const Text('PDF', style: TextStyle(fontSize: 11)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue,
                                  foregroundColor: Colors.white,
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 6,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              flex: 2,
                              child: ElevatedButton.icon(
                                onPressed: () => _shareOnWhatsApp(sale),
                                icon: const Icon(Icons.share, size: 14),
                                label: const Text('Share', style: TextStyle(fontSize: 11)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 6,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );

                        final actionRow2 = Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () => _showEditDialog(sale),
                                icon: const Icon(Icons.edit, size: 12),
                                label: const Text('Edit', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orange,
                                  foregroundColor: Colors.white,
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
                                ),
                              ),
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.of(context).pushNamed(
                                    '/returns',
                                    arguments: {'sale_id': sale.id},
                                  );
                                },
                                icon: const Icon(
                                  Icons.keyboard_return_rounded,
                                  size: 12,
                                ),
                                label: const Text('Return', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.purple,
                                  foregroundColor: Colors.white,
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
                                ),
                              ),
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.of(context).pushNamed(
                                    '/replacements',
                                    arguments: {'sale_id': sale.id},
                                  );
                                },
                                icon: const Icon(Icons.swap_horiz, size: 12),
                                label: const Text('Replace', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.teal,
                                  foregroundColor: Colors.white,
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
                                ),
                              ),
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () =>
                                    _confirmAndDeleteSale(sale.id!),
                                icon: const Icon(Icons.delete, size: 12),
                                label: const Text('Delete', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Theme.of(
                                    context,
                                  ).colorScheme.error,
                                  foregroundColor: Theme.of(
                                    context,
                                  ).colorScheme.onError,
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
                                ),
                              ),
                            ),
                          ],
                        );

                        final actionsColumn = Column(
                          children: [
                            actionRow1,
                            const SizedBox(height: 6),
                            actionRow2,
                          ],
                        );

                        if (isWide) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: col1),
                              const SizedBox(width: 14),
                              Expanded(child: col2),
                              const SizedBox(width: 14),
                              Expanded(flex: 2, child: actionsColumn),
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
                                        '₹${sale.totalAmount.toStringAsFixed(2)}',
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.blue,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      InkWell(
                                        onTap: () => setState(
                                          () => _expandedSaleId =
                                              isExpanded ? null : sale.id,
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
                                            borderRadius:
                                                BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            isExpanded
                                                ? 'Hide items'
                                                : 'View items (${items.length})',
                                            style: const TextStyle(
                                              color: Colors.purple,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              actionsColumn,
                            ],
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),

              // Expanded details
              if (isExpanded) ...[
                Divider(
                  height: 1,
                  color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Sale Information',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              'Items Sold (${items.length})',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      LayoutBuilder(
                        builder: (context, c) {
                          final isWide = c.maxWidth >= 900;
                          final left = Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).cardColor.withValues(alpha: 0.8),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Theme.of(
                                  context,
                                ).dividerColor.withValues(alpha: 0.2),
                              ),
                            ),
                            child: Column(
                              children: [
                                _detailRow(
                                  'Invoice ID:',
                                  'INV-${sale.id ?? 'N/A'}',
                                ),
                                _detailRow(
                                  'Date & Time:',
                                  _formatDateTime(
                                    sale.createdAt ?? DateTime.now(),
                                  ),
                                ),
                                _detailRow(
                                  'Customer Name:',
                                  sale.customerName?.isNotEmpty == true
                                      ? sale.customerName!
                                      : 'Walk-in',
                                ),
                                _detailRow(
                                  'Phone Number:',
                                  sale.customerPhone?.isNotEmpty == true
                                      ? sale.customerPhone!
                                      : 'N/A',
                                ),
                                const Divider(height: 24),
                                _detailRow(
                                  'Stored Total:',
                                  '₹${storedTotal.toStringAsFixed(2)}',
                                  valueColor: Colors.green,
                                ),
                                _detailRow(
                                  'Calculated Total:',
                                  '₹${calculatedTotal.toStringAsFixed(2)}',
                                  valueColor: Colors.blue,
                                ),
                                if (hasAmountMismatch)
                                  Container(
                                    margin: const EdgeInsets.only(top: 8),
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Colors.red.withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: Colors.red.withValues(
                                          alpha: 0.2,
                                        ),
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
                                            "Amount mismatch detected! Difference: ₹${(calculatedTotal - storedTotal).abs().toStringAsFixed(2)}",
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
                            children: items.asMap().entries.map((entry) {
                              final idx = entry.key;
                              final item = entry.value;
                              final lineTotal =
                                  item.quantity * item.pricePerUnit;
                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Theme.of(
                                    context,
                                  ).cardColor.withValues(alpha: 0.8),
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
                                          colors: [
                                            Colors.blue,
                                            Colors.lightBlueAccent,
                                          ],
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
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          if (item.product != null)
                                            Text(
                                              '${item.product!.brand ?? ''} ${item.product!.name}',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.onSurface,
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
                                                  style: TextStyle(
                                                    color: Colors.red,
                                                  ),
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
                            }).toList(),
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
                              children: [
                                left,
                                const SizedBox(height: 12),
                                right,
                              ],
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        // Top status strip
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: Container(
            height: 3,
            decoration: BoxDecoration(
              color: isProblematic ? Colors.red : Colors.green,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _detailRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Theme.of(
                context,
              ).textTheme.bodySmall?.color?.withValues(alpha: 0.8),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: valueColor ?? Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime date) {
    // Example: 24/8/2025, 1:34:00 pm
    return DateFormat('d/M/yyyy, h:mm:ss a').format(date);
  }

  void _showEditDialog(models.Sale sale) {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController(text: sale.customerName ?? '');
    final phoneCtrl = TextEditingController(text: sale.customerPhone ?? '');
    DateTime createdAt = sale.createdAt ?? DateTime.now();
    final items = _safeSalesItems(sale);
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
            final double total = editItems.fold<double>(
              0.0,
              (sum, e) =>
                  sum +
                  ((e['quantity'] as num).toDouble() *
                      (e['price_per_unit'] as num).toDouble()),
            );
            return AlertDialog(
              title: Text('Edit Sale INV-${sale.id}'),
              content: Form(
                key: formKey,
                child: SizedBox(
                  width: 560,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextFormField(
                          controller: nameCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Customer Name *',
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Required'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: phoneCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Phone Number',
                          ),
                          keyboardType: TextInputType.phone,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Sale Date: ${DateFormat('d/M/yyyy, h:mm a').format(createdAt)}',
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
                          'Sale Items',
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
                          final ok = await SupabaseService.updateSaleWithItems(
                            saleId: sale.id!,
                            customerName: nameCtrl.text.trim(),
                            customerPhone: phoneCtrl.text.trim().isEmpty
                                ? null
                                : phoneCtrl.text.trim(),
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
                            await _loadSales();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Sale updated successfully'),
                                ),
                              );
                            }
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Failed to update sale'),
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

  Future<void> _confirmAndDeleteSale(int saleId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Sale'),
        content: Text(
          'Are you sure you want to delete INV-$saleId? This will adjust inventory accordingly.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final ok = await SupabaseService.deleteSaleAndRestock(saleId);
      await _loadSales();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? 'Sale INV-$saleId has been deleted and inventory adjusted.'
                : 'Failed to delete INV-$saleId',
          ),
          backgroundColor: ok
              ? Colors.green
              : Theme.of(context).colorScheme.error,
        ),
      );
    }
  }
}
