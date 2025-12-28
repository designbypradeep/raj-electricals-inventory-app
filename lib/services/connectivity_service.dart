import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ConnectivityService {
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal();

  final Connectivity _connectivity = Connectivity();
  final ValueNotifier<bool> isOnline = ValueNotifier<bool>(true);

  StreamSubscription<List<ConnectivityResult>>? _subscription;
  Timer? _pingTimer;

  Future<void> initialize() async {
    // Initial check
    await _checkConnection();

    // Listen for network changes
    _subscription = _connectivity.onConnectivityChanged.listen((results) {
      _checkConnection();
    });

    // Periodic ping to verify actual internet access (every 30 seconds)
    _pingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _checkConnection();
    });
  }

  Future<void> _checkConnection() async {
    bool hasNetwork = false;
    final results = await _connectivity.checkConnectivity();

    // Check if any interface is connected
    if (results.any((r) => r != ConnectivityResult.none)) {
      hasNetwork = true;
    }

    if (!hasNetwork) {
      if (isOnline.value) {
        if (kDebugMode) print('Connectivity: No network interface.');
        isOnline.value = false;
      }
      return;
    }

    // If we have a network interface, verify we can actually reach the internet
    // (Captive portals or dead wifi spots might show as connected but have no net)
    try {
      // Light ping to google dns
      final response = await http
          .get(Uri.parse('https://8.8.8.8'))
          .timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        if (!isOnline.value) {
          if (kDebugMode) print('Connectivity: Internet restored.');
          isOnline.value = true;
        }
      } else {
        // Fallback or specific status handling if needed
        _markOffline();
      }
    } catch (e) {
      // Try one more reliable host in case 8.8.8.8 blocks pings/http
      try {
        final response = await http
            .get(Uri.parse('https://www.google.com'))
            .timeout(const Duration(seconds: 3));
        if (response.statusCode == 200) {
          if (!isOnline.value) isOnline.value = true;
        } else {
          _markOffline();
        }
      } catch (_) {
        _markOffline();
      }
    }
  }

  void _markOffline() {
    if (isOnline.value) {
      if (kDebugMode) print('Connectivity: Network connected but no internet.');
      isOnline.value = false;
    }
  }

  void dispose() {
    _subscription?.cancel();
    _pingTimer?.cancel();
    isOnline.dispose();
  }
}
