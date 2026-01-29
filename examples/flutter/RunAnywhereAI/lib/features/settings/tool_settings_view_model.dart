import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:runanywhere/public/runanywhere_tool_calling.dart';
import 'package:runanywhere/public/types/tool_calling_types.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Tool Settings ViewModel (mirroring iOS ToolSettingsViewModel)
///
/// Manages tool calling state and registered tools.
class ToolSettingsViewModel extends ChangeNotifier {
  // Singleton pattern (matches iOS)
  static final ToolSettingsViewModel shared = ToolSettingsViewModel._internal();

  factory ToolSettingsViewModel() => shared;

  ToolSettingsViewModel._internal() {
    unawaited(_loadSettings());
  }

  // State
  List<ToolDefinition> _registeredTools = [];
  bool _toolCallingEnabled = false;

  // Getters
  List<ToolDefinition> get registeredTools => _registeredTools;
  bool get toolCallingEnabled => _toolCallingEnabled;

  set toolCallingEnabled(bool value) {
    _toolCallingEnabled = value;
    unawaited(_saveSettings());
    notifyListeners();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _toolCallingEnabled = prefs.getBool('tool_calling_enabled') ?? false;
    await refreshRegisteredTools();
    notifyListeners();
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('tool_calling_enabled', _toolCallingEnabled);
  }

  Future<void> refreshRegisteredTools() async {
    _registeredTools = RunAnywhereTools.getRegisteredTools();
    notifyListeners();
  }

  /// Register demo tools (matches iOS implementation)
  Future<void> registerDemoTools() async {
    // 1. Weather Tool - Uses Open-Meteo API (free, no API key required)
    RunAnywhereTools.registerTool(
      const ToolDefinition(
        name: 'get_weather',
        description:
            'Gets the current weather for a given location using Open-Meteo API',
        parameters: [
          ToolParameter(
            name: 'location',
            type: ToolParameterType.string,
            description: "City name (e.g., 'San Francisco', 'London', 'Tokyo')",
          ),
        ],
      ),
      _fetchWeather,
    );

    // 2. Time Tool - Real system time with timezone
    RunAnywhereTools.registerTool(
      const ToolDefinition(
        name: 'get_current_time',
        description: 'Gets the current date, time, and timezone information',
        parameters: [],
      ),
      _getCurrentTime,
    );

    // 3. Calculator Tool - Real math evaluation
    RunAnywhereTools.registerTool(
      const ToolDefinition(
        name: 'calculate',
        description:
            'Performs math calculations. Supports +, -, *, /, and parentheses',
        parameters: [
          ToolParameter(
            name: 'expression',
            type: ToolParameterType.string,
            description: "Math expression (e.g., '2 + 2 * 3', '(10 + 5) / 3')",
          ),
        ],
      ),
      _calculate,
    );

    await refreshRegisteredTools();
  }

  Future<void> clearAllTools() async {
    RunAnywhereTools.clearTools();
    await refreshRegisteredTools();
  }

  // MARK: - Tool Executors

  /// Weather tool executor - fetches real weather data from Open-Meteo
  Future<Map<String, ToolValue>> _fetchWeather(
    Map<String, ToolValue> args,
  ) async {
    final rawLocation = args['location']?.stringValue;
    
    // Require location argument - no hardcoded defaults
    if (rawLocation == null || rawLocation.isEmpty) {
      return {
        'error': const StringToolValue('Missing required argument: location'),
      };
    }
    
    // Clean up location string - Open-Meteo works better with just city names
    // Remove common suffixes like ", CA", ", US", ", USA", etc.
    final location = _cleanLocationString(rawLocation);

    try {
      // Step 1: Geocode the location
      final geocodeUrl = Uri.parse(
        'https://geocoding-api.open-meteo.com/v1/search?name=${Uri.encodeComponent(location)}&count=5&language=en&format=json',
      );

      final geocodeResponse = await http.get(geocodeUrl);
      if (geocodeResponse.statusCode != 200) {
        throw Exception('Geocoding failed');
      }

      final geocodeData =
          jsonDecode(geocodeResponse.body) as Map<String, dynamic>;
      final results = geocodeData['results'] as List?;
      if (results == null || results.isEmpty) {
        return {
          'error': StringToolValue('Could not find location: $location'),
          'location': StringToolValue(location),
        };
      }

      final firstResult = results[0] as Map<String, dynamic>;
      final lat = firstResult['latitude'] as num;
      final lon = firstResult['longitude'] as num;
      final cityName = firstResult['name'] as String? ?? location;

      // Step 2: Fetch weather for coordinates
      final weatherUrl = Uri.parse(
        'https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current=temperature_2m,relative_humidity_2m,weather_code,wind_speed_10m&temperature_unit=fahrenheit&wind_speed_unit=mph',
      );

      final weatherResponse = await http.get(weatherUrl);
      if (weatherResponse.statusCode != 200) {
        throw Exception('Weather fetch failed');
      }

      final weatherData =
          jsonDecode(weatherResponse.body) as Map<String, dynamic>;
      final current = weatherData['current'] as Map<String, dynamic>;
      final temp = current['temperature_2m'] as num? ?? 0;
      final humidity = current['relative_humidity_2m'] as num? ?? 0;
      final windSpeed = current['wind_speed_10m'] as num? ?? 0;
      final weatherCode = current['weather_code'] as int? ?? 0;

      return {
        'location': StringToolValue(cityName),
        'temperature': NumberToolValue(temp.toDouble()),
        'unit': const StringToolValue('fahrenheit'),
        'humidity': NumberToolValue(humidity.toDouble()),
        'wind_speed_mph': NumberToolValue(windSpeed.toDouble()),
        'condition': StringToolValue(_weatherCodeToCondition(weatherCode)),
      };
    } catch (e) {
      return {
        'error': StringToolValue('Weather fetch failed: $e'),
        'location': StringToolValue(location),
      };
    }
  }

  String _weatherCodeToCondition(int code) {
    switch (code) {
      case 0:
        return 'Clear sky';
      case 1:
        return 'Mainly clear';
      case 2:
        return 'Partly cloudy';
      case 3:
        return 'Overcast';
      case 45:
      case 48:
        return 'Foggy';
      case 51:
      case 53:
      case 55:
        return 'Drizzle';
      case 56:
      case 57:
        return 'Freezing drizzle';
      case 61:
      case 63:
      case 65:
        return 'Rain';
      case 66:
      case 67:
        return 'Freezing rain';
      case 71:
      case 73:
      case 75:
        return 'Snow';
      case 77:
        return 'Snow grains';
      case 80:
      case 81:
      case 82:
        return 'Rain showers';
      case 85:
      case 86:
        return 'Snow showers';
      case 95:
        return 'Thunderstorm';
      case 96:
      case 99:
        return 'Thunderstorm with hail';
      default:
        return 'Unknown';
    }
  }

  /// Clean location string for better geocoding results
  /// Removes common suffixes like ", CA", ", US", state abbreviations, etc.
  String _cleanLocationString(String location) {
    var cleaned = location.trim();
    
    // Common patterns to remove: ", CA", ", NY", ", US", ", USA", ", United States"
    // Also handle variations like "CA" at the end
    final patterns = [
      RegExp(r',\s*(US|USA|United States)$', caseSensitive: false),
      RegExp(r',\s*[A-Z]{2}$'), // State abbreviations like ", CA", ", NY"
      RegExp(r',\s*[A-Z]{2},\s*(US|USA)$', caseSensitive: false), // ", CA, US"
    ];
    
    for (final pattern in patterns) {
      cleaned = cleaned.replaceAll(pattern, '');
    }
    
    // Also handle "SF" -> "San Francisco" for common abbreviations
    final abbreviations = {
      'SF': 'San Francisco',
      'NYC': 'New York City',
      'LA': 'Los Angeles',
      'DC': 'Washington DC',
    };
    
    final upperCleaned = cleaned.toUpperCase();
    if (abbreviations.containsKey(upperCleaned)) {
      return abbreviations[upperCleaned]!;
    }
    
    return cleaned;
  }

  /// Time tool executor
  Future<Map<String, ToolValue>> _getCurrentTime(
    Map<String, ToolValue> args,
  ) async {
    final now = DateTime.now();

    return {
      'datetime': StringToolValue(now.toString()),
      'time': StringToolValue(
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}',
      ),
      'timestamp': StringToolValue(now.toIso8601String()),
      'timezone': StringToolValue(now.timeZoneName),
      'utc_offset': StringToolValue(
        '${now.timeZoneOffset.isNegative ? '-' : '+'}${now.timeZoneOffset.inHours.abs().toString().padLeft(2, '0')}:${(now.timeZoneOffset.inMinutes.abs() % 60).toString().padLeft(2, '0')}',
      ),
    };
  }

  /// Calculator tool executor
  Future<Map<String, ToolValue>> _calculate(
    Map<String, ToolValue> args,
  ) async {
    // Try both 'expression' and 'input' keys - no hardcoded defaults
    final expression = args['expression']?.stringValue ?? args['input']?.stringValue;
    
    if (expression == null || expression.isEmpty) {
      return {
        'error': const StringToolValue('Missing required argument: expression'),
      };
    }

    try {
      // Clean the expression
      final cleanedExpression = expression
          .replaceAll('=', '')
          .replaceAll('x', '*')
          .replaceAll('×', '*')
          .replaceAll('÷', '/')
          .trim();

      final result = _evaluateExpression(cleanedExpression);

      return {
        'result': NumberToolValue(result),
        'expression': StringToolValue(expression),
      };
    } catch (e) {
      return {
        'error': StringToolValue('Could not evaluate expression: $expression'),
        'expression': StringToolValue(expression),
      };
    }
  }

  double _evaluateExpression(String expr) {
    // Remove spaces
    expr = expr.replaceAll(' ', '');

    // Handle simple operations
    if (expr.contains('+')) {
      final parts = expr.split('+');
      return parts.map((p) => double.parse(p)).reduce((a, b) => a + b);
    } else if (expr.contains('-') && !expr.startsWith('-')) {
      final parts = expr.split('-');
      var result = double.parse(parts[0]);
      for (var i = 1; i < parts.length; i++) {
        result -= double.parse(parts[i]);
      }
      return result;
    } else if (expr.contains('*')) {
      final parts = expr.split('*');
      return parts.map((p) => double.parse(p)).reduce((a, b) => a * b);
    } else if (expr.contains('/')) {
      final parts = expr.split('/');
      var result = double.parse(parts[0]);
      for (var i = 1; i < parts.length; i++) {
        result /= double.parse(parts[i]);
      }
      return result;
    }

    return double.parse(expr);
  }
}
