import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/voice_backend_config.dart';

/// Result of POST `/grant-reward` (server adds [creditsAdded] per ad, typically 2).
class GrantRewardResult {
  const GrantRewardResult({
    required this.creditsAdded,
    required this.baseCredits,
    required this.streakBonus,
    required this.streakCount,
    required this.adSubCounter,
    required this.adsWatchedToday,
    this.remainingDailyAds = 0,
    this.firstLifetimeAd = false,
  });

  /// Total credits added this grant (base + optional streak milestone).
  final int creditsAdded;
  final int baseCredits;
  final int streakBonus;
  final int streakCount;
  /// Legacy field; server keeps this at 0 (no multi-ad cycle).
  final int adSubCounter;
  final int adsWatchedToday;
  /// Ads remaining today after this grant (server).
  final int remainingDailyAds;
  /// True when this was the user’s first lifetime rewarded ad (`POST /grant-reward`).
  final bool firstLifetimeAd;
}

class GrantRewardException implements Exception {
  GrantRewardException(this.statusCode, this.message);
  final int statusCode;
  final String message;

  @override
  String toString() => 'GrantRewardException($statusCode): $message';
}

/// Avoid showing raw HTML (e.g. Express "Cannot POST /grant-reward") in SnackBars.
String _parseGrantRewardError(int statusCode, String body) {
  final t = body.trim();
  if (t.contains('<!DOCTYPE') ||
      t.contains('<html') ||
      t.contains('Cannot POST')) {
    return 'Rewards server unavailable (POST /grant-reward). '
        'Redeploy the Node API on Render with the latest server/index.js and FIREBASE_SERVICE_ACCOUNT_JSON.';
  }
  try {
    final j = jsonDecode(body);
    if (j is Map) {
      final err = j['error'];
      final m = j['message'];
      if (m != null && m.toString().isNotEmpty) {
        return m.toString();
      }
      if (err != null) return err.toString();
    }
  } catch (_) {}
  if (t.isNotEmpty && t.length < 300) return t;
  return 'Grant failed (HTTP $statusCode).';
}

/// Secured reward: POST [VoiceBackendConfig.grantRewardUri] with Firebase ID token.
class GrantRewardService {
  GrantRewardService._();
  static final GrantRewardService instance = GrantRewardService._();

  /// Call once after each completed rewarded ad (server enforces 4→+10, 24/day, 20s gap).
  Future<GrantRewardResult> requestMinuteGrant() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('Not signed in');
    }
    final token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      throw StateError('Could not get Firebase ID token');
    }

    final uri = VoiceBackendConfig.grantRewardUri();
    final response = await http
        .post(
          uri,
          headers: <String, String>{
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json; charset=utf-8',
          },
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      if (kDebugMode) {
        debugPrint('grant-reward failed: ${response.statusCode} ${response.body}');
      }
      final msg = _parseGrantRewardError(response.statusCode, response.body);
      throw GrantRewardException(response.statusCode, msg);
    }

    final j = jsonDecode(response.body) as Map<String, dynamic>?;
    final total = (j?['creditsAdded'] as num?)?.toInt() ?? 0;
    final base = (j?['baseCredits'] as num?)?.toInt();
    final streakB = (j?['streakBonus'] as num?)?.toInt() ?? 0;
    final streakC = (j?['streakCount'] as num?)?.toInt() ?? 0;
    final firstAd = j?['firstLifetimeAd'] == true;
    final result = GrantRewardResult(
      creditsAdded: total,
      baseCredits: base ?? (total - streakB).clamp(0, total),
      streakBonus: streakB,
      streakCount: streakC,
      adSubCounter: (j?['adSubCounter'] as num?)?.toInt() ?? 0,
      adsWatchedToday: (j?['adsWatchedToday'] as num?)?.toInt() ?? 0,
      remainingDailyAds: (j?['remainingDailyAds'] as num?)?.toInt() ?? 0,
      firstLifetimeAd: firstAd,
    );
    // Server (Admin SDK) updates Firestore; client must not write credits — listeners refresh UI.
    return result;
  }
}
