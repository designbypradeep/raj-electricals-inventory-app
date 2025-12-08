import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/supabase_service.dart';

class PaymentVerificationPage extends StatefulWidget {
  const PaymentVerificationPage({super.key});

  @override
  State<PaymentVerificationPage> createState() =>
      _PaymentVerificationPageState();
}

class _PaymentVerificationPageState extends State<PaymentVerificationPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _pending = [];
  bool _loadingMore = false;
  String? _lastCreatedAt;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _load(initial: true);
    _scrollController.addListener(_onScroll);
  }

  Future<void> _load({bool initial = false}) async {
    setState(() {
      if (initial) {
        _loading = true;
      } else {
        _loadingMore = true;
      }
      _error = null;
    });
    try {
      final rows = await SupabaseService.getPendingSalesWithProof(
        limit: 50,
        createdBefore: initial ? null : _lastCreatedAt,
      );
      setState(() {
        if (initial) {
          _pending = rows;
          _loading = false;
        } else {
          _pending.addAll(rows);
          _loadingMore = false;
        }
        if (rows.isNotEmpty) {
          _lastCreatedAt = rows.last['created_at'] as String?;
        }
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
        _loadingMore = false;
      });
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

  Future<void> _markStatus(int saleId, String status) async {
    try {
      await SupabaseService.updateSaleStatus(saleId: saleId, status: status);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sale #$saleId marked $status'),
            backgroundColor: status == 'verified' ? Colors.green : Colors.red,
          ),
        );
      }
      await _load(initial: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update sale: $e'),
          backgroundColor: Colors.red,
        ),
      );
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Payment Verification'),
        actions: [
          IconButton(
            onPressed: () => _load(initial: true),
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!))
          : _pending.isEmpty
          ? const Center(child: Text('No pending payments'))
          : ListView.separated(
              controller: _scrollController,
              padding: const EdgeInsets.all(12),
              itemCount: _pending.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final row = _pending[index];
                final saleId = (row['id'] as num).toInt();
                final customer =
                    (row['customer_name'] as String?) ?? 'Walk-in Customer';
                final phone = row['customer_phone'] as String?;
                final amount = (row['total_amount'] as num?)?.toDouble() ?? 0.0;
                final createdAt = (row['created_at'] as String?) ?? '';
                final proofUrl = row['payment_proof_url'] as String?;

                return Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Sale #$saleId',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.orange.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: Colors.orange.withValues(alpha: 0.4),
                                ),
                              ),
                              child: const Text(
                                'Pending',
                                style: TextStyle(
                                  color: Colors.orange,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const Spacer(),
                            Text(
                              createdAt,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          customer,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (phone != null && phone.isNotEmpty)
                          Text(
                            'Phone: $phone',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        const SizedBox(height: 8),
                        if (proofUrl != null) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: AspectRatio(
                              aspectRatio: 16 / 9,
                              child: InkWell(
                                onTap: () => _openUrl(proofUrl),
                                child: Image.network(
                                  proofUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                    color: Theme.of(
                                      context,
                                    ).dividerColor.withOpacity(0.1),
                                    child: const Center(
                                      child: Icon(Icons.broken_image),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                        Row(
                          children: [
                            Text(
                              'Total: ₹${amount.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const Spacer(),
                            if (proofUrl != null) ...[
                              TextButton.icon(
                                onPressed: () => _openUrl(proofUrl),
                                icon: const Icon(Icons.open_in_new),
                                label: const Text('Open'),
                              ),
                              const SizedBox(width: 8),
                              TextButton.icon(
                                onPressed: () async {
                                  await Clipboard.setData(
                                    ClipboardData(text: proofUrl),
                                  );
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Proof URL copied'),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.copy),
                                label: const Text('Copy'),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () =>
                                    _markStatus(saleId, 'rejected'),
                                icon: const Icon(Icons.close),
                                label: const Text('Reject'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: () =>
                                    _markStatus(saleId, 'verified'),
                                icon: const Icon(Icons.check),
                                label: const Text('Mark Verified'),
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
}
