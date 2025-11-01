import 'package:flutter/material.dart';
import '../widgets/page_header.dart';
import '../widgets/search_bar_widget.dart';
import '../data/app_database.dart';
import '../services/supabase_service.dart';

class ReturnsPage extends StatefulWidget {
  final AppDatabase db;
  const ReturnsPage({super.key, required this.db});

  @override
  State<ReturnsPage> createState() => _ReturnsPageState();
}

class _ReturnsPageState extends State<ReturnsPage> {
  String _searchTerm = '';
  String _statusFilter = 'All';
  DateTimeRange? _dateRange;
  List<Map<String, dynamic>> _returns = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadReturns();
  }

  Future<void> _loadReturns() async {
    setState(() => _isLoading = true);
    try {
      final rows = await SupabaseService.getReturns();

      if (rows.isEmpty) {
        setState(() {
          _returns = [];
          _isLoading = false;
        });
        return;
      }

      final mapped = rows.map<Map<String, dynamic>>((row) {
        final createdAt = row['return_date'] as String? ?? row['created_at'] as String?;
        final date = createdAt != null ? DateTime.tryParse(createdAt) : null;
        final List items = (row['return_items'] as List?) ?? const [];
        final int itemCount = items.length;

        double computedTotal = 0;
        for (final it in items) {
          final q = (it['quantity_returned'] as num?)?.toDouble() ?? 0;
          final p = (it['original_price_per_unit'] as num?)?.toDouble() ?? 0;
          computedTotal += q * p;
        }

        final displayId = (row['return_number'] as String?) ?? 'R-${row['id']}';
        final amount = (row['total_return_amount'] as num?)?.toDouble() ?? computedTotal;
        // Heuristic type: treat as refund when there is a refund method and positive amount
        final String returnType = (row['refund_method'] != null && amount > 0)
            ? 'Refund'
            : 'Return';

        return {
          'id': displayId,
          'date': date ?? DateTime.now(),
          'customer': row['customer_name'] ?? 'Walk-in Customer',
          'customer_phone': row['customer_phone'] ?? 'N/A',
          'original_sale': row['original_sale_id'] != null
              ? 'S-${row['original_sale_id']}'
              : '',
          'items': itemCount,
          'amount': amount,
          'refund_amount': amount,
          'reason': row['notes'] ?? '',
          'return_type': returnType,
          'status': _titleCase(row['status']?.toString() ?? 'Pending'),
          'priority': 'Medium',
          'lines': items.map<Map<String, dynamic>>((it) {
            final prod = (it['products'] as Map<String, dynamic>?) ?? const {};
            return {
              'name': prod['name'] ?? 'Item ${it['product_id'] ?? ''}',
              'qty': it['quantity_returned'] ?? 1,
              'price': (it['original_price_per_unit'] as num?)?.toDouble() ?? 0.0,
              'image': '📦',
              'condition': it['item_condition'] ?? '',
            };
          }).toList(),
        };
      }).toList();

      setState(() {
        _returns = mapped;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _returns = [];
        _isLoading = false;
      });
    }
  }

  String _titleCase(String s) {
    if (s.isEmpty) return s;
    final parts = s.split(RegExp(r'[\s_\-]+'));
    return parts
        .map((w) => w.isEmpty
            ? w
            : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
        .join(' ');
  }

  List<Map<String, dynamic>> get _filteredReturns {
    final list = _returns.where((r) {
      final matchesSearch =
          _searchTerm.isEmpty ||
          r['id'].toString().toLowerCase().contains(
            _searchTerm.toLowerCase(),
          ) ||
          r['customer'].toString().toLowerCase().contains(
            _searchTerm.toLowerCase(),
          ) ||
          r['reason'].toString().toLowerCase().contains(
            _searchTerm.toLowerCase(),
          );

      final matchesStatus =
          _statusFilter == 'All' || r['status'] == _statusFilter;

      final matchesDate =
          _dateRange == null ||
          (r['date'] as DateTime).isAfter(
                _dateRange!.start.subtract(const Duration(days: 1)),
              ) &&
              (r['date'] as DateTime).isBefore(
                _dateRange!.end.add(const Duration(days: 1)),
              );

      return matchesSearch && matchesStatus && matchesDate;
    }).toList();

    // Default sort by date desc
    list.sort(
      (a, b) => (b['date'] as DateTime).compareTo(a['date'] as DateTime),
    );
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        top: true,
        bottom: false,
        child: SingleChildScrollView(
          child: Column(
            children: [
              PageHeader(
                title: 'Returns',
                description: 'Manage and track product returns',
                icon: '↩️',
                showBackButton: true,
                backLabel: 'Back to Dashboard',
                breadcrumbs: [
                  PageHeaderBreadcrumb(label: 'Dashboard', icon: '🏠'),
                  PageHeaderBreadcrumb(
                    label: 'Returns',
                    icon: '↩️',
                    current: true,
                  ),
                ],
                stats: [
                  PageHeaderStat(
                    label: 'Total Returns',
                    value: '${_returns.length}',
                    description: 'All return requests',
                  ),
                  PageHeaderStat(
                    label: 'Pending Review',
                    value:
                        '${_returns.where((e) => e['status'] == 'Pending').length}',
                    description: 'Awaiting action',
                  ),
                  PageHeaderStat(
                    label: 'Total Refunds',
                    value:
                        '₹${_returns.where((e) => e['status'] == 'Completed').fold<double>(0, (s, e) => s + ((e['refund_amount'] as num?)?.toDouble() ?? 0)).toStringAsFixed(0)}',
                    description: 'Processed refunds',
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
                    SearchBarWidget(
                      placeholder:
                          'Search by return ID, customer, or reason...',
                      onSearchChanged: (value) =>
                          setState(() => _searchTerm = value),
                      resultCount: _searchTerm.isNotEmpty
                          ? _filteredReturns.length
                          : null,
                      totalCount: _searchTerm.isNotEmpty
                          ? _returns.length
                          : null,
                    ),
                    const SizedBox(height: 16),
                    _buildToolbar(),
                    const SizedBox(height: 16),
                    _buildReturnsList(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1),
        ),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // Date range
          InkWell(
            onTap: () async {
              final now = DateTime.now();
              final lastMonth = now.subtract(const Duration(days: 30));
              final picked = await showDateRangePicker(
                context: context,
                firstDate: DateTime(now.year - 5),
                lastDate: DateTime(now.year + 5),
                initialDateRange:
                    _dateRange ?? DateTimeRange(start: lastMonth, end: now),
              );
              if (picked != null) setState(() => _dateRange = picked);
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(
                    context,
                  ).colorScheme.outline.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.max,
                children: [
                  Icon(
                    Icons.date_range,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _dateRange == null
                          ? 'Date: All time'
                          : '${_dateRange!.start.day}/${_dateRange!.start.month}/${_dateRange!.start.year} - ${_dateRange!.end.day}/${_dateRange!.end.month}/${_dateRange!.end.year}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Status filter
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Status:',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: _statusFilter,
                items: const [
                  DropdownMenuItem(value: 'All', child: Text('All')),
                  DropdownMenuItem(value: 'Pending', child: Text('Pending')),
                  DropdownMenuItem(
                    value: 'Processing',
                    child: Text('Processing'),
                  ),
                  DropdownMenuItem(value: 'Approved', child: Text('Approved')),
                  DropdownMenuItem(
                    value: 'Completed',
                    child: Text('Completed'),
                  ),
                  DropdownMenuItem(value: 'Declined', child: Text('Declined')),
                ],
                onChanged: (v) => setState(() => _statusFilter = v ?? 'All'),
              ),
            ],
          ),

          if (_dateRange != null)
            TextButton.icon(
              onPressed: () => setState(() => _dateRange = null),
              icon: const Icon(Icons.clear),
              label: const Text('Clear filters'),
            ),
        ],
      ),
    );
  }

  Widget _buildReturnsList() {
    if (_isLoading) {
      return Container(
        padding: const EdgeInsets.all(48),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1),
          ),
        ),
        child: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(
              Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
      );
    }

    final returns = _filteredReturns;
    if (returns.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(48),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1),
          ),
        ),
        child: Column(
          children: [
            const Text('🔍', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            Text(
              'No matching returns found',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth > 768;

        if (isDesktop) {
          return _buildDesktopTable(returns);
        } else {
          return _buildMobileCards(returns);
        }
      },
    );
  }

  Widget _buildDesktopTable(List<Map<String, dynamic>> returns) {
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
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(
                    context,
                  ).colorScheme.outline.withValues(alpha: 0.1),
                ),
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 100,
                  child: Text(
                    'Return ID',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ),
                SizedBox(
                  width: 120,
                  child: Text(
                    'Date',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    'Customer & Reason',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 120,
                  child: Text(
                    'Type',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 120,
                  child: Text(
                    'Priority',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 120,
                  child: Text(
                    'Amount',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 120,
                  child: Text(
                    'Status',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ],
            ),
          ),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: returns.length,
            separatorBuilder: (_, __) => Divider(
              height: 1,
              color: Theme.of(
                context,
              ).colorScheme.outline.withValues(alpha: 0.1),
            ),
            itemBuilder: (context, index) {
              final r = returns[index];

              return InkWell(
                onTap: () => _showReturnDetailDialog(r),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 100,
                        child: Text(
                          r['id'],
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                      SizedBox(width: 120, child: Text(_fmtDate(r['date']))),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              r['customer'],
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              r['reason'],
                              style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.6),
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 120,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: r['return_type'] == 'Exchange'
                                ? Theme.of(context).colorScheme.primaryContainer
                                : Theme.of(
                                    context,
                                  ).colorScheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: r['return_type'] == 'Exchange'
                                  ? Theme.of(
                                      context,
                                    ).colorScheme.primary.withValues(alpha: 0.3)
                                  : Theme.of(context).colorScheme.secondary
                                        .withValues(alpha: 0.3),
                            ),
                          ),
                          child: Text(
                            r['return_type'],
                            style: TextStyle(
                              fontSize: 11,
                              color: r['return_type'] == 'Exchange'
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.secondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 120,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: _getPriorityColor(
                              r['priority'],
                            ).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: _getPriorityColor(
                                r['priority'],
                              ).withValues(alpha: 0.2),
                            ),
                          ),
                          child: Text(
                            r['priority'],
                            style: TextStyle(
                              fontSize: 11,
                              color: _getPriorityColor(r['priority']),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 120,
                        child: Text(
                          '₹${(r['amount'] as num).toStringAsFixed(0)}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 120,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _statusColor(
                              r['status'],
                            ).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: _statusColor(
                                r['status'],
                              ).withValues(alpha: 0.2),
                            ),
                          ),
                          child: Text(
                            r['status'],
                            style: TextStyle(
                              color: _statusColor(r['status']),
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMobileCards(List<Map<String, dynamic>> returns) {
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
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: returns.length,
        separatorBuilder: (_, __) => Divider(
          height: 1,
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1),
        ),
        itemBuilder: (context, index) {
          final r = returns[index];

          return InkWell(
            onTap: () => _showReturnDetailDialog(r),
            child: Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: _statusColor(
                            r['status'],
                          ).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _statusColor(
                              r['status'],
                            ).withValues(alpha: 0.2),
                          ),
                        ),
                        child: const Center(child: Text('↩️')),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              r['id'],
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                            Text(
                              _fmtDate(r['date']),
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.6),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '₹${(r['amount'] as num).toStringAsFixed(0)}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    r['reason'],
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _chip(
                        '👤 ${r['customer']}',
                        Theme.of(context).colorScheme.primary,
                      ),
                      _chip(
                        '📦 ${r['items']} items',
                        Theme.of(context).colorScheme.secondary,
                      ),
                      _chip(
                        '🔄 ${r['return_type']}',
                        r['return_type'] == 'Exchange'
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.secondary,
                      ),
                      _chip(
                        '⚡ ${r['priority']}',
                        _getPriorityColor(r['priority']),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _statusColor(
                            r['status'],
                          ).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: _statusColor(
                              r['status'],
                            ).withValues(alpha: 0.2),
                          ),
                        ),
                        child: Text(
                          r['status'],
                          style: TextStyle(
                            color: _statusColor(r['status']),
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _fmtDate(DateTime d) => '${d.day}/${d.month}/${d.year}';

  Color _statusColor(String status) {
    final cs = Theme.of(context).colorScheme;
    switch (status) {
      case 'Pending':
        return cs.tertiary;
      case 'Processing':
        return cs.primary;
      case 'Approved':
        return cs.primary;
      case 'Completed':
        return cs.primary;
      case 'Declined':
        return cs.error;
      default:
        return Theme.of(context).colorScheme.onSurfaceVariant;
    }
  }

  Color _getPriorityColor(String priority) {
    final cs = Theme.of(context).colorScheme;
    switch (priority) {
      case 'High':
        return cs.error;
      case 'Medium':
        return cs.tertiary;
      case 'Low':
        return cs.primary;
      default:
        return cs.onSurfaceVariant;
    }
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, color: color)),
    );
  }

  Future<void> _showReturnDetailDialog(Map<String, dynamic> returnData) async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        final items =
            ((returnData['lines'] as List?) ??
                    (returnData['returned_items'] as List?) ??
                    const [])
                .cast<Map<String, dynamic>>();
        final isPending = returnData['status'] == 'Pending';

        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 600,
              maxHeight: MediaQuery.of(context).size.height * 0.9,
            ),
            child: Container(
              width: MediaQuery.of(context).size.width * 0.9,
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: _statusColor(
                            returnData['status'],
                          ).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _statusColor(
                              returnData['status'],
                            ).withValues(alpha: 0.2),
                          ),
                        ),
                        child: const Center(
                          child: Text('↩️', style: TextStyle(fontSize: 20)),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Return ${returnData['id']}',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              _fmtDate(returnData['date']),
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: _statusColor(
                            returnData['status'],
                          ).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _statusColor(
                              returnData['status'],
                            ).withValues(alpha: 0.2),
                          ),
                        ),
                        child: Text(
                          returnData['status'],
                          style: TextStyle(
                            color: _statusColor(returnData['status']),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Customer Information
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Theme.of(
                          context,
                        ).colorScheme.outline.withValues(alpha: 0.1),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Customer Information',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Name: ${returnData['customer']}'),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Phone: ${returnData['customer_phone']}',
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Original Sale: ${returnData['original_sale']}',
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color:
                                        returnData['return_type'] == 'Exchange'
                                        ? Theme.of(
                                            context,
                                          ).colorScheme.primaryContainer
                                        : Theme.of(
                                            context,
                                          ).colorScheme.secondaryContainer,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color:
                                          returnData['return_type'] ==
                                              'Exchange'
                                          ? Theme.of(context)
                                                .colorScheme
                                                .primary
                                                .withValues(alpha: 0.3)
                                          : Theme.of(context)
                                                .colorScheme
                                                .secondary
                                                .withValues(alpha: 0.3),
                                    ),
                                  ),
                                  child: Text(
                                    returnData['return_type'],
                                    style: TextStyle(
                                      fontSize: 12,
                                      color:
                                          returnData['return_type'] ==
                                              'Exchange'
                                          ? Theme.of(
                                              context,
                                            ).colorScheme.primary
                                          : Theme.of(
                                              context,
                                            ).colorScheme.secondary,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _getPriorityColor(
                                      returnData['priority'],
                                    ).withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: _getPriorityColor(
                                        returnData['priority'],
                                      ).withValues(alpha: 0.2),
                                    ),
                                  ),
                                  child: Text(
                                    '${returnData['priority']} Priority',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: _getPriorityColor(
                                        returnData['priority'],
                                      ),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Return Reason & Details
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Theme.of(
                          context,
                        ).colorScheme.error.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Return Details',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text('Reason: ${returnData['reason']}'),
                        const SizedBox(height: 8),
                        Text('Condition: ${returnData['item_condition']}'),
                        const SizedBox(height: 8),
                        Text('Items: ${returnData['items']} item(s)'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Returned Items
                  const Text(
                    'Returned Items',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Theme.of(
                            context,
                          ).colorScheme.outline.withValues(alpha: 0.2),
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: items.length,
                        separatorBuilder: (_, __) => Divider(
                          height: 1,
                          color: Theme.of(
                            context,
                          ).colorScheme.outline.withValues(alpha: 0.1),
                        ),
                        itemBuilder: (context, index) {
                          final item = items[index];
                          return Container(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .outline
                                          .withValues(alpha: 0.2),
                                    ),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.network(
                                      item['image'],
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Icon(
                                        Icons.inventory_2,
                                        size: 20,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item['name'],
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      Text(
                                        'Qty: ${item['quantity']} × ₹${item['price']}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  '₹${(item['quantity'] * item['price']).toStringAsFixed(0)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Financial Summary
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Theme.of(
                          context,
                        ).colorScheme.outline.withValues(alpha: 0.1),
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Refund Amount:',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              '₹${(returnData['amount'] as num).toStringAsFixed(0)}',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Action Buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close),
                          label: const Text('Close'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      if (isPending) ...[
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: const Text('Return declined'),
                                  backgroundColor: Theme.of(
                                    context,
                                  ).colorScheme.error,
                                ),
                              );
                            },
                            icon: const Icon(Icons.close),
                            label: const Text('Decline'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.error,
                              foregroundColor: Theme.of(
                                context,
                              ).colorScheme.onError,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: const Text(
                                    'Return approved successfully',
                                  ),
                                  backgroundColor: Theme.of(
                                    context,
                                  ).colorScheme.primary,
                                ),
                              );
                            },
                            icon: const Icon(Icons.check),
                            label: const Text('Approve'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.primary,
                              foregroundColor: Theme.of(
                                context,
                              ).colorScheme.onPrimary,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ] else ...[
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: const Text('Return receipt printed'),
                                  backgroundColor: Theme.of(
                                    context,
                                  ).colorScheme.secondary,
                                ),
                              );
                            },
                            icon: const Icon(Icons.print),
                            label: const Text('Print Receipt'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.secondary,
                              foregroundColor: Theme.of(
                                context,
                              ).colorScheme.onSecondary,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _updateReturnStatus(String id, String status) {
    final idx = _returns.indexWhere((e) => e['id'] == id);
    if (idx != -1) {
      setState(() => _returns[idx]['status'] = status);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Return $id $status')));
    }
  }
}
