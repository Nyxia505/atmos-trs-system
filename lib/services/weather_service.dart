import 'dart:convert';

import 'package:http/http.dart' as http;

/// Live weather for Misamis Occidental (province center) via [Open-Meteo](https://open-meteo.com/) — no API key.
class MisamisOccidentalWeather {
  MisamisOccidentalWeather({
    required this.temperatureC,
    required this.humidityPercent,
    required this.windSpeedKmh,
    required this.weatherCode,
    required this.conditionLabel,
    required this.hint,
  });

  final double temperatureC;
  final int humidityPercent;
  final double windSpeedKmh;
  final int weatherCode;
  final String conditionLabel;
  final String hint;

  String get temperatureDisplay => '${temperatureC.round()}°C';
  String get humidityDisplay => '$humidityPercent%';
  String get windDisplay => '${windSpeedKmh.round()} km/h';
  String get subtitle => '$conditionLabel · $hint';

  /// When the API fails, show sensible defaults so the card still looks correct.
  static MisamisOccidentalWeather fallback() {
    return MisamisOccidentalWeather(
      temperatureC: 28,
      humidityPercent: 65,
      windSpeedKmh: 12,
      weatherCode: 0,
      conditionLabel: 'Sunny',
      hint: 'Great day to explore',
    );
  }

  /// Approximate center of Misamis Occidental (matches home map / VR preview).
  static const double latitude = 8.3377;
  static const double longitude = 123.7072;

  static Future<MisamisOccidentalWeather> fetch() async {
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': latitude.toString(),
      'longitude': longitude.toString(),
      'current':
          'temperature_2m,relative_humidity_2m,weather_code,wind_speed_10m',
      'wind_speed_unit': 'kmh',
      'timezone': 'Asia/Manila',
    });

    final response = await http.get(uri).timeout(
          const Duration(seconds: 12),
          onTimeout: () =>
              throw Exception('Weather request timed out. Check your connection.'),
        );

    if (response.statusCode != 200) {
      throw Exception('Weather unavailable (${response.statusCode})');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final current = json['current'] as Map<String, dynamic>?;
    if (current == null) {
      throw Exception('Invalid weather response');
    }

    final temp = (current['temperature_2m'] as num?)?.toDouble() ?? 28.0;
    final humidityRaw = (current['relative_humidity_2m'] as num?)?.round() ?? 65;
    final humidity = humidityRaw.clamp(0, 100);
    final wind = (current['wind_speed_10m'] as num?)?.toDouble() ?? 12.0;
    final code = (current['weather_code'] as num?)?.toInt() ?? 0;

    final labelHint = _labelAndHintForWmoCode(code);
    return MisamisOccidentalWeather(
      temperatureC: temp,
      humidityPercent: humidity,
      windSpeedKmh: wind < 0 ? 0 : wind,
      weatherCode: code,
      conditionLabel: labelHint.$1,
      hint: labelHint.$2,
    );
  }

  /// WMO Weather interpretation codes (Open-Meteo).
  static (String, String) _labelAndHintForWmoCode(int code) {
    if (code == 0) {
      return ('Clear', 'Great day to explore');
    }
    if (code == 1) {
      return ('Mainly clear', 'Nice weather for sightseeing');
    }
    if (code == 2) {
      return ('Partly cloudy', 'Comfortable for outdoor plans');
    }
    if (code == 3) {
      return ('Overcast', 'Good for museums & indoor spots');
    }
    if (code == 45 || code == 48) {
      return ('Foggy', 'Drive carefully if heading out');
    }
    if (code >= 51 && code <= 57) {
      return ('Drizzle', 'Bring a light jacket');
    }
    if (code >= 61 && code <= 67) {
      return ('Rain', 'Pack an umbrella');
    }
    if (code >= 71 && code <= 77) {
      return ('Snow', 'Dress warmly');
    }
    if (code >= 80 && code <= 82) {
      return ('Rain showers', 'Plan for quick downpours');
    }
    if (code >= 85 && code <= 86) {
      return ('Snow showers', 'Check road conditions');
    }
    if (code >= 95 && code <= 99) {
      return ('Thunderstorm', 'Stay safe indoors if lightning');
    }
    return ('Fair', 'Enjoy Misamis Occidental');
  }
}
