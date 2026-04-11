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
import '../widgets/premium_ios_dial_pad.dart' show premiumDialCallGreen;

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
    with WidgetsBindingObserver, TickerProviderStateMixin {
  Timer? _durationTimer;
  int _elapsedSeconds = 0;
  /// Local balance preview: set on connect (−[CreditsPolicy.creditsPerCallTick]), then periodic ticks.
  int? _localCredits;
  StreamSubscription<CallEvent>? _callSub;
  String _statusLine = 'Connecting...';
  bool _remoteEndedHandled = false;
  bool _connectedCreditTimerStarted = false;

  late final AnimationController _callVisualPulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat();

  late final AnimationController _creditPulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  String get _mmSs {
    final m = _elapsedSeconds ~/ 60;
    final s = _elapsedSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_bootstrap());
    });
  }

  void _onConnectedTick(Timer timer) {
    if (!mounted) return;
    setState(() {
      _elapsedSeconds++;
      final lc = _localCredits;
      if (lc != null &&
          _elapsedSeconds >= CreditsPolicy.connectedLiveCreditFirstTickSec &&
          (_elapsedSeconds - CreditsPolicy.connectedLiveCreditFirstTickSec) %
                  CreditsPolicy.connectedLiveCreditIntervalSec ==
              0) {
        _localCredits = lc - CreditsPolicy.connectedLiveCreditPerTick;
        _creditPulse.forward(from: 0);
      }
    });
    final after = _localCredits;
    if (after != null && after < 1) {
      timer.cancel();
      _durationTimer = null;
      unawaited(_autoHangupLowCredits());
    }
  }

  Future<void> _startConnectedCreditTimer() async {
    if (_connectedCreditTimerStarted || !mounted) return;
    _connectedCreditTimerStarted = true;

    final credits = await FirestoreUserService.fetchUsableCredits(
      widget.user.uid,
    );
    if (!mounted) return;

    setState(() {
      _localCredits = credits - CreditsPolicy.creditsPerCallTick;
      _creditPulse.forward(from: 0);
    });

    final afterInitial = _localCredits ?? 0;
    if (afterInitial < 1) {
      unawaited(_autoHangupLowCredits());
      return;
    }

    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), _onConnectedTick);
  }

  Future<void> _autoHangupLowCredits() async {
    if (!mounted) return;
    if (_remoteEndedHandled) return;
    _remoteEndedHandled = true;
    _durationTimer?.cancel();
    _durationTimer = null;
    CallService.instance.stopBilling();
    await _callSub?.cancel();
    _callSub = null;
    try {
      await TwilioVoipFacade.instance.hangUp();
    } catch (_) {}
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Call ended — not enough credits.')),
      );
      Navigator.of(context).pop(false);
    }
  }

  /// Twilio exposes Call SID after ringing; needed for server-side [TerminateCallService].
  Future<void> _pollActiveCallSid() async {
    for (var i = 0; i < 40; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!mounted) return;
      final sid = await TwilioVoipFacade.instance.getActiveCallSid();
      if (sid != null && sid.isNotEmpty) {
        CallService.instance.setActiveCallSid(sid);
        return;
      }
    }
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
    if (c < CreditsPolicy.minCreditsToStartCall) {
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
            unawaited(_startConnectedCreditTimer());
            break;
          case CallEvent.reconnecting:
            setState(() => _statusLine = 'Connecting...');
            break;
          case CallEvent.reconnected:
            setState(() => _statusLine = 'Connected');
            unawaited(_startConnectedCreditTimer());
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

      unawaited(_pollActiveCallSid());

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
    _callVisualPulse.dispose();
    _creditPulse.dispose();
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
              const SizedBox(height: 24),
              _ActiveCallPulseHeader(controller: _callVisualPulse),
              const SizedBox(height: 28),
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
              if (_localCredits != null) ...[
                const SizedBox(height: 20),
                _NeonCreditsBalance(
                  credits: _localCredits!,
                  pulse: _creditPulse,
                ),
              ],
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
                child: FilledButton.icon(
                  onPressed: _endCall,
                  icon: const Icon(Icons.call_end_rounded, size: 26),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFC62828),
                    foregroundColor: Colors.white,
                    elevation: 4,
                    shadowColor: Colors.red.withValues(alpha: 0.45),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  label: Text(
                    'Hang up',
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

/// Live balance: neon green with a short pulse when the value drops.
class _NeonCreditsBalance extends StatelessWidget {
  const _NeonCreditsBalance({
    required this.credits,
    required this.pulse,
  });

  final int credits;
  final Animation<double> pulse;

  static const Color _neon = Color(0xFF39FF14);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulse,
      builder: (context, child) {
        final u = Curves.easeOutCubic.transform(pulse.value);
        final scale = 1.0 + 0.1 * (1.0 - u);
        final blur = 10.0 + 18.0 * (1.0 - u);
        return Transform.scale(
          scale: scale,
          child: Text(
            '$credits credits',
            key: ValueKey<int>(credits),
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: _neon,
              letterSpacing: 0.8,
              shadows: [
                Shadow(
                  color: _neon.withValues(alpha: 0.92),
                  blurRadius: blur,
                ),
                Shadow(
                  color: _neon.withValues(alpha: 0.55),
                  blurRadius: 3,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Neon green expanding rings + center icon for active-call screen.
class _ActiveCallPulseHeader extends StatelessWidget {
  const _ActiveCallPulseHeader({required this.controller});

  final Animation<double> controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final t = controller.value;
        return SizedBox(
          height: 120,
          width: 120,
          child: Stack(
            alignment: Alignment.center,
            children: [
              for (var i = 0; i < 3; i++)
                _ring(t, i),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      premiumDialCallGreen.withValues(alpha: 0.28),
                      premiumDialCallGreen.withValues(alpha: 0.05),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: premiumDialCallGreen.withValues(alpha: 0.45),
                      blurRadius: 22,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Icon(
                  Icons.phone_in_talk_rounded,
                  color: premiumDialCallGreen.withValues(alpha: 0.98),
                  size: 38,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _ring(double t, int index) {
    final phase = (t + index * 0.28) % 1.0;
    return Transform.scale(
      scale: 0.42 + phase * 0.9,
      child: Opacity(
        opacity: (1.0 - phase) * 0.75,
        child: Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: premiumDialCallGreen.withValues(alpha: 0.5),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: premiumDialCallGreen.withValues(alpha: 0.25),
                blurRadius: 14,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
