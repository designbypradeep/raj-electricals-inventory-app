import 'package:flutter/material.dart';
import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shimmer/shimmer.dart';
import '../widgets/page_header.dart';
import '../services/supabase_service.dart';
import '../services/connectivity_service.dart';
import '../theme/ui_tokens.dart';

class ReplacementsHistoryPage extends StatefulWidget {
  const ReplacementsHistoryPage({super.key});

  @override
  State<ReplacementsHistoryPage> createState() =>
      _ReplacementsHistoryPageState();
}

class _ReplacementsHistoryPageState extends State<ReplacementsHistoryPage> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _replacements = [];
  bool _offline = false;
  StreamSubscription<List<ConnectivityResult>>? _connSub;

  // Filters
  String _searchQuery = '';
  String _statusFilter = 'all'; // all, completed, pending, cancelled
  String _dateFilter = 'all'; // all, today, week, month

  // Pagination
  int _currentPage = 1;
  int _itemsPerPage = 25;
  final ScrollController _scrollController = ScrollController();

  List<Map<String, dynamic>> get _paginatedReplacements {
    final list = _filteredReplacements;
    final startIndex = (_currentPage - 1) * _itemsPerPage;
    if (startIndex >= list.length) {
      if (list.isEmpty) return [];
      return list.take(_itemsPerPage).toList();
    }
    final endIndex = (startIndex + _itemsPerPage < list.length)
        ? startIndex + _itemsPerPage
        : list.length;
    return list.sublist(startIndex, endIndex);
  }

  int get _totalPages => _filteredReplacements.isEmpty
      ? 1
      : (_filteredReplacements.length / _itemsPerPage).ceil();

  void _changePage(int newPage) {
    setState(() {
      _currentPage = newPage;
    });
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _loadReplacements();
    // Connectivity monitoring
    _connSub = Connectivity().onConnectivityChanged.listen((results) {
      final offline = results.contains(ConnectivityResult.none);
      if (mounted) setState(() => _offline = offline);
    });
    Connectivity().checkConnectivity().then((results) {
      final offline = results.contains(ConnectivityResult.none);
      if (mounted) setState(() => _offline = offline);
    });
  }

  @override
  void dispose() {
    _connSub?.cancel();
    super.dispose();
  }

  Future<void> _loadReplacements() async {
    setState(() => _isLoading = true);
    try {
      final rows = await SupabaseService.getReplacements();

      final mapped = rows.map<Map<String, dynamic>>((row) {
        final createdAt = row['created_at'] as String?;
        final date = createdAt != null ? DateTime.tryParse(createdAt) : null;

        // Use separate relations if present
        final List rawOut = (row['replacement_items_out'] as List?) ?? const [];
        final List rawIn = (row['replacement_items_in'] as List?) ?? const [];

        // Normalize items into expected shape
        final List<Map<String, dynamic>> itemsOut = rawOut
            .map<Map<String, dynamic>>((it) {
              final prod =
                  (it['products'] as Map<String, dynamic>?) ?? const {};
              return {
                'products': prod,
                'item_condition': it['item_condition'] ?? it['condition'],
                'quantity_returned':
                    it['quantity_returned'] ?? it['quantity'] ?? it['qty'] ?? 0,
                'original_price_per_unit':
                    (it['original_price_per_unit'] as num?)?.toDouble() ??
                    (it['price_per_unit'] as num?)?.toDouble() ??
                    (it['price'] as num?)?.toDouble() ??
                    0.0,
              };
            })
            .toList();

        final List<Map<String, dynamic>> itemsIn = rawIn
            .map<Map<String, dynamic>>((it) {
              final prod =
                  (it['products'] as Map<String, dynamic>?) ?? const {};
              return {
                'products': prod,
                'quantity_given':
                    it['quantity_given'] ?? it['quantity'] ?? it['qty'] ?? 0,
                'price_per_unit':
                    (it['price_per_unit'] as num?)?.toDouble() ??
                    (it['price'] as num?)?.toDouble() ??
                    0.0,
              };
            })
            .toList();

        // Compute price difference: IN - OUT
        double outTotal = 0;
        for (final o in itemsOut) {
          outTotal +=
              (o['quantity_returned'] as num).toDouble() *
              (o['original_price_per_unit'] as num).toDouble();
        }
        double inTotal = 0;
        for (final i in itemsIn) {
          inTotal +=
              (i['quantity_given'] as num).toDouble() *
              (i['price_per_unit'] as num).toDouble();
        }
        final priceDiff =
            (row['amount_difference'] as num?)?.toDouble() ??
            (inTotal - outTotal);

        // Joined sale if available
        Map<String, dynamic>? sale;
        final s = row['sales'];
        if (s is Map<String, dynamic>) {
          sale = s;
        } else if (s is List &&
            s.isNotEmpty &&
            s.first is Map<String, dynamic>) {
          sale = Map<String, dynamic>.from(s.first as Map);
        }

        return {
          'id': row['id'],
          'replacement_number': row['replacement_number'] ?? 'N/A',
          'customer_name':
              row['customer_name'] ??
              sale?['customer_name'] ??
              'Walk-in Customer',
          'original_sale_id':
              row['original_sale_id'] ?? row['sale_id'] ?? sale?['id'],
          'receipt_number': sale?['id'],
          'status': (row['status'] ?? 'pending').toString().toLowerCase(),
          'notes': row['notes'] ?? '',
          'created_at': (date ?? DateTime.now()).toIso8601String(),
          'replacement_items_out': itemsOut,
          'replacement_items_in': itemsIn,
          'price_difference': priceDiff,
        };
      }).toList();

      setState(() {
        _replacements = mapped;
        _isLoading = false;
        _offline = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _offline = true;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load replacements: $e')),
        );
      }
    }
  }

  List<Map<String, dynamic>> get _filteredReplacements {
    final now = DateTime.now();
    return _replacements.where((r) {
      final search = _searchQuery.trim().toLowerCase();
      final numStr = (r['replacement_number'] ?? '').toString().toLowerCase();
      final cust = (r['customer_name'] ?? '').toString().toLowerCase();
      final notes = (r['notes'] ?? '').toString().toLowerCase();
      final receipt = (r['receipt_number'] ?? '').toString().toLowerCase();

      final matchesSearch =
          search.isEmpty ||
          numStr.contains(search) ||
          cust.contains(search) ||
          notes.contains(search) ||
          receipt.contains(search);

      final s = (r['status'] ?? 'pending').toString().toLowerCase();
      final matchesStatus =
          _statusFilter == 'all' || _mapStatus(s) == _statusFilter;

      final created =
          DateTime.tryParse((r['created_at'] ?? '') as String) ?? now;
      final daysDiff = now.difference(created).inDays;
      bool matchesDate = true;
      switch (_dateFilter) {
        case 'today':
          matchesDate =
              daysDiff == 0 &&
              created.day == now.day &&
              created.month == now.month &&
              created.year == now.year;
          break;
        case 'week':
          matchesDate = daysDiff <= 7;
          break;
        case 'month':
          matchesDate = daysDiff <= 30;
          break;
        default:
          matchesDate = true;
      }

      return matchesSearch && matchesStatus && matchesDate;
    }).toList();
  }

  String _mapStatus(String raw) {
    if (raw.contains('complete')) return 'completed';
    if (raw.contains('decline') || raw.contains('cancel')) return 'cancelled';
    return 'pending';
  }

  String _formatDate(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(dt.day)}-${two(dt.month)}-${dt.year} ${two(dt.hour)}:${two(dt.minute)}';
  }

  Color _statusColor(String status) {
    switch (_mapStatus(status)) {
      case 'completed':
        return Colors.green;
      case 'pending':
        return Colors.amber;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Color _priceDiffColor(double v) {
    if (v > 0) return Colors.green;
    if (v < 0) return Colors.red;
    return Theme.of(
          context,
        ).textTheme.bodyMedium?.color?.withValues(alpha: 0.6) ??
        Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    final list = _filteredReplacements;
    final netPriceDiff = list.fold<double>(
      0,
      (s, r) => s + ((r['price_difference'] as num?)?.toDouble() ?? 0),
    );

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        top: false,
        bottom: true,
        child: SingleChildScrollView(
          controller: _scrollController,
          child: Column(
            children: [
              PageHeader(
                title: 'Replacements History',
                description:
                    'View and manage product replacements and exchanges',
                icon: '🔄',
                showBackButton: true,
                backLabel: 'Back to Sales History',
                wrapInSafeArea: true,
                breadcrumbs: [
                  PageHeaderBreadcrumb(label: 'Dashboard', icon: '🏠', href: '/'),
                  if (MediaQuery.of(context).size.width >= 450)
                    PageHeaderBreadcrumb(label: 'Sales History', icon: '📊', href: '/sales-history'),
                  if (MediaQuery.of(context).size.width >= 600)
                    PageHeaderBreadcrumb(
                      label: 'Replacements History',
                      icon: '🔄',
                      current: true,
                    ),
                ],
                stats: [
                  PageHeaderStat(
                    label: 'Total Replacements',
                    value: '${_replacements.length}',
                    description: '${list.length} shown after filters',
                  ),
                  PageHeaderStat(
                    label: 'Net Price Difference',
                    value: '₹${netPriceDiff.toStringAsFixed(0)}',
                    description: 'Total price adjustments processed',
                  ),
                ],
                actions: [
                  PageHeaderAction(
                    label: 'Process Replacement',
                    shortLabel: 'New Replacement',
                    icon: Icons.add,
                    color: Theme.of(context).colorScheme.primary,
                    onPressed: () =>
                        Navigator.of(context).pushNamed('/replacements'),
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
                        if (_offline) ...[
                          _buildOfflineBanner(),
                          const SizedBox(height: 12),
                        ],
                        _buildFilters(),
                        const SizedBox(height: 16),
                        if (_isLoading)
                          _buildLoading()
                        else if (list.isEmpty)
                          _buildEmptyState()
                        else ...[
                          _buildReplacementsList(_paginatedReplacements),
                          if (list.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            _buildPaginationControls(),
                          ],
                        ],
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

  Widget _buildFilters() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final isWide = c.maxWidth >= 768;
          return Flex(
            direction: isWide ? Axis.horizontal : Axis.vertical,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Only use Expanded in horizontal layout, never in vertical.
              isWide
                  ? Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Search Replacements',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            decoration: InputDecoration(
                              hintText:
                                  'Search by replacement number, customer, or reason...',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              isDense: true,
                            ),
                            onChanged: (v) => setState(() => _searchQuery = v),
                          ),
                        ],
                      ),
                    )
                  : SizedBox(
                      width: double.infinity,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Search Replacements',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            decoration: InputDecoration(
                              hintText:
                                  'Search by replacement number, customer, or reason...',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              isDense: true,
                            ),
                            onChanged: (v) => setState(() => _searchQuery = v),
                          ),
                        ],
                      ),
                    ),
              SizedBox(width: isWide ? 12 : 0, height: isWide ? 0 : 12),
              SizedBox(
                width: isWide ? 220 : double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Status',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      initialValue: _statusFilter,
                      items: const [
                        DropdownMenuItem(
                          value: 'all',
                          child: Text('All Statuses'),
                        ),
                        DropdownMenuItem(
                          value: 'completed',
                          child: Text('Completed'),
                        ),
                        DropdownMenuItem(
                          value: 'pending',
                          child: Text('Pending'),
                        ),
                        DropdownMenuItem(
                          value: 'cancelled',
                          child: Text('Cancelled'),
                        ),
                      ],
                      onChanged: (v) =>
                          setState(() => _statusFilter = v ?? 'all'),
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        isDense: true,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: isWide ? 12 : 0, height: isWide ? 0 : 12),
              SizedBox(
                width: isWide ? 220 : double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Date Range',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      initialValue: _dateFilter,
                      items: const [
                        DropdownMenuItem(value: 'all', child: Text('All Time')),
                        DropdownMenuItem(value: 'today', child: Text('Today')),
                        DropdownMenuItem(
                          value: 'week',
                          child: Text('Last 7 Days'),
                        ),
                        DropdownMenuItem(
                          value: 'month',
                          child: Text('Last 30 Days'),
                        ),
                      ],
                      onChanged: (v) =>
                          setState(() => _dateFilter = v ?? 'all'),
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        isDense: true,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildLoading() {
    final cs = Theme.of(context).colorScheme;
    final base = cs.surfaceContainerHighest.withValues(alpha: 0.3);
    final highlight = cs.surfaceTint.withValues(alpha: 0.2);
    return Column(
      children: List.generate(3, (i) => i).map((_) {
        return Shimmer.fromColors(
          baseColor: base,
          highlightColor: highlight,
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
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
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: base,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Container(height: 16, color: base)),
                  ],
                ),
                const SizedBox(height: 12),
                Container(height: 12, color: base),
                const SizedBox(height: 8),
                Container(height: 12, width: 200, color: base),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(48),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        children: [
          const Text('🔄', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 12),
          Text(
            _searchQuery.isNotEmpty ||
                    _statusFilter != 'all' ||
                    _dateFilter != 'all'
                ? 'No replacements match your current filters. Try adjusting your search criteria.'
                : 'No replacements have been processed yet. Replacements will appear here once customers exchange products.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => Navigator.of(context).pushNamed('/replacements'),
            icon: const Icon(Icons.add),
            label: const Text('Process New Replacement'),
          ),
        ],
      ),
    );
  }

  Widget _buildPaginationControls() {
    final totalItems = _filteredReplacements.length;
    final startIndex = (_currentPage - 1) * _itemsPerPage;
    final startItem = totalItems == 0 ? 0 : startIndex + 1;
    final endItem = (_currentPage * _itemsPerPage > totalItems)
        ? totalItems
        : _currentPage * _itemsPerPage;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Showing $startItem-$endItem of $totalItems',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).textTheme.bodySmall?.color,
                ),
              ),
              Row(
                children: [
                  Text(
                    'Per page:',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).textTheme.bodySmall?.color,
                    ),
                  ),
                  const SizedBox(width: 8),
                  DropdownButton<int>(
                    value: _itemsPerPage,
                    underline: Container(),
                    items: [10, 25, 50, 100].map((int value) {
                      return DropdownMenuItem<int>(
                        value: value,
                        child:
                            Text('$value', style: const TextStyle(fontSize: 13)),
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
            ],
          ),
          if (_totalPages > 1) ...[
            const Divider(height: 20),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    onPressed: _currentPage > 1 ? () => _changePage(1) : null,
                    icon: const Icon(Icons.first_page, size: 20),
                    tooltip: 'First page',
                  ),
                  IconButton(
                    onPressed:
                        _currentPage > 1 ? () => _changePage(_currentPage - 1) : null,
                    icon: const Icon(Icons.chevron_left, size: 20),
                    tooltip: 'Previous page',
                  ),
                  ...List.generate(_totalPages, (index) {
                    final pageNum = index + 1;
                    final isCurrentPage = pageNum == _currentPage;
                    final showPage = pageNum == 1 ||
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
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: InkWell(
                        onTap: isCurrentPage
                            ? null
                            : () => _changePage(pageNum),
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: isCurrentPage
                                ? Theme.of(context).colorScheme.primary
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isCurrentPage
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context)
                                      .dividerColor
                                      .withValues(alpha: 0.2),
                            ),
                          ),
                          child: Center(
                            child: Text(
                              '$pageNum',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isCurrentPage
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: isCurrentPage
                                    ? Theme.of(context).colorScheme.onPrimary
                                    : Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.color,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                  IconButton(
                    onPressed: _currentPage < _totalPages
                        ? () => _changePage(_currentPage + 1)
                        : null,
                    icon: const Icon(Icons.chevron_right, size: 20),
                    tooltip: 'Next page',
                  ),
                  IconButton(
                    onPressed: _currentPage < _totalPages
                        ? () => _changePage(_totalPages)
                        : null,
                    icon: const Icon(Icons.last_page, size: 20),
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

  Widget _buildReplacementsList(List<Map<String, dynamic>> list) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final r = list[index];
        final created =
            DateTime.tryParse((r['created_at'] ?? '') as String) ??
            DateTime.now();
        final priceDifference =
            (r['price_difference'] as num?)?.toDouble() ?? 0;
        final itemsOut = (r['replacement_items_out'] as List?) ?? const [];
        final itemsIn = (r['replacement_items_in'] as List?) ?? const [];
        final status = _mapStatus((r['status'] ?? 'pending').toString());

        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
            ),
            boxShadow: [
              BoxShadow(
                color: Theme.of(context).shadowColor.withValues(alpha: 0.03),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _statusColor(r['status']).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _statusColor(
                            r['status'],
                          ).withValues(alpha: 0.2),
                        ),
                      ),
                      child: Icon(Icons.sync, color: _statusColor(r['status'])),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Replacement #${r['replacement_number']}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 12,
                            runSpacing: 4,
                            children: [
                              Text(
                                'Customer: ${r['customer_name']}',
                                style: _mutedStyle(),
                              ),
                              Text(
                                'Original Sale: #${r['receipt_number'] ?? r['original_sale_id'] ?? 'N/A'}',
                                style: _mutedStyle(),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _statusColor(
                              r['status'],
                            ).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            _mapStatus(r['status']).toUpperCase(),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: _statusColor(r['status']),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${priceDifference >= 0 ? '+' : ''}₹${priceDifference.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _priceDiffColor(priceDifference),
                          ),
                        ),
                        Text(
                          _formatDate(created),
                          style: _mutedStyle(fontSize: 11),
                        ),
                      ],
                    ),
                    const SizedBox(width: 4),
                    PopupMenuButton<String>(
                      onSelected: (v) async {
                        final id = r['id'] as int;
                        switch (v) {
                          case 'complete':
                            await _updateStatus(id, 'completed');
                            break;
                          case 'pending':
                            await _updateStatus(id, 'pending');
                            break;
                          case 'cancel':
                            await _updateStatus(id, 'cancelled');
                            break;
                          case 'delete':
                            await _confirmAndDelete(id);
                            break;
                        }
                      },
                      itemBuilder: (c) => [
                        if (status == 'pending')
                          const PopupMenuItem(
                            value: 'complete',
                            child: Text('Mark as Completed'),
                          ),
                        if (status != 'pending')
                          const PopupMenuItem(
                            value: 'pending',
                            child: Text('Mark as Pending'),
                          ),
                        const PopupMenuItem(
                          value: 'cancel',
                          child: Text('Cancel Replacement'),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text('Delete'),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 12),
                // Details grid
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _pill(
                      'Replacement Reason',
                      (r['notes'] as String).isNotEmpty
                          ? r['notes']
                          : 'No reason specified',
                    ),
                    _pill(
                      'Exchange Type',
                      priceDifference > 0
                          ? 'Customer Pays More'
                          : priceDifference < 0
                          ? 'Customer Gets Refund'
                          : 'Even Exchange',
                    ),
                  ],
                ),

                const SizedBox(height: 12),
                // Replacement Items sections
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    if (itemsOut.isNotEmpty)
                      _itemsPanel(
                        title: 'Items Returned',
                        color: Colors.red,
                        bg: _tintBg(Colors.red),
                        items: itemsOut,
                        qtyKey: 'quantity_returned',
                        priceKey: 'original_price_per_unit',
                        sign: '-',
                      ),
                    if (itemsIn.isNotEmpty)
                      _itemsPanel(
                        title: 'Replacement Items',
                        color: Colors.green,
                        bg: _tintBg(Colors.green),
                        items: itemsIn,
                        qtyKey: 'quantity_given',
                        priceKey: 'price_per_unit',
                        sign: '+',
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _itemsPanel({
    required String title,
    required Color color,
    required Color bg,
    required List items,
    required String qtyKey,
    required String priceKey,
    required String sign,
  }) {
    final screenWidth = MediaQuery.of(context).size.width;
    final double panelWidth = screenWidth < 640 ? (screenWidth - 48) : 600;
    return SizedBox(
      width: panelWidth.clamp(0, 800),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 800),
        decoration: BoxDecoration(
          border: Border.all(color: color.withValues(alpha: 0.3)),
          color: bg,
          borderRadius: BorderRadius.circular(UITokens.radius),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(fontWeight: FontWeight.w600, color: color),
            ),
            const SizedBox(height: 8),
            ...items.map((it) {
              final product =
                  (it['products'] as Map<String, dynamic>?) ?? const {};
              final name = product['name'] ?? it['name'] ?? 'Unknown Product';
              final qty = (it[qtyKey] as num?)?.toDouble() ?? 0;
              final price = (it[priceKey] as num?)?.toDouble() ?? 0.0;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Text('📦'),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          if (it['item_condition'] != null)
                            Text(
                              'Condition: ${it['item_condition']}',
                              style: _mutedStyle(fontSize: 11),
                            ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '$qty × ₹${price.toStringAsFixed(2)}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          '$sign₹${(qty * price).toStringAsFixed(2)}',
                          style: TextStyle(fontSize: 12, color: color),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  TextStyle _mutedStyle({double fontSize = 12}) {
    return TextStyle(
      fontSize: fontSize,
      color: Theme.of(
        context,
      ).textTheme.bodyMedium?.color?.withValues(alpha: 0.6),
    );
  }

  Widget _pill(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Color _tintBg(Color base) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return base.withValues(alpha: isDark ? 0.12 : 0.08);
  }

  Widget _buildOfflineBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: const [
          Icon(Icons.wifi_off, color: Colors.orange),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'You are offline. Showing cached UI. Some actions may not work.',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _updateStatus(int id, String status) async {
    if (!ConnectivityService().isOnline.value) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You are offline. Cannot update status.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final ok = await SupabaseService.updateReplacementStatus(
      replacementId: id,
      status: status,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Replacement #$id marked as ${status.toUpperCase()}.'
              : 'Failed to update status.',
        ),
      ),
    );
    if (ok) _loadReplacements();
  }

  Future<void> _confirmAndDelete(int id) async {
    if (!ConnectivityService().isOnline.value) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You are offline. Cannot delete replacement.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete Replacement'),
        content: Text(
          'Are you sure you want to delete replacement #$id? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    final ok = await SupabaseService.deleteReplacement(id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok ? 'Replacement #$id deleted.' : 'Failed to delete replacement.',
        ),
      ),
    );
    if (ok) _loadReplacements();
  }
}
