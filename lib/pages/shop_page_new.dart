import 'package:flutter/material.dart';
import 'package:raj_electricals_inventory_app/theme/ui_tokens.dart';
import 'dart:async';
import '../data/app_database.dart';
import '../services/supabase_service.dart';
import '../models/supabase_models.dart' as supabase_models;
import 'package:shared_preferences/shared_preferences.dart';

class ShopPage extends StatefulWidget {
  final AppDatabase db;
  const ShopPage({super.key, required this.db});

  @override
  State<ShopPage> createState() => _ShopPageState();
}

class _ShopPageState extends State<ShopPage> {
  // State variables
  String _searchQuery = '';
  String _selectedCategory = 'all';
  String _sortBy = 'newest';
  bool _isGridView = true;
  int _cartCount = 0;
  final List<Map<String, dynamic>> _cartItems = [];
  final List<int> _wishlist = [];
  final List<int> _recentlyViewed = [];
  bool _isLoadingProducts = true;
  String? _loadErrorMessage;
  final ScrollController _scrollController = ScrollController();

  // Product data
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _allProducts = [];
  List<String> _categories = ['all'];

  @override
  void initState() {
    super.initState();
    _loadProductsAndCategories();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadProductsAndCategories() async {
    if (!mounted) return;

    setState(() {
      _isLoadingProducts = true;
      _loadErrorMessage = null;
    });

    try {
      // Check if business ID is set
      final businessId = SupabaseService.getCurrentBusinessId();
      if (businessId == null) {
        setState(() {
          _products = [];
          _allProducts = [];
          _categories = ['all'];
          _isLoadingProducts = false;
          _loadErrorMessage = 'No Shop ID configured. Tap here to set.';
        });
        return;
      }

      // Load products from Supabase
      final supaProducts = await SupabaseService.getProducts().timeout(
        const Duration(seconds: 10),
      );

      // Map products to shop format
      final mapped = supaProducts.map((p) => _mapProduct(p)).toList();

      // Extract unique categories
      final Set<String> categorySet = {};
      for (var p in mapped) {
        if (p['category'] != null) {
          categorySet.add(p['category']);
        }
      }

      if (mounted) {
        setState(() {
          _products = mapped;
          _allProducts = List<Map<String, dynamic>>.from(_products);
          _categories = ['all', ...categorySet.toList()..sort()];
          _isLoadingProducts = false;
        });
      }
    } on TimeoutException {
      if (mounted) {
        setState(() {
          _products = [];
          _allProducts = [];
          _categories = ['all'];
          _isLoadingProducts = false;
          _loadErrorMessage = 'Connection timeout. Please check your internet.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _products = [];
          _allProducts = [];
          _categories = ['all'];
          _isLoadingProducts = false;
          _loadErrorMessage = 'Failed to load products: $e';
        });
      }
    }
  }

  Map<String, dynamic> _mapProduct(supabase_models.Product p) {
    return {
      'id': p.id,
      'name': p.name,
      'brand': p.brand ?? '',
      'category': p.category ?? 'General',
      'price': p.sellingPrice ?? 0.0,
      'stock': p.currentStock,
      'description': p.description ?? '',
      'image': p.productImageUrl,
      'rating': 4.5, // Mock rating
      'isNew': false,
    };
  }

  List<Map<String, dynamic>> get _filteredProducts {
    var filtered = _products.where((product) {
      final matchesSearch =
          _searchQuery.isEmpty ||
          product['name'].toString().toLowerCase().contains(
            _searchQuery.toLowerCase(),
          ) ||
          product['brand'].toString().toLowerCase().contains(
            _searchQuery.toLowerCase(),
          );

      final matchesCategory =
          _selectedCategory == 'all' ||
          product['category'] == _selectedCategory;

      return matchesSearch && matchesCategory;
    }).toList();

    // Sort products
    switch (_sortBy) {
      case 'price-low':
        filtered.sort(
          (a, b) => (a['price'] as num).compareTo(b['price'] as num),
        );
        break;
      case 'price-high':
        filtered.sort(
          (a, b) => (b['price'] as num).compareTo(a['price'] as num),
        );
        break;
      case 'name':
        filtered.sort(
          (a, b) => a['name'].toString().compareTo(b['name'].toString()),
        );
        break;
      default:
        // Keep original order
        break;
    }

    return filtered;
  }

  void _addToCart(int productId) {
    final product = _products.firstWhere((p) => p['id'] == productId);
    final existingIndex = _cartItems.indexWhere(
      (item) => item['id'] == productId,
    );

    if (existingIndex >= 0) {
      setState(() {
        _cartItems[existingIndex]['qty']++;
      });
    } else {
      setState(() {
        _cartItems.add({
          'id': productId,
          'name': product['name'],
          'price': product['price'],
          'qty': 1,
          'stock': product['stock'],
        });
      });
    }

    setState(() {
      _cartCount = _cartItems.fold(
        0,
        (sum, item) => sum + (item['qty'] as int),
      );
    });

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('${product['name']} added to cart')));
  }

  void _toggleWishlist(int productId) {
    setState(() {
      if (_wishlist.contains(productId)) {
        _wishlist.remove(productId);
      } else {
        _wishlist.add(productId);
      }
    });
  }

  Future<void> _promptSetBusinessId() async {
    final controller = TextEditingController();
    final result = await showDialog<String?>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Set Shop ID'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Enter your Business ID (UUID) to load products in the Shop app.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'Business ID',
                  hintText: 'e.g. 93926466-a72c-4eda-87c8-ed3594e45c23',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (!mounted) return;
    final id = (result ?? '').trim();
    if (id.isEmpty) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('DEFAULT_BUSINESS_ID', id);
      SupabaseService.setDefaultBusinessId(id);
      await _loadProductsAndCategories();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Shop ID saved. Reloading products...')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to save Shop ID: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Shop'),
        actions: [
          if (_cartCount > 0)
            Stack(
              children: [
                IconButton(
                  icon: const Icon(Icons.shopping_cart),
                  onPressed: _showCart,
                ),
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.error,
                      borderRadius: BorderRadius.circular(UITokens.radius),
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    child: Text(
                      '$_cartCount',
                      style: const TextStyle(color: Colors.white, fontSize: 10),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadProductsAndCategories,
        child: SingleChildScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Search and filters
              _buildSearchBar(),
              _buildFilterBar(),

              // Error or loading state
              if (_loadErrorMessage != null)
                _buildErrorBanner()
              else if (_isLoadingProducts)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (_filteredProducts.isEmpty)
                _buildNoProductsFound()
              else
                // Products grid/list
                _buildProductsSection(),

              // Footer
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: TextField(
        decoration: InputDecoration(
          hintText: 'Search products...',
          prefixIcon: const Icon(Icons.search),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: Theme.of(context).cardColor,
        ),
        onChanged: (value) {
          setState(() {
            _searchQuery = value;
          });
        },
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // Category filter
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _categories.map((cat) {
                  final isSelected = _selectedCategory == cat;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(cat == 'all' ? 'All' : cat),
                      selected: isSelected,
                      onSelected: (selected) {
                        setState(() {
                          _selectedCategory = cat;
                        });
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          // Sort dropdown
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort),
            onSelected: (value) {
              setState(() {
                _sortBy = value;
              });
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'newest', child: Text('Newest')),
              const PopupMenuItem(
                value: 'price-low',
                child: Text('Price: Low to High'),
              ),
              const PopupMenuItem(
                value: 'price-high',
                child: Text('Price: High to Low'),
              ),
              const PopupMenuItem(value: 'name', child: Text('Name')),
            ],
          ),

          // View toggle
          IconButton(
            icon: Icon(_isGridView ? Icons.view_list : Icons.grid_view),
            onPressed: () {
              setState(() {
                _isGridView = !_isGridView;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner() {
    return InkWell(
      onTap: _loadErrorMessage?.contains('Shop ID') == true
          ? _promptSetBusinessId
          : null,
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              Icons.error_outline,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _loadErrorMessage ?? 'An error occurred',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
            if (_loadErrorMessage?.contains('Shop ID') == true)
              Icon(
                Icons.arrow_forward,
                color: Theme.of(context).colorScheme.error,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoProductsFound() {
    return Container(
      padding: const EdgeInsets.all(48),
      child: Column(
        children: [
          Icon(
            Icons.search_off,
            size: 64,
            color: Theme.of(context).disabledColor,
          ),
          const SizedBox(height: 16),
          const Text(
            'No products found',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'Try adjusting your search or filters',
            style: TextStyle(
              color: Theme.of(
                context,
              ).textTheme.bodyMedium?.color?.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductsSection() {
    if (_isGridView) {
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: MediaQuery.of(context).size.width > 600 ? 4 : 2,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 0.75,
        ),
        itemCount: _filteredProducts.length,
        itemBuilder: (context, index) {
          return _buildProductCard(_filteredProducts[index]);
        },
      );
    } else {
      return ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: _filteredProducts.length,
        itemBuilder: (context, index) {
          return _buildProductListItem(_filteredProducts[index]);
        },
      );
    }
  }

  Widget _buildProductCard(Map<String, dynamic> product) {
    final isOutOfStock = product['stock'] == 0;
    final isWishlisted = _wishlist.contains(product['id']);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _viewProduct(product),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Product image
            Expanded(
              flex: 3,
              child: Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                    ),
                    child: product['image'] != null
                        ? Image.network(
                            product['image'],
                            fit: BoxFit.cover,
                            width: double.infinity,
                            errorBuilder: (context, error, stackTrace) {
                              return const Center(
                                child: Icon(
                                  Icons.image_not_supported,
                                  size: 48,
                                ),
                              );
                            },
                          )
                        : const Center(child: Icon(Icons.image, size: 48)),
                  ),
                  if (isOutOfStock)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.error,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'Out of Stock',
                          style: TextStyle(color: Colors.white, fontSize: 10),
                        ),
                      ),
                    ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: IconButton(
                      icon: Icon(
                        isWishlisted ? Icons.favorite : Icons.favorite_border,
                        color: isWishlisted ? Colors.red : Colors.white,
                      ),
                      onPressed: () => _toggleWishlist(product['id']),
                    ),
                  ),
                ],
              ),
            ),

            // Product details
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product['name'],
                          style: const TextStyle(fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          product['brand'],
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).textTheme.bodySmall?.color,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '₹${product['price']}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add_shopping_cart, size: 20),
                          onPressed: isOutOfStock
                              ? null
                              : () => _addToCart(product['id']),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductListItem(Map<String, dynamic> product) {
    final isOutOfStock = product['stock'] == 0;
    final isWishlisted = _wishlist.contains(product['id']);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: product['image'] != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    product['image'],
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return const Icon(Icons.image_not_supported);
                    },
                  ),
                )
              : const Icon(Icons.image),
        ),
        title: Text(product['name']),
        subtitle: Text('${product['brand']} • Stock: ${product['stock']}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '₹${product['price']}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            IconButton(
              icon: Icon(
                isWishlisted ? Icons.favorite : Icons.favorite_border,
                color: isWishlisted ? Colors.red : null,
              ),
              onPressed: () => _toggleWishlist(product['id']),
            ),
            IconButton(
              icon: const Icon(Icons.add_shopping_cart),
              onPressed: isOutOfStock ? null : () => _addToCart(product['id']),
            ),
          ],
        ),
        onTap: () => _viewProduct(product),
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).dividerColor.withOpacity(0.1),
          ),
        ),
      ),
      child: Column(
        children: [
          Text(
            'Raj Electricals & Hardware',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            '© ${DateTime.now().year} All Rights Reserved',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  void _viewProduct(Map<String, dynamic> product) {
    if (!_recentlyViewed.contains(product['id'])) {
      setState(() {
        _recentlyViewed.add(product['id']);
        if (_recentlyViewed.length > 10) {
          _recentlyViewed.removeAt(0);
        }
      });
    }

    // Show product details dialog
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(product['name']),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Brand: ${product['brand']}'),
              Text('Category: ${product['category']}'),
              Text('Price: ₹${product['price']}'),
              Text('Stock: ${product['stock']}'),
              const SizedBox(height: 8),
              Text(product['description'] ?? 'No description available'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
            if (product['stock'] > 0)
              FilledButton(
                onPressed: () {
                  _addToCart(product['id']);
                  Navigator.of(context).pop();
                },
                child: const Text('Add to Cart'),
              ),
          ],
        );
      },
    );
  }

  void _showCart() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Shopping Cart',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _cartItems.isEmpty
                    ? const Center(child: Text('Cart is empty'))
                    : ListView.builder(
                        itemCount: _cartItems.length,
                        itemBuilder: (context, index) {
                          final item = _cartItems[index];
                          return ListTile(
                            title: Text(item['name']),
                            subtitle: Text(
                              '₹${item['price']} x ${item['qty']}',
                            ),
                            trailing: Text(
                              '₹${item['price'] * item['qty']}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          );
                        },
                      ),
              ),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Total', style: Theme.of(context).textTheme.titleMedium),
                  Text(
                    '₹${_cartItems.fold(0.0, (sum, item) => sum + (item['price'] * item['qty']))}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _cartItems.isEmpty
                      ? null
                      : () {
                          // TODO: Implement checkout
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Checkout not implemented yet'),
                            ),
                          );
                        },
                  child: const Text('Checkout'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
