import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:twilio_voice/twilio_voice.dart';

import 'twilio_token_client.dart';

/// Registers device + access token and places VoIP calls via Twilio Voice SDK.
class TwilioVoipFacade {
  TwilioVoipFacade._();
  static final TwilioVoipFacade instance = TwilioVoipFacade._();

  String? _lastIdentity;

  Future<void> registerForOutgoingCalls(String firebaseUid) async {
    final creds = await TwilioTokenClient.fetchAccessToken(firebaseUid);
    String? deviceToken;
    if (!kIsWeb && Platform.isAndroid) {
      deviceToken = await FirebaseMessaging.instance.getToken();
    }
    final ok = await TwilioVoice.instance.setTokens(
      accessToken: creds.accessToken,
      deviceToken: deviceToken,
    );
    if (ok != true) {
      throw StateError('Twilio setTokens failed');
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
    return TwilioVoice.instance.call.place(from: from, to: toE164);
  }

  Future<bool?> hangUp() => TwilioVoice.instance.call.hangUp();

  Stream<CallEvent> get callEvents => TwilioVoice.instance.callEventsListener;
}
