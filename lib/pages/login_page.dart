import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import '../services/supabase_service.dart';
import '../services/connectivity_service.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _isLoading = false;
  bool _isOTPMode = false;
  String _error = '';
  String _success = '';
  int _cooldownSecondsLeft = 0;
  Timer? _cooldownTimer;
  final List<TextEditingController> _otpControllers = List.generate(
    6,
    (index) => TextEditingController(),
  );
  final List<FocusNode> _otpFocusNodes = List.generate(
    6,
    (index) => FocusNode(),
  );

  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );

    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
          CurvedAnimation(parent: _slideController, curve: Curves.elasticOut),
        );

    _fadeController.forward();
    _slideController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    _emailController.dispose();
    for (var controller in _otpControllers) {
      controller.dispose();
    }
    for (var focusNode in _otpFocusNodes) {
      focusNode.dispose();
    }
    _cooldownTimer?.cancel();
    super.dispose();
  }

  String _friendlyError(Object e) {
    final msg = e.toString();
    // Hide internal URLs/stack traces and provide friendly guidance
    if (msg.contains('SocketException') ||
        msg.contains('Failed host lookup') ||
        msg.contains('No address associated with hostname')) {
      return 'Network error: Unable to reach the server.\nPlease check your internet connection or try again in a moment.';
    }
    if (msg.contains('statusCode: 429') ||
        msg.contains('over_email_send_rate_limit')) {
      return 'Please wait a few seconds before requesting another code.';
    }
    if (msg.contains('AuthRetryableFetchException') ||
        msg.contains('TimeoutException')) {
      return 'Temporary network issue. Please try again.';
    }
    // Generic fallback
    return msg.replaceAll('Exception: ', '');
  }

  void _startCooldown(int seconds) {
    _cooldownTimer?.cancel();
    setState(() {
      _cooldownSecondsLeft = seconds;
    });
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_cooldownSecondsLeft <= 1) {
        t.cancel();
        setState(() {
          _cooldownSecondsLeft = 0;
        });
      } else {
        setState(() {
          _cooldownSecondsLeft -= 1;
        });
      }
    });
  }

  Future<void> _sendOTP() async {
    if (!ConnectivityService().isOnline.value) {
      setState(() {
        _error = 'You are offline. Please check your internet connection.';
      });
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _error = '';
      _success = '';
    });

    try {
      // Send OTP using Supabase Auth
      await SupabaseService.sendOTP(_emailController.text.trim());

      if (mounted) {
        setState(() {
          _isOTPMode = true;
          _success = 'OTP sent to your email!';
        });
      }
      // Start a short cooldown to respect Supabase rate limits
      _startCooldown(10);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = _friendlyError(e);
        });
      }
      // If it's a rate-limit error, parse suggested wait seconds (if present)
      final msg = e.toString();
      if (msg.contains('statusCode: 429') ||
          msg.contains('over_email_send_rate_limit')) {
        final match = RegExp(r'after (\d+) seconds').firstMatch(msg);
        final seconds = match != null ? int.tryParse(match.group(1)!) ?? 5 : 5;
        _startCooldown(seconds);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _verifyOTP() async {
    String otpCode = _otpControllers
        .map((controller) => controller.text)
        .join();

    if (otpCode.length != 6) {
      setState(() => _error = 'Please enter the complete 6-digit code');
      return;
    }

    if (!ConnectivityService().isOnline.value) {
      setState(() {
        _error = 'You are offline. Cannot verify code.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = '';
    });

    try {
      final result = await SupabaseService.verifyOTP(
        _emailController.text.trim(),
        otpCode,
      );

      if (result['success']) {
        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/dashboard');
        }
      } else {
        setState(() {
          _error = result['message'] ?? 'Verification failed';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceAll('Exception: ', '');
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _goBack() {
    setState(() {
      _isOTPMode = false;
      _error = '';
      _success = '';
      for (var controller in _otpControllers) {
        controller.clear();
      }
    });
  }

  void _onOTPChanged(String value, int index) {
    // Handle pasted content (multiple digits)
    if (value.length > 1) {
      _handlePastedOTP(value, index);
      return;
    }

    if (value.isNotEmpty && index < 5) {
      _otpFocusNodes[index + 1].requestFocus();
    } else if (value.isEmpty && index > 0) {
      _otpFocusNodes[index - 1].requestFocus();
    }

    // Auto-verify when all 6 digits are entered
    String otpCode = _otpControllers
        .map((controller) => controller.text)
        .join();
    if (otpCode.length == 6) {
      _verifyOTP();
    }
  }

  void _handlePastedOTP(String pastedText, int startIndex) {
    // Extract only digits from pasted text
    String digits = pastedText.replaceAll(RegExp(r'[^0-9]'), '');

    // Clear all fields first
    for (var controller in _otpControllers) {
      controller.clear();
    }

    // Fill the fields with the digits
    for (int i = 0; i < digits.length && i < 6; i++) {
      _otpControllers[i].text = digits[i];
    }

    // Focus on the next empty field or the last field if all are filled
    int nextFocusIndex = digits.length < 6 ? digits.length : 5;
    if (nextFocusIndex < 6) {
      _otpFocusNodes[nextFocusIndex].requestFocus();
    }

    // Auto-verify if we have 6 digits
    if (digits.length == 6) {
      _verifyOTP();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0F172A), // Slate-900
              Color(0xFF1E293B), // Slate-800
              Color(0xFF334155), // Slate-700
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        color: Theme.of(context).colorScheme.surface,
                        border: Border.all(
                          color: Theme.of(
                            context,
                          ).colorScheme.outline.withValues(alpha: 0.3),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Theme.of(
                              context,
                            ).shadowColor.withValues(alpha: 0.12),
                            blurRadius: 24,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(40),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Logo and Title
                              Container(
                                width: 80,
                                height: 80,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      const Color(
                                        0xFFE07B39,
                                      ), // Terracotta Orange - Primary
                                      const Color(
                                        0xFFD86A28,
                                      ), // Darker Terracotta
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Icon(
                                  Icons.inventory_2,
                                  size: 40,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 24),
                              Text(
                                'Smart Inventory',
                                style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _isOTPMode
                                    ? 'Enter verification code'
                                    : 'Welcome back',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 32),

                              // Error Message
                              if (_error.isNotEmpty) ...[
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: Colors.red.shade200,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.error_outline,
                                        color: Colors.red.shade600,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          _error,
                                          style: TextStyle(
                                            color: Colors.red.shade700,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 16),
                              ],

                              // Success Message
                              if (_success.isNotEmpty) ...[
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: Colors.green.shade200,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.check_circle_outline,
                                        color: Colors.green.shade600,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          _success,
                                          style: TextStyle(
                                            color: Colors.green.shade700,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 16),
                              ],

                              if (!_isOTPMode) ...[
                                // Email Field
                                TextFormField(
                                  controller: _emailController,
                                  keyboardType: TextInputType.emailAddress,
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
                                  ),
                                  cursorColor: Theme.of(
                                    context,
                                  ).colorScheme.primary,
                                  decoration: InputDecoration(
                                    labelText: 'Email',
                                    hintText: 'Enter your email address',
                                    labelStyle: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                                    hintStyle: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant
                                          .withValues(alpha: 0.7),
                                    ),
                                    prefixIcon: Icon(
                                      Icons.email_outlined,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .outline
                                            .withValues(alpha: 0.6),
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                        width: 2,
                                      ),
                                    ),
                                    filled: true,
                                    fillColor: Theme.of(
                                      context,
                                    ).colorScheme.surface,
                                  ),
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'Please enter your email';
                                    }
                                    if (!RegExp(
                                      r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
                                    ).hasMatch(value)) {
                                      return 'Please enter a valid email';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 24),

                                // Send OTP Button
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    onPressed:
                                        (_isLoading || _cooldownSecondsLeft > 0)
                                        ? null
                                        : _sendOTP,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(
                                        0xFFE07B39,
                                      ), // Terracotta Orange
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 16,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      elevation: 2,
                                    ),
                                    child: _isLoading
                                        ? const SizedBox(
                                            height: 20,
                                            width: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : Text(
                                            _cooldownSecondsLeft > 0
                                                ? 'Send Code (${_cooldownSecondsLeft}s)'
                                                : 'Send Code',
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                  ),
                                ),
                              ] else ...[
                                // Back Button
                                Row(
                                  children: [
                                    TextButton.icon(
                                      onPressed: _isLoading ? null : _goBack,
                                      icon: const Icon(
                                        Icons.arrow_back,
                                        size: 18,
                                      ),
                                      label: const Text('Back'),
                                      style: TextButton.styleFrom(
                                        foregroundColor: Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),

                                // OTP Description
                                Text(
                                  'We sent a 6-digit code to ${_emailController.text}',
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 14,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 24),

                                // OTP Input Fields
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceEvenly,
                                  children: List.generate(6, (index) {
                                    return SizedBox(
                                      width: 45,
                                      height: 55,
                                      child: TextFormField(
                                        controller: _otpControllers[index],
                                        focusNode: _otpFocusNodes[index],
                                        keyboardType: TextInputType.number,
                                        textAlign: TextAlign.center,
                                        maxLength:
                                            6, // All fields can accept 6 digits for paste
                                        style: TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurface,
                                        ),
                                        cursorColor: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                        decoration: InputDecoration(
                                          counterText: '',
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          enabledBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            borderSide: BorderSide(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .outline
                                                  .withValues(alpha: 0.6),
                                            ),
                                          ),
                                          focusedBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            borderSide: BorderSide(
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.primary,
                                              width: 2,
                                            ),
                                          ),
                                          filled: true,
                                          fillColor: Theme.of(
                                            context,
                                          ).colorScheme.surface,
                                        ),
                                        inputFormatters: [
                                          FilteringTextInputFormatter
                                              .digitsOnly,
                                        ],
                                        onChanged: (value) =>
                                            _onOTPChanged(value, index),
                                      ),
                                    );
                                  }),
                                ),
                                const SizedBox(height: 24),

                                // Verify Button
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    onPressed: _isLoading ? null : _verifyOTP,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(
                                        0xFFE07B39,
                                      ), // Terracotta Orange
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 16,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      elevation: 2,
                                    ),
                                    child: _isLoading
                                        ? const SizedBox(
                                            height: 20,
                                            width: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : const Text(
                                            'Verify Code',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                  ),
                                ),
                                const SizedBox(height: 16),

                                // Resend Code
                                TextButton(
                                  onPressed:
                                      (_isLoading || _cooldownSecondsLeft > 0)
                                      ? null
                                      : _sendOTP,
                                  child: Text(
                                    _cooldownSecondsLeft > 0
                                        ? 'Resend in ${_cooldownSecondsLeft}s'
                                        : 'Resend code',
                                    style: TextStyle(
                                      color: const Color(
                                        0xFFE07B39,
                                      ), // Terracotta Orange
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
