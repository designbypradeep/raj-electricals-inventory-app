import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:raj_electricals_inventory_app/pages/welcome_page.dart';
import 'package:raj_electricals_inventory_app/services/slug_resolver.dart';
import 'data/app_database.dart';
import 'pages/dashboard_page.dart';
import 'pages/login_page.dart';
import 'pages/business_settings_page.dart';
import 'pages/catalog_page.dart';
import 'pages/add_product_page.dart';
import 'pages/purchase_page.dart';
import 'pages/sales_page.dart';
import 'pages/returns_history_page.dart';
import 'pages/replacements_history_page.dart';
import 'pages/returns_page.dart';
import 'pages/process_replacement_page.dart';
import 'pages/shop_page.dart';
import 'pages/inventory_page.dart';
import 'pages/customers_page.dart';
import 'pages/payment_verification_page.dart';
import 'pages/status_blocked_page.dart';
import 'services/supabase_service.dart';
import 'models/supabase_models.dart' as supabase_models;
import 'services/connectivity_service.dart';
import 'services/theme_service.dart';
import 'services/theme_controller.dart';
import 'theme/status_colors.dart';
import 'theme/brand_accents.dart';
import 'widgets/biometric_lock_gate.dart';

import 'package:package_info_plus/package_info_plus.dart';

class RajElectricalsApp extends StatefulWidget {
  final AppDatabase database;
  const RajElectricalsApp({super.key, required this.database});

  @override
  State<RajElectricalsApp> createState() => _RajElectricalsAppState();
}

class _RajElectricalsAppState extends State<RajElectricalsApp> {
  late ThemeService _themeService;
  ThemeMode _themeMode = ThemeMode.system;
  final ThemeController _themeController = ThemeController.instance;
  late AppLinks _appLinks;
  StreamSubscription<Uri>? _appLinksSub;

  @override
  void initState() {
    super.initState();
    _themeService = ThemeService();
    _loadThemeMode();
    _themeController.addListener(_onThemeColorsChanged);
    _themeController.loadSavedColors();
    ConnectivityService().initialize();
    _initAppLinks();
  }

  void _initAppLinks() {
    _appLinks = AppLinks();
    _appLinks.getInitialLink().then((uri) {
      if (uri != null) _handleGlobalUri(uri);
    }).catchError((_) {});
    _appLinksSub = _appLinks.uriLinkStream.listen(_handleGlobalUri);
  }

  void _handleGlobalUri(Uri uri) {
    if (uri.scheme == 'io.supabase.rajinventory' || uri.scheme == 'inventoza') {
      SupabaseService.handleAuthCallbackUrl(uri).then((_) {
        if (mounted) setState(() {});
      }).catchError((e) {
        debugPrint('[App] Error handling OAuth callback: $e');
      });
    }
  }

  void _loadThemeMode() async {
    final themeMode = await _themeService.getThemeMode();
    setState(() {
      _themeMode = themeMode;
    });
  }

  void _changeThemeMode(ThemeMode themeMode) async {
    await _themeService.setThemeMode(themeMode);
    setState(() {
      _themeMode = themeMode;
    });
  }

  void _onThemeColorsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _appLinksSub?.cancel();
    _themeController.removeListener(_onThemeColorsChanged);
    ConnectivityService().dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Inventoza',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: _buildLightTheme(),
      darkTheme: _buildDarkTheme(),
      builder: (context, child) {
        return Stack(
          children: [
            if (child != null) child,
            ValueListenableBuilder<bool>(
              valueListenable: ConnectivityService().isOnline,
              builder: (context, isOnline, _) {
                if (isOnline) return const SizedBox.shrink();
                return Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Material(
                    color: Colors.red.shade700,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 4,
                        horizontal: 16,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.wifi_off, color: Colors.white, size: 16),
                          SizedBox(width: 8),
                          Text(
                            'No Internet Connection',
                            style: TextStyle(color: Colors.white, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
      initialRoute: '/',
      routes: {
        '/': (context) => FlavorWrapper(
          onThemeChanged: _changeThemeMode,
          database: widget.database,
        ),
        '/login': (context) => const LoginPage(),
        '/dashboard': (context) => BiometricLockGate(
          child: DashboardWrapper(
            onThemeChanged: _changeThemeMode,
            database: widget.database,
          ),
        ),
        '/home': (context) => BiometricLockGate(
          child: DashboardWrapper(
            onThemeChanged: _changeThemeMode,
            database: widget.database,
          ),
        ),
        '/inventory': (context) => const InventoryPage(),
        '/business-settings': (context) => const BusinessSettingsPage(),
        '/catalog': (context) => CatalogPage(db: widget.database),
        '/add-product': (context) => AddProductPage(db: widget.database),
        '/purchase': (context) => const PurchasePage(),
        '/sales': (context) => const SalesPage(),
        '/returns': (context) => ReturnsPage(db: widget.database),
        '/replacements': (context) =>
            ProcessReplacementPage(db: widget.database),
        '/shop': (context) => ShopPage(db: widget.database),
        '/returns-history': (context) => const ReturnsHistoryPage(),
        '/history/returns': (context) => const ReturnsHistoryPage(),
        '/replacements-history': (context) => const ReplacementsHistoryPage(),
        '/history/replacements': (context) => const ReplacementsHistoryPage(),
        '/payments/verification': (context) => const PaymentVerificationPage(),
        '/customers': (context) => const CustomersPage(),
        '/status-blocked': (context) =>
            const StatusBlockedPage(status: 'SUSPENDED'),
      },
    );
  }

  ThemeData _buildLightTheme() {
    final brandPrimary =
        _themeController.previewPrimary ??
        _themeController.savedPrimary ??
        const Color(0xFFC1441E);
    final brandSecondary =
        _themeController.previewSecondary ??
        _themeController.savedSecondary ??
        const Color(0xFF118AB2);
    const accent1 = Color(0xFFFFD166);
    const errorColor = Color(0xFFD62828);
    const background = Color(0xFFEFF3F6); // Darker Cool Grey for contrast
    const surface = Color(0xFFFFFFFF);
    const onSurface = Color(0xFF1E1E1E);
    const outline = Color(0xFFE2E8F0);

    final scheme =
        ColorScheme.fromSeed(
          seedColor: brandPrimary,
          brightness: Brightness.light,
        ).copyWith(
          primary: brandPrimary,
          onPrimary: Colors.white,
          secondary: brandSecondary,
          onSecondary: Colors.white,
          error: errorColor,
          onError: Colors.white,
          surface: surface,
          surfaceContainerLow: const Color(0xFFFFF9F6), // Warm tint for cards
          onSurface: onSurface,
          tertiary: accent1,
          onTertiary: onSurface,
          outline: outline,
        );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      cardColor: surface,
      dividerColor: outline,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: onSurface,
        elevation: 0,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbVisibility: WidgetStateProperty.all(true),
        trackVisibility: WidgetStateProperty.all(true),
        thumbColor: WidgetStateProperty.all(brandPrimary),
        trackColor: WidgetStateProperty.all(
          brandPrimary.withValues(alpha: 0.2),
        ),
        radius: const Radius.circular(4),
        thickness: WidgetStateProperty.all(8),
      ),
      extensions: const <ThemeExtension<dynamic>>[
        StatusColors.light,
        BrandAccents.light,
      ],
    );
  }

  ThemeData _buildDarkTheme() {
    final brandPrimary =
        _themeController.previewPrimary ??
        _themeController.savedPrimary ??
        const Color(0xFFC1441E);
    // If user set a secondary, use same in dark; else fall back to dark default
    final brandSecondary =
        _themeController.previewSecondary ??
        _themeController.savedSecondary ??
        const Color(0xFF5EC2E8); // lighter blue variant for dark
    const accent1 = Color(0xFFFFD166);
    const errorColor = Color(0xFFFF6B6B); // lighter red for visibility

    final scheme =
        ColorScheme.fromSeed(
          seedColor: brandPrimary,
          brightness: Brightness.dark,
        ).copyWith(
          primary: brandPrimary,
          onPrimary: Colors.white,
          secondary: brandSecondary,
          onSecondary: Colors.white,
          error: errorColor,
          onError: Colors.white,
          surface: const Color(0xFF2C2C2C),
          onSurface: Colors.white,
          tertiary: accent1,
          onTertiary: Colors.black,
          outline: const Color(0xFF444444),
        );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFF1C1C1C),
      cardColor: const Color(0xFF2C2C2C),
      dividerColor: const Color(0xFF444444),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF1E1E1E),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbVisibility: WidgetStateProperty.all(true),
        trackVisibility: WidgetStateProperty.all(true),
        thumbColor: WidgetStateProperty.all(brandPrimary),
        trackColor: WidgetStateProperty.all(
          brandPrimary.withValues(alpha: 0.2),
        ),
        radius: const Radius.circular(4),
        thickness: WidgetStateProperty.all(8),
      ),
      extensions: const <ThemeExtension<dynamic>>[
        StatusColors.dark,
        BrandAccents.dark,
      ],
    );
  }
}

class FlavorWrapper extends StatefulWidget {
  final Function(ThemeMode) onThemeChanged;
  final AppDatabase database;
  const FlavorWrapper({
    super.key,
    required this.onThemeChanged,
    required this.database,
  });

  @override
  State<FlavorWrapper> createState() => _FlavorWrapperState();
}

class _FlavorWrapperState extends State<FlavorWrapper> {
  bool? _isShopFlavor;
  bool _isShopResolved = false;

  @override
  void initState() {
    super.initState();
    _checkFlavor();
  }

  Future<void> _checkFlavor() async {
    final packageInfo = await PackageInfo.fromPlatform();
    const appType = String.fromEnvironment('APP_TYPE');
    final isShop = appType == 'shop' ||
        packageInfo.packageName.endsWith('.shop') ||
        appFlavor == 'shop';

    if (isShop) {
      // 1. Runtime Slug Resolution
      try {
        final slugResolver = SlugResolver();
        final slug = await slugResolver.resolveInitialSlug();

        if (slug != null && slug.isNotEmpty) {
          try {
            // 2. Validate & Load Context (secure RPC - no PII)
            // Attempt online fetch first
            final response = await SupabaseService.client
                .rpc(
                  'get_public_business_by_slug_secure',
                  params: {'p_slug': slug},
                )
                .timeout(const Duration(seconds: 5)); // Fail fast for offline

            if (response != null) {
              final profileMap = Map<String, dynamic>.from(response);
              await SupabaseService.setBusinessContext(profileMap);
              if (mounted) {
                setState(() {
                  _isShopResolved = true;
                });
              }
              // Found online, proceed to set shop flavor below
            }
          } catch (e) {
            debugPrint('Error resolving shop slug online: $e');
            // Fallthrough to offline cache check
          }

          if (!_isShopResolved) {
            // 3. Offline Caching Fallback
            // If network failed or timed out, try to load last valid profile
            final cached = await SupabaseService.loadBusinessContextFromCache();
            if (cached) {
              if (mounted) {
                setState(() {
                  _isShopResolved = true;
                });
              }
            }
          }
        }
      } catch (e) {
        debugPrint('Error resolving shop slug: $e');
      }
    }

    if (mounted) {
      setState(() {
        _isShopFlavor = isShop;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isShopFlavor == null) {
      return const Scaffold(
        backgroundColor: Color(0xFFF8FAFC),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_isShopFlavor == true) {
      if (_isShopResolved) {
        return ShopPage(db: widget.database);
      } else {
        return WelcomePage(db: widget.database);
      }
    }

    return AuthWrapper(
      onThemeChanged: widget.onThemeChanged,
      database: widget.database,
    );
  }
}

class AuthWrapper extends StatelessWidget {
  final Function(ThemeMode) onThemeChanged;
  final AppDatabase database;
  const AuthWrapper({
    super.key,
    required this.onThemeChanged,
    required this.database,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: SupabaseService.supabase.auth.onAuthStateChange,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Color(0xFFF8FAFC),
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final session = SupabaseService.supabase.auth.currentSession;
        if (session != null) {
          return BiometricLockGate(
            child: DashboardWrapper(
              onThemeChanged: onThemeChanged,
              database: database,
            ),
          );
        } else {
          return const LoginPage();
        }
      },
    );
  }
}

class DashboardWrapper extends StatefulWidget {
  final Function(ThemeMode) onThemeChanged;
  final AppDatabase database;
  const DashboardWrapper({
    super.key,
    required this.onThemeChanged,
    required this.database,
  });

  @override
  State<DashboardWrapper> createState() => _DashboardWrapperState();
}

class _DashboardWrapperState extends State<DashboardWrapper> {
  int _refreshKey = 0;

  @override
  void initState() {
    super.initState();
    ConnectivityService().isOnline.addListener(_onConnectivityChanged);
  }

  @override
  void dispose() {
    ConnectivityService().isOnline.removeListener(_onConnectivityChanged);
    super.dispose();
  }

  void _onConnectivityChanged() {
    if (ConnectivityService().isOnline.value) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Back online! Reloading dashboard...'),
            duration: Duration(seconds: 2),
            backgroundColor: Colors.green,
          ),
        );
        setState(() {
          _refreshKey++;
        });
      }
    }
  }

  Future<dynamic> _loadProfileSafely() async {
    try {
      // 1. Try Fetch
      var p = await SupabaseService.getCurrentBusinessProfile();

      // 2. If success, cache it explicitly because SupabaseService might not be doing it automatically
      if (p != null) {
        try {
          // We need to construct a map or use a method to cache.
          // Since SupabaseService.setBusinessContext is public and handles caching:
          await SupabaseService.setBusinessContext(p.toJson());
        } catch (_) {
          // implicit caching failed, but we have the profile, so proceed
        }
      }

      // 3. If null, check cache (SupabaseService might swallow error -> null)
      if (p == null) {
        final loaded = await SupabaseService.loadBusinessContextFromCache();
        if (loaded) {
          p = SupabaseService.cachedBusinessProfile;
        }
      }
      return p;
    } catch (e) {
      // 4. If explicit error (timeout/socket), try cache
      final loaded = await SupabaseService.loadBusinessContextFromCache();
      if (loaded) {
        return SupabaseService.cachedBusinessProfile;
      }
      // If no cache, rethrow to show Dashboard (empty/error state) instead of BusinessSettings
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      key: ValueKey('dashboard_$_refreshKey'),
      future: _loadProfileSafely(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Color(0xFFF8FAFC),
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // If error (and no cache found in catch), fallback to DashboardPage
        // effectively treating it as "Offline / Error" rather than "No Business"
        if (snapshot.hasError) {
          return DashboardPage(
            db: widget.database,
            onThemeChanged: widget.onThemeChanged,
          );
        }

        final businessProfile = snapshot.data;
        // Only if we explicitly got NULL and NO CACHE do we show BusinessSettings.
        // This likely means: Online + Success + No Profile row found.
        if (businessProfile == null) {
          return const BusinessSettingsPage();
        }

        if (businessProfile is supabase_models.BusinessProfile) {
          if (businessProfile.isSuspended || businessProfile.isPending) {
            return StatusBlockedPage(
              status: businessProfile.status ?? 'SUSPENDED',
              onStatusRefreshed: () {
                setState(() {
                  _refreshKey++;
                });
              },
            );
          }
        }

        return DashboardPage(
          db: widget.database,
          onThemeChanged: widget.onThemeChanged,
        );
      },
    );
  }
}
