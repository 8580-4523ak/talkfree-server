import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/twilio_env.dart';

/// Twilio Account SID: `AC` + 32 hex chars (34 total).
final RegExp _twilioAccountSid = RegExp(r'^AC[a-fA-F0-9]{32}$');

/// Sends SMS via Twilio REST API (`/Messages.json`).
///
/// Credentials and [from] number are read from `.env` — not hardcoded in source.
Future<void> sendTwilioSMS(String recipientNumber, String messageBody) async {
  final sid = TwilioEnv.accountSid;
  final token = TwilioEnv.authToken;
  final from = TwilioEnv.phoneNumber;

  if (sid == null || token == null) {
    throw StateError('TWILIO_ACCOUNT_SID / TWILIO_AUTH_TOKEN missing in .env');
  }
  if (from == null || from.isEmpty) {
    throw StateError('TWILIO_PHONE_NUMBER missing in .env');
  }
  if (!_twilioAccountSid.hasMatch(sid)) {
    throw StateError(
      'TWILIO_ACCOUNT_SID must be 34 chars: AC + 32 hex digits. '
      'Copy it again from Twilio Console → Account → API keys & tokens.',
    );
  }

  if (kDebugMode) {
    debugPrint(
      'Twilio auth check: SID len=${sid.length} (expect 34), '
      'token len=${token.length} (usually 32)',
    );
  }

  final uri = Uri.parse(
    'https://api.twilio.com/2010-04-01/Accounts/$sid/Messages.json',
  );

  final basic = base64Encode(utf8.encode('$sid:$token'));

  final body = [
    'From=${Uri.encodeQueryComponent(from)}',
    'To=${Uri.encodeQueryComponent(recipientNumber)}',
    'Body=${Uri.encodeQueryComponent(messageBody)}',
  ].join('&');

  try {
    final response = await http
        .post(
          uri,
          headers: {
            'Authorization': 'Basic $basic',
            'Content-Type': 'application/x-www-form-urlencoded',
          },
          body: body,
        )
        .timeout(
          const Duration(seconds: 30),
          onTimeout: () => throw TwilioSmsException(
            'Request timed out after 30s — check network and try again.',
            0,
          ),
        );

    // ignore: avoid_print
    print('Twilio SMS response status: ${response.statusCode}');

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final hint = response.statusCode == 401
          ? ' Wrong Account SID or Auth Token — open Twilio Console, copy '
              'Account SID + Auth Token from the main dashboard (not API Key SK…). '
              'Update project root `.env`, then stop app and `flutter run` again.'
          : '';
      throw TwilioSmsException(
        'Twilio error ${response.statusCode}: ${response.body}$hint',
        response.statusCode,
      );
    }
  } catch (e, st) {
    if (e is TwilioSmsException) rethrow;
    // ignore: avoid_print
    print('Twilio SMS request failed: $e');
    // ignore: avoid_print
    print('$st');
    rethrow;
  }
}

class TwilioSmsException implements Exception {
  TwilioSmsException(this.message, [this.statusCode]);
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}
