import 'package:flutter/material.dart';
import 'package:raj_electricals_inventory_app/models/supabase_models.dart';
import 'package:raj_electricals_inventory_app/services/supabase_service.dart';
import 'package:raj_electricals_inventory_app/widgets/page_header.dart';

class SuppliersPage extends StatefulWidget {
  const SuppliersPage({super.key});

  @override
  _SuppliersPageState createState() => _SuppliersPageState();
}

class _SuppliersPageState extends State<SuppliersPage> {
  List<Supplier> _suppliers = [];
  List<Supplier> _filteredSuppliers = [];
  bool _isLoading = true;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSuppliers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSuppliers() async {
    setState(() => _isLoading = true);
    try {
      final suppliers = await SupabaseService.getSuppliers();
      setState(() {
        _suppliers = suppliers;
        _filteredSuppliers = suppliers;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading suppliers: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _filterSuppliers(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredSuppliers = _suppliers;
      } else {
        _filteredSuppliers = _suppliers
            .where(
              (s) =>
                  s.name.toLowerCase().contains(query.toLowerCase()) ||
                  (s.contactNumber ?? '').toLowerCase().contains(
                    query.toLowerCase(),
                  ),
            )
            .toList();
      }
    });
  }

  Future<void> _showSupplierDialog({Supplier? supplier}) async {
    final result = await showDialog<Supplier>(
      context: context,
      builder: (context) => _SupplierDialog(supplier: supplier),
    );

    if (result != null) {
      try {
        if (supplier == null) {
          await SupabaseService.createSupplier(result);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Supplier added successfully'),
                backgroundColor: Colors.green,
              ),
            );
          }
        } else {
          await SupabaseService.updateSupplier(result);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Supplier updated successfully'),
                backgroundColor: Colors.green,
              ),
            );
          }
        }
        _loadSuppliers();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error saving supplier: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _deleteSupplier(Supplier supplier) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Delete'),
        content: Text('Are you sure you want to delete "${supplier.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await SupabaseService.deleteSupplier(supplier.id!);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Supplier deleted successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
        _loadSuppliers();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error deleting supplier: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 768;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            PageHeader(
              title: 'Suppliers Management',
              description: 'Manage your dealers and suppliers',
              icon: '🤝',
              showBackButton: true,
              stats: [
                PageHeaderStat(
                  label: 'Total Suppliers',
                  value: '${_suppliers.length}',
                  description: 'Active suppliers',
                ),
              ],
            ),
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isMobile ? 12 : 16,
                vertical: 12,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        labelText: 'Search suppliers',
                        prefixIcon: const Icon(Icons.search),
                        border: const OutlineInputBorder(),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _searchController.clear();
                                  _filterSuppliers('');
                                },
                              )
                            : null,
                      ),
                      onChanged: _filterSuppliers,
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: () => _showSupplierDialog(),
                    icon: const Icon(Icons.add),
                    label: Text(isMobile ? 'Add' : 'Add Supplier'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredSuppliers.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.business,
                            size: 64,
                            color: Colors.grey,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _searchController.text.isEmpty
                                ? 'No suppliers yet'
                                : 'No suppliers found',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          ElevatedButton.icon(
                            onPressed: () => _showSupplierDialog(),
                            icon: const Icon(Icons.add),
                            label: const Text('Add First Supplier'),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.symmetric(
                        horizontal: isMobile ? 12 : 16,
                      ),
                      itemCount: _filteredSuppliers.length,
                      itemBuilder: (context, index) {
                        final supplier = _filteredSuppliers[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: ListTile(
                            leading: CircleAvatar(
                              child: Text(
                                supplier.name[0].toUpperCase(),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            title: Text(
                              supplier.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (supplier.contactNumber != null)
                                  Text('📱 ${supplier.contactNumber}'),
                                if (supplier.physicalAddress != null)
                                  Text('📍 ${supplier.physicalAddress}'),
                                if (supplier.advancePay > 0)
                                  Text(
                                    '💰 Advance: ₹${supplier.advancePay.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      color: Colors.green,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit),
                                  onPressed: () =>
                                      _showSupplierDialog(supplier: supplier),
                                  tooltip: 'Edit',
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete,
                                    color: Colors.red,
                                  ),
                                  onPressed: () => _deleteSupplier(supplier),
                                  tooltip: 'Delete',
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SupplierDialog extends StatefulWidget {
  final Supplier? supplier;

  const _SupplierDialog({this.supplier});

  @override
  __SupplierDialogState createState() => __SupplierDialogState();
}

class __SupplierDialogState extends State<_SupplierDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _contactController;
  late final TextEditingController _addressController;
  late final TextEditingController _mapLocationController;
  late final TextEditingController _advancePayController;
  late final TextEditingController _notesController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.supplier?.name ?? '');
    _contactController = TextEditingController(
      text: widget.supplier?.contactNumber ?? '',
    );
    _addressController = TextEditingController(
      text: widget.supplier?.physicalAddress ?? '',
    );
    _mapLocationController = TextEditingController(
      text: widget.supplier?.mapLocation ?? '',
    );
    _advancePayController = TextEditingController(
      text: widget.supplier?.advancePay.toStringAsFixed(2) ?? '0.00',
    );
    _notesController = TextEditingController(
      text: widget.supplier?.notes ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _contactController.dispose();
    _addressController.dispose();
    _mapLocationController.dispose();
    _advancePayController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.supplier == null ? 'Add Supplier' : 'Edit Supplier'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Supplier Name *',
                  border: OutlineInputBorder(),
                ),
                validator: (value) =>
                    value?.trim().isEmpty == true ? 'Name is required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _contactController,
                decoration: const InputDecoration(
                  labelText: 'Contact Number',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.phone),
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _addressController,
                decoration: const InputDecoration(
                  labelText: 'Physical Address',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.location_on),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _mapLocationController,
                decoration: const InputDecoration(
                  labelText: 'Map Location (URL or Lat,Long)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.map),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _advancePayController,
                decoration: const InputDecoration(
                  labelText: 'Advance Payment',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.currency_rupee),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notesController,
                decoration: const InputDecoration(
                  labelText: 'Notes',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.note),
                ),
                maxLines: 3,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              final supplier = Supplier(
                id: widget.supplier?.id,
                businessId: widget.supplier?.businessId ?? '',
                name: _nameController.text.trim(),
                contactNumber: _contactController.text.trim().isEmpty
                    ? null
                    : _contactController.text.trim(),
                physicalAddress: _addressController.text.trim().isEmpty
                    ? null
                    : _addressController.text.trim(),
                mapLocation: _mapLocationController.text.trim().isEmpty
                    ? null
                    : _mapLocationController.text.trim(),
                advancePay: double.tryParse(_advancePayController.text) ?? 0.0,
                notes: _notesController.text.trim().isEmpty
                    ? null
                    : _notesController.text.trim(),
              );
              Navigator.pop(context, supplier);
            }
          },
          child: Text(widget.supplier == null ? 'Add' : 'Update'),
        ),
      ],
    );
  }
}
