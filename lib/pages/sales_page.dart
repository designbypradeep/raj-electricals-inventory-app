import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/supabase_models.dart' as supabase;
import '../services/supabase_service.dart';
import '../services/connectivity_service.dart';
import '../widgets/page_header.dart';
import '../widgets/product_search_field.dart';
import '../services/receipt_service.dart';

class SalesPage extends StatefulWidget {
  const SalesPage({super.key});

  @override
  State<SalesPage> createState() => _SalesPageState();
}

class SaleItem {
  final int productId;
  final String name;
  final int quantity;
  final double pricePerUnit;
  final String unit;
  final String? itemCode;

  SaleItem({
    required this.productId,
    required this.name,
    required this.quantity,
    required this.pricePerUnit,
    required this.unit,
    this.itemCode,
  });

  Map<String, dynamic> toJson() => {
    'product_id': productId,
    'name': name,
    'quantity': quantity,
    'price_per_unit': pricePerUnit,
    'unit': unit,
    'item_code': itemCode,
  };
}

class SaleReceipt {
  final String saleId;
  final String customerName;
  final String? customerPhone;
  final String? transactionId;
  final List<SaleItem> items;
  final double subTotal;
  final double discount;
  final double finalTotal;
  final String paymentMethod;
  final DateTime saleDate;

  SaleReceipt({
    required this.saleId,
    required this.customerName,
    this.customerPhone,
    this.transactionId,
    required this.items,
    required this.subTotal,
    required this.discount,
    required this.finalTotal,
    required this.paymentMethod,
    required this.saleDate,
  });
}

class _SalesPageState extends State<SalesPage> {
  List<supabase.Product> _products = [];
  final List<SaleItem> _salesItems = [];
  bool _isLoading = true;
  bool _isProcessing = false;
  String? _errorMessage;

  // Product selection
  int? _selectedProductId;
  String _selectedUnit = '';
  int _quantity = 1;
  supabase.Product? _selectedProductObj;
  double _pricePerUnit = 0.0;

  // Payment details
  double _discount = 0.0;
  String _paymentMethod = 'Cash';
  double _paidNow = 0.0;
  bool _useAdvance = false;

  // Receipt data
  SaleReceipt? _receipt;

  // Customer details
  final TextEditingController _customerNameController = TextEditingController();
  final TextEditingController _customerPhoneController =
      TextEditingController();
  final TextEditingController _transactionIdController =
      TextEditingController();
  final TextEditingController _discountController = TextEditingController();
  final TextEditingController _paidNowController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _quantityController = TextEditingController(
    text: '1',
  );
  DateTime? _customDate;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Widget _buildPriceField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Price per Unit (₹)',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Theme.of(context).textTheme.bodyLarge?.color,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _priceController,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
          ],
          onChanged: (value) {
            setState(() {
              _pricePerUnit = double.tryParse(value) ?? 0.0;
            });
          },
          decoration: InputDecoration(
            hintText: (_selectedProductObj?.sellingPrice ?? 0) > 0
                ? (_selectedProductObj!.sellingPrice!.toStringAsFixed(
                    ((_selectedProductObj!.sellingPrice! % 1 == 0) ? 0 : 2),
                  ))
                : '0',
            filled: true,
            fillColor: Theme.of(context).scaffoldBackgroundColor,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: Theme.of(context).colorScheme.primary,
                width: 2,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 14,
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _customerNameController.dispose();
    _customerPhoneController.dispose();
    _transactionIdController.dispose();
    _discountController.dispose();
    _paidNowController.dispose();
    _paidNowController.dispose();
    _priceController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    try {
      final products = await SupabaseService.getProducts();
      setState(() {
        _products = products;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading products: $e')));
      }
    }
  }

  supabase.Product? get _selectedProductForSale {
    if (_selectedProductObj != null) return _selectedProductObj;
    if (_selectedProductId == null) return null;
    try {
      return _products.firstWhere((p) => p.id == _selectedProductId);
    } catch (e) {
      return null;
    }
  }

  void _handleAddProduct() {
    setState(() {
      _errorMessage = null;
    });

    if (_selectedProductId == null || _quantity <= 0 || _selectedUnit.isEmpty) {
      setState(() {
        _errorMessage =
            'Please select a product, unit and enter a valid quantity.';
      });
      _clearErrorAfterDelay();
      return;
    }

    final selectedProduct = _selectedProductForSale;
    if (selectedProduct == null) return;

    if ((_pricePerUnit) <= 0) {
      setState(() {
        _errorMessage = 'Enter a valid price per unit.';
      });
      _clearErrorAfterDelay();
      return;
    }

    // Calculate stock check based on unit type
    final num availableStock = selectedProduct.currentStock;
    int quantityInSingleUnits = _quantity;

    // If selling in wholesale units, convert to single units for stock checking
    if (_selectedUnit == selectedProduct.unitTypeWholesale) {
      quantityInSingleUnits =
          _quantity * (selectedProduct.itemsPerWholesaleUnit ?? 1);
    }

    if (quantityInSingleUnits > availableStock) {
      final maxWholesale = _selectedUnit == selectedProduct.unitTypeWholesale
          ? (availableStock / (selectedProduct.itemsPerWholesaleUnit ?? 1))
                .floor()
          : availableStock.toInt();
      setState(() {
        _errorMessage =
            'Not enough stock. Only $maxWholesale $_selectedUnit available.';
      });
      _clearErrorAfterDelay();
      return;
    }

    if (_salesItems.any((item) => item.productId == _selectedProductId)) {
      setState(() {
        _errorMessage = 'This product is already in the list.';
      });
      _clearErrorAfterDelay();
      return;
    }

    setState(() {
      _salesItems.add(
        SaleItem(
          productId: selectedProduct.id!,
          name:
              '${selectedProduct.brand ?? ''} ${selectedProduct.name} ${selectedProduct.sizeOrSpec ?? ''}'
                  .trim(),
          quantity: _quantity,
          pricePerUnit: _pricePerUnit,
          unit: _selectedUnit,
          itemCode: selectedProduct.itemCode,
        ),
      );

      // Reset form for next item
      _selectedProductId = null;
      _quantity = 1;
      _selectedUnit = '';
      _selectedProductObj = null;
      _pricePerUnit = 0.0;
      _selectedProductObj = null;
      _pricePerUnit = 0.0;
      _priceController.text = '';
      _quantityController.text = '1';
    });
  }

  void _clearErrorAfterDelay() {
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _errorMessage = null;
        });
      }
    });
  }

  void _removeItem(int productId) {
    setState(() {
      _salesItems.removeWhere((item) => item.productId == productId);
    });
  }

  void _startNewSale() {
    setState(() {
      _salesItems.clear();
      _discount = 0;
      _receipt = null;
      _paidNow = 0.0;
      _useAdvance = false;
      _customerNameController.clear();
      _customerPhoneController.clear();
      _transactionIdController.clear();
      _discountController.clear();
      _paidNowController.clear();
      _paymentMethod = 'Cash';
      _customDate = null;
      _quantity = 1;
      _quantityController.text = '1';
    });
  }

  double get _subTotal {
    return _salesItems.fold(
      0.0,
      (sum, item) => sum + (item.quantity * item.pricePerUnit),
    );
  }

  double get _finalTotal {
    final total = _subTotal - _discount;
    return total < 0 ? 0 : total;
  }

  Future<void> _completeSale() async {
    if (!ConnectivityService().isOnline.value) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: const [
                Icon(Icons.wifi_off, color: Colors.white),
                SizedBox(width: 8),
                Text('You are offline. Cannot complete sale.'),
              ],
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }
    if (_salesItems.isEmpty) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      // Map payment method to lowercase tokens commonly used in DB
      String paymentToken = _paymentMethod.trim().toLowerCase();
      if (paymentToken == 'upi' ||
          paymentToken == 'cash' ||
          paymentToken == 'card') {
        // ok
      } else {
        // Default to cash if unknown label
        paymentToken = 'cash';
      }

      final itemsPayload = _salesItems
          .map(
            (it) => {
              'product_id': it.productId,
              'quantity': it.quantity,
              'price_per_unit': it.pricePerUnit,
              'unit': it.unit,
            },
          )
          .toList();

      final computedPaid = _paidNowController.text.trim().isEmpty
          ? (_paymentMethod.trim().toLowerCase() == 'credit'
                ? 0.0
                : _finalTotal)
          : _paidNow;

      final newSaleId = await SupabaseService.createSaleWithItems(
        customerName: _customerNameController.text.isEmpty
            ? 'Walk-in Customer'
            : _customerNameController.text.trim(),
        customerPhone: _customerPhoneController.text.trim().isEmpty
            ? null
            : _customerPhoneController.text.trim(),
        transactionId: _transactionIdController.text.trim().isEmpty
            ? null
            : _transactionIdController.text.trim(),
        createdAt: _customDate, // optional custom date
        paymentMethod: paymentToken,
        totalAmount: _finalTotal,
        discountAmount: _discount,
        taxAmount: null,
        items: itemsPayload,
        amountPaid: computedPaid,
        useAdvance: _useAdvance,
      );

      if (newSaleId == null) {
        throw Exception('Sale was not created');
      }

      setState(() {
        _receipt = SaleReceipt(
          saleId: newSaleId.toString(),
          customerName: _customerNameController.text.isEmpty
              ? 'Walk-in Customer'
              : _customerNameController.text.trim(),
          customerPhone: _customerPhoneController.text.trim().isEmpty
              ? null
              : _customerPhoneController.text.trim(),
          transactionId: _transactionIdController.text.trim().isEmpty
              ? null
              : _transactionIdController.text.trim(),
          items: List.from(_salesItems),
          subTotal: _subTotal,
          discount: _discount,
          finalTotal: _finalTotal,
          paymentMethod: _paymentMethod,
          saleDate: _customDate ?? DateTime.now(),
        );
        _isProcessing = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Sale completed successfully! Invoice: ${newSaleId.toString()}',
          ),
          backgroundColor: Theme.of(context).colorScheme.secondary,
        ),
      );
    } catch (e) {
      setState(() {
        _isProcessing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to complete sale: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _shareOnWhatsApp() async {
    if (_receipt == null) return;

    final phone = _receipt!.customerPhone ?? '';
    if (phone.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No customer phone number available')),
      );
      return;
    }

    // Compose a brief message; user can send the PDF via the Download/Share button
    final msg =
        'Thank you for your purchase! Invoice ${_receipt!.saleId} — '
        'Total: ₹${_receipt!.finalTotal.toStringAsFixed(2)}';
    final encoded = Uri.encodeComponent(msg);

    // Prefer whatsapp:// scheme (opens app directly); fallback to wa.me
    final direct = Uri.parse('whatsapp://send?phone=91$phone&text=$encoded');
    final web = Uri.parse('https://wa.me/91$phone?text=$encoded');

    try {
      if (await canLaunchUrl(direct)) {
        await launchUrl(direct, mode: LaunchMode.externalApplication);
        return;
      }
      if (await canLaunchUrl(web)) {
        await launchUrl(web, mode: LaunchMode.externalApplication);
        return;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('WhatsApp is not installed or unavailable'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not open WhatsApp: $e')));
      }
    }
  }

  Future<void> _generatePdf() async {
    if (_receipt == null) return;
    try {
      final data = _buildReceiptDataFromState();
      await ReceiptService.shareReceiptPdf(data);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to generate PDF: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  ReceiptData _buildReceiptDataFromState() {
    final r = _receipt!;
    return ReceiptData(
      saleId: r.saleId,
      customerName: r.customerName,
      customerPhone: r.customerPhone,
      transactionId: r.transactionId,
      items: r.items
          .map(
            (it) => ReceiptItem(
              name: it.name,
              quantity: it.quantity,
              pricePerUnit: it.pricePerUnit,
              itemCode: it.itemCode,
            ),
          )
          .toList(),
      subTotal: r.subTotal,
      discount: r.discount,
      finalTotal: r.finalTotal,
      paymentMethod: r.paymentMethod,
      saleDate: r.saleDate,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).scaffoldBackgroundColor,
              Theme.of(context).scaffoldBackgroundColor,
              Theme.of(context).dividerColor.withValues(alpha: 0.05),
            ],
          ),
        ),
        child: SafeArea(
          top: false,
          bottom: true,
          child: SingleChildScrollView(
            child: Column(
              children: [
                // Page Header - Exact SvelteKit structure
                PageHeader(
                  title: 'Record Sale',
                  description:
                      'Create new sales transactions and manage customer orders',
                  icon: '🛒',
                  showBackButton: true,
                  backLabel: 'Back to Dashboard',
                  wrapInSafeArea: true,
                  breadcrumbs: [
                    PageHeaderBreadcrumb(label: 'Dashboard', icon: '🏠', href: '/'),
                    if (MediaQuery.of(context).size.width >= 450)
                      PageHeaderBreadcrumb(
                        label: 'Record Sale',
                        icon: '🛒',
                        current: true,
                      ),
                  ],
                  stats: [
                    PageHeaderStat(
                      label: 'Items in Cart',
                      value: '${_salesItems.length}',
                      description: _salesItems.isEmpty
                          ? 'Cart is empty'
                          : 'Ready for billing',
                    ),
                    PageHeaderStat(
                      label: 'Cart Total',
                      value: '₹${_finalTotal.toStringAsFixed(0)}',
                      description: _paymentMethod.isNotEmpty
                          ? 'Payment: $_paymentMethod'
                          : 'Pending payment',
                    ),
                  ],
                  actions: [
                    PageHeaderAction(
                      label: 'Sales History',
                      shortLabel: 'History',
                      icon: Icons.history,
                      color: Theme.of(context).colorScheme.primary,
                      onPressed: () =>
                          Navigator.pushNamed(context, '/sales-history'),
                    ),
                  ],
                ),
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: MediaQuery.of(context).size.width < 480 ? 12 : 16,
                    vertical: MediaQuery.of(context).size.width < 480 ? 16 : 24,
                  ),
                  child: Column(
                    children: [
                      // Conditional display: Receipt or Sale Form (exact SvelteKit pattern)
                      _receipt != null ? _buildSuccessReceipt() : _buildSaleForm(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSuccessReceipt() {
    if (_receipt == null) return const SizedBox();

    return Container(
      padding: EdgeInsets.all(
        MediaQuery.of(context).size.width < 480 ? 20 : 32,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).shadowColor.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Success Header - Exact SvelteKit styling
          Text(
            '✅ Sale Recorded!',
            style: TextStyle(
              fontSize: MediaQuery.of(context).size.width < 480 ? 24 : 32,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.secondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),

          // Receipt Details Container - SvelteKit card styling
          Container(
            padding: EdgeInsets.all(
              MediaQuery.of(context).size.width < 480 ? 16 : 24,
            ),
            decoration: BoxDecoration(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildReceiptRow('Customer:', _receipt!.customerName),
                if (_receipt!.customerPhone != null)
                  _buildReceiptRow('Phone:', _receipt!.customerPhone!),

                Divider(
                  color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
                  height: 32,
                ),

                Text(
                  'Items:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Theme.of(context).textTheme.titleMedium?.color,
                  ),
                ),
                const SizedBox(height: 12),

                // Items list
                ..._receipt!.items.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      '${item.name} - ${item.quantity} ${item.unit} @ ₹${item.pricePerUnit.toStringAsFixed(2)}',
                      style: TextStyle(
                        color: Theme.of(context).textTheme.bodyMedium?.color,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),

                Divider(
                  color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
                  height: 32,
                ),

                _buildReceiptRow(
                  'Subtotal:',
                  '₹${_receipt!.subTotal.toStringAsFixed(2)}',
                ),
                _buildReceiptRow(
                  'Discount:',
                  '- ₹${_receipt!.discount.toStringAsFixed(2)}',
                ),
                if (_receipt!.paymentMethod.isNotEmpty)
                  _buildReceiptRow('Paid via:', _receipt!.paymentMethod),

                const SizedBox(height: 16),
                _buildReceiptRow(
                  'Final Total:',
                  '₹${_receipt!.finalTotal.toStringAsFixed(2)}',
                  isTotal: true,
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // Action Buttons - SvelteKit grid layout
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth > 600) {
                // Desktop: 3 columns
                return Row(
                  children: [
                    Expanded(
                      child: _buildActionButton(
                        onPressed: _startNewSale,
                        icon: Icons.refresh,
                        label: 'Start New Sale',
                        variant: 'outline',
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildActionButton(
                        onPressed: _generatePdf,
                        icon: Icons.picture_as_pdf,
                        label: 'Download PDF',
                        variant: 'primary',
                      ),
                    ),
                    if (_receipt!.customerPhone != null) ...[
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildActionButton(
                          onPressed: _shareOnWhatsApp,
                          icon: Icons.share,
                          label: 'Share on WhatsApp',
                          variant: 'whatsapp',
                        ),
                      ),
                    ],
                  ],
                );
              } else {
                // Mobile: Stacked
                return Column(
                  children: [
                    _buildActionButton(
                      onPressed: _startNewSale,
                      icon: Icons.refresh,
                      label: 'Start New Sale',
                      variant: 'outline',
                    ),
                    const SizedBox(height: 12),
                    _buildActionButton(
                      onPressed: _generatePdf,
                      icon: Icons.picture_as_pdf,
                      label: 'Download PDF',
                      variant: 'primary',
                    ),
                    if (_receipt!.customerPhone != null) ...[
                      const SizedBox(height: 12),
                      _buildActionButton(
                        onPressed: _shareOnWhatsApp,
                        icon: Icons.share,
                        label: 'Share on WhatsApp',
                        variant: 'whatsapp',
                      ),
                    ],
                  ],
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildReceiptRow(String label, String value, {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: isTotal ? FontWeight.bold : FontWeight.w500,
              fontSize: isTotal ? 18 : 14,
              color: Theme.of(context).textTheme.bodyMedium?.color,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: isTotal ? FontWeight.bold : FontWeight.w600,
              fontSize: isTotal ? 20 : 14,
              color: isTotal
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).textTheme.bodyMedium?.color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required VoidCallback onPressed,
    required IconData icon,
    required String label,
    required String variant,
  }) {
    Color backgroundColor;
    Color foregroundColor;
    BorderSide? border;

    switch (variant) {
      case 'outline':
        backgroundColor = Theme.of(context).cardColor;
        foregroundColor =
            Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black;
        border = BorderSide(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
        );
        break;
      case 'primary':
        backgroundColor = Theme.of(context).colorScheme.primary;
        foregroundColor = Theme.of(context).colorScheme.onPrimary;
        border = null;
        break;
      case 'whatsapp':
        backgroundColor = const Color(0xFF25D366);
        foregroundColor = Colors.white;
        border = null;
        break;
      default:
        backgroundColor = Theme.of(context).colorScheme.primary;
        foregroundColor = Theme.of(context).colorScheme.onPrimary;
        border = null;
    }

    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        label: Text(
          label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          side: border,
          elevation: variant == 'outline' ? 0 : 2,
          shadowColor: backgroundColor.withValues(alpha: 0.3),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }

  Widget _buildSaleForm() {
    final isMobile = MediaQuery.of(context).size.width < 600;
    return Container(
      padding: EdgeInsets.all(isMobile ? 12 : 24),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).shadowColor.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Customer Details Section - Exact SvelteKit styling
          Container(
            padding: EdgeInsets.all(isMobile ? 12 : 20),
            margin: EdgeInsets.only(bottom: isMobile ? 16 : 24),
            decoration: BoxDecoration(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header with icon - SvelteKit pattern
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
                      child: Center(
                        child: Text(
                          '👤',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Sale Details',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).textTheme.titleLarge?.color,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Responsive grid layout - SvelteKit pattern
                LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth > 768) {
                      // Desktop: 3 columns
                      return Row(
                        children: [
                          Expanded(child: _buildCustomerNameField()),
                          const SizedBox(width: 24),
                          Expanded(child: _buildCustomerPhoneField()),
                          const SizedBox(width: 24),
                          Expanded(child: _buildSaleDateField()),
                        ],
                      );
                    } else if (constraints.maxWidth > 480) {
                      // Tablet: 2 columns
                      return Column(
                        children: [
                          Row(
                            children: [
                              Expanded(child: _buildCustomerNameField()),
                              const SizedBox(width: 24),
                              Expanded(child: _buildCustomerPhoneField()),
                            ],
                          ),
                          const SizedBox(height: 24),
                          _buildSaleDateField(),
                        ],
                      );
                    } else {
                      // Mobile: 1 column
                      return Column(
                        children: [
                          _buildCustomerNameField(),
                          const SizedBox(height: 24),
                          _buildCustomerPhoneField(),
                          const SizedBox(height: 24),
                          _buildSaleDateField(),
                        ],
                      );
                    }
                  },
                ),
              ],
            ),
          ),

          // Add Items Section
          _buildAddItemsSection(),

          // Current Sale Items (if any)
          if (_salesItems.isNotEmpty) ...[
            const SizedBox(height: 32),
            _buildCurrentSaleSection(),
          ],

          // Payment Summary (if items exist)
          if (_salesItems.isNotEmpty) ...[
            const SizedBox(height: 32),
            _buildPaymentSummarySection(),
          ],

          // Submit Section (if items exist)
          if (_salesItems.isNotEmpty) ...[
            const SizedBox(height: 32),
            _buildSubmitSection(),
          ],
        ],
      ),
    );
  }

  Widget _buildCustomerNameField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Customer Name (Optional)',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Theme.of(context).textTheme.bodyLarge?.color,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _customerNameController,
          decoration: InputDecoration(
            hintText: 'Enter customer name',
            filled: true,
            fillColor: Theme.of(context).scaffoldBackgroundColor,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: Theme.of(context).colorScheme.primary,
                width: 2,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 14,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCustomerPhoneField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Customer Phone (Optional)',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Theme.of(context).textTheme.bodyLarge?.color,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _customerPhoneController,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(
            hintText: 'Enter phone number',
            filled: true,
            fillColor: Theme.of(context).scaffoldBackgroundColor,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: Theme.of(context).colorScheme.primary,
                width: 2,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 14,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSaleDateField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Sale Date & Time (Optional)',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Theme.of(context).textTheme.bodyLarge?.color,
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: () async {
            final date = await showDatePicker(
              context: context,
              initialDate: _customDate ?? DateTime.now(),
              firstDate: DateTime.now().subtract(const Duration(days: 365)),
              lastDate: DateTime.now().add(const Duration(days: 1)),
            );
            if (date != null && mounted) {
              final time = await showTimePicker(
                context: context,
                initialTime: TimeOfDay.now(),
              );
              if (time != null && mounted) {
                setState(() {
                  _customDate = DateTime(
                    date.year,
                    date.month,
                    date.day,
                    time.hour,
                    time.minute,
                  );
                });
              }
            }
          },
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.calendar_today,
                  color: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.color?.withValues(alpha: 0.6),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _customDate != null
                        ? '${_customDate!.day}/${_customDate!.month}/${_customDate!.year} ${_customDate!.hour}:${_customDate!.minute.toString().padLeft(2, '0')}'
                        : 'Leave empty for current date & time',
                    style: TextStyle(
                      color: _customDate != null
                          ? Theme.of(context).textTheme.bodyLarge?.color
                          : Theme.of(context).textTheme.bodyMedium?.color
                                ?.withValues(alpha: 0.6),
                    ),
                  ),
                ),
                if (_customDate != null)
                  IconButton(
                    onPressed: () => setState(() => _customDate = null),
                    icon: Icon(
                      Icons.clear,
                      size: 18,
                      color: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.color?.withValues(alpha: 0.6),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Leave empty for current date & time',
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(
              context,
            ).textTheme.bodyMedium?.color?.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }

  Widget _buildAddItemsSection() {
    final isMobile = MediaQuery.of(context).size.width < 600;
    return Container(
      padding: EdgeInsets.all(isMobile ? 12 : 20),
      margin: EdgeInsets.only(bottom: isMobile ? 16 : 24),
      decoration: BoxDecoration(
        color: Theme.of(context).dividerColor.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with icon - SvelteKit pattern
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
                child: Center(
                  child: Text(
                    '🛍️',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Add Items to Sale',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).textTheme.titleLarge?.color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Product Selection Grid - SvelteKit responsive layout
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth > 1000) {
                // Desktop: 4 columns (2 for product, 1 for unit, 1 for quantity)
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(flex: 2, child: _buildProductDropdown()),
                    const SizedBox(width: 24),
                    Expanded(child: _buildUnitDropdown()),
                    const SizedBox(width: 24),
                    Expanded(child: _buildQuantityField()),
                    const SizedBox(width: 24),
                    Expanded(child: _buildPriceField()),
                  ],
                );
              } else {
                // Mobile/Tablet: Stacked
                return Column(
                  children: [
                    _buildProductDropdown(),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(child: _buildUnitDropdown()),
                        const SizedBox(width: 24),
                        Expanded(child: _buildQuantityField()),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _buildPriceField(),
                  ],
                );
              }
            },
          ),

          const SizedBox(height: 24),

          // Add Button and Error Message - responsive layout
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 420;
              final button = ElevatedButton.icon(
                onPressed: _handleAddProduct,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Item to Cart'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  padding: EdgeInsets.symmetric(
                    horizontal: narrow ? 16 : 24,
                    vertical: narrow ? 12 : 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              );

              Widget errorBox() => Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(
                      context,
                    ).colorScheme.error.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Text(
                      '⚠️',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              );

              if (narrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    button,
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 12),
                      errorBox(),
                    ],
                  ],
                );
              } else {
                return Row(
                  children: [
                    button,
                    if (_errorMessage != null) ...[
                      const SizedBox(width: 16),
                      Expanded(child: errorBox()),
                    ],
                  ],
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildProductDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select Product',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Theme.of(context).textTheme.bodyMedium?.color,
          ),
        ),
        const SizedBox(height: 8),
        ProductSearchField(
          value: _selectedProductObj,
          onlyInStock: true,
          onChanged: (p) {
            setState(() {
              _selectedProductObj = p;
              _selectedProductId = p?.id;
              if (p != null) {
                _selectedUnit = p.unitTypeSingle ?? '';
                _pricePerUnit = p.sellingPrice ?? 0.0;
                _priceController.text = (_pricePerUnit == 0)
                    ? ''
                    : _pricePerUnit.toStringAsFixed(
                        (_pricePerUnit % 1 == 0) ? 0 : 2,
                      );
              } else {
                _selectedUnit = '';
                _pricePerUnit = 0.0;
                _priceController.text = '';
              }
            });
          },
        ),
      ],
    );
  }

  Widget _buildUnitDropdown() {
    final selectedProduct = _selectedProductForSale;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Unit',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Theme.of(context).textTheme.bodyLarge?.color,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: selectedProduct == null
                ? Theme.of(context).dividerColor.withValues(alpha: 0.05)
                : Theme.of(context).scaffoldBackgroundColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: selectedProduct != null && _selectedUnit.isNotEmpty
                  ? _selectedUnit
                  : null,
              hint: Text(
                '--',
                style: TextStyle(
                  color: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.color?.withValues(alpha: 0.6),
                ),
              ),
              isExpanded: true,
              items: selectedProduct != null
                  ? [
                      if (selectedProduct.unitTypeSingle != null)
                        DropdownMenuItem<String>(
                          value: selectedProduct.unitTypeSingle!,
                          child: Text(selectedProduct.unitTypeSingle!),
                        ),
                      if (selectedProduct.unitTypeWholesale != null &&
                          selectedProduct.unitTypeWholesale !=
                              selectedProduct.unitTypeSingle)
                        DropdownMenuItem<String>(
                          value: selectedProduct.unitTypeWholesale!,
                          child: Text(selectedProduct.unitTypeWholesale!),
                        ),
                    ]
                  : [],
              onChanged: selectedProduct != null
                  ? (value) {
                      setState(() {
                        final oldUnit = _selectedUnit;
                        _selectedUnit = value ?? '';

                        // Smart Pricing Logic
                        if (_selectedUnit != oldUnit) {
                          double basePrice =
                              selectedProduct.sellingPrice ?? 0.0;
                          double multiplier =
                              (selectedProduct.itemsPerWholesaleUnit ?? 1)
                                  .toDouble();

                          if (_selectedUnit ==
                              selectedProduct.unitTypeWholesale) {
                            // Wholesale: Price = Base * Multiplier
                            _pricePerUnit = basePrice * multiplier;
                          } else {
                            // Single/Default: Price = Base
                            _pricePerUnit = basePrice;
                          }

                          // Update controller text
                          _priceController.text = _pricePerUnit.toStringAsFixed(
                            (_pricePerUnit % 1 == 0) ? 0 : 2,
                          );
                        }
                      });
                    }
                  : null,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQuantityField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quantity',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Theme.of(context).textTheme.bodyLarge?.color,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _quantityController,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (value) {
            // Only update the state variable, don't force the text back
            // allow empty string during typing
            if (value.isNotEmpty) {
              setState(() {
                _quantity = int.tryParse(value) ?? 1;
              });
            } else {
              // temporarily set to 0 or 1 internally to avoid issues,
              // but leave text empty so user can type
              _quantity = 0;
            }
          },
          decoration: InputDecoration(
            hintText: '1',
            filled: true,
            fillColor: Theme.of(context).scaffoldBackgroundColor,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: Theme.of(context).colorScheme.primary,
                width: 2,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 14,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCurrentSaleSection() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).shadowColor.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header - SvelteKit styling
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.05),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
                ),
              ),
            ),
            child: Row(
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
                  child: Center(
                    child: Text(
                      '🛒',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Current Sale',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).textTheme.titleLarge?.color,
                      ),
                    ),
                    Text(
                      '${_salesItems.length} item${_salesItems.length != 1 ? 's' : ''} added',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(
                          context,
                        ).textTheme.bodyMedium?.color?.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Items List - SvelteKit card styling
          Column(
            children: _salesItems.asMap().entries.map((entry) {
              final item = entry.value;
              final isLast = entry.key == _salesItems.length - 1;

              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: isLast
                      ? null
                      : Border(
                          bottom: BorderSide(
                            color: Theme.of(
                              context,
                            ).dividerColor.withValues(alpha: 0.1),
                          ),
                        ),
                ),
                child: Row(
                  children: [
                    // Item Details
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.name,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Theme.of(
                                context,
                              ).textTheme.titleMedium?.color,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '${item.quantity} ${item.unit}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              Text(
                                '@ ₹${item.pricePerUnit.toStringAsFixed(2)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.color
                                      ?.withValues(alpha: 0.6),
                                ),
                              ),
                              Text(
                                '= ₹${(item.quantity * item.pricePerUnit).toStringAsFixed(2)}',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(
                                    context,
                                  ).textTheme.bodyLarge?.color,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Remove Button - SvelteKit styling
                    const SizedBox(width: 12),
                    InkWell(
                      onTap: () => _removeItem(item.productId),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.error.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Theme.of(
                              context,
                            ).colorScheme.error.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Center(
                          child: Text(
                            '✕',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentSummarySection() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).shadowColor.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header - SvelteKit styling
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.05),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
                ),
              ),
            ),
            child: Row(
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
                  child: Center(
                    child: Text(
                      '💰',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Payment Summary',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).textTheme.titleLarge?.color,
                  ),
                ),
              ],
            ),
          ),

          // Payment Details
          Padding(
            padding: EdgeInsets.all(
              MediaQuery.of(context).size.width < 480 ? 16 : 24,
            ),
            child: Column(
              children: [
                // Subtotal
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Subtotal:',
                      style: TextStyle(
                        color: Theme.of(
                          context,
                        ).textTheme.bodyMedium?.color?.withValues(alpha: 0.8),
                      ),
                    ),
                    Text(
                      '₹${_subTotal.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).textTheme.bodyLarge?.color,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Discount Field
                LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 420;
                    final field = SizedBox(
                      width: compact ? double.infinity : 120,
                      child: TextField(
                        controller: _discountController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'^\d*\.?\d*'),
                          ),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _discount = double.tryParse(value) ?? 0.0;
                          });
                        },
                        decoration: InputDecoration(
                          hintText: '0',
                          filled: true,
                          fillColor: Theme.of(context).scaffoldBackgroundColor,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: Theme.of(
                                context,
                              ).dividerColor.withValues(alpha: 0.3),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: Theme.of(
                                context,
                              ).dividerColor.withValues(alpha: 0.3),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: Theme.of(context).colorScheme.primary,
                              width: 2,
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                      ),
                    );
                    if (compact) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Discount (₹):',
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              color: Theme.of(
                                context,
                              ).textTheme.bodyLarge?.color,
                            ),
                          ),
                          const SizedBox(height: 8),
                          field,
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Text(
                          'Discount (₹):',
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            color: Theme.of(context).textTheme.bodyLarge?.color,
                          ),
                        ),
                        const Spacer(),
                        field,
                      ],
                    );
                  },
                ),

                const SizedBox(height: 16),

                // Paid Now Field
                LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 420;
                    final field = SizedBox(
                      width: compact ? double.infinity : 140,
                      child: TextField(
                        controller: _paidNowController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'^\d*\.?\d*'),
                          ),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _paidNow = double.tryParse(value) ?? 0.0;
                          });
                        },
                        decoration: InputDecoration(
                          hintText: '0',
                          filled: true,
                          fillColor: Theme.of(context).scaffoldBackgroundColor,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: Theme.of(
                                context,
                              ).dividerColor.withValues(alpha: 0.3),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: Theme.of(
                                context,
                              ).dividerColor.withValues(alpha: 0.3),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: Theme.of(context).colorScheme.primary,
                              width: 2,
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                      ),
                    );
                    if (compact) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Paid Now (₹):',
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              color: Theme.of(
                                context,
                              ).textTheme.bodyLarge?.color,
                            ),
                          ),
                          const SizedBox(height: 8),
                          field,
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Text(
                          'Paid Now (₹):',
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            color: Theme.of(context).textTheme.bodyLarge?.color,
                          ),
                        ),
                        const Spacer(),
                        field,
                      ],
                    );
                  },
                ),

                const SizedBox(height: 12),

                // Use Advance toggle
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Use available customer advance (if any)',
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          color: Theme.of(context).textTheme.bodyLarge?.color,
                        ),
                      ),
                    ),
                    Switch(
                      value: _useAdvance,
                      onChanged: (v) {
                        setState(() => _useAdvance = v);
                      },
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Payment Method
                LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 420;
                    final methodDropdown = SizedBox(
                      width: compact ? double.infinity : 140,
                      child: Container(
                        height: 40,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).scaffoldBackgroundColor,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Theme.of(
                              context,
                            ).dividerColor.withValues(alpha: 0.3),
                          ),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _paymentMethod,
                            isExpanded: true,
                            items: ['Cash', 'UPI', 'Card', 'Credit'].map((
                              method,
                            ) {
                              return DropdownMenuItem<String>(
                                value: method,
                                child: Text(method),
                              );
                            }).toList(),
                            onChanged: (value) {
                              setState(() {
                                _paymentMethod = value ?? 'Cash';
                              });
                            },
                          ),
                        ),
                      ),
                    );
                    if (compact) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Payment Method:',
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              color: Theme.of(
                                context,
                              ).textTheme.bodyLarge?.color,
                            ),
                          ),
                          const SizedBox(height: 8),
                          methodDropdown,
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Text(
                          'Payment Method:',
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            color: Theme.of(context).textTheme.bodyLarge?.color,
                          ),
                        ),
                        const Spacer(),
                        methodDropdown,
                      ],
                    );
                  },
                ),

                // Transaction ID (if UPI/Card)
                if (_paymentMethod == 'UPI' || _paymentMethod == 'Card') ...[
                  const SizedBox(height: 16),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 420;
                      final txnField = SizedBox(
                        width: compact ? double.infinity : 140,
                        child: TextField(
                          controller: _transactionIdController,
                          decoration: InputDecoration(
                            hintText: 'Optional',
                            filled: true,
                            fillColor: Theme.of(
                              context,
                            ).scaffoldBackgroundColor,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                color: Theme.of(
                                  context,
                                ).dividerColor.withValues(alpha: 0.3),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                color: Theme.of(
                                  context,
                                ).dividerColor.withValues(alpha: 0.3),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                color: Theme.of(context).colorScheme.primary,
                                width: 2,
                              ),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                          ),
                        ),
                      );
                      if (compact) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Transaction ID:',
                              style: TextStyle(
                                fontWeight: FontWeight.w500,
                                color: Theme.of(
                                  context,
                                ).textTheme.bodyLarge?.color,
                              ),
                            ),
                            const SizedBox(height: 8),
                            txnField,
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Text(
                            'Transaction ID:',
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              color: Theme.of(
                                context,
                              ).textTheme.bodyLarge?.color,
                            ),
                          ),
                          const Spacer(),
                          txnField,
                        ],
                      );
                    },
                  ),
                ],

                const SizedBox(height: 20),

                // Total with border
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(
                        color: Theme.of(
                          context,
                        ).dividerColor.withValues(alpha: 0.2),
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Final Total:',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).textTheme.titleLarge?.color,
                        ),
                      ),
                      Text(
                        '₹${_finalTotal.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitSection() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).shadowColor.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth > 600) {
            // Desktop: Row layout
            return Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ready to complete sale?',
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(
                            context,
                          ).textTheme.bodyMedium?.color?.withValues(alpha: 0.6),
                        ),
                      ),
                      const SizedBox(height: 4),
                      RichText(
                        text: TextSpan(
                          text: 'Total Amount: ',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(
                              context,
                            ).textTheme.titleLarge?.color,
                          ),
                          children: [
                            TextSpan(
                              text: '₹${_finalTotal.toStringAsFixed(2)}',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                SizedBox(
                  width: 280,
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: _isProcessing ? null : _completeSale,
                    icon: _isProcessing
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Theme.of(context).colorScheme.onPrimary,
                              ),
                            ),
                          )
                        : const Icon(Icons.check_circle, size: 20),
                    label: Text(
                      _isProcessing
                          ? 'Processing...'
                          : '🎯 Complete Sale (₹${_finalTotal.toStringAsFixed(2)})',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF16A34A), // Green-600
                      foregroundColor: Colors.white,
                      elevation: 4,
                      shadowColor: const Color(
                        0xFF16A34A,
                      ).withValues(alpha: 0.3),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            );
          } else {
            // Mobile: Column layout
            return Column(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ready to complete sale?',
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(
                          context,
                        ).textTheme.bodyMedium?.color?.withValues(alpha: 0.6),
                      ),
                    ),
                    const SizedBox(height: 4),
                    RichText(
                      text: TextSpan(
                        text: 'Total Amount: ',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).textTheme.titleLarge?.color,
                        ),
                        children: [
                          TextSpan(
                            text: '₹${_finalTotal.toStringAsFixed(2)}',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: _isProcessing ? null : _completeSale,
                    icon: _isProcessing
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Theme.of(context).colorScheme.onPrimary,
                              ),
                            ),
                          )
                        : const Icon(Icons.check_circle, size: 20),
                    label: Text(
                      _isProcessing
                          ? 'Processing...'
                          : '🎯 Complete Sale (₹${_finalTotal.toStringAsFixed(2)})',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF16A34A), // Green-600
                      foregroundColor: Colors.white,
                      elevation: 4,
                      shadowColor: const Color(
                        0xFF16A34A,
                      ).withValues(alpha: 0.3),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            );
          }
        },
      ),
    );
  }
}
