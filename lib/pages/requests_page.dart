import 'package:flutter/material.dart';
import 'dart:io';
import '../widgets/page_header.dart';
import 'manage_requests_page.dart';
import '../services/supabase_service.dart';
import '../services/connectivity_service.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart' show rootBundle;

class RequestItem {
  final int productId;
  final String name;
  final int quantity;
  final String notes;
  final double expectedPrice;
  final String? imageUrl;

  RequestItem({
    required this.productId,
    required this.name,
    required this.quantity,
    required this.notes,
    required this.expectedPrice,
    this.imageUrl,
  });
}

class Product {
  final int id;
  final String name;
  final String brand;
  final String? imageUrl;

  Product({
    required this.id,
    required this.name,
    required this.brand,
    this.imageUrl,
  });
}

class RequestsPage extends StatefulWidget {
  const RequestsPage({super.key});

  @override
  State<RequestsPage> createState() => _RequestsPageState();
}

class _RequestsPageState extends State<RequestsPage> {
  final _formKey = GlobalKey<FormState>();
  final _dealerNameController = TextEditingController();
  final _dealerPhoneController = TextEditingController();
  final _notesController = TextEditingController();
  final _quantityController = TextEditingController(text: '1');
  final _expectedPriceController = TextEditingController(text: '0');

  final List<RequestItem> _requestItems = [];
  int? _selectedProductId;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _requestSaved = false;
  String _savedRequestId = '';

  // Loaded from Supabase
  List<Product> _products = [];

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    setState(() => _isLoading = true);
    try {
      final list = await SupabaseService.getProducts();
      final mapped = list
          .where((p) => p.id != null)
          .map(
            (p) => Product(
              id: p.id!,
              name: p.name,
              brand: p.brand ?? '',
              imageUrl:
                  p.productImageUrl ??
                  ((p.productImages != null && p.productImages!.isNotEmpty)
                      ? p.productImages!.first
                      : null),
            ),
          )
          .toList();
      setState(() {
        _products = mapped;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load products: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _dealerNameController.dispose();
    _dealerPhoneController.dispose();
    _notesController.dispose();
    _quantityController.dispose();
    _expectedPriceController.dispose();
    super.dispose();
  }

  void _handleAddItem() {
    if (_selectedProductId == null ||
        int.tryParse(_quantityController.text) == null ||
        int.parse(_quantityController.text) <= 0) {
      return;
    }

    final selectedProduct = _products.firstWhere(
      (p) => p.id == _selectedProductId,
    );
    final quantity = int.parse(_quantityController.text);
    final expectedPrice = double.tryParse(_expectedPriceController.text) ?? 0.0;

    // Check if product is already in the request list
    if (_requestItems.any((item) => item.productId == _selectedProductId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Product is already in the request list.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _requestItems.add(
        RequestItem(
          productId: selectedProduct.id,
          name: '${selectedProduct.name} (${selectedProduct.brand})',
          quantity: quantity,
          notes: _notesController.text.trim(),
          expectedPrice: expectedPrice,
          imageUrl: selectedProduct.imageUrl,
        ),
      );

      // Reset form
      _selectedProductId = null;
      _quantityController.text = '1';
      _notesController.clear();
      _expectedPriceController.text = '0';
    });
  }

  void _removeItem(int productId) {
    setState(() {
      _requestItems.removeWhere((item) => item.productId == productId);
    });
  }

  Future<void> _saveRequest() async {
    if (!_formKey.currentState!.validate() || _requestItems.isEmpty) {
      return;
    }

    if (!ConnectivityService().isOnline.value) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You are offline. Cannot save request.')),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final items = _requestItems
          .map(
            (it) => {
              'product_id': it.productId,
              'quantity': it.quantity,
              'expected_price': it.expectedPrice,
              if (it.notes.isNotEmpty) 'notes': it.notes,
            },
          )
          .toList();

      final reqId = await SupabaseService.createItemRequest(
        dealerName: _dealerNameController.text.trim().isEmpty
            ? null
            : _dealerNameController.text.trim(),
        dealerPhone: _dealerPhoneController.text.trim().isEmpty
            ? null
            : _dealerPhoneController.text.trim(),
        notes: null,
        items: items,
      );

      if (reqId == null) {
        throw Exception('Request failed to create');
      }

      setState(() {
        _requestSaved = true;
        _savedRequestId = '$reqId';
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save request: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      setState(() {
        _isSaving = false;
      });
    }
  }

  Future<void> _generatePdf() async {
    try {
      // Load custom fonts from assets (ensure assets/fonts/Poppins-*.ttf exist)
      final fontRegular = pw.Font.ttf(
        await rootBundle.load('assets/fonts/Poppins-Regular.ttf'),
      );
      final fontBold = pw.Font.ttf(
        await rootBundle.load('assets/fonts/Poppins-Bold.ttf'),
      );

      final doc = pw.Document(
        theme: pw.ThemeData.withFont(base: fontRegular, bold: fontBold),
      );

      final headers = [
        'S.No.',
        'Image',
        'Product Description',
        'Qty',
        'Expected Price (₹)',
        'Notes',
        'Price',
        'Check',
      ];

      // Styles for table
      final headerStyle = pw.TextStyle(
        fontWeight: pw.FontWeight.bold,
        fontSize: 11,
      );
      final cellStyle = const pw.TextStyle(fontSize: 10);
      final descStyle = const pw.TextStyle(fontSize: 11);
      final notesStyle = const pw.TextStyle(fontSize: 11);

      Future<pw.ImageProvider?> loadImage(String? pathOrUrl) async {
        if (pathOrUrl == null || pathOrUrl.isEmpty) return null;
        final isHttp =
            pathOrUrl.startsWith('http://') || pathOrUrl.startsWith('https://');
        if (isHttp) {
          try {
            Uri? uri = Uri.tryParse(pathOrUrl);
            uri ??= Uri.parse(Uri.encodeFull(pathOrUrl));
            final resp = await http
                .get(uri)
                .timeout(const Duration(seconds: 10));
            if (resp.statusCode == 200) {
              return pw.MemoryImage(resp.bodyBytes);
            }
          } catch (_) {}
        } else {
          try {
            final file = File(
              pathOrUrl.startsWith('file://')
                  ? pathOrUrl.replaceFirst('file://', '')
                  : pathOrUrl,
            );
            if (await file.exists()) {
              final bytes = await file.readAsBytes();
              return pw.MemoryImage(bytes);
            }
          } catch (_) {}
        }
        return null;
      }

      final rows = <pw.TableRow>[];
      for (var i = 0; i < _requestItems.length; i++) {
        final it = _requestItems[i];
        final img = await loadImage(it.imageUrl);
        rows.add(
          pw.TableRow(
            children: [
              pw.Padding(
                padding: const pw.EdgeInsets.all(4),
                child: pw.Text('${i + 1}', style: cellStyle),
              ),
              pw.Container(
                height: 48,
                width: 58,
                alignment: pw.Alignment.center,
                child: img != null
                    ? pw.ClipRRect(
                        horizontalRadius: 4,
                        verticalRadius: 4,
                        child: pw.Image(
                          img,
                          height: 44,
                          width: 54,
                          fit: pw.BoxFit.cover,
                        ),
                      )
                    : pw.Container(
                        height: 44,
                        width: 54,
                        decoration: pw.BoxDecoration(
                          color: PdfColors.grey300,
                          borderRadius: pw.BorderRadius.circular(4),
                        ),
                        alignment: pw.Alignment.center,
                        child: pw.Text(
                          'No\nImg',
                          style: cellStyle,
                          textAlign: pw.TextAlign.center,
                        ),
                      ),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(4),
                child: pw.Text(it.name, style: descStyle),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(4),
                child: pw.Text('${it.quantity}', style: cellStyle),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(4),
                child: pw.Text(
                  '₹${it.expectedPrice.toStringAsFixed(2)}',
                  style: cellStyle,
                ),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(4),
                child: pw.Text(it.notes, style: notesStyle),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(4),
                child: pw.Text('', style: cellStyle),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(4),
                child: pw.Text('', style: cellStyle),
              ),
            ],
          ),
        );
      }

      final totalExpectedAmount = _requestItems.fold<double>(
        0,
        (sum, it) => sum + (it.expectedPrice * it.quantity),
      );

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          build: (context) => [
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Item Request List',
                        style: pw.TextStyle(
                          fontSize: 20,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'For Dealer: ${_dealerNameController.text.trim()}',
                      ),
                    ],
                  ),
                ),
                pw.Text(
                  'Date: ${DateTime.now().toLocal().toString().split('.').first}',
                  style: const pw.TextStyle(fontSize: 12),
                ),
              ],
            ),
            pw.SizedBox(height: 8),
            pw.Table(
              border: pw.TableBorder.all(width: 0.5),
              defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
              columnWidths: const {
                0: pw.FixedColumnWidth(28),
                1: pw.FixedColumnWidth(60),
                2: pw.FlexColumnWidth(3),
                3: pw.FixedColumnWidth(36),
                4: pw.FixedColumnWidth(70),
                5: pw.FlexColumnWidth(2),
                6: pw.FixedColumnWidth(50),
                7: pw.FixedColumnWidth(40),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(
                    color: PdfColor.fromInt(0xFFEEEEEE),
                  ),
                  children: headers
                      .map(
                        (h) => pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text(h, style: headerStyle),
                        ),
                      )
                      .toList(),
                ),
                ...rows,
              ],
            ),
            pw.SizedBox(height: 12),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(
                'Total Expected Amount: ₹${totalExpectedAmount.toStringAsFixed(2)}',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
            ),
          ],
        ),
      );

      final fileName =
          'request_${_savedRequestId.isNotEmpty ? _savedRequestId : DateTime.now().millisecondsSinceEpoch}.pdf';
      await Printing.sharePdf(bytes: await doc.save(), filename: fileName);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to generate PDF: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  void _createNewRequest() {
    setState(() {
      _requestSaved = false;
      _savedRequestId = '';
      _requestItems.clear();
      _dealerNameController.clear();
      _dealerPhoneController.clear();
      _notesController.clear();
      _quantityController.text = '1';
      _expectedPriceController.text = '0';
      _selectedProductId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        top: false,
        bottom: true,
        child: SingleChildScrollView(
          child: Column(
            children: [
              PageHeader(
                title: 'Create Item Request',
                description:
                    'डीलर पर्ची • Build dealer request lists with products and specifications',
                icon: '📋',
                showBackButton: true,
                onBackPressed: () => Navigator.pop(context),
                wrapInSafeArea: true,
                breadcrumbs: [
                  PageHeaderBreadcrumb(label: 'Dashboard', icon: '🏠', href: '/'),
                  if (MediaQuery.of(context).size.width >= 450)
                    PageHeaderBreadcrumb(
                      label: 'Item Requests',
                      icon: '📋',
                      current: true,
                    ),
                ],
                stats: [
                  PageHeaderStat(
                    label: 'Products Available',
                    value: '${_products.length}',
                    description: 'Products ready to add to requests',
                  ),
                  PageHeaderStat(
                    label: 'Items in Request',
                    value: '${_requestItems.length}',
                    description: 'Items currently in the request list',
                  ),
                ],
                actions: [
                  PageHeaderAction(
                    label: 'Manage Requests',
                    shortLabel: 'Manage',
                    icon: Icons.settings,
                    color: Theme.of(context).colorScheme.tertiary,
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ManageRequestsPage(),
                        ),
                      );
                    },
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // Statistics Cards
                    _buildStatisticsCards(),
                    const SizedBox(height: 24),

                    if (_requestSaved) ...[
                      _buildSuccessState(),
                    ] else ...[
                      // Dealer Information Form
                      _buildDealerInformationForm(),
                      const SizedBox(height: 24),

                      // Request Items List
                      if (_requestItems.isNotEmpty) ...[
                        _buildRequestItemsList(),
                        const SizedBox(height: 24),
                      ],

                      // Summary and Save Section
                      _buildSaveSection(),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatisticsCards() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 680;
        if (isWide) {
          return Row(
            children: [
              Expanded(child: _buildAvailableProductsCard()),
              const SizedBox(width: 16),
              Expanded(child: _buildCurrentRequestItemsCard()),
            ],
          );
        }
        return Column(
          children: [
            _buildAvailableProductsCard(),
            const SizedBox(height: 16),
            _buildCurrentRequestItemsCard(),
          ],
        );
      },
    );
  }

  Widget _buildAvailableProductsCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).shadowColor.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.inventory_2,
                  color: Theme.of(context).colorScheme.primary,
                  size: 24,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 4,
                      backgroundColor: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'Available',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '${_products.length}',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w900,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          Text(
            'Products Available',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          Text(
            'Ready to add to requests',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentRequestItemsCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).shadowColor.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.tertiary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.assignment,
                  color: Theme.of(context).colorScheme.tertiary,
                  size: 24,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.tertiary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 4,
                      backgroundColor: Theme.of(context).colorScheme.tertiary,
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'Current',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '${_requestItems.length}',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w900,
              color: Theme.of(context).colorScheme.tertiary,
            ),
          ),
          Text(
            'Items in Request',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.tertiary,
            ),
          ),
          Text(
            'Ready to save',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessState() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Theme.of(context).colorScheme.tertiary.withValues(alpha: 0.2),
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).shadowColor.withValues(alpha: 0.06),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.tertiary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Theme.of(
                    context,
                  ).colorScheme.tertiary.withValues(alpha: 0.25),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Icon(
              Icons.check_circle,
              color: Theme.of(context).colorScheme.tertiary,
              size: 40,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            '🎉 Request Created Successfully!',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.tertiary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            'Your dealer request has been saved and is ready to share',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.tertiary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 4,
                      backgroundColor: Theme.of(context).colorScheme.tertiary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Request ID: #$_savedRequestId',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.tertiary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 4,
                      backgroundColor: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Items: ${_requestItems.length}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: _createNewRequest,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.secondary,
                    foregroundColor: Theme.of(context).colorScheme.onSecondary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Create Another',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: _generatePdf,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.download, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Download PDF',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDealerInformationForm() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).shadowColor.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.person,
                      color: Theme.of(context).colorScheme.primary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Dealer Information',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  Expanded(
                    child: Divider(
                      indent: 16,
                      color: Theme.of(context).dividerColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Form Fields
              LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth > 768) {
                    return Row(
                      children: [
                        Expanded(child: _buildDealerNameField()),
                        const SizedBox(width: 24),
                        Expanded(child: _buildDealerPhoneField()),
                      ],
                    );
                  } else {
                    return Column(
                      children: [
                        _buildDealerNameField(),
                        const SizedBox(height: 20),
                        _buildDealerPhoneField(),
                      ],
                    );
                  }
                },
              ),
              const SizedBox(height: 32),

              // Add Items Section
              _buildAddItemsSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDealerNameField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Dealer Name *',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _dealerNameController,
          decoration: InputDecoration(
            hintText: 'Enter dealer name',
            prefixIcon: Icon(
              Icons.person,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            filled: true,
            fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Theme.of(context).dividerColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Theme.of(context).dividerColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: Theme.of(context).colorScheme.primary,
                width: 2,
              ),
            ),
            contentPadding: const EdgeInsets.all(16),
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Dealer name is required';
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildDealerPhoneField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Phone Number (WhatsApp)',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _dealerPhoneController,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(
            hintText: '10-digit mobile number (optional)',
            prefixIcon: Icon(
              Icons.phone,
              color: Theme.of(context).colorScheme.tertiary,
            ),
            filled: true,
            fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Theme.of(context).dividerColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Theme.of(context).dividerColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: Theme.of(context).colorScheme.tertiary,
                width: 2,
              ),
            ),
            contentPadding: const EdgeInsets.all(16),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Used for WhatsApp sharing',
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildAddItemsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.add,
                color: Theme.of(context).colorScheme.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Add Items to Request',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            Expanded(
              child: Divider(indent: 16, color: Theme.of(context).dividerColor),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Add Items Form
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
            ),
          ),
          child: Column(
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth > 768) {
                    return Row(
                      children: [
                        Expanded(flex: 2, child: _buildProductDropdown()),
                        const SizedBox(width: 16),
                        Expanded(child: _buildQuantityField()),
                        const SizedBox(width: 16),
                        Expanded(child: _buildExpectedPriceField()),
                      ],
                    );
                  } else {
                    return Column(
                      children: [
                        _buildProductDropdown(),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(child: _buildQuantityField()),
                            const SizedBox(width: 16),
                            Expanded(child: _buildExpectedPriceField()),
                          ],
                        ),
                      ],
                    );
                  }
                },
              ),
              const SizedBox(height: 16),
              _buildNotesField(),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed:
                      (_selectedProductId != null &&
                          int.tryParse(_quantityController.text) != null &&
                          int.parse(_quantityController.text) > 0)
                      ? _handleAddItem
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Add to Request List',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProductDropdown() {
    if (_isLoading) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Select Product',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(
                      Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Loading products...',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    if (_products.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Select Product',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: Text(
              'No products found. Add products first.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select Product',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<int>(
          initialValue: _selectedProductId,
          isExpanded: true,
          decoration: InputDecoration(
            hintText: '🔍 Choose a product...',
            prefixIcon: Icon(
              Icons.inventory_2,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Theme.of(context).dividerColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Theme.of(context).dividerColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: Theme.of(context).colorScheme.primary,
                width: 2,
              ),
            ),
            contentPadding: const EdgeInsets.all(16),
          ),
          items: _products.map((product) {
            return DropdownMenuItem<int>(
              value: product.id,
              child: Text(
                '${product.name} (${product.brand})',
                overflow: TextOverflow.ellipsis,
              ),
            );
          }).toList(),
          onChanged: (value) {
            setState(() {
              _selectedProductId = value;
            });
          },
        ),
      ],
    );
  }

  Widget _buildQuantityField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quantity',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _quantityController,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            hintText: '1',
            prefixIcon: Icon(
              Icons.format_list_numbered,
              color: Theme.of(context).colorScheme.secondary,
            ),
            filled: true,
            fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Theme.of(context).dividerColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Theme.of(context).dividerColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: Theme.of(context).colorScheme.secondary,
                width: 2,
              ),
            ),
            contentPadding: const EdgeInsets.all(16),
          ),
        ),
      ],
    );
  }

  Widget _buildExpectedPriceField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Expected Price (₹)',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _expectedPriceController,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            hintText: '0.00',
            prefixIcon: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '₹',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.tertiary,
                ),
              ),
            ),
            filled: true,
            fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Theme.of(context).dividerColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Theme.of(context).dividerColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: Theme.of(context).colorScheme.tertiary,
                width: 2,
              ),
            ),
            contentPadding: const EdgeInsets.all(16),
          ),
        ),
      ],
    );
  }

  Widget _buildNotesField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Notes (Optional)',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _notesController,
          decoration: InputDecoration(
            hintText: 'Add any special notes or requirements...',
            prefixIcon: Icon(
              Icons.note,
              color: Theme.of(context).colorScheme.primary,
            ),
            filled: true,
            fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Theme.of(context).dividerColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Theme.of(context).dividerColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: Theme.of(context).colorScheme.primary,
                width: 2,
              ),
            ),
            contentPadding: const EdgeInsets.all(16),
          ),
        ),
      ],
    );
  }

  Widget _buildRequestItemsList() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).shadowColor.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header (responsive)
            LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 420;
                final leftHeader = Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.assignment,
                        color: Theme.of(context).colorScheme.primary,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Request List (${_requestItems.length} items)',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            'Total Quantity: ${_requestItems.fold<int>(0, (sum, item) => sum + item.quantity)}',
                            style: TextStyle(
                              fontSize: 14,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                );

                final printButton = Align(
                  alignment: isNarrow
                      ? Alignment.centerLeft
                      : Alignment.centerRight,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 180),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Print feature coming soon!'),
                            ),
                          );
                        },
                        icon: const Icon(Icons.print, size: 16),
                        label: const Text('Print List'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
                          foregroundColor: Theme.of(
                            context,
                          ).colorScheme.onSurface,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ),
                );

                if (isNarrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      leftHeader,
                      const SizedBox(height: 12),
                      printButton,
                    ],
                  );
                }
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(child: leftHeader),
                    const SizedBox(width: 12),
                    printButton,
                  ],
                );
              },
            ),
            const SizedBox(height: 24),

            // Items List
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _requestItems.length,
              itemBuilder: (context, index) {
                final item = _requestItems[index];
                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Theme.of(context).dividerColor),
                    boxShadow: [
                      BoxShadow(
                        color: Theme.of(
                          context,
                        ).shadowColor.withValues(alpha: 0.05),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: LayoutBuilder(
                      builder: (context, itemConstraints) {
                        final isWide = itemConstraints.maxWidth > 600;
                        if (isWide) {
                          return Row(
                            children: [
                              // Item Number
                              _buildItemNumberBadge(index),
                              const SizedBox(width: 16),
                              // Product Image
                              _buildItemImage(item),
                              const SizedBox(width: 16),
                              // Product Info
                              Expanded(child: _buildItemInfo(item)),
                              // Item Stats
                              _buildItemStats(item),
                              // Remove Button
                              const SizedBox(width: 16),
                              _buildRemoveButton(item),
                            ],
                          );
                        }
                        // Stacked mobile layout
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildItemNumberBadge(index),
                                const SizedBox(width: 12),
                                Expanded(child: _buildItemInfo(item)),
                                const SizedBox(width: 8),
                                _buildRemoveButton(item),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                _buildItemImage(item),
                                const SizedBox(width: 12),
                                Expanded(child: _buildItemStats(item)),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // --- Item builders for responsiveness ---
  Widget _buildItemNumberBadge(int index) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Text(
          '${index + 1}',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildItemImage(RequestItem item) {
    final box = BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Theme.of(context).dividerColor),
    );

    if (item.imageUrl == null || item.imageUrl!.isEmpty) {
      return Container(
        width: 64,
        height: 64,
        decoration: box,
        child: Icon(
          Icons.inventory_2,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          size: 24,
        ),
      );
    }

    final ref = item.imageUrl!;
    final isHttp = ref.startsWith('http://') || ref.startsWith('https://');

    Widget brokenIcon() => Icon(
      Icons.inventory_2,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      size: 24,
    );

    if (isHttp) {
      return Container(
        width: 64,
        height: 64,
        decoration: box,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(
            ref,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => brokenIcon(),
          ),
        ),
      );
    }

    // Try local file path
    final filePath = ref.startsWith('file://')
        ? ref.replaceFirst('file://', '')
        : ref;
    final f = File(filePath);
    if (f.existsSync()) {
      return Container(
        width: 64,
        height: 64,
        decoration: box,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.file(
            f,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => brokenIcon(),
          ),
        ),
      );
    }

    // Unknown reference type
    return Container(
      width: 64,
      height: 64,
      decoration: box,
      child: brokenIcon(),
    );
  }

  Widget _buildItemInfo(RequestItem item) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.name,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        if (item.notes.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            '"${item.notes}"',
            style: TextStyle(
              fontSize: 14,
              fontStyle: FontStyle.italic,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildItemStats(RequestItem item) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              children: [
                Text(
                  '${item.quantity}',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: Theme.of(context).colorScheme.tertiary,
                  ),
                ),
                Text(
                  'Qty',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 16),
            Column(
              children: [
                Text(
                  '₹${item.expectedPrice.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.tertiary,
                  ),
                ),
                Text(
                  'Expected',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.2),
            ),
          ),
          child: Text(
            'Total: ₹${(item.quantity * item.expectedPrice).toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRemoveButton(RequestItem item) {
    return IconButton(
      onPressed: () => _removeItem(item.productId),
      icon: Icon(
        Icons.close,
        color: Theme.of(context).colorScheme.error,
        size: 20,
      ),
      style: IconButton.styleFrom(
        backgroundColor: Theme.of(
          context,
        ).colorScheme.errorContainer.withValues(alpha: 0.4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget _buildSaveSection() {
    return Column(
      children: [
        // Summary Card
        if (_requestItems.isNotEmpty) ...[
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 760;

              final left = Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.calculate,
                      color: Theme.of(context).colorScheme.primary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Request Summary',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        'Ready to save and share',
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              );

              final stats = Wrap(
                alignment: isWide ? WrapAlignment.end : WrapAlignment.start,
                spacing: 24,
                runSpacing: 8,
                children: [
                  _buildSummaryItem(
                    '${_requestItems.length}',
                    'Items',
                    Theme.of(context).colorScheme.primary,
                  ),
                  _buildSummaryItem(
                    '${_requestItems.fold<int>(0, (sum, item) => sum + item.quantity)}',
                    'Total Qty',
                    Theme.of(context).colorScheme.secondary,
                  ),
                  _buildSummaryItem(
                    '₹${_requestItems.fold<double>(0, (sum, item) => sum + (item.quantity * item.expectedPrice)).toStringAsFixed(0)}',
                    'Expected',
                    Theme.of(context).colorScheme.tertiary,
                  ),
                ],
              );

              return Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Theme.of(
                      context,
                    ).dividerColor.withValues(alpha: 0.2),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Theme.of(
                        context,
                      ).shadowColor.withValues(alpha: 0.06),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: isWide
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(child: left),
                          const SizedBox(width: 12),
                          stats,
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [left, const SizedBox(height: 12), stats],
                      ),
              );
            },
          ),
          const SizedBox(height: 24),
        ],

        // Save Button
        SizedBox(
          width: 300,
          child: ElevatedButton(
            onPressed: (_requestItems.isNotEmpty && !_isSaving)
                ? _saveRequest
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: _requestItems.isEmpty
                  ? Theme.of(context).colorScheme.surfaceContainerHighest
                  : Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 20),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 4,
            ),
            child: _isSaving
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Theme.of(context).colorScheme.onPrimary,
                          ),
                        ),
                      ),
                      SizedBox(width: 12),
                      Text(
                        'Saving Request...',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.save, size: 24),
                      const SizedBox(width: 12),
                      Text(
                        _requestItems.isEmpty
                            ? 'Add Items to Save'
                            : 'Save Request',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _requestItems.isEmpty
              ? 'Add at least one item to save the request'
              : 'Request ready to save and share with dealer',
          style: TextStyle(
            fontSize: 14,
            color: _requestItems.isEmpty
                ? const Color(0xFF6B7280)
                : const Color(0xFF16A34A),
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildSummaryItem(String value, String label, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
