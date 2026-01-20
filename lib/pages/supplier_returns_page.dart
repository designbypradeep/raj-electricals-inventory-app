import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:raj_electricals_inventory_app/models/sales_purchase_models.dart';
import 'package:raj_electricals_inventory_app/services/supabase_service.dart';
import 'package:raj_electricals_inventory_app/models/supabase_models.dart'
    as supabase_models;
import 'package:raj_electricals_inventory_app/services/connectivity_service.dart';
import 'package:raj_electricals_inventory_app/widgets/page_header.dart';

class SupplierReturnsPage extends StatefulWidget {
  const SupplierReturnsPage({super.key});

  @override
  _SupplierReturnsPageState createState() => _SupplierReturnsPageState();
}

class _SupplierReturnsPageState extends State<SupplierReturnsPage> {
  final _formKey = GlobalKey<FormState>();
  final _supplierNameController = TextEditingController();
  DateTime _returnDate = DateTime.now();
  String _refundType = 'credit';
  final List<PurchaseReturnItemInput> _returnItems = [];
  final List<String> _returnItemNames = [];
  String? _errorMessage;
  String? _successMessage;

  double _computeTotal() {
    double total = 0.0;
    for (int i = 0; i < _returnItems.length; i++) {
      final it = _returnItems[i];
      total += (it.quantity * it.pricePerUnit);
    }
    return total;
  }

  void _addReturnItem(PurchaseReturnItemInput item, String productName) {
    setState(() {
      _returnItems.add(item);
      _returnItemNames.add(productName);
    });
  }

  void _removeReturnItem(int index) {
    setState(() {
      _returnItems.removeAt(index);
      _returnItemNames.removeAt(index);
    });
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _returnDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
    );
    if (picked != null && picked != _returnDate) {
      setState(() {
        _returnDate = picked;
      });
    }
  }

  Future<void> _showAddReturnItemDialog() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => const _AddReturnItemDialog(),
    );

    if (result != null) {
      final product = result['product'] as supabase_models.Product;
      final quantity = result['quantity'] as int;
      final price = result['price'] as double;

      _addReturnItem(
        PurchaseReturnItemInput(
          productId: product.id!,
          quantity: quantity,
          pricePerUnit: price,
        ),
        product.name,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 480;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        top: true,
        bottom: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 12 : 16,
            vertical: isMobile ? 16 : 24,
          ),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                PageHeader(
                  title: 'Supplier Returns & Credits',
                  description:
                      'Record items returned to suppliers and create credit notes or cash refunds',
                  icon: '↩️',
                  showBackButton: true,
                  stats: [
                    PageHeaderStat(
                      label: 'Mode',
                      value: 'Return',
                      description: 'Create supplier return entries',
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Error / Success
                if (_errorMessage != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      border: Border.all(color: Colors.red),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                if (_successMessage != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.1),
                      border: Border.all(color: Colors.green),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Text('✅ '),
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

                // Main card
                Container(
                  padding: EdgeInsets.all(isMobile ? 16 : 20),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    border: Border.all(color: Theme.of(context).dividerColor),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Supplier + Date + Refund Type
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final nameField = TextFormField(
                            controller: _supplierNameController,
                            decoration: const InputDecoration(
                              labelText: 'Supplier Name',
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) {
                              if ((value ?? '').trim().isEmpty) {
                                return 'Please enter a supplier name';
                              }
                              return null;
                            },
                          );

                          final dateField = InkWell(
                            onTap: () => _selectDate(context),
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Return Date',
                                border: OutlineInputBorder(),
                              ),
                              child: Text(DateFormat.yMd().format(_returnDate)),
                            ),
                          );

                          final refundField = InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Refund Type',
                              border: OutlineInputBorder(),
                            ),
                            child: Row(
                              children: [
                                Radio<String>(
                                  value: 'credit',
                                  groupValue: _refundType,
                                  onChanged: (v) =>
                                      setState(() => _refundType = v!),
                                ),
                                const Text('Credit'),
                                const SizedBox(width: 8),
                                Radio<String>(
                                  value: 'cash',
                                  groupValue: _refundType,
                                  onChanged: (v) =>
                                      setState(() => _refundType = v!),
                                ),
                                const Text('Cash'),
                              ],
                            ),
                          );

                          if (constraints.maxWidth > 768) {
                            return Row(
                              children: [
                                Expanded(child: nameField),
                                const SizedBox(width: 16),
                                Expanded(child: dateField),
                                const SizedBox(width: 16),
                                Expanded(child: refundField),
                              ],
                            );
                          }
                          return Column(
                            children: [
                              nameField,
                              const SizedBox(height: 12),
                              dateField,
                              const SizedBox(height: 12),
                              refundField,
                            ],
                          );
                        },
                      ),

                      const SizedBox(height: 20),
                      const Divider(),
                      const SizedBox(height: 12),
                      const Text(
                        'Return Items',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildReturnItemsList(),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _showAddReturnItemDialog,
                          icon: const Icon(Icons.add),
                          label: const Text('Add Item'),
                        ),
                      ),

                      const Divider(),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Total Amount',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          Text(
                            '₹${_computeTotal().toStringAsFixed(2)}',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () async {
                            if (!ConnectivityService().isOnline.value) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'You are offline. Cannot save return.',
                                  ),
                                ),
                              );
                              return;
                            }
                            if (!_formKey.currentState!.validate()) return;
                            if (_returnItems.isEmpty) {
                              setState(
                                () => _errorMessage =
                                    'Add at least one return item',
                              );
                              return;
                            }
                            setState(() => _errorMessage = null);
                            try {
                              await SupabaseService.createPurchaseReturn(
                                supplierName: _supplierNameController.text
                                    .trim(),
                                returnDate: _returnDate,
                                refundType: _refundType,
                                items: _returnItems,
                              );
                              setState(() {
                                _successMessage = 'Return saved successfully!';
                                _formKey.currentState!.reset();
                                _supplierNameController.clear();
                                _returnItems.clear();
                                _returnItemNames.clear();
                                _returnDate = DateTime.now();
                                _refundType = 'credit';
                              });
                              await Future.delayed(const Duration(seconds: 2));
                              if (mounted) {
                                setState(() => _successMessage = null);
                              }
                            } catch (e) {
                              setState(
                                () => _errorMessage = 'Error saving return: $e',
                              );
                            }
                          },
                          child: const Text('Save Return'),
                        ),
                      ),
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

  Widget _buildReturnItemsList() {
    if (_returnItems.isEmpty) {
      return const Center(child: Text('No items added to the return.'));
    }

    return ListView.builder(
      shrinkWrap: true,
      itemCount: _returnItems.length,
      itemBuilder: (context, index) {
        final item = _returnItems[index];
        final itemName = _returnItemNames[index];
        return ListTile(
          title: Text(itemName),
          subtitle: Text('Quantity: ${item.quantity} @ ${item.pricePerUnit}'),
          trailing: IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () => _removeReturnItem(index),
          ),
        );
      },
    );
  }
}

class _AddReturnItemDialog extends StatefulWidget {
  const _AddReturnItemDialog();

  @override
  __AddReturnItemDialogState createState() => __AddReturnItemDialogState();
}

class __AddReturnItemDialogState extends State<_AddReturnItemDialog> {
  final _searchController = TextEditingController();
  List<supabase_models.Product> _searchResults = [];
  supabase_models.Product? _selectedProduct;
  final _quantityController = TextEditingController();
  final _priceController = TextEditingController();
  final _totalController = TextEditingController();

  String _pricingMode = 'rate'; // 'rate' | 'total'
  String _selectedUnit = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _quantityController.dispose();
    _priceController.dispose();
    _totalController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (_searchController.text.isEmpty) {
      setState(() {
        _searchResults = [];
      });
      return;
    }
    SupabaseService.searchProductsQuick(_searchController.text).then((
      products,
    ) {
      if (mounted) {
        setState(() {
          _searchResults = products;
        });
      }
    });
  }

  void _onProductSelected(supabase_models.Product product) {
    setState(() {
      _selectedProduct = product;
      _searchController.text = product.name;
      _searchResults = [];
      _selectedUnit = product.unitTypeSingle ?? 'Piece';
      // Default to purchase price
      _priceController.text = (product.purchasePrice ?? 0.0).toStringAsFixed(2);
      _quantityController.text = '1';
      _calculateTotal();
    });
  }

  void _calculateTotal() {
    final qty = double.tryParse(_quantityController.text) ?? 0.0;
    final rate = double.tryParse(_priceController.text) ?? 0.0;
    _totalController.text = (qty * rate).toStringAsFixed(2);
  }

  void _calculateRate() {
    final qty = double.tryParse(_quantityController.text) ?? 0.0;
    final total = double.tryParse(_totalController.text) ?? 0.0;
    if (qty > 0) {
      _priceController.text = (total / qty).toStringAsFixed(2);
    }
  }

  void _handleUnitChange(String? newUnit) {
    if (newUnit == null || newUnit == _selectedUnit) return;
    if (_selectedProduct == null) return;

    final oldUnit = _selectedUnit;
    double currentRate = double.tryParse(_priceController.text) ?? 0.0;

    final single = _selectedProduct!.unitTypeSingle ?? 'Piece';
    final wholesale = _selectedProduct!.unitTypeWholesale;
    final multiplier = (_selectedProduct!.itemsPerWholesaleUnit ?? 1)
        .toDouble();

    if (multiplier > 1 && wholesale != null) {
      if (oldUnit == single && newUnit == wholesale) {
        // Switch to Wholesale: Scale Rate UP
        currentRate = currentRate * multiplier;
      } else if (oldUnit == wholesale && newUnit == single) {
        // Switch to Single: Scale Rate DOWN
        currentRate = currentRate / multiplier;
      }
    }

    setState(() {
      _selectedUnit = newUnit;
      _priceController.text = currentRate.toStringAsFixed(2);
      // Recalculate based on current mode
      if (_pricingMode == 'rate') {
        _calculateTotal();
      } else {
        // If total mode, total stays same, rate implies quantity change?
        // No, typically in 'Total' mode, if we change unit, we probably want to keep Total fixed
        // and adjust Rate? Or keep Scale Rate and adjust Total?
        // purchase_page.dart scales rate and re-calcs total implicitly via controller update.
        // Let's stick to standard behavior: Unit change affects Rate. Total gets re-calc'd.
        _calculateTotal();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isProductSelected = _selectedProduct != null;

    return AlertDialog(
      title: const Text('Add Return Item'),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _searchController,
            decoration: const InputDecoration(
              labelText: 'Search Product',
              border: OutlineInputBorder(),
              suffixIcon: Icon(Icons.search),
            ),
          ),
          if (_searchResults.isNotEmpty)
            Container(
              height: 150,
              margin: const EdgeInsets.only(top: 8),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(4),
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _searchResults.length,
                itemBuilder: (context, index) {
                  final p = _searchResults[index];
                  return ListTile(
                    title: Text(p.name),
                    subtitle: Text('${p.brand ?? ''} (${p.currentStock})'),
                    onTap: () => _onProductSelected(p),
                    dense: true,
                  );
                },
              ),
            ),

          if (isProductSelected) ...[
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),

            // Unit Selection
            DropdownButtonFormField<String>(
              value: _selectedUnit.isNotEmpty ? _selectedUnit : null,
              decoration: const InputDecoration(
                labelText: 'Unit',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
              ),
              items: [
                if (_selectedProduct?.unitTypeSingle != null)
                  DropdownMenuItem(
                    value: _selectedProduct!.unitTypeSingle,
                    child: Text(_selectedProduct!.unitTypeSingle!),
                  ),
                if (_selectedProduct?.unitTypeWholesale != null &&
                    _selectedProduct!.unitTypeWholesale !=
                        _selectedProduct!.unitTypeSingle)
                  DropdownMenuItem(
                    value: _selectedProduct!.unitTypeWholesale,
                    child: Text(_selectedProduct!.unitTypeWholesale!),
                  ),
              ],
              onChanged: _handleUnitChange,
            ),
            const SizedBox(height: 16),

            // Pricing Mode Toggle using standard flutter widgets instead of SegmentedButton
            // to avoid import issues if Material 3 isn't fully set up or just for simplicity
            Row(
              children: [
                const Text(
                  'Pricing Mode:',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(width: 12),
                ChoiceChip(
                  label: const Text('Rate'),
                  selected: _pricingMode == 'rate',
                  onSelected: (selected) {
                    if (selected) setState(() => _pricingMode = 'rate');
                  },
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Total'),
                  selected: _pricingMode == 'total',
                  onSelected: (selected) {
                    if (selected) setState(() => _pricingMode = 'total');
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Quantity
            TextField(
              controller: _quantityController,
              decoration: const InputDecoration(
                labelText: 'Quantity',
                border: OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) {
                if (_pricingMode == 'rate') {
                  _calculateTotal();
                } else {
                  _calculateRate();
                }
              },
            ),
            const SizedBox(height: 16),

            // Rate Input
            TextField(
              controller: _priceController,
              decoration: InputDecoration(
                labelText: 'Rate per Unit',
                border: const OutlineInputBorder(),
                filled: _pricingMode == 'total',
                fillColor: _pricingMode == 'total'
                    ? Colors.grey.shade100
                    : null,
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              readOnly: _pricingMode == 'total',
              onChanged: (_) {
                if (_pricingMode == 'rate') _calculateTotal();
              },
            ),
            const SizedBox(height: 16),

            // Total Input
            TextField(
              controller: _totalController,
              decoration: InputDecoration(
                labelText: 'Total Amount',
                border: const OutlineInputBorder(),
                filled: _pricingMode == 'rate',
                fillColor: _pricingMode == 'rate' ? Colors.grey.shade100 : null,
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              readOnly: _pricingMode == 'rate',
              onChanged: (_) {
                if (_pricingMode == 'total') _calculateRate();
              },
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_selectedProduct != null &&
                _quantityController.text.isNotEmpty &&
                _priceController.text.isNotEmpty) {
              // Conversion Logic
              double qty = double.parse(_quantityController.text);
              double price = double.parse(_priceController.text);

              // If wholesale unit selected, convert to single units for backend
              final wholesale = _selectedProduct!.unitTypeWholesale;
              final multiplier = (_selectedProduct!.itemsPerWholesaleUnit ?? 1)
                  .toDouble();

              if (wholesale != null &&
                  _selectedUnit == wholesale &&
                  multiplier > 1) {
                // Return = Box. Backend = Piece.
                // Qty 1 Box = 10 Pieces.
                qty = qty * multiplier;
                // Price 100/Box = 10/Piece.
                price = price / multiplier;
              }

              Navigator.of(context).pop({
                'product': _selectedProduct,
                'quantity': qty.toInt(), // Backend expects int
                'price': price,
              });
            }
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}
