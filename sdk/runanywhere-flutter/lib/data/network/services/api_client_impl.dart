import 'package:dio/dio.dart';
import 'api_client.dart';

/// API Client Implementation using Dio
class APIClientImpl extends APIClient {
  final Dio _dio;

  APIClientImpl({
    required super.baseURL,
    required super.apiKey,
  }) : _dio = Dio(
          BaseOptions(
            baseUrl: baseURL.toString(),
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
            connectTimeout: const Duration(seconds: 30),
            receiveTimeout: const Duration(seconds: 30),
          ),
        );

  @override
  Future<Map<String, dynamic>> get(String path) async {
    try {
      final response = await _dio.get(path);
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw Exception('API GET error: ${e.message}');
    }
  }

  @override
  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> data,
  ) async {
    try {
      final response = await _dio.post(path, data: data);
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw Exception('API POST error: ${e.message}');
    }
  }
}

