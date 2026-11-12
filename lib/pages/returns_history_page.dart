import 'package:flutter/material.dart';
import '../widgets/page_header.dart';
import '../services/supabase_service.dart';
import '../services/connectivity_service.dart';

class ReturnsHistoryPage extends StatefulWidget {
  const ReturnsHistoryPage({super.key});

  @override
  State<ReturnsHistoryPage> createState() => _ReturnsHistoryPageState();
}

class _ReturnsHistoryPageState extends State<ReturnsHistoryPage> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _returns = [];

  // Filters
  String _searchQuery = '';
  String _statusFilter = 'all'; // all, completed, pending, cancelled
  String _dateFilter = 'all'; // all, today, week, month

  @override
  void initState() {
    super.initState();
    _loadReturns();
  }

  Future<void> _loadReturns() async {
    setState(() => _isLoading = true);
    try {
      final rows = await SupabaseService.getReturns();

      final mapped = rows.map<Map<String, dynamic>>((row) {
        final createdAt = row['created_at'] as String?;
        final date = createdAt != null ? DateTime.tryParse(createdAt) : null;
        final List items = (row['return_items'] as List?) ?? const [];
        // Joined sale (may be a Map or a List depending on relation config)
        Map<String, dynamic>? sale;
        final s = row['sales'];
        if (s is Map<String, dynamic>) {
          sale = s;
        } else if (s is List &&
            s.isNotEmpty &&
            s.first is Map<String, dynamic>) {
          sale = Map<String, dynamic>.from(s.first as Map);
        }

        // Compute totals if not provided
        double computedTotal = 0;
        for (final it in items) {
          final q =
              (it['quantity_returned'] as num?)?.toDouble() ??
              (it['quantity'] as num?)?.toDouble() ??
              0;
          final p =
              (it['original_price_per_unit'] as num?)?.toDouble() ??
              (it['price_per_unit'] as num?)?.toDouble() ??
              (it['price'] as num?)?.toDouble() ??
              0;
          computedTotal += q * p;
        }

        return {
          'id': row['id'],
          'return_number': row['return_number'] ?? 'N/A',
          'customer_name':
              row['customer_name'] ??
              sale?['customer_name'] ??
              'Walk-in Customer',
          'original_sale_id':
              row['original_sale_id'] ?? row['sale_id'] ?? sale?['id'],
          'receipt_number': sale?['id'],
          'notes': row['notes'] ?? '',
          'status': (row['status'] ?? 'pending').toString().toLowerCase(),
          'total_return_amount':
              (row['total_return_amount'] as num?)?.toDouble() ?? computedTotal,
          'created_at': (date ?? DateTime.now()).toIso8601String(),
          'return_items': items,
        };
      }).toList();

      setState(() {
        _returns = mapped;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to load returns: $e')));
      }
    }
  }

  List<Map<String, dynamic>> get _filteredReturns {
    final now = DateTime.now();
    return _returns.where((r) {
      final search = _searchQuery.trim().toLowerCase();
      final rn = (r['return_number'] ?? '').toString().toLowerCase();
      final cust = (r['customer_name'] ?? '').toString().toLowerCase();
      final notes = (r['notes'] ?? '').toString().toLowerCase();
      final receipt = (r['receipt_number'] ?? '').toString().toLowerCase();
      final matchesSearch =
          search.isEmpty ||
          rn.contains(search) ||
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
    // Normalize backend statuses to Svelte filter options
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

  @override
  Widget build(BuildContext context) {
    final returns = _filteredReturns;
    final totalValue = returns.fold<double>(
      0,
      (s, r) => s + ((r['total_return_amount'] as num?)?.toDouble() ?? 0),
    );

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        top: false,
        bottom: true,
        child: SingleChildScrollView(
          child: Column(
            children: [
              PageHeader(
                title: 'Returns History',
                description: 'View and manage product returns',
                icon: '↩️',
                showBackButton: true,
                backLabel: 'Back to Sales History',
                wrapInSafeArea: true,
                breadcrumbs: [
                  PageHeaderBreadcrumb(label: 'Dashboard', icon: '🏠', href: '/'),
                  if (MediaQuery.of(context).size.width >= 450)
                    PageHeaderBreadcrumb(label: 'Sales History', icon: '📊', href: '/sales-history'),
                  if (MediaQuery.of(context).size.width >= 600)
                    PageHeaderBreadcrumb(
                      label: 'Returns History',
                      icon: '↩️',
                      current: true,
                    ),
                ],
                stats: [
                  PageHeaderStat(
                    label: 'Total Returns',
                    value: '${_returns.length}',
                    description: '${returns.length} shown after filters',
                  ),
                  PageHeaderStat(
                    label: 'Total Value',
                    value: '₹${totalValue.toStringAsFixed(0)}',
                    description: 'Total return amount processed',
                  ),
                ],
                actions: [
                  PageHeaderAction(
                    label: 'Process Return',
                    shortLabel: 'New Return',
                    icon: Icons.add,
                    color: Theme.of(context).colorScheme.primary,
                    onPressed: () {
                      if (!ConnectivityService().isOnline.value) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'You are offline. Cannot process returns.',
                            ),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }
                      Navigator.of(context).pushNamed('/returns');
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
                        _buildFilters(),
                        const SizedBox(height: 16),
                        if (_isLoading)
                          _buildLoading()
                        else if (returns.isEmpty)
                          _buildEmptyState()
                        else
                          _buildReturnsList(returns),
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
              // Use Expanded only in horizontal (wide) mode; in vertical mode,
              // avoid Expanded to prevent unbounded height constraints.
              isWide
                  ? Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Search Returns',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            decoration: InputDecoration(
                              hintText:
                                  'Search by return number, customer, or reason...',
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
                            'Search Returns',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            decoration: InputDecoration(
                              hintText:
                                  'Search by return number, customer, or reason...',
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
    return Container(
      padding: const EdgeInsets.all(48),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
        ),
      ),
      child: const Center(child: CircularProgressIndicator()),
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
          const Text('↩️', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 12),
          Text(
            _searchQuery.isNotEmpty ||
                    _statusFilter != 'all' ||
                    _dateFilter != 'all'
                ? 'No returns match your current filters. Try adjusting your search criteria.'
                : 'No returns have been processed yet. Returns will appear here once customers return products.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => Navigator.of(context).pushNamed('/returns'),
            icon: const Icon(Icons.add),
            label: const Text('Process New Return'),
          ),
        ],
      ),
    );
  }

  Widget _buildReturnsList(List<Map<String, dynamic>> returns) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: returns.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final r = returns[index];
        final created =
            DateTime.tryParse((r['created_at'] ?? '') as String) ??
            DateTime.now();
        final amount = (r['total_return_amount'] as num?)?.toDouble() ?? 0;
        final status = (r['status'] ?? 'pending').toString();
        final items = (r['return_items'] as List?) ?? const [];
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
                        color: _statusColor(status).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _statusColor(status).withValues(alpha: 0.2),
                        ),
                      ),
                      child: Icon(Icons.reply, color: _statusColor(status)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Return #${r['return_number']}',
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
                                'Customer: ${r['customer_name'] ?? ''}',
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
                            color: _statusColor(status).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            _mapStatus(status).toUpperCase(),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: _statusColor(status),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '₹${amount.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                        Text(
                          _formatDate(created),
                          style: _mutedStyle(fontSize: 11),
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
                      'Return Reason',
                      (r['notes'] as String).isNotEmpty
                          ? r['notes']
                          : 'No reason specified',
                    ),
                    _pill('Items Returned', '${items.length} items'),
                  ],
                ),

                if (items.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 8),
                  const Text(
                    'Returned Items',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  ...items.map((it) {
                    final product =
                        (it['products'] as Map<String, dynamic>?) ?? const {};
                    final name =
                        it['product_name'] ??
                        product['name'] ??
                        'Unknown Product';
                    final qty = it['quantity_returned'] ?? it['quantity'] ?? 0;
                    final price =
                        (it['original_price_per_unit'] as num?)?.toDouble() ??
                        (it['price_per_unit'] as num?)?.toDouble() ??
                        0.0;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
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
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Text(
                                  'Condition: ${it['item_condition'] ?? it['condition'] ?? 'N/A'}',
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
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                '₹${(qty * price).toStringAsFixed(2)}',
                                style: _mutedStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
        );
      },
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
}
