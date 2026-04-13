import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/voice_backend_config.dart';

/// Result of POST `/assign-number` (Twilio purchase + Firestore).
class AssignNumberResult {
  const AssignNumberResult({
    required this.assignedNumber,
    this.twilioIncomingPhoneSid,
    this.alreadyAssigned = false,
    this.planType,
    this.numberExpiryIso,
    this.creditsDeducted,
    this.newBalance,
  });

  final String assignedNumber;
  final String? twilioIncomingPhoneSid;
  final bool alreadyAssigned;
  final String? planType;
  final String? numberExpiryIso;
  final int? creditsDeducted;
  final int? newBalance;
}

class AssignNumberException implements Exception {
  AssignNumberException(this.statusCode, this.message);
  final int statusCode;
  final String message;

  @override
  String toString() => 'AssignNumberException($statusCode): $message';
}

String _parseError(int statusCode, String body) {
  final t = body.trim();
  if (t.contains('<!DOCTYPE') || t.contains('<html') || t.contains('Cannot POST')) {
    return 'Number server unavailable (POST /assign-number). '
        'Check API deployment and FIREBASE_SERVICE_ACCOUNT_JSON.';
  }
  try {
    final j = jsonDecode(body);
    if (j is Map) {
      final m = j['message'];
      final err = j['error'];
      if (m != null && m.toString().isNotEmpty) return m.toString();
      if (err != null) return err.toString();
    }
  } catch (_) {}
  if (t.isNotEmpty && t.length < 400) return t;
  return 'Assign number failed (HTTP $statusCode).';
}

/// Secured: POST [VoiceBackendConfig.assignNumberUri] with Firebase ID token.
class AssignNumberService {
  AssignNumberService._();
  static final AssignNumberService instance = AssignNumberService._();

  /// [planType] must match server: `daily`, `weekly`, `monthly`, `yearly`.
  Future<AssignNumberResult> requestAssignNumber({
    String planType = 'monthly',
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('Not signed in');
    }
    final token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      throw StateError('Could not get Firebase ID token');
    }

    final uri = VoiceBackendConfig.assignNumberUri();
    final response = await http
        .post(
          uri,
          headers: <String, String>{
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json; charset=utf-8',
          },
          body: jsonEncode(<String, String>{'planType': planType}),
        )
        .timeout(const Duration(seconds: 90));

    if (response.statusCode != 200) {
      if (kDebugMode) {
        debugPrint('assign-number failed: ${response.statusCode} ${response.body}');
      }
      throw AssignNumberException(
        response.statusCode,
        _parseError(response.statusCode, response.body),
      );
    }

    final j = jsonDecode(response.body) as Map<String, dynamic>?;
    final assigned = (j?['assigned_number'] as String?)?.trim() ?? '';
    final sid = (j?['twilioIncomingPhoneSid'] as String?)?.trim();
    final already = j?['alreadyAssigned'] == true;
    if (assigned.isEmpty) {
      throw AssignNumberException(500, 'Invalid assign-number response');
    }
    final pt = j?['planType'] as String?;
    final ne = j?['number_expiry_date'] as String?;
    final cd = (j?['creditsDeducted'] as num?)?.toInt();
    final nb = (j?['newBalance'] as num?)?.toInt();
    return AssignNumberResult(
      assignedNumber: assigned,
      twilioIncomingPhoneSid: sid,
      alreadyAssigned: already,
      planType: pt,
      numberExpiryIso: ne,
      creditsDeducted: cd,
      newBalance: nb,
    );
  }
}
