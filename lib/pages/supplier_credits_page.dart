import 'package:flutter/material.dart';
import 'package:raj_electricals_inventory_app/models/sales_purchase_models.dart';
import 'package:raj_electricals_inventory_app/models/supabase_models.dart';
import 'package:raj_electricals_inventory_app/services/supabase_service.dart';
import 'package:raj_electricals_inventory_app/services/connectivity_service.dart';
import 'package:raj_electricals_inventory_app/widgets/page_header.dart';

class SupplierCreditsPage extends StatefulWidget {
  final String? initialSupplierName;
  const SupplierCreditsPage({super.key, this.initialSupplierName});

  @override
  _SupplierCreditsPageState createState() => _SupplierCreditsPageState();
}

class _SupplierCreditsPageState extends State<SupplierCreditsPage> {
  final _supplierNameController = TextEditingController();
  List<SupplierLedgerEntry> _ledgerEntries = [];
  List<Supplier> _allSuppliers = [];
  double _creditBalance = 0.0;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadAllSuppliers();
    if (widget.initialSupplierName != null) {
      _supplierNameController.text = widget.initialSupplierName!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _fetchSupplierData();
      });
    }
  }

  Future<void> _loadAllSuppliers() async {
    try {
      final suppliers = await SupabaseService.getSuppliers();
      if (mounted) {
        setState(() {
          _allSuppliers = suppliers;
        });
      }
    } catch (_) {
      // Silent failure for autocomplete, user can still type
    }
  }

  Future<void> _fetchSupplierData([String? name]) async {
    final searchName = name ?? _supplierNameController.text;
    if (searchName.isEmpty) return;
    if (_supplierNameController.text != searchName) {
      _supplierNameController.text = searchName;
    }

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

    setState(() {
      _isLoading = true;
    });

    try {
      final ledger = await SupabaseService.getSupplierLedger(searchName);
      final balance = await SupabaseService.getSupplierCreditBalance(
        searchName,
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
  void dispose() {
    _supplierNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 768;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      floatingActionButton:
          _ledgerEntries.isNotEmpty || _supplierNameController.text.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: () => _showPaymentDialog(),
              label: const Text('Record Payment'),
              icon: const Icon(Icons.payment),
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
            )
          : null,
      body: SafeArea(
        top: false,
        bottom: true,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: PageHeader(
                title: 'Supplier Credits',
                description: 'Track credits and payments',
                icon: '💳',
                showBackButton: true,
                wrapInSafeArea: true,
                breadcrumbs: [
                  PageHeaderBreadcrumb(label: 'Dashboard', icon: '🏠', href: '/'),
                  if (MediaQuery.of(context).size.width >= 450)
                    PageHeaderBreadcrumb(
                      label: 'Supplier Credits',
                      icon: '💳',
                      current: true,
                    ),
                ],
                stats: [
                  PageHeaderStat(
                    label: 'Entries',
                    value: '${_ledgerEntries.length}',
                    description: 'Transactions',
                  ),
                ],
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  isMobile ? 16 : 24,
                  16,
                  isMobile ? 16 : 24,
                  24,
                ),
                child: Column(
                  children: [
                    // Search Bar with Autocomplete
                    Container(
                      decoration: BoxDecoration(
                        color: theme.cardColor,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.search),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Autocomplete<Supplier>(
                              initialValue: TextEditingValue(
                                text: _supplierNameController.text,
                              ),
                              optionsBuilder:
                                  (TextEditingValue textEditingValue) {
                                    if (textEditingValue.text == '') {
                                      return const Iterable<Supplier>.empty();
                                    }
                                    return _allSuppliers.where((
                                      Supplier option,
                                    ) {
                                      return option.name.toLowerCase().contains(
                                        textEditingValue.text.toLowerCase(),
                                      );
                                    });
                                  },
                              displayStringForOption: (Supplier option) =>
                                  option.name,
                              onSelected: (Supplier selection) {
                                _fetchSupplierData(selection.name);
                              },
                              fieldViewBuilder:
                                  (
                                    context,
                                    textEditingController,
                                    focusNode,
                                    onFieldSubmitted,
                                  ) {
                                    // Sync controllers if needed or just use this one
                                    // We need _supplierNameController to verify state for FAB, so we listen
                                    if (textEditingController.text !=
                                        _supplierNameController.text) {
                                      // Update the independent controller if user types directly
                                      // This is a bit tricky with Autocomplete.
                                      // Ideally we use textEditingController as the main one.
                                      // Let's attach a listener to update our state variable.
                                    }
                                    return TextField(
                                      controller: textEditingController,
                                      focusNode: focusNode,
                                      decoration: const InputDecoration(
                                        hintText: 'Enter Supplier Name',
                                        border: InputBorder.none,
                                      ),
                                      onSubmitted: (value) {
                                        _supplierNameController.text = value;
                                        _fetchSupplierData(value);
                                      },
                                      onChanged: (value) {
                                        _supplierNameController.text = value;
                                        // Trigger rebuild to update FAB visibility
                                        setState(() {});
                                      },
                                    );
                                  },
                              optionsViewBuilder:
                                  (context, onSelected, options) {
                                    return Align(
                                      alignment: Alignment.topLeft,
                                      child: Material(
                                        elevation: 4,
                                        borderRadius: BorderRadius.circular(12),
                                        color: theme.cardColor,
                                        child: ConstrainedBox(
                                          constraints: const BoxConstraints(
                                            maxHeight: 200,
                                            maxWidth: 300,
                                          ),
                                          child: ListView.builder(
                                            padding: EdgeInsets.zero,
                                            shrinkWrap: true,
                                            itemCount: options.length,
                                            itemBuilder:
                                                (
                                                  BuildContext context,
                                                  int index,
                                                ) {
                                                  final Supplier option =
                                                      options.elementAt(index);
                                                  return InkWell(
                                                    onTap: () =>
                                                        onSelected(option),
                                                    child: Padding(
                                                      padding:
                                                          const EdgeInsets.all(
                                                            16.0,
                                                          ),
                                                      child: Text(
                                                        option.name,
                                                        style: TextStyle(
                                                          color: colorScheme
                                                              .onSurface,
                                                        ),
                                                      ),
                                                    ),
                                                  );
                                                },
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    if (_isLoading)
                      const Center(child: CircularProgressIndicator())
                    else if (_ledgerEntries.isNotEmpty) ...[
                      // Balance Card
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              colorScheme.primary,
                              colorScheme.secondary,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: colorScheme.primary.withOpacity(0.3),
                              blurRadius: 20,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Total Balance Due',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.9),
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '₹${_creditBalance.toStringAsFixed(2)}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                letterSpacing: -1,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Ledger List Header
                      Row(
                        children: [
                          Text(
                            'Transaction History',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          const Spacer(),
                          Icon(
                            Icons.history_rounded,
                            size: 16,
                            color: colorScheme.outline,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],
                  ],
                ),
              ),
            ),

            if (!_isLoading && _ledgerEntries.isNotEmpty)
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 24),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final entry = _ledgerEntries[index];
                    final isCredit =
                        entry.entryType == 'purchase' ||
                        entry.entryType == 'credit';

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: theme.cardColor,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: theme.dividerColor.withOpacity(0.5),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.02),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        leading: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: isCredit
                                ? Colors.red.withOpacity(0.1)
                                : Colors.green.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            isCredit
                                ? Icons.remove_circle_outline
                                : Icons.add_circle_outline,
                            color: isCredit ? Colors.red : Colors.green,
                            size: 24,
                          ),
                        ),
                        title: Text(
                          entry.entryType.toUpperCase(),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (entry.notes != null && entry.notes!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  entry.notes!,
                                  style: TextStyle(
                                    color: colorScheme.onSurfaceVariant,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            const SizedBox(height: 4),
                            Text(
                              'Ref: ${entry.refTable ?? '-'} #${entry.refId ?? ''}',
                              style: TextStyle(
                                fontSize: 12,
                                // Using onSurfaceVariant ensures visibility in dark mode
                                color: colorScheme.onSurfaceVariant.withOpacity(
                                  0.7,
                                ),
                              ),
                            ),
                            Text(
                              entry.createdAt?.toLocal().toString().split(
                                    ' ',
                                  )[0] ??
                                  '',
                              style: TextStyle(
                                fontSize: 11,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        trailing: Text(
                          '₹${entry.amount.toStringAsFixed(0)}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: isCredit ? Colors.red : Colors.green,
                          ),
                        ),
                      ),
                    );
                  }, childCount: _ledgerEntries.length),
                ),
              )
            else if (!_isLoading &&
                _ledgerEntries.isEmpty &&
                _supplierNameController.text.isNotEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest
                              .withOpacity(0.5),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.receipt_long_rounded,
                          size: 48,
                          color: colorScheme.outline,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No transactions found',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Try searching for another supplier',
                        style: TextStyle(color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              )
            else if (!_isLoading && _supplierNameController.text.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer.withOpacity(0.3),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.search_rounded,
                          size: 48,
                          color: colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Supplier Credits',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Search for a supplier to view ledger',
                        style: TextStyle(color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
            const SliverPadding(padding: EdgeInsets.only(bottom: 80)),
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
                decoration: InputDecoration(
                  labelText: 'Amount Paid (₹)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: notesController,
                decoration: InputDecoration(
                  labelText: 'Notes (Optional)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text('Date: '),
                  TextButton.icon(
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
                    icon: const Icon(Icons.calendar_today, size: 16),
                    label: Text(
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

                Navigator.pop(context);

                // Use the outer state's setState to show loading
                this.setState(() {
                  _isLoading = true;
                });

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
                      const SnackBar(
                        content: Text(
                          'Payment Recorded',
                          style: TextStyle(color: Colors.white),
                        ),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text('Error: $e')));
                  }
                } finally {
                  if (mounted) {
                    this.setState(() {
                      _isLoading = false;
                    });
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Save Payment'),
            ),
          ],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}
