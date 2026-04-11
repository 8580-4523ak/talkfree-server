import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:twilio_voice/twilio_voice.dart';

import '../config/voice_backend_config.dart';
import 'twilio_token_client.dart';

/// Registers device + Twilio Voice SDK using a JWT from the Render server ([VoiceBackendConfig.tokenUri]).
class TwilioVoipFacade {
  TwilioVoipFacade._();
  static final TwilioVoipFacade instance = TwilioVoipFacade._();

  String? _lastIdentity;

  /// Fetches access token from `${VoiceBackendConfig.baseUrl}/token`, then [TwilioVoice.instance.setTokens].
  Future<void> registerForOutgoingCalls(String firebaseUid) async {
    if (firebaseUid.trim().isEmpty) {
      throw StateError('registerForOutgoingCalls: empty Firebase uid');
    }

    final creds = await TwilioTokenClient.fetchAccessToken(firebaseUid);

    if (kDebugMode) {
      debugPrint(
        'Twilio Voice: token from ${VoiceBackendConfig.baseUrl}/token, '
        'identity=${creds.identity}, jwtLen=${creds.accessToken.length}',
      );
    }

    String? deviceToken;
    if (!kIsWeb && Platform.isAndroid) {
      deviceToken = await FirebaseMessaging.instance.getToken();
    }

    final ok = await TwilioVoice.instance.setTokens(
      accessToken: creds.accessToken,
      deviceToken: deviceToken,
    );
    if (ok != true) {
      throw StateError(
        'Twilio Voice setTokens failed after loading token from ${VoiceBackendConfig.baseUrl}. '
        'Check Twilio env on the server and device permissions.',
      );
    }
    if (Platform.isAndroid) {
      await TwilioVoice.instance.registerPhoneAccount();
      if (!await TwilioVoice.instance.isPhoneAccountEnabled()) {
        await TwilioVoice.instance.openPhoneAccountSettings();
      }
      await TwilioVoice.instance.requestCallPhonePermission();
      await TwilioVoice.instance.requestReadPhoneStatePermission();
      await TwilioVoice.instance.requestManageOwnCallsPermission();
    }
    await TwilioVoice.instance.requestMicAccess();
    _lastIdentity = creds.identity;
  }

  String get registeredIdentity {
    final id = _lastIdentity;
    if (id == null) {
      throw StateError('registerForOutgoingCalls first');
    }
    return id;
  }

  Future<bool?> placePstnCall(String toE164) async {
    final from = registeredIdentity;
    final result = await TwilioVoice.instance.call.place(from: from, to: toE164);
    if (kDebugMode && result != true) {
      debugPrint('TwilioVoice.place returned $result (from=$from to=$toE164)');
    }
    return result;
  }

  Future<bool?> hangUp() => TwilioVoice.instance.call.hangUp();

  /// Available after ringing / connect (see Twilio Voice plugin).
  Future<String?> getActiveCallSid() => TwilioVoice.instance.call.getSid();

  Stream<CallEvent> get callEvents => TwilioVoice.instance.callEventsListener;
}
