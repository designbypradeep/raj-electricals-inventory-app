import 'package:flutter/material.dart';
import '../widgets/page_header.dart';
import '../services/supabase_service.dart';
import '../models/supabase_models.dart' as models;
import '../services/connectivity_service.dart';

class ArchivedProductsPage extends StatefulWidget {
  const ArchivedProductsPage({super.key});

  @override
  State<ArchivedProductsPage> createState() => _ArchivedProductsPageState();
}

class _ArchivedProductsPageState extends State<ArchivedProductsPage> {
  bool _isLoading = true;
  List<models.Product> _products = [];

  String _searchTerm = '';
  String _selectedCategory = '';

  @override
  void initState() {
    super.initState();
    _loadArchivedProducts();
  }

  Future<void> _loadArchivedProducts() async {
    setState(() => _isLoading = true);
    final items = await SupabaseService.getArchivedProducts();
    setState(() {
      _products = items;
      _isLoading = false;
    });
  }

  List<String> get _categories {
    final set = <String>{};
    for (final p in _products) {
      if ((p.category ?? '').isNotEmpty) set.add(p.category!);
    }
    return set.toList()..sort();
  }

  List<models.Product> get _filteredProducts {
    return _products.where((p) {
      final q = _searchTerm.toLowerCase();
      final matchesSearch =
          _searchTerm.isEmpty ||
          p.name.toLowerCase().contains(q) ||
          (p.brand?.toLowerCase().contains(q) ?? false) ||
          (p.category?.toLowerCase().contains(q) ?? false) ||
          (p.sizeOrSpec?.toLowerCase().contains(q) ?? false);
      final matchesCategory =
          _selectedCategory.isEmpty || p.category == _selectedCategory;
      return matchesSearch && matchesCategory;
    }).toList();
  }

  void _clearFilters() {
    setState(() {
      _searchTerm = '';
      _selectedCategory = '';
    });
  }

  Future<void> _restoreProduct(models.Product p) async {
    if (!ConnectivityService().isOnline.value) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: const [
              Icon(Icons.wifi_off, color: Colors.white),
              SizedBox(width: 8),
              Text('You are offline. Cannot restore product.'),
            ],
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    final ok = await SupabaseService.restoreProductById(p.id!);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok ? 'Product restored successfully' : 'Failed to restore product',
        ),
        backgroundColor: ok
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.error,
      ),
    );
    if (ok) _loadArchivedProducts();
  }

  Future<void> _deleteProduct(models.Product p) async {
    if (!ConnectivityService().isOnline.value) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: const [
              Icon(Icons.wifi_off, color: Colors.white),
              SizedBox(width: 8),
              Text('You are offline. Cannot delete product.'),
            ],
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('⚠️ Permanent Delete'),
        content: Text(
          'This will permanently delete "${p.name}" from the database. This action CANNOT be undone. Are you sure?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('Delete Forever'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final ok = await SupabaseService.permanentlyDeleteProductById(p.id!);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok ? 'Product deleted permanently' : 'Failed to delete product',
        ),
        backgroundColor: ok
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.error,
      ),
    );
    if (ok) _loadArchivedProducts();
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
                title: 'Archived Products',
                description:
                    'Products that have been archived due to transaction history',
                icon: '📦',
                showBackButton: true,
                backLabel: 'Back to Catalog',
                breadcrumbs: [
                  PageHeaderBreadcrumb(label: 'Dashboard', icon: '🏠'),
                  PageHeaderBreadcrumb(label: 'Product Catalog', icon: '📦'),
                  PageHeaderBreadcrumb(
                    label: 'Archived Products',
                    icon: '🗃️',
                    current: true,
                  ),
                ],
                stats: [
                  PageHeaderStat(
                    label: 'Archived Products',
                    value: '${_products.length}',
                    description: 'Total archived products',
                  ),
                  PageHeaderStat(
                    label: 'Status',
                    value: 'Archived',
                    description: 'Products with transaction history',
                  ),
                ],
                actions: [
                  PageHeaderAction(
                    label: 'Active Catalog',
                    shortLabel: 'Active',
                    icon: Icons.inventory_2,
                    color: Theme.of(context).colorScheme.primary,
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
                    // Controls Card
                    _buildControlsCard(context),
                    const SizedBox(height: 16),
                    // Content
                    _buildContent(context),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControlsCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1),
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search (responsive)
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 560;
              final searchField = Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    labelText: 'Search Archived Products',
                    hintText: 'Search by name, brand, category, or size...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchTerm.isNotEmpty
                        ? IconButton(
                            onPressed: () => setState(() => _searchTerm = ''),
                            icon: const Icon(Icons.close),
                          )
                        : null,
                    filled: true,
                    fillColor: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    border: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: Theme.of(context).colorScheme.primary,
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onChanged: (v) => setState(() => _searchTerm = v),
                ),
              );
              final clearBtn = OutlinedButton.icon(
                onPressed: _clearFilters,
                icon: const Icon(Icons.filter_alt_off),
                label: const Text('Clear Filters'),
              );
              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [searchField]),
                    const SizedBox(height: 8),
                    clearBtn,
                  ],
                );
              } else {
                return Row(
                  children: [searchField, const SizedBox(width: 12), clearBtn],
                );
              }
            },
          ),
          const SizedBox(height: 12),
          // Filters row (responsive)
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 560;
              final category = Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _selectedCategory.isEmpty
                      ? null
                      : _selectedCategory,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Filter by Category',
                    labelStyle: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    filled: true,
                    fillColor: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    border: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: Theme.of(context).colorScheme.primary,
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('All Categories'),
                    ),
                    ..._categories.map(
                      (c) => DropdownMenuItem(value: c, child: Text(c)),
                    ),
                  ].toList(),
                  onChanged: (v) => setState(() => _selectedCategory = v ?? ''),
                ),
              );
              final countBox = Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(
                      context,
                    ).colorScheme.outline.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.tertiary,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${_filteredProducts.length} archived products found',
                      style: TextStyle(
                        color: Theme.of(
                          context,
                        ).textTheme.bodyMedium?.color?.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              );
              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [category]),
                    const SizedBox(height: 8),
                    countBox,
                  ],
                );
              } else {
                return Row(
                  children: [category, const SizedBox(width: 12), countBox],
                );
              }
            },
          ),

          // Active filters chips
          if (_searchTerm.isNotEmpty || _selectedCategory.isNotEmpty) ...[
            const SizedBox(height: 12),
            Divider(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 8),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                const Text('Active filters:'),
                if (_searchTerm.isNotEmpty)
                  _filterChip(
                    label: 'Search: "$_searchTerm"',
                    color: Theme.of(context).colorScheme.primary,
                    onClear: () => setState(() => _searchTerm = ''),
                  ),
                if (_selectedCategory.isNotEmpty)
                  _filterChip(
                    label: 'Category: $_selectedCategory',
                    color: Theme.of(context).colorScheme.tertiary,
                    onClear: () => setState(() => _selectedCategory = ''),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _filterChip({
    required String label,
    required Color color,
    required VoidCallback onClear,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: color)),
          const SizedBox(width: 6),
          InkWell(
            onTap: onClear,
            child: Icon(Icons.close, size: 14, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (_isLoading) {
      return Container(
        margin: const EdgeInsets.only(top: 24),
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

    final items = _filteredProducts;
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: Theme.of(context).dividerColor.withValues(alpha: 0.4),
                ),
              ),
              child: Icon(
                Icons.archive_outlined,
                size: 40,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'No Archived Products',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              _products.isEmpty
                  ? 'No products have been archived yet. Products are archived when they have transaction history.'
                  : 'No products match your search criteria. Try adjusting your filters.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(
                  context,
                ).textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
              ),
            ),
            if (_searchTerm.isNotEmpty || _selectedCategory.isNotEmpty) ...[
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _clearFilters,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                ),
                child: const Text('Clear Filters'),
              ),
            ],
          ],
        ),
      );
    }

    // Responsive Grid
    int cross = 1;
    double aspect = 1.05;
    final width = MediaQuery.of(context).size.width;
    if (width >= 1400) {
      cross = 4;
      aspect = 0.88;
    } else if (width >= 1100) {
      cross = 3;
      aspect = 0.9;
    } else if (width >= 800) {
      cross = 2;
      aspect = 0.95;
    }
    return GridView.count(
      crossAxisCount: cross,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: aspect,
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      children: items.map(_buildProductCard).toList(),
    );
  }

  Widget _buildProductCard(models.Product p) {
    return Container(
      padding: const EdgeInsets.all(16),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Archived badge and ID
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.tertiary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: Theme.of(
                      context,
                    ).colorScheme.tertiary.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.archive_outlined,
                      size: 14,
                      color: Theme.of(context).colorScheme.tertiary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Archived',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.tertiary,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'ID: ${p.id ?? '-'}',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Image
          if ((p.productImageUrl ?? '').isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                children: [
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Image.network(
                      p.productImageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        child: Center(
                          child: Icon(
                            Icons.inventory_2,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [Color(0x33000000), Color(0x00000000)],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Container(
              height: 120,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).dividerColor.withValues(alpha: 0.4),
                ),
              ),
              child: Center(
                child: Icon(
                  Icons.inventory_2,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),

          const SizedBox(height: 12),
          // Product details
          Text(
            p.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          if ((p.brand ?? '').isNotEmpty) _metaRow('BRAND', p.brand!),
          if ((p.category ?? '').isNotEmpty) _metaRow('CATEGORY', p.category!),
          if ((p.sizeOrSpec ?? '').isNotEmpty) _metaRow('SIZE', p.sizeOrSpec!),

          const SizedBox(height: 8),
          Divider(color: Theme.of(context).dividerColor.withValues(alpha: 0.6)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if ((p.sellingPrice ?? 0) > 0)
                Text(
                  '₹${p.sellingPrice!.toStringAsFixed(0)}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              Row(
                children: [
                  Text(
                    'Stock:',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${p.currentStock}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: p.id == null ? null : () => _restoreProduct(p),
                  icon: const Icon(Icons.restore, size: 18),
                  label: const Text('Restore'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: p.id == null ? null : () => _deleteProduct(p),
                  icon: const Icon(Icons.delete_forever, size: 18),
                  label: const Text('Delete Forever'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                    foregroundColor: Theme.of(context).colorScheme.onError,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Created: ${p.createdAt != null ? '${p.createdAt!.day}/${p.createdAt!.month}/${p.createdAt!.year}' : 'N/A'}',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.color?.withValues(alpha: 0.6),
                ),
              ),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.tertiary,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metaRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Theme.of(
                  context,
                ).textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
