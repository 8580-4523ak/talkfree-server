/// Production TalkFree voice API on Render — single source of truth (no env/ngrok overrides).
abstract final class VoiceBackendConfig {
  VoiceBackendConfig._();

  static const String _host = 'talkfree-server.onrender.com';

  /// `https://talkfree-server.onrender.com` (no trailing slash).
  static const String productionOrigin = 'https://talkfree-server.onrender.com';

  /// Base URL only, no trailing slash.
  static String get baseUrl => productionOrigin;

  /// `GET /call?to=<number>` — query built with [Uri.https] so `+` encodes correctly.
  static Uri callUri(String to) {
    return Uri.https(_host, '/call', <String, String>{'to': to});
  }

  /// `GET /token?identity=<id>` for Twilio Voice access token.
  static Uri tokenUri(String identity) {
    return Uri.https(
      _host,
      '/token',
      <String, String>{'identity': identity},
    );
  }

  /// `POST /grant-reward` — Firebase ID token in `Authorization` (server adds credits).
  static Uri grantRewardUri() => Uri.https(_host, '/grant-reward');

  /// `POST /terminate-call` — JSON `{ "callSid": "CA..." }` when balance cannot cover talk time.
  static Uri terminateCallUri() => Uri.https(_host, '/terminate-call');

  /// `POST /call-live-tick` — JSON `{ "callSid", "amount" }` (secured live credit pulses).
  static Uri callLiveTickUri() => Uri.https(_host, '/call-live-tick');

  /// `POST /sync-call-billing` — JSON `{ "callSid" }` after hangup (same settlement as Twilio `/call-status`).
  static Uri syncCallBillingUri() => Uri.https(_host, '/sync-call-billing');
}
