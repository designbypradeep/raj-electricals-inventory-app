import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:app_links/app_links.dart';
import 'dart:async';
import '../services/slug_resolver.dart';
import '../services/supabase_service.dart';
import 'shop_page.dart';
import '../data/app_database.dart';

class WelcomePage extends StatefulWidget {
  final AppDatabase db;
  const WelcomePage({super.key, required this.db});

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  final TextEditingController _slugController = TextEditingController();
  final SlugResolver _slugResolver = SlugResolver();
  late AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initDeepLinks();
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    _slugController.dispose();
    super.dispose();
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
    String? slug;
    // 1. Standard Path: https://domain.com/store/slug or myshop://store/slug
    if (uri.pathSegments.contains('store')) {
      final idx = uri.pathSegments.indexOf('store');
      if (idx + 1 < uri.pathSegments.length) {
        slug = uri.pathSegments[idx + 1];
      }
    }
    // 2. Custom Scheme: myshop://store/slug (host might be 'store')
    else if (uri.scheme == 'myshop' &&
        uri.host == 'store' &&
        uri.pathSegments.isNotEmpty) {
      slug = uri.pathSegments.first;
    }
    // 3. Fallback for query param ?id=slug (if using web redirect link directly)
    else if (uri.queryParameters.containsKey('id')) {
      slug = uri.queryParameters['id'];
    }

    if (slug != null && slug.isNotEmpty) {
      _slugController.text = slug;
      await _handleSlugSubmission(slug);
    }
  }

  Future<void> _handleSlugSubmission(String slug) async {
    if (slug.isEmpty) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 1. Verify Slug with Backend via secure RPC
      // Use secure RPC that returns only public columns (no PII)
      final response = await SupabaseService.client.rpc(
        'get_public_business_by_slug_secure',
        params: {'p_slug': slug.trim().toLowerCase()},
      );

      if (response != null) {
        // 2. Valid Slug Found
        final profileMap = Map<String, dynamic>.from(response);

        // 3. Save Context & Persist
        await _slugResolver.saveSlug(slug);
        await SupabaseService.setBusinessContext(profileMap);

        // 4. Navigate to Shop
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => ShopPage(db: widget.db)),
          );
        }
      } else {
        if (mounted) {
          setState(() {
            _errorMessage =
                'Shop not found regarding "$slug". Please check and try again.';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Error connecting to shop: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _openQRScanner() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('Scan Shop QR')),
          body: MobileScanner(
            controller: MobileScannerController(
              detectionSpeed: DetectionSpeed.noDuplicates,
              returnImage: false,
              formats: [BarcodeFormat.qrCode],
            ),
            fit: BoxFit.cover,
            onDetect: (capture) {
              final List<Barcode> barcodes = capture.barcodes;
              for (final barcode in barcodes) {
                final String? rawValue = barcode.rawValue;
                if (rawValue != null) {
                  // Parse slug from URL if possible, else assume raw text is slug
                  final uri = Uri.tryParse(rawValue);
                  String? slug;
                  if (uri != null) {
                    // Support standard http links AND custom scheme myshop://
                    final isHttp = uri.scheme.startsWith('http');
                    final isCustom = uri.scheme == 'myshop';

                    if (isHttp || isCustom) {
                      // 1. Standard Path: https://domain.com/store/slug
                      if (uri.pathSegments.contains('store')) {
                        final idx = uri.pathSegments.indexOf('store');
                        if (idx + 1 < uri.pathSegments.length) {
                          slug = uri.pathSegments[idx + 1];
                        }
                      }
                      // 2. Custom Scheme: myshop://store/slug (host is 'store')
                      else if (uri.host == 'store' &&
                          uri.pathSegments.isNotEmpty) {
                        slug = uri.pathSegments.first;
                      }
                      // 3. Query Parameter: ?id=slug (for redirect links)
                      else if (uri.queryParameters.containsKey('id')) {
                        slug = uri.queryParameters['id'];
                      }
                    }
                  }

                  slug ??= rawValue; // Fallback to raw value

                  if (slug.isNotEmpty) {
                    Navigator.pop(context); // Close scanner
                    _slugController.text = slug; // Auto-fill
                    _handleSlugSubmission(slug); // Auto-submit
                  }
                }
              }
            },
            errorBuilder: (context, error, child) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error, color: Colors.red, size: 48),
                    const SizedBox(height: 12),
                    Text(
                      'Camera Error: ${error.errorCode}',
                      style: const TextStyle(color: Colors.white),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      error.errorDetails?.message ?? 'Unknown error',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: Stack(
        children: [
          // 1. Premium Gradient Background
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? [const Color(0xFF1a1a1a), const Color(0xFF2d2d2d)]
                    : [colorScheme.primary, colorScheme.secondary],
              ),
            ),
          ),

          // 2. Content
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // --- App Logo & Branding ---
                    Container(
                      padding: const EdgeInsets.all(4), // White border effect
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 30, // Softer, larger shadow
                            offset: const Offset(0, 15),
                          ),
                        ],
                      ),
                      child: ClipOval(
                        child: Image.asset(
                          'assets/icons/app_icon_shop.png',
                          height: 120,
                          width: 120,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Welcome to Shop',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Connect to your favorite local store',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: Colors.white.withOpacity(0.85),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 48),

                    // --- Action Card ---
                    Card(
                      elevation: 8,
                      shadowColor: Colors.black26,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      color: isDark ? const Color(0xFF333333) : Colors.white,
                      child: Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Enter Shop ID',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _slugController,
                              style: TextStyle(
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                              decoration: InputDecoration(
                                hintText: 'e.g. raj-electricals',
                                hintStyle: TextStyle(
                                  color: isDark ? Colors.white38 : Colors.grey,
                                ),
                                filled: true,
                                fillColor: isDark
                                    ? Colors.black12
                                    : Colors.grey.shade50,
                                prefixIcon: Icon(
                                  Icons.store_rounded,
                                  color: colorScheme.primary,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: BorderSide.none,
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 16,
                                ),
                                errorText: _errorMessage,
                              ),
                              onSubmitted: _handleSlugSubmission,
                            ),
                            const SizedBox(height: 24),
                            SizedBox(
                              height: 54,
                              child: FilledButton(
                                onPressed: _isLoading
                                    ? null
                                    : () => _handleSlugSubmission(
                                        _slugController.text,
                                      ),
                                style: FilledButton.styleFrom(
                                  backgroundColor: colorScheme.primary,
                                  foregroundColor: Colors
                                      .white, // Force white text on primary
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  elevation: 2,
                                ),
                                child: _isLoading
                                    ? const SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: const [
                                          Text(
                                            'Visit Store',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          SizedBox(width: 8),
                                          Icon(Icons.arrow_forward_rounded),
                                        ],
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 32),

                    // --- Divider ---
                    Row(
                      children: [
                        Expanded(
                          child: Divider(color: Colors.white.withOpacity(0.3)),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            'OR',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Divider(color: Colors.white.withOpacity(0.3)),
                        ),
                      ],
                    ),

                    const SizedBox(height: 32),

                    // --- QR Code Button ---
                    OutlinedButton.icon(
                      onPressed: _openQRScanner,
                      icon: const Icon(Icons.qr_code_scanner_rounded),
                      label: const Text('Scan QR Code'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(
                          color: Colors.white.withOpacity(0.5),
                          width: 1.5,
                        ),
                        padding: const EdgeInsets.symmetric(
                          vertical: 16,
                          horizontal: 32,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
