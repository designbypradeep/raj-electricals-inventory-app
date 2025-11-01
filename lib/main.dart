import 'package:flutter/material.dart';
import 'app.dart';
import 'package:raj_electricals_inventory_app/data/app_database.dart';
import 'package:raj_electricals_inventory_app/services/supabase_service.dart';

final AppDatabase database = AppDatabase();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Supabase with correct credentials from SvelteKit project
  await SupabaseService.initialize(
    url: 'https://oyilhssweqpicnmagmmn.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im95aWxoc3N3ZXFwaWNubWFnbW1uIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTM0MjkzOTIsImV4cCI6MjA2OTAwNTM5Mn0.d-qgWVuMzg3cvbKSHTFMJziduMZOTq-ewp3LyXKvSHQ',
  );
  
  runApp(RajElectricalsApp(database: database));
}
