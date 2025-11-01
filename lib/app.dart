import 'package:flutter/material.dart';
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
import 'services/supabase_service.dart';
import 'services/theme_service.dart';
import 'services/theme_controller.dart';
import 'theme/status_colors.dart';
import 'theme/brand_accents.dart';
import 'widgets/biometric_lock_gate.dart';

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

  @override
  void initState() {
    super.initState();
    _themeService = ThemeService();
    _loadThemeMode();
    _themeController.addListener(_onThemeColorsChanged);
    _themeController.loadSavedColors();
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
    _themeController.removeListener(_onThemeColorsChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Inventory',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: _buildLightTheme(),
      darkTheme: _buildDarkTheme(),
      initialRoute: '/',
      routes: {
        '/': (context) => AuthWrapper(
          onThemeChanged: _changeThemeMode,
          database: widget.database,
        ),
        '/login': (context) => const LoginPage(),
        '/dashboard': (context) => DashboardPage(
          db: widget.database,
          onThemeChanged: _changeThemeMode,
        ),
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
    const background = Color(0xFFF9F5F3);
    const surface = Color(0xFFFFFFFF);
    const onSurface = Color(0xFF1E1E1E);
    const outline = Color(0xFFE0E0E0);

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
          onSurface: onSurface,
          tertiary: accent1, // Warning/Accent
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
        trackColor: WidgetStateProperty.all(brandPrimary.withOpacity(0.2)),
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
        trackColor: WidgetStateProperty.all(brandPrimary.withOpacity(0.2)),
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

class DashboardWrapper extends StatelessWidget {
  final Function(ThemeMode) onThemeChanged;
  final AppDatabase database;
  const DashboardWrapper({
    super.key,
    required this.onThemeChanged,
    required this.database,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: SupabaseService.getCurrentBusinessProfile(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Color(0xFFF8FAFC),
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // If there was an error (e.g., offline), do NOT return BusinessSettings
        // as the root. Show Dashboard so it can display its offline view/skeleton.
        if (snapshot.hasError) {
          return DashboardPage(db: database, onThemeChanged: onThemeChanged);
        }

        final businessProfile = snapshot.data;
        if (businessProfile == null) {
          // Only treat as setup-needed when request succeeded but profile is actually null.
          return const BusinessSettingsPage();
        }
        return DashboardPage(db: database, onThemeChanged: onThemeChanged);
      },
    );
  }
}
