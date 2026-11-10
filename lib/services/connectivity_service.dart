import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

class ConnectivityService with WidgetsBindingObserver {
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal();

  final Connectivity _connectivity = Connectivity();
  final ValueNotifier<bool> isOnline = ValueNotifier<bool>(true);

  StreamSubscription<List<ConnectivityResult>>? _subscription;
  Timer? _pingTimer;
  bool _isAppInForeground = true;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    try {
      WidgetsBinding.instance.addObserver(this);
    } catch (_) {}

    // Initial check
    await _checkConnection();

    // Listen for network changes
    _subscription = _connectivity.onConnectivityChanged.listen((results) {
      if (_isAppInForeground) {
        _checkConnection();
      }
    });

    // Periodic ping to verify actual internet access (every 30 seconds only while in foreground)
    _pingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_isAppInForeground) {
        _checkConnection();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _isAppInForeground = true;
      // Immediately re-verify on returning to foreground to clear any false-positive offline states
      _checkConnection();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _isAppInForeground = false;
    }
  }

  Future<void> _checkConnection() async {
    // If the app is suspended in the background, ignore checks to avoid Android OS
    // background socket throttling from falsely tripping offline alarms.
    if (!_isAppInForeground) return;

    final results = await _connectivity.checkConnectivity();
    bool hasNetwork = results.any((r) => r != ConnectivityResult.none);

    // Debounce: when switching apps, sockets momentarily disconnect/reconnect.
    // Wait 700ms and re-check before flagging the user as offline.
    if (!hasNetwork) {
      await Future.delayed(const Duration(milliseconds: 700));
      if (!_isAppInForeground) return;
      final retryResults = await _connectivity.checkConnectivity();
      hasNetwork = retryResults.any((r) => r != ConnectivityResult.none);
    }

    if (!hasNetwork) {
      if (isOnline.value) {
        if (kDebugMode) print('Connectivity: No network interface.');
        isOnline.value = false;
      }
      return;
    }

    // Interface detected: immediately mark online
    if (!isOnline.value) {
      if (kDebugMode) {
        print('Connectivity: Interface detected, marking online.');
      }
      isOnline.value = true;
    }

    // Background verify DNS without blocking or setting false offline
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
    try {
      WidgetsBinding.instance.removeObserver(this);
    } catch (_) {}
    _subscription?.cancel();
    _pingTimer?.cancel();
    _initialized = false;
  }
}
