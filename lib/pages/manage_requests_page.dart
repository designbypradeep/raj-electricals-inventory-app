import 'package:flutter/material.dart';
import '../widgets/page_header.dart';
import '../services/supabase_service.dart';
import '../services/connectivity_service.dart';

class ManageRequestsPage extends StatefulWidget {
  const ManageRequestsPage({super.key});

  @override
  State<ManageRequestsPage> createState() => _ManageRequestsPageState();
}

class _ManageRequestsPageState extends State<ManageRequestsPage> {
  List<Map<String, dynamic>> _requests = [];
  bool _loading = false;
  String? _error;
  String _search = '';

  int get _totalRequests => _requests.length;
  int get _totalItems => _requests.fold(0, (sum, r) {
    final items = (r['request_items'] as List?) ?? const [];
    return sum + items.length;
  });
  int get _totalProducts => _requests.fold(0, (sum, r) {
    final items = (r['request_items'] as List?) ?? const [];
    final ids = items.map((it) => it['product_id']).toSet();
    return sum + ids.length;
  });

  List<Map<String, dynamic>> get _filteredRequests {
    if (_search.trim().isEmpty) return _requests;
    final q = _search.trim().toLowerCase();
    return _requests.where((r) {
      final idStr = (r['id'] ?? '').toString();
      if (idStr.contains(q)) return true;
      final items = (r['request_items'] as List?) ?? const [];
      return items.any((it) {
        final p = it['products'] as Map?;
        final name = (p?['name'] ?? '').toString().toLowerCase();
        final brand = (p?['brand'] ?? '').toString().toLowerCase();
        return name.contains(q) || brand.contains(q);
      });
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await SupabaseService.getItemRequests();
      setState(() {
        _requests = data;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load requests';
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              PageHeader(
                title: 'Manage Requests',
                description: 'View, edit, and share saved dealer requests',
                icon: '🗂️',
                showBackButton: true,
                onBackPressed: () => Navigator.pop(context),
                stats: [
                  PageHeaderStat(
                    label: 'Total Requests',
                    value: '$_totalRequests',
                    description: 'Saved in this device',
                  ),
                  PageHeaderStat(
                    label: 'Items & Products',
                    value: '$_totalItems items • $_totalProducts products',
                    description: 'Across all requests',
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).dividerColor.withValues(alpha: 0.2),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Theme.of(
                          context,
                        ).shadowColor.withValues(alpha: 0.05),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header row with icon, title and Clear All
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.primary.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.settings,
                              color: Theme.of(context).colorScheme.primary,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Request Management',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ),
                          if (_totalRequests > 0)
                            ElevatedButton.icon(
                              onPressed: _confirmClearAll,
                              icon: const Icon(Icons.delete),
                              label: const Text('Clear All'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Theme.of(
                                  context,
                                ).colorScheme.error,
                                foregroundColor: Theme.of(
                                  context,
                                ).colorScheme.onError,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Search field
                      TextField(
                        decoration: InputDecoration(
                          hintText: 'Search by Request ID... ',
                          prefixIcon: Icon(
                            Icons.search,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                          filled: true,
                          fillColor: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: Theme.of(context).dividerColor,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: Theme.of(context).dividerColor,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: Theme.of(context).colorScheme.primary,
                              width: 2,
                            ),
                          ),
                          contentPadding: const EdgeInsets.all(14),
                        ),
                        onChanged: (v) => setState(() => _search = v),
                      ),

                      const SizedBox(height: 16),

                      if (_loading)
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation(
                                Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                        )
                      else if (_error != null)
                        Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontWeight: FontWeight.w600,
                          ),
                        )
                      else if (_filteredRequests.isEmpty)
                        Text(
                          'No saved requests yet. Create a request and save it to manage here.',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        )
                      else
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _filteredRequests.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final r = _filteredRequests[index];
                            final items =
                                (r['request_items'] as List?) ?? const [];
                            final createdAt = DateTime.tryParse(
                              (r['created_at'] ?? '').toString(),
                            );
                            return Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Theme.of(context).cardColor,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Theme.of(
                                    context,
                                  ).dividerColor.withValues(alpha: 0.2),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  LayoutBuilder(
                                    builder: (context, constraints) {
                                      final isNarrow =
                                          constraints.maxWidth < 360;
                                      if (isNarrow) {
                                        return Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    'Request #${r['id']}',
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: Theme.of(
                                                        context,
                                                      ).colorScheme.onSurface,
                                                    ),
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                if (createdAt != null)
                                                  Text(
                                                    '• ${createdAt.toLocal().toString().split('.').first}',
                                                    style: TextStyle(
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .onSurfaceVariant,
                                                      fontSize: 12,
                                                    ),
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                              ],
                                            ),
                                            const SizedBox(height: 6),
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    '${items.length} items • ${items.map((e) => e['product_id']).toSet().length} products',
                                                    style: TextStyle(
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .onSurfaceVariant,
                                                    ),
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                IconButton(
                                                  tooltip: 'Delete request',
                                                  onPressed: () =>
                                                      _confirmDeleteRequest(
                                                        r['id'] as int,
                                                      ),
                                                  style: IconButton.styleFrom(
                                                    backgroundColor:
                                                        Theme.of(context)
                                                            .colorScheme
                                                            .error
                                                            .withValues(
                                                              alpha: 0.10,
                                                            ),
                                                  ),
                                                  icon: Icon(
                                                    Icons.delete,
                                                    color: Theme.of(
                                                      context,
                                                    ).colorScheme.error,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        );
                                      }
                                      // Wide layout
                                      return Row(
                                        children: [
                                          Expanded(
                                            child: Row(
                                              children: [
                                                Text(
                                                  'Request #${r['id']}',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w700,
                                                    color: Theme.of(
                                                      context,
                                                    ).colorScheme.onSurface,
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                if (createdAt != null)
                                                  Flexible(
                                                    child: Text(
                                                      '• ${createdAt.toLocal().toString().split('.').first}',
                                                      style: TextStyle(
                                                        color: Theme.of(context)
                                                            .colorScheme
                                                            .onSurfaceVariant,
                                                        fontSize: 12,
                                                      ),
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                          Flexible(
                                            child: Text(
                                              '${items.length} items • ${items.map((e) => e['product_id']).toSet().length} products',
                                              style: TextStyle(
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.onSurfaceVariant,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          IconButton(
                                            tooltip: 'Delete request',
                                            onPressed: () =>
                                                _confirmDeleteRequest(
                                                  r['id'] as int,
                                                ),
                                            style: IconButton.styleFrom(
                                              backgroundColor: Theme.of(context)
                                                  .colorScheme
                                                  .error
                                                  .withValues(alpha: 0.10),
                                            ),
                                            icon: Icon(
                                              Icons.delete,
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.error,
                                            ),
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                  const SizedBox(height: 12),
                                  if (items.isNotEmpty)
                                    ListView.separated(
                                      shrinkWrap: true,
                                      physics:
                                          const NeverScrollableScrollPhysics(),
                                      itemCount: items.length,
                                      separatorBuilder: (_, __) =>
                                          const SizedBox(height: 8),
                                      itemBuilder: (_, i) {
                                        final it = items[i] as Map;
                                        final p =
                                            (it['products'] as Map?) ??
                                            const {};
                                        return Row(
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    (p['name'] ?? 'Unnamed')
                                                        .toString(),
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: Theme.of(
                                                        context,
                                                      ).colorScheme.onSurface,
                                                    ),
                                                  ),
                                                  Text(
                                                    'Brand: ${(p['brand'] ?? '-').toString()} • Qty: ${it['quantity']} • ₹${(it['expected_price'] ?? 0).toString()}',
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .onSurfaceVariant,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            IconButton(
                                              tooltip: 'Remove item',
                                              onPressed: () =>
                                                  _deleteRequestItem(
                                                    it['id'] as int,
                                                  ),
                                              icon: Icon(
                                                Icons.close,
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.error,
                                              ),
                                            ),
                                          ],
                                        );
                                      },
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmClearAll() {
    if (!ConnectivityService().isOnline.value) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: const [
                Icon(Icons.wifi_off, color: Colors.white),
                SizedBox(width: 8),
                Text('You are offline. Cannot clear requests.'),
              ],
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Clear All Requests'),
        content: Text(
          'This will permanently delete all $_totalRequests requests and $_totalItems items. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              setState(() => _loading = true);
              final ok = await SupabaseService.clearAllRequests();
              if (ok) {
                setState(() => _requests = []);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('All requests cleared')),
                  );
                }
              } else {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Failed to clear requests')),
                  );
                }
              }
              if (mounted) setState(() => _loading = false);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteRequest(int requestId) {
    if (!ConnectivityService().isOnline.value) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: const [
                Icon(Icons.wifi_off, color: Colors.white),
                SizedBox(width: 8),
                Text('You are offline. Cannot delete request.'),
              ],
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Request'),
        content: const Text(
          'Are you sure you want to delete this request? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              setState(() => _loading = true);
              final ok = await SupabaseService.deleteRequest(requestId);
              if (ok) {
                setState(
                  () => _requests.removeWhere((r) => r['id'] == requestId),
                );
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Request deleted')),
                  );
                }
              } else {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Failed to delete request')),
                  );
                }
              }
              if (mounted) setState(() => _loading = false);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteRequestItem(int itemId) async {
    if (!ConnectivityService().isOnline.value) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: const [
                Icon(Icons.wifi_off, color: Colors.white),
                SizedBox(width: 8),
                Text('You are offline. Cannot remove item.'),
              ],
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }
    final ok = await SupabaseService.deleteRequestItem(itemId);
    if (ok) {
      setState(() {
        for (final r in _requests) {
          final items = (r['request_items'] as List?) ?? [];
          final idx = items.indexWhere((it) => (it as Map)['id'] == itemId);
          if (idx != -1) {
            items.removeAt(idx);
            break;
          }
        }
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Item removed')));
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Failed to remove item')));
      }
    }
  }
}

// Removed old placeholder record model; using raw maps from Supabase for flexibility.
