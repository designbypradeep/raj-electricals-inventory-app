import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:raj_electricals_inventory_app/models/sales_purchase_models.dart';
import 'package:raj_electricals_inventory_app/services/supabase_service.dart';
import 'package:raj_electricals_inventory_app/models/supabase_models.dart' as supabase_models;
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
                                  onChanged: (v) => setState(() => _refundType = v!),
                                ),
                                const Text('Credit'),
                                const SizedBox(width: 8),
                                Radio<String>(
                                  value: 'cash',
                                  groupValue: _refundType,
                                  onChanged: (v) => setState(() => _refundType = v!),
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
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
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
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () async {
                            if (!_formKey.currentState!.validate()) return;
                            if (_returnItems.isEmpty) {
                              setState(() => _errorMessage = 'Add at least one return item');
                              return;
                            }
                            setState(() => _errorMessage = null);
                            try {
                              await SupabaseService.createPurchaseReturn(
                                supplierName: _supplierNameController.text.trim(),
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
                              if (mounted) setState(() => _successMessage = null);
                            } catch (e) {
                              setState(() => _errorMessage = 'Error saving return: $e');
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
    super.dispose();
  }

  void _onSearchChanged() {
    if (_searchController.text.isEmpty) {
      setState(() {
        _searchResults = [];
      });
      return;
    }
    SupabaseService.searchProductsQuick(_searchController.text).then((products) {
      setState(() {
        _searchResults = products;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Return Item'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: 'Search Product',
                border: OutlineInputBorder(),
              ),
            ),
            if (_searchResults.isNotEmpty)
              SizedBox(
                height: 200,
                width: double.maxFinite,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _searchResults.length,
                  itemBuilder: (context, index) {
                    final product = _searchResults[index];
                    return ListTile(
                      title: Text(product.name),
                      subtitle: Text(product.brand ?? ''),
                      onTap: () {
                        setState(() {
                          _selectedProduct = product;
                          _searchController.text = product.name;
                          _searchResults = [];
                        });
                      },
                    );
                  },
                ),
              ),
            if (_selectedProduct != null) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _quantityController,
                decoration: const InputDecoration(
                  labelText: 'Quantity',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _priceController,
                decoration: const InputDecoration(
                  labelText: 'Price per Unit',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
            ],
          ],
        ),
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
              Navigator.of(context).pop({
                'product': _selectedProduct,
                'quantity': int.parse(_quantityController.text),
                'price': double.parse(_priceController.text),
              });
            }
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}
