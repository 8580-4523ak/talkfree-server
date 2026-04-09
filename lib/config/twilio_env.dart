import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Reads Twilio keys from `.env` (loaded in [main]).
///
/// **Security:** Values ship inside the app bundle. For production, call Twilio
/// only from your backend — never rely on hiding secrets in the client.
abstract final class TwilioEnv {
  static String? get accountSid => _norm(dotenv.env['TWILIO_ACCOUNT_SID']);
  static String? get authToken => _norm(dotenv.env['TWILIO_AUTH_TOKEN']);

  /// Your Twilio SMS / voice number (E.164). Same as server `TWILIO_CALLER_ID`.
  static String? get phoneNumber => _norm(dotenv.env['TWILIO_CALLER_ID']);

  /// TwiML Bin (or webhook) URL for outbound [Calls] — returns Voice TwiML when the call connects.
  static String? get voiceTwimlUrl => _norm(dotenv.env['TWILIO_VOICE_TWIML_URL']);

  /// Trims, strips CR/BOM, optional surrounding quotes (common .env copy issues).
  static String? _norm(String? raw) {
    if (raw == null) return null;
    var s = raw.trim().replaceAll('\r', '');
    if (s.startsWith('\uFEFF')) s = s.substring(1);
    if (s.length >= 2 && s.startsWith('"') && s.endsWith('"')) {
      s = s.substring(1, s.length - 1).trim();
    }
    return s.isEmpty ? null : s;
  }
}
