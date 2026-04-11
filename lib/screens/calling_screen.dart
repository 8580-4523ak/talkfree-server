import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:twilio_voice/twilio_voice.dart';

import '../config/credits_policy.dart';
import '../config/voice_backend_config.dart';
import '../services/call_service.dart';
import '../widgets/voip_gate_dialog.dart';
import '../services/firestore_user_service.dart';
import '../services/call_live_billing_service.dart';
import '../services/twilio_voip_facade.dart';
import '../widgets/premium_ios_dial_pad.dart' show premiumDialCallGreen;

/// Returned when [CallingScreen] closes; [syncedBalance] is set after disconnect via Firestore fetch.
class CallingScreenResult {
  const CallingScreenResult({
    required this.insufficientCredits,
    this.syncedBalance,
    this.serverBillingPending = false,
  });

  final bool insufficientCredits;

  /// Authoritative usable credits from Firestore (e.g. after call end).
  final int? syncedBalance;

  /// True if the call connected but Firestore still matched the pre-call balance after waiting
  /// for Twilio `/call-status` (webhook delay or misconfiguration).
  final bool serverBillingPending;
}

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
  /// Elapsed call time (MM:SS) — 1 Hz while connected.
  Timer? _elapsedTimer;
  int _elapsedSeconds = 0;
  /// Live UI: −1 credit every [CreditsPolicy.connectedLiveCreditIntervalSec] while connected.
  Timer? _liveCreditTicker;
  /// Local balance preview: −[CreditsPolicy.creditsPerCallTick] on connect, then −1 per ticker tick.
  int? _localCredits;
  StreamSubscription<CallEvent>? _callSub;
  String _statusLine = 'Connecting...';
  bool _remoteEndedHandled = false;
  bool _connectedCreditTimerStarted = false;
  /// Firestore usable credits at dial (before connect). Used to wait for server billing after hangup.
  int? _creditsAtSessionStart;
  /// Twilio Call SID — required for POST /call-live-tick and /sync-call-billing.
  String? _activeCallSid;
  /// Tier-2 settlement in progress — shows a light overlay so the 5s window does not feel frozen.
  bool _finalizingBill = false;

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

  void _onElapsedTick(Timer _) {
    if (!mounted) return;
    if (kDebugMode && _elapsedSeconds == 0) {
      debugPrint('DEBUG: _elapsedTimer first tick (1 Hz) — call is Connected');
    }
    setState(() => _elapsedSeconds++);
  }

  void _onLiveCreditTick(Timer timer) {
    unawaited(_applyServerLiveTick(timer));
  }

  Future<void> _applyServerLiveTick(Timer timer) async {
    if (!mounted) return;
    final sid = _activeCallSid;
    if (sid == null || sid.isEmpty) return;
    if (kDebugMode) {
      debugPrint(
        'DEBUG: _liveCreditTicker → POST /call-live-tick amount '
        '${CreditsPolicy.connectedLiveCreditPerTick}',
      );
    }
    final ok = await CallLiveBillingService.instance.postLiveTick(
      callSid: sid,
      amount: CreditsPolicy.connectedLiveCreditPerTick,
    );
    if (!mounted) return;
    if (!ok && kDebugMode) {
      debugPrint('DEBUG: call-live-tick failed (will retry on next tick)');
    }
    int display;
    try {
      display = await FirestoreUserService.fetchUsableCredits(widget.user.uid);
    } catch (_) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _localCredits = display;
      _creditPulse.forward(from: 0);
    });
    if (display <= 0) {
      timer.cancel();
      _liveCreditTicker = null;
      unawaited(_autoHangupLowCredits());
    }
  }

  void _cancelConnectedTimers() {
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
    _liveCreditTicker?.cancel();
    _liveCreditTicker = null;
  }

  Future<void> _startConnectedCreditTimer() async {
    if (kDebugMode) {
      debugPrint(
        'DEBUG: _startConnectedCreditTimer() entered — '
        'alreadyStarted=$_connectedCreditTimerStarted mounted=$mounted',
      );
    }
    if (_connectedCreditTimerStarted || !mounted) {
      if (kDebugMode) {
        debugPrint(
          'DEBUG: _startConnectedCreditTimer() skipped (duplicate connect or unmounted)',
        );
      }
      return;
    }
    _connectedCreditTimerStarted = true;

    final credits = await FirestoreUserService.fetchUsableCredits(
      widget.user.uid,
    );
    if (!mounted) return;

    var sid = _activeCallSid ?? '';
    for (var i = 0; i < 50 && sid.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      if (!mounted) return;
      final g = await TwilioVoipFacade.instance.getActiveCallSid();
      if (g != null && g.isNotEmpty) {
        sid = g;
        _activeCallSid = g;
        CallService.instance.setActiveCallSid(g);
      }
    }

    if (sid.isEmpty) {
      if (kDebugMode) {
        debugPrint('DEBUG: No CallSid yet — elapsed only, no live billing ticks');
      }
      setState(() => _localCredits = credits);
      _cancelConnectedTimers();
      _elapsedSeconds = 0;
      _elapsedTimer = Timer.periodic(const Duration(seconds: 1), _onElapsedTick);
      return;
    }

    if (kDebugMode) {
      debugPrint(
        'DEBUG: Connected → POST /call-live-tick amount ${CreditsPolicy.creditsPerCallTick}',
      );
    }

    final okInitial = await CallLiveBillingService.instance.postLiveTick(
      callSid: sid,
      amount: CreditsPolicy.creditsPerCallTick,
    );
    if (!mounted) return;
    if (!okInitial && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not reach billing server for this call. Credits may update when the call ends.',
          ),
        ),
      );
    }

    final afterServer = await FirestoreUserService.fetchUsableCredits(
      widget.user.uid,
    );
    if (!mounted) return;

    setState(() {
      _localCredits = afterServer;
      _creditPulse.forward(from: 0);
    });

    if (afterServer <= 0) {
      if (kDebugMode) {
        debugPrint('DEBUG: Connected → balance ≤0 after initial server deduct');
      }
      unawaited(_autoHangupLowCredits());
      return;
    }

    _cancelConnectedTimers();
    _elapsedSeconds = 0;
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), _onElapsedTick);
    _liveCreditTicker = Timer.periodic(
      Duration(seconds: CreditsPolicy.connectedLiveCreditIntervalSec),
      _onLiveCreditTick,
    );
    if (kDebugMode) {
      debugPrint(
        'DEBUG: Started _elapsedTimer (1s) + _liveCreditTicker → /call-live-tick '
        '(${CreditsPolicy.connectedLiveCreditIntervalSec}s)',
      );
    }
  }

  Future<void> _autoHangupLowCredits() async {
    if (!mounted) return;
    if (_remoteEndedHandled) return;
    _remoteEndedHandled = true;
    _cancelConnectedTimers();
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
      await _popWithFirestoreSync(insufficientCredits: true);
    }
  }

  /// After hangup: [CallLiveBillingService.runFinalSettlementWindow] (5s Tier-2 sync) then Firestore read
  /// so the dialer does not flash the pre-call balance. Twilio `/call-status` still settles if the app died.
  Future<void> _popWithFirestoreSync({required bool insufficientCredits}) async {
    if (!mounted) return;
    setState(() => _finalizingBill = true);
    int? synced;
    var serverBillingPending = false;
    try {
      final settled = await _fetchUsableCreditsAfterCallSettles();
      synced = settled.balance;
      serverBillingPending = settled.serverBillingPending;
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() => _finalizingBill = false);
      }
    }
    if (!mounted) return;
    Navigator.of(context).pop(
      CallingScreenResult(
        insufficientCredits: insufficientCredits,
        syncedBalance: synced,
        serverBillingPending: serverBillingPending,
      ),
    );
  }

  Future<({int? balance, bool serverBillingPending})>
      _fetchUsableCreditsAfterCallSettles() async {
    final uid = widget.user.uid;
    final baseline = _creditsAtSessionStart;
    final sid = _activeCallSid;

    if (baseline == null || !_connectedCreditTimerStarted) {
      try {
        final v = await FirestoreUserService.fetchUsableCredits(uid);
        return (balance: v, serverBillingPending: false);
      } catch (_) {
        return (balance: null, serverBillingPending: false);
      }
    }

    if (sid != null && sid.isNotEmpty) {
      if (!mounted) {
        return (balance: null, serverBillingPending: false);
      }
      await CallLiveBillingService.instance.runFinalSettlementWindow(
        callSid: sid,
        window: const Duration(seconds: 5),
      );
      if (kDebugMode) {
        debugPrint('DEBUG: Tier-2 settlement window (5s) finished for $sid');
      }
    }

    const maxAttempts = 8;
    const delay = Duration(milliseconds: 400);
    int? last;

    for (var i = 0; i < maxAttempts; i++) {
      if (!mounted) {
        return (balance: last, serverBillingPending: false);
      }
      try {
        last = await FirestoreUserService.fetchUsableCredits(uid);
      } catch (_) {
        if (i == maxAttempts - 1) {
          return (balance: last, serverBillingPending: true);
        }
        await Future<void>.delayed(delay);
        continue;
      }

      if (last < baseline) {
        return (balance: last, serverBillingPending: false);
      }
      if (i < maxAttempts - 1) {
        await Future<void>.delayed(delay);
      }
    }

    final pending = last != null && last >= baseline;
    if (pending && kDebugMode) {
      debugPrint(
        'DEBUG: Balance still ≥ pre-call after sync — check Render / Twilio /call-status',
      );
    }
    return (balance: last, serverBillingPending: pending);
  }

  /// Shown when [TwilioVoipFacade.placePstnCall] does not return true (permissions, phone account, Twilio config).
  Future<void> _showVoipStartFailedHelp() async {
    if (!mounted) return;
    var alreadyLeftCallingScreen = false;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: Text(
            'Could not start VoIP call',
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          content: SingleChildScrollView(
            child: Text(
              'Twilio Voice did not start the call. Check:\n\n'
              '• Microphone & Phone permissions for this app.\n'
              '• Android: enable this app as a calling account (ConnectionService).\n'
              '• Twilio Console → TwiML Apps → same SID as server TWILIO_TWIML_APP_SID → '
              'Voice request URL = ${VoiceBackendConfig.baseUrl}/call (POST, returns TwiML to <Dial>).',
              style: GoogleFonts.inter(
                fontSize: 14,
                height: 1.45,
                color: Colors.white70,
              ),
            ),
          ),
          actions: [
            if (!kIsWeb && Platform.isAndroid)
              TextButton(
                onPressed: () async {
                  Navigator.of(ctx).pop();
                  if (!mounted) return;
                  alreadyLeftCallingScreen = true;
                  Navigator.of(context).pop(
                    const CallingScreenResult(insufficientCredits: true),
                  );
                  await TwilioVoice.instance.openPhoneAccountSettings();
                },
                child: const Text('Calling account'),
              ),
            TextButton(
              onPressed: () async {
                Navigator.of(ctx).pop();
                if (!mounted) return;
                  alreadyLeftCallingScreen = true;
                  Navigator.of(context).pop(
                    const CallingScreenResult(insufficientCredits: true),
                  );
                  await openAppSettings();
              },
              child: const Text('App permissions'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
    if (mounted && !alreadyLeftCallingScreen) {
      Navigator.of(context).pop(
        const CallingScreenResult(insufficientCredits: true),
      );
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
        setState(() => _activeCallSid = sid);
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
      Navigator.of(context).pop(
        const CallingScreenResult(insufficientCredits: true),
      );
      return;
    }

    final c = await FirestoreUserService.fetchUsableCredits(widget.user.uid);
    if (!mounted) return;
    _creditsAtSessionStart = c;
    if (c < CreditsPolicy.minCreditsToStartCall) {
      _cancelConnectedTimers();
      Navigator.of(context).pop(
        const CallingScreenResult(insufficientCredits: true),
      );
      return;
    }

    StreamSubscription<CallEvent>? sub;
    try {
      await TwilioVoipFacade.instance.registerForOutgoingCalls(widget.user.uid);
      if (!mounted) return;

      setState(() => _statusLine = 'Connecting...');

      sub = TwilioVoipFacade.instance.callEvents.listen((event) {
        if (!mounted) return;
        final status = event.name;
        if (kDebugMode) {
          debugPrint('DEBUG: Call Status is $status');
        }
        switch (event) {
          case CallEvent.ringing:
            setState(() => _statusLine = 'Calling...');
            break;
          case CallEvent.connected:
            if (kDebugMode) {
              debugPrint(
                'DEBUG: CallEvent.connected → UI Connected + '
                '_startConnectedCreditTimer() (local −credits + timers)',
              );
            }
            setState(() => _statusLine = 'Connected');
            unawaited(_startConnectedCreditTimer());
            break;
          case CallEvent.reconnecting:
            setState(() => _statusLine = 'Connecting...');
            break;
          case CallEvent.reconnected:
            if (kDebugMode) {
              debugPrint(
                'DEBUG: CallEvent.reconnected → UI Connected + '
                '_startConnectedCreditTimer()',
              );
            }
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
          await _showVoipStartFailedHelp();
        }
        return;
      }

      unawaited(_pollActiveCallSid());

      if (kDebugMode) {
        debugPrint(
          'DEBUG: placePstnCall ok → CallService.startBilling(); '
          'live pulses use POST /call-live-tick, final settle: /sync-call-billing + Twilio /call-status',
        );
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
    } catch (e, _) {
      await sub?.cancel();
      _callSub = null;
      if (!mounted) return;
      final msg = e.toString();
      final callingAccount = msg.contains('Calling account disabled');
      if (callingAccount) {
        // Not a runtime permission — OEM "Calling accounts" toggle. Open system UI directly;
        // runtime mic/phone were already requested on the dialer.
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Turn ON TalkFree (or Twilio) in Calling accounts — the settings screen will open.',
              ),
              duration: Duration(seconds: 5),
            ),
          );
          try {
            await TwilioVoice.instance.openPhoneAccountSettings();
          } catch (_) {}
        }
        if (!mounted) return;
      }
      final tokenOrServer = !callingAccount &&
          (msg.contains('token') ||
              msg.contains('Token') ||
              msg.contains('HTTP') ||
              msg.contains(VoiceBackendConfig.baseUrl) ||
              msg.contains('setTokens'));
      if (tokenOrServer) {
        if (!mounted) return;
        await showVoipGateDialog(
          context,
          title: 'Voice service',
          message:
              'Could not load the Twilio access token from your server '
              '(${VoiceBackendConfig.baseUrl}/token). '
              'Ensure the Render app is live and Twilio keys are set.\n\n'
              '$msg',
          icon: Icons.cloud_sync_rounded,
          primaryLabel: 'OK',
          openSettingsOnPrimary: false,
        );
        if (!mounted) return;
      } else if (!callingAccount) {
        if (!mounted) return;
        await showVoipGateDialog(
          context,
          title: 'Call setup failed',
          message: msg,
          icon: Icons.error_outline_rounded,
          primaryLabel: 'OK',
          openSettingsOnPrimary: false,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(
        const CallingScreenResult(insufficientCredits: true),
      );
    }
  }

  Future<void> _onInsufficientFromBilling() async {
    _cancelConnectedTimers();
    await _callSub?.cancel();
    _callSub = null;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not enough credits to continue.')),
      );
      await _popWithFirestoreSync(insufficientCredits: true);
    }
  }

  Future<void> _onRemoteEnded() async {
    if (_remoteEndedHandled) return;
    _remoteEndedHandled = true;
    if (!mounted) return;
    _cancelConnectedTimers();
    CallService.instance.stopBilling();
    await _callSub?.cancel();
    _callSub = null;
    if (mounted) {
      await _popWithFirestoreSync(insufficientCredits: false);
    }
  }

  @override
  void dispose() {
    _callVisualPulse.dispose();
    _creditPulse.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _cancelConnectedTimers();
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
      final sid = _activeCallSid;
      if (sid != null && sid.isNotEmpty) {
        unawaited(CallLiveBillingService.instance.flushPendingTicksForCall(sid));
      }
    }
  }

  Future<void> _endCall() async {
    _cancelConnectedTimers();
    CallService.instance.stopBilling();
    await _callSub?.cancel();
    _callSub = null;
    try {
      await TwilioVoipFacade.instance.hangUp();
    } catch (_) {}
    if (mounted) {
      await _popWithFirestoreSync(insufficientCredits: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
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
              if (!kIsWeb &&
                  Platform.isAndroid &&
                  (_statusLine == 'Connected' || _statusLine == 'Calling...')) ...[
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    'This call uses Twilio VoIP inside TalkFree — not the cellular dialer. '
                    'Some phones show the system Phone bar on top; hang up here to end the call.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      height: 1.4,
                      color: Colors.white54,
                    ),
                  ),
                ),
              ],
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
        ),
        if (_finalizingBill)
          Positioned.fill(
            child: Material(
              color: Colors.black.withValues(alpha: 0.45),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 36,
                      height: 36,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Color(0xFF39FF14),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Finalizing bill…',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Syncing with server',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
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
