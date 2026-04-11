import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/voice_backend_config.dart';

/// Server-side live credits ([/call-live-tick]) + final settlement ([/sync-call-billing]).
class CallLiveBillingService {
  CallLiveBillingService._();
  static final CallLiveBillingService instance = CallLiveBillingService._();

  Future<String?> _bearer() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return user.getIdToken();
  }

  /// Deducts [amount] (1 or 10) for an in-progress Twilio Voice call.
  Future<bool> postLiveTick({
    required String callSid,
    required int amount,
  }) async {
    final sid = callSid.trim();
    if (sid.isEmpty) return false;
    final token = await _bearer();
    if (token == null || token.isEmpty) return false;

    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final r = await http
            .post(
              VoiceBackendConfig.callLiveTickUri(),
              headers: <String, String>{
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/json; charset=utf-8',
              },
              body: jsonEncode(<String, Object?>{
                'callSid': sid,
                'amount': amount,
              }),
            )
            .timeout(const Duration(seconds: 12));
        if (r.statusCode == 200) return true;
        if (kDebugMode) {
          debugPrint('call-live-tick failed: ${r.statusCode} ${r.body}');
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('call-live-tick error: $e');
        }
      }
      await Future<void>.delayed(Duration(milliseconds: 300 * (attempt + 1)));
    }
    return false;
  }

  /// Runs final charge reconciliation (Twilio duration vs live ticks). Call after [hangUp].
  Future<bool> syncCallBilling(String callSid) async {
    final sid = callSid.trim();
    if (sid.isEmpty) return false;
    final token = await _bearer();
    if (token == null || token.isEmpty) return false;

    for (var attempt = 0; attempt < 4; attempt++) {
      try {
        final r = await http
            .post(
              VoiceBackendConfig.syncCallBillingUri(),
              headers: <String, String>{
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/json; charset=utf-8',
              },
              body: jsonEncode(<String, String>{'callSid': sid}),
            )
            .timeout(const Duration(seconds: 20));
        if (r.statusCode == 200) return true;
        if (kDebugMode) {
          debugPrint('sync-call-billing failed: ${r.statusCode} ${r.body}');
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('sync-call-billing error: $e');
        }
      }
      await Future<void>.delayed(Duration(milliseconds: 500 * (attempt + 1)));
    }
    return false;
  }
}
