import 'package:flutter/material.dart';
import '../widgets/page_header.dart';
import '../widgets/search_bar_widget.dart';
import '../data/app_database.dart';

class PurchasePage extends StatefulWidget {
  final AppDatabase db;

  const PurchasePage({super.key, required this.db});

  @override
  State<PurchasePage> createState() => _PurchasePageState();
}

class _PurchasePageState extends State<PurchasePage> {
  String _searchTerm = '';
  String _selectedSupplier = '';
  final List<Map<String, dynamic>> _purchaseItems = [];
  double _totalAmount = 0.0;
  double _discount = 0.0;
  double _tax = 0.0;

  // Filters & sorting
  String _activeFilter = 'All';
  String _sortBy = 'Name'; // Name, Last Price
  bool _isGridView = true; // default to grid like SvelteKit

  // Supplier details
  final TextEditingController _invoiceController = TextEditingController();
  final TextEditingController _supplierController = TextEditingController();
  final TextEditingController _discountController = TextEditingController();
  DateTime _purchaseDate = DateTime.now();
  String _paymentMethod = 'Cash';

  // Supplier suggestions
  final List<String> _supplierSuggestions = [
    'Raj Electricals Wholesale',
    'Bright Light Distributors',
    'National Wires & Cables',
    'Modern Electronics Supply',
    'Power Tech Solutions',
  ];

  // Mock products for purchase
  final List<Map<String, dynamic>> _mockProducts = [
    {
      'id': 1,
      'name': 'REO Ceiling Fan',
      'brand': 'Havells',
      'category': 'Electronics',
      'size_or_spec': '1200MM',
      'unit_type_single': 'Piece',
      'last_purchase_price': 2200,
      'image': '🪭',
    },
    {
      'id': 2,
      'name': 'LED Bulb 9W',
      'brand': 'Philips',
      'category': 'Lighting',
      'size_or_spec': '9W',
      'unit_type_single': 'Piece',
      'last_purchase_price': 120,
      'image': '💡',
    },
    {
      'id': 3,
      'name': 'Copper Wire',
      'brand': 'Finolex',
      'category': 'Cables & Wires',
      'size_or_spec': '2.5 sq mm',
      'unit_type_single': 'Meter',
      'last_purchase_price': 65,
      'image': '🔌',
    },
    {
      'id': 4,
      'name': 'Switch Board 6M',
      'brand': 'Anchor',
      'category': 'Switches',
      'size_or_spec': '6 Module',
      'unit_type_single': 'Piece',
      'last_purchase_price': 380,
      'image': '🔘',
    },
    {
      'id': 5,
      'name': 'PVC Tape',
      'brand': '3M',
      'category': 'Accessories',
      'size_or_spec': '19mm x 20m',
      'unit_type_single': 'Roll',
      'last_purchase_price': 20,
      'image': '📼',
    },
  ];

  List<Map<String, dynamic>> get _filteredProducts {
    final list = _mockProducts.where((product) {
      final searchLower = _searchTerm.toLowerCase();
      final matchesSearch =
          _searchTerm.isEmpty ||
          product['name'].toString().toLowerCase().contains(searchLower) ||
          (product['brand']?.toString().toLowerCase().contains(searchLower) ??
              false) ||
          (product['category']?.toString().toLowerCase().contains(
                searchLower,
              ) ??
              false);
      final matchesFilter =
          _activeFilter == 'All' || product['category'] == _activeFilter;
      return matchesSearch && matchesFilter;
    }).toList();
    switch (_sortBy) {
      case 'Last Price':
        list.sort(
          (a, b) => (a['last_purchase_price'] as num).compareTo(
            b['last_purchase_price'] as num,
          ),
        );
        break;
      default:
        list.sort(
          (a, b) => a['name'].toString().toLowerCase().compareTo(
            b['name'].toString().toLowerCase(),
          ),
        );
    }
    return list;
  }

  List<String> get _categories {
    final set = <String>{};
    for (final p in _mockProducts) {
      final c = p['category']?.toString();
      if (c != null && c.isNotEmpty) set.add(c);
    }
    final list = set.toList()..sort();
    return ['All', ...list];
  }

  void _addToPurchase(Map<String, dynamic> product) {
    final existingIndex = _purchaseItems.indexWhere(
      (item) => item['id'] == product['id'],
    );

    if (existingIndex >= 0) {
      setState(() {
        _purchaseItems[existingIndex]['quantity']++;
        _updateTotalAmount();
      });
    } else {
      setState(() {
        _purchaseItems.add({
          ...product,
          'quantity': 1,
          'purchase_price': product['last_purchase_price'],
        });
        _updateTotalAmount();
      });
    }
  }

  void _updateQuantity(int index, int newQuantity) {
    if (newQuantity <= 0) {
      setState(() {
        _purchaseItems.removeAt(index);
        _updateTotalAmount();
      });
    } else {
      setState(() {
        _purchaseItems[index]['quantity'] = newQuantity;
        _updateTotalAmount();
      });
    }
  }

  void _updateTotalAmount() {
    final subtotal = _purchaseItems.fold(
      0.0,
      (sum, item) => sum + (item['quantity'] * item['purchase_price']),
    );
    _tax = subtotal * 0.18; // 18% GST
    _totalAmount = subtotal + _tax - _discount;
  }

  void _updateDiscount(String value) {
    final discount = double.tryParse(value) ?? 0.0;
    setState(() {
      _discount = discount;
      _updateTotalAmount();
    });
  }

  double get _subtotal {
    return _purchaseItems.fold(
      0.0,
      (sum, item) => sum + (item['quantity'] * item['purchase_price']),
    );
  }

  Future<void> _showConfirmPurchaseDialog() async {
    final itemCount = _purchaseItems.fold<int>(
      0,
      (sum, i) => sum + (i['quantity'] as int),
    );
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Confirm Purchase'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.business, size: 18, color: Colors.grey),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _selectedSupplier.isEmpty
                          ? 'No supplier specified'
                          : _selectedSupplier,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.receipt_long, size: 18, color: Colors.grey),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _invoiceController.text.isEmpty
                          ? 'No invoice number'
                          : _invoiceController.text,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.event, size: 18, color: Colors.grey),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${_purchaseDate.day}/${_purchaseDate.month}/${_purchaseDate.year}',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.payment, size: 18, color: Colors.grey),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Payment: $_paymentMethod')),
                ],
              ),
              const Divider(height: 20),
              Text('Items: $itemCount'),
              Text(
                'Total: ₹${_totalAmount.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _processPurchase();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                foregroundColor: Colors.white,
              ),
              child: const Text('Confirm'),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _invoiceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Page Header
            PageHeader(
              title: 'Record Purchase',
              description: 'Add new stock from suppliers',
              icon: '📦',
              showBackButton: true,
              breadcrumbs: [
                PageHeaderBreadcrumb(label: 'Dashboard', icon: '🏠'),
                PageHeaderBreadcrumb(
                  label: 'Record Purchase',
                  icon: '📦',
                  current: true,
                ),
              ],
              stats: [
                PageHeaderStat(
                  label: 'Purchase Items',
                  value: '${_purchaseItems.length} products',
                  description: 'Items to purchase',
                ),
                PageHeaderStat(
                  label: 'Total Cost',
                  value: '₹${_totalAmount.toStringAsFixed(0)}',
                  description: 'Purchase value',
                ),
              ],
              actions: [
                PageHeaderAction(
                  label: 'Purchase History',
                  shortLabel: 'History',
                  icon: Icons.history,
                  color: const Color(0xFF7C3AED),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Purchase history coming soon!'),
                      ),
                    );
                  },
                ),
              ],
            ),

            // Main Content
            Padding(
              padding: const EdgeInsets.all(24),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth > 1024) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 2, child: _buildProductSelection()),
                        const SizedBox(width: 24),
                        Expanded(flex: 1, child: _buildPurchaseSummary()),
                      ],
                    );
                  } else {
                    return Column(
                      children: [
                        _buildProductSelection(),
                        const SizedBox(height: 24),
                        _buildPurchaseSummary(),
                      ],
                    );
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductSelection() {
    return Column(
      children: [
        // Supplier Selection
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '🏢 Supplier Information',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                decoration: InputDecoration(
                  hintText: 'Enter supplier name or company',
                  prefixIcon: const Icon(Icons.business, color: Colors.grey),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: Colors.grey.withValues(alpha: 0.3),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: Colors.grey.withValues(alpha: 0.3),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Colors.blue, width: 2),
                  ),
                ),
                onChanged: (value) {
                  setState(() {
                    _selectedSupplier = value;
                  });
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  // Invoice number
                  Expanded(
                    child: TextField(
                      controller: _invoiceController,
                      decoration: InputDecoration(
                        hintText: 'Invoice No.',
                        prefixIcon: const Icon(
                          Icons.receipt_long,
                          color: Colors.grey,
                        ),
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: Colors.grey.withValues(alpha: 0.3),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: Colors.grey.withValues(alpha: 0.3),
                          ),
                        ),
                        focusedBorder: const OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(8)),
                          borderSide: BorderSide(color: Colors.blue, width: 2),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Purchase date
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        final now = DateTime.now();
                        final picked = await showDatePicker(
                          context: context,
                          firstDate: DateTime(now.year - 1),
                          lastDate: DateTime(now.year + 2),
                          initialDate: _purchaseDate ?? now,
                        );
                        if (picked != null) {
                          setState(() => _purchaseDate = picked);
                        }
                      },
                      child: InputDecorator(
                        decoration: InputDecoration(
                          hintText: 'Purchase Date',
                          prefixIcon: const Icon(
                            Icons.event,
                            color: Colors.grey,
                          ),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: Colors.grey.withValues(alpha: 0.3),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: Colors.grey.withValues(alpha: 0.3),
                            ),
                          ),
                        ),
                        child: Text(
                          '${_purchaseDate.day}/${_purchaseDate.month}/${_purchaseDate.year}',
                          style: TextStyle(color: Colors.grey.shade800),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Payment method
              Row(
                children: [
                  Expanded(
                    child: InputDecorator(
                      decoration: InputDecoration(
                        hintText: 'Payment Method',
                        prefixIcon: const Icon(
                          Icons.payment,
                          color: Colors.grey,
                        ),
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: Colors.grey.withValues(alpha: 0.3),
                          ),
                        ),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _paymentMethod,
                          items: const [
                            DropdownMenuItem(
                              value: 'Cash',
                              child: Text('Cash'),
                            ),
                            DropdownMenuItem(value: 'UPI', child: Text('UPI')),
                            DropdownMenuItem(
                              value: 'Card',
                              child: Text('Card'),
                            ),
                            DropdownMenuItem(
                              value: 'Bank',
                              child: Text('Bank Transfer'),
                            ),
                          ],
                          onChanged: (v) =>
                              setState(() => _paymentMethod = v ?? 'Cash'),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // Search Bar
        SearchBarWidget(
          placeholder: 'Search products to purchase...',
          onSearchChanged: (value) {
            setState(() {
              _searchTerm = value;
            });
          },
          resultCount: _searchTerm.isNotEmpty ? _filteredProducts.length : null,
          totalCount: _searchTerm.isNotEmpty ? _mockProducts.length : null,
        ),

        const SizedBox(height: 24),

        // Category Filters + Toolbar
        _buildFiltersAndToolbar(),
        const SizedBox(height: 16),

        // Products Grid
        _buildProductsSection(),
      ],
    );
  }

  Widget _buildProductsSection() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.purple.withValues(alpha: 0.05),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
              border: Border(
                bottom: BorderSide(color: Colors.purple.withValues(alpha: 0.1)),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '📦 Available Products',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Select items to purchase',
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Text(
                      '${_filteredProducts.length}',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.purple,
                      ),
                    ),
                    const SizedBox(width: 12),
                    DropdownButton<String>(
                      value: _sortBy,
                      items: const [
                        DropdownMenuItem(
                          value: 'Name',
                          child: Text('Sort: Name'),
                        ),
                        DropdownMenuItem(
                          value: 'Last Price',
                          child: Text('Sort: Last Price'),
                        ),
                      ],
                      onChanged: (v) => setState(() => _sortBy = v ?? 'Name'),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: 'List view',
                      onPressed: _isGridView
                          ? () => setState(() => _isGridView = false)
                          : null,
                      icon: const Icon(Icons.view_list),
                    ),
                    IconButton(
                      tooltip: 'Grid view',
                      onPressed: _isGridView
                          ? null
                          : () => setState(() => _isGridView = true),
                      icon: const Icon(Icons.grid_view),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Products List
          if (_filteredProducts.isEmpty)
            _buildEmptyProductState()
          else
            Padding(
              padding: const EdgeInsets.all(16),
              child: _isGridView
                  ? _buildProductGridLayout(_filteredProducts)
                  : Column(
                      children: _filteredProducts
                          .map((product) => _buildProductCard(product))
                          .toList(),
                    ),
            ),
        ],
      ),
    );
  }

  Widget _buildProductGridLayout(List<Map<String, dynamic>> products) {
    return LayoutBuilder(
      builder: (context, constraints) {
        int crossAxisCount = 1;
        double aspect = 3.0;
        if (constraints.maxWidth >= 1200) {
          crossAxisCount = 3;
          aspect = 2.6;
        } else if (constraints.maxWidth >= 992) {
          crossAxisCount = 2;
          aspect = 2.8;
        } else {
          crossAxisCount = 1;
          aspect = 3.2;
        }

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: aspect,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: products.length,
          itemBuilder: (context, index) => _buildProductCard(products[index]),
        );
      },
    );
  }

  Widget _buildFiltersAndToolbar() {
    final categories = [
      'All',
      ...{for (final p in _mockProducts) p['category'] as String},
    ];
    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: categories.map((c) {
          final selected = _activeFilter == c;
          return ChoiceChip(
            label: Text(c),
            selected: selected,
            onSelected: (_) => setState(() => _activeFilter = c),
            selectedColor: Colors.purple.withValues(alpha: 0.08),
            labelStyle: TextStyle(
              color: selected ? Colors.purple : Colors.grey.shade800,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
            side: BorderSide(
              color: selected
                  ? Colors.purple.withValues(alpha: 0.3)
                  : Colors.grey.shade300,
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildProductCard(Map<String, dynamic> product) {
    final isInCart = _purchaseItems.any((item) => item['id'] == product['id']);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isInCart ? Colors.purple.withValues(alpha: 0.05) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isInCart
              ? Colors.purple.withValues(alpha: 0.3)
              : Colors.grey.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          // Product Image
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
            ),
            child: const Center(
              child: Text('📦', style: TextStyle(fontSize: 20)),
            ),
          ),

          const SizedBox(width: 12),

          // Product Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        product['name'],
                        style: const TextStyle(fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '₹${product['last_purchase_price']}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.purple,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (product['brand'] != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '🏷️ ${product['brand']}',
                          style: const TextStyle(fontSize: 10),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Last: ₹${product['last_purchase_price']}',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.blue,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(width: 12),

          // Add Button
          ElevatedButton.icon(
            onPressed: () => _addToPurchase(product),
            icon: Icon(isInCart ? Icons.check : Icons.add, size: 16),
            label: Text(isInCart ? 'Added' : 'Add'),
            style: ElevatedButton.styleFrom(
              backgroundColor: isInCart ? Colors.purple : Colors.blue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyProductState() {
    return Container(
      padding: const EdgeInsets.all(48),
      child: Column(
        children: [
          const Text('🔍', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 16),
          Text(
            _searchTerm.isNotEmpty
                ? 'No products found matching "$_searchTerm"'
                : 'No products available',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _searchTerm.isNotEmpty
                ? 'Try adjusting your search terms.'
                : 'Add products to catalog first.',
            style: TextStyle(color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildPurchaseSummary() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.purple.withValues(alpha: 0.05),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
              border: Border(
                bottom: BorderSide(color: Colors.purple.withValues(alpha: 0.1)),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.purple.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.purple.withValues(alpha: 0.2),
                    ),
                  ),
                  child: const Text('📦', style: TextStyle(fontSize: 16)),
                ),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Purchase Summary',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    Text(
                      'Review and complete',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Purchase Items
          if (_purchaseItems.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '📋 Items to Purchase',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...(_purchaseItems.asMap().entries.map(
                    (entry) => _buildPurchaseItem(entry.key, entry.value),
                  )),
                ],
              ),
            ),

            // Total Section
            Container(
              margin: const EdgeInsets.all(20),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.purple.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.purple.withValues(alpha: 0.2)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Total Cost:',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '₹${_totalAmount.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.purple,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _purchaseItems.isNotEmpty
                          ? _showConfirmPurchaseDialog
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purple,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        'Complete Purchase',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else
            Container(
              padding: const EdgeInsets.all(40),
              child: const Column(
                children: [
                  Text('📦', style: TextStyle(fontSize: 48)),
                  SizedBox(height: 16),
                  Text(
                    'No items selected',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Add products to start a purchase',
                    style: TextStyle(color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPurchaseItem(int index, Map<String, dynamic> item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['name'],
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '₹${item['purchase_price']} each',
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                onPressed: () => _updateQuantity(index, item['quantity'] - 1),
                icon: const Icon(Icons.remove, size: 16),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.grey.withValues(alpha: 0.1),
                  minimumSize: const Size(24, 24),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  '${item['quantity']}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                onPressed: () => _updateQuantity(index, item['quantity'] + 1),
                icon: const Icon(Icons.add, size: 16),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.purple.withValues(alpha: 0.1),
                  minimumSize: const Size(24, 24),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _processPurchase() {
    // Show success message
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Purchase recorded! Total: ₹${_totalAmount.toStringAsFixed(2)}',
        ),
        backgroundColor: Colors.purple,
        duration: const Duration(seconds: 3),
      ),
    );

    // Clear purchase items
    setState(() {
      _purchaseItems.clear();
      _totalAmount = 0.0;
      _selectedSupplier = '';
    });
  }
}
