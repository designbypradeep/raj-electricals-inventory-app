import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/supabase_models.dart' as supa;
import '../services/supabase_service.dart';

class ProductSearchField extends StatefulWidget {
  final supa.Product? value;
  final ValueChanged<supa.Product?> onChanged;
  final String hintText;
  final bool enabled;
  final bool onlyInStock;

  const ProductSearchField({
    super.key,
    required this.value,
    required this.onChanged,
    this.hintText = '-- Choose a product --',
    this.enabled = true,
    this.onlyInStock = false,
  });

  @override
  State<ProductSearchField> createState() => _ProductSearchFieldState();
}

class _ProductSearchFieldState extends State<ProductSearchField> {
  Future<void> _openPicker() async {
    if (!widget.enabled) return;
    final selected = await showModalBottomSheet<supa.Product>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => _ProductPickerSheet(
        initial: widget.value,
        onlyInStock: widget.onlyInStock,
      ),
    );
    if (selected != null) {
      widget.onChanged(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final display = widget.value == null
        ? widget.hintText
        : '${widget.value!.brand ?? ''} ${widget.value!.name} ${widget.value!.sizeOrSpec ?? ''}'
              .trim();

    return InkWell(
      onTap: _openPicker,
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                display,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: widget.value == null
                      ? Theme.of(
                          context,
                        ).textTheme.bodyMedium?.color?.withValues(alpha: 0.6)
                      : Theme.of(context).textTheme.bodyMedium?.color,
                ),
              ),
            ),
            if (widget.value != null)
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                tooltip: 'Clear',
                onPressed: () => widget.onChanged(null),
              ),
            const Icon(Icons.search, size: 18),
          ],
        ),
      ),
    );
  }
}

class _ProductPickerSheet extends StatefulWidget {
  final supa.Product? initial;
  final bool onlyInStock;
  const _ProductPickerSheet({required this.initial, required this.onlyInStock});

  @override
  State<_ProductPickerSheet> createState() => _ProductPickerSheetState();
}

class _ProductPickerSheetState extends State<_ProductPickerSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _debounce;
  bool _loading = true;
  List<supa.Product> _results = const [];
  int _highlightIndex = 0;
  final FocusNode _focusNode = FocusNode();

  Widget _thumbPlaceholder() {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Icon(
        Icons.photo,
        size: 20,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }

  Widget _buildThumb(supa.Product p) {
    final url =
        p.productImageUrl ??
        (p.productImages?.isNotEmpty == true ? p.productImages!.first : null);
    if (url == null || url.isEmpty) return _thumbPlaceholder();
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Image.network(
        url,
        width: 48,
        height: 48,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _thumbPlaceholder(),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _runSearch('');
    _searchCtrl.addListener(_onChanged);
    // Ensure we can catch keyboard events
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  void _onChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      _runSearch(_searchCtrl.text);
    });
  }

  Future<void> _runSearch(String q) async {
    setState(() => _loading = true);
    final list = await SupabaseService.searchProductsQuick(
      q,
      limit: 30,
      onlyInStock: widget.onlyInStock,
    );
    if (!mounted) return;
    setState(() {
      _results = list;
      _loading = false;
      _highlightIndex = list.isNotEmpty ? 0 : 0;
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: RawKeyboardListener(
          focusNode: _focusNode,
          onKey: (event) {
            if (event is! RawKeyDownEvent) return;
            final key = event.logicalKey;
            if (key == LogicalKeyboardKey.arrowDown && _results.isNotEmpty) {
              setState(() {
                _highlightIndex = (_highlightIndex + 1).clamp(
                  0,
                  _results.length - 1,
                );
              });
            } else if (key == LogicalKeyboardKey.arrowUp &&
                _results.isNotEmpty) {
              setState(() {
                _highlightIndex = (_highlightIndex - 1).clamp(
                  0,
                  _results.length - 1,
                );
              });
            } else if (key == LogicalKeyboardKey.enter && _results.isNotEmpty) {
              Navigator.of(context).pop(_results[_highlightIndex]);
            } else if (key == LogicalKeyboardKey.escape) {
              Navigator.of(context).maybePop();
            }
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    const Icon(Icons.search, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _searchCtrl,
                        autofocus: true,
                        onSubmitted: (_) {
                          if (_results.isNotEmpty) {
                            Navigator.of(
                              context,
                            ).pop(_results[_highlightIndex]);
                          }
                        },
                        decoration: const InputDecoration(
                          hintText: 'Search by name, brand, category...',
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Divider(color: Theme.of(context).dividerColor, height: 1),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _results.isEmpty
                    ? Center(
                        child: Text(
                          'No products found',
                          style: TextStyle(
                            color: Theme.of(context).textTheme.bodyMedium?.color
                                ?.withValues(alpha: 0.7),
                          ),
                        ),
                      )
                    : ListView.separated(
                        itemCount: _results.length,
                        separatorBuilder: (_, __) => Divider(
                          color: Theme.of(context).dividerColor,
                          height: 1,
                        ),
                        itemBuilder: (context, i) {
                          final p = _results[i];
                          final selected = i == _highlightIndex;
                          return Container(
                            color: selected
                                ? Theme.of(
                                    context,
                                  ).colorScheme.primary.withValues(alpha: 0.08)
                                : null,
                            child: ListTile(
                              leading: _buildThumb(p),
                              minLeadingWidth: 54,
                              title: Text(
                                '${p.brand ?? ''} ${p.name} ${p.sizeOrSpec ?? ''}'
                                    .trim(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                [
                                  if ((p.category ?? '').isNotEmpty)
                                    p.category!,
                                  if (p.itemCode != null &&
                                      p.itemCode!.isNotEmpty)
                                    'Code: ${p.itemCode}',
                                  'Stock: ${p.currentStock}',
                                  if (p.sellingPrice != null)
                                    '₹${p.sellingPrice!.toStringAsFixed(2)}',
                                ].join(' • '),
                              ),
                              onTap: () => Navigator.of(context).pop(p),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
