import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart'; // for kDebugMode
import 'package:supabase_flutter/supabase_flutter.dart'; // for Supabase.instance
import 'dart:async';
import '../services/supabase_service.dart';
import '../services/connectivity_service.dart';
import '../models/supabase_models.dart' as supabase;
import '../widgets/page_header.dart';
import '../widgets/product_search_field.dart';

class PurchasePage extends StatefulWidget {
  const PurchasePage({super.key});

  @override
  State<PurchasePage> createState() => _PurchasePageState();
}

class _PurchasePageState extends State<PurchasePage> {
  // State variables
  List<supabase.Product> _products = [];
  final List<Map<String, dynamic>> _purchaseItems = [];
  bool _isLoading = true;
  bool _isProcessing = false;
  String? _errorMessage;
  String? _successMessage;
  bool _onlyInStockFilter =
      false; // allow purchasing out-of-stock products by default
  Timer? _autoRefreshTimer; // auto refresh timer
  Timer? _dealerDebounce; // debounce for dealer credit fetch

  // Form controllers
  final TextEditingController _dealerNameController = TextEditingController();
  final TextEditingController _billNumberController = TextEditingController();
  final TextEditingController _quantityController = TextEditingController(
    text: '1',
  );
  final TextEditingController _purchasePriceController =
      TextEditingController();
  final TextEditingController _totalCostController = TextEditingController();
  final TextEditingController _creditApplyController = TextEditingController();
  final TextEditingController _paidAmountController = TextEditingController();

  // Pricing mode state
  String _pricingMode = 'rate'; // 'rate' | 'total'

  // Supplier credit state
  double _availableCredit = 0.0;
  double _appliedCredit = 0.0;

  // Selection state
  supabase.Product? _selectedProduct;
  String _selectedUnit = '';
  DateTime? _customDate;

  @override
  void initState() {
    super.initState();
    _loadProducts();
    _dealerNameController.addListener(_onDealerNameChanged);
    // Auto refresh products every 60 seconds (silent)
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted) {
        _refreshProducts();
      }
    });
  }

  void _onDealerNameChanged() {
    _dealerDebounce?.cancel();
    _dealerDebounce = Timer(const Duration(milliseconds: 350), () async {
      final name = _dealerNameController.text.trim();
      if (name.isEmpty) {
        if (!mounted) return;
        setState(() {
          _availableCredit = 0.0;
          _appliedCredit = 0.0;
          _creditApplyController.text = '';
        });
        return;
      }
      try {
        final bal = await SupabaseService.getSupplierCreditBalance(name);
        if (!mounted) return;
        setState(() {
          _availableCredit = bal;
          final maxAllowed = _maxApplicableCredit();
          if (_appliedCredit > maxAllowed) {
            _appliedCredit = maxAllowed;
            _creditApplyController.text = _appliedCredit > 0
                ? _appliedCredit.toStringAsFixed(2)
                : '';
          }
        });
      } catch (_) {
        // ignore errors
      }
    });
  }

  double _maxApplicableCredit() {
    final total = _computeTotalAmount();
    final safeTotal = total.isFinite && total > 0 ? total : 0.0;
    final bal = _availableCredit.isFinite && _availableCredit > 0
        ? _availableCredit
        : 0.0;
    return safeTotal < bal ? safeTotal : bal;
  }

  void _onCreditChanged(String v) {
    final parsed = double.tryParse(v.trim()) ?? 0.0;
    final maxAllowed = _maxApplicableCredit();
    final clamped = parsed.isFinite
        ? (parsed < 0 ? 0.0 : (parsed > maxAllowed ? maxAllowed : parsed))
        : 0.0;
    if (!mounted) return;
    setState(() {
      _appliedCredit = clamped;
      if ((_appliedCredit == 0.0 && v.trim().isNotEmpty) ||
          (_appliedCredit.toStringAsFixed(2) != v.trim())) {
        _creditApplyController.text = _appliedCredit > 0
            ? _appliedCredit.toStringAsFixed(2)
            : '';
      }
    });
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _dealerDebounce?.cancel();
    _dealerNameController.dispose();
    _billNumberController.dispose();
    _quantityController.dispose();
    _purchasePriceController.dispose();
    _totalCostController.dispose();
    _creditApplyController.dispose();
    _paidAmountController.dispose();
    super.dispose();
  }

  void _onQuantityChanged(String value) {
    _calculatePricing();
  }

  void _onRateChanged(String value) {
    if (_pricingMode == 'rate') {
      _calculatePricing();
    }
  }

  void _onTotalChanged(String value) {
    if (_pricingMode == 'total') {
      _calculatePricing();
    }
  }

  void _calculatePricing() {
    final qty = double.tryParse(_quantityController.text) ?? 0.0;
    if (qty <= 0) return;

    if (_pricingMode == 'rate') {
      // Calculate Total based on Rate
      final rate = double.tryParse(_purchasePriceController.text) ?? 0.0;
      final total = rate * qty;
      final currentTotal = double.tryParse(_totalCostController.text) ?? 0.0;
      if (total != currentTotal) {
        _totalCostController.text = total == 0 ? '' : total.toStringAsFixed(2);
      }
    } else {
      // Calculate Rate based on Total
      final total = double.tryParse(_totalCostController.text) ?? 0.0;
      final rate = total / qty;
      final currentRate = double.tryParse(_purchasePriceController.text) ?? 0.0;
      // Avoid infinite loop / precision jitter
      if ((rate - currentRate).abs() > 0.01) {
        _purchasePriceController.text = rate == 0
            ? ''
            : rate.toStringAsFixed(2);
      }
    }
  }

  void _togglePricingMode(String mode) {
    setState(() {
      _pricingMode = mode;
    });
    // Re-calculate based on new mode dominance
    _calculatePricing();
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
        _errorMessage = 'Error loading products: $e';
        _isLoading = false;
      });
    }
  }

  // Silent refresh used by pull-to-refresh and auto refresh
  Future<void> _refreshProducts() async {
    try {
      final products = await SupabaseService.getProducts();
      if (!mounted) return;
      setState(() {
        _products = products;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Error refreshing products: $e';
      });
    }
  }

  void _handleAddProduct() {
    if (_selectedProduct == null) {
      _showError('Please select a product');
      return;
    }

    final quantity = int.tryParse(_quantityController.text) ?? 0;
    if (quantity <= 0) {
      _showError('Please enter a valid quantity');
      return;
    }

    final purchasePrice = double.tryParse(_purchasePriceController.text) ?? 0.0;
    if (purchasePrice <= 0) {
      _showError('Please enter a valid price');
      return;
    }

    if (_selectedUnit.isEmpty) {
      _showError('Please select a unit');
      return;
    }

    // Check if product already exists in list
    final existingIndex = _purchaseItems.indexWhere(
      (item) => item['product_id'] == _selectedProduct!.id,
    );

    if (existingIndex != -1) {
      _showError('This product is already in the list');
      return;
    }

    setState(() {
      _purchaseItems.add({
        'product_id': _selectedProduct!.id,
        'name': _selectedProduct!.name,
        'quantity': quantity,
        'price_per_unit': purchasePrice,
        'unit': _selectedUnit,
      });

      // Reset form
      _selectedProduct = null;
      _selectedProduct = null;
      _selectedUnit = '';
      _quantityController.text = '1';
      _purchasePriceController.clear();
      _totalCostController.clear();
      _errorMessage = null;
    });
  }

  void _removeItem(int productId) {
    setState(() {
      _purchaseItems.removeWhere((item) => item['product_id'] == productId);
    });
  }

  Future<void> _savePurchase() async {
    if (!ConnectivityService().isOnline.value) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: const [
                Icon(Icons.wifi_off, color: Colors.white),
                SizedBox(width: 8),
                Text('You are offline. Cannot save purchase.'),
              ],
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    if (_dealerNameController.text.trim().isEmpty) {
      _showError('Please enter dealer name');
      return;
    }

    if (_purchaseItems.isEmpty) {
      _showError('Please add items to purchase');
      return;
    }

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      // 1. Auto-Create Supplier if not exists
      final dealerName = _dealerNameController.text.trim();
      if (dealerName.isNotEmpty) {
        // Check for existing supplier (case-insensitive)
        final existingSupplier = await SupabaseService.searchSuppliers(
          dealerName,
        );

        // Exact match check (searchSuppliers uses ilike %query%)
        // We need to be careful not to match "Test" with "Test Ref"
        final exactMatch = existingSupplier.any(
          (s) => s.name.toLowerCase() == dealerName.toLowerCase(),
        );

        if (!exactMatch) {
          if (kDebugMode) {
            print('Auto-creating new supplier: $dealerName');
          }
          try {
            // Create new supplier
            await Supabase.instance.client.from('suppliers').insert({
              'business_id':
                  SupabaseService.getCurrentBusinessId(), // ensure we get ID
              'name': dealerName,
            });
            // We don't need the ID for the purchase record itself as it stores dealer_name text,
            // but creating it ensures it appears in future autocompletes.
          } catch (e) {
            print('Error auto-creating supplier: $e');
            // Proceed anyway, don't block purchase save
          }
        }
      }

      await SupabaseService.createPurchase(
        dealerName: _dealerNameController.text.trim(),
        billNumber: _billNumberController.text.trim().isNotEmpty
            ? _billNumberController.text.trim()
            : null,
        purchaseDate: _customDate?.toUtc(),
        purchaseItems: _purchaseItems,
        paidAmount: double.tryParse(_paidAmountController.text) ?? 0.0,
      );

      // Note: We do NOT need to "apply" supplier credit explicitly.
      // The Ledger is a running balance.
      // Returns (Debit) and Purchases (Credit) naturally net out.
      // Inserting an 'apply' record would double-count the deduction.

      setState(() {
        _successMessage = 'Purchase saved successfully!';
        _purchaseItems.clear();
        _dealerNameController.clear();
        _billNumberController.clear();
        _customDate = null;
        _isProcessing = false;
        _availableCredit = 0.0;
        _appliedCredit = 0.0;
        _appliedCredit = 0.0;
        _creditApplyController.text = '';
        _paidAmountController.clear();
      });

      // Clear success message after 3 seconds
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            _successMessage = null;
          });
        }
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error saving purchase: $e';
        _isProcessing = false;
      });
    }
  }

  void _showError(String message) {
    setState(() {
      _errorMessage = message;
      _successMessage = null;
    });
  }

  Future<void> _showQuickAddSupplierDialog() async {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final addressController = TextEditingController();

    final result = await showDialog<supabase.Supplier>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Quick Add Supplier'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Supplier Name *',
                  border: OutlineInputBorder(),
                ),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneController,
                decoration: const InputDecoration(
                  labelText: 'Phone',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: addressController,
                decoration: const InputDecoration(
                  labelText: 'Address',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Supplier name is required')),
                );
                return;
              }
              try {
                final supplier = supabase.Supplier(
                  businessId: '',
                  name: nameController.text.trim(),
                  contactNumber: phoneController.text.trim().isEmpty
                      ? null
                      : phoneController.text.trim(),
                  physicalAddress: addressController.text.trim().isEmpty
                      ? null
                      : addressController.text.trim(),
                );
                await SupabaseService.createSupplier(supplier);
                if (context.mounted) {
                  Navigator.pop(context, supplier);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Supplier added successfully'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (result != null) {
      setState(() {
        _dealerNameController.text = result.name;
      });
    }
  }

  // Compute live total amount of the purchase list
  double _computeTotalAmount() {
    double total = 0.0;
    for (final it in _purchaseItems) {
      final qty = (it['quantity'] as num?)?.toDouble() ?? 0.0;
      final price = (it['price_per_unit'] as num?)?.toDouble() ?? 0.0;
      total += qty * price;
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        top: true,
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _refreshProducts,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: MediaQuery.of(context).size.width < 480 ? 12 : 16,
                vertical: MediaQuery.of(context).size.width < 480 ? 16 : 24,
              ),
              child: Column(
                children: [
                  SizedBox(
                    height: MediaQuery.of(context).size.width < 480 ? 12 : 32,
                  ),
                  PageHeader(
                    title: 'Record Purchase',
                    description:
                        'Add new stock acquisitions and manage inventory purchases',
                    icon: '🛍️',
                    showBackButton: true,
                    stats: [
                      PageHeaderStat(
                        label: 'Items Added',
                        value: '${_purchaseItems.length}',
                        description: _purchaseItems.isEmpty
                            ? 'No items added'
                            : 'Ready to record',
                      ),
                      PageHeaderStat(
                        label: 'Total Cost',
                        value: '₹${_computeTotalAmount().toStringAsFixed(0)}',
                        description: 'Estimated order value',
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),
                  // Error Message
                  if (_errorMessage != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        border: Border.all(color: Colors.red),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),

                  // Success Message
                  if (_successMessage != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.1),
                        border: Border.all(color: Colors.green),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Text('✅ ', style: TextStyle(fontSize: 16)),
                          Text(
                            _successMessage!,
                            style: const TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Main Form
                  Container(
                    padding: EdgeInsets.all(
                      MediaQuery.of(context).size.width < 480 ? 16 : 24,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      border: Border.all(color: Theme.of(context).dividerColor),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Basic Information (responsive)
                        LayoutBuilder(
                          builder: (context, constraints) {
                            Widget dealerField = Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Dealer Name',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w500,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Autocomplete<supabase.Supplier>(
                                  optionsBuilder:
                                      (
                                        TextEditingValue textEditingValue,
                                      ) async {
                                        if (textEditingValue.text.isEmpty) {
                                          return const Iterable<
                                            supabase.Supplier
                                          >.empty();
                                        }
                                        try {
                                          final suppliers =
                                              await SupabaseService.searchSuppliers(
                                                textEditingValue.text,
                                              );
                                          return suppliers;
                                        } catch (e) {
                                          return const Iterable<
                                            supabase.Supplier
                                          >.empty();
                                        }
                                      },
                                  displayStringForOption:
                                      (supabase.Supplier supplier) =>
                                          supplier.name,
                                  onSelected: (supabase.Supplier supplier) {
                                    _dealerNameController.text = supplier.name;
                                  },
                                  fieldViewBuilder:
                                      (
                                        context,
                                        controller,
                                        focusNode,
                                        onEditingComplete,
                                      ) {
                                        // Sync controller with _dealerNameController
                                        controller.text =
                                            _dealerNameController.text;
                                        controller.selection =
                                            _dealerNameController.selection;

                                        return TextField(
                                          controller: controller,
                                          focusNode: focusNode,
                                          onChanged: (value) {
                                            _dealerNameController.text = value;
                                            _dealerNameController.selection =
                                                controller.selection;
                                          },
                                          decoration: InputDecoration(
                                            hintText: 'e.g., Gupta Electronics',
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                  horizontal: 12,
                                                  vertical: 12,
                                                ),
                                            suffixIcon: IconButton(
                                              icon: const Icon(
                                                Icons.add_business,
                                                size: 20,
                                              ),
                                              onPressed: () {
                                                // Quick add supplier (open dialog)
                                                _showQuickAddSupplierDialog();
                                              },
                                              tooltip: 'Quick add supplier',
                                            ),
                                          ),
                                        );
                                      },
                                ),
                              ],
                            );

                            Widget billField = Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Bill Number',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w500,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                TextField(
                                  controller: _billNumberController,
                                  decoration: InputDecoration(
                                    hintText: 'Optional',
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 12,
                                    ),
                                  ),
                                ),
                              ],
                            );

                            Widget dateTimeField = Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.surface.withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    '📅 Purchase Date & Time (Optional)',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w500,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  InkWell(
                                    onTap: () async {
                                      final date = await showDatePicker(
                                        context: context,
                                        initialDate:
                                            _customDate ?? DateTime.now(),
                                        firstDate: DateTime(2020),
                                        lastDate: DateTime.now(),
                                      );
                                      if (date != null && mounted) {
                                        final time = await showTimePicker(
                                          context: context,
                                          initialTime: TimeOfDay.fromDateTime(
                                            _customDate ?? DateTime.now(),
                                          ),
                                        );
                                        if (time != null) {
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
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 12,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context).cardColor,
                                        border: Border.all(
                                          color: Theme.of(context).dividerColor,
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        _customDate != null
                                            ? '${_customDate!.day}/${_customDate!.month}/${_customDate!.year} ${_customDate!.hour}:${_customDate!.minute.toString().padLeft(2, '0')}'
                                            : 'Current date & time',
                                        style: TextStyle(
                                          color: _customDate != null
                                              ? Theme.of(
                                                  context,
                                                ).textTheme.bodyMedium?.color
                                              : Theme.of(context)
                                                    .textTheme
                                                    .bodyMedium
                                                    ?.color
                                                    ?.withValues(alpha: 0.6),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Leave empty to use current date & time',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.color
                                          ?.withValues(alpha: 0.6),
                                    ),
                                  ),
                                ],
                              ),
                            );

                            if (constraints.maxWidth > 768) {
                              return Row(
                                children: [
                                  Expanded(child: dealerField),
                                  const SizedBox(width: 16),
                                  Expanded(child: billField),
                                  const SizedBox(width: 16),
                                  Expanded(child: dateTimeField),
                                ],
                              );
                            } else if (constraints.maxWidth > 480) {
                              return Column(
                                children: [
                                  Row(
                                    children: [
                                      Expanded(child: dealerField),
                                      const SizedBox(width: 16),
                                      Expanded(child: billField),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  dateTimeField,
                                ],
                              );
                            } else {
                              return Column(
                                children: [
                                  dealerField,
                                  const SizedBox(height: 16),
                                  billField,
                                  const SizedBox(height: 16),
                                  dateTimeField,
                                ],
                              );
                            }
                          },
                        ),

                        const SizedBox(height: 16),
                        // Supplier Credit
                        if (_dealerNameController.text.trim().isNotEmpty)
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.surface.withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Theme.of(
                                  context,
                                ).dividerColor.withValues(alpha: 0.5),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.receipt_long,
                                      size: 16,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Supplier Credit',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: Theme.of(
                                          context,
                                        ).textTheme.titleMedium?.color,
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      'Available: ₹${_availableCredit.toStringAsFixed(2)}',
                                      style: TextStyle(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: _creditApplyController,
                                        keyboardType:
                                            const TextInputType.numberWithOptions(
                                              decimal: true,
                                            ),
                                        inputFormatters: [
                                          FilteringTextInputFormatter.allow(
                                            RegExp(r'^\d*\.?\d*'),
                                          ),
                                        ],
                                        onChanged: _onCreditChanged,
                                        decoration: InputDecoration(
                                          labelText: 'Apply Credit (₹)',
                                          hintText: '0.00',
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          helperText:
                                              'Max: ₹${_maxApplicableCredit().toStringAsFixed(2)}',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),

                        const SizedBox(height: 24),
                        const Divider(),
                        const SizedBox(height: 24),

                        // Add Items Section
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.surface.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Add Items to Purchase',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 18,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Icon(
                                    Icons.inventory_2,
                                    size: 16,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Show only in-stock',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Switch(
                                    value: _onlyInStockFilter,
                                    onChanged: (v) => setState(() {
                                      _onlyInStockFilter = v;
                                    }),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),

                              Column(
                                children: [
                                  // First Row: Product Selection
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              'Select Product',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w500,
                                                fontSize: 14,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            ProductSearchField(
                                              value: _selectedProduct,
                                              onlyInStock: _onlyInStockFilter,
                                              onChanged: (p) {
                                                setState(() {
                                                  _selectedProduct = p;
                                                  if (p != null) {
                                                    _selectedUnit =
                                                        p.unitTypeSingle ?? '';
                                                  } else {
                                                    _selectedUnit = '';
                                                  }
                                                });
                                              },
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),

                                  const SizedBox(height: 16),

                                  // Second Row: Quantity, Unit, Price (responsive)
                                  LayoutBuilder(
                                    builder: (context, constraints) {
                                      Widget quantityField = Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Quantity',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w500,
                                              fontSize: 14,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          TextField(
                                            controller: _quantityController,
                                            keyboardType: TextInputType.number,
                                            onChanged: _onQuantityChanged,
                                            inputFormatters: [
                                              FilteringTextInputFormatter
                                                  .digitsOnly,
                                            ],
                                            decoration: InputDecoration(
                                              border: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              contentPadding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 12,
                                                  ),
                                            ),
                                          ),
                                        ],
                                      );

                                      Widget unitField = Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Unit',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w500,
                                              fontSize: 14,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          DropdownButtonFormField<String>(
                                            initialValue:
                                                _selectedUnit.isNotEmpty
                                                ? _selectedUnit
                                                : null,
                                            isExpanded: true,
                                            decoration: InputDecoration(
                                              border: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              contentPadding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 12,
                                                  ),
                                            ),
                                            items: _selectedProduct != null
                                                ? [
                                                    if (_selectedProduct!
                                                            .unitTypeSingle !=
                                                        null)
                                                      DropdownMenuItem(
                                                        value: _selectedProduct!
                                                            .unitTypeSingle,
                                                        child: Text(
                                                          _selectedProduct!
                                                              .unitTypeSingle!,
                                                        ),
                                                      ),
                                                    if (_selectedProduct!
                                                                .unitTypeWholesale !=
                                                            null &&
                                                        _selectedProduct!
                                                                .unitTypeWholesale !=
                                                            _selectedProduct!
                                                                .unitTypeSingle)
                                                      DropdownMenuItem(
                                                        value: _selectedProduct!
                                                            .unitTypeWholesale,
                                                        child: Text(
                                                          _selectedProduct!
                                                              .unitTypeWholesale!,
                                                        ),
                                                      ),
                                                  ]
                                                : [],
                                            onChanged: _selectedProduct != null
                                                ? (value) {
                                                    final oldUnit =
                                                        _selectedUnit;
                                                    final newUnit = value ?? '';

                                                    // Smart Scaling Logic
                                                    double currentPrice =
                                                        double.tryParse(
                                                          _purchasePriceController
                                                              .text,
                                                        ) ??
                                                        0.0;

                                                    if (oldUnit.isNotEmpty &&
                                                        newUnit.isNotEmpty &&
                                                        oldUnit != newUnit &&
                                                        currentPrice > 0) {
                                                      final single =
                                                          _selectedProduct!
                                                              .unitTypeSingle;
                                                      final wholesale =
                                                          _selectedProduct!
                                                              .unitTypeWholesale;
                                                      final multiplier =
                                                          (_selectedProduct!
                                                                      .itemsPerWholesaleUnit ??
                                                                  1)
                                                              .toDouble();

                                                      if (oldUnit == single &&
                                                          newUnit ==
                                                              wholesale) {
                                                        // Scale Up
                                                        currentPrice =
                                                            currentPrice *
                                                            multiplier;
                                                        _purchasePriceController
                                                            .text = currentPrice
                                                            .toStringAsFixed(2);
                                                        // Trigger recalc manually since controller update doesn't fire listeners
                                                        _onRateChanged(
                                                          _purchasePriceController
                                                              .text,
                                                        );
                                                      } else if (oldUnit ==
                                                              wholesale &&
                                                          newUnit == single) {
                                                        // Scale Down
                                                        currentPrice =
                                                            currentPrice /
                                                            multiplier;
                                                        _purchasePriceController
                                                            .text = currentPrice
                                                            .toStringAsFixed(2);
                                                        // Trigger recalc
                                                        _onRateChanged(
                                                          _purchasePriceController
                                                              .text,
                                                        );
                                                      }
                                                    }

                                                    setState(() {
                                                      _selectedUnit = newUnit;
                                                    });
                                                  }
                                                : null,
                                          ),
                                        ],
                                      );

                                      Widget priceField = Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Price/Unit (₹)',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w500,
                                              fontSize: 14,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          TextField(
                                            controller:
                                                _purchasePriceController,
                                            keyboardType:
                                                const TextInputType.numberWithOptions(
                                                  decimal: true,
                                                ),
                                            enabled: _pricingMode == 'rate',
                                            onChanged: _onRateChanged,
                                            inputFormatters: [
                                              FilteringTextInputFormatter.allow(
                                                RegExp(r'^\d*\.?\d*'),
                                              ),
                                            ],
                                            decoration: InputDecoration(
                                              filled: _pricingMode != 'rate',
                                              fillColor: _pricingMode != 'rate'
                                                  ? Theme.of(context)
                                                        .disabledColor
                                                        .withOpacity(0.1)
                                                  : null,
                                              border: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              contentPadding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 12,
                                                  ),
                                            ),
                                          ),
                                        ],
                                      );

                                      Widget totalField = Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Total Amount (₹)',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w500,
                                              fontSize: 14,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          TextField(
                                            controller: _totalCostController,
                                            keyboardType:
                                                const TextInputType.numberWithOptions(
                                                  decimal: true,
                                                ),
                                            enabled: _pricingMode == 'total',
                                            onChanged: _onTotalChanged,
                                            inputFormatters: [
                                              FilteringTextInputFormatter.allow(
                                                RegExp(r'^\d*\.?\d*'),
                                              ),
                                            ],
                                            decoration: InputDecoration(
                                              filled: _pricingMode != 'total',
                                              fillColor: _pricingMode != 'total'
                                                  ? Theme.of(context)
                                                        .disabledColor
                                                        .withOpacity(0.1)
                                                  : null,
                                              border: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              contentPadding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 12,
                                                  ),
                                            ),
                                          ),
                                        ],
                                      );

                                      Widget
                                      modeToggle = SegmentedButton<String>(
                                        segments: const [
                                          ButtonSegment<String>(
                                            value: 'rate',
                                            label: Text('Rate'),
                                            icon: Icon(Icons.sell_outlined),
                                          ),
                                          ButtonSegment<String>(
                                            value: 'total',
                                            label: Text('Total'),
                                            icon: Icon(Icons.attach_money),
                                          ),
                                        ],
                                        selected: {_pricingMode},
                                        onSelectionChanged:
                                            (Set<String> newSelection) {
                                              _togglePricingMode(
                                                newSelection.first,
                                              );
                                            },
                                        style: ButtonStyle(
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                          visualDensity: VisualDensity.compact,
                                        ),
                                      );

                                      if (constraints.maxWidth > 900) {
                                        return Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            Expanded(child: quantityField),
                                            const SizedBox(width: 12),
                                            Expanded(child: unitField),
                                            const SizedBox(width: 12),
                                            // Pricing Block
                                            Expanded(
                                              flex: 2,
                                              child: Container(
                                                padding: const EdgeInsets.all(
                                                  12,
                                                ),
                                                decoration: BoxDecoration(
                                                  border: Border.all(
                                                    color: Theme.of(
                                                      context,
                                                    ).dividerColor,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Row(
                                                      children: [
                                                        Text(
                                                          'Pricing Mode',
                                                          style: TextStyle(
                                                            fontSize: 12,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                            color:
                                                                Theme.of(
                                                                      context,
                                                                    )
                                                                    .colorScheme
                                                                    .primary,
                                                          ),
                                                        ),
                                                        const Spacer(),
                                                        SizedBox(
                                                          height: 32,
                                                          child: modeToggle,
                                                        ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 12),
                                                    Row(
                                                      children: [
                                                        Expanded(
                                                          child: priceField,
                                                        ),
                                                        const SizedBox(
                                                          width: 12,
                                                        ),
                                                        Expanded(
                                                          child: totalField,
                                                        ),
                                                      ],
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ],
                                        );
                                      } else {
                                        return Column(
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(child: quantityField),
                                                const SizedBox(width: 12),
                                                Expanded(child: unitField),
                                              ],
                                            ),
                                            const SizedBox(height: 16),
                                            Container(
                                              padding: const EdgeInsets.all(12),
                                              decoration: BoxDecoration(
                                                border: Border.all(
                                                  color: Theme.of(
                                                    context,
                                                  ).dividerColor,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      Text(
                                                        'Pricing Mode',
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color: Theme.of(
                                                            context,
                                                          ).colorScheme.primary,
                                                        ),
                                                      ),
                                                      const Spacer(),
                                                      SizedBox(
                                                        height: 32,
                                                        child: modeToggle,
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 12),
                                                  Row(
                                                    children: [
                                                      Expanded(
                                                        child: priceField,
                                                      ),
                                                      const SizedBox(width: 12),
                                                      Expanded(
                                                        child: totalField,
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        );
                                      }
                                    },
                                  ),
                                ],
                              ),

                              const SizedBox(height: 16),

                              ElevatedButton(
                                onPressed: _handleAddProduct,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Theme.of(
                                    context,
                                  ).colorScheme.secondary,
                                  foregroundColor: Theme.of(
                                    context,
                                  ).colorScheme.onSecondary,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                ),
                                child: const Text('+ Add Item to List'),
                              ),
                            ],
                          ),
                        ),

                        // Purchase Items List
                        if (_purchaseItems.isNotEmpty) ...[
                          const SizedBox(height: 24),
                          const Text(
                            'Purchase List',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 18,
                            ),
                          ),
                          const SizedBox(height: 16),

                          Container(
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: Theme.of(context).dividerColor,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _purchaseItems.length,
                              separatorBuilder: (context, index) => Divider(
                                height: 1,
                                color: Theme.of(context).dividerColor,
                              ),
                              itemBuilder: (context, index) {
                                final item = _purchaseItems[index];
                                final double qty =
                                    (item['quantity'] as num?)?.toDouble() ??
                                    0.0;
                                final double unitPrice =
                                    (item['price_per_unit'] as num?)
                                        ?.toDouble() ??
                                    0.0;
                                final double lineTotal = qty * unitPrice;
                                return Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              item['name'],
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Builder(
                                              builder: (context) {
                                                final int productId =
                                                    item['product_id'] as int;
                                                supabase.Product? prod;
                                                try {
                                                  prod = _products.firstWhere(
                                                    (p) => p.id == productId,
                                                  );
                                                } catch (_) {
                                                  prod = null;
                                                }
                                                final String unit =
                                                    (item['unit'] as String?) ??
                                                    '';
                                                final int perUnit =
                                                    prod?.itemsPerWholesaleUnit ??
                                                    1;
                                                final bool isWholesale =
                                                    prod != null &&
                                                    unit.isNotEmpty &&
                                                    prod.unitTypeWholesale !=
                                                        null &&
                                                    unit ==
                                                        prod.unitTypeWholesale &&
                                                    perUnit > 1;
                                                final double price =
                                                    (item['price_per_unit']
                                                            as num)
                                                        .toDouble();

                                                return Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      '${item['quantity']} ${item['unit']} @ ₹${price.toStringAsFixed(2)}',
                                                      style: TextStyle(
                                                        fontSize: 14,
                                                        color: Theme.of(context)
                                                            .textTheme
                                                            .bodyMedium
                                                            ?.color
                                                            ?.withValues(
                                                              alpha: 0.7,
                                                            ),
                                                      ),
                                                    ),
                                                    if (isWholesale) ...[
                                                      const SizedBox(height: 2),
                                                      Text(
                                                        '≈ ₹${(price / perUnit).toStringAsFixed(2)} per piece',
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          color:
                                                              Theme.of(context)
                                                                  .textTheme
                                                                  .bodyMedium
                                                                  ?.color
                                                                  ?.withValues(
                                                                    alpha: 0.55,
                                                                  ),
                                                        ),
                                                      ),
                                                    ],
                                                  ],
                                                );
                                              },
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        'Total: ₹${lineTotal.toStringAsFixed(2)}',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: Theme.of(
                                            context,
                                          ).textTheme.bodyLarge?.color,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      IconButton(
                                        onPressed: () =>
                                            _removeItem(item['product_id']),
                                        icon: const Icon(
                                          Icons.close,
                                          color: Colors.red,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),

                          const SizedBox(height: 16),
                          // Summary row with total amount
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Items: ${_purchaseItems.length}',
                                style: TextStyle(
                                  color: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.color
                                      ?.withValues(alpha: 0.7),
                                ),
                              ),
                              Text(
                                'Total: ₹${_computeTotalAmount().toStringAsFixed(2)}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                  color: Theme.of(
                                    context,
                                  ).textTheme.bodyLarge?.color,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const Divider(),
                        ],

                        if (_purchaseItems.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.primary.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Theme.of(
                                  context,
                                ).colorScheme.primary.withValues(alpha: 0.2),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Payment & Balance Details',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('Previous Balance:'),
                                    Text(
                                      '₹${_availableCredit.toStringAsFixed(2)}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: _availableCredit > 0
                                            ? Colors.red
                                            : Colors.green,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('Current Bill:'),
                                    Text(
                                      '₹${_computeTotalAmount().toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                const Divider(),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'Net Payable:',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      '₹${(_availableCredit + _computeTotalAmount()).toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _paidAmountController,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'Amount Paid Now (₹)',
                                    border: OutlineInputBorder(),
                                    prefixText: '₹',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: 24),

                        // Save Button
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _purchaseItems.isEmpty || _isProcessing
                                ? null
                                : _savePurchase,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFE07B39),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: _isProcessing
                                ? const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      ),
                                      SizedBox(width: 12),
                                      Text('Saving Purchase...'),
                                    ],
                                  )
                                : const Text(
                                    'Save Purchase',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
