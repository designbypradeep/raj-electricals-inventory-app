import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import '../services/supabase_service.dart';

class OrderHistoryPage extends StatefulWidget {
  const OrderHistoryPage({super.key});

  @override
  State<OrderHistoryPage> createState() => _OrderHistoryPageState();
}

class _OrderHistoryPageState extends State<OrderHistoryPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _orders = [];
  bool _loadingMore = false;
  String? _lastCreatedAt;
  final ScrollController _scrollController = ScrollController();
  final DateFormat _dateFormat = DateFormat('MMM dd, yyyy HH:mm');

  @override
  void initState() {
    super.initState();
    _load(initial: true);
    _scrollController.addListener(_onScroll);
  }

  Future<void> _load({bool initial = false}) async {
    if (initial) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else {
      if (_loadingMore) return;
      setState(() => _loadingMore = true);
    }

    try {
      final rows = await SupabaseService.getShopOrderHistory(
        limit: 20,
        createdBefore: initial ? null : _lastCreatedAt,
      );
      if (mounted) {
        setState(() {
          if (initial) {
            _orders = rows;
            _loading = false;
          } else {
            _orders.addAll(rows);
            _loadingMore = false;
          }
          if (rows.isNotEmpty) {
            _lastCreatedAt = rows.last['created_at'] as String?;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  void _onScroll() {
    if (_loading || _loadingMore) return;
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels > pos.maxScrollExtent - 200) {
      _load(initial: false);
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not open URL')));
    }
  }

  Color _getStatusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'payment_verified':
        return Colors.green;
      case 'payment_rejected':
        return Colors.red;
      case 'cancelled':
        return Colors.grey;
      case 'expired':
        return Colors.orange;
      default:
        return Colors.blueGrey;
    }
  }

  String _formatStatus(String? status) {
    if (status == null) return 'Unknown';
    return status.replaceAll('payment_', '').toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Order History'),
        actions: [
          IconButton(
            onPressed: () => _load(initial: true),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading && _orders.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text('Error: $_error'))
          : _orders.isEmpty
          ? const Center(child: Text('No order history found'))
          : ListView.separated(
              controller: _scrollController,
              padding: const EdgeInsets.all(12),
              itemCount: _orders.length + (_loadingMore ? 1 : 0),
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                if (index == _orders.length) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(8.0),
                      child: CircularProgressIndicator(),
                    ),
                  );
                }

                final row = _orders[index];
                final saleId = (row['id'] as num).toInt();
                final customer =
                    (row['customer_name'] as String?) ?? 'Walk-in Customer';
                final amount = (row['total_amount'] as num?)?.toDouble() ?? 0.0;
                final createdAtStr = row['created_at'] as String?;
                final date = createdAtStr != null
                    ? DateTime.parse(createdAtStr).toLocal()
                    : DateTime.now();
                final status = (row['status'] as String?) ?? 'unknown';
                final items = (row['shop_order_items'] as List?) ?? [];
                final proofUrl = row['payment_proof_url'] as String?;

                return Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ExpansionTile(
                    title: Row(
                      children: [
                        Text(
                          '#$saleId',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: _getStatusColor(
                              status,
                            ).withValues(alpha: 0.1),
                            border: Border.all(
                              color: _getStatusColor(
                                status,
                              ).withValues(alpha: 0.5),
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _formatStatus(status),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: _getStatusColor(status),
                            ),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '₹${amount.toStringAsFixed(0)}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(customer, style: const TextStyle(fontSize: 13)),
                          Text(
                            _dateFormat.format(date),
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (items.isNotEmpty) ...[
                              const Text(
                                'Items',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                              const SizedBox(height: 8),
                              ...items.map((item) {
                                final i = item as Map;
                                final p = i['products'] as Map? ?? {};
                                final name = p['name'] ?? 'Unknown Item';
                                final qty =
                                    (i['quantity'] as num?)?.toInt() ?? 0;
                                final price =
                                    (i['price_per_unit'] as num?)?.toDouble() ??
                                    0.0;
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '$qty x $name',
                                          style: const TextStyle(fontSize: 13),
                                        ),
                                      ),
                                      Text(
                                        '₹${(qty * price).toStringAsFixed(0)}',
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                              const Divider(height: 24),
                            ],
                            if (proofUrl != null) ...[
                              TextButton.icon(
                                onPressed: () => _openUrl(proofUrl),
                                icon: const Icon(Icons.attachment),
                                label: const Text('View Payment Proof'),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
