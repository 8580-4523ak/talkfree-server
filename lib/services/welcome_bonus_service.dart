import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/voice_backend_config.dart';

/// POST `/claim-welcome-bonus` — server grants one-time credits if not yet [welcomeCallingCreditsGranted].
class WelcomeBonusService {
  WelcomeBonusService._();
  static final WelcomeBonusService instance = WelcomeBonusService._();

  /// Returns `true` if this request applied the bonus (show welcome snackbar).
  Future<bool> claimIfEligible(User user) async {
    final token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      return false;
    }
    final uri = VoiceBackendConfig.claimWelcomeBonusUri();
    try {
      final response = await http
          .post(
            uri,
            headers: <String, String>{
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json; charset=utf-8',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 25));

      if (response.statusCode == 200) {
        final j = jsonDecode(response.body);
        if (j is Map && j['granted'] == true) {
          return true;
        }
        return false;
      }
      if (kDebugMode) {
        debugPrint('claim-welcome-bonus HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('claim-welcome-bonus: $e\n$st');
      }
    }
    return false;
  }
}
