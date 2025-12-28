import 'package:flutter/material.dart';
import '../widgets/page_header.dart';
import '../widgets/search_bar_widget.dart';
import '../data/app_database.dart';
import '../services/supabase_service.dart';
import '../services/connectivity_service.dart';

class ReplacementsPage extends StatefulWidget {
  final AppDatabase db;
  const ReplacementsPage({super.key, required this.db});

  @override
  State<ReplacementsPage> createState() => _ReplacementsPageState();
}

class _ReplacementsPageState extends State<ReplacementsPage> {
  String _searchTerm = '';
  String _statusFilter = 'All';
  DateTimeRange? _dateRange;
  List<Map<String, dynamic>> _replacements = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadReplacements();
  }

  Future<void> _loadReplacements() async {
    setState(() => _isLoading = true);
    try {
      final rows = await SupabaseService.getReplacements();

      if (rows.isEmpty) {
        setState(() {
          _replacements = _mockReplacements; // fallback if table absent
          _isLoading = false;
        });
        return;
      }

      final mapped = rows.map<Map<String, dynamic>>((row) {
        final createdAt = row['created_at'] as String?;
        final date = createdAt != null ? DateTime.tryParse(createdAt) : null;

        // Sales join (map or single element list)
        Map<String, dynamic>? sale;
        final s = row['sales'];
        if (s is Map<String, dynamic>) {
          sale = s;
        } else if (s is List &&
            s.isNotEmpty &&
            s.first is Map<String, dynamic>) {
          sale = Map<String, dynamic>.from(s.first as Map);
        }

        // Prefer new relations if present; fallback to legacy replacement_items
        final List rawOut = (row['replacement_items_out'] as List?) ?? const [];
        final List rawIn = (row['replacement_items_in'] as List?) ?? const [];
        List<Map<String, dynamic>> linesOut = [];
        List<Map<String, dynamic>> linesIn = [];

        if (rawOut.isNotEmpty || rawIn.isNotEmpty) {
          linesOut = rawOut.map<Map<String, dynamic>>((it) {
            final prod = (it['products'] as Map<String, dynamic>?) ?? const {};
            return {
              'name': it['product_name'] ?? prod['name'] ?? 'Item',
              'qty':
                  (it['quantity_returned'] ?? it['quantity'] ?? it['qty'] ?? 0)
                      as int,
              'price':
                  ((it['original_price_per_unit'] as num?)?.toDouble() ??
                  (it['price_per_unit'] as num?)?.toDouble() ??
                  (it['price'] as num?)?.toDouble() ??
                  0.0),
              'image': '📦',
              'condition': it['item_condition'] ?? it['condition'] ?? '',
            };
          }).toList();
          linesIn = rawIn.map<Map<String, dynamic>>((it) {
            final prod = (it['products'] as Map<String, dynamic>?) ?? const {};
            return {
              'name': it['product_name'] ?? prod['name'] ?? 'Item',
              'qty':
                  (it['quantity_given'] ?? it['quantity'] ?? it['qty'] ?? 0)
                      as int,
              'price':
                  ((it['price_per_unit'] as num?)?.toDouble() ??
                  (it['price'] as num?)?.toDouble() ??
                  0.0),
              'image': '📦',
              'condition': it['item_condition'] ?? it['condition'] ?? 'New',
            };
          }).toList();
        } else {
          final List items = (row['replacement_items'] as List?) ?? const [];
          for (final it in items) {
            final prod = (it['products'] as Map<String, dynamic>?) ?? const {};
            final mapItem = {
              'name': it['product_name'] ?? prod['name'] ?? 'Item',
              'qty': it['quantity'] ?? it['qty'] ?? 1,
              'price':
                  (it['price'] as num?)?.toDouble() ??
                  (it['price_per_unit'] as num?)?.toDouble() ??
                  0.0,
              'image': '📦',
              'condition': it['condition'] ?? '',
            };
            final dir = (it['direction'] ?? it['type'] ?? 'out').toString();
            if (dir.toLowerCase() == 'in') {
              linesIn.add(mapItem);
            } else {
              linesOut.add(mapItem);
            }
          }
        }

        final itemsOut = linesOut.fold<int>(0, (s, e) => s + (e['qty'] as int));
        final itemsIn = linesIn.fold<int>(0, (s, e) => s + (e['qty'] as int));
        final totalOut = linesOut.fold<double>(
          0,
          (s, e) => s + ((e['qty'] as int) * (e['price'] as double)),
        );
        final totalIn = linesIn.fold<double>(
          0,
          (s, e) => s + ((e['qty'] as int) * (e['price'] as double)),
        );
        final amountDiff =
            ((row['amount_difference'] as num?)?.toDouble()) ??
            (totalIn - totalOut);

        return {
          'id': row['id'] != null
              ? 'REP-${row['id']}'
              : (row['reference'] ?? 'REP-?'),
          'date': date ?? DateTime.now(),
          'customer':
              row['customer_name'] ??
              sale?['customer_name'] ??
              row['customer'] ??
              'Walk-in Customer',
          'customer_phone': row['customer_phone'] ?? 'N/A',
          'original_sale': sale?['id'] != null
              ? 'S-${sale?['id']}'
              : (row['sale_id'] != null
                    ? 'S-${row['sale_id']}'
                    : (row['original_sale'] ?? '')),
          'items_out': itemsOut,
          'items_in': itemsIn,
          'amount_difference': amountDiff,
          'reason': row['reason'] ?? row['notes'] ?? '',
          'status': row['status'] ?? 'Pending',
          'priority': row['priority'] ?? 'Medium',
          'lines_out': linesOut,
          'lines_in': linesIn,
        };
      }).toList();

      setState(() {
        _replacements = mapped;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _replacements = _mockReplacements; // Fallback to mock data
        _isLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filteredReplacements {
    final list = _replacements.where((r) {
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
          ) ||
          r['original_sale'].toString().toLowerCase().contains(
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

    return list;
  }

  final List<Map<String, dynamic>> _mockReplacements = [
    {
      'id': 'REP-2008',
      'date': DateTime.now().subtract(const Duration(days: 0)),
      'customer': 'Rahul Sharma',
      'customer_phone': '+91 98765 43210',
      'original_sale': 'S-1008',
      'items_out': 1,
      'items_in': 1,
      'amount_difference': 50.0,
      'reason': 'Defective product',
      'status': 'Pending',
      'priority': 'High',
      'lines_out': [
        {
          'name': 'LED Bulb 9W',
          'qty': 1,
          'price': 120.0,
          'image': '💡',
          'condition': 'Defective',
        },
      ],
      'lines_in': [
        {
          'name': 'LED Bulb 12W',
          'qty': 1,
          'price': 170.0,
          'image': '💡',
          'condition': 'New',
        },
      ],
    },
    {
      'id': 'REP-2007',
      'date': DateTime.now().subtract(const Duration(days: 1)),
      'customer': 'Anita Verma',
      'customer_phone': '+91 87654 32109',
      'original_sale': 'S-1007',
      'items_out': 2,
      'items_in': 2,
      'amount_difference': -30.0,
      'reason': 'Wrong size ordered',
      'status': 'Completed',
      'priority': 'Medium',
      'lines_out': [
        {
          'name': 'Switch Board 6M',
          'qty': 2,
          'price': 380.0,
          'image': '🔘',
          'condition': 'Good',
        },
      ],
      'lines_in': [
        {
          'name': 'Switch Board 4M',
          'qty': 2,
          'price': 350.0,
          'image': '🔘',
          'condition': 'New',
        },
      ],
    },
    {
      'id': 'REP-2006',
      'date': DateTime.now().subtract(const Duration(days: 3)),
      'customer': 'Priya Singh',
      'customer_phone': '+91 76543 21098',
      'original_sale': 'S-1006',
      'items_out': 1,
      'items_in': 1,
      'amount_difference': 0.0,
      'reason': 'Color preference',
      'status': 'Completed',
      'priority': 'Low',
      'lines_out': [
        {
          'name': 'Extension Cord 5m Black',
          'qty': 1,
          'price': 350.0,
          'image': '🔌',
          'condition': 'Excellent',
        },
      ],
      'lines_in': [
        {
          'name': 'Extension Cord 5m White',
          'qty': 1,
          'price': 350.0,
          'image': '🔌',
          'condition': 'New',
        },
      ],
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SingleChildScrollView(
        child: Column(
          children: [
            PageHeader(
              title: 'Replacements History',
              description: 'View and manage product replacement records',
              icon: '🔄',
              showBackButton: true,
              backLabel: 'Back to Dashboard',
              breadcrumbs: [
                PageHeaderBreadcrumb(label: 'Dashboard', icon: '🏠'),
                PageHeaderBreadcrumb(
                  label: 'Replacements',
                  icon: '🔄',
                  current: true,
                ),
              ],
              stats: [
                PageHeaderStat(
                  label: 'Total Replacements',
                  value: _replacements.length.toString(),
                  description: 'All time',
                ),
                PageHeaderStat(
                  label: 'Pending',
                  value: _replacements
                      .where((r) => r['status'] == 'Pending')
                      .length
                      .toString(),
                  description: 'Awaiting processing',
                ),
                PageHeaderStat(
                  label: 'Completed Today',
                  value: _replacements
                      .where(
                        (r) =>
                            r['status'] == 'Completed' &&
                            (r['date'] as DateTime).isAfter(
                              DateTime.now().subtract(const Duration(days: 1)),
                            ),
                      )
                      .length
                      .toString(),
                  description: 'Successfully processed',
                ),
              ],
            ),

            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  SearchBarWidget(
                    placeholder:
                        'Search by replacement ID, customer, or reason...',
                    onSearchChanged: (value) =>
                        setState(() => _searchTerm = value),
                    resultCount: _searchTerm.isNotEmpty
                        ? _filteredReplacements.length
                        : null,
                    totalCount: _searchTerm.isNotEmpty
                        ? _replacements.length
                        : null,
                  ),
                  const SizedBox(height: 16),
                  _buildToolbar(),
                  const SizedBox(height: 16),
                  _buildReplacementsList(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: _statusFilter,
              decoration: InputDecoration(
                labelText: 'Filter by Status',
                labelStyle: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                border: OutlineInputBorder(
                  borderSide: BorderSide(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(
                    color: Theme.of(context).colorScheme.primary,
                    width: 2,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                filled: true,
                fillColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest,
              ),
              items: ['All', 'Pending', 'Completed', 'Cancelled']
                  .map(
                    (status) =>
                        DropdownMenuItem(value: status, child: Text(status)),
                  )
                  .toList(),
              onChanged: (value) =>
                  setState(() => _statusFilter = value ?? 'All'),
            ),
          ),
          const SizedBox(width: 16),
          OutlinedButton.icon(
            onPressed: () async {
              final picked = await showDateRangePicker(
                context: context,
                firstDate: DateTime.now().subtract(const Duration(days: 365)),
                lastDate: DateTime.now(),
                initialDateRange: _dateRange,
              );
              if (picked != null) setState(() => _dateRange = picked);
            },
            icon: const Icon(Icons.date_range),
            label: Text(
              _dateRange == null ? 'Select Date Range' : 'Date Range Selected',
            ),
          ),
          if (_dateRange != null) ...[
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: () => setState(() => _dateRange = null),
              icon: const Icon(Icons.clear),
              label: const Text('Clear filters'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildReplacementsList() {
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

    final replacements = _filteredReplacements;
    if (replacements.isEmpty) {
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
              'No matching replacements found',
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
          return _buildDesktopTable(replacements);
        } else {
          return _buildMobileCards(replacements);
        }
      },
    );
  }

  Widget _buildDesktopTable(List<Map<String, dynamic>> replacements) {
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
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Text(
                    'Replacement ID',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Customer',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Reason',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Text(
                    'Items',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Text(
                    'Difference',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Text(
                    'Status',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Text(
                    'Actions',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ),
              ],
            ),
          ),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: replacements.length,
            itemBuilder: (context, index) =>
                _buildDesktopTableRow(replacements[index]),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopTableRow(Map<String, dynamic> replacement) {
    final isPending = replacement['status'] == 'Pending';
    final difference = replacement['amount_difference'] as double;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  replacement['id'],
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  '${replacement['date'].day}/${replacement['date'].month}/${replacement['date'].year}',
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
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  replacement['customer'],
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                Text(
                  replacement['customer_phone'],
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
          Expanded(
            flex: 2,
            child: Text(
              replacement['reason'],
              style: const TextStyle(fontSize: 13),
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              '${replacement['items_out']} → ${replacement['items_in']}',
              style: const TextStyle(fontSize: 13),
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              difference == 0
                  ? '₹0'
                  : (difference > 0
                        ? '+₹${difference.toStringAsFixed(0)}'
                        : '-₹${(-difference).toStringAsFixed(0)}'),
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: difference == 0
                    ? Theme.of(context).colorScheme.onSurfaceVariant
                    : (difference > 0
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.error),
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isPending
                    ? Theme.of(context).colorScheme.tertiaryContainer
                    : Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                replacement['status'],
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isPending
                      ? Theme.of(context).colorScheme.tertiary
                      : Theme.of(context).colorScheme.primary,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: () => _showReplacementDetails(replacement),
                  icon: const Icon(Icons.visibility, size: 18),
                  tooltip: 'View Details',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileCards(List<Map<String, dynamic>> replacements) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: replacements.length,
      itemBuilder: (context, index) => _buildMobileCard(replacements[index]),
    );
  }

  Widget _buildMobileCard(Map<String, dynamic> replacement) {
    final isPending = replacement['status'] == 'Pending';
    final difference = replacement['amount_difference'] as double;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
      child: InkWell(
        onTap: () => _showReplacementDetails(replacement),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    replacement['id'],
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: isPending
                          ? Theme.of(context).colorScheme.tertiaryContainer
                          : Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      replacement['status'],
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isPending
                            ? Theme.of(context).colorScheme.tertiary
                            : Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                replacement['customer'],
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              Text(
                replacement['customer_phone'],
                style: TextStyle(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.6),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Reason: ${replacement['reason']}',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Items: ${replacement['items_out']} → ${replacement['items_in']}',
                  ),
                  Text(
                    difference == 0
                        ? '₹0'
                        : (difference > 0
                              ? '+₹${difference.toStringAsFixed(0)}'
                              : '-₹${(-difference).toStringAsFixed(0)}'),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: difference == 0
                          ? Theme.of(context).colorScheme.onSurfaceVariant
                          : (difference > 0
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.error),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showReplacementDetails(Map<String, dynamic> replacement) {
    final isPending = replacement['status'] == 'Pending';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Replacement ${replacement['id']}'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow('Customer', replacement['customer']),
              _buildDetailRow('Phone', replacement['customer_phone']),
              _buildDetailRow('Original Sale', replacement['original_sale']),
              _buildDetailRow('Reason', replacement['reason']),
              _buildDetailRow('Status', replacement['status']),
              _buildDetailRow('Priority', replacement['priority']),
              const SizedBox(height: 16),
              const Text(
                'Items Going Out:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ...replacement['lines_out'].map<Widget>(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Text(item['image'], style: const TextStyle(fontSize: 16)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('${item['name']} (${item['condition']})'),
                      ),
                      Text(
                        '${item['qty']}x ₹${item['price'].toStringAsFixed(0)}',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Items Coming In:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ...replacement['lines_in'].map<Widget>(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Text(item['image'], style: const TextStyle(fontSize: 16)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('${item['name']} (${item['condition']})'),
                      ),
                      Text(
                        '${item['qty']}x ₹${item['price'].toStringAsFixed(0)}',
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          if (isPending) ...[
            TextButton(
              onPressed: () {
                if (!ConnectivityService().isOnline.value) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('You are offline. Cannot decline.'),
                    ),
                  );
                  return;
                }
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Replacement declined'),
                    backgroundColor: Theme.of(context).colorScheme.error,
                  ),
                );
              },
              child: const Text('Decline'),
            ),
            ElevatedButton(
              onPressed: () {
                if (!ConnectivityService().isOnline.value) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('You are offline. Cannot approve.'),
                    ),
                  );
                  return;
                }
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Replacement approved successfully'),
                    backgroundColor: Theme.of(context).colorScheme.primary,
                  ),
                );
              },
              child: const Text('Approve'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
