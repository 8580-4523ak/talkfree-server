import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:twilio_voice/twilio_voice.dart';

import '../config/credits_policy.dart';
import '../services/call_service.dart';
import '../services/firestore_user_service.dart';
import '../services/twilio_voip_facade.dart';

class CallingScreen extends StatefulWidget {
  const CallingScreen({
    super.key,
    required this.user,
    required this.dialE164,
  });

  final User user;
  final String dialE164;

  @override
  State<CallingScreen> createState() => _CallingScreenState();
}

class _CallingScreenState extends State<CallingScreen>
    with WidgetsBindingObserver {
  Timer? _durationTimer;
  int _elapsedSeconds = 0;
  StreamSubscription<CallEvent>? _callSub;
  String _statusLine = 'Connecting...';
  bool _remoteEndedHandled = false;

  String get _mmSs {
    final m = _elapsedSeconds ~/ 60;
    final s = _elapsedSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsedSeconds++);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_bootstrap());
    });
  }

  Future<void> _bootstrap() async {
    if (kIsWeb) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('VoIP is not supported on web.')),
      );
      Navigator.of(context).pop(true);
      return;
    }

    final c = await FirestoreUserService.fetchUsableCredits(widget.user.uid);
    if (!mounted) return;
    if (c < CreditsPolicy.creditsPerCallTick) {
      _durationTimer?.cancel();
      _durationTimer = null;
      Navigator.of(context).pop(true);
      return;
    }

    StreamSubscription<CallEvent>? sub;
    try {
      await TwilioVoipFacade.instance.registerForOutgoingCalls(widget.user.uid);
      if (!mounted) return;

      setState(() => _statusLine = 'Connecting...');

      sub = TwilioVoipFacade.instance.callEvents.listen((event) {
        if (!mounted) return;
        switch (event) {
          case CallEvent.ringing:
            setState(() => _statusLine = 'Calling...');
            break;
          case CallEvent.connected:
            setState(() => _statusLine = 'Connected');
            break;
          case CallEvent.reconnecting:
            setState(() => _statusLine = 'Connecting...');
            break;
          case CallEvent.reconnected:
            setState(() => _statusLine = 'Connected');
            break;
          case CallEvent.callEnded:
          case CallEvent.declined:
            unawaited(_onRemoteEnded());
            break;
          default:
            break;
        }
      });
      _callSub = sub;

      final ok = await TwilioVoipFacade.instance.placePstnCall(widget.dialE164);
      if (!mounted) return;
      if (ok != true) {
        await sub.cancel();
        _callSub = null;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not start call.')),
          );
          Navigator.of(context).pop(true);
        }
        return;
      }

      CallService.instance.startBilling(
        uid: widget.user.uid,
        twilioCallSid: null,
        hangUpActiveCall: () async {
          await TwilioVoipFacade.instance.hangUp();
        },
        onInsufficientCredits: () {
          if (!mounted) return;
          unawaited(_onInsufficientFromBilling());
        },
        onError: (_) {},
      );
    } catch (e) {
      await sub?.cancel();
      _callSub = null;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Call failed: $e')),
      );
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _onInsufficientFromBilling() async {
    _durationTimer?.cancel();
    _durationTimer = null;
    await _callSub?.cancel();
    _callSub = null;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not enough credits to continue.')),
      );
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _onRemoteEnded() async {
    if (_remoteEndedHandled) return;
    _remoteEndedHandled = true;
    if (!mounted) return;
    _durationTimer?.cancel();
    _durationTimer = null;
    CallService.instance.stopBilling();
    await _callSub?.cancel();
    _callSub = null;
    if (mounted) Navigator.of(context).pop(false);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _durationTimer?.cancel();
    _callSub?.cancel();
    CallService.instance.stopBilling();
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      unawaited(TwilioVoipFacade.instance.hangUp());
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(CallService.instance.syncAfterAppResumed());
    }
  }

  Future<void> _endCall() async {
    _durationTimer?.cancel();
    _durationTimer = null;
    CallService.instance.stopBilling();
    await _callSub?.cancel();
    _callSub = null;
    try {
      await TwilioVoipFacade.instance.hangUp();
    } catch (_) {}
    if (mounted) Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            children: [
              const SizedBox(height: 32),
              Text(
                widget.dialE164,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 26,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _statusLine,
                style: GoogleFonts.poppins(
                  fontSize: 17,
                  fontWeight: FontWeight.w500,
                  color: Colors.white70,
                ),
              ),
              const Spacer(),
              Text(
                _mmSs,
                style: GoogleFonts.poppins(
                  fontSize: 56,
                  fontWeight: FontWeight.w300,
                  color: Colors.white,
                  letterSpacing: 2,
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 72,
                child: FilledButton(
                  onPressed: _endCall,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.red.shade700,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  child: Text(
                    'End call',
                    style: GoogleFonts.poppins(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
