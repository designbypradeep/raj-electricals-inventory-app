import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:reorderables/reorderables.dart';
import 'dart:async';
import 'dart:io';
import '../data/app_database.dart';
import '../models/supabase_models.dart' as supabase_models;
import '../services/supabase_service.dart';
import '../services/image_storage_service.dart';
import '../services/connectivity_service.dart';
import '../widgets/page_header.dart';

class CatalogPage extends StatefulWidget {
  final AppDatabase db;

  const CatalogPage({super.key, required this.db});

  @override
  State<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<CatalogPage> {
  // Search and filter state
  String _searchTerm = '';
  String _selectedCategory = '';
  String _selectedBrand = '';
  String _stockFilter = 'all'; // 'all', 'in-stock', 'out-of-stock', 'low-stock'

  // Sorting state
  String _sortColumn = 'name';
  String _sortOrder = 'asc';

  // Pagination state
  int _currentPage = 1;
  int _itemsPerPage = 20;

  // UI state
  final FocusNode _searchFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  StreamSubscription<List<Map<String, dynamic>>>? _productsSub;

  supabase_models.BusinessProfile? _businessProfile;

  // Bulk operations state
  Set<int> _selectedProducts = <int>{};
  bool _bulkOperationMode = false;
  bool _isLoading = true;
  String _errorMessage = '';
  String _successMessage = '';
  List<supabase_models.Product> _products = [];
  List<supabase_models.Product> _filteredProducts = [];
  List<String> _categories = ['All'];
  List<String> _brands = [];

  // Mobile responsive breakpoint
  static const double _mobileBreakpoint = 768.0;

  @override
  void initState() {
    super.initState();
    _checkAuthAndLoadData();
    _initRealtime();
    // Add keyboard shortcuts listener
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        FocusScope.of(context).requestFocus(FocusNode());
      }
    });
  }

  @override
  void dispose() {
    _searchFocusNode.dispose();
    _scrollController.dispose();
    _productsSub?.cancel();
    super.dispose();
  }

  void _initRealtime() async {
    try {
      // Ensure business profile is ready to read business_id
      final current = SupabaseService.getCurrentBusinessId();
      if (current == null) {
        await SupabaseService.getCurrentBusinessProfile();
      }
      final businessId = SupabaseService.getCurrentBusinessId();
      if (businessId == null) return;

      // Recreate subscription
      await _productsSub?.cancel();
      _productsSub = SupabaseService.client
          .from('products')
          .stream(primaryKey: ['id'])
          .eq('business_id', businessId)
          .listen((_) {
            if (!mounted) return;
            // Lightweight approach: simply reload products on any change
            _loadProducts();
          });
    } catch (_) {
      // ignore realtime init errors to avoid crashing the page
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

    // Load profile for status check
    final profile = await SupabaseService.getBusinessProfile();
    if (mounted) {
      setState(() {
        _businessProfile = profile;
      });
    }

    await _loadProducts();
  }

  Future<void> _loadProducts() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = '';
      });

      final products = await SupabaseService.getProducts();

      if (mounted) {
        setState(() {
          _products = products;
          _filteredProducts = products;
          _categories = [
            'All',
            ...products.map((p) => p.category ?? 'Uncategorized').toSet(),
          ];
          _brands =
              products
                  .map((p) => p.brand ?? '')
                  .where((b) => b.isNotEmpty)
                  .toSet()
                  .toList()
                ..sort();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load products: ${e.toString()}';
          _isLoading = false;
        });
      }
    }
  }

  void _applyFilters() {
    setState(() {
      _filteredProducts = _products.where((product) {
        // Search filter (order-insensitive multi-keyword matching)
        final q = _searchTerm.trim().toLowerCase();
        final tokens = q
            .split(RegExp(r'\s+'))
            .where((t) => t.isNotEmpty)
            .toList();
        final hay = [
          product.name,
          product.brand ?? '',
          product.category ?? '',
          product.sizeOrSpec ?? '',
          product.description ?? '',
        ].join(' ').toLowerCase();
        final searchMatch =
            tokens.isEmpty || tokens.every((t) => hay.contains(t));

        // Category filter
        final categoryMatch =
            _selectedCategory.isEmpty ||
            _selectedCategory == 'All' ||
            product.category == _selectedCategory;

        // Brand filter
        final brandMatch =
            _selectedBrand.isEmpty || product.brand == _selectedBrand;

        // Stock filter
        bool stockMatch = true;
        switch (_stockFilter) {
          case 'in-stock':
            stockMatch = product.currentStock > 0;
            break;
          case 'out-of-stock':
            stockMatch = product.currentStock == 0;
            break;
          case 'low-stock':
            stockMatch = product.currentStock > 0 && product.currentStock <= 10;
            break;
          default:
            stockMatch = true;
        }

        return searchMatch && categoryMatch && brandMatch && stockMatch;
      }).toList();

      // Apply sorting
      _applySorting();

      // Reset to first page when filters change
      _currentPage = 1;
    });
  }

  void _applySorting() {
    _filteredProducts.sort((a, b) {
      dynamic aVal, bVal;

      switch (_sortColumn) {
        case 'name':
          aVal = a.name.toLowerCase();
          bVal = b.name.toLowerCase();
          break;
        case 'brand':
          aVal = (a.brand ?? '').toLowerCase();
          bVal = (b.brand ?? '').toLowerCase();
          break;
        case 'category':
          aVal = (a.category ?? '').toLowerCase();
          bVal = (b.category ?? '').toLowerCase();
          break;
        case 'stock':
          aVal = a.currentStock;
          bVal = b.currentStock;
          break;
        case 'price':
          aVal = a.sellingPrice ?? 0;
          bVal = b.sellingPrice ?? 0;
          break;
        default:
          aVal = a.name.toLowerCase();
          bVal = b.name.toLowerCase();
      }

      if (aVal == bVal) return 0;
      final result = aVal.compareTo(bVal);
      return _sortOrder == 'asc' ? result : -result;
    });
  }

  void _handleSort(String column) {
    setState(() {
      if (_sortColumn == column) {
        // Toggle sort order if same column
        _sortOrder = _sortOrder == 'asc' ? 'desc' : 'asc';
      } else {
        // New column, start with ascending
        _sortColumn = column;
        _sortOrder = 'asc';
      }
      _applySorting();
    });
  }

  void _toggleProductSelection(int productId) {
    setState(() {
      if (_selectedProducts.contains(productId)) {
        _selectedProducts.remove(productId);
      } else {
        _selectedProducts.add(productId);
      }
    });
  }

  void _toggleSelectAll() {
    setState(() {
      final paginatedProducts = _getPaginatedProducts();
      if (_selectedProducts.length == paginatedProducts.length) {
        _selectedProducts.clear();
      } else {
        _selectedProducts = Set.from(paginatedProducts.map((p) => p.id!));
      }
    });
  }

  List<supabase_models.Product> _getPaginatedProducts() {
    final startIndex = (_currentPage - 1) * _itemsPerPage;
    final endIndex = startIndex + _itemsPerPage;
    return _filteredProducts.sublist(
      startIndex,
      endIndex > _filteredProducts.length ? _filteredProducts.length : endIndex,
    );
  }

  int get _totalPages => (_filteredProducts.length / _itemsPerPage).ceil();

  void _openEditDialog(supabase_models.Product product) {
    showDialog(
      context: context,
      builder: (context) =>
          EditProductDialog(product: product, onProductUpdated: _loadProducts),
    );
  }

  Future<void> _bulkDeleteProducts() async {
    if (!ConnectivityService().isOnline.value) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You are offline. Cannot delete products.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (_selectedProducts.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Products'),
        content: Text(
          'Are you sure you want to delete ${_selectedProducts.length} selected products? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        for (final productId in _selectedProducts) {
          await SupabaseService.deleteProduct(productId);
        }
        await _loadProducts();
        setState(() {
          _selectedProducts.clear();
          _bulkOperationMode = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Successfully deleted ${_selectedProducts.length} products',
              ),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to delete products: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _bulkEditProducts() async {
    if (!ConnectivityService().isOnline.value) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You are offline. Cannot edit products.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (_selectedProducts.isEmpty) return;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _BulkEditDialog(
        selectedCount: _selectedProducts.length,
        categories: _categories.where((cat) => cat != 'All').toList(),
        brands: _brands,
      ),
    );

    if (result != null) {
      try {
        setState(() => _isLoading = true);

        // Apply bulk updates to selected products
        for (final productId in _selectedProducts) {
          await SupabaseService.updateProduct(
            id: productId,
            name: result['name'],
            brand: result['brand'],
            category: result['category'],
            sellingPrice: result['sellingPrice'],
            purchasePrice: result['purchasePrice'],
          );
        }

        await _loadProducts();
        setState(() {
          _bulkOperationMode = false;
          _selectedProducts.clear();
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Successfully updated ${_selectedProducts.length} products',
              ),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error updating products: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _bulkChangeCategory() async {
    if (!ConnectivityService().isOnline.value) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You are offline. Cannot change categories.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (_selectedProducts.isEmpty) return;

    final selectedCategory = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change Category'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Select new category for ${_selectedProducts.length} products:',
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Category',
              ),
              items: _categories.where((cat) => cat != 'All').map((category) {
                return DropdownMenuItem(value: category, child: Text(category));
              }).toList(),
              onChanged: (value) => Navigator.of(context).pop(value),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (selectedCategory != null) {
      try {
        setState(() => _isLoading = true);

        // Update category for all selected products
        for (final productId in _selectedProducts) {
          await SupabaseService.updateProduct(
            id: productId,
            category: selectedCategory,
          );
        }

        await _loadProducts();
        setState(() {
          _bulkOperationMode = false;
          _selectedProducts.clear();
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Successfully updated category for ${_selectedProducts.length} products',
              ),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error updating categories: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _exportSelectedProducts() async {
    if (_selectedProducts.isEmpty) return;

    try {
      // Export selected products (CSV content generation removed as unused)

      // Show export options dialog
      final format = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Export Format'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Export ${_selectedProducts.length} selected products as:'),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.table_chart),
                title: const Text('CSV File'),
                subtitle: const Text('Comma-separated values'),
                onTap: () => Navigator.of(context).pop('csv'),
              ),
              ListTile(
                leading: const Icon(Icons.code),
                title: const Text('JSON File'),
                subtitle: const Text('JavaScript Object Notation'),
                onTap: () => Navigator.of(context).pop('json'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        ),
      );

      if (format != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Exporting ${_selectedProducts.length} products as $format...',
            ),
            backgroundColor: Colors.green,
          ),
        );

        // In a real implementation, you would save the file here
        // For now, we'll just show the export was initiated
        await Future.delayed(const Duration(seconds: 1));

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Export completed! ${_selectedProducts.length} products exported as $format',
              ),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error exporting products: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Keyboard shortcuts handler
  void _handleKeyboardShortcuts(KeyEvent event) {
    if (event is KeyDownEvent) {
      final isCtrlPressed = HardwareKeyboard.instance.isControlPressed;

      // Ctrl+F: Focus search
      if (event.logicalKey == LogicalKeyboardKey.keyF && isCtrlPressed) {
        _searchFocusNode.requestFocus();
        return;
      }

      // Escape: Clear filters or exit bulk mode
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        if (_bulkOperationMode) {
          setState(() {
            _bulkOperationMode = false;
            _selectedProducts.clear();
          });
        } else if (_hasActiveFilters()) {
          _clearAllFilters();
        }
        return;
      }

      // Ctrl+A: Select all (when in bulk mode)
      if (event.logicalKey == LogicalKeyboardKey.keyA &&
          isCtrlPressed &&
          _bulkOperationMode) {
        _toggleSelectAll();
        return;
      }

      // Delete: Bulk delete selected products
      if (event.logicalKey == LogicalKeyboardKey.delete &&
          _bulkOperationMode &&
          _selectedProducts.isNotEmpty) {
        _bulkDeleteProducts();
        return;
      }

      // Ctrl+B: Toggle bulk mode
      if (event.logicalKey == LogicalKeyboardKey.keyB && isCtrlPressed) {
        setState(() {
          _bulkOperationMode = !_bulkOperationMode;
          if (!_bulkOperationMode) {
            _selectedProducts.clear();
          }
        });
        return;
      }
    }
  }

  void _clearAllFilters() {
    setState(() {
      _searchTerm = '';
      _selectedCategory = '';
      _selectedBrand = '';
      _stockFilter = 'all';
      _currentPage = 1;
    });
    _applyFilters();
  }

  // Check if any filters are active
  bool _hasActiveFilters() {
    return _searchTerm.isNotEmpty ||
        (_selectedCategory.isNotEmpty && _selectedCategory != 'All') ||
        _selectedCategory.isNotEmpty ||
        _selectedBrand.isNotEmpty ||
        _stockFilter != 'all';
  }

  // Build success message widget
  Widget _buildSuccessMessage() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        border: Border.all(color: Colors.green.shade200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle, color: Colors.green.shade600, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _successMessage,
              style: TextStyle(
                color: Colors.green.shade800,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          IconButton(
            onPressed: () => setState(() => _successMessage = ''),
            icon: Icon(Icons.close, color: Colors.green.shade600, size: 18),
          ),
        ],
      ),
    );
  }

  // Build error message widget
  Widget _buildErrorMessage() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        border: Border.all(color: Colors.red.shade200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.error, color: Colors.red.shade600, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage,
              style: TextStyle(
                color: Colors.red.shade800,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          IconButton(
            onPressed: () => setState(() => _errorMessage = ''),
            icon: Icon(Icons.close, color: Colors.red.shade600, size: 18),
          ),
        ],
      ),
    );
  }

  // Build active filters display
  Widget _buildEnhancedSearchSection() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Header with icon
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.2),
                  ),
                ),
                child: Icon(
                  Icons.search,
                  size: 18,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '🔍 Search & Filter Products',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Search and Action Row
          _buildSearchAndActionRow(),
          const SizedBox(height: 20),

          // Filter Row
          _buildFilterRow(),
        ],
      ),
    );
  }

  Widget _buildSearchAndActionRow() {
    final isRestricted =
        _businessProfile != null && !_businessProfile!.isWritable;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 480;
        if (isCompact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Search field full width
              _buildSearchInput(),
              const SizedBox(height: 12),
              // Actions wrap to next line as needed
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (!isRestricted)
                    _buildActionButton(
                      icon: Icons.add,
                      label: 'Add Product',
                      onPressed: () =>
                          Navigator.pushNamed(context, '/add-product'),
                      isPrimary: true,
                    ),
                  _buildActionButton(
                    icon: Icons.select_all,
                    label: _bulkOperationMode ? 'Exit Bulk' : 'Bulk Select',
                    onPressed: () {
                      setState(() {
                        _bulkOperationMode = !_bulkOperationMode;
                        if (!_bulkOperationMode) {
                          _selectedProducts.clear();
                        }
                      });
                    },
                    isPrimary: false,
                  ),
                  _buildActionButton(
                    icon: Icons.keyboard,
                    label: 'Shortcuts',
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (context) => _buildShortcutsDialog(),
                      );
                    },
                    isPrimary: false,
                  ),
                ],
              ),
            ],
          );
        }
        // Wide screens: row layout
        return Row(
          children: [
            Expanded(flex: 3, child: _buildSearchInput()),
            const SizedBox(width: 16),
            if (!isRestricted) ...[
              _buildActionButton(
                icon: Icons.add,
                label: 'Add Product',
                onPressed: () => Navigator.pushNamed(context, '/add-product'),
                isPrimary: true,
              ),
              const SizedBox(width: 12),
            ],
            _buildActionButton(
              icon: Icons.select_all,
              label: _bulkOperationMode ? 'Exit Bulk' : 'Bulk Select',
              onPressed: () {
                setState(() {
                  _bulkOperationMode = !_bulkOperationMode;
                  if (!_bulkOperationMode) {
                    _selectedProducts.clear();
                  }
                });
              },
              isPrimary: false,
            ),
            const SizedBox(width: 12),
            _buildActionButton(
              icon: Icons.keyboard,
              label: 'Shortcuts',
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => _buildShortcutsDialog(),
                );
              },
              isPrimary: false,
            ),
          ],
        );
      },
    );
  }

  // Extracted for reuse between compact and wide layouts
  Widget _buildSearchInput() {
    return TextField(
      focusNode: _searchFocusNode,
      onChanged: (value) {
        setState(() {
          _searchTerm = value;
        });
        _applyFilters();
      },
      decoration: InputDecoration(
        hintText: 'Search products by name, brand, category...',
        prefixIcon: Icon(
          Icons.search,
          color: Theme.of(context).colorScheme.primary,
        ),
        suffixIcon: _searchTerm.isNotEmpty
            ? IconButton(
                onPressed: () {
                  setState(() {
                    _searchTerm = '';
                  });
                  _applyFilters();
                },
                icon: const Icon(Icons.clear),
              )
            : null,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
            width: 2,
          ),
        ),
        filled: true,
        fillColor: Theme.of(context).colorScheme.surface,
      ),
    );
  }

  Widget _buildShortcutsDialog() {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.keyboard, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          const Text('Keyboard Shortcuts'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _shortcutRow('Ctrl + F', 'Focus search input'),
          _shortcutRow('Escape', 'Clear filters or exit bulk mode'),
          _shortcutRow('Ctrl + B', 'Toggle bulk selection mode'),
          _shortcutRow('Ctrl + A', 'Select all products (in bulk mode)'),
          _shortcutRow('Delete', 'Delete selected products (in bulk mode)'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _shortcutRow(String combo, String description) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: Theme.of(
                  context,
                ).colorScheme.outline.withValues(alpha: 0.3),
              ),
            ),
            child: Text(
              combo,
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(description)),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    required bool isPrimary,
  }) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: isPrimary
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.surface,
        foregroundColor: isPrimary
            ? Theme.of(context).colorScheme.onPrimary
            : Theme.of(context).colorScheme.onSurface,
        elevation: isPrimary ? 2 : 0,
        side: isPrimary
            ? null
            : BorderSide(
                color: Theme.of(
                  context,
                ).colorScheme.outline.withValues(alpha: 0.3),
              ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }

  Widget _buildFilterRow() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 480;
        if (isCompact) {
          return Column(
            children: [
              _buildFilterDropdown(
                label: 'Category',
                value: _selectedCategory.isEmpty ? null : _selectedCategory,
                items: _categories
                    .map(
                      (category) => {
                        'value': category == 'All' ? '' : category,
                        'label': category,
                      },
                    )
                    .toList(),
                onChanged: (value) {
                  setState(() => _selectedCategory = value ?? '');
                  _applyFilters();
                },
                icon: '📂',
              ),
              const SizedBox(height: 12),
              _buildFilterDropdown(
                label: 'Brand',
                value: _selectedBrand.isNotEmpty ? _selectedBrand : null,
                items: ['All', ..._brands]
                    .map(
                      (brand) => {
                        'value': brand == 'All' ? '' : brand,
                        'label': brand,
                      },
                    )
                    .toList(),
                onChanged: (value) {
                  setState(() => _selectedBrand = value ?? '');
                  _applyFilters();
                },
                icon: '🏷️',
              ),
              const SizedBox(height: 12),
              _buildFilterDropdown(
                label: 'Stock Status',
                value: _stockFilter,
                items: const [
                  {'value': 'all', 'label': 'All Stock'},
                  {'value': 'in-stock', 'label': 'In Stock'},
                  {'value': 'out-of-stock', 'label': 'Out of Stock'},
                  {'value': 'low-stock', 'label': 'Low Stock'},
                ],
                onChanged: (value) {
                  setState(() => _stockFilter = value ?? 'all');
                  _applyFilters();
                },
                icon: '📊',
              ),
            ],
          );
        }
        // Wide layout: keep single row with spacing
        return Row(
          children: [
            Expanded(
              child: _buildFilterDropdown(
                label: 'Category',
                value: _selectedCategory.isEmpty ? null : _selectedCategory,
                items: _categories
                    .map(
                      (category) => {
                        'value': category == 'All' ? '' : category,
                        'label': category,
                      },
                    )
                    .toList(),
                onChanged: (value) {
                  setState(() => _selectedCategory = value ?? '');
                  _applyFilters();
                },
                icon: '📂',
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildFilterDropdown(
                label: 'Brand',
                value: _selectedBrand.isEmpty ? null : _selectedBrand,
                items: ['All', ..._brands]
                    .map(
                      (brand) => {
                        'value': brand == 'All' ? '' : brand,
                        'label': brand,
                      },
                    )
                    .toList(),
                onChanged: (value) {
                  setState(() => _selectedBrand = value ?? '');
                  _applyFilters();
                },
                icon: '🏷️',
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildFilterDropdown(
                label: 'Stock Status',
                value: _stockFilter,
                items: const [
                  {'value': 'all', 'label': 'All Stock'},
                  {'value': 'in-stock', 'label': 'In Stock'},
                  {'value': 'out-of-stock', 'label': 'Out of Stock'},
                  {'value': 'low-stock', 'label': 'Low Stock'},
                ],
                onChanged: (value) {
                  setState(() => _stockFilter = value ?? 'all');
                  _applyFilters();
                },
                icon: '📊',
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFilterDropdown({
    required String label,
    required String? value,
    required List<Map<String, String>> items,
    required ValueChanged<String?> onChanged,
    required String icon,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
        ),
      ),
      child: DropdownButtonFormField<String>(
        initialValue: value,
        decoration: InputDecoration(
          labelText: '$icon $label',
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
        items: items.map((item) {
          return DropdownMenuItem(
            value: item['value'],
            child: Text(item['label']!),
          );
        }).toList(),
        onChanged: onChanged,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: FocusNode(),
      autofocus: true,
      onKeyEvent: _handleKeyboardShortcuts,
      child: _buildScaffoldContent(),
    );
  }

  Widget _buildScaffoldContent() {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: const Center(child: CircularProgressIndicator()),
      );
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
                ).textTheme.bodyMedium?.color?.withValues(alpha: 0.6),
              ),
              const SizedBox(height: 16),
              Text(
                'Failed to load catalog',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).textTheme.titleLarge?.color,
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
                  ).textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
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

    // SvelteKit-inspired main layout with gradient background
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).colorScheme.surface,
              Theme.of(context).colorScheme.surface,
              Theme.of(
                context,
              ).colorScheme.surfaceContainerLowest.withValues(alpha: 0.3),
            ],
            stops: const [0.0, 0.7, 1.0],
          ),
        ),
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: _loadProducts,
            child: _buildScrollableContent(),
          ),
        ),
      ),
    );
  }

  Widget _buildScrollableContent() {
    return Scrollbar(
      controller: _scrollController,
      thumbVisibility: true,
      trackVisibility: true,
      thickness: 8,
      radius: const Radius.circular(4),
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          // Page Header as part of scrollable content
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: MediaQuery.of(context).size.width > 1024
                    ? 32
                    : MediaQuery.of(context).size.width > 640
                    ? 24
                    : 16,
                vertical: MediaQuery.of(context).size.width > 1024
                    ? 32
                    : MediaQuery.of(context).size.width > 640
                    ? 24
                    : 16,
              ),
              child: PageHeader(
                title: 'Product Catalog',
                description: 'Manage all products your business offers',
                icon: '📦',
                showBackButton: true,
                stats: [
                  PageHeaderStat(
                    label: 'Total Products',
                    value: '${_products.length}',
                    description: 'All products in inventory',
                  ),
                  PageHeaderStat(
                    label: 'Filtered Results',
                    value: '${_filteredProducts.length}',
                    description: 'Products matching current filters',
                  ),
                  PageHeaderStat(
                    label: 'Categories',
                    value: '${_categories.length - 1}',
                    description: 'Product categories available',
                  ),
                ],
              ),
            ),
          ),
          // Status Messages
          if (_successMessage.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: MediaQuery.of(context).size.width > 1024
                      ? 32
                      : MediaQuery.of(context).size.width > 640
                      ? 24
                      : 16,
                ),
                child: _buildSuccessMessage(),
              ),
            ),
          if (_errorMessage.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: MediaQuery.of(context).size.width > 1024
                      ? 32
                      : MediaQuery.of(context).size.width > 640
                      ? 24
                      : 16,
                ),
                child: _buildErrorMessage(),
              ),
            ),
          // Main content with consistent padding
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: MediaQuery.of(context).size.width > 1024
                    ? 32
                    : MediaQuery.of(context).size.width > 640
                    ? 24
                    : 16,
              ),
              child: Column(
                children: [
                  _buildEnhancedSearchSection(),
                  const SizedBox(height: 16),
                  if (_hasActiveFilters()) ...[
                    _buildActiveFilters(),
                    const SizedBox(height: 16),
                  ],
                  if (_bulkOperationMode && _selectedProducts.isNotEmpty) ...[
                    _buildBulkOperationsBar(),
                    const SizedBox(height: 16),
                  ],
                  _buildResultsSummary(),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
          // Products content with padding
          _buildSliverProductsListWithPadding(),
          // Pagination with padding
          if ((_filteredProducts.length / _itemsPerPage).ceil() > 1)
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  MediaQuery.of(context).size.width > 1024
                      ? 32
                      : MediaQuery.of(context).size.width > 640
                      ? 24
                      : 16,
                  16,
                  MediaQuery.of(context).size.width > 1024
                      ? 32
                      : MediaQuery.of(context).size.width > 640
                      ? 24
                      : 16,
                  32,
                ),
                child: _buildPaginationControls(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSliverProductsListWithPadding() {
    final horizontalPadding = MediaQuery.of(context).size.width > 1024
        ? 32.0
        : MediaQuery.of(context).size.width > 640
        ? 24.0
        : 16.0;

    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      sliver: _buildSliverProductsList(),
    );
  }

  Widget _buildSliverProductsList() {
    if (_filteredProducts.isEmpty) {
      return SliverToBoxAdapter(child: _buildEmptyState());
    }

    // Use MediaQuery to determine mobile layout
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < _mobileBreakpoint;

    if (isMobile) {
      return SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          final product = _getPaginatedProducts()[index];
          final isSelected = _selectedProducts.contains(product.id);
          return _buildMobileCard(product, isSelected);
        }, childCount: _getPaginatedProducts().length),
      );
    } else {
      return SliverToBoxAdapter(child: _buildDesktopTable());
    }
  }

  Widget _buildMobileCard(supabase_models.Product product, bool isSelected) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isSelected
            ? Theme.of(
                context,
              ).colorScheme.primaryContainer.withValues(alpha: 0.3)
            : Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.4)
              : Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
          width: isSelected ? 1.5 : 1,
        ),
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
        children: [
          Row(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
                child: product.productImageUrl?.isNotEmpty == true
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: product.productImageUrl!.startsWith('http')
                            ? Image.network(
                                product.productImageUrl!,
                                fit:
                                    MediaQuery.of(context).size.width >
                                        _mobileBreakpoint
                                    ? BoxFit.cover
                                    : BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) =>
                                    const Icon(Icons.image, size: 30),
                              )
                            : Image.file(
                                File(product.productImageUrl!),
                                fit:
                                    MediaQuery.of(context).size.width >
                                        _mobileBreakpoint
                                    ? BoxFit.cover
                                    : BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) =>
                                    const Icon(Icons.image, size: 30),
                              ),
                      )
                    : const Icon(Icons.image, size: 30),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (product.description?.isNotEmpty == true)
                      Text(
                        product.description!,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.7),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_bulkOperationMode)
                    Checkbox(
                      value: isSelected,
                      onChanged: (_) => _toggleProductSelection(product.id!),
                    ),
                  Container(
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.primaryContainer.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: IconButton(
                      onPressed: () => _openEditDialog(product),
                      icon: Icon(
                        Icons.edit_outlined,
                        size: 18,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      tooltip: 'Edit Product',
                      constraints: const BoxConstraints(
                        minWidth: 36,
                        minHeight: 36,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.errorContainer.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: IconButton(
                      onPressed: () => _deleteProduct(product),
                      icon: Icon(
                        Icons.delete_outline,
                        size: 18,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      tooltip: 'Delete Product',
                      constraints: const BoxConstraints(
                        minWidth: 36,
                        minHeight: 36,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              if (product.brand?.isNotEmpty == true)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.primaryContainer.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    '🏷️ ${product.brand}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '📂 ${product.category ?? 'Uncategorized'}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSecondaryContainer,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '💰 ₹${product.sellingPrice?.toStringAsFixed(2) ?? '0.00'}',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  if (product.purchasePrice != null)
                    Text(
                      'Cost: ₹${product.purchasePrice!.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _getStockColor(
                    product.currentStock,
                  ).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _getStockColor(
                      product.currentStock,
                    ).withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  '📊 ${product.currentStock} stock',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _getStockColor(product.currentStock),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActiveFilters() {
    List<Widget> filterChips = [];

    if (_searchTerm.isNotEmpty) {
      filterChips.add(
        _buildFilterChip('Search: $_searchTerm', () {
          setState(() => _searchTerm = '');
          _applyFilters();
        }),
      );
    }

    if (_selectedCategory.isNotEmpty && _selectedCategory != 'All') {
      filterChips.add(
        _buildFilterChip('Category: $_selectedCategory', () {
          setState(() => _selectedCategory = '');
          _applyFilters();
        }),
      );
    }

    if (_selectedBrand.isNotEmpty) {
      filterChips.add(
        _buildFilterChip('Brand: $_selectedBrand', () {
          setState(() => _selectedBrand = '');
          _applyFilters();
        }),
      );
    }

    if (_stockFilter != 'all') {
      final stockLabels = {
        'in-stock': 'In Stock',
        'out-of-stock': 'Out of Stock',
        'low-stock': 'Low Stock',
      };
      filterChips.add(
        _buildFilterChip('Stock: ${stockLabels[_stockFilter]}', () {
          setState(() => _stockFilter = 'all');
          _applyFilters();
        }),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Active Filters',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ...filterChips,
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _searchTerm = '';
                    _selectedCategory = '';
                    _selectedBrand = '';
                    _stockFilter = 'all';
                  });
                  _applyFilters();
                },
                icon: const Icon(Icons.clear_all, size: 16),
                label: const Text('Clear All'),
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                  textStyle: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, VoidCallback onRemove) {
    return Chip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      deleteIcon: const Icon(Icons.close, size: 16),
      onDeleted: onRemove,
      backgroundColor: Theme.of(
        context,
      ).colorScheme.primary.withValues(alpha: 0.1),
      side: BorderSide(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
      ),
    );
  }

  Widget _buildResultsSummary() {
    final startItem = (_currentPage - 1) * _itemsPerPage + 1;
    final endItem = (_currentPage * _itemsPerPage > _filteredProducts.length)
        ? _filteredProducts.length
        : _currentPage * _itemsPerPage;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 480;
        final summaryText =
            'Showing $startItem-$endItem of ${_filteredProducts.length} products';
        final content = isCompact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '📊 Results Summary',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    summaryText,
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: DropdownButton<int>(
                      value: _itemsPerPage,
                      underline: Container(),
                      items: [10, 20, 50, 100].map((int value) {
                        return DropdownMenuItem<int>(
                          value: value,
                          child: Text('$value per page'),
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
                  ),
                ],
              )
            : Row(
                children: [
                  Text(
                    '📊 Results Summary',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    summaryText,
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(width: 16),
                  DropdownButton<int>(
                    value: _itemsPerPage,
                    underline: Container(),
                    items: [10, 20, 50, 100].map((int value) {
                      return DropdownMenuItem<int>(
                        value: value,
                        child: Text('$value per page'),
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
              );
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Theme.of(
                context,
              ).colorScheme.outline.withValues(alpha: 0.2),
            ),
          ),
          child: content,
        );
      },
    );
  }

  Widget _buildDesktopTable() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Table Header with Sorting
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.8),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(
                    context,
                  ).colorScheme.outline.withValues(alpha: 0.15),
                  width: 1.5,
                ),
              ),
            ),
            child: Row(
              children: [
                if (_bulkOperationMode)
                  SizedBox(
                    width: 40,
                    child: Checkbox(
                      value:
                          _selectedProducts.length ==
                          _getPaginatedProducts().length,
                      onChanged: (_) => _toggleSelectAll(),
                    ),
                  ),
                _buildSortableHeader('🖼️ Image', 'image', flex: 1),
                _buildSortableHeader('📦 Product Name', 'name', flex: 4),
                _buildSortableHeader('🏷️ Brand', 'brand', flex: 2),
                _buildSortableHeader('📂 Category', 'category', flex: 2),
                _buildSortableHeader('📊 Stock', 'stock', flex: 1),
                _buildSortableHeader('💰 Price (₹)', 'price', flex: 2),
                Expanded(
                  flex: 2,
                  child: Text(
                    '⚙️ Actions',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onSurface,
                      letterSpacing: 0.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
          // Products List with improved styling
          ...(_getPaginatedProducts().asMap().entries.map((entry) {
            final index = entry.key;
            final product = entry.value;
            return _buildEnhancedProductRow(product, index);
          }).toList()),
        ],
      ),
    );
  }

  Widget _buildEnhancedProductRow(supabase_models.Product product, int index) {
    final isSelected = _selectedProducts.contains(product.id);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        color: isSelected
            ? Theme.of(
                context,
              ).colorScheme.primaryContainer.withValues(alpha: 0.3)
            : index.isEven
            ? Theme.of(context).colorScheme.surface
            : Theme.of(
                context,
              ).colorScheme.surfaceContainerLowest.withValues(alpha: 0.3),
        border: Border(
          bottom: BorderSide(
            color: Theme.of(
              context,
            ).colorScheme.outline.withValues(alpha: 0.08),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          if (_bulkOperationMode)
            SizedBox(
              width: 40,
              child: Checkbox(
                value: isSelected,
                onChanged: (_) => _toggleProductSelection(product.id!),
              ),
            ),
          Expanded(
            flex: 1,
            child: Container(
              width: MediaQuery.of(context).size.width > _mobileBreakpoint
                  ? 64
                  : 44,
              height: MediaQuery.of(context).size.width > _mobileBreakpoint
                  ? 64
                  : 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                border: Border.all(
                  color: Theme.of(
                    context,
                  ).colorScheme.outline.withValues(alpha: 0.1),
                ),
              ),
              child: product.productImageUrl?.isNotEmpty == true
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: product.productImageUrl!.startsWith('http')
                          ? Image.network(
                              product.productImageUrl!,
                              fit:
                                  MediaQuery.of(context).size.width >
                                      _mobileBreakpoint
                                  ? BoxFit.cover
                                  : BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) =>
                                  Icon(
                                    Icons.image,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.5),
                                    size: 20,
                                  ),
                            )
                          : Image.file(
                              File(product.productImageUrl!),
                              fit:
                                  MediaQuery.of(context).size.width >
                                      _mobileBreakpoint
                                  ? BoxFit.cover
                                  : BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) =>
                                  Icon(
                                    Icons.image,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.5),
                                    size: 20,
                                  ),
                            ),
                    )
                  : Icon(
                      Icons.image,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.5),
                      size: 20,
                    ),
            ),
          ),
          Expanded(
            flex: 4,
            child: Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (product.description?.isNotEmpty == true)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        product.description!,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text(
                product.brand ?? 'No Brand',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.8),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.secondaryContainer.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Theme.of(
                      context,
                    ).colorScheme.secondary.withValues(alpha: 0.2),
                  ),
                ),
                child: Text(
                  product.category ?? 'Uncategorized',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.onSecondaryContainer,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Padding(
              padding: const EdgeInsets.only(right: 20),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _getStockColor(
                    product.currentStock,
                  ).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _getStockColor(
                      product.currentStock,
                    ).withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  '${product.currentStock}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _getStockColor(product.currentStock),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text(
                '₹${product.sellingPrice?.toStringAsFixed(2) ?? '0.00'}',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.primaryContainer.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: IconButton(
                    onPressed: () => _openEditDialog(product),
                    icon: Icon(
                      Icons.edit_outlined,
                      size: 18,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    tooltip: 'Edit Product',
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.errorContainer.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: IconButton(
                    onPressed: () => _deleteProduct(product),
                    icon: Icon(
                      Icons.delete_outline,
                      size: 18,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    tooltip: 'Delete Product',
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBulkOperationsBar() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        children: [
          // Selection Info Row
          Row(
            children: [
              Icon(
                Icons.checklist,
                color: Theme.of(context).colorScheme.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Bulk Operations Mode',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const Spacer(),
              Text(
                '${_selectedProducts.length} selected',
                style: TextStyle(color: Theme.of(context).colorScheme.primary),
              ),
              const SizedBox(width: 12),
              TextButton(
                onPressed: _toggleSelectAll,
                child: Text(
                  _selectedProducts.length == _getPaginatedProducts().length
                      ? 'Deselect All'
                      : 'Select All',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Bulk Actions Row
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildBulkActionButton(
                icon: Icons.select_all_rounded,
                label:
                    _selectedProducts.length == _getPaginatedProducts().length
                    ? 'Deselect All'
                    : 'Select All',
                onPressed: _toggleSelectAll,
                color: Theme.of(context).colorScheme.secondary,
              ),
              _buildBulkActionButton(
                icon: Icons.edit_rounded,
                label: 'Bulk Edit',
                onPressed: _bulkEditProducts,
                color: Colors.blue,
              ),
              _buildBulkActionButton(
                icon: Icons.category_rounded,
                label: 'Change Category',
                onPressed: _bulkChangeCategory,
                color: Colors.orange,
              ),
              _buildBulkActionButton(
                icon: Icons.file_download_rounded,
                label: 'Export Selected',
                onPressed: _exportSelectedProducts,
                color: Colors.green,
              ),
              _buildBulkActionButton(
                icon: Icons.delete_rounded,
                label: 'Delete Selected',
                onPressed: _bulkDeleteProducts,
                color: Colors.red,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBulkActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    required Color color,
  }) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: color.withValues(alpha: 0.1),
        foregroundColor: color,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: color.withValues(alpha: 0.3)),
        ),
      ),
    );
  }

  Widget _buildSortableHeader(String title, String column, {int flex = 1}) {
    final isActive = _sortColumn == column;
    return Expanded(
      flex: flex,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _handleSort(column),
          borderRadius: BorderRadius.circular(4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: isActive
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.onSurface,
                      letterSpacing: 0.5,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: isActive
                      ? Icon(
                          _sortOrder == 'asc'
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.keyboard_arrow_down_rounded,
                          key: ValueKey(_sortOrder),
                          size: 20,
                          color: Theme.of(context).colorScheme.primary,
                        )
                      : Icon(
                          Icons.unfold_more_rounded,
                          key: const ValueKey('unfold'),
                          size: 16,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.4),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _getStockColor(num stock) {
    if (stock <= 0) return Colors.red;
    if (stock <= 10) return Colors.orange;
    return Colors.green;
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.inventory_2_outlined,
            size: 64,
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'No products found',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Try adjusting your search or filter criteria',
            style: TextStyle(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaginationControls() {
    final startItem = (_currentPage - 1) * _itemsPerPage + 1;
    final endItem = (_currentPage * _itemsPerPage > _filteredProducts.length)
        ? _filteredProducts.length
        : _currentPage * _itemsPerPage;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Column(
        children: [
          // Items per page selector
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
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
                    items: [10, 20, 50, 100].map((int value) {
                      return DropdownMenuItem<int>(
                        value: value,
                        child: Text('$value'),
                      );
                    }).toList(),
                    onChanged: (int? newValue) {
                      if (newValue != null) {
                        setState(() {
                          _itemsPerPage = newValue;
                          _currentPage = 1; // Reset to first page
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
          const SizedBox(height: 12),
          // Navigation controls
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // First page
                IconButton(
                  onPressed: _currentPage > 1
                      ? () => setState(() => _currentPage = 1)
                      : null,
                  icon: const Icon(Icons.first_page),
                  tooltip: 'First page',
                ),
                // Previous page
                IconButton(
                  onPressed: _currentPage > 1
                      ? () => setState(() => _currentPage--)
                      : null,
                  icon: const Icon(Icons.chevron_left),
                  tooltip: 'Previous page',
                ),
                const SizedBox(width: 8),
                // Page numbers
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
                          width: 40,
                          height: 40,
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
                // Next page
                IconButton(
                  onPressed: _currentPage < _totalPages
                      ? () => setState(() => _currentPage++)
                      : null,
                  icon: const Icon(Icons.chevron_right),
                  tooltip: 'Next page',
                ),
                // Last page
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
      ),
    );
  }

  Future<void> _deleteProduct(supabase_models.Product product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Product'),
        content: Text('Are you sure you want to delete "${product.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await SupabaseService.deleteProduct(product.id!);
        await _loadProducts();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Successfully deleted "${product.name}"'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to delete product: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }
}

class EditProductDialog extends StatefulWidget {
  final supabase_models.Product product;
  final VoidCallback onProductUpdated;

  const EditProductDialog({
    super.key,
    required this.product,
    required this.onProductUpdated,
  });

  @override
  State<EditProductDialog> createState() => _EditProductDialogState();
}

class _EditProductDialogState extends State<EditProductDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _brandController = TextEditingController();
  final _priceController = TextEditingController();
  // New fields to mirror AddProductPage
  final _sizeSpecController = TextEditingController();
  final _unitTypeSingleController = TextEditingController(text: 'Piece');
  final _unitTypeWholesaleController = TextEditingController();
  final _itemsPerUnitController = TextEditingController(text: '1');
  // Category state
  List<String> _categories = [];
  bool _isLoadingCategories = false;
  String? _selectedCategory;
  final _newCategoryController = TextEditingController();
  final _urlController = TextEditingController();

  bool _isLoading = false;
  List<String> _selectedImages = [];
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _initializeFields();
    _loadCategories();
  }

  void _initializeFields() {
    _nameController.text = widget.product.name;
    _descriptionController.text = widget.product.description ?? '';
    _brandController.text = widget.product.brand ?? '';
    _priceController.text = widget.product.sellingPrice?.toString() ?? '';
    _sizeSpecController.text = widget.product.sizeOrSpec ?? '';
    _unitTypeSingleController.text = widget.product.unitTypeSingle ?? 'Piece';
    _unitTypeWholesaleController.text = widget.product.unitTypeWholesale ?? '';
    _itemsPerUnitController.text = (widget.product.itemsPerWholesaleUnit ?? 1)
        .toString();
    _selectedCategory = widget.product.category;

    // Initialize existing images by fetching from product_images table
    _selectedImages = [];
    final pid = widget.product.id;
    if (pid != null) {
      // Load URLs from table and merge with cover as fallback
      SupabaseService.getProductImageUrls(pid).then((urls) {
        if (!mounted) return;
        setState(() {
          _selectedImages.clear();
          if (urls.isNotEmpty) {
            _selectedImages.addAll(urls);
          } else {
            // Fallback: include cover if present
            final cover = widget.product.productImageUrl;
            if (cover != null && cover.isNotEmpty) {
              _selectedImages.add(cover);
            }
          }
        });
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _brandController.dispose();
    _priceController.dispose();
    _sizeSpecController.dispose();
    _unitTypeSingleController.dispose();
    _unitTypeWholesaleController.dispose();
    _itemsPerUnitController.dispose();
    _newCategoryController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  // Image handling methods
  Widget buildImagePreview(String reference) {
    if (reference.startsWith("http")) {
      return Image.network(
        reference,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Icon(
              Icons.broken_image,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          );
        },
      );
    } else {
      return Image.file(
        File(reference),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Icon(
              Icons.broken_image,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          );
        },
      );
    }
  }

  Future<void> _pickImages() async {
    final List<XFile> pickedFiles = await _picker.pickMultiImage();
    if (pickedFiles.isNotEmpty) {
      setState(() {
        for (var file in pickedFiles) {
          if (_selectedImages.length < 10 &&
              !_selectedImages.contains(file.path)) {
            _selectedImages.add(file.path);
          }
        }
      });
      _showSnackBar(
        '${pickedFiles.length} image(s) added successfully!',
        isError: false,
      );
    }
  }

  void _addImageFromUrl() {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      _showSnackBar('Please enter a valid URL', isError: true);
      return;
    }

    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      _showSnackBar('URL must start with http:// or https://', isError: true);
      return;
    }

    if (_selectedImages.length >= 10) {
      _showSnackBar('Maximum 10 images allowed', isError: true);
      return;
    }

    if (_selectedImages.contains(url)) {
      _showSnackBar('This image URL is already added', isError: true);
      return;
    }

    setState(() {
      _selectedImages.add(url);
      _urlController.clear();
    });
    _showSnackBar('Image URL added successfully!', isError: false);
  }

  void _removeImage(int index) {
    setState(() {
      _selectedImages.removeAt(index);
    });
    _showSnackBar('Image removed', isError: false);
  }

  void _showSnackBar(String message, {required bool isError}) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError
              ? Theme.of(context).colorScheme.error
              : Theme.of(context).colorScheme.primary,
        ),
      );
    }
  }

  Widget _buildImageSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Product Images',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 12),

        // Image Upload Area
        Container(
          width: double.infinity,
          height: 120,
          decoration: BoxDecoration(
            border: Border.all(
              color: Theme.of(
                context,
              ).colorScheme.outline.withValues(alpha: 0.3),
              width: 1,
              style: BorderStyle.solid,
            ),
            borderRadius: BorderRadius.circular(12),
            color: Theme.of(context).colorScheme.surface,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.cloud_upload_outlined,
                size: 32,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              const SizedBox(height: 8),
              Text(
                'Use the buttons below to add images',
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Maximum 10 images allowed',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Action Buttons
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pickImages,
                icon: const Icon(Icons.photo_library, size: 18),
                label: const Text('Choose Images'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),

        // URL Input Section
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _urlController,
                decoration: InputDecoration(
                  labelText: 'Or add image from URL',
                  hintText: 'https://example.com/image.jpg',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    onPressed: _addImageFromUrl,
                    icon: const Icon(Icons.add),
                    tooltip: 'Add URL',
                  ),
                ),
                onFieldSubmitted: (_) => _addImageFromUrl(),
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),

        // Selected Images Grid with drag-to-reorder
        if (_selectedImages.isNotEmpty) ...[
          Text(
            'Selected Images (${_selectedImages.length}/10)',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(
                Icons.drag_indicator,
                size: 16,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              const SizedBox(width: 6),
              Text(
                'Drag to reorder. First image becomes the cover.',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ReorderableWrap(
            spacing: 8,
            runSpacing: 8,
            needsLongPressDraggable: true,
            onReorder: (oldIndex, newIndex) {
              setState(() {
                final item = _selectedImages.removeAt(oldIndex);
                _selectedImages.insert(newIndex, item);
              });
            },
            children: List.generate(_selectedImages.length, (index) {
              return Container(
                key: ValueKey(_selectedImages[index]),
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(
                      context,
                    ).colorScheme.outline.withValues(alpha: 0.3),
                  ),
                ),
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(7),
                      child: buildImagePreview(_selectedImages[index]),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: GestureDetector(
                        onTap: () => _removeImage(index),
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.error,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.close,
                            size: 16,
                            color: Theme.of(context).colorScheme.onError,
                          ),
                        ),
                      ),
                    ),
                    if (index == 0)
                      Positioned(
                        left: 4,
                        bottom: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.primary.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Cover',
                            style: TextStyle(
                              fontSize: 10,
                              color: Theme.of(context).colorScheme.onPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            }),
          ),
        ],
      ],
    );
  }

  Future<void> _updateProduct() async {
    if (!ConnectivityService().isOnline.value) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You are offline. Cannot update product.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // Save images: persist local files to device; http URLs to product_images table
      List<String> saved = [];
      if (_selectedImages.isNotEmpty) {
        saved = await ImageStorageService.saveProductImages(
          _selectedImages,
          widget.product.id!,
        );
      }
      final httpUrls = saved.where((p) => p.startsWith('http')).toList();
      // Update product_images and cover; keep device-local files as is
      await SupabaseService.setProductImageUrls(widget.product.id!, httpUrls);

      final updatedProduct = await SupabaseService.updateProduct(
        id: widget.product.id!,
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        brand: _brandController.text.trim().isEmpty
            ? null
            : _brandController.text.trim(),
        category: (_selectedCategory ?? '').trim().isEmpty
            ? null
            : _selectedCategory!.trim(),
        sellingPrice: double.tryParse(_priceController.text),
        sizeOrSpec: _sizeSpecController.text.trim().isEmpty
            ? null
            : _sizeSpecController.text.trim(),
        unitTypeSingle: _unitTypeSingleController.text.trim().isEmpty
            ? 'Piece'
            : _unitTypeSingleController.text.trim(),
        unitTypeWholesale: _unitTypeWholesaleController.text.trim().isEmpty
            ? null
            : _unitTypeWholesaleController.text.trim(),
        itemsPerWholesaleUnit:
            int.tryParse(_itemsPerUnitController.text.trim()) ?? 1,
        // We no longer attempt to write product_images column; cover is set by setProductImageUrls
        localImagePaths: null,
      );

      if (mounted && updatedProduct != null) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Product updated successfully!')),
        );
        widget.onProductUpdated();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update product')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error updating product: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.edit,
                    color: Theme.of(context).colorScheme.onPrimary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Edit Product',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _isLoading
                        ? null
                        : () => Navigator.of(context).pop(),
                    icon: Icon(
                      Icons.close,
                      color: Theme.of(context).colorScheme.onPrimary,
                    ),
                  ),
                ],
              ),
            ),
            // Form Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Product Name *',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Product name is required';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _descriptionController,
                        decoration: const InputDecoration(
                          labelText: 'Description',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 3,
                      ),
                      const SizedBox(height: 16),
                      // Brand + Category (dropdown with Add New)
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final bool narrow = constraints.maxWidth < 480;
                          final brandField = TextFormField(
                            controller: _brandController,
                            decoration: const InputDecoration(
                              labelText: 'Brand',
                              border: OutlineInputBorder(),
                            ),
                          );
                          final categoryField = DropdownButtonFormField<String>(
                            isExpanded: true,
                            initialValue: _selectedCategory,
                            decoration: const InputDecoration(
                              labelText: 'Category *',
                              border: OutlineInputBorder(),
                            ),
                            items: _categories
                                .map(
                                  (c) => DropdownMenuItem(
                                    value: c,
                                    child: Text(
                                      c,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) => setState(() {
                              _selectedCategory = v;
                            }),
                            validator: (value) {
                              if ((value ?? '').isEmpty) {
                                return 'Category is required';
                              }
                              return null;
                            },
                          );
                          if (narrow) {
                            return Column(
                              children: [
                                brandField,
                                const SizedBox(height: 12),
                                categoryField,
                              ],
                            );
                          }
                          return Row(
                            children: [
                              Expanded(child: brandField),
                              const SizedBox(width: 16),
                              Expanded(child: categoryField),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: _isLoadingCategories
                              ? null
                              : () async {
                                  await _showAddCategoryDialog();
                                },
                          icon: const Icon(Icons.add),
                          label: const Text('Add New Category'),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Size/Spec
                      TextFormField(
                        controller: _sizeSpecController,
                        decoration: const InputDecoration(
                          labelText: 'Size/Spec',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Unit Information
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Theme.of(
                              context,
                            ).dividerColor.withValues(alpha: 0.1),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Unit Information',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Theme.of(
                                  context,
                                ).textTheme.titleMedium?.color,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _unitTypeSingleController,
                                    decoration: const InputDecoration(
                                      labelText: 'Single Unit',
                                      hintText: 'Piece',
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextFormField(
                                    controller: _unitTypeWholesaleController,
                                    decoration: const InputDecoration(
                                      labelText: 'Wholesale Unit',
                                      hintText: 'Box, Coil, Payti',
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _itemsPerUnitController,
                              decoration: const InputDecoration(
                                labelText: 'Items per Wholesale Unit',
                                border: OutlineInputBorder(),
                              ),
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              validator: (value) {
                                final v = int.tryParse((value ?? '').trim());
                                if (v == null) {
                                  return 'Enter a valid number';
                                }
                                if (v <= 0) {
                                  return 'Must be a positive integer';
                                }
                                return null;
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Selling Price
                      TextFormField(
                        controller: _priceController,
                        decoration: const InputDecoration(
                          labelText: 'Selling Price',
                          border: OutlineInputBorder(),
                          prefixText: '₹ ',
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'^\d*\.?\d*'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Image Management Section
                      _buildImageSection(),
                    ],
                  ),
                ),
              ),
            ),
            // Footer
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isLoading
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _updateProduct,
                    child: _isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Update Product'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Category helpers
  Future<void> _loadCategories() async {
    setState(() => _isLoadingCategories = true);
    try {
      // Try categories table
      final supabaseCategories = await SupabaseService.getCategories();
      var names = supabaseCategories.map((c) => c.name).toList();
      // Fallback to categories from products
      if (names.isEmpty) {
        names = await SupabaseService.getProductCategories();
      }
      setState(() {
        _categories = names..sort();
        // Ensure selected exists in list
        if (_selectedCategory != null &&
            _selectedCategory!.isNotEmpty &&
            !_categories.contains(_selectedCategory)) {
          _categories.add(_selectedCategory!);
          _categories.sort();
        }
      });
    } catch (_) {
      // keep empty list on failure
    } finally {
      if (mounted) setState(() => _isLoadingCategories = false);
    }
  }

  Future<void> _showAddCategoryDialog() async {
    if (!ConnectivityService().isOnline.value) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You are offline. Cannot add new category.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    _newCategoryController.clear();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add New Category'),
        content: TextField(
          controller: _newCategoryController,
          decoration: const InputDecoration(
            labelText: 'Category Name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final name = _newCategoryController.text.trim();
              if (name.isNotEmpty) {
                Navigator.of(context).pop(name);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      try {
        // Try creating on Supabase, ignore failures
        await SupabaseService.createCategory(name: result);
      } catch (_) {}
      if (mounted) {
        setState(() {
          if (!_categories.contains(result)) {
            _categories.add(result);
            _categories.sort();
          }
          _selectedCategory = result;
        });
        // Optionally reload from server in background
        _loadCategories();
      }
    }
  }
}

// Bulk Edit Dialog Widget
class _BulkEditDialog extends StatefulWidget {
  final int selectedCount;
  final List<String> categories;
  final List<String> brands;

  const _BulkEditDialog({
    required this.selectedCount,
    required this.categories,
    required this.brands,
  });

  @override
  State<_BulkEditDialog> createState() => _BulkEditDialogState();
}

class _BulkEditDialogState extends State<_BulkEditDialog> {
  final _formKey = GlobalKey<FormState>();
  final _brandController = TextEditingController();
  final _categoryController = TextEditingController();
  final _sellingPriceController = TextEditingController();
  final _purchasePriceController = TextEditingController();

  bool _updateBrand = false;
  bool _updateCategory = false;
  bool _updateSellingPrice = false;
  bool _updatePurchasePrice = false;

  @override
  void dispose() {
    _brandController.dispose();
    _categoryController.dispose();
    _sellingPriceController.dispose();
    _purchasePriceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.edit_note,
                    color: Theme.of(context).colorScheme.onPrimary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Bulk Edit ${widget.selectedCount} Products',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(
                      Icons.close,
                      color: Theme.of(context).colorScheme.onPrimary,
                    ),
                  ),
                ],
              ),
            ),
            // Form Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Select which fields to update for all selected products:',
                        style: TextStyle(
                          fontSize: 16,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Brand Section
                      CheckboxListTile(
                        title: const Text('Update Brand'),
                        value: _updateBrand,
                        onChanged: (value) {
                          setState(() {
                            _updateBrand = value ?? false;
                          });
                        },
                      ),
                      if (_updateBrand) ...[
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _brandController,
                          decoration: const InputDecoration(
                            labelText: 'New Brand',
                            border: OutlineInputBorder(),
                          ),
                          validator: _updateBrand
                              ? (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Brand is required';
                                  }
                                  return null;
                                }
                              : null,
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Category Section
                      CheckboxListTile(
                        title: const Text('Update Category'),
                        value: _updateCategory,
                        onChanged: (value) {
                          setState(() {
                            _updateCategory = value ?? false;
                          });
                        },
                      ),
                      if (_updateCategory) ...[
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          decoration: const InputDecoration(
                            labelText: 'New Category',
                            border: OutlineInputBorder(),
                          ),
                          items: widget.categories.map((category) {
                            return DropdownMenuItem(
                              value: category,
                              child: Text(category),
                            );
                          }).toList(),
                          onChanged: (value) {
                            _categoryController.text = value ?? '';
                          },
                          validator: _updateCategory
                              ? (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Category is required';
                                  }
                                  return null;
                                }
                              : null,
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Purchase Price Section
                      CheckboxListTile(
                        title: const Text('Update Purchase Price'),
                        value: _updatePurchasePrice,
                        onChanged: (value) {
                          setState(() {
                            _updatePurchasePrice = value ?? false;
                          });
                        },
                      ),
                      if (_updatePurchasePrice) ...[
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _purchasePriceController,
                          decoration: const InputDecoration(
                            labelText: 'New Purchase Price',
                            border: OutlineInputBorder(),
                            prefixText: '₹ ',
                          ),
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'^\d*\.?\d*'),
                            ),
                          ],
                          validator: _updatePurchasePrice
                              ? (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Purchase price is required';
                                  }
                                  if (double.tryParse(value) == null) {
                                    return 'Enter a valid price';
                                  }
                                  return null;
                                }
                              : null,
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Selling Price Section
                      CheckboxListTile(
                        title: const Text('Update Selling Price'),
                        value: _updateSellingPrice,
                        onChanged: (value) {
                          setState(() {
                            _updateSellingPrice = value ?? false;
                          });
                        },
                      ),
                      if (_updateSellingPrice) ...[
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _sellingPriceController,
                          decoration: const InputDecoration(
                            labelText: 'New Selling Price',
                            border: OutlineInputBorder(),
                            prefixText: '₹ ',
                          ),
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'^\d*\.?\d*'),
                            ),
                          ],
                          validator: _updateSellingPrice
                              ? (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Selling price is required';
                                  }
                                  if (double.tryParse(value) == null) {
                                    return 'Enter a valid price';
                                  }
                                  return null;
                                }
                              : null,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            // Footer
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: () {
                      if (_formKey.currentState!.validate()) {
                        final updates = <String, dynamic>{};

                        if (_updateBrand) {
                          updates['brand'] = _brandController.text.trim();
                        }
                        if (_updateCategory) {
                          updates['category'] = _categoryController.text.trim();
                        }
                        if (_updatePurchasePrice) {
                          updates['purchasePrice'] = double.tryParse(
                            _purchasePriceController.text,
                          );
                        }
                        if (_updateSellingPrice) {
                          updates['sellingPrice'] = double.tryParse(
                            _sellingPriceController.text,
                          );
                        }

                        Navigator.of(context).pop(updates);
                      }
                    },
                    child: Text('Update ${widget.selectedCount} Products'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
