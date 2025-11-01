import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'data/app_database.dart';
import 'pages/shop_page.dart';
import 'services/supabase_service.dart';

final AppDatabase database = AppDatabase();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase (same as main.dart)
  await SupabaseService.initialize(
    url: 'https://oyilhssweqpicnmagmmn.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im95aWxoc3N3ZXFwaWNubWFnbW1uIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTM0MjkzOTIsImV4cCI6MjA2OTAwNTM5Mn0.d-qgWVuMzg3cvbKSHTFMJziduMZOTq-ewp3LyXKvSHQ',
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
