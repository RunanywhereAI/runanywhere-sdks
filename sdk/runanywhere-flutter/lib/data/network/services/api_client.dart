/// API Client Protocol
abstract class APIClient {
  final Uri baseURL;
  final String apiKey;

  APIClient({required this.baseURL, required this.apiKey});

  /// Make a GET request
  Future<Map<String, dynamic>> get(String path);

  /// Make a POST request
  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> data);
}
