import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:async';
import 'app.dart';
import 'package:raj_electricals_inventory_app/data/app_database.dart';
import 'package:raj_electricals_inventory_app/services/supabase_service.dart';

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

void main() async {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // Fix for HandshakeException (SSL error) on some networks/devices
      HttpOverrides.global = GlobalHttpOverrides();

      // Initialize Supabase (anon key is public by design - security via RLS/RPCs)
      await SupabaseService.initialize(
        url: _supabaseUrl,
        anonKey: _supabaseAnonKey,
      );

      runApp(RajElectricalsApp(database: database));
    },
    (error, stack) {
      debugPrint(
        '\n\n!!! CRITICAL STARTUP ERROR !!!\n$error\n$stack\n!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n\n',
      );
    },
  );
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
