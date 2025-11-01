import 'package:shared_preferences/shared_preferences.dart';

class SecurityService {
  static const _biometricKey = 'require_biometric_lock';

  Future<bool> getRequireBiometric() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_biometricKey) ?? false;
  }

  Future<void> setRequireBiometric(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_biometricKey, value);
  }
}
