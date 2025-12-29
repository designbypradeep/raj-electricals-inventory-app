import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:raj_electricals_inventory_app/data/app_database.dart';
import 'package:raj_electricals_inventory_app/services/image_storage_service.dart';
import 'package:raj_electricals_inventory_app/services/supabase_service.dart';
import 'package:raj_electricals_inventory_app/services/connectivity_service.dart';
import 'package:drift/drift.dart' as drift;
import '../widgets/page_header.dart';
import './shop_page.dart';

// Simple decimal input formatter: allows digits with a single decimal point
// and up to a fixed number of decimal places (default: 2)
class DecimalTextInputFormatter extends TextInputFormatter {
  final int decimalRange;
  DecimalTextInputFormatter([this.decimalRange = 2]);

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    if (text.isEmpty) return newValue;

    // Allow only digits and an optional single dot
    if (!RegExp(r'^\d*\.?\d*$').hasMatch(text)) {
      return oldValue;
    }

    // Enforce single dot
    if ('.'.allMatches(text).length > 1) return oldValue;
    // Enforce decimal places
    if (text.contains('.')) {
      final parts = text.split('.');
      if (parts.length > 2) return oldValue;
      if (parts.length == 2 && parts[1].length > decimalRange) {
        return oldValue;
      }
    }
    return newValue;
  }
}

class AddProductPage extends StatefulWidget {
  final AppDatabase db;
  const AddProductPage({super.key, required this.db});

  @override
  State<AddProductPage> createState() => _AddProductPageState();
}

class _AddProductPageState extends State<AddProductPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _brandController = TextEditingController();
  final _sizeSpecController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _sellingPriceController = TextEditingController();
  final _unitTypeSingleController = TextEditingController(text: 'Piece');
  final _unitTypeWholesaleController = TextEditingController();
  final _itemsPerUnitController = TextEditingController(text: '1');
  final _newCategoryController = TextEditingController();

  bool _isLoading = false;
  String? _selectedCategory;

  List<String> _categories = [];
  bool _isLoadingCategories = false;

  bool _isSupabaseEnabled = false;

  final List<String> _selectedImages =
      []; // Can hold both URLs and local file paths
  final ImagePicker _picker = ImagePicker();
  bool _isDragging = false;
  final TextEditingController _urlController = TextEditingController();

  // Autocomplete state
  final FocusNode _nameFocusNode = FocusNode();
  final FocusNode _brandFocusNode = FocusNode();
  final FocusNode _sizeFocusNode = FocusNode();
  List<String> _nameSuggestions = [];
  List<String> _brandSuggestions = [];
  List<String> _sizeSuggestions = [];
  Timer? _nameDebounce;
  Timer? _brandDebounce;
  Timer? _sizeDebounce;
  // Category keyboard support
  final FocusNode _categoryFocusNode = FocusNode(debugLabel: 'category');
  String? _lastCategoryKey;
  int _categoryCycleIndex = 0;
  DateTime _lastCategoryKeyTime = DateTime.fromMillisecondsSinceEpoch(0);

  // Themed fill color for inputs for better contrast in dark/light modes
  Color _fieldFillColor() {
    final theme = Theme.of(context);
    final configured = theme.inputDecorationTheme.fillColor;
    if (configured != null) return configured;
    if (theme.brightness == Brightness.dark) {
      return theme.colorScheme.surfaceContainerHighest.withAlpha(40);
    }
    return theme.cardColor.withValues(alpha: 0.04);
  }

  @override
  void initState() {
    super.initState();
    _nameController.addListener(_onNameChanged);
    _brandController.addListener(_onBrandChanged);
    _sizeSpecController.addListener(_onSizeChanged);
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    await _checkSupabaseConnection();
    await _loadCategories();
  }

  @override
  void dispose() {
    _nameDebounce?.cancel();
    _brandDebounce?.cancel();
    _sizeDebounce?.cancel();
    _nameController.removeListener(_onNameChanged);
    _brandController.removeListener(_onBrandChanged);
    _sizeSpecController.removeListener(_onSizeChanged);
    _nameFocusNode.dispose();
    _brandFocusNode.dispose();
    _sizeFocusNode.dispose();
    _nameController.dispose();
    _brandController.dispose();
    _sizeSpecController.dispose();
    _descriptionController.dispose();
    _sellingPriceController.dispose();
    _unitTypeSingleController.dispose();
    _unitTypeWholesaleController.dispose();
    _itemsPerUnitController.dispose();
    _newCategoryController.dispose();
    _categoryFocusNode.dispose();
    super.dispose();
  }

  void _onNameChanged() {
    _nameDebounce?.cancel();
    final q = _nameController.text;
    _nameDebounce = Timer(const Duration(milliseconds: 250), () {
      _loadNameSuggestions(q);
    });
  }

  void _onBrandChanged() {
    _brandDebounce?.cancel();
    final q = _brandController.text;
    _brandDebounce = Timer(const Duration(milliseconds: 250), () {
      _loadBrandSuggestions(q);
    });
  }

  void _onSizeChanged() {
    _sizeDebounce?.cancel();
    final q = _sizeSpecController.text;
    _sizeDebounce = Timer(const Duration(milliseconds: 250), () {
      _loadSizeSuggestions(q);
    });
  }

  Future<void> _loadNameSuggestions(String q) async {
    if (!_isSupabaseEnabled || q.trim().isEmpty) {
      setState(() => _nameSuggestions = []);
      return;
    }
    try {
      final results = await SupabaseService.getDistinctProductNames(q);
      if (mounted) setState(() => _nameSuggestions = results);
    } catch (_) {}
  }

  Future<void> _loadBrandSuggestions(String q) async {
    if (!_isSupabaseEnabled || q.trim().isEmpty) {
      setState(() => _brandSuggestions = []);
      return;
    }
    try {
      final results = await SupabaseService.getDistinctProductBrands(q);
      if (mounted) setState(() => _brandSuggestions = results);
    } catch (_) {}
  }

  Future<void> _loadSizeSuggestions(String q) async {
    if (!_isSupabaseEnabled || q.trim().isEmpty) {
      setState(() => _sizeSuggestions = []);
      return;
    }
    try {
      final results = await SupabaseService.getDistinctProductSizeSpecs(q);
      if (mounted) setState(() => _sizeSuggestions = results);
    } catch (_) {}
  }

  Widget _buildNameAutocompleteField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Product Name',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).textTheme.bodyLarge?.color,
          ),
        ),
        const SizedBox(height: 8),
        RawAutocomplete<String>(
          textEditingController: _nameController,
          focusNode: _nameFocusNode,
          optionsBuilder: (TextEditingValue tev) {
            final q = tev.text.trim();
            if (q.isEmpty) return const Iterable<String>.empty();
            final lowered = q.toLowerCase();
            return _nameSuggestions
                .where((s) => s.toLowerCase().contains(lowered))
                .take(8);
          },
          onSelected: (String selection) {
            _nameController.text = selection;
            _nameController.selection = TextSelection.collapsed(
              offset: selection.length,
            );
          },
          fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
            return Focus(
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.tab) {
                  if (_nameSuggestions.isNotEmpty) {
                    final first = _nameSuggestions.first;
                    if (controller.text != first) {
                      controller.text = first;
                      controller.selection = TextSelection.collapsed(
                        offset: first.length,
                      );
                      return KeyEventResult.handled; // complete on first Tab
                    }
                  }
                }
                return KeyEventResult.ignored;
              },
              child: TextFormField(
                controller: controller,
                focusNode: focusNode,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: null,
                  hintText: 'e.g., REO Ceiling Fan',
                  hintStyle: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  filled: true,
                  fillColor: _fieldFillColor(),
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
                  errorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: Theme.of(context).colorScheme.error,
                      width: 2,
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 16,
                  ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Product name is required';
                  }
                  return null;
                },
              ),
            );
          },
          optionsViewBuilder: (context, onSelected, options) {
            final opts = options.toList();
            if (opts.isEmpty) return const SizedBox.shrink();
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(8),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxHeight: 220,
                    minWidth: 280,
                  ),
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: opts.length,
                    itemBuilder: (context, index) {
                      final opt = opts[index];
                      return ListTile(
                        dense: true,
                        title: Text(opt),
                        onTap: () => onSelected(opt),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildBrandAutocompleteField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Brand',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).textTheme.bodyLarge?.color,
          ),
        ),
        const SizedBox(height: 8),
        RawAutocomplete<String>(
          textEditingController: _brandController,
          focusNode: _brandFocusNode,
          optionsBuilder: (TextEditingValue tev) {
            final q = tev.text.trim();
            if (q.isEmpty) return const Iterable<String>.empty();
            final lowered = q.toLowerCase();
            return _brandSuggestions
                .where((s) => s.toLowerCase().contains(lowered))
                .take(8);
          },
          onSelected: (String selection) {
            _brandController.text = selection;
            _brandController.selection = TextSelection.collapsed(
              offset: selection.length,
            );
          },
          fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
            return Focus(
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.tab) {
                  if (_brandSuggestions.isNotEmpty) {
                    final first = _brandSuggestions.first;
                    if (controller.text != first) {
                      controller.text = first;
                      controller.selection = TextSelection.collapsed(
                        offset: first.length,
                      );
                      return KeyEventResult.handled;
                    }
                  }
                }
                return KeyEventResult.ignored;
              },
              child: TextFormField(
                controller: controller,
                focusNode: focusNode,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  hintText: 'e.g., Havells',
                  hintStyle: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  filled: true,
                  fillColor: _fieldFillColor(),
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
                    vertical: 16,
                  ),
                ),
              ),
            );
          },
          optionsViewBuilder: (context, onSelected, options) {
            final opts = options.toList();
            if (opts.isEmpty) return const SizedBox.shrink();
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(8),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxHeight: 220,
                    minWidth: 280,
                  ),
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: opts.length,
                    itemBuilder: (context, index) {
                      final opt = opts[index];
                      return ListTile(
                        dense: true,
                        title: Text(opt),
                        onTap: () => onSelected(opt),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildSizeAutocompleteField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Size / Spec',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).textTheme.bodyLarge?.color,
          ),
        ),
        const SizedBox(height: 8),
        RawAutocomplete<String>(
          textEditingController: _sizeSpecController,
          focusNode: _sizeFocusNode,
          optionsBuilder: (TextEditingValue tev) {
            final q = tev.text.trim();
            if (q.isEmpty) return const Iterable<String>.empty();
            final lowered = q.toLowerCase();
            return _sizeSuggestions
                .where((s) => s.toLowerCase().contains(lowered))
                .take(8);
          },
          onSelected: (String selection) {
            _sizeSpecController.text = selection;
            _sizeSpecController.selection = TextSelection.collapsed(
              offset: selection.length,
            );
          },
          fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
            return Focus(
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.tab) {
                  if (_sizeSuggestions.isNotEmpty) {
                    final first = _sizeSuggestions.first;
                    if (controller.text != first) {
                      controller.text = first;
                      controller.selection = TextSelection.collapsed(
                        offset: first.length,
                      );
                      return KeyEventResult.handled;
                    }
                  }
                }
                return KeyEventResult.ignored;
              },
              child: TextFormField(
                controller: controller,
                focusNode: focusNode,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  hintText: 'e.g., 1200MM, 2.5 sq mm',
                  hintStyle: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  filled: true,
                  fillColor: _fieldFillColor(),
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
                    vertical: 16,
                  ),
                ),
              ),
            );
          },
          optionsViewBuilder: (context, onSelected, options) {
            final opts = options.toList();
            if (opts.isEmpty) return const SizedBox.shrink();
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(8),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxHeight: 220,
                    minWidth: 280,
                  ),
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: opts.length,
                    itemBuilder: (context, index) {
                      final opt = opts[index];
                      return ListTile(
                        dense: true,
                        title: Text(opt),
                        onTap: () => onSelected(opt),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  // Category dropdown with keyboard type-ahead (press a letter to jump/cycle)
  Widget _buildCategoryDropdown() {
    return Focus(
      focusNode: _categoryFocusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        // Determine the typed character; prefer character when available
        String label;
        try {
          final dynamic e = event;
          final String? ch = (e.character is String)
              ? e.character as String
              : null;
          label = (ch?.isNotEmpty == true ? ch! : event.logicalKey.keyLabel)
              .toLowerCase();
        } catch (_) {
          label = event.logicalKey.keyLabel.toLowerCase();
        }

        // Only react to a single a-z or 0-9
        if (label.isEmpty ||
            label.length != 1 ||
            !RegExp(r'[a-z0-9]').hasMatch(label)) {
          return KeyEventResult.ignored;
        }

        final now = DateTime.now();
        // If pressing same key within 1s, cycle to next match; else restart
        if (_lastCategoryKey == label &&
            now.difference(_lastCategoryKeyTime).inMilliseconds < 1000) {
          _categoryCycleIndex += 1;
        } else {
          _lastCategoryKey = label;
          _categoryCycleIndex = 0;
        }
        _lastCategoryKeyTime = now;

        final matches = _categories
            .where((c) => c.toLowerCase().startsWith(label))
            .toList();
        if (matches.isEmpty) return KeyEventResult.ignored;

        final next = matches[_categoryCycleIndex % matches.length];
        if (next != _selectedCategory) {
          setState(() => _selectedCategory = next);
        }
        return KeyEventResult.handled;
      },
      child: DropdownButtonFormField<String>(
        initialValue: _selectedCategory,
        isExpanded: true,
        hint: const Text('Select a category', overflow: TextOverflow.ellipsis),
        onChanged: (value) => setState(() => _selectedCategory = value),
        decoration: InputDecoration(
          filled: true,
          fillColor: _fieldFillColor(),
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
            vertical: 16,
          ),
        ),
        items: _categories
            .map(
              (category) => DropdownMenuItem<String>(
                value: category,
                child: Text(category, overflow: TextOverflow.ellipsis),
              ),
            )
            .toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).colorScheme.surface,
              Theme.of(context).brightness == Brightness.dark
                  ? Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest.withAlpha(50)
                  : Theme.of(context).colorScheme.primary.withAlpha(25),
              Theme.of(context).colorScheme.surface,
            ],
            stops: const [0.0, 0.6, 1.0],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  // Page Header
                  _buildPageHeader(),

                  const SizedBox(height: 24),

                  // Main Content
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1100),
                      child: Form(
                        key: _formKey,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            if (constraints.maxWidth > 1024) {
                              return _buildDesktopLayout();
                            } else {
                              return _buildMobileLayout();
                            }
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left Column - Images and Unit Info
        Expanded(
          flex: 1,
          child: Column(
            children: [
              _buildImageUploadSection(),
              const SizedBox(height: 24),
              _buildUnitInformationSection(),
            ],
          ),
        ),

        const SizedBox(width: 32),

        // Right Column - Main Form
        Expanded(
          flex: 2,
          child: Column(
            children: [
              _buildNameAutocompleteField(),
              const SizedBox(height: 20),
              _buildBrandAutocompleteField(),
              const SizedBox(height: 20),
              LayoutBuilder(
                builder: (context, c) {
                  final isNarrow = c.maxWidth < 520;
                  final categoryField = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Category',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(
                                  context,
                                ).textTheme.bodyLarge?.color,
                              ),
                            ),
                          ),
                          if (_isLoadingCategories) ...[
                            const SizedBox(width: 8),
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ],
                          TextButton(
                            onPressed: _showAddCategoryDialog,
                            child: const Text(
                              '+ Add New',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _buildCategoryDropdown(),
                    ],
                  );
                  final sizeField = _buildSizeAutocompleteField();
                  if (isNarrow) {
                    return Column(
                      children: [
                        categoryField,
                        const SizedBox(height: 16),
                        sizeField,
                      ],
                    );
                  } else {
                    return Row(
                      children: [
                        Expanded(child: categoryField),
                        const SizedBox(width: 16),
                        Expanded(child: sizeField),
                      ],
                    );
                  }
                },
              ),
              const SizedBox(height: 20),

              // Description (Full Width)
              _buildTextField(
                controller: _descriptionController,
                label: 'Description',
                hint: 'e.g., 360RPM, 24 Month Warranty',
                maxLines: 3,
              ),
              const SizedBox(height: 20),

              // Selling Price
              _buildTextField(
                controller: _sellingPriceController,
                label: 'Selling Price (₹)',
                hint: '0.00',
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [DecimalTextInputFormatter(2)],
                textInputAction: TextInputAction.done,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Selling price is required';
                  }
                  final price = double.tryParse(value);
                  if (price == null || price < 0) {
                    return 'Enter valid price';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 32),
              _buildSubmitButton(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMobileLayout() {
    return Column(
      children: [
        _buildImageUploadSection(),
        const SizedBox(height: 24),
        _buildUnitInformationSection(),
        const SizedBox(height: 24),
        _buildNameAutocompleteField(),
        const SizedBox(height: 20),
        _buildBrandAutocompleteField(),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, c) {
            final isNarrow = c.maxWidth < 520;
            final categoryField = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Category',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).textTheme.bodyLarge?.color,
                        ),
                      ),
                    ),
                    if (_isLoadingCategories) ...[
                      const SizedBox(width: 8),
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ],
                    TextButton(
                      onPressed: _showAddCategoryDialog,
                      child: const Text(
                        '+ Add New',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _buildCategoryDropdown(),
              ],
            );
            final sizeField = _buildSizeAutocompleteField();
            if (isNarrow) {
              return Column(
                children: [
                  categoryField,
                  const SizedBox(height: 16),
                  sizeField,
                ],
              );
            } else {
              return Row(
                children: [
                  Expanded(child: categoryField),
                  const SizedBox(width: 16),
                  Expanded(child: sizeField),
                ],
              );
            }
          },
        ),
        const SizedBox(height: 20),

        // Description (Full Width)
        _buildTextField(
          controller: _descriptionController,
          label: 'Description',
          hint: 'e.g., 360RPM, 24 Month Warranty',
          maxLines: 3,
        ),
        const SizedBox(height: 20),

        // Selling Price
        _buildTextField(
          controller: _sellingPriceController,
          label: 'Selling Price (₹)',
          hint: '0.00',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [DecimalTextInputFormatter(2)],
          textInputAction: TextInputAction.done,
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Selling price is required';
            }
            final price = double.tryParse(value);
            if (price == null || price < 0) {
              return 'Enter valid price';
            }
            return null;
          },
        ),
        const SizedBox(height: 32),
        _buildSubmitButton(),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    int maxLines = 1,
    List<TextInputFormatter>? inputFormatters,
    TextInputAction? textInputAction,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).textTheme.bodyLarge?.color,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          validator: validator,
          maxLines: maxLines,
          inputFormatters: inputFormatters,
          textInputAction: textInputAction,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            filled: true,
            fillColor: _fieldFillColor(),
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
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: Theme.of(context).colorScheme.error,
                width: 2,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 16,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _saveProduct,
        style: ElevatedButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          elevation: 0,
        ),
        child: _isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Text(
                'Save Product',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
      ),
    );
  }

  // Supabase connection and initial data
  Future<void> _checkSupabaseConnection() async {
    try {
      if (kDebugMode) {
        print('Checking Supabase connection...');
        print('User authenticated: ${SupabaseService.isAuthenticated}');
      }

      if (SupabaseService.isAuthenticated) {
        final businessProfile =
            await SupabaseService.getCurrentBusinessProfile();
        if (kDebugMode) {
          print('Business profile: $businessProfile');
        }
        if (businessProfile != null) {
          if (mounted) {
            setState(() {
              _isSupabaseEnabled = true;
            });
          }
          if (kDebugMode) {
            print('Supabase enabled: true');
          }
          return;
        }
      }

      if (kDebugMode) {
        print(
          'No authenticated user or business profile, falling back to local',
        );
      }
      if (mounted) {
        setState(() {
          _isSupabaseEnabled = false;
        });
      }
    } catch (e) {
      if (kDebugMode) {
        print('Supabase connection failed, using local database: $e');
      }
      if (mounted) {
        setState(() {
          _isSupabaseEnabled = false;
        });
      }
    }
  }

  Future<void> _loadCategories() async {
    setState(() {
      _isLoadingCategories = true;
    });

    try {
      List<String> categories = [];

      if (_isSupabaseEnabled) {
        final supabaseCategories = await SupabaseService.getCategories();
        categories = supabaseCategories.map((c) => c.name).toList();
        if (kDebugMode) {
          print('Loaded categories from database: $categories');
        }

        if (categories.isEmpty) {
          categories = await SupabaseService.getProductCategories();
          if (kDebugMode) {
            print('Loaded fallback product categories: $categories');
          }
        }
      } else {
        categories = [
          'Electronics',
          'Electrical',
          'Switches',
          'Wires',
          'Lights',
          'Fans',
        ];
        if (kDebugMode) {
          print('Using fallback categories: $categories');
        }
      }

      setState(() {
        _categories = categories;
        _isLoadingCategories = false;
      });
    } catch (e) {
      if (kDebugMode) {
        print('Error loading categories: $e');
      }
      setState(() {
        _isLoadingCategories = false;
      });
    }
  }

  Future<void> _addNewCategory(String categoryName) async {
    try {
      bool success = false;

      if (_isSupabaseEnabled) {
        if (!SupabaseService.isAuthenticated) {
          throw Exception('Please log in to add categories');
        }

        final created = await SupabaseService.createCategory(
          name: categoryName,
        );
        success = created != null;
        await _loadCategories();
        if (success) {
          setState(() {
            _selectedCategory = categoryName;
          });
        }
      } else {
        if (!_categories.contains(categoryName)) {
          setState(() {
            _categories.add(categoryName);
            _selectedCategory = categoryName;
          });
        }
        success = true;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success
                  ? 'Category "$categoryName" added successfully!'
                  : 'Failed to add category',
            ),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error adding category: $e');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error adding category: ${e.toString().replaceAll('Exception: ', '')}',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Image helpers and UI
  Widget buildImagePreview(String reference) {
    if (reference.startsWith('http')) {
      return Image.network(
        reference,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            const Icon(Icons.broken_image, size: 40),
      );
    } else {
      return Image.file(
        File(reference),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            const Icon(Icons.broken_image, size: 40),
      );
    }
  }

  void _addDroppedImages(List<dynamic> images) {
    int addedCount = 0;
    int duplicateCount = 0;
    int limitSkipped = 0;

    setState(() {
      final remainingSlots = 10 - _selectedImages.length;
      if (remainingSlots <= 0) {
        limitSkipped = images.length;
        return;
      }

      int processed = 0;
      for (final image in images) {
        String imagePath = '';
        if (image is File) {
          imagePath = image.path;
        } else if (image is String) {
          imagePath = image;
        } else {
          continue;
        }

        if (_selectedImages.contains(imagePath)) {
          duplicateCount++;
          continue;
        }
        if (addedCount >= remainingSlots) {
          // Count remaining unprocessed as limit skipped
          limitSkipped = images.length - processed;
          break;
        }
        _selectedImages.add(imagePath);
        addedCount++;
        processed++;
      }
    });

    if (mounted && (addedCount > 0 || duplicateCount > 0 || limitSkipped > 0)) {
      final parts = <String>[];
      if (addedCount > 0) parts.add('Added $addedCount image(s)');
      if (duplicateCount > 0) parts.add('$duplicateCount duplicate(s) skipped');
      if (limitSkipped > 0) parts.add('$limitSkipped skipped (max 10 images)');
      final message = parts.join(', ');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message.isEmpty ? 'No images added' : message),
          backgroundColor: addedCount > 0 ? Colors.green : Colors.orange,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _clearAllImages() {
    setState(() {
      _selectedImages.clear();
    });
  }

  void _removeImage(int index) {
    setState(() {
      _selectedImages.removeAt(index);
    });
  }

  void _makeCover(int index) {
    if (index <= 0 || index >= _selectedImages.length) return;
    setState(() {
      final img = _selectedImages.removeAt(index);
      _selectedImages.insert(0, img);
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Set as cover image'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  Future<void> _pickImages() async {
    try {
      final List<XFile> images = await _picker.pickMultiImage(
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (images.isNotEmpty) {
        final List<File> newImages = images
            .map((xfile) => File(xfile.path))
            .toList();
        _addDroppedImages(newImages);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error picking images: $e')));
      }
    }
  }

  void _addImageFromUrl() {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter an image URL'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    if (!url.startsWith('http')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please enter a valid URL starting with http:// or https://',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    _addDroppedImages([url]);
    _urlController.clear();
  }

  Widget _buildImageUploadSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withAlpha(40),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.image_outlined,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Product Images',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).textTheme.bodyLarge?.color,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Supported: JPG, PNG, GIF, WebP • Max 10 images',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (_selectedImages.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_selectedImages.length}/10',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          DropTarget(
            onDragEntered: (_) => setState(() => _isDragging = true),
            onDragExited: (_) => setState(() => _isDragging = false),
            onDragDone: (details) {
              final files = details.files.map((e) => File(e.path)).toList();
              _addDroppedImages(files);
              setState(() => _isDragging = false);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              height: 160,
              decoration: BoxDecoration(
                color: _isDragging
                    ? Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.08)
                    : Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest.withAlpha(30),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _isDragging
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.outline.withAlpha(50),
                ),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.cloud_upload,
                      size: 32,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Drag & drop images here or use the button below',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 8),
                    Tooltip(
                      message: 'Select images from your device',
                      child: ElevatedButton.icon(
                        onPressed: _pickImages,
                        icon: const Icon(Icons.photo_library),
                        label: const Text('Select Images'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _urlController,
                  decoration: InputDecoration(
                    hintText: 'Or add image from URL',
                    hintStyle: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    filled: true,
                    fillColor: _fieldFillColor(),
                    prefixIcon: const Icon(Icons.link),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: Theme.of(
                          context,
                        ).colorScheme.outline.withAlpha(50),
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
                      vertical: 16,
                    ),
                  ),
                  onSubmitted: (_) => _addImageFromUrl(),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _addImageFromUrl,
                child: const Text('Add URL'),
              ),
              const SizedBox(width: 8),
              if (_selectedImages.isNotEmpty)
                TextButton(
                  onPressed: _clearAllImages,
                  child: const Text('Clear All'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_selectedImages.isNotEmpty)
            LayoutBuilder(
              builder: (context, c) {
                final cross = c.maxWidth >= 1100
                    ? 5
                    : c.maxWidth >= 900
                    ? 4
                    : c.maxWidth >= 600
                    ? 3
                    : 2;
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cross,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 1,
                  ),
                  itemCount: _selectedImages.length,
                  itemBuilder: (context, index) {
                    final ref = _selectedImages[index];
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: buildImagePreview(ref),
                        ),
                        Positioned(
                          top: 6,
                          right: 6,
                          child: InkWell(
                            onTap: () => _removeImage(index),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.55),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.35),
                                ),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              padding: const EdgeInsets.all(4),
                              child: const Icon(
                                Icons.close,
                                size: 16,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        if (index == 0)
                          Positioned(
                            left: 6,
                            top: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.55),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.35),
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                'Cover',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        if (index > 0)
                          Positioned(
                            left: 6,
                            bottom: 6,
                            child: InkWell(
                              onTap: () => _makeCover(index),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.55),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.35),
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Text(
                                  'Make cover',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildUnitInformationSection() {
    return Container(
      padding: const EdgeInsets.all(20),
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
          _buildTextField(
            controller: _unitTypeSingleController,
            label: 'Single Unit',
            hint: 'Piece',
          ),
          const SizedBox(height: 16),
          _buildTextField(
            controller: _unitTypeWholesaleController,
            label: 'Wholesale Unit',
            hint: 'Box, Payti, Coil',
          ),
          const SizedBox(height: 16),
          _buildTextField(
            controller: _itemsPerUnitController,
            label: 'Items per Unit',
            hint: '1',
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textInputAction: TextInputAction.next,
          ),
        ],
      ),
    );
  }

  Widget _buildPageHeader() {
    return PageHeader(
      title: 'Add Product',
      description: 'Create a new product entry with images and details',
      icon: '📝',
      showBackButton: true,
      onBackPressed: () => Navigator.pop(context),
      breadcrumbs: [
        PageHeaderBreadcrumb(label: 'Dashboard', icon: '🏠'),
        PageHeaderBreadcrumb(label: 'Add Product', icon: '📝', current: true),
      ],
      stats: [
        PageHeaderStat(
          label: 'Product Management',
          value: 'New Entry',
          description: 'Create product with images and details',
        ),
        PageHeaderStat(
          label: 'Status',
          value: 'Ready',
          description: 'All systems operational',
        ),
      ],
      actions: [
        PageHeaderAction(
          label: 'Open Catalog',
          shortLabel: 'Catalog',
          icon: Icons.apps,
          color: Theme.of(context).colorScheme.tertiary,
          pill: true,
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => ShopPage(db: widget.db)),
          ),
        ),
      ],
    );
  }

  Future<void> _saveProduct() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCategory == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please select a category')));
      return;
    }

    if (_isSupabaseEnabled && !ConnectivityService().isOnline.value) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You are offline. Cannot save product to cloud.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Save images locally first
      List<String> savedImagePaths = [];
      if (_selectedImages.isNotEmpty) {
        final tempProductId = DateTime.now().millisecondsSinceEpoch;
        savedImagePaths = await ImageStorageService.saveProductImages(
          _selectedImages,
          tempProductId,
        );
      }

      bool success = false;

      if (_isSupabaseEnabled) {
        final product = await SupabaseService.createProduct(
          name: _nameController.text.trim(),
          brand: _brandController.text.trim().isEmpty
              ? null
              : _brandController.text.trim(),
          category: _selectedCategory!,
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          sizeSpec: _sizeSpecController.text.trim().isEmpty
              ? null
              : _sizeSpecController.text.trim(),
          sellingPrice:
              double.tryParse(_sellingPriceController.text.trim()) ?? 0.0,
          unitTypeSingle: _unitTypeSingleController.text.trim().isEmpty
              ? 'Piece'
              : _unitTypeSingleController.text.trim(),
          unitTypeWholesale: _unitTypeWholesaleController.text.trim().isEmpty
              ? null
              : _unitTypeWholesaleController.text.trim(),
          itemsPerWholesaleUnit:
              int.tryParse(_itemsPerUnitController.text.trim()) ?? 1,
          localImagePaths: savedImagePaths,
        );

        success = product != null;
      } else {
        await widget.db.insertProduct(
          ProductsCompanion.insert(
            name: _nameController.text.trim(),
            brand: _brandController.text.trim().isEmpty
                ? 'Unknown'
                : _brandController.text.trim(),
            model: drift.Value(
              _sizeSpecController.text.trim().isEmpty
                  ? null
                  : _sizeSpecController.text.trim(),
            ),
            sizeOrType: _sizeSpecController.text.trim().isEmpty
                ? 'N/A'
                : _sizeSpecController.text.trim(),
            category: _selectedCategory ?? 'General',
            quantity: 0,
            price: (double.tryParse(_sellingPriceController.text.trim()) ?? 0.0)
                .round(),
            imagePaths: drift.Value(
              savedImagePaths.isEmpty
                  ? null
                  : ImageStorageService.imagePathsToJson(savedImagePaths),
            ),
          ),
        );
        success = true;
      }

      if (mounted && success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isSupabaseEnabled
                  ? '✅ Product saved to cloud successfully!'
                  : '✅ Product saved locally successfully!',
            ),
            backgroundColor: Colors.green,
          ),
        );

        // Clear form
        _nameController.clear();
        _brandController.clear();
        _sizeSpecController.clear();
        _sellingPriceController.clear();
        _descriptionController.clear();
        _unitTypeSingleController.text = 'Piece';
        _unitTypeWholesaleController.clear();
        _itemsPerUnitController.text = '1';
        setState(() {
          _selectedImages.clear();
          _selectedCategory = null;
        });
      } else if (mounted) {
        throw Exception('Failed to save product');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showAddCategoryDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add New Category'),
        content: TextField(
          controller: _newCategoryController,
          decoration: const InputDecoration(
            labelText: 'Category Name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _newCategoryController.clear();
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final categoryName = _newCategoryController.text.trim();
              if (categoryName.isNotEmpty) {
                _addNewCategory(categoryName);
                Navigator.pop(context);
                _newCategoryController.clear();
              }
            },
            child: const Text('Save Category'),
          ),
        ],
      ),
    );
  }
}
