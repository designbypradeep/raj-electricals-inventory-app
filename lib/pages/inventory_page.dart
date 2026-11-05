import 'package:flutter/material.dart';
import 'package:raj_electricals_inventory_app/theme/ui_tokens.dart';
import '../services/supabase_service.dart';
import '../models/supabase_models.dart' as supabase_models;
import '../models/sales_purchase_models.dart';
import '../widgets/page_header.dart';

class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key});

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  List<supabase_models.Product> _allProducts = [];
  List<supabase_models.Product> _filteredProducts = [];
  List<Purchase> _recentPurchases = [];
  List<Sale> _recentSales = [];
  bool _isLoading = true;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  // Pagination state
  int _currentPage = 1;
  int _itemsPerPage = 25;

  List<supabase_models.Product> get _paginatedProducts {
    final startIndex = (_currentPage - 1) * _itemsPerPage;
    if (startIndex >= _filteredProducts.length) {
      if (_filteredProducts.isEmpty) return [];
      return _filteredProducts.take(_itemsPerPage).toList();
    }
    final endIndex = startIndex + _itemsPerPage;
    return _filteredProducts.sublist(
      startIndex,
      endIndex > _filteredProducts.length ? _filteredProducts.length : endIndex,
    );
  }

  int get _totalPages => _filteredProducts.isEmpty
      ? 1
      : (_filteredProducts.length / _itemsPerPage).ceil();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  // Compact tablet table: fewer columns, tighter layout
  Widget _buildCompactProductTable() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double nameMaxW =
            constraints.maxWidth * 0.45; // larger share for name
        final table = DataTable(
          columnSpacing: 14,
          dataRowMinHeight: 52,
          dataRowMaxHeight: 60,
          headingRowHeight: 40,
          headingRowColor: WidgetStateProperty.all(
            Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(24),
          ),
          columns: const [
            DataColumn(label: Text('🖼️')),
            DataColumn(label: Text('Product')),
            DataColumn(label: Text('📂 Cat')),
            DataColumn(label: Text('📊 Stock')),
            DataColumn(label: Text('💰 Price'), numeric: true),
          ],
          rows: _paginatedProducts.map((product) {
            final stockColor = _getStockColor(product.currentStock);
            return DataRow(
              cells: [
                DataCell(
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: (() {
                      final cover =
                          (product.productImageUrl?.isNotEmpty ?? false)
                          ? product.productImageUrl
                          : ((product.productImages?.isNotEmpty ?? false)
                                ? product.productImages!.first
                                : null);
                      if (cover != null) {
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            cover,
                            width: 36,
                            height: 36,
                            fit: BoxFit.cover,
                            errorBuilder: (c, e, s) =>
                                const Icon(Icons.inventory_2, size: 18),
                          ),
                        );
                      }
                      return const Icon(Icons.inventory_2, size: 18);
                    })(),
                  ),
                ),
                DataCell(
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: nameMaxW),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          product.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        if (product.sizeOrSpec != null)
                          Text(
                            product.sizeOrSpec!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
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
                ),
                DataCell(
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 120),
                    child: product.category != null
                        ? Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(
                                  UITokens.radius,
                                ),
                              ),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  product.category!,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onPrimaryContainer,
                                  ),
                                ),
                              ),
                            ),
                          )
                        : const Text('-'),
                  ),
                ),
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: stockColor.withAlpha(30),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${product.currentStock}',
                          style: TextStyle(
                            color: stockColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      _buildStockStatusChip(product.currentStock),
                    ],
                  ),
                ),
                DataCell(
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      '₹${product.sellingPrice?.toStringAsFixed(2) ?? '0.00'}',
                    ),
                  ),
                ),
              ],
            );
          }).toList(),
        );
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: table,
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      // Load products with stock > 0
      final allProducts = await SupabaseService.getProducts();
      final productsWithStock = allProducts
          .where((p) => p.currentStock > 0)
          .toList();

      // Load recent purchases and sales for stock movements
      final purchases = await SupabaseService.getPurchases();
      final sales = await SupabaseService.getSales();

      setState(() {
        _allProducts = productsWithStock;
        _filteredProducts = productsWithStock;
        _currentPage = 1;
        _recentPurchases = purchases.take(5).toList();
        _recentSales = sales.take(5).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading inventory: $e')));
      }
    }
  }

  void _filterProducts(String query) {
    setState(() {
      _searchQuery = query;
      _currentPage = 1;
      if (query.isEmpty) {
        _filteredProducts = _allProducts;
      } else {
        _filteredProducts = _allProducts.where((product) {
          return product.name.toLowerCase().contains(query.toLowerCase()) ||
              (product.brand?.toLowerCase().contains(query.toLowerCase()) ??
                  false) ||
              (product.category?.toLowerCase().contains(query.toLowerCase()) ??
                  false) ||
              (product.itemCode?.toLowerCase().contains(query.toLowerCase()) ??
                  false);
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Theme.of(context).colorScheme.primary.withAlpha(20),
              Theme.of(context).colorScheme.surface,
            ],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  _buildPageHeader(),
                  const SizedBox(height: 24),
                  _buildSearchBar(),
                  const SizedBox(height: 24),
                  _isLoading
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(40.0),
                            child: CircularProgressIndicator(),
                          ),
                        )
                      : _buildContent(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPageHeader() {
    final totalValue = _allProducts.fold<double>(
      0.0,
      (sum, p) => sum + (p.currentStock * (p.sellingPrice ?? 0)),
    );

    return PageHeader(
      title: 'Live Inventory',
      description: 'Real-time stock levels and product information',
      icon: '📦',
      showBackButton: true,
      backLabel: 'Back to Dashboard',
      onBackPressed: () => Navigator.pop(context),
      breadcrumbs: [
        PageHeaderBreadcrumb(label: 'Dashboard', icon: '🏠'),
        PageHeaderBreadcrumb(
          label: 'Live Inventory',
          icon: '📦',
          current: true,
        ),
      ],
      stats: [
        PageHeaderStat(
          label: 'Products in Stock',
          value: '${_allProducts.length} items',
          description: 'Total products available',
        ),
        PageHeaderStat(
          label: 'Total Value',
          value: '₹${totalValue.toStringAsFixed(0)}',
          description: 'Current inventory value',
        ),
      ],
      actions: [
        PageHeaderAction(
          label: 'Manage Catalog',
          shortLabel: 'Catalog',
          icon: Icons.list_alt,
          color: Theme.of(context).colorScheme.tertiary,
          onPressed: () => Navigator.pushNamed(context, '/catalog'),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    final isMobile = MediaQuery.of(context).size.width < 480;
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      child: Card(
        elevation: 1,
        child: Padding(
          padding: EdgeInsets.all(isMobile ? 16.0 : 20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withAlpha(25),
                      border: Border.all(
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withAlpha(50),
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.search,
                      size: 16,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '🔍 Search Inventory',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: isMobile ? 12 : 16),
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outline.withAlpha(50),
                  ),
                ),
                child: TextField(
                  controller: _searchController,
                  onChanged: _filterProducts,
                  decoration: InputDecoration(
                    hintText: 'Search by name, brand, category...',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: isMobile ? 10 : 12,
                    ),
                    prefixIcon: Icon(
                      Icons.search,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            onPressed: () {
                              _searchController.clear();
                              _filterProducts('');
                            },
                            icon: const Icon(Icons.clear),
                          )
                        : null,
                  ),
                ),
              ),
              if (_searchQuery.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest.withAlpha(50),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).colorScheme.outline.withAlpha(30),
                    ),
                  ),
                  child: RichText(
                    text: TextSpan(
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                      children: [
                        const TextSpan(text: '📊 Showing '),
                        TextSpan(
                          text: _filteredProducts.length.toString(),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const TextSpan(text: ' of '),
                        TextSpan(
                          text: _allProducts.length.toString(),
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const TextSpan(text: ' products'),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_filteredProducts.isEmpty) {
      return _buildEmptyState();
    }

    return Column(
      children: [
        _buildDataContainer(),
        const SizedBox(height: 24),
        _buildRecentMovementsSection(),
        const SizedBox(height: 24),
        _buildInfoSection(),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.inventory_2_outlined,
                size: 64,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text(
                _searchQuery.isEmpty
                    ? 'No products with stock found'
                    : 'No products match your search',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                _searchQuery.isEmpty
                    ? 'Add some products to your inventory to get started.'
                    : 'Try adjusting your search terms.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => Navigator.pushNamed(context, '/add-product'),
                icon: const Icon(Icons.add),
                label: const Text('Add Product'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDataContainer() {
    return Card(
      elevation: 1,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest.withAlpha(50),
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).colorScheme.outline.withAlpha(30),
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '📦 Current Stock',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Live inventory levels',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _filteredProducts.length.toString(),
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                    ),
                    Text(
                      'PRODUCTS',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              if (w > 1024) {
                return _buildDesktopProductTable();
              } else if (w > 600) {
                return _buildCompactProductTable();
              } else {
                return _buildMobileProductCards();
              }
            },
          ),
          if (_filteredProducts.isNotEmpty) _buildPaginationControls(),
        ],
      ),
    );
  }

  Widget _buildDesktopProductTable() {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Limit wide columns to prevent table overflow and horizontal scroll
        final double nameMaxW = constraints.maxWidth * 0.34; // ~34% for name
        const double brandMaxW = 140;
        const double specMaxW = 160;
        final table = DataTable(
          columnSpacing: 20,
          dataRowMinHeight: 56,
          dataRowMaxHeight: 64,
          headingRowHeight: 44,
          headingRowColor: WidgetStateProperty.all(
            Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(30),
          ),
          columns: const [
            DataColumn(label: Text('🖼️ Image')),
            DataColumn(label: Text('📦 Product Name')),
            DataColumn(label: Text('🏷️ Brand')),
            DataColumn(label: Text('📂 Category')),
            DataColumn(label: Text('📏 Spec/Size')),
            DataColumn(label: Text('📊 Stock Level')),
            DataColumn(label: Text('💰 Price'), numeric: true),
          ],
          rows: _paginatedProducts.isEmpty
              ? [
                  DataRow(
                    cells: [
                      const DataCell(
                        Center(
                          child: Text('📦', style: TextStyle(fontSize: 24)),
                        ),
                      ),
                      DataCell(
                        Center(
                          child: Text(
                            _searchController.text.isEmpty
                                ? 'No products in stock'
                                : 'No products match your search',
                            style: const TextStyle(
                              fontStyle: FontStyle.italic,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                      ),
                      const DataCell(Text('-')),
                      const DataCell(Text('-')),
                      const DataCell(Text('-')),
                      const DataCell(Text('-')),
                      const DataCell(Text('-')),
                    ],
                  ),
                ]
              : _paginatedProducts.map((product) {
                  final stockColor = _getStockColor(product.currentStock);

                  return DataRow(
                    cells: [
                      DataCell(
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: (() {
                            final cover =
                                (product.productImageUrl?.isNotEmpty ?? false)
                                ? product.productImageUrl
                                : ((product.productImages?.isNotEmpty ?? false)
                                      ? product.productImages!.first
                                      : null);
                            if (cover != null) {
                              return ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  cover,
                                  width: 40,
                                  height: 40,
                                  fit: BoxFit.cover,
                                  loadingBuilder:
                                      (context, child, loadingProgress) {
                                        if (loadingProgress == null) {
                                          return child;
                                        }
                                        return Center(
                                          child: CircularProgressIndicator(
                                            value:
                                                loadingProgress
                                                        .expectedTotalBytes !=
                                                    null
                                                ? loadingProgress
                                                          .cumulativeBytesLoaded /
                                                      loadingProgress
                                                          .expectedTotalBytes!
                                                : null,
                                            strokeWidth: 2,
                                          ),
                                        );
                                      },
                                  errorBuilder: (context, error, stackTrace) {
                                    return const Icon(
                                      Icons.inventory_2,
                                      size: 20,
                                    );
                                  },
                                ),
                              );
                            }
                            return const Icon(Icons.inventory_2, size: 20);
                          })(),
                        ),
                      ),
                      DataCell(
                        ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: nameMaxW),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                product.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              if (product.itemCode != null &&
                                  product.itemCode!.isNotEmpty)
                                Text(
                                  'Code: ${product.itemCode}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              if (product.sizeOrSpec != null)
                                Text(
                                  product.sizeOrSpec!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
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
                      ),
                      DataCell(
                        ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: brandMaxW,
                          ),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              product.brand ?? '-',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ),
                      DataCell(
                        Align(
                          alignment: Alignment.centerLeft,
                          child: product.category != null
                              ? ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 140,
                                  ),
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primaryContainer,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        product.category!,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onPrimaryContainer,
                                        ),
                                      ),
                                    ),
                                  ),
                                )
                              : const Text('-', maxLines: 1),
                        ),
                      ),
                      DataCell(
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: specMaxW),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              product.sizeOrSpec ?? '-',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ),
                      DataCell(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ConstrainedBox(
                              constraints: const BoxConstraints(minWidth: 96),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: stockColor.withAlpha(30),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '${product.currentStock} ${product.unitTypeSingle ?? 'pcs'}',
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: stockColor,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            _buildStockStatusChip(product.currentStock),
                          ],
                        ),
                      ),
                      DataCell(
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            '₹${product.sellingPrice?.toStringAsFixed(2) ?? '0.00'}',
                          ),
                        ),
                      ),
                    ],
                  );
                }).toList(),
        );
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: table,
          ),
        );
      },
    );
  }

  Widget _buildMobileProductCards() {
    return Column(
      children: _paginatedProducts.map((product) {
        final stockColor = _getStockColor(product.currentStock);
        final totalValue = product.currentStock * (product.sellingPrice ?? 0);

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Product Image
                    Container(
                      width: 60,
                      height: 60,
                      margin: const EdgeInsets.only(right: 12),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: (() {
                        final cover =
                            (product.productImageUrl?.isNotEmpty ?? false)
                            ? product.productImageUrl
                            : ((product.productImages?.isNotEmpty ?? false)
                                  ? product.productImages!.first
                                  : null);
                        if (cover != null) {
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              cover,
                              width: 60,
                              height: 60,
                              fit: BoxFit.cover,
                              loadingBuilder:
                                  (context, child, loadingProgress) {
                                    if (loadingProgress == null) return child;
                                    return Center(
                                      child: CircularProgressIndicator(
                                        value:
                                            loadingProgress
                                                    .expectedTotalBytes !=
                                                null
                                            ? loadingProgress
                                                      .cumulativeBytesLoaded /
                                                  loadingProgress
                                                      .expectedTotalBytes!
                                            : null,
                                        strokeWidth: 2,
                                      ),
                                    );
                                  },
                              errorBuilder: (context, error, stackTrace) =>
                                  const Icon(Icons.inventory_2, size: 24),
                            ),
                          );
                        }
                        return const Icon(Icons.inventory_2, size: 24);
                      })(),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            product.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                          if (product.sizeOrSpec != null)
                            Text(
                              product.sizeOrSpec!,
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
                    _buildStockStatusChip(product.currentStock),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (product.brand != null)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.business,
                            size: 16,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Text(product.brand!),
                        ],
                      ),
                    if (product.category != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          product.category!,
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(
                              context,
                            ).colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.end,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Stock',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: stockColor.withAlpha(30),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${product.currentStock} ${product.unitTypeSingle ?? 'Piece'}',
                            style: TextStyle(
                              color: stockColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'Price',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          '₹${product.sellingPrice?.toStringAsFixed(2) ?? '0.00'}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'Total Value',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          '₹${totalValue.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildPaginationControls() {
    final startIndex = (_currentPage - 1) * _itemsPerPage;
    final startItem = _filteredProducts.isEmpty ? 0 : startIndex + 1;
    final endItem = (_currentPage * _itemsPerPage > _filteredProducts.length)
        ? _filteredProducts.length
        : _currentPage * _itemsPerPage;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(20),
        border: Border(
          top: BorderSide(
            color: Theme.of(context).colorScheme.outline.withAlpha(30),
          ),
        ),
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
                'Showing $startItem-$endItem of ${_filteredProducts.length}',
                style: TextStyle(
                  fontSize: 14,
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
                        ? () => setState(() => _currentPage = 1)
                        : null,
                    icon: const Icon(Icons.first_page),
                    tooltip: 'First page',
                  ),
                  IconButton(
                    onPressed: _currentPage > 1
                        ? () => setState(() => _currentPage--)
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
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: isCurrentPage
                              ? null
                              : () => setState(() => _currentPage = pageNum),
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
                                      ).colorScheme.outline.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Center(
                              child: Text(
                                '$pageNum',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: isCurrentPage
                                      ? Theme.of(context).colorScheme.onPrimary
                                      : Theme.of(context).colorScheme.onSurface,
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
                        ? () => setState(() => _currentPage++)
                        : null,
                    icon: const Icon(Icons.chevron_right),
                    tooltip: 'Next page',
                  ),
                  IconButton(
                    onPressed: _currentPage < _totalPages
                        ? () => setState(() => _currentPage = _totalPages)
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

  Widget _buildRecentMovementsSection() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 640;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Recent Stock Movements',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            if (isCompact) ...[
              _buildRecentPurchases(),
              const SizedBox(height: 12),
              _buildRecentSales(),
            ] else ...[
              Row(
                children: [
                  Expanded(child: _buildRecentPurchases()),
                  const SizedBox(width: 16),
                  Expanded(child: _buildRecentSales()),
                ],
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildRecentPurchases() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.add_shopping_cart, color: Colors.green, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Recent Purchases',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_recentPurchases.isEmpty)
              Text(
                'No recent purchases',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              )
            else
              ..._recentPurchases.map((purchase) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          purchase.supplierName ?? 'Unknown Supplier',
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                      Text(
                        purchase.createdAt != null
                            ? _formatDate(purchase.createdAt!)
                            : 'Unknown',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
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

  Widget _buildRecentSales() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.shopping_cart_checkout,
                  color: Colors.blue,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Recent Sales',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_recentSales.isEmpty)
              Text(
                'No recent sales',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              )
            else
              ..._recentSales.map((sale) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          sale.customerName ?? 'Walk-in Customer',
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                      Text(
                        sale.createdAt != null
                            ? _formatDate(sale.createdAt!)
                            : 'Unknown',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
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

  Widget _buildStockStatusChip(num stock) {
    final color = _getStockColor(stock);
    final status = _getStockStatus(stock);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Color _getStockColor(num stock) {
    if (stock <= 0) return Colors.red;
    if (stock <= 5) return Colors.orange;
    if (stock <= 20) return Colors.yellow.shade700;
    return Colors.green;
  }

  String _getStockStatus(num stock) {
    if (stock <= 0) return 'Out of Stock';
    if (stock <= 5) return 'Critical';
    if (stock <= 20) return 'Low Stock';
    return 'In Stock';
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date).inDays;

    if (difference == 0) return 'Today';
    if (difference == 1) return 'Yesterday';
    if (difference < 7) return '${difference}d ago';
    return '${date.day}/${date.month}';
  }

  Widget _buildInfoSection() {
    return Card(
      elevation: 1,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withAlpha(12),
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).colorScheme.primary.withAlpha(25),
                ),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withAlpha(25),
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withAlpha(50),
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Center(
                    child: Text('💡', style: TextStyle(fontSize: 18)),
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'About Live Inventory',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Understanding your stock management',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50.withAlpha(50),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.blue.shade100.withAlpha(50),
                    ),
                  ),
                  child: RichText(
                    text: TextSpan(
                      style: Theme.of(context).textTheme.bodyMedium,
                      children: [
                        TextSpan(
                          text:
                              'This page shows only products with actual stock',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        TextSpan(
                          text:
                              ' — items you\'ve purchased and received through the system.',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth > 768) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _buildStockIncreaseInfo()),
                          const SizedBox(width: 24),
                          Expanded(child: _buildStockDecreaseInfo()),
                        ],
                      );
                    } else {
                      return Column(
                        children: [
                          _buildStockIncreaseInfo(),
                          const SizedBox(height: 24),
                          _buildStockDecreaseInfo(),
                        ],
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStockIncreaseInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: Colors.green.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  '+',
                  style: TextStyle(
                    color: Colors.green.shade600,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '📈 Stock Increases From:',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.only(left: 32),
          child: Column(
            children: [
              _buildInfoItem('Purchase Page recordings'),
              _buildInfoItem('Supplier deliveries'),
              _buildInfoItem('Stock adjustments'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStockDecreaseInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: Colors.red.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  '−',
                  style: TextStyle(
                    color: Colors.red.shade600,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '📉 Stock Decreases Through:',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.only(left: 32),
          child: Column(
            children: [
              _buildInfoItem('Sales Page recordings', isDecrease: true),
              _buildInfoItem('Customer deliveries', isDecrease: true),
              _buildInfoItem('Stock corrections', isDecrease: true),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInfoItem(String text, {bool isDecrease = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: isDecrease
                  ? Colors.red.shade500
                  : Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
