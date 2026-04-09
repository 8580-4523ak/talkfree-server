import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/twilio_env.dart';
import 'twilio_service.dart' show TwilioApiException;

/// Twilio Account SID: `AC` + 32 hex chars (34 total).
final RegExp _twilioAccountSid = RegExp(r'^AC[a-fA-F0-9]{32}$');

/// Starts an outbound PSTN call via Twilio [Calls] API (server-side dial).
///
/// [twimlBinUrl] overrides [.env] `TWILIO_VOICE_TWIML_URL` when set.
class VoiceService {
  VoiceService._();

  static String get _sid {
    final v = TwilioEnv.accountSid?.trim();
    if (v == null || v.isEmpty) {
      throw StateError('TWILIO_ACCOUNT_SID missing in .env');
    }
    if (!_twilioAccountSid.hasMatch(v)) {
      throw StateError(
        'TWILIO_ACCOUNT_SID must be 34 chars: AC + 32 hex digits.',
      );
    }
    return v;
  }

  static String get _token {
    final v = TwilioEnv.authToken?.trim();
    if (v == null || v.isEmpty) {
      throw StateError('TWILIO_AUTH_TOKEN missing in .env');
    }
    return v;
  }

  static Map<String, String> get _formHeaders => {
        'Authorization':
            'Basic ${base64Encode(utf8.encode('$_sid:$_token'))}',
        'Content-Type': 'application/x-www-form-urlencoded',
      };

  /// POST `/2010-04-01/Accounts/{AccountSid}/Calls.json`
  ///
  /// Twilio requests [twimlBinUrl] when the callee answers and runs that Voice TwiML.
  /// Returns the Call `sid` for cancel / billing lifecycle.
  static Future<String> createOutboundCall({
    required String fromE164,
    required String toE164,
    String? twimlBinUrl,
  }) async {
    final urlRaw = (twimlBinUrl ?? TwilioEnv.voiceTwimlUrl)?.trim();
    if (urlRaw == null || urlRaw.isEmpty) {
      throw StateError(
        'TWILIO_VOICE_TWIML_URL missing in .env — paste your TwiML Bin URL.',
      );
    }
    if (!urlRaw.startsWith('http://') && !urlRaw.startsWith('https://')) {
      throw StateError('TwiML URL must start with https://');
    }

    final uri = Uri.parse(
      'https://api.twilio.com/2010-04-01/Accounts/$_sid/Calls.json',
    );
    final body = [
      'From=${Uri.encodeQueryComponent(fromE164)}',
      'To=${Uri.encodeQueryComponent(toE164)}',
      'Url=${Uri.encodeQueryComponent(urlRaw)}',
    ].join('&');

    final response = await http.post(uri, headers: _formHeaders, body: body);
    if (response.statusCode != 200 && response.statusCode != 201) {
      _throwTwilioHttpError(response.statusCode, response.body);
    }
    try {
      final decoded = jsonDecode(response.body) as Map<String, dynamic>?;
      final sid = decoded?['sid'] as String?;
      if (sid == null || sid.isEmpty) {
        throw StateError('Twilio: missing Call sid in response');
      }
      return sid;
    } catch (e) {
      if (e is StateError) rethrow;
      throw StateError('Twilio: invalid Calls response JSON');
    }
  }

  /// Ends an in-progress call (queued, ringing, or in-progress).
  static Future<void> cancelCall(String callSid) async {
    final sid = callSid.trim();
    if (sid.isEmpty) return;
    final uri = Uri.parse(
      'https://api.twilio.com/2010-04-01/Accounts/$_sid/Calls/$sid.json',
    );
    final response = await http.post(
      uri,
      headers: _formHeaders,
      body: 'Status=canceled',
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      _throwTwilioHttpError(response.statusCode, response.body);
    }
  }

  static Never _throwTwilioHttpError(int statusCode, String body) {
    final p = _parseTwilioErrorJson(body);
    final text = p.message != null
        ? (p.code != null ? '${p.message} (code ${p.code})' : p.message!)
        : body;
    throw TwilioApiException(
      text,
      statusCode: statusCode,
      twilioCode: p.code,
    );
  }

  static ({String? message, int? code}) _parseTwilioErrorJson(String body) {
    try {
      final m = jsonDecode(body) as Map<String, dynamic>?;
      return (
        message: m?['message'] as String?,
        code: (m?['code'] as num?)?.toInt(),
      );
    } catch (_) {
      return (message: null, code: null);
    }
  }
}
