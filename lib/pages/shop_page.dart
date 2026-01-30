import 'package:flutter/material.dart';

import 'package:raj_electricals_inventory_app/theme/ui_tokens.dart';
import 'dart:async';
import '../data/app_database.dart';
import '../services/supabase_service.dart';
import '../models/supabase_models.dart' as supabase_models;
import '../services/receipt_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'dart:io';
import 'dart:ui';

import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'smart_scan_page.dart';
import '../services/connectivity_service.dart';
import '../services/voice_search_service.dart';
import 'package:app_links/app_links.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';

class ShopPage extends StatefulWidget {
  final AppDatabase db;
  const ShopPage({super.key, required this.db});

  @override
  State<ShopPage> createState() => _ShopPageState();
}

class _ShopPageState extends State<ShopPage> with TickerProviderStateMixin {
  // State variables
  String _searchQuery = '';
  String _selectedCategory = 'all';
  final bool _isGridView = true;
  int _cartCount = 0;
  final List<Map<String, dynamic>> _cartItems = [];
  final List<int> _wishlist = [];
  final List<int> _recentlyViewed = [];
  bool _isLoadingProducts = true;
  String? _loadErrorMessage;
  final ScrollController _scrollController = ScrollController();
  bool _isScrolled = false;
  String _businessName = 'Inventoza Shop';
  String? _businessLogoUrl;
  String? _rawLogoUrl;
  String? _currentBusinessId;

  final GlobalKey _filterBarKey = GlobalKey();
  supabase_models.BusinessProfile? _businessProfile;
  // Optional: Social and Maps links (set these if available)
  String? _instagramUrl; // e.g., https://instagram.com/yourhandle
  String? _whatsappCatalogUrl; // e.g., https://wa.me/c/<your-catalog-id>
  String? _googleMapsUrl; // e.g., https://maps.google.com/?q=...
  String? _mapMyIndiaUrl; // e.g., https://maps.mapmyindia.com/...

  // Advanced filter state
  final List<String> _brands = ['all'];
  final List<String> _specs = ['all']; // e.g., 6Amp, 16Amp, 1.5sqmm
  final List<String> _colors = ['all'];
  String _selectedBrand = 'all';
  String _selectedSpec = 'all';
  String _selectedColor = 'all';
  // Stock filter: 'all' | 'in' | 'out'
  String _stockFilter = 'all';
  // Multi-select support
  final Set<String> _selectedBrands = {};
  final Set<String> _selectedSpecs = {};
  final Set<String> _selectedColors = {};
  // Collapsible filters (mobile compact)
  bool _filtersExpanded = false;

  // Voice Search - Platform-specific implementation
  final VoiceSearchService _voiceSearchService = VoiceSearchService();
  bool _isListening = false;
  bool _speechAvailable = false;
  // Price range (text controllers so user can type)
  final TextEditingController _minPriceCtl = TextEditingController();
  final TextEditingController _maxPriceCtl = TextEditingController();
  RangeValues? _priceRange; // for range slider UI
  // Sort
  String _sortOption = 'Relevance';
  final List<String> _sortOptions = const [
    'Relevance',
    'Price: Low to High',
    'Price: High to Low',
    'Newest',
    'Name A-Z',
  ];
  // defined above
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  late NumberFormat _currencyFormat;
  // Product data
  List<Map<String, dynamic>> _products = [];
  List<String> _categories = ['all'];
  // Smart Search Filters
  List<String> _availableCategories = [];
  List<String> _availableBrands = [];

  // App Links
  late AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;

  // Pagination State
  int _page = 1;
  static const int _limit = 24;
  bool _hasMore = true;
  bool _isLoadingMore = false;

  @override
  void initState() {
    super.initState();
    _currencyFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹');
    _searchController.addListener(() {
      // Debounce handled by listener in build or manual calls?
      // Actually the text field calls onChanged: _onSearchChanged
    });
    _scrollController.addListener(_onScroll);
    _loadBusinessProfile().then((_) {
      _loadProductsAndCategories(reset: true);
      _loadFilters(); // Fetch distinct categories/brands for suggestions
    });
    _initSpeech();
    _initDeepLinks();
  }

  Future<void> _loadFilters() async {
    final filters = await SupabaseService.getShopFilters();
    if (mounted) {
      setState(() {
        _availableCategories = filters['categories'] ?? [];
        _availableBrands = filters['brands'] ?? [];
      });
    }
  }

  // Reloads products (Reset = true for fresh list, false for load more)
  Future<void> _loadProductsAndCategories({
    bool reset = false,
    int recursionDepth = 0,
  }) async {
    if (!mounted) return;
    if (recursionDepth > 5) return; // Recursion Guard

    if (reset) {
      setState(() {
        _page = 1;
        _products = [];
        _hasMore = true;
        _isLoadingProducts = true;
        _loadErrorMessage = null;
      });
    } else {
      if (_isLoadingMore || !_hasMore) return;
      // Only show loading indicator if it's the first call (depth 0)
      if (recursionDepth == 0) setState(() => _isLoadingMore = true);
    }

    try {
      final bid = _currentBusinessId ?? SupabaseService.getCurrentBusinessId();
      if (bid == null) {
        // Wait for profile if not ready
        await _loadBusinessProfile();
      }

      final double? minPrice = double.tryParse(_minPriceCtl.text.trim());
      final double? maxPrice = double.tryParse(_maxPriceCtl.text.trim());

      final result = await SupabaseService.getShopProductsV2(
        page: _page,
        limit: _limit,
        search: _searchQuery, // Use current UI search query
        category: _selectedCategory,
        minPrice: minPrice,
        maxPrice: maxPrice,
      );

      if (!mounted) return;

      final newProducts = (result['products'] as List)
          .cast<Map<String, dynamic>>();
      final total = result['total'] as int;

      // Extract categories from *loaded* products?
      // With pagination, we might miss categories if we only check loaded ones.
      // Ideally, categories should be a separate fetch or fixed list.
      // For now, we'll append unique categories from the new batch to existing list if desired,
      // or just keep 'all' + explicit ones if we have a separate API.
      // The RPC V2 doesn't return all categories. We might need a separate call for that.
      // Preserving existing category logic (append unique from batch):
      final newCats = <String>{};
      for (var p in newProducts) {
        final c = p['category']?.toString();
        if (c != null && c.isNotEmpty) newCats.add(c);
      }

      setState(() {
        if (reset) {
          _products = newProducts;
          // Reset categories only on full reset? Or accumulate?
          // If we reset, we might lose categories from other pages.
          // Better to keep accumulating or fetch global categories separately.
          // For now adding to existing _categories logic:
          final currentCats = Set<String>.from(_categories);
          currentCats.addAll(newCats);
          _categories = currentCats.toList()..sort();
          if (!_categories.contains('all')) _categories.insert(0, 'all');
        } else {
          // Append new products (Deduped by ID)
          for (var newP in newProducts) {
            if (!_products.any((p) => p['id'] == newP['id'])) {
              _products.add(newP);
            }
          }

          final currentCats = Set<String>.from(_categories);
          currentCats.addAll(newCats);
          _categories = currentCats.toList()..sort();
          if (!_categories.contains('all')) _categories.insert(0, 'all');
        }

        // Logic check: _products.length is collapsed count, total is raw count.
        // We cannot compare them directly.
        // Use page count logic:
        // fetchedSoFar = _page * _limit
        // hasMore = fetchedSoFar < total
        final fetchedSoFar = _page * _limit;
        _hasMore = fetchedSoFar < total;

        _page++;

        _isLoadingProducts = false;
        _isLoadingMore = false;
      });

      // Auto-Fill Loop:
      // If merging reduced the list size significantly (< 10 items) and there's more data,
      // strictly fetch the next page to ensure the screen is filled.
      if (!reset && _hasMore && _products.length < 10) {
        await _loadProductsAndCategories(
          reset: false,
          recursionDepth: recursionDepth + 1,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingProducts = false;
          _isLoadingMore = false;
          if (reset) _loadErrorMessage = 'Failed to load products: $e';
        });
      }
    } finally {
      // Robust Fail-safe:
      // If after all loading (and potential recursion), the list is still small
      // and there's more data, schedule another fetch.
      // This covers cases where recursion limit was hit but screen isn't full.
      if (mounted && _hasMore && _products.length < 10 && !_isLoadingProducts) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (_scrollController.hasClients) {
            // Check absolute height or just item count
            if (_scrollController.position.maxScrollExtent < 500) {
              _loadProductsAndCategories(reset: false);
            }
          }
        });
      }
    }
  }

  Future<void> _initDeepLinks() async {
    _appLinks = AppLinks();

    // Check initial link
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        _handleDeepLink(initialUri);
      }
    } catch (_) {}

    // Listen to changes
    _linkSubscription = _appLinks.uriLinkStream.listen((uri) {
      _handleDeepLink(uri);
    });
  }

  Future<void> _handleDeepLink(Uri uri) async {
    // Expected format: https://rajelectricals.com/store/<slug> or myshop://store/<slug>
    if (uri.pathSegments.contains('store')) {
      final index = uri.pathSegments.indexOf('store');
      if (index + 1 < uri.pathSegments.length) {
        final slug = uri.pathSegments[index + 1];
        await _switchShop(slug);
      }
    }
  }

  Future<void> _switchShop(String slug) async {
    if (!mounted) return;

    // Show loading indicator or toast
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Loading shop details...')));

    final profile = await SupabaseService.getBusinessBySlug(slug);
    if (profile != null) {
      final businessId = profile['id'] as String;
      final businessName = profile['business_name'] as String;

      // Update Service
      SupabaseService.setDefaultBusinessId(businessId);

      // Persist
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('DEFAULT_BUSINESS_ID', businessId);

      // Refresh Page
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Welcome to $businessName')));
        _loadBusinessProfile();
        _loadProductsAndCategories(); // Reload products for new business
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Shop not found')));
      }
    }
  }

  Future<void> _initSpeech() async {
    // Initialize platform-specific voice search service
    final available = await _voiceSearchService.initialize();
    if (mounted) {
      setState(() {
        _speechAvailable = available;
      });
    }
  }

  Future<void> _listen(BuildContext context) async {
    if (!_speechAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Voice search not available on this device'),
        ),
      );
      return;
    }

    if (_isListening) {
      await _voiceSearchService.stopListening();
      if (mounted) {
        setState(() => _isListening = false);
      }
      return;
    }

    await _voiceSearchService.startListening(
      onResult: (text) {
        if (mounted && text.isNotEmpty) {
          setState(() {
            _searchController.text = text;
          });
          _onSearchChanged(text);
        }
      },
      onStatusChange: (isListening) {
        if (mounted) {
          setState(() => _isListening = isListening);
        }
      },
      localeId: 'en_IN', // English (India) for better local recognition
    );
  }

  Future<void> _openCameraLabelScan(BuildContext context) async {
    await _openSmartScan(context);
  }

  void _onScroll() {
    final bool scrolled =
        _scrollController.hasClients && _scrollController.offset > 4;
    if (scrolled != _isScrolled) {
      setState(() => _isScrolled = scrolled);
    }

    // Infinite Scroll - DISABLED (Switched to Load More Button)
    /*
    if (_scrollController.hasClients) {
      final maxScroll = _scrollController.position.maxScrollExtent;
      final currentScroll = _scrollController.position.pixels;
      // Trigger if close to bottom (e.g. 200px) and not already loading / exhausted
      if (maxScroll - currentScroll <= 200) {
        if (_hasMore && !_isLoadingMore && !_isLoadingProducts) {
          _loadProductsAndCategories(reset: false);
        }
      }
    }
    */
  }

  // Open Lens-like Smart Scan camera and apply returned query
  Future<void> _openSmartScan(BuildContext context) async {
    final query = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const SmartScanPage()));
    if (query == null || !mounted) return;
    setState(() {
      _searchController.text = query;
    });
    _onSearchChanged(query);
  }

  // --- Search quality helpers: stopwords, synonyms, scoring ---
  static const Set<String> _stopWords = {
    'the',
    'a',
    'an',
    'and',
    'or',
    'for',
    'of',
    'to',
    'with',
    'by',
    'in',
    'on',
    'at',
    'from',
    'new',
    'pack',
    'piece',
    'pieces',
  };

  static const Map<String, List<String>> _synonyms = {
    'typec': ['type-c', 'usb-c', 'usbc', 'c-type', 'c type', 'usb type c'],
    'micro': ['micro-usb', 'microusb', 'micro usb'],
    'earphone': [
      'earphones',
      'earbuds',
      'headset',
      'headphones',
      'ear bud',
      'ear buds',
    ],
    'adapter': ['adaptor', 'charger', 'power adapter', 'power adaptor'],
    'cable': ['wire', 'lead', 'cord'],
    'bulb': ['lamp', 'light'],
    'switch': ['switches'],
    'socket': [
      'outlet',
      'power socket',
      'wall socket',
      '3 pin',
      '3-pin',
      'three pin',
      'plug point',
      'plug',
      '3 way',
      '3-way',
    ],
    'switchboard': [
      'switch board',
      'switch plate',
      'faceplate',
      'switch panel',
      'board',
    ],
    'screwdriver': [
      'screw driver',
      'driver',
      'phillips',
      'philips',
      'flathead',
      'flat head',
      'slotted',
      'torx',
      'pozidriv',
      'pozi',
      'ph',
      'pz',
    ],
    'smart scan': [
      'smart scan',
      'unified scan',
      'camera search',
      'visual search',
    ],
  };

  List<String> _normalizeAndExpandTokens(String query) {
    // Phase 1: Aggressive pre-splitting of number+unit combos
    // e.g. "0.5w" -> "0.5 w", "6amp" -> "6 amp"
    String processed = query.toLowerCase();
    processed = processed.replaceAllMapped(
      RegExp(r'(\d+(\.\d+)?)([a-z]+)'),
      (match) => '${match.group(1)} ${match.group(3)}',
    );

    final base = processed
        .replaceAll(RegExp(r'[^a-z0-9\-\. ]+'), ' ') // Allow dots
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty && !_stopWords.contains(t))
        .toList();

    final expanded = <String>{};
    for (final t in base) {
      expanded.add(t);

      // Handle "type-c" -> "typec"
      if (t.contains('-')) {
        expanded.add(t.replaceAll('-', ''));
      }

      // Synonyms
      final k = t.replaceAll('-', '');
      final syns = _synonyms[k];
      if (syns != null) expanded.addAll(syns);
    }

    return expanded
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
  }

  int _relevanceScore(Map<String, dynamic> product, List<String> tokens) {
    if (tokens.isEmpty) return 0;
    final name = (product['name'] ?? '').toString().toLowerCase();
    final brand = (product['brand'] ?? '').toString().toLowerCase();
    final category = (product['category'] ?? '').toString().toLowerCase();
    final spec = (product['spec'] ?? '').toString().toLowerCase();
    final desc = (product['description'] ?? '').toString().toLowerCase();
    final hay = '$name $brand $category $spec $desc';

    int score = 0;
    for (final t in tokens) {
      final token = t.trim();
      if (token.isEmpty) continue;
      if (name.contains(token)) {
        score += 10;
      } else if (brand.contains(token)) {
        score += 9;
      } else if (category.contains(token)) {
        score += 8;
      } else if (spec.contains(token)) {
        score += 6;
      } else if (desc.contains(token)) {
        score += 3;
      }

      final words = hay.split(RegExp(r'[^a-z0-9]+')).where((w) => w.isNotEmpty);
      int best = 99;
      for (final w in words) {
        final d = _levenshtein(w, token);
        if (d < best) best = d;
      }
      if (best == 1) score += 2;
      if (best == 2) score += 1;

      if (RegExp(r'^\d+$').hasMatch(token) && hay.contains(token)) score += 3;
    }
    return score;
  }

  // Camera Search: Quick menu (Barcode or Text OCR)
  void _openCameraSearchQuick(BuildContext context) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.qr_code_scanner),
                title: const Text('Scan barcode or QR'),
                subtitle: const Text('Instantly search by code'),
                onTap: () {
                  Navigator.pop(ctx);
                  _openBarcodeScannerSheet(ctx);
                },
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined),
                title: const Text('Scan text (OCR)'),
                subtitle: const Text('Capture label/text and search'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _openCameraTextScan(ctx);
                },
              ),
              ListTile(
                leading: const Icon(Icons.image_search_outlined),
                title: const Text('Visual search (on-device)'),
                subtitle: const Text('Labels + objects, zero cloud cost'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _openCameraLabelScan(ctx);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // Barcode Scanner Sheet
  Future<void> _openBarcodeScannerSheet(BuildContext context) async {
    final controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
      torchEnabled: false,
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black,
      builder: (ctx) {
        return SafeArea(
          child: Stack(
            children: [
              MobileScanner(
                controller: controller,
                onDetect: (capture) {
                  final barcodes = capture.barcodes;
                  if (barcodes.isEmpty) return;
                  final value = barcodes.first.rawValue?.trim();
                  if (value == null || value.isEmpty) return;
                  if (!mounted) return;
                  setState(() {
                    _searchController.text = value;
                  });
                  _onSearchChanged(value);
                  Navigator.of(ctx).pop();
                },
              ),
              // Top bar
              Positioned(
                top: 8,
                left: 8,
                right: 8,
                child: Row(
                  children: [
                    IconButton(
                      color: Colors.white,
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Point at barcode or QR',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                    const Spacer(),
                    IconButton(
                      color: Colors.white,
                      icon: const Icon(Icons.flash_on),
                      onPressed: () => controller.toggleTorch(),
                    ),
                    IconButton(
                      color: Colors.white,
                      icon: const Icon(Icons.cameraswitch),
                      onPressed: () => controller.switchCamera(),
                    ),
                  ],
                ),
              ),
              // Simple viewfinder
              Center(
                child: Container(
                  width: 260,
                  height: 260,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.7),
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ).whenComplete(() => controller.dispose());
  }

  // OCR capture via camera -> text search
  Future<void> _openCameraTextScan(BuildContext context) async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? shot = await picker.pickImage(source: ImageSource.camera);
      if (shot == null) return;

      final inputImage = InputImage.fromFilePath(shot.path);
      final textRecognizer = TextRecognizer(
        script: TextRecognitionScript.latin,
      );
      final RecognizedText recognizedText = await textRecognizer.processImage(
        inputImage,
      );
      await textRecognizer.close();

      // Build a concise query from recognized text
      final buffer = StringBuffer();
      for (final block in recognizedText.blocks) {
        for (final line in block.lines) {
          final t = line.text.trim();
          if (t.isNotEmpty) buffer.write('$t ');
        }
      }
      final full = buffer.toString().toLowerCase();
      if (full.isEmpty) return;

      // Heuristic: take first 5 relevant tokens
      final tokens = full
          .split(RegExp(r'[^a-z0-9\-]+'))
          .where((w) => w.length >= 3)
          .take(5)
          .join(' ');

      if (!mounted) return;
      setState(() {
        _searchController.text = tokens;
      });
      _onSearchChanged(tokens);
    } catch (_) {}
  }

  // Simple Levenshtein distance (lowercase inputs recommended)
  int _levenshtein(String s, String t) {
    final m = s.length;
    final n = t.length;
    if (m == 0) return n;
    if (n == 0) return m;
    final prev = List<int>.generate(n + 1, (j) => j);
    final curr = List<int>.filled(n + 1, 0);
    for (int i = 1; i <= m; i++) {
      curr[0] = i;
      final sc = s.codeUnitAt(i - 1);
      for (int j = 1; j <= n; j++) {
        final cost = sc == t.codeUnitAt(j - 1) ? 0 : 1;
        final del = prev[j] + 1;
        final ins = curr[j - 1] + 1;
        final sub = prev[j - 1] + cost;
        int v = del;
        if (ins < v) v = ins;
        if (sub < v) v = sub;
        curr[j] = v;
      }
      // swap prev/curr
      for (int j = 0; j <= n; j++) {
        final tmp = prev[j];
        prev[j] = curr[j];
        curr[j] = tmp;
      }
    }
    return prev[n];
  }

  Future<void> _loadBusinessProfile() async {
    try {
      final p = await SupabaseService.getCurrentBusinessProfile();
      if (!mounted) return;
      setState(() {
        _businessProfile = p;
        if (p != null) {
          _businessName = p.businessName;
          _businessLogoUrl = p.logoUrl;
          _currentBusinessId = p.id;
        }
        // Social + Maps links (from user-provided values)
        _instagramUrl = 'https://www.instagram.com/raj_electricals_hardware/';
        _whatsappCatalogUrl = 'https://wa.me/c/919911636339';
        _googleMapsUrl = 'https://share.google/kJ0sqD2CEQwy1XYCA';
        // _mapMyIndiaUrl left null for now (user will provide later)
      });
    } catch (_) {}
  }

  // Pinned filter + search header (tablet/desktop), expandable with filters
  // Pinned filter + search header (tablet/desktop), expandable with filters
  SliverPersistentHeader _buildPinnedFilterSearchHeader(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    const double collapsedH = 125;
    final double expandedH = _filtersExpanded
        ? (width > 1024 ? 360 : 330)
        : 125;

    return SliverPersistentHeader(
      pinned: true,
      delegate: _SimpleHeaderDelegate(
        minHeight: _filtersExpanded ? expandedH : collapsedH,
        maxHeight: expandedH,
        child: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              color: Theme.of(context).cardColor.withValues(alpha: 0.8),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Builder(
                builder: (context) {
                  final cs = Theme.of(context).colorScheme;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Row 1: Search Bar + Filter Toggle
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              onChanged: _onSearchChanged,
                              decoration: InputDecoration(
                                hintText: _isListening
                                    ? 'Listening...'
                                    : 'Search products...',
                                hintStyle: TextStyle(
                                  fontSize: 14,
                                  color: cs.onSurfaceVariant,
                                ),
                                prefixIcon: const Icon(Icons.search, size: 20),
                                filled: true,
                                fillColor: cs.surface.withValues(alpha: 0.5),
                                contentPadding: const EdgeInsets.symmetric(
                                  vertical: 0,
                                  horizontal: 16,
                                ),
                                suffixIcon: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (_searchController.text.isNotEmpty)
                                      IconButton(
                                        icon: const Icon(Icons.clear, size: 18),
                                        onPressed: () {
                                          _searchController.clear();
                                          _onSearchChanged('');
                                        },
                                      ),
                                    if (_speechAvailable)
                                      IconButton(
                                        icon: Icon(
                                          _isListening
                                              ? Icons.mic
                                              : Icons.mic_none,
                                          size: 20,
                                          color: _isListening
                                              ? Colors.red
                                              : null,
                                        ),
                                        onPressed: () => _listen(context),
                                        tooltip: 'Voice Search',
                                      ),
                                    const SizedBox(width: 4),
                                  ],
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(999),
                                  borderSide: BorderSide.none,
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(999),
                                  borderSide: BorderSide(
                                    color: cs.outline.withValues(alpha: 0.1),
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(999),
                                  borderSide: BorderSide(
                                    color: cs.primary.withValues(alpha: 0.5),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Smart Scan Action
                          IconButton.filledTonal(
                            onPressed: () => _openCameraSearchQuick(context),
                            icon: const Icon(Icons.qr_code_scanner),
                            tooltip: 'Scan Code',
                          ),
                          const SizedBox(width: 8),
                          // Filter Toggle
                          IconButton.outlined(
                            onPressed: () {
                              setState(() {
                                _filtersExpanded = !_filtersExpanded;
                              });
                            },
                            icon: Icon(
                              _filtersExpanded
                                  ? Icons.filter_list_off
                                  : Icons.tune,
                            ),
                            tooltip: 'Filters',
                            style: IconButton.styleFrom(
                              side: BorderSide(
                                color: cs.outline.withValues(alpha: 0.2),
                              ),
                            ),
                          ),
                        ],
                      ),

                      if (!_filtersExpanded) ...[
                        const SizedBox(height: 12),
                        // Row 2: Categories Horizontal List (Pills)
                        SizedBox(
                          height: 36,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: _categories.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 8),
                            itemBuilder: (context, index) {
                              final cat = _categories[index];
                              final isSelected = _selectedCategory == cat;
                              final label = cat == 'all'
                                  ? 'All Items'
                                  : (cat[0].toUpperCase() + cat.substring(1));

                              return ChoiceChip(
                                label: Text(label),
                                selected: isSelected,
                                onSelected: (selected) {
                                  if (selected) {
                                    setState(() {
                                      _selectedCategory = cat;
                                      // Server-side filter reset
                                      _loadProductsAndCategories(reset: true);
                                      _scrollToProducts();
                                    });
                                  }
                                },
                                showCheckmark: false,
                                labelStyle: TextStyle(
                                  fontSize: 13,
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                  color: isSelected
                                      ? cs.onPrimary
                                      : cs.onSurface,
                                ),
                                selectedColor: cs.primary,
                                backgroundColor: Colors.transparent,
                                side: isSelected
                                    ? BorderSide.none
                                    : BorderSide(
                                        color: cs.outline.withValues(
                                          alpha: 0.2,
                                        ),
                                      ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              );
                            },
                          ),
                        ),
                      ],

                      if (_filtersExpanded) ...[
                        const SizedBox(height: 16),
                        const Divider(height: 1),
                        const SizedBox(height: 16),
                        Expanded(
                          child: SingleChildScrollView(
                            child: _buildCollapsibleFilters(context, cs),
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _footerActionChip(
    BuildContext context,
    IconData icon,
    String label,
    String url,
  ) {
    final borderColor = Theme.of(context).dividerColor.withValues(alpha: 0.25);
    final bg = Theme.of(
      context,
    ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35);
    return InkWell(
      onTap: () async {
        try {
          final uri = Uri.parse(url);
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } catch (_) {}
      },
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showMultiSelectBottomSheet(
    BuildContext context, {
    required String title,
    required List<String> options,
    required Set<String> targetSet,
  }) async {
    final initial = Set<String>.from(targetSet);
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final List<String> opts = options.where((o) => o != 'all').toList();
        final local = Set<String>.from(initial);
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return StatefulBuilder(
              builder: (context, setLocal) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.filter_list),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              title,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          TextButton(
                            onPressed: () => setLocal(() => local.clear()),
                            child: const Text('Clear'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: SingleChildScrollView(
                          controller: scrollController,
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final o in opts)
                                FilterChip(
                                  label: Text(o),
                                  selected: local.contains(o),
                                  onSelected: (sel) => setLocal(() {
                                    if (sel) {
                                      local.add(o);
                                    } else {
                                      local.remove(o);
                                    }
                                  }),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              onPressed: () {
                                setState(() {
                                  targetSet
                                    ..clear()
                                    ..addAll(local);
                                  // Clear single-select counterpart to avoid confusion
                                  if (title.toLowerCase().contains('brand')) {
                                    _selectedBrand = 'all';
                                  } else if (title.toLowerCase().contains(
                                    'spec',
                                  )) {
                                    _selectedSpec = 'all';
                                  } else if (title.toLowerCase().contains(
                                    'color',
                                  )) {
                                    _selectedColor = 'all';
                                  }
                                });
                                _scrollToProducts();
                                Navigator.of(context).pop();
                              },
                              child: const Text('Apply'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  // Direct "Buy Now" for a single product (skips cart)
  Future<void> _buyNow(
    BuildContext context,
    Map<String, dynamic> product,
    int qty,
  ) async {
    if (!ConnectivityService().isOnline.value) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: const [
                Icon(Icons.wifi_off, color: Colors.white),
                SizedBox(width: 8),
                Text('You are offline. Cannot buy now.'),
              ],
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }
    final int stock = (product['stock'] as int?) ?? 0;
    if (stock <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Out of stock')));
      }
      return;
    }
    final double price = (product['price'] as num?)?.toDouble() ?? 0.0;
    if (price <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid price for this product')),
        );
      }
      return;
    }
    if (qty <= 0) qty = 1;
    final double total = price * qty;

    String upiId = 'pradeepsupergalaxy12@okicici';
    if (_businessProfile?.upiVpa != null &&
        _businessProfile!.upiVpa!.isNotEmpty) {
      upiId = _businessProfile!.upiVpa!;
    }
    if (!_isValidUpiVpa(upiId)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Receiver UPI ID not set. Please try again later.'),
          ),
        );
      }
      return;
    }

    String payeeName = _sanitizeUpiName(_businessName).trim();
    if (payeeName.isEmpty) payeeName = 'Merchant';
    if (payeeName.length > 20) payeeName = payeeName.substring(0, 20);
    final String checkoutId =
        'RE-BN-${DateTime.now().millisecondsSinceEpoch}-${product['id']}';
    String tnBase = 'Buy ${product['name'] ?? 'Item'}';
    if (tnBase.length > 28) tnBase = tnBase.substring(0, 28);
    String tn = '$tnBase ${checkoutId.substring(checkoutId.length - 6)}';
    if (tn.length > 40) tn = tn.substring(0, 40);

    final qp = [
      'pa=${Uri.encodeQueryComponent(upiId)}',
      'pn=${Uri.encodeQueryComponent(payeeName)}',
      'am=${Uri.encodeQueryComponent(total.toStringAsFixed(2))}',
      'cu=INR',
      'tr=${Uri.encodeQueryComponent(checkoutId)}',
      'tid=${Uri.encodeQueryComponent(checkoutId)}',
      'tn=${Uri.encodeQueryComponent(tn)}',
    ].join('&');

    final bool isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    bool launched = false;
    if (isMobile) {
      launched = await _tryLaunchUri(Uri.parse('upi://pay?$qp'));
      if (!launched) {
        final intentUri = Uri.parse('intent://pay?$qp#Intent;scheme=upi;end');
        launched = await _tryLaunchUri(intentUri);
      }
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No UPI app found to handle this payment.'),
          ),
        );
      }
    }

    if (mounted) {
      _showUpiConfirmationSheetForBuyNow(
        context,
        checkoutId,
        total,
        product,
        qty,
      );
    }
  }

  void _showUpiConfirmationSheetForBuyNow(
    BuildContext context,
    String checkoutId,
    double total,
    Map<String, dynamic> product,
    int qty,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (BuildContext ctx) {
        bool showQr = !(Platform.isAndroid || Platform.isIOS);
        return StatefulBuilder(
          builder: (context, setSheetState) {
            // Build UPI URI for QR
            const upiId = 'pradeepsupergalaxy12@okicici';
            String pn = _sanitizeUpiName(_businessName).trim();
            if (pn.isEmpty) pn = 'Merchant';
            if (pn.length > 20) pn = pn.substring(0, 20);
            String tnBase = 'Buy ${product['name'] ?? 'Item'}';
            if (tnBase.length > 28) tnBase = tnBase.substring(0, 28);
            String tn =
                '$tnBase ${checkoutId.substring(checkoutId.length - 6)}';
            if (tn.length > 40) tn = tn.substring(0, 40);
            final qp = [
              'pa=${Uri.encodeQueryComponent(upiId)}',
              'pn=${Uri.encodeQueryComponent(pn)}',
              'am=${Uri.encodeQueryComponent(total.toStringAsFixed(2))}',
              'cu=INR',
              'tr=${Uri.encodeQueryComponent(checkoutId)}',
              'tid=${Uri.encodeQueryComponent(checkoutId)}',
              'tn=${Uri.encodeQueryComponent(tn)}',
            ].join('&');
            final upiUri = 'upi://pay?$qp';
            final mq = MediaQuery.of(ctx);
            double qrSize = 260;
            final double w = mq.size.width;
            final double h = mq.size.height;
            if (w < 360) {
              qrSize = 200;
            } else if (w < 480) {
              qrSize = 220;
            } else if (w < 768) {
              qrSize = 240;
            } else {
              qrSize = 280;
            }
            final double capByHeight = h * 0.35;
            if (qrSize > capByHeight) {
              qrSize = capByHeight;
            }
            final bool disableScroll = h >= 720;

            return SingleChildScrollView(
              physics: disableScroll
                  ? const NeverScrollableScrollPhysics()
                  : null,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.payments_outlined),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Complete Payment',
                            style: Theme.of(ctx).textTheme.titleMedium,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () =>
                              setSheetState(() => showQr = !showQr),
                          icon: const Icon(Icons.qr_code_2),
                          label: Text(showQr ? 'Hide QR' : 'Show QR'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Amount: ₹${total.toStringAsFixed(2)}  •  Item: ${product['name']}',
                      style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(
                          ctx,
                        ).textTheme.bodySmall?.color?.withValues(alpha: 0.8),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (showQr) ...[
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              ctx,
                            ).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Theme.of(
                                ctx,
                              ).dividerColor.withValues(alpha: 0.2),
                            ),
                          ),
                          child: QrImageView(
                            data: upiUri,
                            version: QrVersions.auto,
                            size: qrSize,
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: SelectableText(
                          upiId,
                          style: Theme.of(ctx).textTheme.bodySmall,
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    Text(
                      'Pay via UPI app or scan QR from another phone, then upload the payment screenshot for verification.',
                      style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                        color: Theme.of(
                          ctx,
                        ).textTheme.bodySmall?.color?.withValues(alpha: 0.9),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => Navigator.of(ctx).pop(),
                            icon: const Icon(Icons.close),
                            label: const Text('Close'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () async {
                              final file = await _pickPaymentScreenshot();
                              if (file == null) return;
                              if (mounted) Navigator.of(ctx).pop();
                              await _completeBuyNowSaleWithProof(
                                ctx,
                                checkoutId,
                                total,
                                product,
                                qty,
                                file,
                              );
                            },
                            icon: const Icon(Icons.upload_file),
                            label: const Text('Upload Payment Screenshot'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _openImageGallery(
    BuildContext context,
    List<String> images,
    int initialIndex,
  ) {
    if (images.isEmpty) return;
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black87,
      builder: (ctx) {
        int current = initialIndex.clamp(0, images.length - 1);
        final controller = PageController(initialPage: current);
        bool showHints = true;
        bool hideScheduled = false;
        return Dialog(
          backgroundColor: Colors.black,
          insetPadding: EdgeInsets.zero,
          child: StatefulBuilder(
            builder: (context, setState) {
              if (!hideScheduled) {
                hideScheduled = true;
                Future.delayed(const Duration(seconds: 5), () {
                  if (showHints) {
                    setState(() => showHints = false);
                  }
                });
              }
              return KeyboardListener(
                focusNode: FocusNode(),
                autofocus: true,
                onKeyEvent: (KeyEvent e) {
                  if (e is KeyDownEvent) {
                    if (e.logicalKey == LogicalKeyboardKey.arrowRight) {
                      if (current < images.length - 1) {
                        current++;
                        controller.animateToPage(
                          current,
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeInOut,
                        );
                        setState(() {});
                      }
                    } else if (e.logicalKey == LogicalKeyboardKey.arrowLeft) {
                      if (current > 0) {
                        current--;
                        controller.animateToPage(
                          current,
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeInOut,
                        );
                        setState(() {});
                      }
                    } else if (e.logicalKey == LogicalKeyboardKey.home) {
                      if (current != 0) {
                        current = 0;
                        controller.jumpToPage(current);
                        setState(() {});
                      }
                    } else if (e.logicalKey == LogicalKeyboardKey.end) {
                      if (current != images.length - 1) {
                        current = images.length - 1;
                        controller.jumpToPage(current);
                        setState(() {});
                      }
                    } else if (e.logicalKey == LogicalKeyboardKey.escape) {
                      Navigator.of(ctx).pop();
                    } else if (e.logicalKey == LogicalKeyboardKey.keyH ||
                        e.logicalKey == LogicalKeyboardKey.slash) {
                      // Toggle hints
                      showHints = !showHints;
                      setState(() {});
                    }
                  }
                },
                child: Stack(
                  children: [
                    PageView.builder(
                      controller: controller,
                      onPageChanged: (i) => setState(() => current = i),
                      itemCount: images.length,
                      itemBuilder: (context, index) {
                        final url = images[index];
                        return Center(
                          child: InteractiveViewer(
                            minScale: 1.0,
                            maxScale: 4.0,
                            child: Image.network(
                              url,
                              headers: const {
                                'User-Agent':
                                    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                              },
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.image_not_supported,
                                color: Colors.white70,
                                size: 48,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    Positioned(
                      top: 16,
                      right: 16,
                      child: IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ),
                    // Desktop mouse navigation buttons (left/right)
                    if (images.length > 1 &&
                        MediaQuery.of(context).size.width > 800) ...[
                      Positioned(
                        left: 8,
                        top: 0,
                        bottom: 0,
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              if (current > 0) {
                                current--;
                                controller.animateToPage(
                                  current,
                                  duration: const Duration(milliseconds: 200),
                                  curve: Curves.easeInOut,
                                );
                                setState(() {});
                              }
                            },
                            child: Container(
                              width: 64,
                              height: double.infinity,
                              alignment: Alignment.center,
                              color: Colors.transparent,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.35),
                                  shape: BoxShape.circle,
                                ),
                                padding: const EdgeInsets.all(8),
                                child: const Icon(
                                  Icons.chevron_left,
                                  color: Colors.white,
                                  size: 36,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 8,
                        top: 0,
                        bottom: 0,
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              if (current < images.length - 1) {
                                current++;
                                controller.animateToPage(
                                  current,
                                  duration: const Duration(milliseconds: 200),
                                  curve: Curves.easeInOut,
                                );
                                setState(() {});
                              }
                            },
                            child: Container(
                              width: 64,
                              height: double.infinity,
                              alignment: Alignment.center,
                              color: Colors.transparent,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.35),
                                  shape: BoxShape.circle,
                                ),
                                padding: const EdgeInsets.all(8),
                                child: const Icon(
                                  Icons.chevron_right,
                                  color: Colors.white,
                                  size: 36,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                    if (images.length > 1)
                      Positioned(
                        bottom: 20,
                        left: 0,
                        right: 0,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            for (int i = 0; i < images.length; i++)
                              Container(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                width: i == current ? 10 : 8,
                                height: i == current ? 10 : 8,
                                decoration: BoxDecoration(
                                  color: i == current
                                      ? Colors.white
                                      : Colors.white.withValues(alpha: 0.5),
                                  shape: BoxShape.circle,
                                ),
                              ),
                          ],
                        ),
                      ),
                    // Desktop keyboard hints overlay (theme-aware)
                    if (MediaQuery.of(context).size.width > 800 && showHints)
                      Positioned(
                        bottom: 20,
                        left: 20,
                        child: Builder(
                          builder: (context) {
                            final theme = Theme.of(context);
                            final bg = theme.cardColor.withValues(alpha: 0.85);
                            final textStyle =
                                theme.textTheme.bodySmall?.copyWith(
                                  color: theme.textTheme.bodySmall?.color,
                                  fontSize: 12,
                                ) ??
                                const TextStyle(
                                  fontSize: 12,
                                  color: Colors.white,
                                );
                            final titleStyle =
                                theme.textTheme.bodySmall?.copyWith(
                                  color: theme.textTheme.bodySmall?.color,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ) ??
                                const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                );
                            return Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: bg,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: theme.dividerColor.withValues(
                                    alpha: 0.2,
                                  ),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Navigation shortcuts',
                                    style: titleStyle,
                                  ),
                                  const SizedBox(height: 4),
                                  Text('→  Next image', style: textStyle),
                                  Text('←  Previous image', style: textStyle),
                                  Text('Home  First image', style: textStyle),
                                  Text('End  Last image', style: textStyle),
                                  Text('Esc  Close gallery', style: textStyle),
                                  const SizedBox(height: 4),
                                  Text(
                                    'H or /  Toggle this help',
                                    style: textStyle,
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  // Sanitize UPI payee name to ASCII-friendly subset many UPI apps expect
  String _sanitizeUpiName(String name) {
    final cleaned = name.replaceAll(RegExp(r'[^A-Za-z0-9 .&\-]'), '').trim();
    return cleaned.isEmpty ? 'Merchant' : cleaned;
  }

  // UPI helpers
  bool _isValidUpiVpa(String? vpa) {
    if (vpa == null) return false;
    final s = vpa.trim();
    final re = RegExp(r'^[A-Za-z0-9.\-_]{2,}@[A-Za-z]{2,}$');
    return re.hasMatch(s);
  }

  // Safely attempt to launch a URI, returning false if not handled or if it throws
  Future<bool> _tryLaunchUri(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    _scrollController.dispose();
    _searchDebounce?.cancel();
    _searchController.dispose();
    _minPriceCtl.dispose();
    _maxPriceCtl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();

    // Check if value is a redirect link or deep link
    // Format 1: https://.../shop_redirect.html?id=slug
    // Format 2: myshop://store/slug
    final trimmed = value.trim();
    if (trimmed.contains('shop_redirect.html') && trimmed.contains('id=')) {
      try {
        final uri = Uri.parse(trimmed);
        final slug = uri.queryParameters['id'];
        if (slug != null && slug.isNotEmpty) {
          _searchController.clear();
          _switchShop(slug);
          return;
        }
      } catch (_) {}
    } else if (trimmed.startsWith('myshop://store/')) {
      final slug = trimmed.replaceFirst('myshop://store/', '');
      if (slug.isNotEmpty) {
        _searchController.clear();
        _switchShop(slug);
        return;
      }
    }

    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() => _searchQuery = _searchController.text.trim());
      // Reset to page 1 for new search
      _loadProductsAndCategories(reset: true);
      // Bring products into view when searching
      _scrollToProducts();
    });
  }

  // Smoothly scroll to a section identified by a GlobalKey
  Future<void> _scrollToKey(GlobalKey key) async {
    final ctx = key.currentContext;
    if (ctx == null) return;
    await Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
      alignment: 0.05,
    );
  }

  Future<void> _launchUrl(String? urlString) async {
    if (urlString == null || urlString.isEmpty) return;
    final uri = Uri.parse(urlString);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    } catch (_) {}
  }

  void _scrollToProducts() => _scrollToKey(_filterBarKey);

  void _openCart(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 20,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Handle Bar
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: 12, bottom: 8),
                      width: 48,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).dividerColor.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(2.5),
                      ),
                    ),
                  ),
                  // Header
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Shopping Cart',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        IconButton.filledTonal(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),

                  // Cart Items
                  Expanded(
                    child: StatefulBuilder(
                      builder: (context, setModalState) {
                        if (_cartItems.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.shopping_cart_outlined,
                                  size: 80,
                                  color: Theme.of(context).disabledColor,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Your cart is empty',
                                  style: Theme.of(context).textTheme.titleLarge
                                      ?.copyWith(
                                        color: Theme.of(context).disabledColor,
                                      ),
                                ),
                                const SizedBox(height: 8),
                                ElevatedButton.icon(
                                  onPressed: () => Navigator.of(context).pop(),
                                  icon: const Icon(Icons.arrow_back),
                                  label: const Text('Start Shopping'),
                                ),
                              ],
                            ),
                          );
                        }

                        return ListView.separated(
                          controller: scrollController,
                          padding: const EdgeInsets.all(16),
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 16),
                          itemCount: _cartItems.length,
                          itemBuilder: (context, index) {
                            final item = _cartItems[index];

                            final String? imageUrl = item['image'];
                            final String name = item['name'] ?? 'Unknown Item';
                            final double price =
                                (item['price'] as num?)?.toDouble() ?? 0.0;
                            final int qty = (item['qty'] as int?) ?? 1;
                            final int stock = (item['stock'] as int?) ?? 0;
                            final double totalItemPrice = price * qty;

                            return Container(
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.surface,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Theme.of(
                                    context,
                                  ).dividerColor.withValues(alpha: 0.5),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.03),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Product Image
                                  Container(
                                    width: 80,
                                    height: 80,
                                    decoration: BoxDecoration(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.surfaceContainerHighest,
                                      borderRadius: BorderRadius.circular(12),
                                      image:
                                          imageUrl != null &&
                                              imageUrl.isNotEmpty
                                          ? DecorationImage(
                                              image: CachedNetworkImageProvider(
                                                imageUrl,
                                              ),
                                              fit: BoxFit.cover,
                                            )
                                          : null,
                                    ),
                                    child: imageUrl == null || imageUrl.isEmpty
                                        ? Center(
                                            child: Icon(
                                              Icons.image,
                                              size: 32,
                                              color: Theme.of(
                                                context,
                                              ).disabledColor,
                                            ),
                                          )
                                        : null,
                                  ),
                                  const SizedBox(width: 16),

                                  // Details
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          name,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.bold,
                                              ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Unit Price: ₹${price.toStringAsFixed(2)}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall
                                                    ?.color
                                                    ?.withValues(alpha: 0.7),
                                              ),
                                        ),
                                        const SizedBox(height: 12),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              '₹${totalItemPrice.toStringAsFixed(2)}',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleMedium
                                                  ?.copyWith(
                                                    color: Theme.of(
                                                      context,
                                                    ).primaryColor,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                            ),
                                            // Qty Controls
                                            Container(
                                              decoration: BoxDecoration(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .surfaceContainerHighest,
                                                borderRadius:
                                                    BorderRadius.circular(24),
                                                border: Border.all(
                                                  color: Theme.of(context)
                                                      .dividerColor
                                                      .withValues(alpha: 0.3),
                                                ),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  IconButton(
                                                    icon: const Icon(
                                                      Icons.remove,
                                                      size: 18,
                                                    ),
                                                    constraints:
                                                        const BoxConstraints(
                                                          minWidth: 36,
                                                          minHeight: 36,
                                                        ),
                                                    padding: EdgeInsets.zero,
                                                    onPressed: () {
                                                      setModalState(() {
                                                        if (item['qty'] > 1) {
                                                          item['qty']--;
                                                        } else {
                                                          _cartItems.removeAt(
                                                            index,
                                                          );
                                                        }
                                                        _cartCount = _cartItems
                                                            .fold(
                                                              0,
                                                              (sum, it) =>
                                                                  sum +
                                                                  (it['qty']
                                                                      as int),
                                                            );
                                                      });
                                                      setState(() {});
                                                    },
                                                  ),
                                                  Text(
                                                    '$qty',
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: Theme.of(
                                                        context,
                                                      ).colorScheme.onSurface,
                                                    ),
                                                  ),
                                                  IconButton(
                                                    icon: const Icon(
                                                      Icons.add,
                                                      size: 18,
                                                    ),
                                                    constraints:
                                                        const BoxConstraints(
                                                          minWidth: 36,
                                                          minHeight: 36,
                                                        ),
                                                    padding: EdgeInsets.zero,
                                                    onPressed: qty < stock
                                                        ? () {
                                                            setModalState(() {
                                                              item['qty']++;
                                                              _cartCount =
                                                                  _cartItems.fold(
                                                                    0,
                                                                    (sum, it) =>
                                                                        sum +
                                                                        (it['qty']
                                                                            as int),
                                                                  );
                                                            });
                                                            setState(() {});
                                                          }
                                                        : null,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),

                  // Footer
                  if (_cartItems.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        border: Border(
                          top: BorderSide(
                            color: Theme.of(context).dividerColor,
                          ),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            offset: const Offset(0, -4),
                            blurRadius: 16,
                          ),
                        ],
                      ),
                      child: SafeArea(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Total Amount',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                Text(
                                  '₹${_calculateTotal().toStringAsFixed(2)}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                      ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: () {
                                  Navigator.of(context).pop();
                                  _proceedToCheckout(context);
                                },
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                ),
                                icon: const Icon(Icons.payment),
                                label: const Text(
                                  'Proceed to Checkout',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // Cash Option A: Do NOT record a new sale here. Ask for an existing Shop Sale ID,
  // fetch it with items, and generate a receipt from that data.
  Future<void> _openCashReceiptDialog(BuildContext context) async {
    final formKey = GlobalKey<FormState>();
    final saleIdCtl = TextEditingController();

    final result = await showDialog<int?>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Cash Receipt'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Enter Shop Sale ID to fetch and print receipt. No new sale will be recorded.',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: saleIdCtl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Shop Sale ID',
                    prefixIcon: Icon(Icons.receipt_long),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Sale ID is required';
                    }
                    final n = int.tryParse(v.trim());
                    if (n == null || n <= 0) {
                      return 'Enter a valid numeric Sale ID';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () {
                if (formKey.currentState?.validate() ?? false) {
                  final id = int.parse(saleIdCtl.text.trim());
                  Navigator.of(ctx).pop(id);
                }
              },
              icon: const Icon(Icons.search),
              label: const Text('Fetch Receipt'),
            ),
          ],
        );
      },
    );

    if (result == null) return; // cancelled

    // Show loading while fetching
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // Use the secure RPC for public shop lookup
      final sale = await SupabaseService.getShopReceipt(result);
      if (!mounted) return;
      Navigator.of(context).pop(); // close loading

      if (sale == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sale not found. Please verify the ID.'),
          ),
        );
        return;
      }

      // Build receipt from fetched sale (RPC returns 'items' array)
      final itemsRaw = List<Map<String, dynamic>>.from(
        (sale['items'] as List?)?.map(
              (e) => Map<String, dynamic>.from(e as Map),
            ) ??
            const [],
      );
      final items = <ReceiptItem>[];
      for (final it in itemsRaw) {
        // RPC structure: {product_name, quantity, price_per_unit, subtotal}
        final name = it['product_name'] as String?;
        final qty = (it['quantity'] as num?)?.toInt() ?? 0;
        final ppu = (it['price_per_unit'] as num?)?.toDouble() ?? 0.0;
        items.add(
          ReceiptItem(name: name ?? 'Item', quantity: qty, pricePerUnit: ppu),
        );
      }

      final double subTotal = items.fold(
        0.0,
        (s, it) => s + it.quantity * it.pricePerUnit,
      );
      final double totalAmount =
          (sale['total_amount'] as num?)?.toDouble() ?? subTotal;
      // Discount might not be in RPC or different key, check if needed
      // RPC returns fields matching sales table usually
      double discount = 0.0;
      // If RPC doesn't return discount explicitly, calc from totals
      if (sale.containsKey('discount')) {
        discount = (sale['discount'] as num?)?.toDouble() ?? 0.0;
      } else {
        discount = (subTotal - totalAmount);
      }
      if (discount < 0) discount = 0;

      final String saleIdStr = (sale['id']?.toString()) ?? 'N/A';
      final String custName =
          (sale['customer_name'] as String?)?.trim().isNotEmpty == true
          ? (sale['customer_name'] as String)
          : 'Walk-in Customer';
      final String? custPhone =
          (sale['customer_phone'] as String?)?.trim().isNotEmpty == true
          ? (sale['customer_phone'] as String?)
          : null;
      final String? txnId =
          (sale['transaction_id'] as String?)?.trim().isNotEmpty == true
          ? (sale['transaction_id'] as String?)
          : null;
      final String payMethod = (sale['payment_method'] as String?) ?? 'cash';
      DateTime saleDate;
      try {
        final createdAt = sale['created_at'] as String?;
        saleDate = createdAt != null
            ? DateTime.parse(createdAt).toLocal()
            : DateTime.now();
      } catch (_) {
        saleDate = DateTime.now();
      }

      final receipt = ReceiptData(
        saleId: saleIdStr,
        customerName: custName,
        customerPhone: custPhone,
        transactionId: txnId,
        items: items,
        subTotal: subTotal,
        discount: discount,
        finalTotal: totalAmount,
        paymentMethod: payMethod,
        saleDate: saleDate,
      );

      await ReceiptService.shareReceiptPdf(receipt);
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // close loading
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to fetch sale/receipt: $e')),
      );
    }
  }

  double _calculateTotal() {
    return _cartItems.fold(
      0.0,
      (sum, item) => sum + (item['price'] * item['qty']),
    );
  }

  // Computes the min and max selling price across all products
  List<double> _priceBounds() {
    double minP = double.infinity;
    double maxP = 0.0;
    for (final p in _products) {
      final pr = (p['price'] as num?)?.toDouble() ?? 0.0;
      if (pr < minP) minP = pr;
      if (pr > maxP) maxP = pr;
    }
    if (minP == double.infinity) minP = 0.0;
    if (maxP < minP) maxP = minP;
    return [minP, maxP];
  }

  Future<void> _proceedToCheckout(BuildContext context) async {
    if (!ConnectivityService().isOnline.value) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: const [
              Icon(Icons.wifi_off, color: Colors.white),
              SizedBox(width: 8),
              Text('You are offline. Cannot checkout.'),
            ],
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (_cartItems.isEmpty) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.9,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              child: Column(
                children: [
                  // Handle
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: 12, bottom: 8),
                      width: 48,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).dividerColor.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(2.5),
                      ),
                    ),
                  ),

                  // Header
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Checkout',
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              '${_cartItems.length} items',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                        IconButton.filledTonal(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),

                  // Scrollable Content
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.all(24),
                      children: [
                        Text(
                          'Order Summary',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 16),
                        // Order List
                        ..._cartItems.map((item) {
                          final double price = (item['price'] as num)
                              .toDouble();
                          final int qty = (item['qty'] as int);
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    '${item['qty']}x ${item['name']}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodyLarge,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text(
                                  '₹${(price * qty).toStringAsFixed(2)}',
                                  style: Theme.of(context).textTheme.bodyLarge
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          );
                        }),
                        const Divider(height: 32),

                        // Bill Details
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Total Amount',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              _currencyFormat.format(_calculateTotal()),
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: Colors.orange,
                                  ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 32),

                        Text(
                          'Payment Method',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 16),

                        // UPI Option
                        Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: Theme.of(context).dividerColor,
                            ),
                          ),
                          child: ListTile(
                            onTap: () {
                              Navigator.of(context).pop();
                              _initiateUPIPayment(context);
                            },
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                Icons.qr_code_scanner,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onPrimaryContainer,
                              ),
                            ),
                            title: const Text('Pay via UPI'),
                            subtitle: Text(
                              'Google Pay, PhonePe, Paytm, etc.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            trailing: const Icon(
                              Icons.arrow_forward_ios,
                              size: 16,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Cash Option
                        Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: Theme.of(context).dividerColor,
                            ),
                          ),
                          child: ListTile(
                            onTap: () {
                              Navigator.of(context).pop();
                              _openCashReceiptDialog(context);
                            },
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.secondaryContainer,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                Icons.money,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSecondaryContainer,
                              ),
                            ),
                            title: const Text('Cash Payment'),
                            subtitle: Text(
                              'Pay at counter / cash register',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            trailing: const Icon(
                              Icons.arrow_forward_ios,
                              size: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _initiateUPIPayment(BuildContext context) async {
    try {
      // Use app-managed static UPI VPA (no Supabase dependency)
      String upiId = 'pradeepsupergalaxy12@okicici';
      if (_businessProfile?.upiVpa != null &&
          _businessProfile!.upiVpa!.isNotEmpty) {
        upiId = _businessProfile!.upiVpa!;
      }
      String payeeName = _sanitizeUpiName(_businessName).trim();
      if (payeeName.isEmpty) payeeName = 'Merchant';
      if (payeeName.length > 20) {
        payeeName = payeeName.substring(0, 20);
      }
      final total = _calculateTotal();
      final checkoutId = 'RE-${DateTime.now().millisecondsSinceEpoch}';

      if (!_isValidUpiVpa(upiId)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Receiver UPI ID not set. Please try again later.'),
            ),
          );
        }
        return;
      }

      // Many UPI apps do not show a pay sheet for zero amount
      if (total <= 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Cart total must be greater than 0 to pay by UPI.'),
            ),
          );
        }
        return;
      }

      // Skip confirmation dialog; directly open UPI app
      // upiId and payeeName already set.

      // Keep tn short; some apps truncate silently
      String tn = 'Checkout ${checkoutId.substring(checkoutId.length - 6)}';
      if (tn.length > 40) tn = tn.substring(0, 40);

      final qp = [
        'pa=${Uri.encodeQueryComponent(upiId)}',
        'pn=${Uri.encodeQueryComponent(payeeName)}',
        'am=${Uri.encodeQueryComponent(total.toStringAsFixed(2))}',
        'cu=INR',
        'tr=${Uri.encodeQueryComponent(checkoutId)}',
        'tid=${Uri.encodeQueryComponent(checkoutId)}',
        'tn=${Uri.encodeQueryComponent(tn)}',
      ].join('&');

      final bool isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
      bool launched = false;
      if (isMobile) {
        launched = await _tryLaunchUri(Uri.parse('upi://pay?$qp'));
        if (!launched) {
          final intentUri = Uri.parse('intent://pay?$qp#Intent;scheme=upi;end');
          launched = await _tryLaunchUri(intentUri);
        }
        if (!launched && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No UPI app found to handle this payment.'),
            ),
          );
        }
      }
      if (mounted) {
        _showUpiConfirmationSheet(context, checkoutId, total);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Payment error: $e')));
      }
    }
  }

  void _showUpiConfirmationSheet(
    BuildContext context,
    String checkoutId,
    double total,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        bool showQr = !(Platform.isAndroid || Platform.isIOS);
        return StatefulBuilder(
          builder: (context, setSheetState) {
            const upiId = 'pradeepsupergalaxy12@okicici';
            String pn = _sanitizeUpiName(_businessName).trim();
            if (pn.isEmpty) pn = 'Merchant';
            if (pn.length > 20) pn = pn.substring(0, 20);
            String tn =
                'Checkout ${checkoutId.substring(checkoutId.length - 6)}';
            if (tn.length > 40) tn = tn.substring(0, 40);
            final qp = [
              'pa=${Uri.encodeQueryComponent(upiId)}',
              'pn=${Uri.encodeQueryComponent(pn)}',
              'am=${Uri.encodeQueryComponent(total.toStringAsFixed(2))}',
              'cu=INR',
              'tr=${Uri.encodeQueryComponent(checkoutId)}',
              'tid=${Uri.encodeQueryComponent(checkoutId)}',
              'tn=${Uri.encodeQueryComponent(tn)}',
            ].join('&');
            final upiUri = 'upi://pay?$qp';

            final mq = MediaQuery.of(ctx);
            double qrSize = 260;
            final double w = mq.size.width;
            final double h = mq.size.height;
            if (w < 360) {
              qrSize = 200;
            } else if (w < 480) {
              qrSize = 220;
            } else if (w < 768) {
              qrSize = 240;
            } else {
              qrSize = 280;
            }
            final double capByHeight = h * 0.35;
            if (qrSize > capByHeight) {
              qrSize = capByHeight;
            }
            final bool disableScroll = h >= 720;

            return SingleChildScrollView(
              physics: disableScroll
                  ? const NeverScrollableScrollPhysics()
                  : null,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.payments_outlined),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Complete Payment',
                            style: Theme.of(ctx).textTheme.titleMedium,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () =>
                              setSheetState(() => showQr = !showQr),
                          icon: const Icon(Icons.qr_code_2),
                          label: Text(showQr ? 'Hide QR' : 'Show QR'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Amount: ₹${total.toStringAsFixed(2)}  •  Receiver: $_businessName',
                      style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(
                          ctx,
                        ).textTheme.bodySmall?.color?.withValues(alpha: 0.8),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (showQr) ...[
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              ctx,
                            ).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Theme.of(
                                ctx,
                              ).dividerColor.withValues(alpha: 0.2),
                            ),
                          ),
                          child: QrImageView(
                            data: upiUri,
                            version: QrVersions.auto,
                            size: qrSize,
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: SelectableText(
                          upiId,
                          style: Theme.of(ctx).textTheme.bodySmall,
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    Text(
                      'Pay via UPI app or scan QR from another phone, then upload the payment screenshot for verification.',
                      style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                        color: Theme.of(
                          ctx,
                        ).textTheme.bodySmall?.color?.withValues(alpha: 0.9),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => Navigator.of(ctx).pop(),
                            icon: const Icon(Icons.close),
                            label: const Text('Close'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () async {
                              final file = await _pickPaymentScreenshot();
                              if (file == null) return;
                              if (mounted) Navigator.of(ctx).pop();
                              await _completeCartSaleWithProof(
                                context,
                                checkoutId,
                                total,
                                file,
                              );
                            },
                            icon: const Icon(Icons.upload_file),
                            label: const Text('Upload Payment Screenshot'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: TextButton.icon(
                        onPressed: () async {
                          // Allow user to open another UPI app
                          bool launched = await _tryLaunchUri(
                            Uri.parse(upiUri),
                          );
                          if (!launched) {
                            final intentUri = Uri.parse(
                              'intent://pay?$qp#Intent;scheme=upi;end',
                            );
                            await _tryLaunchUri(intentUri);
                          }
                        },
                        icon: const Icon(Icons.open_in_new),
                        label: const Text('Open in another UPI app'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<File?> _pickPaymentScreenshot() async {
    try {
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        final ImagePicker picker = ImagePicker();
        final XFile? shot = await picker.pickImage(source: ImageSource.gallery);
        if (shot == null) return null;
        return File(shot.path);
      } else {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.image,
          allowMultiple: false,
          withData: false,
        );
        if (result == null || result.files.isEmpty) return null;
        final path = result.files.single.path;
        if (path == null) return null;
        return File(path);
      }
    } catch (_) {
      return null;
    }
  }

  Future<String?> _uploadPaymentProof(File file, String checkoutId) async {
    try {
      final bytes = await file.readAsBytes();
      final ext = file.path.split('.').last.toLowerCase();
      final name =
          'payment_proofs/${checkoutId}_${DateTime.now().millisecondsSinceEpoch}.$ext';
      await Supabase.instance.client.storage
          .from('payment-proofs')
          .uploadBinary(
            name,
            bytes,
            fileOptions: const FileOptions(
              upsert: true,
              contentType: 'image/jpeg',
            ),
          );
      final publicUrl = Supabase.instance.client.storage
          .from('payment-proofs')
          .getPublicUrl(name);
      return publicUrl;
    } catch (_) {
      return null;
    }
  }

  Future<void> _completeCartSaleWithProof(
    BuildContext context,
    String checkoutId,
    double total,
    File proof,
  ) async {
    // Capture state objects before async gap
    final navigator = Navigator.of(context);
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final items = _cartItems
          .map(
            (e) => {
              'product_id': e['id'],
              'quantity': e['qty'],
              'price_per_unit': (e['price'] as num).toDouble(),
            },
          )
          .toList();

      // Upload proof first (best-effort)
      final proofUrl = await _uploadPaymentProof(proof, checkoutId);

      final saleId = await SupabaseService.createSaleWithItems(
        customerName: 'Walk-in Customer',
        paymentMethod: 'upi',
        totalAmount: total,
        transactionId: checkoutId,
        amountPaid: total,
        status: 'pending',
        paymentProofUrl: proofUrl,
        items: items,
      );

      if (saleId != null) {
        // Build receipt items
        final receiptItems = _cartItems
            .map(
              (e) => ReceiptItem(
                name: e['name'] ?? 'Item',
                quantity: e['qty'] as int,
                pricePerUnit: (e['price'] as num).toDouble(),
              ),
            )
            .toList();

        final receipt = ReceiptData(
          saleId: saleId.toString(),
          customerName: 'Walk-in Customer',
          customerPhone: null,
          items: receiptItems,
          subTotal: total,
          discount: 0,
          finalTotal: total,
          paymentMethod: 'upi',
          saleDate: DateTime.now(),
          status: 'pending',
        );

        // Share receipt (might take time/switch apps)
        await ReceiptService.shareReceiptPdf(receipt);

        if (mounted) {
          setState(() {
            _cartItems.clear();
            _cartCount = 0;
          });
        }

        navigator.pop(); // Pop loading dialog
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(
              'Payment submitted for verification. Sale ID: $saleId',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      } else {
        navigator.pop(); // Pop loading dialog
        scaffoldMessenger.showSnackBar(
          const SnackBar(
            content: Text('Failed to record sale.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      navigator.pop(); // Pop loading dialog
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('Failed to record sale: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _completeBuyNowSaleWithProof(
    BuildContext context,
    String checkoutId,
    double total,
    Map<String, dynamic> product,
    int qty,
    File proof,
  ) async {
    // Capture state to safely use across async gaps
    final navigator = Navigator.of(context);
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // Upload proof first (best-effort)
      final proofUrl = await _uploadPaymentProof(proof, checkoutId);

      final double price = (product['price'] as num?)?.toDouble() ?? 0.0;
      final items = [
        {'product_id': product['id'], 'quantity': qty, 'price_per_unit': price},
      ];

      final saleId = await SupabaseService.createSaleWithItems(
        customerName: 'Walk-in Customer',
        paymentMethod: 'upi',
        totalAmount: total,
        transactionId: checkoutId,
        amountPaid: total,
        status: 'pending',
        paymentProofUrl: proofUrl,
        items: items,
      );

      if (saleId != null) {
        final receipt = ReceiptData(
          saleId: saleId.toString(),
          customerName: 'Walk-in Customer',
          customerPhone: null,
          items: [
            ReceiptItem(
              name: product['name'] ?? 'Item',
              quantity: qty,
              pricePerUnit: price,
            ),
          ],
          subTotal: total,
          discount: 0,
          finalTotal: total,
          paymentMethod: 'upi',
          saleDate: DateTime.now(),
          status: 'pending',
        );

        // Share receipt
        await ReceiptService.shareReceiptPdf(receipt);

        navigator.pop(); // Pop dialog
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(
              'Payment submitted for verification. Sale ID: $saleId',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      } else {
        navigator.pop();
        scaffoldMessenger.showSnackBar(
          const SnackBar(
            content: Text('Failed to record sale.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      navigator.pop();
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('Failed to record sale: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _updateCart(Map<String, dynamic> product, int newQty) {
    if (newQty < 0) return;
    final existingIndex = _cartItems.indexWhere(
      (item) => item['id'] == product['id'],
    );

    setState(() {
      if (existingIndex >= 0) {
        if (newQty == 0) {
          _cartItems.removeAt(existingIndex);
        } else {
          _cartItems[existingIndex]['qty'] = newQty;
        }
      } else if (newQty > 0) {
        _cartItems.add({
          'id': product['id'],
          'name': product['name'],
          'price': product['price'],
          'qty': newQty,
          'stock': product['stock'],
        });
      }
      _cartCount = _cartItems.fold(
        0,
        (sum, item) => sum + (item['qty'] as int),
      );
    });
  }

  void _addToCart(
    BuildContext context,
    Map<String, dynamic> product, {
    int qty = 1,
  }) {
    final existingIndex = _cartItems.indexWhere(
      (item) => item['id'] == product['id'],
    );

    if (existingIndex >= 0) {
      setState(() {
        _cartItems[existingIndex]['qty'] += qty;
      });
    } else {
      setState(() {
        _cartItems.add({
          'id': product['id'],
          'name': product['name'],
          'price': product['price'],
          'qty': qty,
          'stock': product['stock'],
          'image': product['image'],
        });
      });
    }

    setState(() {
      _cartCount = _cartItems.fold(
        0,
        (sum, item) => sum + (item['qty'] as int),
      );
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${product['name']} added to cart${qty > 1 ? ' (x$qty)' : ''}',
        ),
      ),
    );
  }

  Widget _buildFilterBar(BuildContext context, BoxConstraints constraints) {
    final isMobile = constraints.maxWidth <= 480;
    final filtersExpanded = _filtersExpanded;

    return Container(
      key: _filterBarKey,
      padding: const EdgeInsets.all(24),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isMobile) ...[
              // Compact title + count on mobile
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'All Products',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    '${_filteredProducts.length}',
                    style: TextStyle(
                      color: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],

            // Category (mobile-only; desktop Category lives in pinned header)
            if (isMobile)
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedCategory,
                      items: _categories
                          .map(
                            (c) => DropdownMenuItem(
                              value: c,
                              child: Text(c[0].toUpperCase() + c.substring(1)),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() {
                        _selectedCategory = v ?? 'all';
                        _scrollToProducts();
                      }),
                      decoration: InputDecoration(
                        labelText: 'Category',
                        filled: true,
                        fillColor: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withValues(alpha: 0.4),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(UITokens.radius),
                          borderSide: BorderSide(
                            color: Theme.of(
                              context,
                            ).dividerColor.withValues(alpha: 0.2),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 12),

            // Collapsible toggle (mobile)
            if (isMobile)
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: () =>
                      setState(() => _filtersExpanded = !_filtersExpanded),
                  icon: Icon(
                    _filtersExpanded ? Icons.expand_less : Icons.expand_more,
                  ),
                  label: Text(
                    _filtersExpanded ? 'Hide Filters' : 'Show Filters',
                  ),
                ),
              ),

            if (filtersExpanded)
              // Brand, Spec, Color
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: isMobile ? double.infinity : 220,
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedBrand,
                      items: _brands
                          .map(
                            (b) => DropdownMenuItem(
                              value: b,
                              child: Text(b[0].toUpperCase() + b.substring(1)),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() {
                        _selectedBrand = v ?? 'all';
                        _selectedBrands.clear();
                        _scrollToProducts();
                      }),
                      decoration: InputDecoration(
                        labelText: 'Brand',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(UITokens.radius),
                        ),
                        isDense: true,
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 40,
                    child: OutlinedButton.icon(
                      onPressed: () => _showMultiSelectBottomSheet(
                        context,
                        title: 'Select Brands',
                        options: _brands,
                        targetSet: _selectedBrands,
                      ),
                      icon: const Icon(Icons.checklist),
                      label: const Text('Multi'),
                    ),
                  ),
                  SizedBox(
                    width: isMobile ? double.infinity : 220,
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedSpec,
                      items: _specs
                          .map(
                            (s) => DropdownMenuItem(
                              value: s,
                              child: Text(s[0].toUpperCase() + s.substring(1)),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() {
                        _selectedSpec = v ?? 'all';
                        _selectedSpecs.clear();
                        _scrollToProducts();
                      }),
                      decoration: InputDecoration(
                        labelText: 'Spec (Amp/sqmm)',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(UITokens.radius),
                        ),
                        isDense: true,
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 40,
                    child: OutlinedButton.icon(
                      onPressed: () => _showMultiSelectBottomSheet(
                        context,
                        title: 'Select Specs',
                        options: _specs,
                        targetSet: _selectedSpecs,
                      ),
                      icon: const Icon(Icons.checklist),
                      label: const Text('Multi'),
                    ),
                  ),
                  SizedBox(
                    width: isMobile ? double.infinity : 220,
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedColor,
                      items: _colors
                          .map(
                            (c) => DropdownMenuItem(
                              value: c,
                              child: Text(c[0].toUpperCase() + c.substring(1)),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() {
                        _selectedColor = v ?? 'all';
                        _selectedColors.clear();
                        _scrollToProducts();
                      }),
                      decoration: InputDecoration(
                        labelText: 'Color',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(UITokens.radius),
                        ),
                        isDense: true,
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 40,
                    child: OutlinedButton.icon(
                      onPressed: () => _showMultiSelectBottomSheet(
                        context,
                        title: 'Select Colors',
                        options: _colors,
                        targetSet: _selectedColors,
                      ),
                      icon: const Icon(Icons.checklist),
                      label: const Text('Multi'),
                    ),
                  ),
                ],
              ),
            if (filtersExpanded) const SizedBox(height: 12),

            if (filtersExpanded)
              // Price range and Sort
              Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: isMobile
                        ? (MediaQuery.of(context).size.width - 64) / 2
                        : 160,
                    child: TextField(
                      controller: _minPriceCtl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Min Price',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (_) => setState(() {
                        _scrollToProducts();
                      }),
                    ),
                  ),
                  SizedBox(
                    width: isMobile
                        ? (MediaQuery.of(context).size.width - 64) / 2
                        : 160,
                    child: TextField(
                      controller: _maxPriceCtl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Max Price',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (_) => setState(() {
                        _scrollToProducts();
                      }),
                    ),
                  ),
                  SizedBox(
                    width: isMobile ? double.infinity : 220,
                    child: DropdownButtonFormField<String>(
                      initialValue: _sortOption,
                      items: _sortOptions
                          .map(
                            (s) => DropdownMenuItem(value: s, child: Text(s)),
                          )
                          .toList(),
                      onChanged: (v) => setState(() {
                        _sortOption = v ?? 'Relevance';
                        _scrollToProducts();
                      }),
                      decoration: const InputDecoration(
                        labelText: 'Sort',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _selectedCategory = 'all';
                        _selectedBrand = 'all';
                        _selectedSpec = 'all';
                        _selectedColor = 'all';
                        _selectedBrands.clear();
                        _selectedSpecs.clear();
                        _selectedColors.clear();
                        _minPriceCtl.clear();
                        _maxPriceCtl.clear();
                        final b = _priceBounds();
                        final start = b[0];
                        final end = b[1] > b[0] ? b[1] : b[0] + 1.0;
                        _priceRange = RangeValues(start, end);
                        _sortOption = 'Relevance';
                        _scrollToProducts();
                      });
                    },
                    icon: const Icon(Icons.clear),
                    label: const Text('Clear All'),
                  ),
                ],
              ),

            if (filtersExpanded) const SizedBox(height: 12),

            // Price Range Slider (synced with text inputs)
            if (filtersExpanded)
              Builder(
                builder: (context) {
                  if (_products.isEmpty) return const SizedBox.shrink();
                  final bounds = _priceBounds();
                  final minBound = bounds[0];
                  final maxBound = bounds[1] > bounds[0]
                      ? bounds[1]
                      : bounds[0] + 1.0;
                  double currentMin =
                      double.tryParse(_minPriceCtl.text.trim()) ??
                      (_priceRange?.start ?? minBound);
                  double currentMax =
                      double.tryParse(_maxPriceCtl.text.trim()) ??
                      (_priceRange?.end ?? maxBound);
                  if (currentMin.isNaN || currentMin < minBound) {
                    currentMin = minBound;
                  }
                  if (currentMax.isNaN || currentMax > maxBound) {
                    currentMax = maxBound;
                  }
                  if (currentMin > currentMax) {
                    final tmp = currentMin;
                    currentMin = currentMax;
                    currentMax = tmp;
                  }
                  final rv = RangeValues(currentMin, currentMax);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Price Range',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            '${_currencyFormat.format(rv.start)} - ${_currencyFormat.format(rv.end)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                      RangeSlider(
                        values: rv,
                        min: minBound,
                        max: maxBound,
                        onChanged: (val) {
                          setState(() {
                            _priceRange = val;
                            _minPriceCtl.text = val.start.toStringAsFixed(0);
                            _maxPriceCtl.text = val.end.toStringAsFixed(0);
                          });
                        },
                      ),
                    ],
                  );
                },
              ),

            // Active Filters Chips
            Builder(
              builder: (context) {
                final List<Widget> chips = [];
                if (_selectedCategory != 'all') {
                  chips.add(
                    Chip(
                      label: Text('Category: $_selectedCategory'),
                      onDeleted: () => setState(() {
                        _selectedCategory = 'all';
                        _scrollToProducts();
                      }),
                      visualDensity: VisualDensity.compact,
                    ),
                  );
                }
                // Multi-select brand chips
                if (_selectedBrands.isNotEmpty) {
                  for (final b in _selectedBrands.toList()) {
                    chips.add(
                      Chip(
                        label: Text('Brand: $b'),
                        onDeleted: () => setState(() {
                          _selectedBrands.remove(b);
                          _scrollToProducts();
                        }),
                        visualDensity: VisualDensity.compact,
                      ),
                    );
                  }
                } else if (_selectedBrand != 'all') {
                  chips.add(
                    Chip(
                      label: Text('Brand: $_selectedBrand'),
                      onDeleted: () => setState(() {
                        _selectedBrand = 'all';
                        _scrollToProducts();
                      }),
                      visualDensity: VisualDensity.compact,
                    ),
                  );
                }
                if (_selectedSpecs.isNotEmpty) {
                  for (final s in _selectedSpecs.toList()) {
                    chips.add(
                      Chip(
                        label: Text('Spec: $s'),
                        onDeleted: () => setState(() {
                          _selectedSpecs.remove(s);
                          _scrollToProducts();
                        }),
                        visualDensity: VisualDensity.compact,
                      ),
                    );
                  }
                } else if (_selectedSpec != 'all') {
                  chips.add(
                    Chip(
                      label: Text('Spec: $_selectedSpec'),
                      onDeleted: () => setState(() {
                        _selectedSpec = 'all';
                        _scrollToProducts();
                      }),
                      visualDensity: VisualDensity.compact,
                    ),
                  );
                }
                if (_selectedColors.isNotEmpty) {
                  for (final c in _selectedColors.toList()) {
                    chips.add(
                      Chip(
                        label: Text('Color: $c'),
                        onDeleted: () => setState(() {
                          _selectedColors.remove(c);
                          _scrollToProducts();
                        }),
                        visualDensity: VisualDensity.compact,
                      ),
                    );
                  }
                } else if (_selectedColor != 'all') {
                  chips.add(
                    Chip(
                      label: Text('Color: $_selectedColor'),
                      onDeleted: () => setState(() {
                        _selectedColor = 'all';
                        _scrollToProducts();
                      }),
                      visualDensity: VisualDensity.compact,
                    ),
                  );
                }
                final hasMin =
                    double.tryParse(_minPriceCtl.text.trim()) != null;
                final hasMax =
                    double.tryParse(_maxPriceCtl.text.trim()) != null;
                if (hasMin) {
                  chips.add(
                    Chip(
                      label: Text('Min: ${_minPriceCtl.text}'),
                      onDeleted: () => setState(() {
                        _minPriceCtl.clear();
                        _scrollToProducts();
                      }),
                      visualDensity: VisualDensity.compact,
                    ),
                  );
                }
                if (hasMax) {
                  chips.add(
                    Chip(
                      label: Text('Max: ${_maxPriceCtl.text}'),
                      onDeleted: () => setState(() {
                        _maxPriceCtl.clear();
                        _scrollToProducts();
                      }),
                      visualDensity: VisualDensity.compact,
                    ),
                  );
                }

                if (chips.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    Text(
                      'Active Filters',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(spacing: 8, runSpacing: 8, children: chips),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductsSection(
    BuildContext context,
    BoxConstraints constraints,
  ) {
    if (_loadErrorMessage != null) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.wifi_off,
                  size: 48,
                  color: Theme.of(context).disabledColor,
                ),
                const SizedBox(height: 12),
                const Text('Failed to load products'),
                const SizedBox(height: 8),
                Text(
                  _loadErrorMessage!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_isLoadingProducts) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: SizedBox(
              height: 28,
              width: 28,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
          ),
        ),
      );
    }

    if (_filteredProducts.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.inbox_outlined,
                  size: 48,
                  color: Theme.of(context).disabledColor,
                ),
                const SizedBox(height: 12),
                const Text('No products found'),
              ],
            ),
          ),
        ),
      );
    }

    if (_isGridView) {
      final double maxW = constraints.maxWidth;
      const double horizontalPadding = 32; // SliverPadding left+right
      const double crossSpacing = 14; // grid crossAxisSpacing

      // Adaptive count based on desired minimum tile width (~300px on desktop)
      int crossAxisCount = (maxW / 300).floor();
      if (crossAxisCount < 1) crossAxisCount = 1;
      if (crossAxisCount > 6) crossAxisCount = 6;

      // Compute effective tile width after padding and spacing
      final double tileWidth =
          (maxW - horizontalPadding - crossSpacing * (crossAxisCount - 1)) /
          crossAxisCount;

      // Derive aspect ratio (w/h). Smaller widths need taller cards to avoid overflow.
      double childAspectRatio;
      if (tileWidth < 240) {
        childAspectRatio = 0.66;
      } else if (tileWidth < 280) {
        childAspectRatio = 0.69;
      } else if (tileWidth < 340) {
        childAspectRatio = 0.74;
      } else if (tileWidth < 420) {
        childAspectRatio = 0.80;
      } else {
        childAspectRatio = 0.85;
      }
      return SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            childAspectRatio: childAspectRatio,
          ),
          delegate: SliverChildBuilderDelegate((context, index) {
            final p = _filteredProducts[index];
            return _buildProductCard(context, p);
          }, childCount: _filteredProducts.length),
        ),
      );
    } else {
      return SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          final p = _filteredProducts[index];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: KeyedSubtree(
              key: ValueKey(p['id']),
              child: _buildProductListItem(context, p),
            ),
          );
        }, childCount: _filteredProducts.length),
      );
    }
  }

  Color _stringToColor(String text) {
    if (text.isEmpty) return Colors.grey;
    final lower = text.trim().toLowerCase();

    // Explicit color mapping
    switch (lower) {
      case 'white':
        return const Color(0xFFF5F5F5); // Slightly off-white for visibility
      case 'black':
        return Colors.black;
      case 'red':
        return const Color(0xFFE63946);
      case 'blue':
        return const Color(0xFF1982C4);
      case 'green':
        return const Color(0xFF8AC926);
      case 'yellow':
        return const Color(0xFFFFCA3A);
      case 'orange':
        return const Color(0xFFF4A261);
      case 'brown':
        return const Color(0xFF8D6E63);
      case 'grey':
      case 'gray':
        return Colors.grey;
      case 'silver':
        return const Color(0xFFC0C0C0);
      case 'gold':
        return const Color(0xFFFFD700);
      case 'pink':
        return const Color(0xFFFF595E);
      case 'purple':
        return const Color(0xFF6A4C93);
      case 'transparent':
      case 'clear':
        return Colors.white; // Represent clear as white with border usually
      case 'beige':
        return const Color(0xFFF5F5DC);
      case 'cream':
        return const Color(0xFFFFFDD0);
      case 'ivory':
        return const Color(0xFFFFFFF0);
      case 'multicolor':
        // Return a distinct color or we could try a gradient shader if possible,
        // but for a solid color return something recognizable
        return Colors.teal;
      case 'standard':
      case 'default':
        return Colors.grey.shade400; // Neutral
      case 'warm white':
      case 'warm':
        return const Color(0xFFFDF4DC); // Warm/Yellowish
      case 'cool white':
      case 'cool':
      case 'daylight':
      case 'day light':
        return const Color(0xFFF0F8FF); // Cool/Blueish
    }

    final int hash = text.codeUnits.fold(0, (prev, c) => prev + c);
    final List<Color> palette = [
      const Color(0xFFE63946), // Red
      const Color(0xFFF4A261), // Orange
      const Color(0xFF2A9D8F), // Teal
      const Color(0xFF264653), // Dark Blue
      const Color(0xFF457B9D), // Blue
      const Color(0xFF1D3557), // Navy
      const Color(0xFF6A4C93), // Purple
      const Color(0xFF8AC926), // Green
      const Color(0xFFFF595E), // Pink
      const Color(0xFF1982C4), // Bright Blue
    ];
    return palette[hash % palette.length];
  }

  Widget _buildProductCard(BuildContext context, Map<String, dynamic> product) {
    final isOutOfStock = product['stock'] == 0;
    final isWishlisted = _wishlist.contains(product['id']);
    final isLowStock = !isOutOfStock && (product['stock'] as int? ?? 0) <= 5;
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final cartItem = _cartItems.firstWhere(
      (item) => item['id'] == product['id'],
      orElse: () => {'qty': 0},
    );
    final quantityInCart = cartItem['qty'] as int;

    return Card(
      color: cs.surface,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outline.withValues(alpha: 0.08)),
      ),
      child: InkWell(
        onTap: () => _viewProduct(context, product),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Image Section with subtle gradient overlay
            Expanded(
              flex: 4, // More space for image
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    color: Colors
                        .white, // reliable background for product standard images
                    child: Hero(
                      tag: 'pimg-${product['id']}',
                      child: CachedNetworkImage(
                        imageUrl: product['image'] ?? '',
                        fit: BoxFit
                            .contain, // Contain usually looks better for products
                        placeholder: (c, _) => Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        errorWidget: (c, _, __) => Icon(
                          Icons.broken_image_outlined,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),

                  // Subtle gradient at bottom for text contrast if needed?
                  // kept minimal as we have text below image now.
                  if (isOutOfStock)
                    Container(
                      color: Colors.black54,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: cs.error,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Sold Out',
                            style: TextStyle(
                              color: cs.onError,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ),

                  // Wishlist Button - Top Right
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Material(
                      color: Colors.white.withValues(alpha: 0.9),
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => _toggleWishlist(product['id']),
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Icon(
                            isWishlisted
                                ? Icons.favorite
                                : Icons.favorite_border,
                            size: 18,
                            color: isWishlisted ? Colors.red : Colors.grey,
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Low Stock Badge - Top Left
                  if (isLowStock && !isOutOfStock)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.orange,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${product['stock']} left',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Details Section
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Brand/Category
                  Text(
                    [
                          product['brand'] as String?,
                          product['category'] as String?,
                        ]
                        .where((s) => s != null && s.isNotEmpty)
                        .join(' • ')
                        .toUpperCase(),
                    style: textTheme.labelSmall?.copyWith(
                      color: cs.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                      letterSpacing: 0.5,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  // Product Name
                  Text(
                    product['name'] ?? 'Unknown Item',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Price & Action
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _currencyFormat.format(product['price'] ?? 0),
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: cs.onSurface,
                        ),
                      ),

                      // Add Button
                      if (!isOutOfStock)
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: quantityInCart > 0
                              ? Container(
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: cs.primaryContainer,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                  child: Row(
                                    children: [
                                      IconButton(
                                        icon: Icon(
                                          Icons.remove,
                                          size: 16,
                                          color: cs.onPrimaryContainer,
                                        ),
                                        onPressed: () => _updateCart(
                                          product,
                                          quantityInCart - 1,
                                        ),
                                        padding: EdgeInsets.zero,
                                        constraints: BoxConstraints(
                                          minWidth: 24,
                                          minHeight: 24,
                                        ),
                                      ),
                                      Text(
                                        '$quantityInCart',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          color: cs.onPrimaryContainer,
                                        ),
                                      ),
                                      IconButton(
                                        icon: Icon(
                                          Icons.add,
                                          size: 16,
                                          color: cs.onPrimaryContainer,
                                        ),
                                        onPressed: () => _updateCart(
                                          product,
                                          quantityInCart + 1,
                                        ),
                                        padding: EdgeInsets.zero,
                                        constraints: BoxConstraints(
                                          minWidth: 24,
                                          minHeight: 24,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : SizedBox(
                                  height: 36,
                                  child: FilledButton(
                                    onPressed: () =>
                                        _addToCart(context, product),
                                    style: FilledButton.styleFrom(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 16,
                                      ),
                                      visualDensity: VisualDensity.compact,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    child: const Text(
                                      'Add',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  ),
                                ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _toggleWishlist(int productId) {
    setState(() {
      if (_wishlist.contains(productId)) {
        _wishlist.remove(productId);
      } else {
        _wishlist.add(productId);
      }
    });
  }

  Future<void> _shareProduct(Map<String, dynamic> product) async {
    final id = product['id'];
    final name = product['name'];
    final price = (product['price'] as num?)?.toDouble() ?? 0.0;
    final url = 'https://rajelectricals.com/shop?product=$id';
    await Share.share(
      'Check out $name for ${_currencyFormat.format(price)} on Raj Electricals!\n$url',
      subject: 'Check out $name',
    );
  }

  void _viewProduct(BuildContext context, Map<String, dynamic> product) {
    if (!_recentlyViewed.contains(product['id'])) {
      setState(() {
        _recentlyViewed.add(product['id']);
        if (_recentlyViewed.length > 10) {
          _recentlyViewed.removeAt(0);
        }
      });
    }

    // Redesigned product detail as a modern bottom sheet
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final cartItem = _cartItems.firstWhere(
          (item) => item['id'] == product['id'],
          orElse: () => {'qty': 0},
        );
        int qty = (cartItem['qty'] as int) > 0 ? (cartItem['qty'] as int) : 1;

        final int stoRck = (product['stock'] as int?) ?? 0;
        final String desc = (product['description'] as String?)?.trim() ?? '';
        final specs = _parseSpecs(desc);

        final PageController pageController = PageController();
        int currentImage = 0;

        // Clone initial product to local state for switching variants
        Map<String, dynamic> currentProduct = Map<String, dynamic>.from(
          product,
        );

        return StatefulBuilder(
          builder: (context, setSheetState) {
            // Re-bind current product data
            final int pId = currentProduct['id'];
            final int stock = (currentProduct['stock'] as int?) ?? 0;
            final double price =
                (currentProduct['price'] as num?)?.toDouble() ?? 0.0;
            final String name = currentProduct['name'] ?? 'Product';
            final String desc =
                (currentProduct['description'] as String?)?.trim() ?? '';
            final specs = _parseSpecs(desc);
            final List<dynamic> variants =
                (currentProduct['variants'] as List<dynamic>?) ?? [];

            final List<String> images = [];
            final Set<String> uniqueImages = {};

            // Helper to add unique images
            void addImages(List<String> newImages) {
              for (var img in newImages) {
                if (img.isNotEmpty && !uniqueImages.contains(img)) {
                  uniqueImages.add(img);
                  images.add(img);
                }
              }
            }

            // Initial population
            if (currentProduct['image'] != null &&
                (currentProduct['image'] as String).isNotEmpty) {
              addImages([currentProduct['image'] as String]);
            }
            if (currentProduct['images'] != null &&
                (currentProduct['images'] as List).isNotEmpty) {
              addImages(
                (currentProduct['images'] as List)
                    .map((e) => e.toString())
                    .toList(),
              );
            }

            // Function to switch variant
            void switchVariant(int variantId) async {
              Map<String, dynamic>? newP = _products.firstWhere(
                (p) => p['id'] == variantId,
                orElse: () => <String, dynamic>{},
              );

              // If empty (not in list), fetch from server
              if (newP.isEmpty) {
                newP = await SupabaseService.getShopProductById(variantId);
              }

              if (newP != null && newP.isNotEmpty) {
                setSheetState(() {
                  // Preserve variants so chips don't disappear
                  final variants = currentProduct['variants'];
                  newP!['variants'] = variants;

                  // Preserve detected color logic if needed
                  if (variants != null) {
                    // Safer finding logic to avoid cast errors
                    final matches = (variants as List).where(
                      (x) => x['id'] == variantId,
                    );
                    if (matches.isNotEmpty) {
                      newP['detected_color'] = matches.first['color'];
                    }
                  }

                  currentProduct = Map<String, dynamic>.from(newP);
                  currentImage = 0; // Reset image carousel
                });
              }
            }

            return SafeArea(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.9,
                ),
                child: Stack(
                  children: [
                    SingleChildScrollView(
                      padding: EdgeInsets.only(
                        left: 16,
                        right: 16,
                        top: 16,
                        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Image carousel
                          if (images.isNotEmpty) ...[
                            SizedBox(
                              height: 220,
                              child: GestureDetector(
                                onTap: () => _openImageGallery(
                                  context,
                                  images,
                                  currentImage,
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: PageView.builder(
                                    controller: pageController,
                                    itemCount: images.length,
                                    onPageChanged: (i) => setSheetState(() {
                                      currentImage = i;
                                    }),
                                    itemBuilder: (context, index) {
                                      final url = images[index];
                                      return Container(
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          border: Border.all(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .outline
                                                .withValues(alpha: 0.1),
                                          ),
                                        ),
                                        child: Image.network(
                                          url,
                                          headers: const {
                                            'User-Agent':
                                                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                                          },
                                          fit: BoxFit.contain,
                                          errorBuilder: (_, __, ___) => Center(
                                            child: Icon(
                                              Icons.image_not_supported,
                                              size: 32,
                                              color: Colors.grey.withValues(
                                                alpha: 0.4,
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            if (images.length > 1)
                              Center(
                                child: Wrap(
                                  spacing: 6,
                                  children: [
                                    for (int i = 0; i < images.length; i++)
                                      Container(
                                        width: 8,
                                        height: 8,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: i == currentImage
                                              ? Theme.of(
                                                  context,
                                                ).colorScheme.primary
                                              : Theme.of(context).dividerColor
                                                    .withValues(alpha: 0.5),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            const SizedBox(height: 12),
                          ] else ...[
                            Container(
                              height: 280,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.outline.withValues(alpha: 0.1),
                                ),
                              ),
                              child: Center(
                                child: Icon(
                                  Icons.image,
                                  size: 64,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant
                                      .withValues(alpha: 0.4),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],

                          // Title, price & stock
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  name,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        height: 1.2,
                                      ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Text(
                                _currencyFormat.format(price),
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: (stock > 0 ? Colors.green : Colors.red)
                                      .withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  stock > 0
                                      ? 'In stock: $stock'
                                      : 'Out of stock',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: stock > 0
                                        ? Colors.green
                                        : Colors.red,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const SizedBox(height: 8),
                          // Variant Selector
                          if (variants.length > 1) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Available Colors',
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: Theme.of(context).disabledColor,
                                  ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: [
                                for (final v in variants)
                                  InkWell(
                                    onTap: () => switchVariant(v['id'] as int),
                                    borderRadius: BorderRadius.circular(24),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                          color: (v['id'] == pId)
                                              ? Theme.of(context).primaryColor
                                              : Colors.transparent,
                                          width: 2,
                                        ),
                                        borderRadius: BorderRadius.circular(24),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                            width: 24,
                                            height: 24,
                                            decoration: BoxDecoration(
                                              color: _stringToColor(v['color']),
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: Colors.grey.withValues(
                                                  alpha: 0.3,
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            v['color'],
                                            style: TextStyle(
                                              fontWeight: (v['id'] == pId)
                                                  ? FontWeight.bold
                                                  : FontWeight.normal,
                                              fontSize: 13,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),
                          ],

                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              if ((currentProduct['brand'] as String?)
                                      ?.isNotEmpty ==
                                  true)
                                Builder(
                                  builder: (context) {
                                    final color = _stringToColor(
                                      currentProduct['brand'] as String,
                                    );
                                    return Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: color.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: color.withValues(alpha: 0.2),
                                        ),
                                      ),
                                      child: Text(
                                        (currentProduct['brand'] as String)
                                            .toUpperCase(),
                                        style: TextStyle(
                                          color: color,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              if ((currentProduct['category'] as String?)
                                      ?.isNotEmpty ==
                                  true)
                                Builder(
                                  builder: (context) {
                                    final color = _stringToColor(
                                      currentProduct['category'] as String,
                                    );
                                    return Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: color.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: color.withValues(alpha: 0.2),
                                        ),
                                      ),
                                      child: Text(
                                        currentProduct['category'] as String,
                                        style: TextStyle(
                                          color: color,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          if (specs.isNotEmpty) ...[
                            Text(
                              'Specifications',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            _buildSpecsGrid(context, specs),
                          ] else if (desc.isNotEmpty) ...[
                            const Text(
                              'About this item',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              desc,
                              style: TextStyle(
                                color: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.color
                                    ?.withValues(alpha: 0.9),
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          if (_cartItems.any((i) => i['id'] == pId)) ...[
                            Row(
                              children: [
                                const Text(
                                  'Quantity',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(width: 12),
                                Container(
                                  decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerHighest
                                        .withValues(alpha: 0.5),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        onPressed:
                                            (qty > 1 ||
                                                _cartItems.any(
                                                  (i) => i['id'] == pId,
                                                ))
                                            ? () {
                                                if (qty > 1) {
                                                  setSheetState(() => qty--);
                                                  if (_cartItems.any(
                                                    (i) => i['id'] == pId,
                                                  )) {
                                                    _updateCart(
                                                      currentProduct,
                                                      qty,
                                                    );
                                                  }
                                                } else {
                                                  // Remove from cart
                                                  _updateCart(
                                                    currentProduct,
                                                    0,
                                                  );
                                                  // Reset local qty to 1 for "Add" state
                                                  setSheetState(() => qty = 1);
                                                }
                                              }
                                            : null,
                                        icon: const Icon(Icons.remove),
                                        tooltip: 'Decrease quantity',
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                        ),
                                        child: Text(
                                          '$qty',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 18,
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        onPressed: (stock == 0 || qty >= stock)
                                            ? null
                                            : () {
                                                setSheetState(() => qty++);
                                                if (_cartItems.any(
                                                  (i) => i['id'] == pId,
                                                )) {
                                                  _updateCart(
                                                    currentProduct,
                                                    qty,
                                                  );
                                                }
                                              },
                                        icon: const Icon(Icons.add),
                                        tooltip: 'Increase quantity',
                                      ),
                                    ],
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  'Total: ${_currencyFormat.format(price * qty)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                          ],
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton.tonalIcon(
                                  onPressed: (stock == 0)
                                      ? null
                                      : () {
                                          final isInCart = _cartItems.any(
                                            (i) => i['id'] == pId,
                                          );
                                          if (isInCart) {
                                            _updateCart(currentProduct, 0);
                                            Navigator.of(context).pop();
                                          } else {
                                            _addToCart(
                                              context,
                                              currentProduct,
                                              qty: qty,
                                            );
                                            Navigator.of(context).pop();
                                          }
                                        },
                                  style: _cartItems.any((i) => i['id'] == pId)
                                      ? FilledButton.styleFrom(
                                          backgroundColor: Theme.of(
                                            context,
                                          ).colorScheme.errorContainer,
                                          foregroundColor: Theme.of(
                                            context,
                                          ).colorScheme.onErrorContainer,
                                        )
                                      : null,
                                  icon: Icon(
                                    _cartItems.any((i) => i['id'] == pId)
                                        ? Icons.remove_shopping_cart
                                        : Icons.add_shopping_cart,
                                  ),
                                  label: Text(
                                    stock == 0
                                        ? 'Out of Stock'
                                        : (_cartItems.any((i) => i['id'] == pId)
                                              ? 'Remove from Cart'
                                              : 'Add to Cart'),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: (stock == 0)
                                      ? null
                                      : () {
                                          Navigator.of(context).pop();
                                          _buyNow(context, currentProduct, qty);
                                        },
                                  icon: const Icon(Icons.flash_on),
                                  label: const Text('Buy Now'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      top: 12,
                      right: 12,
                      child: IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                        style: IconButton.styleFrom(
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.surface.withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 60,
                      right: 12,
                      child: IconButton.filledTonal(
                        onPressed: () => _shareProduct(currentProduct),
                        icon: const Icon(Icons.share, size: 20),
                        tooltip: 'Share Product',
                        style: IconButton.styleFrom(
                          backgroundColor: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest
                              .withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // Parse description into key: value specs (one per line). Returns ordered list.
  List<MapEntry<String, String>> _parseSpecs(String description) {
    final lines = description
        .split(RegExp(r"\r?\n"))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    final specs = <MapEntry<String, String>>[];
    for (final line in lines) {
      final idx = line.indexOf(':');
      if (idx <= 0) continue; // skip lines without key:value
      final key = line.substring(0, idx).trim();
      final value = line.substring(idx + 1).trim();
      if (key.isEmpty || value.isEmpty) continue;
      specs.add(MapEntry(key, value));
    }
    return specs;
  }

  // Build a neat two-column specs table
  Widget _buildSpecsGrid(
    BuildContext context,
    List<MapEntry<String, String>> specs,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
        ),
      ),
      child: Table(
        columnWidths: const {0: IntrinsicColumnWidth(), 1: FlexColumnWidth()},
        defaultVerticalAlignment: TableCellVerticalAlignment.top,
        children: [
          for (final e in specs)
            TableRow(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 6,
                    horizontal: 4,
                  ),
                  child: Text(
                    e.key,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 6,
                    horizontal: 4,
                  ),
                  child: Text(e.value, softWrap: true),
                ),
              ],
            ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> get _filteredProducts {
    // Parse price range once
    final double? minPrice = double.tryParse(_minPriceCtl.text.trim());
    final double? maxPrice = double.tryParse(_maxPriceCtl.text.trim());

    // Compute search tokens ONCE per build, not per product/compare
    final String q = _searchQuery.trim().toLowerCase();
    final List<String> tokens = q.isEmpty
        ? const <String>[]
        : _normalizeAndExpandTokens(q);

    final filtered = _products.where((product) {
      final brand = (product['brand'] ?? '').toString();
      final category = (product['category'] ?? '').toString();
      final spec = (product['spec'] ?? '').toString();
      final color = (product['color'] ?? '').toString().toLowerCase();
      final price = (product['price'] as num?)?.toDouble() ?? 0.0;
      final stock = (product['stock'] as int?) ?? 0;

      final matchesSearch =
          true; // Trust server-side search results for wider matches

      // Category (case-insensitive)
      final matchesCategory =
          _selectedCategory == 'all' ||
          category.toLowerCase() == _selectedCategory.toLowerCase();

      // Multi-select aware matching: if multi-set not empty, use it; else fallback to single-select
      final brandLc = brand.toLowerCase();
      final specLc = spec.toLowerCase();
      final matchesBrand = _selectedBrands.isNotEmpty
          ? _selectedBrands.map((e) => e.toLowerCase()).contains(brandLc)
          : (_selectedBrand == 'all' ||
                brandLc == _selectedBrand.toLowerCase());
      final matchesSpec = _selectedSpecs.isNotEmpty
          ? _selectedSpecs.map((e) => e.toLowerCase()).contains(specLc)
          : (_selectedSpec == 'all' || specLc == _selectedSpec.toLowerCase());
      final matchesColor = _selectedColors.isNotEmpty
          ? _selectedColors.map((e) => e.toLowerCase()).contains(color)
          : (_selectedColor == 'all' || color == _selectedColor.toLowerCase());

      // Stock filter
      final matchesStock =
          _stockFilter == 'all' ||
          (_stockFilter == 'in' && stock > 0) ||
          (_stockFilter == 'out' && stock == 0);

      final matchesMin = minPrice == null || price >= minPrice;
      final matchesMax = maxPrice == null || price <= maxPrice;

      return matchesSearch &&
          matchesCategory &&
          matchesBrand &&
          matchesSpec &&
          matchesColor &&
          matchesStock &&
          matchesMin &&
          matchesMax;
    }).toList();

    // Sort: if we have tokens and sort option is Relevance, rank using a cached score map
    final bool hasTokens = tokens.isNotEmpty;
    if (hasTokens && _sortOption == 'Relevance') {
      final Map<Map<String, dynamic>, int> score = {};
      for (final p in filtered) {
        score[p] = _relevanceScore(p, tokens);
      }
      filtered.sort((a, b) {
        final sa = score[a] ?? 0;
        final sb = score[b] ?? 0;
        if (sb != sa) return sb.compareTo(sa);
        // tie-breakers
        final na = (a['name'] ?? '').toString().toLowerCase();
        final nb = (b['name'] ?? '').toString().toLowerCase();
        return na.compareTo(nb);
      });
    } else {
      // Fallback to existing sorts
      switch (_sortOption) {
        case 'Price: Low to High':
          filtered.sort(
            (a, b) => ((a['price'] as num?)?.toDouble() ?? 0).compareTo(
              ((b['price'] as num?)?.toDouble() ?? 0),
            ),
          );
          break;
        case 'Price: High to Low':
          filtered.sort(
            (a, b) => ((b['price'] as num?)?.toDouble() ?? 0).compareTo(
              ((a['price'] as num?)?.toDouble() ?? 0),
            ),
          );
          break;
        case 'Newest':
          filtered.sort((a, b) {
            final da = a['createdAt'] as DateTime?;
            final db = b['createdAt'] as DateTime?;
            if (da == null && db == null) return 0;
            if (da == null) return 1;
            if (db == null) return -1;
            return db.compareTo(da); // newest first
          });
          break;
        case 'Name A-Z':
          filtered.sort(
            (a, b) => (a['name'] ?? '').toString().toLowerCase().compareTo(
              (b['name'] ?? '').toString().toLowerCase(),
            ),
          );
          break;
        default:
          // Relevance & no tokens: keep current order
          break;
      }
    }

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isDesktop = constraints.maxWidth > 768;
            final showPinnedSearch = constraints.maxWidth > 600;

            final content = CustomScrollView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                // Sticky Header
                _buildSliverAppBar(context, isDesktop),
                // Sticky filter search (tablet + desktop)
                if (showPinnedSearch) _buildPinnedFilterSearchHeader(context),

                // Hero Section
                SliverToBoxAdapter(
                  child: _buildHeroSection(context, constraints),
                ),

                // Categories Section
                SliverToBoxAdapter(
                  child: _buildCategoriesSection(context, constraints),
                ),

                // Filter Bar (mobile only; on tablet/desktop it's inside the pinned header)
                if (!showPinnedSearch)
                  SliverToBoxAdapter(
                    child: _buildFilterBar(context, constraints),
                  ),

                // Products Grid/List
                _buildProductsSection(context, constraints),

                // Recently Viewed
                if (_recentlyViewed.isNotEmpty)
                  SliverToBoxAdapter(
                    child: _buildRecentlyViewedSection(context, constraints),
                  ),

                // Load More Button / Indicator
                if (_hasMore)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Center(
                        child: _isLoadingMore
                            ? const CircularProgressIndicator()
                            : FilledButton.tonalIcon(
                                onPressed: () {
                                  _loadProductsAndCategories(reset: false);
                                },
                                icon: const Icon(Icons.expand_more),
                                label: const Text('Load More Products'),
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                    vertical: 12,
                                  ),
                                ),
                              ),
                      ),
                    ),
                  ),

                // Footer
                SliverToBoxAdapter(child: _buildFooter(context, constraints)),
              ],
            );

            // Pull-to-refresh for mobile
            return RefreshIndicator(
              onRefresh: _loadProductsAndCategories,
              child: content,
            );
          },
        ),
      ),
      // Floating Cart Button for mobile
      floatingActionButton: _cartCount > 0 ? _buildFloatingCart(context) : null,
    );
  }

  Widget _buildSliverAppBar(BuildContext context, bool isDesktop) {
    return SliverAppBar(
      pinned: true,
      toolbarHeight: isDesktop ? 80 : 120,
      collapsedHeight: isDesktop ? 80 : 140,
      expandedHeight: isDesktop ? 120 : 180,
      backgroundColor: Theme.of(context).cardColor,
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: EdgeInsets.zero,
        title: Container(
          padding: EdgeInsets.symmetric(
            horizontal: isDesktop ? 24 : 16,
            vertical: isDesktop ? 12 : 6,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  // Logo (long-press to show debug info)
                  GestureDetector(
                    onLongPress: () {
                      if (!kDebugMode) return;
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Logo Debug'),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Business ID:'),
                              const SizedBox(height: 4),
                              SelectableText(_currentBusinessId ?? '(null)'),
                              const SizedBox(height: 12),
                              const Text('Raw logoUrl:'),
                              const SizedBox(height: 4),
                              SelectableText(_rawLogoUrl ?? '(null)'),
                              const SizedBox(height: 12),
                              const Text('Resolved URL used:'),
                              const SizedBox(height: 4),
                              SelectableText(_businessLogoUrl ?? '(null)'),
                            ],
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(ctx).pop(),
                              child: const Text('Close'),
                            ),
                          ],
                        ),
                      );
                    },
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).primaryColor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(UITokens.radius),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: _businessLogoUrl != null
                          ? Image.network(
                              _businessLogoUrl!,
                              headers: const {
                                'User-Agent':
                                    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                              },
                              fit: BoxFit.cover,
                              loadingBuilder: (context, child, progress) {
                                if (progress == null) return child;
                                return Icon(
                                  Icons.cable,
                                  color: Theme.of(context).primaryColor,
                                  size: 24,
                                );
                              },
                              errorBuilder: (c, e, s) {
                                if (kDebugMode) {
                                  debugPrint(
                                    '[Shop] Image.network failed for logo: $e',
                                  );
                                }
                                return Center(
                                  child: Image.asset(
                                    'assets/icons/app_icon.png',
                                    fit: BoxFit.contain,
                                    width: 28,
                                    height: 28,
                                  ),
                                );
                              },
                            )
                          : Center(
                              child: Image.asset(
                                'assets/icons/app_icon.png',
                                fit: BoxFit.contain,
                                width: 28,
                                height: 28,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Business Name
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _businessName,
                          style: TextStyle(
                            fontSize: isDesktop ? 20 : 19,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(
                              context,
                            ).textTheme.titleLarge?.color,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Cart Icon
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.shopping_cart_outlined),
                        onPressed: () => _openCart(context),
                        iconSize: 24,
                      ),
                      if (_cartCount > 0)
                        Positioned(
                          right: 8,
                          top: 8,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.error,
                              shape: BoxShape.circle,
                            ),
                            constraints: const BoxConstraints(
                              minWidth: 16,
                              minHeight: 16,
                            ),
                            child: Text(
                              '$_cartCount',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              // Search Bar (mobile only)
              if (MediaQuery.of(context).size.width <= 600)
                Container(
                  height: 36,
                  decoration: BoxDecoration(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Autocomplete<String>(
                    optionsBuilder: (TextEditingValue textEditingValue) {
                      final query = textEditingValue.text.trim().toLowerCase();
                      if (query.isEmpty) return const Iterable<String>.empty();

                      final catMatches = _availableCategories
                          .where((c) => c.toLowerCase().contains(query))
                          .map((c) => 'Category: $c');

                      final brandMatches = _availableBrands
                          .where((b) => b.toLowerCase().contains(query))
                          .map((b) => 'Brand: $b');

                      return [...catMatches, ...brandMatches];
                    },
                    onSelected: (String selection) {
                      if (selection.startsWith('Category: ')) {
                        final cat = selection.substring(10);
                        setState(() {
                          _selectedCategory = cat;
                          _searchController.clear();
                        });
                        _loadProductsAndCategories(reset: true);
                      } else if (selection.startsWith('Brand: ')) {
                        final brand = selection.substring(7);
                        // Ideally we have a brand filter, for now treating as text search or adding filter?
                        // Current UI has 'Brand' filter logic but it's not fully exposed in _loadProductsAndCategories V2 params commonly?
                        // _loadProductsAndCategories uses `search` param which acts on name/brand.
                        // But for strict filtering, we might want to set a dedicated brand filter if supported.
                        // Let's use search query for now, or update _selectedBrand if we support it in API.
                        // API supports p_search.
                        setState(() {
                          _searchController.text =
                              brand; // Search by brand name
                          _onSearchChanged(brand);
                        });
                      }
                    },
                    fieldViewBuilder:
                        (
                          context,
                          textEditingController,
                          focusNode,
                          onFieldSubmitted,
                        ) {
                          // Sync controllers
                          if (textEditingController.text !=
                              _searchController.text) {
                            textEditingController.text = _searchController.text;
                          }

                          return TextField(
                            controller: textEditingController,
                            focusNode: focusNode,
                            onSubmitted: (val) {
                              _searchController.text = val;
                              _onSearchChanged(val);
                            },
                            onChanged: (val) {
                              _searchController.text = val;
                              // Optionally auto-search on type (existing logic)
                              // _onSearchChanged(val);
                            },
                            decoration: InputDecoration(
                              hintText: _isListening
                                  ? 'Listening...'
                                  : 'Search products...',
                              hintStyle: TextStyle(
                                fontSize: 14,
                                color: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.color
                                    ?.withValues(alpha: 0.6),
                              ),
                              isDense: true,
                              prefixIcon: const Icon(Icons.search, size: 20),
                              prefixIconConstraints: const BoxConstraints(
                                minWidth: 40,
                                minHeight: 36,
                              ),
                              suffixIconConstraints: const BoxConstraints(
                                minWidth: 72,
                                minHeight: 36,
                              ),
                              filled: true,
                              fillColor: Theme.of(
                                context,
                              ).colorScheme.surface.withValues(alpha: 0.5),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(999),
                                borderSide: BorderSide.none,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(999),
                                borderSide: BorderSide(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.outline.withValues(alpha: 0.1),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(999),
                                borderSide: BorderSide(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.primary.withValues(alpha: 0.5),
                                ),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              suffixIcon: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (_speechAvailable)
                                    IconButton(
                                      icon: Icon(
                                        _isListening
                                            ? Icons.mic
                                            : Icons.mic_none,
                                        color: _isListening
                                            ? Colors.red
                                            : Theme.of(context).primaryColor,
                                        size: 20,
                                      ),
                                      onPressed: () => _listen(context),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                    ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.camera_alt_outlined,
                                      size: 18,
                                    ),
                                    onPressed: () => _openSmartScan(context),
                                  ),
                                  if (_searchController.text.isNotEmpty)
                                    IconButton(
                                      icon: const Icon(Icons.clear, size: 18),
                                      onPressed: () {
                                        _searchController.clear();
                                        _onSearchChanged('');
                                      },
                                    ),
                                ],
                              ),
                            ),
                            textAlignVertical: TextAlignVertical.center,
                          );
                        },
                  ),
                ),
              if (MediaQuery.of(context).size.width <= 600)
                SizedBox(height: (_isScrolled) ? 28 : 12),
            ],
          ),
        ),
        centerTitle: false,
      ),
    );
  }

  Widget _buildHeroSection(BuildContext context, BoxConstraints constraints) {
    final padding = constraints.maxWidth > 768 ? 48.0 : 24.0;
    final titleSize = constraints.maxWidth > 768 ? 48.0 : 32.0;
    final cs = Theme.of(context).colorScheme;

    return Container(
      margin: EdgeInsets.all(padding / 2),
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            cs.primary.withValues(alpha: 0.08),
            cs.secondaryContainer.withValues(alpha: 0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cs.outline.withValues(alpha: 0.05)),
      ),
      child: Column(
        children: [
          Text(
            'Your One-Stop Shop in Ghaziabad',
            style: TextStyle(
              fontSize: titleSize,
              fontWeight: FontWeight.w900,
              color: cs.onSurface,
              letterSpacing: -0.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            'Quality electricals, hardware, and accessories.\nAll your needs, in one place.',
            style: TextStyle(
              fontSize: constraints.maxWidth > 768 ? 18 : 16,
              color: cs.onSurfaceVariant,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 16,
            runSpacing: 16,
            children: [
              FilledButton.icon(
                onPressed: () {
                  _launchUrl(_googleMapsUrl);
                },
                icon: const FaIcon(FontAwesomeIcons.mapLocationDot, size: 18),
                label: const Text('Locate Us'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                  textStyle: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  _launchUrl(_instagramUrl);
                },
                icon: const FaIcon(FontAwesomeIcons.instagram, size: 18),
                label: const Text('Follow Us'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                  side: BorderSide(color: cs.outline, width: 1.5),
                  textStyle: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCategoriesSection(
    BuildContext context,
    BoxConstraints constraints,
  ) {
    return const SizedBox.shrink(); // Categories now shown in pinned header only
  }

  Widget _buildProductListItem(
    BuildContext context,
    Map<String, dynamic> product,
  ) {
    final isOutOfStock = (product['stock'] as int? ?? 0) == 0;
    final isWishlisted = _wishlist.contains(product['id']);
    final isDesktop = MediaQuery.of(context).size.width > 900;
    final cs = Theme.of(context).colorScheme;

    final String name = (product['name'] as String?) ?? '';
    final String brand =
        ((product['brand'] as String?)?.trim().isNotEmpty ?? false)
        ? (product['brand'] as String)
        : 'Generic';
    final String category = (product['category'] as String?) ?? 'General';
    final int stock = (product['stock'] as int?) ?? 0;
    final double price = (product['price'] as num?)?.toDouble() ?? 0.0;

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: isDesktop ? 2 : 1,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: Theme.of(context).cardColor,
      child: InkWell(
        onTap: () => _viewProduct(context, product),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Image
              Stack(
                children: [
                  Container(
                    width: isDesktop ? 64 : 56,
                    height: isDesktop ? 64 : 56,
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(UITokens.radius),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: (product['image'] != null)
                        ? Image.network(
                            product['image'],
                            headers: const {
                              'User-Agent':
                                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                            },
                            fit: BoxFit.cover,
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return const Center(
                                child: Icon(Icons.image, size: 20),
                              );
                            },
                            errorBuilder: (context, error, stackTrace) =>
                                const Center(
                                  child: Icon(
                                    Icons.image_not_supported,
                                    size: 20,
                                  ),
                                ),
                          )
                        : const Center(child: Icon(Icons.image, size: 22)),
                  ),
                  if (isOutOfStock)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: cs.error,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'Out',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),

              // Main info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        // Brand chip
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerHighest.withValues(
                              alpha: 0.6,
                            ),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            brand,
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(
                                context,
                              ).textTheme.bodyMedium?.color,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        // Category chip
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerHighest.withValues(
                              alpha: 0.35,
                            ),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: Theme.of(
                                context,
                              ).dividerColor.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Text(
                            category,
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(
                                context,
                              ).textTheme.bodyMedium?.color,
                            ),
                          ),
                        ),
                        // Stock chip
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: isOutOfStock
                                ? cs.error.withValues(alpha: 0.12)
                                : cs.primaryContainer.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            'Stock: $stock',
                            style: TextStyle(
                              fontSize: 12,
                              color: isOutOfStock
                                  ? cs.error
                                  : cs.onPrimaryContainer,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 12),

              // Price and actions
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _currencyFormat.format(price),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: isWishlisted
                            ? 'Remove from Wishlist'
                            : 'Add to Wishlist',
                        onPressed: () => _toggleWishlist(product['id'] as int),
                        icon: Icon(
                          isWishlisted ? Icons.favorite : Icons.favorite_border,
                          color: isWishlisted
                              ? cs.error
                              : Theme.of(context).iconTheme.color,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Tooltip(
                        message: isOutOfStock ? 'Out of stock' : 'Add to cart',
                        child: IconButton.filled(
                          onPressed: isOutOfStock
                              ? null
                              : () => _addToCart(context, product),
                          style: IconButton.styleFrom(
                            backgroundColor: Theme.of(context).primaryColor,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: Theme.of(
                              context,
                            ).disabledColor,
                            disabledForegroundColor: Theme.of(
                              context,
                            ).disabledColor.withValues(alpha: 0.38),
                          ),
                          icon: const Icon(
                            Icons.shopping_cart_checkout,
                            size: 20,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecentlyViewedSection(
    BuildContext context,
    BoxConstraints constraints,
  ) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Recently Viewed',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 120,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _recentlyViewed.length,
              itemBuilder: (context, index) {
                final id = _recentlyViewed[index];
                final prod = _products.firstWhere(
                  (p) => p['id'] == id,
                  orElse: () => {},
                );
                final String name = (prod['name'] as String?) ?? 'Product';
                final String? img = prod['image'] as String?;
                return InkWell(
                  onTap: prod.isNotEmpty
                      ? () => _viewProduct(context, prod)
                      : null,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: 120,
                    margin: const EdgeInsets.only(right: 16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Theme.of(
                          context,
                        ).dividerColor.withValues(alpha: 0.1),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(8),
                            ),
                            child: Container(
                              color: Theme.of(
                                context,
                              ).dividerColor.withValues(alpha: 0.1),
                              child: img != null
                                  ? Image.network(
                                      img,
                                      fit: BoxFit.cover,
                                      errorBuilder: (c, e, s) => const Center(
                                        child: Icon(
                                          Icons.image_not_supported,
                                          size: 24,
                                        ),
                                      ),
                                    )
                                  : const Center(
                                      child: Icon(Icons.image, size: 24),
                                    ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
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
    );
  }

  Widget _buildFooter(BuildContext context, BoxConstraints constraints) {
    final isMobile = constraints.maxWidth <= 600;
    final p = _businessProfile;

    String joinNonEmpty(List<String?> parts) => parts
        .where((e) => e != null && e.trim().isNotEmpty)
        .map((e) => e!.trim())
        .join(', ');

    String? nonEmpty(String? s) =>
        (s?.trim().isNotEmpty ?? false) ? s!.trim() : null;

    final businessName = p?.businessName ?? _businessName;
    // Environment fallbacks (provided via --dart-define)
    const envAddress = String.fromEnvironment(
      'BUSINESS_ADDRESS',
      defaultValue: '',
    );
    const envCity = String.fromEnvironment('BUSINESS_CITY', defaultValue: '');
    const envState = String.fromEnvironment('BUSINESS_STATE', defaultValue: '');
    const envPostal = String.fromEnvironment(
      'BUSINESS_POSTAL_CODE',
      defaultValue: '',
    );
    const envCountry = String.fromEnvironment(
      'BUSINESS_COUNTRY',
      defaultValue: '',
    );
    const envPhone = String.fromEnvironment('BUSINESS_PHONE', defaultValue: '');
    const envEmail = String.fromEnvironment('BUSINESS_EMAIL', defaultValue: '');
    const envWebsite = String.fromEnvironment(
      'BUSINESS_WEBSITE',
      defaultValue: '',
    );

    final address =
        nonEmpty(p?.address) ?? (envAddress.isNotEmpty ? envAddress : null);
    final city = nonEmpty(p?.city) ?? (envCity.isNotEmpty ? envCity : null);
    final state = nonEmpty(p?.state) ?? (envState.isNotEmpty ? envState : null);
    final postalCode =
        nonEmpty(p?.postalCode) ?? (envPostal.isNotEmpty ? envPostal : null);
    final country =
        nonEmpty(p?.country) ?? (envCountry.isNotEmpty ? envCountry : null);
    final addressText = joinNonEmpty([
      address,
      city,
      state,
      postalCode,
      country,
    ]);

    final phone = nonEmpty(p?.phone) ?? (envPhone.isNotEmpty ? envPhone : null);
    final email = nonEmpty(p?.email) ?? (envEmail.isNotEmpty ? envEmail : null);
    final website =
        nonEmpty(p?.website) ?? (envWebsite.isNotEmpty ? envWebsite : null);
    final gst = p?.gstNumber;
    final pan = p?.panNumber;
    final upi = p?.upiVpa;

    final contactSection = _buildContactInfoSection(
      context,
      phone: phone,
      email: email,
      website: website,
    );

    return Container(
      padding: EdgeInsets.all(isMobile ? 24 : 48),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isMobile)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildFooterSection(
                  businessName,
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (addressText.isNotEmpty)
                        Text(
                          addressText,
                          style: TextStyle(
                            color: Theme.of(context).textTheme.bodyMedium?.color
                                ?.withValues(alpha: 0.75),
                          ),
                        ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          if (gst != null && gst.trim().isNotEmpty)
                            _footerChip(context, 'GST: ${gst.trim()}'),
                          if (pan != null && pan.trim().isNotEmpty)
                            _footerChip(context, 'PAN: ${pan.trim()}'),
                          if (upi != null && upi.trim().isNotEmpty)
                            _footerChip(context, 'UPI: ${upi.trim()}'),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                if (contactSection != null) contactSection,
                const SizedBox(height: 24),
                Builder(
                  builder: (_) {
                    final List<Widget> actions = [];
                    void addIf(String? url, IconData icon, String label) {
                      if (url != null && url.trim().isNotEmpty) {
                        actions.add(
                          _footerActionChip(context, icon, label, url.trim()),
                        );
                      }
                    }

                    addIf(
                      _instagramUrl,
                      Icons.camera_alt_outlined,
                      'Instagram',
                    );
                    addIf(
                      _whatsappCatalogUrl,
                      Icons.chat_bubble_outline,
                      'WhatsApp Catalog',
                    );
                    final fallbackGmaps = addressText.isNotEmpty
                        ? 'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(addressText)}'
                        : null;
                    final fallbackMmi = addressText.isNotEmpty
                        ? 'https://maps.mapmyindia.com/?q=${Uri.encodeComponent(addressText)}'
                        : null;
                    addIf(
                      _googleMapsUrl ?? fallbackGmaps,
                      Icons.map_outlined,
                      'Google Maps',
                    );
                    addIf(
                      _mapMyIndiaUrl ?? fallbackMmi,
                      Icons.place_outlined,
                      'Map My India',
                    );

                    if (actions.isEmpty) return const SizedBox.shrink();
                    return _buildFooterSection(
                      'Connect',
                      Wrap(spacing: 8, runSpacing: 8, children: actions),
                    );
                  },
                ),
                const SizedBox(height: 24),
                _buildFooterSection(
                  'Business Hours',
                  const Text(
                    'Mon-Sat: 9:00 AM - 8:00 PM\nSunday: 10:00 AM - 6:00 PM',
                  ),
                ),
              ],
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _buildFooterSection(
                    businessName,
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (addressText.isNotEmpty)
                          Text(
                            addressText,
                            style: TextStyle(
                              color: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.color
                                  ?.withValues(alpha: 0.75),
                            ),
                          ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            if (gst != null && gst.trim().isNotEmpty)
                              _footerChip(context, 'GST: ${gst.trim()}'),
                            if (pan != null && pan.trim().isNotEmpty)
                              _footerChip(context, 'PAN: ${pan.trim()}'),
                            if (upi != null && upi.trim().isNotEmpty)
                              _footerChip(context, 'UPI: ${upi.trim()}'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 32),
                if (contactSection != null) Expanded(child: contactSection),
                const SizedBox(width: 32),
                Expanded(
                  child: Builder(
                    builder: (_) {
                      final List<Widget> actions = [];
                      void addIf(String? url, IconData icon, String label) {
                        if (url != null && url.trim().isNotEmpty) {
                          actions.add(
                            _footerActionChip(context, icon, label, url.trim()),
                          );
                        }
                      }

                      final fallbackGmaps = addressText.isNotEmpty
                          ? 'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(addressText)}'
                          : null;
                      final fallbackMmi = addressText.isNotEmpty
                          ? 'https://maps.mapmyindia.com/?q=${Uri.encodeComponent(addressText)}'
                          : null;
                      addIf(
                        _instagramUrl,
                        Icons.camera_alt_outlined,
                        'Instagram',
                      );
                      addIf(
                        _whatsappCatalogUrl,
                        Icons.chat_bubble_outline,
                        'WhatsApp Catalog',
                      );
                      addIf(
                        _googleMapsUrl ?? fallbackGmaps,
                        Icons.map_outlined,
                        'Google Maps',
                      );
                      addIf(
                        _mapMyIndiaUrl ?? fallbackMmi,
                        Icons.place_outlined,
                        'Map My India',
                      );

                      if (actions.isEmpty) return const SizedBox.shrink();
                      return _buildFooterSection(
                        'Connect',
                        Wrap(spacing: 8, runSpacing: 8, children: actions),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 32),
                Expanded(
                  child: _buildFooterSection(
                    'Business Hours',
                    const Text(
                      'Mon-Sat: 9:00 AM - 8:00 PM\nSunday: 10:00 AM - 6:00 PM',
                    ),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 24),
          Text(
            '© ${DateTime.now().year} $businessName. All rights reserved.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(
                context,
              ).textTheme.bodySmall?.color?.withValues(alpha: 0.6),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooterSection(String title, Widget content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        const SizedBox(height: 8),
        content,
      ],
    );
  }

  Widget? _buildContactInfoSection(
    BuildContext context, {
    required String? phone,
    required String? email,
    required String? website,
  }) {
    final rows = <Widget>[];
    if (phone != null && phone.trim().isNotEmpty) {
      rows.add(
        _footerLink(context, Icons.call, phone.trim(), 'tel:${phone.trim()}'),
      );
    }
    if (email != null && email.trim().isNotEmpty) {
      rows.add(
        _footerLink(
          context,
          Icons.email_outlined,
          email.trim(),
          'mailto:${email.trim()}',
        ),
      );
    }
    if (website != null && website.trim().isNotEmpty) {
      final w = website.trim();
      rows.add(
        _footerLink(
          context,
          Icons.public,
          w,
          w.startsWith('http') ? w : 'https://$w',
        ),
      );
    }
    if (rows.isEmpty) return null;
    return _buildFooterSection(
      'Contact Info',
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows),
    );
  }

  Widget _footerChip(BuildContext context, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.25),
        ),
      ),
      child: Text(label, style: const TextStyle(fontSize: 10.5)),
    );
  }

  Widget _footerLink(
    BuildContext context,
    IconData icon,
    String label,
    String url,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: () async {
          try {
            final uri = Uri.parse(url);
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          } catch (_) {}
        },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: Theme.of(context).iconTheme.color?.withValues(alpha: 0.8),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  color: Theme.of(context).textTheme.bodyMedium?.color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFloatingCart(BuildContext context) {
    return FloatingActionButton.extended(
      onPressed: () => _openCart(context),
      icon: const Icon(Icons.shopping_cart),
      label: Text('Cart ($_cartCount)'),
      backgroundColor: Theme.of(context).colorScheme.primary,
    );
  }

  List<double> _priceBoundsNew() {
    if (_products.isEmpty) return [0, 1000];
    double min = double.infinity;
    double max = double.negativeInfinity;
    for (final p in _products) {
      final price = (p['price'] as num?)?.toDouble() ?? 0.0;
      if (price < min) min = price;
      if (price > max) max = price;
    }
    if (min == double.infinity) return [0, 1000];
    return [min, max];
  }

  Widget _buildCollapsibleFilters(BuildContext context, ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Brand, Spec, Color + Multi buttons
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<String>(
                initialValue: _selectedBrand,
                isExpanded: true,
                items: _brands
                    .map(
                      (b) => DropdownMenuItem(
                        value: b,
                        child: Text(
                          b[0].toUpperCase() + b.substring(1),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() {
                  _selectedBrand = v ?? 'all';
                  _selectedBrands.clear();
                  _scrollToProducts();
                }),
                decoration: InputDecoration(
                  labelText: 'Brand',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  isDense: true,
                ),
              ),
            ),
            SizedBox(
              height: 40,
              child: OutlinedButton.icon(
                onPressed: () => _showMultiSelectBottomSheet(
                  context,
                  title: 'Select Brands',
                  options: _brands,
                  targetSet: _selectedBrands,
                ),
                icon: const Icon(Icons.checklist),
                label: const Text('Multi'),
              ),
            ),
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<String>(
                initialValue: _selectedSpec,
                isExpanded: true,
                items: _specs
                    .map(
                      (s) => DropdownMenuItem(
                        value: s,
                        child: Text(
                          s[0].toUpperCase() + s.substring(1),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() {
                  _selectedSpec = v ?? 'all';
                  _selectedSpecs.clear();
                  _scrollToProducts();
                }),
                decoration: InputDecoration(
                  labelText: 'Spec (Amp/sqmm)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  isDense: true,
                ),
              ),
            ),
            SizedBox(
              height: 40,
              child: OutlinedButton.icon(
                onPressed: () => _showMultiSelectBottomSheet(
                  context,
                  title: 'Select Specs',
                  options: _specs,
                  targetSet: _selectedSpecs,
                ),
                icon: const Icon(Icons.checklist),
                label: const Text('Multi'),
              ),
            ),
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<String>(
                initialValue: _selectedColor,
                items: _colors
                    .map(
                      (c) => DropdownMenuItem(
                        value: c,
                        child: Text(c[0].toUpperCase() + c.substring(1)),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() {
                  _selectedColor = v ?? 'all';
                  _selectedColors.clear();
                  _scrollToProducts();
                }),
                decoration: InputDecoration(
                  labelText: 'Color',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  isDense: true,
                ),
              ),
            ),
            SizedBox(
              height: 40,
              child: OutlinedButton.icon(
                onPressed: () => _showMultiSelectBottomSheet(
                  context,
                  title: 'Select Colors',
                  options: _colors,
                  targetSet: _selectedColors,
                ),
                icon: const Icon(Icons.checklist),
                label: const Text('Multi'),
              ),
            ),
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<String>(
                initialValue: _stockFilter,
                decoration: InputDecoration(
                  labelText: 'Availability',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('All Items')),
                  DropdownMenuItem(value: 'in', child: Text('In Stock Only')),
                  DropdownMenuItem(
                    value: 'out',
                    child: Text('Out of Stock Only'),
                  ),
                ],
                onChanged: (v) => setState(() {
                  _stockFilter = v ?? 'all';
                  _scrollToProducts();
                }),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Price range + Sort + Clear
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 160,
              child: TextField(
                controller: _minPriceCtl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                decoration: const InputDecoration(
                  labelText: 'Min Price',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (_) => setState(() => _scrollToProducts()),
              ),
            ),
            SizedBox(
              width: 160,
              child: TextField(
                controller: _maxPriceCtl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                decoration: const InputDecoration(
                  labelText: 'Max Price',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (_) => setState(() => _scrollToProducts()),
              ),
            ),
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<String>(
                initialValue: _sortOption,
                items: _sortOptions
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: (v) => setState(() {
                  _sortOption = v ?? 'Relevance';
                  _scrollToProducts();
                }),
                decoration: const InputDecoration(
                  labelText: 'Sort',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _selectedCategory = 'all';
                  _selectedBrand = 'all';
                  _selectedSpec = 'all';
                  _selectedColor = 'all';
                  _selectedBrands.clear();
                  _selectedSpecs.clear();
                  _selectedColors.clear();
                  _minPriceCtl.clear();
                  _maxPriceCtl.clear();
                  _stockFilter = 'all';
                  final b = _priceBoundsNew();
                  final start = b[0];
                  final end = b[1] > b[0] ? b[1] : b[0] + 1.0;
                  _priceRange = RangeValues(start, end);
                  _sortOption = 'Relevance';
                  _scrollToProducts();
                });
              },
              icon: const Icon(Icons.clear),
              label: const Text('Clear All'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Price slider
        Builder(
          builder: (context) {
            if (_products.isEmpty) {
              return const SizedBox.shrink();
            }
            final bounds = _priceBoundsNew();
            final minBound = bounds[0];
            final maxBound = bounds[1] > bounds[0]
                ? bounds[1]
                : bounds[0] + 1.0;
            double currentMin =
                double.tryParse(_minPriceCtl.text.trim()) ??
                (_priceRange?.start ?? minBound);
            double currentMax =
                double.tryParse(_maxPriceCtl.text.trim()) ??
                (_priceRange?.end ?? maxBound);
            if (currentMin.isNaN || currentMin < minBound) {
              currentMin = minBound;
            }
            if (currentMax.isNaN || currentMax > maxBound) {
              currentMax = maxBound;
            }
            if (currentMin > currentMax) {
              final tmp = currentMin;
              currentMin = currentMax;
              currentMax = tmp;
            }
            final rv = RangeValues(currentMin, currentMax);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Price Range',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '${_currencyFormat.format(rv.start)} - ${_currencyFormat.format(rv.end)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                RangeSlider(
                  values: rv,
                  min: minBound,
                  max: maxBound,
                  onChanged: (val) {
                    setState(() {
                      _priceRange = val;
                      _minPriceCtl.text = val.start.toStringAsFixed(0);
                      _maxPriceCtl.text = val.end.toStringAsFixed(0);
                    });
                  },
                ),
              ],
            );
          },
        ),
        // Active filter chips
        Builder(
          builder: (context) {
            final List<Widget> chips = [];
            if (_selectedCategory != 'all') {
              chips.add(
                Chip(
                  label: Text('Category: $_selectedCategory'),
                  onDeleted: () => setState(() {
                    _selectedCategory = 'all';
                    _scrollToProducts();
                  }),
                  visualDensity: VisualDensity.compact,
                ),
              );
            }
            if (_selectedBrands.isNotEmpty) {
              for (final b in _selectedBrands.toList()) {
                chips.add(
                  Chip(
                    label: Text('Brand: $b'),
                    onDeleted: () => setState(() {
                      _selectedBrands.remove(b);
                      _scrollToProducts();
                    }),
                    visualDensity: VisualDensity.compact,
                  ),
                );
              }
            } else if (_selectedBrand != 'all') {
              chips.add(
                Chip(
                  label: Text('Brand: $_selectedBrand'),
                  onDeleted: () => setState(() {
                    _selectedBrand = 'all';
                    _scrollToProducts();
                  }),
                  visualDensity: VisualDensity.compact,
                ),
              );
            }
            if (_selectedSpecs.isNotEmpty) {
              for (final s in _selectedSpecs.toList()) {
                chips.add(
                  Chip(
                    label: Text('Spec: $s'),
                    onDeleted: () => setState(() {
                      _selectedSpecs.remove(s);
                      _scrollToProducts();
                    }),
                    visualDensity: VisualDensity.compact,
                  ),
                );
              }
            } else if (_selectedSpec != 'all') {
              chips.add(
                Chip(
                  label: Text('Spec: $_selectedSpec'),
                  onDeleted: () => setState(() {
                    _selectedSpec = 'all';
                    _scrollToProducts();
                  }),
                  visualDensity: VisualDensity.compact,
                ),
              );
            }
            if (_selectedColors.isNotEmpty) {
              for (final c in _selectedColors.toList()) {
                chips.add(
                  Chip(
                    label: Text('Color: $c'),
                    onDeleted: () => setState(() {
                      _selectedColors.remove(c);
                      _scrollToProducts();
                    }),
                    visualDensity: VisualDensity.compact,
                  ),
                );
              }
            } else if (_selectedColor != 'all') {
              chips.add(
                Chip(
                  label: Text('Color: $_selectedColor'),
                  onDeleted: () => setState(() {
                    _selectedColor = 'all';
                    _scrollToProducts();
                  }),
                  visualDensity: VisualDensity.compact,
                ),
              );
            }
            final hasMin = double.tryParse(_minPriceCtl.text.trim()) != null;
            final hasMax = double.tryParse(_maxPriceCtl.text.trim()) != null;
            if (hasMin) {
              chips.add(
                Chip(
                  label: Text('Min: ${_minPriceCtl.text}'),
                  onDeleted: () => setState(() {
                    _minPriceCtl.clear();
                    _scrollToProducts();
                  }),
                  visualDensity: VisualDensity.compact,
                ),
              );
            }
            if (hasMax) {
              chips.add(
                Chip(
                  label: Text('Max: ${_maxPriceCtl.text}'),
                  onDeleted: () => setState(() {
                    _maxPriceCtl.clear();
                    _scrollToProducts();
                  }),
                  visualDensity: VisualDensity.compact,
                ),
              );
            }
            if (chips.isEmpty) {
              return const SizedBox.shrink();
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                Text(
                  'Active Filters',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Wrap(spacing: 8, runSpacing: 8, children: chips),
              ],
            );
          },
        ),
      ],
    );
  }
}

// Simple SliverPersistentHeader delegate used for the pinned desktop search bar
class _SimpleHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double minHeight;
  final double maxHeight;
  final Widget child;

  _SimpleHeaderDelegate({
    required this.minHeight,
    required this.maxHeight,
    required this.child,
  });

  @override
  double get minExtent => minHeight;

  @override
  double get maxExtent => maxHeight > minHeight ? maxHeight : minHeight;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return SizedBox.expand(child: child);
  }

  @override
  bool shouldRebuild(covariant _SimpleHeaderDelegate oldDelegate) {
    return maxHeight != oldDelegate.maxHeight ||
        minHeight != oldDelegate.minHeight ||
        child != oldDelegate.child;
  }
}
