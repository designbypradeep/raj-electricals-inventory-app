import 'dart:async';

import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import '../services/security_service.dart';
import '../services/supabase_service.dart';

class BiometricLockGate extends StatefulWidget {
  final Widget child;
  const BiometricLockGate({super.key, required this.child});

  @override
  State<BiometricLockGate> createState() => _BiometricLockGateState();
}

class _BiometricLockGateState extends State<BiometricLockGate>
    with WidgetsBindingObserver {
  final _localAuth = LocalAuthentication();
  final _security = SecurityService();

  bool _locked = false;
  bool _requireBiometric = false;
  bool _deviceSupported = false;
  bool _checking = true;
  bool _authInProgress = false;

  // Grace window to avoid prompting too often
  DateTime? _lastUnlockAt;
  DateTime? _lastPausedAt;
  final Duration _graceDuration = const Duration(seconds: 60);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  Future<void> _init() async {
    final session = SupabaseService.supabase.auth.currentSession;
    if (session == null) {
      // Not logged in; no lock
      setState(() {
        _locked = false;
        _checking = false;
      });
      return;
    }

    final enabled = await _security.getRequireBiometric();
    final supported = await _localAuth.isDeviceSupported();

    setState(() {
      _requireBiometric = enabled;
      _deviceSupported = supported;
    });

    if (enabled && supported) {
      await _authenticate();
    }

    if (mounted) setState(() => _checking = false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _lastPausedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      _onResume();
    }
  }

  Future<void> _onResume() async {
    final session = SupabaseService.supabase.auth.currentSession;
    if (session == null) return;
    final enabled = await _security.getRequireBiometric();
    final supported = await _localAuth.isDeviceSupported();

    if (!(enabled && supported)) return;

    // If already locked, prompt
    if (_locked) {
      await _authenticate();
      return;
    }

    // Respect grace period
    final now = DateTime.now();
    final pausedAgo = _lastPausedAt != null
        ? now.difference(_lastPausedAt!)
        : null;
    final unlockedAgo = _lastUnlockAt != null
        ? now.difference(_lastUnlockAt!)
        : null;

    if (pausedAgo != null && pausedAgo < _graceDuration) return;
    if (unlockedAgo != null && unlockedAgo < _graceDuration) return;

    await _authenticate();
  }

  Future<void> _authenticate() async {
    if (_authInProgress) return;
    _authInProgress = true;
    try {
      final didAuth = await _localAuth.authenticate(
        localizedReason: 'Unlock to access the app',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
          useErrorDialogs: true,
        ),
      );
      if (mounted) {
        setState(() {
          _locked = !didAuth;
          if (didAuth) {
            _lastUnlockAt = DateTime.now();
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => _locked = true);
    } finally {
      _authInProgress = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) return widget.child;
    if (!_requireBiometric || !_deviceSupported) return widget.child;

    if (_locked) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock, size: 48),
              const SizedBox(height: 12),
              const Text(
                'Locked',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              const Text('Authenticate to continue'),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _authenticate,
                icon: const Icon(Icons.fingerprint),
                label: const Text('Unlock with biometrics'),
              ),
            ],
          ),
        ),
      );
    }

    return widget.child;
  }
}
