import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
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
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _slugController.dispose();
    super.dispose();
  }

  Future<void> _handleSlugSubmission(String slug) async {
    if (slug.isEmpty) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 1. Verify Slug with Backend via secure RPC
      final response = await SupabaseService.client.rpc(
        'get_public_business_by_slug',
        params: {'p_slug': slug.trim().toLowerCase()},
      );

      if (response != null) {
        // 2. Valid Slug Found
        final profileMap = Map<String, dynamic>.from(response);

        // 3. Save Context & Persist
        await _slugResolver.saveSlug(slug);
        SupabaseService.setBusinessContext(profileMap);

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
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.storefront_rounded,
                    size: 80,
                    color: Colors.blueAccent,
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Welcome to Shop App',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'To enter a store, scan their QR code or enter the Shop ID below.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, color: Colors.black54),
                  ),
                  const SizedBox(height: 48),

                  // Manual Entry
                  TextField(
                    controller: _slugController,
                    decoration: InputDecoration(
                      labelText: 'Shop ID (Slug)',
                      hintText: 'e.g. raj-electricals',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      errorText: _errorMessage,
                    ),
                    onSubmitted: _handleSlugSubmission,
                  ),
                  const SizedBox(height: 16),

                  FilledButton.icon(
                    onPressed: _isLoading
                        ? null
                        : () => _handleSlugSubmission(_slugController.text),
                    icon: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.arrow_forward),
                    label: const Text('Enter Shop'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),
                  const Row(
                    children: [
                      Expanded(child: Divider()),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Text('OR', style: TextStyle(color: Colors.grey)),
                      ),
                      Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 32),

                  // QR Scan Option
                  OutlinedButton.icon(
                    onPressed: _openQRScanner,
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Scan QR Code'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
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
}
