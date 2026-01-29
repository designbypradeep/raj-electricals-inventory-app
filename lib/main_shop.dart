import 'package:flutter/material.dart';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'data/app_database.dart';
import 'pages/shop_page.dart';
import 'services/supabase_service.dart';

final AppDatabase database = AppDatabase();

// Supabase credentials - anon key is intentionally public (security via RLS/RPCs)
// Override via --dart-define if needed for different environments
const String _supabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'https://oyilhssweqpicnmagmmn.supabase.co',
);
const String _supabaseAnonKey = String.fromEnvironment(
  'SUPABASE_ANON_KEY',
  defaultValue:
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im95aWxoc3N3ZXFwaWNubWFnbW1uIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTM0MjkzOTIsImV4cCI6MjA2OTAwNTM5Mn0.d-qgWVuMzg3cvbKSHTFMJziduMZOTq-ewp3LyXKvSHQ',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = GlobalHttpOverrides();

  // Initialize Supabase (anon key is public by design - security via RLS/RPCs)
  await SupabaseService.initialize(
    url: _supabaseUrl,
    anonKey: _supabaseAnonKey,
  );

  // Public Shop mode: set default business ID via --dart-define=BUSINESS_ID=<uuid>
  const defaultBusinessId = String.fromEnvironment(
    'BUSINESS_ID',
    defaultValue: '',
  );
  if (defaultBusinessId.isNotEmpty) {
    SupabaseService.setDefaultBusinessId(defaultBusinessId);
  } else {
    // Fallback: load from local preferences if previously saved in-app
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('DEFAULT_BUSINESS_ID') ?? '';
      if (saved.isNotEmpty) {
        SupabaseService.setDefaultBusinessId(saved);
      }
    } catch (_) {}
  }

  runApp(const ShopOnlyApp());
}

class ShopOnlyApp extends StatelessWidget {
  const ShopOnlyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Raj Electricals Shop',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFC1441E)),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFC1441E),
          brightness: Brightness.dark,
        ),
      ),
      home: ShopPage(db: database),
    );
  }
}

class GlobalHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback =
          ((X509Certificate cert, String host, int port) => true)
      ..userAgent =
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
  }
}
