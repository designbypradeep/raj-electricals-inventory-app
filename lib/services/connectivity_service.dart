import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

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
    // RELAXED MODE: Trust the interface status primarily to avoid blocking valid users.
    // We update isOnline to true immediately if we have a network.
    if (!isOnline.value) {
      if (kDebugMode) {
        print('Connectivity: Interface detected, marking online.');
      }
      isOnline.value = true;
    }

    // Optional: We can still do a background check, but let's NOT block the user if it fails.
    // Just log it for now.
    try {
      final result = await InternetAddress.lookup('google.com');
      if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
        if (kDebugMode) print('Connectivity: DNS verified.');
      }
    } catch (_) {
      if (kDebugMode) {
        print('Connectivity: DNS check failed, but keeping online status.');
      }
    }
  }

  void dispose() {
    _subscription?.cancel();
    _pingTimer?.cancel();
    isOnline.dispose();
  }
}
