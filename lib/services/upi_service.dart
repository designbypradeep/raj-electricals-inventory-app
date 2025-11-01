import 'dart:io' as io;
import 'package:flutter/services.dart';

class UpiService {
  static const MethodChannel _channel = MethodChannel(
    'com.raj_electricals/upi',
  );

  /// Starts a UPI payment using the native Android MethodChannel.
  /// Returns a map with parsed response fields and a `status` key
  /// (e.g., SUCCESS, FAILURE, SUBMITTED, CANCELLED, UNKNOWN), or null on error/unsupported.
  static Future<Map<String, dynamic>?> startUpiPayment(String uri) async {
    if (!io.Platform.isAndroid) return null;
    try {
      final res = await _channel.invokeMethod<dynamic>('startUpiPayment', {
        'uri': uri,
      });
      if (res is Map) {
        return Map<String, dynamic>.from(res.cast<String, dynamic>());
      }
      return null;
    } on PlatformException {
      return null;
    }
  }
}
