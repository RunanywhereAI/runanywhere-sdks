import 'package:runanywhere_ai/core/models/proxy_settings.dart';
import 'package:runanywhere_ai/core/utilities/constants.dart';
import 'package:runanywhere_ai/core/utilities/keychain_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProxySettingsValidationResult {
  final bool isValid;
  final String? message;

  const ProxySettingsValidationResult.valid()
      : isValid = true,
        message = null;

  const ProxySettingsValidationResult.invalid(this.message) : isValid = false;
}

class ProxySettingsService {
  static final ProxySettingsService shared = ProxySettingsService._internal();

  ProxySettingsService._internal();

  final Map<ProxyScope, ProxySettings> _current = {
    ProxyScope.general: const ProxySettings(),
    ProxyScope.download: const ProxySettings(),
  };

  ProxySettings getCurrent(ProxyScope scope) => _current[scope]!;

  Future<ProxySettings> load(ProxyScope scope) async {
    final prefs = await SharedPreferences.getInstance();
    final username = await KeychainHelper.loadString(_usernameKey(scope)) ?? '';
    final password = await KeychainHelper.loadString(_passwordKey(scope)) ?? '';

    final enabled = prefs.getBool(_enabledKey(scope));
    final scheme = prefs.getString(_schemeKey(scope));
    final host = prefs.getString(_hostKey(scope));
    final port = prefs.getInt(_portKey(scope));
    final bypassLocal = prefs.getBool(_bypassLocalKey(scope));
    final hasScopedPreferences = enabled != null ||
        scheme != null ||
        host != null ||
        port != null ||
        bypassLocal != null;

    ProxySettings settings;
    if (scope == ProxyScope.general && !hasScopedPreferences) {
      settings = await _loadLegacyGeneralSettings(prefs);
    } else {
      settings = ProxySettings(
        enabled: enabled ?? false,
        scheme: ProxyScheme.fromWireValue(scheme),
        host: host ?? '',
        port: port,
        username: username,
        password: password,
        bypassLocal: bypassLocal ?? true,
      );
    }

    _current[scope] = settings;
    return settings;
  }

  ProxySettingsValidationResult validate(ProxySettings settings) {
    if (!settings.enabled) {
      return const ProxySettingsValidationResult.valid();
    }

    if (!settings.scheme.isSupportedInExampleApp) {
      return const ProxySettingsValidationResult.invalid(
        'SOCKS5 is temporarily disabled in the Flutter example app.',
      );
    }

    if (settings.host.trim().isEmpty) {
      return const ProxySettingsValidationResult.invalid(
        'Proxy host is required.',
      );
    }

    final port = settings.port;
    if (port == null || port < 1 || port > 65535) {
      return const ProxySettingsValidationResult.invalid(
        'Proxy port must be between 1 and 65535.',
      );
    }

    final username = settings.username.trim();
    final password = settings.password.trim();
    if ((username.isEmpty && password.isNotEmpty) ||
        (username.isNotEmpty && password.isEmpty)) {
      return const ProxySettingsValidationResult.invalid(
        'Username and password must be provided together.',
      );
    }

    return const ProxySettingsValidationResult.valid();
  }

  Future<ProxySettingsValidationResult> save(
    ProxyScope scope,
    ProxySettings settings,
  ) async {
    final validation = validate(settings);
    if (!validation.isValid) {
      return validation;
    }

    final normalizedUsername = settings.username.trim();
    final normalizedPassword = settings.password.trim();
    final normalizedSettings = settings.copyWith(
      username: normalizedUsername,
      password: normalizedPassword,
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey(scope), normalizedSettings.enabled);
    await prefs.setString(
        _schemeKey(scope), normalizedSettings.scheme.wireValue);
    await prefs.setString(_hostKey(scope), normalizedSettings.host.trim());

    if (normalizedSettings.port != null) {
      await prefs.setInt(_portKey(scope), normalizedSettings.port!);
    } else {
      await prefs.remove(_portKey(scope));
    }

    await prefs.setBool(
      _bypassLocalKey(scope),
      normalizedSettings.bypassLocal,
    );

    if (normalizedUsername.isNotEmpty) {
      await KeychainHelper.saveString(
        key: _usernameKey(scope),
        data: normalizedUsername,
      );
      await KeychainHelper.saveString(
        key: _passwordKey(scope),
        data: normalizedPassword,
      );
    } else {
      await KeychainHelper.delete(_usernameKey(scope));
      await KeychainHelper.delete(_passwordKey(scope));
    }

    _current[scope] = normalizedSettings;
    return const ProxySettingsValidationResult.valid();
  }

  Future<void> clear(ProxyScope scope) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_enabledKey(scope));
    await prefs.remove(_schemeKey(scope));
    await prefs.remove(_hostKey(scope));
    await prefs.remove(_portKey(scope));
    await prefs.remove(_bypassLocalKey(scope));
    if (scope == ProxyScope.general) {
      await prefs.remove(PreferenceKeys.proxyEnabled);
      await prefs.remove(PreferenceKeys.proxyScheme);
      await prefs.remove(PreferenceKeys.proxyHost);
      await prefs.remove(PreferenceKeys.proxyPort);
      await prefs.remove(PreferenceKeys.proxyBypassLocal);
    }
    await KeychainHelper.delete(_usernameKey(scope));
    await KeychainHelper.delete(_passwordKey(scope));
    _current[scope] = const ProxySettings();
  }

  String _enabledKey(ProxyScope scope) {
    return switch (scope) {
      ProxyScope.general => PreferenceKeys.proxyGeneralEnabled,
      ProxyScope.download => PreferenceKeys.proxyDownloadEnabled,
    };
  }

  String _schemeKey(ProxyScope scope) {
    return switch (scope) {
      ProxyScope.general => PreferenceKeys.proxyGeneralScheme,
      ProxyScope.download => PreferenceKeys.proxyDownloadScheme,
    };
  }

  String _hostKey(ProxyScope scope) {
    return switch (scope) {
      ProxyScope.general => PreferenceKeys.proxyGeneralHost,
      ProxyScope.download => PreferenceKeys.proxyDownloadHost,
    };
  }

  String _portKey(ProxyScope scope) {
    return switch (scope) {
      ProxyScope.general => PreferenceKeys.proxyGeneralPort,
      ProxyScope.download => PreferenceKeys.proxyDownloadPort,
    };
  }

  String _bypassLocalKey(ProxyScope scope) {
    return switch (scope) {
      ProxyScope.general => PreferenceKeys.proxyGeneralBypassLocal,
      ProxyScope.download => PreferenceKeys.proxyDownloadBypassLocal,
    };
  }

  String _usernameKey(ProxyScope scope) {
    return switch (scope) {
      ProxyScope.general => KeychainKeys.proxyGeneralUsername,
      ProxyScope.download => KeychainKeys.proxyDownloadUsername,
    };
  }

  String _passwordKey(ProxyScope scope) {
    return switch (scope) {
      ProxyScope.general => KeychainKeys.proxyGeneralPassword,
      ProxyScope.download => KeychainKeys.proxyDownloadPassword,
    };
  }

  Future<ProxySettings> _loadLegacyGeneralSettings(
    SharedPreferences prefs,
  ) async {
    final username =
        await KeychainHelper.loadString(KeychainKeys.proxyGeneralUsername) ??
            '';
    final password =
        await KeychainHelper.loadString(KeychainKeys.proxyGeneralPassword) ??
            '';

    return ProxySettings(
      enabled: prefs.getBool(PreferenceKeys.proxyEnabled) ?? false,
      scheme: ProxyScheme.fromWireValue(
        prefs.getString(PreferenceKeys.proxyScheme),
      ),
      host: prefs.getString(PreferenceKeys.proxyHost) ?? '',
      port: prefs.getInt(PreferenceKeys.proxyPort),
      username: username,
      password: password,
      bypassLocal: prefs.getBool(PreferenceKeys.proxyBypassLocal) ?? true,
    );
  }
}
