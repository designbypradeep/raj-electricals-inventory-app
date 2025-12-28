import 'package:flutter/material.dart';
import 'package:raj_electricals_inventory_app/models/sales_purchase_models.dart';
import 'package:raj_electricals_inventory_app/services/supabase_service.dart';
import 'package:raj_electricals_inventory_app/services/connectivity_service.dart';

class SupplierCreditsPage extends StatefulWidget {
  const SupplierCreditsPage({super.key});

  @override
  _SupplierCreditsPageState createState() => _SupplierCreditsPageState();
}

class _SupplierCreditsPageState extends State<SupplierCreditsPage> {
  final _supplierNameController = TextEditingController();
  List<SupplierLedgerEntry> _ledgerEntries = [];
  double _creditBalance = 0.0;
  bool _isLoading = false;

  Future<void> _fetchSupplierData() async {
    if (!ConnectivityService().isOnline.value) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You are offline. Cannot search supplier data.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }
    if (_supplierNameController.text.isEmpty) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final ledger = await SupabaseService.getSupplierLedger(
        _supplierNameController.text,
      );
      final balance = await SupabaseService.getSupplierCreditBalance(
        _supplierNameController.text,
      );

      setState(() {
        _ledgerEntries = ledger;
        _creditBalance = balance;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error fetching data: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Supplier Credits')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _supplierNameController,
                    decoration: const InputDecoration(
                      labelText: 'Supplier Name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _fetchSupplierData,
                  child: const Text('Search'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_isLoading)
              const CircularProgressIndicator()
            else if (_ledgerEntries.isNotEmpty)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Credit Balance: $_creditBalance',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _ledgerEntries.length,
                        itemBuilder: (context, index) {
                          final entry = _ledgerEntries[index];
                          return ListTile(
                            title: Text(entry.entryType),
                            subtitle: Text(
                              'Amount: ${entry.amount} - Ref: ${entry.refTable} #${entry.refId}',
                            ),
                            trailing: Text(
                              entry.createdAt?.toLocal().toString() ?? '',
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              )
            else
              const Text('No data for this supplier.'),
          ],
        ),
      ),
    );
  }
}
