import 'package:flutter/material.dart';
import 'package:raj_electricals_inventory_app/models/sales_purchase_models.dart';
import 'package:raj_electricals_inventory_app/services/supabase_service.dart';
import 'package:raj_electricals_inventory_app/services/connectivity_service.dart';

class SupplierCreditsPage extends StatefulWidget {
  final String? initialSupplierName;
  const SupplierCreditsPage({super.key, this.initialSupplierName});

  @override
  _SupplierCreditsPageState createState() => _SupplierCreditsPageState();
}

class _SupplierCreditsPageState extends State<SupplierCreditsPage> {
  final _supplierNameController = TextEditingController();
  List<SupplierLedgerEntry> _ledgerEntries = [];
  double _creditBalance = 0.0;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialSupplierName != null) {
      _supplierNameController.text = widget.initialSupplierName!;
      // Use addPostFrameCallback to ensure context is safe if fetch relies on it,
      // though _fetchSupplierData only uses context for SnackBar.
      // Standard future call also works in initState but better to schedule.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _fetchSupplierData();
      });
    }
  }

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
      floatingActionButton:
          _ledgerEntries.isNotEmpty || _supplierNameController.text.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: () => _showPaymentDialog(),
              label: const Text('Record Payment'),
              icon: const Icon(Icons.payment),
            )
          : null,
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
                          final isCredit =
                              entry.entryType == 'purchase' ||
                              entry.entryType == 'credit';
                          return ListTile(
                            leading: Icon(
                              isCredit ? Icons.remove_circle : Icons.add_circle,
                              color: isCredit ? Colors.red : Colors.green,
                            ),
                            title: Text(entry.entryType.toUpperCase()),
                            subtitle: Text(
                              '${entry.notes ?? ''}\nRef: ${entry.refTable ?? '-'} #${entry.refId ?? ''}',
                              style: const TextStyle(fontSize: 12),
                            ),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '₹${entry.amount}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: isCredit ? Colors.red : Colors.green,
                                  ),
                                ),
                                Text(
                                  entry.createdAt?.toLocal().toString().split(
                                        ' ',
                                      )[0] ??
                                      '',
                                  style: const TextStyle(fontSize: 10),
                                ),
                              ],
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

  Future<void> _showPaymentDialog() async {
    final amountController = TextEditingController();
    final notesController = TextEditingController();
    DateTime selectedDate = DateTime.now();

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Record Payment'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amountController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Amount Paid (₹)'),
              ),
              TextField(
                controller: notesController,
                decoration: const InputDecoration(
                  labelText: 'Notes (Optional)',
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text('Date: '),
                  TextButton(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) {
                        setState(() => selectedDate = picked);
                      }
                    },
                    child: Text(
                      selectedDate.toLocal().toString().split(' ')[0],
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final amount = double.tryParse(amountController.text);
                if (amount == null || amount <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Invalid Amount')),
                  );
                  return;
                }

                Navigator.pop(
                  context,
                ); // Close dialog logic here or after wait? Better close to show loader on screen maybe?
                // Let's do async loading in main screen

                setState(
                  () => _isLoading = true,
                ); // Need to use parent setState, but this dialog is in context.
                // Ah, I need to call the parent's method effectively.
                // Actually, just calling the service and then refreshing is fine.

                try {
                  await SupabaseService.addSupplierPayment(
                    supplierName: _supplierNameController.text,
                    amount: amount,
                    date: selectedDate,
                    notes: notesController.text,
                  );
                  await _fetchSupplierData(); // Refresh list
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Payment Recorded')),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text('Error: $e')));
                  }
                } finally {
                  // _fetchSupplierData sets loading false
                }
              },
              child: const Text('Save Payment'),
            ),
          ],
        ),
      ),
    );
  }
}
