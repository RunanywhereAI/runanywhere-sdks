import 'package:runanywhere_ai/core/utilities/constants.dart';
import 'package:runanywhere_ai/core/utilities/keychain_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Shared storage for the Hugging Face token used by NPU bundle downloads.
abstract final class HfTokenStore {
  HfTokenStore._();

  static Future<String> load() async {
    final storedToken = await KeychainHelper.loadString(KeychainKeys.hfToken);
    if (storedToken != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(PreferenceKeys.hfToken);
      return storedToken.trim();
    }

    final prefs = await SharedPreferences.getInstance();
    final legacyToken = prefs.getString(PreferenceKeys.hfToken);
    if (legacyToken == null) {
      return '';
    }

    final token = legacyToken.trim();
    if (token.isNotEmpty) {
      await KeychainHelper.saveString(key: KeychainKeys.hfToken, data: token);
    }
    await prefs.remove(PreferenceKeys.hfToken);
    return token;
  }

  static Future<void> save(String value) async {
    final token = value.trim();
    if (token.isEmpty) {
      await KeychainHelper.delete(KeychainKeys.hfToken);
    } else {
      await KeychainHelper.saveString(key: KeychainKeys.hfToken, data: token);
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(PreferenceKeys.hfToken);
  }
}
