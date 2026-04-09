import 'package:flutter_dotenv/flutter_dotenv.dart';

abstract final class VoiceBackendConfig {
  VoiceBackendConfig._();

  /// Default when `VOICE_BACKEND_BASE_URL` is unset (e.g. ngrok for local server).
  static const String _defaultBaseUrl =
      'https://649b-223-181-96-18.ngrok-free.app';

  /// Base URL only, no trailing slash. `.env` overrides default.
  static String get baseUrl {
    final v = dotenv.env['VOICE_BACKEND_BASE_URL']?.trim();
    final raw = (v != null && v.isNotEmpty) ? v : _defaultBaseUrl;
    return raw.replaceAll(RegExp(r'/$'), '');
  }

  static Uri tokenUri(String identity) {
    return Uri.parse('$baseUrl/token').replace(
      queryParameters: {'identity': identity},
    );
  }
}
