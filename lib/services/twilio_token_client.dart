import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/voice_backend_config.dart';

class TwilioTokenClient {
  TwilioTokenClient._();

  static Future<({String identity, String accessToken})> fetchAccessToken(
    String firebaseUid,
  ) async {
    final uri = VoiceBackendConfig.tokenUri(firebaseUid);
    final res = await http.get(uri).timeout(const Duration(seconds: 20));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw StateError('Token HTTP ${res.statusCode}: ${res.body}');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>?;
    final identity = data?['identity'] as String?;
    final token = data?['token'] as String?;
    if (identity == null || token == null) {
      throw StateError('Invalid token JSON');
    }
    return (identity: identity, accessToken: token);
  }
}
