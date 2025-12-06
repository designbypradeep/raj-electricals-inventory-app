import 'package:flutter/material.dart';
import 'package:raj_electricals_inventory_app/theme/ui_tokens.dart';
import '../widgets/page_header.dart';
import '../data/app_database.dart';
import '../services/supabase_service.dart';

class ProcessReplacementPage extends StatefulWidget {
  final AppDatabase db;
  const ProcessReplacementPage({super.key, required this.db});

  @override
  State<ProcessReplacementPage> createState() => _ProcessReplacementPageState();
}

class _ProcessReplacementPageState extends State<ProcessReplacementPage> {
  // Selected sale and items
  Map<String, dynamic>? _selectedSale;
  List<Map<String, dynamic>> _itemsOut =
      []; // quantity_returned, price_per_unit, item_condition
  List<Map<String, dynamic>> _itemsIn = []; // quantity_given, price_per_unit

  // Form fields
  String _customerName = '';
  String _replacementReason = '';
  String _notes = '';
  bool _isSubmitting = false;

  // Controllers
  late TextEditingController _customerNameController;

  // Optional prefill from an existing Return
  int? _prefilledReturnId;
  Map<String, dynamic>? _prefilledReturn;
  bool _isPrefilling = false;

  // Search state
  String _saleSearch = '';
  List<Map<String, dynamic>> _saleResults = [];
  bool _isSaleSearching = false;

  String _productSearch = '';
  List<Map<String, dynamic>> _productResults = [];
  bool _isProductSearching = false;

  // Returns import search state
  String _returnSearch = '';
  List<Map<String, dynamic>> _returnResults = [];
  bool _isReturnSearching = false;

  // Entry mode: 'sale' or 'return'
  String _entryMode = 'sale';

  double get _totalOutAmount {
    return _itemsOut.fold<double>(
      0,
      (sum, it) =>
          sum +
          ((it['quantity_returned'] as num) * (it['price_per_unit'] as num))
              .toDouble(),
    );
  }

  Future<void> _prefillFromSale(int saleId) async {
    try {
      final results = await SupabaseService.searchSales('$saleId');
      if (results.isNotEmpty) {
        final sale = Map<String, dynamic>.from(results.first as Map);
        _selectSale(sale);
      }
    } catch (_) {}
  }

  Widget _buildStepper() {
    final theme = Theme.of(context);
    final step1Done = _selectedSale != null;
    final step2Done = _validItemsOut.isNotEmpty;
    final step3Done = _validItemsIn.isNotEmpty;
    final step4Done =
        step1Done &&
        (step2Done || step3Done) &&
        _customerName.trim().isNotEmpty &&
        _replacementReason.trim().isNotEmpty;

    final current = !step1Done ? 1 : (!step2Done ? 2 : (!step3Done ? 3 : 4));

    Widget dot(int index, String label, bool done, bool active) {
      final bg = done
          ? theme.colorScheme.primary
          : (active
                ? theme.colorScheme.tertiary
                : theme.colorScheme.surfaceContainerHighest);
      final fg = done
          ? theme.colorScheme.onPrimary
          : (active
                ? theme.colorScheme.onTertiary
                : theme.textTheme.bodyMedium?.color);
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: theme.dividerColor.withValues(alpha: 0.3),
              ),
            ),
            child: Text(
              '$index',
              style: TextStyle(
                color: fg,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: 110,
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                color: theme.textTheme.bodyMedium?.color?.withValues(
                  alpha: 0.75,
                ),
              ),
            ),
          ),
        ],
      );
    }

    Widget bar() => Expanded(
      child: Container(
        height: 2,
        margin: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: theme.dividerColor.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(99),
        ),
      ),
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.2)),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final isWide = c.maxWidth >= 680;
          final steps = [
            {'i': 1, 't': 'Select Sale / Import Return', 'd': step1Done},
            {'i': 2, 't': 'Mark Returned Items', 'd': step2Done},
            {'i': 3, 't': 'Add Replacement Items', 'd': step3Done},
            {'i': 4, 't': 'Review & Submit', 'd': step4Done},
          ];
          if (isWide) {
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                dot(
                  steps[0]['i'] as int,
                  steps[0]['t'] as String,
                  steps[0]['d'] as bool,
                  current == 1,
                ),
                bar(),
                dot(
                  steps[1]['i'] as int,
                  steps[1]['t'] as String,
                  steps[1]['d'] as bool,
                  current == 2,
                ),
                bar(),
                dot(
                  steps[2]['i'] as int,
                  steps[2]['t'] as String,
                  steps[2]['d'] as bool,
                  current == 3,
                ),
                bar(),
                dot(
                  steps[3]['i'] as int,
                  steps[3]['t'] as String,
                  steps[3]['d'] as bool,
                  current == 4,
                ),
              ],
            );
          }
          return Wrap(
            spacing: 16,
            runSpacing: 10,
            alignment: WrapAlignment.spaceBetween,
            children: [
              dot(
                steps[0]['i'] as int,
                steps[0]['t'] as String,
                steps[0]['d'] as bool,
                current == 1,
              ),
              dot(
                steps[1]['i'] as int,
                steps[1]['t'] as String,
                steps[1]['d'] as bool,
                current == 2,
              ),
              dot(
                steps[2]['i'] as int,
                steps[2]['t'] as String,
                steps[2]['d'] as bool,
                current == 3,
              ),
              dot(
                steps[3]['i'] as int,
                steps[3]['t'] as String,
                steps[3]['d'] as bool,
                current == 4,
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _customerNameController = TextEditingController(text: _customerName);
    // Read route args after first frame to allow ModalRoute access
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkRouteArgs());
  }

  @override
  void dispose() {
    _customerNameController.dispose();
    super.dispose();
  }

  double get _totalInAmount {
    return _itemsIn.fold<double>(
      0,
      (sum, it) =>
          sum +
          ((it['quantity_given'] as num) * (it['price_per_unit'] as num))
              .toDouble(),
    );
  }

  double get _priceDifference => _totalInAmount - _totalOutAmount;

  List<Map<String, dynamic>> get _validItemsOut =>
      _itemsOut.where((e) => (e['quantity_returned'] as num) > 0).toList();
  List<Map<String, dynamic>> get _validItemsIn =>
      _itemsIn.where((e) => (e['quantity_given'] as num) > 0).toList();

  Future<void> _searchSales() async {
    final q = _saleSearch.trim();
    if (q.isEmpty) {
      setState(() => _saleResults = []);
      return;
    }
    setState(() => _isSaleSearching = true);
    try {
      final results = await SupabaseService.searchSales(q);
      setState(() => _saleResults = results);
    } catch (_) {
      setState(() => _saleResults = []);
    } finally {
      if (mounted) setState(() => _isSaleSearching = false);
    }
  }

  Future<void> _searchProducts() async {
    final q = _productSearch.trim();
    if (q.isEmpty) {
      setState(() => _productResults = []);
      return;
    }
    setState(() => _isProductSearching = true);
    try {
      final results = await SupabaseService.searchProducts(q);
      setState(() => _productResults = results);
    } catch (_) {
      setState(() => _productResults = []);
    } finally {
      if (mounted) setState(() => _isProductSearching = false);
    }
  }

  void _selectSale(Map<String, dynamic> sale) {
    setState(() {
      _selectedSale = sale;
      _customerName = (sale['customer_name'] as String?) ?? '';
      _customerNameController.text = _customerName;
      // Build itemsOut from sales_items
      final List items = (sale['sales_items'] as List?) ?? const [];
      _itemsOut = items.map<Map<String, dynamic>>((it) {
        final prod = (it['products'] as Map<String, dynamic>?) ?? const {};
        final qty = (it['quantity'] as num?)?.toInt() ?? 0;
        final price = (it['price_per_unit'] as num?)?.toDouble() ?? 0.0;
        return {
          'product_id': it['product_id'],
          'product_name': it['product_name'] ?? prod['name'] ?? 'Item',
          'original_quantity': qty,
          'quantity_returned': 0,
          'price_per_unit': price,
          'item_condition': 'good',
        };
      }).toList();
      _itemsIn = [];
      _saleSearch = '';
      _saleResults = [];
    });
  }

  void _addReplacementProduct(Map<String, dynamic> product) {
    setState(() {
      final idx = _itemsIn.indexWhere((e) => e['product_id'] == product['id']);
      if (idx >= 0) {
        _itemsIn[idx]['quantity_given'] =
            (_itemsIn[idx]['quantity_given'] as int) + 1;
      } else {
        _itemsIn.add({
          'product_id': product['id'],
          'product_name': product['name'] ?? 'Item',
          'quantity_given': 1,
          'price_per_unit':
              (product['selling_price'] as num?)?.toDouble() ?? 0.0,
        });
      }
      _productSearch = '';
      _productResults = [];
    });
  }

  void _removeReplacementProduct(int index) {
    setState(() {
      _itemsIn.removeAt(index);
    });
  }

  Future<void> _submitReplacement() async {
    if (_selectedSale == null) return;
    if (_validItemsOut.isEmpty && _validItemsIn.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add at least one returned or replacement item.'),
        ),
      );
      return;
    }
    if (_customerName.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Customer name is required.')),
      );
      return;
    }
    if (_replacementReason.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a replacement reason.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await SupabaseService.createReplacement(
        originalSaleId: _selectedSale!['id'] as int,
        customerName: _customerName.trim(),
        replacementReason: _replacementReason.trim(),
        notes: _notes.trim(),
        itemsOut: _validItemsOut,
        itemsIn: _validItemsIn,
        amountDifference: _priceDifference,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Replacement processed successfully')),
      );

      setState(() {
        _selectedSale = null;
        _itemsOut = [];
        _itemsIn = [];
        _customerName = '';
        _replacementReason = '';
        _notes = '';
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to process replacement: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        top: true,
        bottom: false,
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: MediaQuery.of(context).size.width < 480 ? 12 : 16,
              vertical: MediaQuery.of(context).size.width < 480 ? 8 : 12,
            ),
            child: Column(
              children: [
                PageHeader(
                  title: 'Process Replacements',
                  description: 'Handle product exchanges and replacements',
                  icon: '🔄',
                  showBackButton: true,
                  backLabel: 'Back to Dashboard',
                  breadcrumbs: [
                    PageHeaderBreadcrumb(label: 'Dashboard', icon: '🏠'),
                    PageHeaderBreadcrumb(
                      label: 'Replacements',
                      icon: '🔄',
                      current: true,
                    ),
                  ],
                ),

                // Entry mode switch and stepper
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: Theme.of(
                                  context,
                                ).dividerColor.withValues(alpha: 0.35),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Text(
                                  'Workflow',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ChoiceChip(
                            label: const Text('From Sale'),
                            selected: _entryMode == 'sale',
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            labelPadding: EdgeInsets.zero,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                            labelStyle: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                            shape: StadiumBorder(
                              side: BorderSide(
                                color: Theme.of(
                                  context,
                                ).dividerColor.withValues(alpha: 0.4),
                              ),
                            ),
                            selectedColor: Theme.of(
                              context,
                            ).colorScheme.primary.withValues(alpha: 0.12),
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                            onSelected: (v) {
                              if (!v) return;
                              setState(() => _entryMode = 'sale');
                            },
                          ),
                          ChoiceChip(
                            label: const Text('From Return'),
                            selected: _entryMode == 'return',
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            labelPadding: EdgeInsets.zero,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                            labelStyle: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                            shape: StadiumBorder(
                              side: BorderSide(
                                color: Theme.of(
                                  context,
                                ).dividerColor.withValues(alpha: 0.4),
                              ),
                            ),
                            selectedColor: Theme.of(
                              context,
                            ).colorScheme.primary.withValues(alpha: 0.12),
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                            onSelected: (v) async {
                              if (!v) return;
                              setState(() => _entryMode = 'return');
                              if (_prefilledReturnId == null) {
                                _openImportReturns();
                              }
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _buildStepper(),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),

                if (_prefilledReturnId != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Theme.of(
                            context,
                          ).dividerColor.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Text('ℹ️'),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _isPrefilling
                                  ? 'Prefilling from return…'
                                  : 'Prefilled from Return #${_prefilledReturn?['return_number'] ?? _prefilledReturnId} linked to Sale S-${_selectedSale?['id'] ?? ''}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                Padding(
                  padding: const EdgeInsets.all(12),
                  child: LayoutBuilder(
                    builder: (context, c) {
                      final isXL = c.maxWidth >= 1200;
                      final isLG = c.maxWidth >= 992 && c.maxWidth < 1200;
                      final spacing = isXL ? 16.0 : 12.0;
                      final columns = isXL ? 3 : (isLG ? 2 : 1);
                      final totalSpacing = spacing * (columns - 1);
                      final colWidth = columns > 1
                          ? (c.maxWidth - totalSpacing) / columns
                          : c.maxWidth;

                      return Flex(
                        direction: columns > 1
                            ? Axis.horizontal
                            : Axis.vertical,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          // Sale Selection
                          SizedBox(
                            width: colWidth,
                            child: _buildSaleSelection(),
                          ),
                          SizedBox(
                            width: columns > 1 ? spacing : 0,
                            height: columns > 1 ? 0 : spacing,
                          ),
                          // Items Out
                          SizedBox(width: colWidth, child: _buildItemsOut()),
                          SizedBox(
                            width: columns > 1 ? spacing : 0,
                            height: columns > 1 ? 0 : spacing,
                          ),
                          // Items In
                          SizedBox(width: colWidth, child: _buildItemsIn()),
                        ],
                      );
                    },
                  ),
                ),
                if (_selectedSale != null &&
                    (_validItemsOut.isNotEmpty || _validItemsIn.isNotEmpty))
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    child: _buildCompleteReplacementForm(),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(UITokens.radius),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).shadowColor.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildSaleSelection() {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '🧾 Select Original Sale',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          if (_selectedSale == null) ...[
            TextField(
              decoration: InputDecoration(
                hintText: 'Search by sale ID or customer...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                isDense: true,
              ),
              onChanged: (v) {
                setState(() => _saleSearch = v);
                _searchSales();
              },
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: _openImportReturns,
                icon: const Icon(Icons.import_export, size: 16),
                label: const Text('Import from Return'),
              ),
            ),
            const SizedBox(height: 10),
            if (_isSaleSearching)
              const Center(child: CircularProgressIndicator()),
            if (!_isSaleSearching && _saleResults.isNotEmpty)
              SizedBox(
                height: 320,
                child: ListView.separated(
                  itemCount: _saleResults.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, idx) {
                    final sale = _saleResults[idx];
                    final items = (sale['sales_items'] as List?) ?? const [];
                    return ListTile(
                      onTap: () => _selectSale(sale),
                      title: Text('Sale S-${sale['id']}'),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(sale['customer_name'] ?? 'Walk-in Customer'),
                          Text(
                            (sale['created_at'] as String?) ?? '',
                            style: TextStyle(
                              color: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.color
                                  ?.withValues(alpha: 0.7),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      trailing: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('₹${(sale['total_amount'] ?? 0).toString()}'),
                          Text(
                            '${items.length} items',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            if (!_isSaleSearching &&
                _saleResults.isEmpty &&
                _saleSearch.isNotEmpty)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Center(
                  child: Text('No sales found matching your search.'),
                ),
              ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Sale S-${_selectedSale!['id']}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          _selectedSale!['customer_name'] ?? 'Walk-in Customer',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      setState(() {
                        _selectedSale = null;
                        _itemsOut = [];
                        _itemsIn = [];
                      });
                    },
                    icon: const Icon(Icons.close),
                    tooltip: 'Clear selection',
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildItemsOut() {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '↩️ Items Being Returned',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          if (_selectedSale == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text('Select a sale to choose items for return'),
              ),
            )
          else ...[
            ..._itemsOut.map((item) {
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(
                      context,
                    ).dividerColor.withValues(alpha: 0.2),
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: LayoutBuilder(
                  builder: (context, c) {
                    final narrow = c.maxWidth < 380;
                    final info = Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item['product_name'] ?? 'Item',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            'Available: ${item['original_quantity']} × ₹${(item['price_per_unit'] as num).toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.color
                                  ?.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    );
                    final qty = SizedBox(
                      width: 60,
                      child: TextFormField(
                        initialValue: (item['quantity_returned']).toString(),
                        onChanged: (v) {
                          final n = int.tryParse(v) ?? 0;
                          setState(
                            () => item['quantity_returned'] = n.clamp(
                              0,
                              (item['original_quantity'] as int),
                            ),
                          );
                        },
                        decoration: const InputDecoration(isDense: true),
                        keyboardType: TextInputType.number,
                      ),
                    );
                    final cond = DropdownButton<String>(
                      value: (item['item_condition'] as String?) ?? 'good',
                      items: const [
                        DropdownMenuItem(value: 'good', child: Text('Good')),
                        DropdownMenuItem(
                          value: 'damaged',
                          child: Text('Damaged'),
                        ),
                        DropdownMenuItem(
                          value: 'defective',
                          child: Text('Defective'),
                        ),
                      ],
                      onChanged: (v) =>
                          setState(() => item['item_condition'] = v ?? 'good'),
                    );
                    if (narrow) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // info block
                          Row(children: [info]),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              qty,
                              const SizedBox(width: 8),
                              Flexible(
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: cond,
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                    } else {
                      return Row(
                        children: [info, qty, const SizedBox(width: 8), cond],
                      );
                    }
                  },
                ),
              );
            }),
            if (_validItemsOut.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Total Return Value:',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '-₹${_totalOutAmount.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Colors.red,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildItemsIn() {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '🔁 Replacement Items',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          TextField(
            decoration: InputDecoration(
              hintText: 'Search products to add as replacements...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              isDense: true,
            ),
            onChanged: (v) {
              setState(() => _productSearch = v);
              _searchProducts();
            },
          ),
          const SizedBox(height: 8),
          if (_isProductSearching)
            const Center(child: CircularProgressIndicator()),
          if (!_isProductSearching && _productResults.isNotEmpty)
            SizedBox(
              height: 220,
              child: ListView.separated(
                itemCount: _productResults.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, idx) {
                  final p = _productResults[idx];
                  return ListTile(
                    onTap: () => _addReplacementProduct(p),
                    title: Text(p['name'] ?? 'Item'),
                    subtitle: Text(
                      'Stock: ${p['current_stock'] ?? 0}  |  ₹${(p['selling_price'] ?? 0).toString()}',
                    ),
                    trailing: const Text(
                      '+ Add',
                      style: TextStyle(color: Colors.blue),
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 8),
          if (_itemsIn.isNotEmpty) ...[
            const Text(
              'Selected Items:',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            ..._itemsIn.asMap().entries.map((e) {
              final index = e.key;
              final item = e.value;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: LayoutBuilder(
                  builder: (context, c) {
                    final narrow = c.maxWidth < 360;
                    final info = Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item['product_name'] ?? 'Item',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            '₹${(item['price_per_unit'] as num).toStringAsFixed(2)} each',
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.color
                                  ?.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    );
                    final qty = SizedBox(
                      width: 60,
                      child: TextFormField(
                        initialValue: (item['quantity_given']).toString(),
                        onChanged: (v) {
                          final n = int.tryParse(v) ?? 0;
                          setState(
                            () => item['quantity_given'] = n < 1 ? 1 : n,
                          );
                        },
                        decoration: const InputDecoration(isDense: true),
                        keyboardType: TextInputType.number,
                      ),
                    );
                    final removeBtn = IconButton(
                      onPressed: () => _removeReplacementProduct(index),
                      icon: const Icon(Icons.close, color: Colors.redAccent),
                      tooltip: 'Remove',
                    );
                    if (narrow) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [info]),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              qty,
                              const SizedBox(width: 8),
                              removeBtn,
                            ],
                          ),
                        ],
                      );
                    } else {
                      return Row(
                        children: [
                          info,
                          qty,
                          const SizedBox(width: 8),
                          removeBtn,
                        ],
                      );
                    }
                  },
                ),
              );
            }),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Total Replacement Value:',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    '+₹${_totalInAmount.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Colors.green,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCompleteReplacementForm() {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Complete Replacement',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, c) {
              final isWide = c.maxWidth >= 768;
              return Flex(
                direction: isWide ? Axis.horizontal : Axis.vertical,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Customer Name',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _customerNameController,
                          onChanged: (v) => _customerName = v,
                          decoration: InputDecoration(
                            isDense: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                color: Theme.of(context).dividerColor,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: isWide ? 12 : 0, height: isWide ? 0 : 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Replacement Reason',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        DropdownButtonFormField<String>(
                          initialValue: _replacementReason.isEmpty
                              ? null
                              : _replacementReason,
                          items: const [
                            DropdownMenuItem(
                              value: 'defective',
                              child: Text('Defective/Damaged'),
                            ),
                            DropdownMenuItem(
                              value: 'wrong_item',
                              child: Text('Wrong Item'),
                            ),
                            DropdownMenuItem(
                              value: 'size_exchange',
                              child: Text('Size/Variant Exchange'),
                            ),
                            DropdownMenuItem(
                              value: 'upgrade',
                              child: Text('Product Upgrade'),
                            ),
                            DropdownMenuItem(
                              value: 'customer_preference',
                              child: Text('Customer Preference'),
                            ),
                            DropdownMenuItem(
                              value: 'other',
                              child: Text('Other'),
                            ),
                          ],
                          onChanged: (v) =>
                              setState(() => _replacementReason = v ?? ''),
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          const Text(
            'Notes (Optional)',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          TextField(
            minLines: 3,
            maxLines: 5,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            onChanged: (v) => _notes = v,
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Items Returned:'),
                    Text(
                      '-₹${_totalOutAmount.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Replacement Items:'),
                    Text(
                      '+₹${_totalInAmount.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Price Difference:',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '${_priceDifference >= 0 ? '+' : ''}₹${_priceDifference.toStringAsFixed(2)}',
                      style: TextStyle(
                        color: _priceDifference >= 0
                            ? Colors.green
                            : Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _priceDifference > 0
                      ? 'Customer pays additional amount'
                      : _priceDifference < 0
                      ? 'Customer receives refund'
                      : 'Even exchange',
                  style: TextStyle(
                    color: Theme.of(
                      context,
                    ).textTheme.bodySmall?.color?.withValues(alpha: 0.7),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed:
                  _isSubmitting ||
                      _selectedSale == null ||
                      (_validItemsOut.isEmpty && _validItemsIn.isEmpty) ||
                      _customerName.trim().isEmpty ||
                      _replacementReason.trim().isEmpty
                  ? null
                  : _submitReplacement,
              child: Text(
                _isSubmitting
                    ? 'Processing Replacement...'
                    : 'Process Replacement',
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ======== Import from Return helpers ========
  void _openImportReturns() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Import from Return'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 280, maxWidth: 520),
            child: SizedBox(
              width: MediaQuery.of(context).size.width * 0.9,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'Search by return no. or customer...',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) {
                      setState(() => _returnSearch = v);
                      _searchReturns();
                    },
                  ),
                  const SizedBox(height: 10),
                  if (_isReturnSearching)
                    const Center(child: CircularProgressIndicator())
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 320),
                      child: _returnResults.isEmpty && _returnSearch.isNotEmpty
                          ? const Padding(
                              padding: EdgeInsets.all(12.0),
                              child: Text('No returns found.'),
                            )
                          : ListView.separated(
                              shrinkWrap: true,
                              itemBuilder: (ctx, i) {
                                final r = _returnResults[i];
                                final s = r['sales'];
                                Map<String, dynamic>? sale;
                                if (s is Map<String, dynamic>) sale = s;
                                if (s is List &&
                                    s.isNotEmpty &&
                                    s.first is Map<String, dynamic>) {
                                  sale = Map<String, dynamic>.from(
                                    s.first as Map,
                                  );
                                }
                                return ListTile(
                                  onTap: () async {
                                    Navigator.of(context).pop();
                                    final id = r['id'] as int;
                                    await _prefillFromReturn(id);
                                  },
                                  title: Text(
                                    'Return #${r['return_number'] ?? r['id']}',
                                  ),
                                  subtitle: Text(
                                    '${r['customer_name'] ?? 'Walk-in'}${sale != null && sale['id'] != null ? ' · Sale S-${sale['id']}' : ''}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                  trailing: Text(
                                    (r['created_at'] ?? '').toString(),
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                );
                              },
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemCount: _returnResults.length,
                            ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _searchReturns() async {
    final q = _returnSearch.trim();
    if (q.isEmpty) {
      setState(() => _returnResults = []);
      return;
    }
    setState(() => _isReturnSearching = true);
    try {
      final results = await SupabaseService.searchReturns(q);
      setState(() => _returnResults = results);
    } catch (_) {
      setState(() => _returnResults = []);
    } finally {
      if (mounted) setState(() => _isReturnSearching = false);
    }
  }

  void _checkRouteArgs() async {
    final route = ModalRoute.of(context);
    final args = route?.settings.arguments;
    if (args is Map && args['return_id'] != null) {
      final id = args['return_id'];
      if (id is int) {
        await _prefillFromReturn(id);
      } else if (id is String) {
        final parsed = int.tryParse(id);
        if (parsed != null) await _prefillFromReturn(parsed);
      }
    } else if (args is Map && args['sale_id'] != null) {
      final id = args['sale_id'];
      if (id is int) {
        await _prefillFromSale(id);
      } else if (id is String) {
        final parsed = int.tryParse(id);
        if (parsed != null) await _prefillFromSale(parsed);
      }
    }
  }

  Future<void> _prefillFromReturn(int returnId) async {
    setState(() {
      _prefilledReturnId = returnId;
      _isPrefilling = true;
    });
    try {
      final ret = await SupabaseService.getReturnById(returnId);
      if (ret == null) return;
      _prefilledReturn = ret;

      // Extract joined sale
      Map<String, dynamic>? sale;
      final s = ret['sales'];
      if (s is Map<String, dynamic>) {
        sale = s;
      } else if (s is List && s.isNotEmpty && s.first is Map<String, dynamic>) {
        sale = Map<String, dynamic>.from(s.first as Map);
      }

      if (sale != null) {
        final saleItems = (sale['sales_items'] as List?) ?? const [];
        _selectedSale = {
          'id': sale['id'],
          'customer_name': sale['customer_name'],
          'created_at': sale['created_at'],
          'sales_items': saleItems,
        };
      }

      // Prefill Items Being Returned from return_items
      final List rawReturnItems = (ret['return_items'] as List?) ?? const [];
      final List saleItems =
          (_selectedSale?['sales_items'] as List?) ?? const [];

      _itemsOut = rawReturnItems.map<Map<String, dynamic>>((it) {
        final prod = (it['products'] as Map<String, dynamic>?) ?? const {};
        final productId = it['product_id'] ?? prod['id'];
        // default quantity and look up original sold quantity
        int originalQty =
            (it['quantity_returned'] as num?)?.toInt() ??
            (it['quantity'] as num?)?.toInt() ??
            0;
        for (final si in saleItems) {
          if ((si['product_id'] == productId) ||
              (si is Map && (si['products']?['id'] == productId))) {
            originalQty = (si['quantity'] as num?)?.toInt() ?? originalQty;
            break;
          }
        }
        final price =
            (it['original_price_per_unit'] as num?)?.toDouble() ??
            (it['price_per_unit'] as num?)?.toDouble() ??
            0.0;
        return {
          'product_id': productId,
          'product_name': it['product_name'] ?? prod['name'] ?? 'Item',
          'original_quantity': originalQty,
          'quantity_returned':
              (it['quantity_returned'] as num?)?.toInt() ??
              (it['quantity'] as num?)?.toInt() ??
              0,
          'price_per_unit': price,
          'item_condition': it['item_condition'] ?? it['condition'] ?? 'good',
        };
      }).toList();

      _customerName =
          (ret['customer_name'] as String?) ??
          (_selectedSale?['customer_name'] as String?) ??
          '';
      _customerNameController.text = _customerName;
      final reason = (ret['replacement_reason'] ?? ret['return_reason'] ?? '')
          .toString();
      if (reason.isNotEmpty) _replacementReason = reason;

      // clear searches
      _saleSearch = '';
      _saleResults = [];
      _productSearch = '';
      _productResults = [];

      setState(() {});
    } finally {
      if (mounted) setState(() => _isPrefilling = false);
    }
  }
}
