enum ProxyScope {
  general('Network Proxy'),
  download('Download Proxy');

  final String displayName;

  const ProxyScope(this.displayName);
}

enum ProxyScheme {
  http('HTTP'),
  https('HTTPS'),
  socks5('SOCKS5');

  final String displayName;

  const ProxyScheme(this.displayName);

  String get wireValue => name;

  static ProxyScheme fromWireValue(String? value) {
    return ProxyScheme.values.firstWhere(
      (scheme) => scheme.wireValue == value,
      orElse: () => ProxyScheme.http,
    );
  }
}

class ProxySettings {
  final bool enabled;
  final ProxyScheme scheme;
  final String host;
  final int? port;
  final String username;
  final String password;
  final bool bypassLocal;

  const ProxySettings({
    this.enabled = false,
    this.scheme = ProxyScheme.http,
    this.host = '',
    this.port,
    this.username = '',
    this.password = '',
    this.bypassLocal = true,
  });

  bool get hasCredentials => username.isNotEmpty || password.isNotEmpty;

  bool get isComplete => !enabled || (host.trim().isNotEmpty && port != null);

  ProxySettings copyWith({
    bool? enabled,
    ProxyScheme? scheme,
    String? host,
    int? port,
    String? username,
    String? password,
    bool? bypassLocal,
  }) {
    return ProxySettings(
      enabled: enabled ?? this.enabled,
      scheme: scheme ?? this.scheme,
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      password: password ?? this.password,
      bypassLocal: bypassLocal ?? this.bypassLocal,
    );
  }
}
