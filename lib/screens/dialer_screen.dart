import 'dart:async' show unawaited;
import 'dart:io' show Platform;

import 'package:twilio_voice/twilio_voice.dart';
import 'dart:math' show min;
import 'dart:ui' show ImageFilter;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:country_picker/country_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../config/credits_policy.dart';
import '../services/ad_service.dart';
import '../config/voice_backend_config.dart';
import '../theme/app_colors.dart';
import '../services/call_service.dart';
import '../services/firestore_user_service.dart';
import '../utils/voip_runtime_permissions.dart';
import '../widgets/premium_ios_dial_pad.dart';
import 'calling_screen.dart';

class DialerScreen extends StatefulWidget {
  const DialerScreen({
    super.key,
    required this.user,
    this.isPremium = false,
    this.onEarnMinutes,
    this.rewardedAdBusy = false,
    this.cooldownRemaining = 0,
    this.rewardCycleProgress = 0,
    this.rewardDailyLimitReached = false,
  });

  final User user;
  /// Pro subscribers get a lower per-minute rate (see [CreditsPolicy.creditsPerMinutePremium]).
  final bool isPremium;
  final Future<void> Function()? onEarnMinutes;
  final bool rewardedAdBusy;
  final int cooldownRemaining;
  /// Firestore `ad_progress` toward 4 ads / grant.
  final int rewardCycleProgress;
  /// 24 ads/day cap from Firestore.
  final bool rewardDailyLimitReached;

  @override
  State<DialerScreen> createState() => _DialerScreenState();
}

class _DialerScreenState extends State<DialerScreen>
    with TickerProviderStateMixin {
  final StringBuffer _digits = StringBuffer();
  bool _callBusy = false;
  /// True while opening / showing the in-call screen — neon pulsing overlay.
  bool _apiConnecting = false;
  late Country _country;

  late final AnimationController _digitFadeIn = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  late final Animation<double> _digitFadeInCurve = CurvedAnimation(
    parent: _digitFadeIn,
    curve: Curves.easeOutCubic,
  );

  late final AnimationController _connectPulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  String get _display => _digits.toString();

  @override
  void initState() {
    super.initState();
    _country = Country.parse('IN');
  }

  @override
  void dispose() {
    _digitFadeIn.dispose();
    _connectPulse.dispose();
    super.dispose();
  }

  void _append(String ch) {
    HapticFeedback.lightImpact();
    _digitFadeIn.reset();
    setState(() => _digits.write(ch));
    _digitFadeIn.forward();
  }

  void _backspace() {
    HapticFeedback.selectionClick();
    final s = _display;
    if (s.isEmpty) return;
    _digitFadeIn.reset();
    setState(() {
      _digits.clear();
      if (s.length > 1) _digits.write(s.substring(0, s.length - 1));
    });
    if (_display.isNotEmpty) {
      _digitFadeIn.forward();
    }
  }

  void _clearNumber() {
    if (_display.isEmpty) return;
    HapticFeedback.mediumImpact();
    setState(_digits.clear);
  }

  static String _spaceDigitRun(String digits) {
    if (digits.length <= 2) return digits;
    final b = StringBuffer(digits.substring(0, 2));
    var i = 2;
    while (i < digits.length) {
      b.write(' ');
      final take = min(3, digits.length - i);
      b.write(digits.substring(i, i + take));
      i += take;
    }
    return b.toString();
  }

  static String _prettyDial(String s) {
    if (s.isEmpty) {
      return '';
    }
    final out = StringBuffer();
    final digitRun = StringBuffer();

    void flushDigits() {
      if (digitRun.isEmpty) return;
      out.write(_spaceDigitRun(digitRun.toString()));
      digitRun.clear();
    }

    for (var i = 0; i < s.length; i++) {
      final ch = s[i];
      final isSpecial = ch == '+' || ch == '*' || ch == '#';
      final isDigit = ch.compareTo('0') >= 0 && ch.compareTo('9') <= 0;

      if (isSpecial) {
        flushDigits();
        if (out.isNotEmpty) {
          final str = out.toString();
          final last = str[str.length - 1];
          final lastIsDigit = last.compareTo('0') >= 0 && last.compareTo('9') <= 0;
          if (lastIsDigit) out.write(' ');
        }
        out.write(ch);
      } else if (isDigit) {
        digitRun.write(ch);
      } else {
        flushDigits();
        out.write(ch);
      }
    }
    flushDigits();
    return out.toString();
  }

  /// Microphone + (Android) Phone — system prompts first; app Settings only if permanently denied.
  Future<bool> _ensureCallPermissionsForVoip() async {
    if (kIsWeb) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('VoIP calls are not supported in this browser.')),
      );
      return false;
    }

    if (!mounted) return false;
    return ensureVoipRuntimePermissions(context);
  }

  /// In-app VoIP only: [TwilioVoipFacade] + [CallingScreen] (neon in-call UI).
  /// Does **not** use [url_launcher], `tel:` URIs, or the system phone app — stays inside TalkFree.
  Future<void> _onCall() async {
    if (_callBusy) return;

    final to = formatDialInputToE164(
      _display,
      defaultCallingCode: _country.phoneCode,
    );
    if (to.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a phone number')),
      );
      return;
    }

    final allDigits = to.replaceAll(RegExp(r'\D'), '');
    final rawDigits = _display.replaceAll(RegExp(r'\D'), '');
    final trimmed = _display.trim();
    final tooShort = trimmed.startsWith('+')
        ? allDigits.length < 11
        : rawDigits.length < 10;
    if (tooShort) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a complete number for the selected country.'),
        ),
      );
      return;
    }

    final usable = await FirestoreUserService.fetchUsableCredits(widget.user.uid);
    if (!mounted) return;
    if (usable < CreditsPolicy.minCreditsToStartCallFor(widget.isPremium)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not enough credits')),
      );
      return;
    }

    final allowed = await _ensureCallPermissionsForVoip();
    if (!allowed || !mounted) return;

    setState(() {
      _callBusy = true;
      _apiConnecting = true;
    });
    _connectPulse.repeat();
    try {
      if (!mounted) return;

      // Outbound calls use Twilio Voice SDK only ([CallingScreen.placePstnCall]).
      // Do not call server GET /call here — it started a duplicate PSTN leg and could
      // confuse the SDK or Twilio (two outbound attempts).

      final result = await Navigator.of(context).push<CallingScreenResult?>(
        PageRouteBuilder<CallingScreenResult?>(
          opaque: true,
          transitionDuration: const Duration(milliseconds: 380),
          pageBuilder: (_, animation, secondaryAnimation) => CallingScreen(
            user: widget.user,
            dialE164: to,
          ),
          transitionsBuilder: (_, animation, _, child) {
            return FadeTransition(
              opacity: CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              ),
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.04),
                  end: Offset.zero,
                ).animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  ),
                ),
                child: child,
              ),
            );
          },
        ),
      );
      if (!mounted) return;
      final r = result;
      if (r == null) return;
      if (!r.insufficientCredits && !widget.isPremium) {
        unawaited(AdService.instance.loadAndShowInterstitialAd());
      }
      if (r.insufficientCredits) {
        final b = r.syncedBalance;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              b != null
                  ? 'Insufficient credits. Current balance: $b credits.'
                  : 'Insufficient credits',
            ),
          ),
        );
      } else if (r.serverBillingPending) {
        final b = r.syncedBalance;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              b != null
                  ? 'Balance still $b credits — server may be slow. If it does not drop, check Twilio '
                      'Status Callback → ${VoiceBackendConfig.baseUrl}/call-status'
                  : 'Credits usually update shortly after the call. If not, check Twilio Status Callback on your server.',
            ),
            duration: const Duration(seconds: 7),
          ),
        );
      } else if (r.syncedBalance != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Balance: ${r.syncedBalance} credits'),
          ),
        );
      }
    } finally {
      _connectPulse.stop();
      _connectPulse.reset();
      if (mounted) {
        setState(() {
          _callBusy = false;
          _apiConnecting = false;
        });
      }
    }
  }

  void _openCountryPicker() {
    HapticFeedback.selectionClick();
    showCountryPicker(
      context: context,
      showPhoneCode: true,
      favorite: const ['IN', 'US', 'GB', 'CA', 'AU', 'AE'],
      countryListTheme: CountryListThemeData(
        bottomSheetHeight: MediaQuery.sizeOf(context).height * 0.88,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
        backgroundColor: const Color(0xFF0B1220),
        textStyle: GoogleFonts.inter(
          color: Colors.white.withValues(alpha: 0.94),
          fontSize: 16,
        ),
        searchTextStyle: GoogleFonts.inter(color: Colors.white),
        inputDecoration: InputDecoration(
          filled: true,
          fillColor: const Color(0xFF151D2B),
          labelText: 'Search',
          labelStyle: GoogleFonts.inter(color: Colors.white54),
          hintText: 'Country or code',
          hintStyle: GoogleFonts.inter(color: Colors.white38),
          prefixIcon: Icon(
            Icons.search_rounded,
            color: premiumDialCallGreen.withValues(alpha: 0.9),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: Colors.white.withValues(alpha: 0.12),
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: Colors.white.withValues(alpha: 0.12),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: premiumDialCallGreen.withValues(alpha: 0.55),
            ),
          ),
        ),
      ),
      onSelect: (Country country) {
        HapticFeedback.selectionClick();
        setState(() => _country = country);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final compactDial = MediaQuery.sizeOf(context).height < 700;
    final fabBottom = MediaQuery.paddingOf(context).bottom +
        kBottomNavigationBarHeight +
        8;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Scaffold(
              backgroundColor: premiumDialBackground,
              body: SafeArea(
                bottom: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                        stream: FirestoreUserService.watchUserDocument(
                          widget.user.uid,
                        ),
                        builder: (context, creditSnap) {
                          final c = creditSnap.hasData
                              ? FirestoreUserService.usableCreditsFromSnapshot(
                                  creditSnap.data!,
                                )
                              : 0;
                          return _GlassCreditsCard(credits: c);
                        },
                      ),
                    ),
                    if (!kIsWeb && Platform.isAndroid) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: TextButton.icon(
                          onPressed: () async {
                            try {
                              await TwilioVoice.instance.openPhoneAccountSettings();
                            } catch (_) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Could not open Calling accounts.'),
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.phone_in_talk_rounded, size: 18),
                          label: Text(
                            'VoIP: enable TalkFree in Calling accounts (required once)',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: Colors.white60,
                              decoration: TextDecoration.underline,
                              decorationColor: Colors.white38,
                            ),
                            textAlign: TextAlign.start,
                          ),
                          style: TextButton.styleFrom(
                            alignment: Alignment.centerLeft,
                            padding: const EdgeInsets.symmetric(vertical: 4),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: _CountryPickerTile(
                        country: _country,
                        rateLine:
                            'Rate: ${CreditsPolicy.creditsPerMinuteForUser(widget.isPremium)} ⚡/min'
                            '${widget.isPremium ? ' (Pro)' : ''}',
                        onOpen: _openCountryPicker,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: _DialerNumberLine(
                              phoneCode: _country.phoneCode,
                              prettyDigits: _prettyDial(_display),
                              hasDigits: _display.isNotEmpty,
                              compactDial: compactDial,
                              digitFade: _digitFadeInCurve,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _DialerDeleteIconButton(
                            enabled: _display.isNotEmpty,
                            compact: compactDial,
                            onTap: _backspace,
                            onLongPress: _clearNumber,
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return SingleChildScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                minHeight: constraints.maxHeight,
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  PremiumIosDialPad(
                                    onDigit: _append,
                                    gap: compactDial ? 12 : 14,
                                    keyHeight: compactDial ? 52 : 56,
                                  ),
                                  SizedBox(height: compactDial ? 24 : 32),
                                  PremiumIosCallButton(
                                    busy: _callBusy,
                                    onPressed: _onCall,
                                  ),
                                  SizedBox(height: compactDial ? 28 : 32),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (widget.onEarnMinutes != null && !widget.isPremium)
              Positioned(
                right: 16,
                bottom: fabBottom,
                child: _DialerGetTwoMinsFab(
                  busy: widget.rewardedAdBusy,
                  cooldownRemaining: widget.cooldownRemaining,
                  cycleProgress: widget.rewardCycleProgress,
                  dailyLimitReached: widget.rewardDailyLimitReached,
                  onPressed: widget.onEarnMinutes!,
                ),
              ),
        if (_apiConnecting)
          Positioned.fill(
            child: AbsorbPointer(
              child: _DialerConnectingOverlay(
                pulse: _connectPulse,
              ),
            ),
          ),
      ],
    );
  }
}

/// Full-screen dim + neon green pulsing rings while [CallingScreen] opens (Twilio Voice SDK).
class _DialerConnectingOverlay extends StatelessWidget {
  const _DialerConnectingOverlay({required this.pulse});

  final Animation<double> pulse;

  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.52),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedBuilder(
                animation: pulse,
                builder: (context, _) {
                  final t = pulse.value;
                  return SizedBox(
                    width: 112,
                    height: 112,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        for (var i = 0; i < 3; i++)
                          _pulseRing(t, i),
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: premiumDialCallGreen.withValues(alpha: 0.18),
                            boxShadow: [
                              BoxShadow(
                                color: premiumDialCallGreen.withValues(
                                  alpha: 0.45,
                                ),
                                blurRadius: 20,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.phone_in_talk_rounded,
                            color: premiumDialCallGreen.withValues(alpha: 0.98),
                            size: 28,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 22),
              Text(
                'Connecting…',
                style: GoogleFonts.inter(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                  color: premiumDialCallGreen.withValues(alpha: 0.95),
                  shadows: [
                    Shadow(
                      color: premiumDialCallGreen.withValues(alpha: 0.55),
                      blurRadius: 12,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Reaching your TalkFree server',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Colors.white.withValues(alpha: 0.45),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pulseRing(double t, int index) {
    final phase = ((t + index * 0.28) % 1.0);
    final scale = 0.45 + phase * 0.95;
    return Transform.scale(
      scale: scale,
      child: Opacity(
        opacity: (1.0 - phase) * 0.85,
        child: Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: premiumDialCallGreen.withValues(alpha: 0.65),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: premiumDialCallGreen.withValues(alpha: 0.35),
                blurRadius: 18,
                spreadRadius: 0,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassCreditsCard extends StatelessWidget {
  const _GlassCreditsCard({required this.credits});

  final int credits;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: premiumDialCallGreen.withValues(alpha: 0.14),
            ),
            boxShadow: [
              BoxShadow(
                color: premiumDialCallGreen.withValues(alpha: 0.12),
                blurRadius: 20,
                spreadRadius: -4,
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.28),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.1),
                Colors.white.withValues(alpha: 0.03),
                premiumDialCallGreen.withValues(alpha: 0.05),
              ],
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: premiumDialCallGreen.withValues(alpha: 0.12),
                  boxShadow: [
                    BoxShadow(
                      color: premiumDialCallGreen.withValues(alpha: 0.18),
                      blurRadius: 12,
                      spreadRadius: -2,
                    ),
                  ],
                ),
                child: Icon(
                  Icons.bolt_rounded,
                  color: AppColors.accentAmber.withValues(alpha: 0.98),
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AVAILABLE CREDITS',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.6,
                        color: Colors.white.withValues(alpha: 0.45),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$credits',
                      style: GoogleFonts.inter(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        height: 1.0,
                        color: Colors.white.withValues(alpha: 0.96),
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Wallet',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.accentAmber.withValues(alpha: 0.9),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'balance',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.35),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CountryPickerTile extends StatelessWidget {
  const _CountryPickerTile({
    required this.country,
    required this.rateLine,
    required this.onOpen,
  });

  final Country country;
  final String rateLine;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(16),
        splashColor: premiumDialCallGreen.withValues(alpha: 0.12),
        highlightColor: Colors.white.withValues(alpha: 0.05),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: premiumDialCallGreen.withValues(alpha: 0.14),
            ),
            color: Colors.white.withValues(alpha: 0.04),
            boxShadow: [
              BoxShadow(
                color: premiumDialCallGreen.withValues(alpha: 0.1),
                blurRadius: 16,
                spreadRadius: -4,
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                country.flagEmoji,
                style: const TextStyle(fontSize: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      country.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.95),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '+${country.phoneCode}',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: premiumDialCallGreen.withValues(alpha: 0.9),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      rateLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                        color: premiumDialCallGreen.withValues(alpha: 0.95),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: premiumDialCallGreen.withValues(alpha: 0.85),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Country code + blinking caret when empty; dialed digits fade in subtly.
class _DialerNumberLine extends StatelessWidget {
  const _DialerNumberLine({
    required this.phoneCode,
    required this.prettyDigits,
    required this.hasDigits,
    required this.compactDial,
    required this.digitFade,
  });

  final String phoneCode;
  final String prettyDigits;
  final bool hasDigits;
  final bool compactDial;
  final Animation<double> digitFade;

  @override
  Widget build(BuildContext context) {
    final fontSize = compactDial ? 22.0 : 28.0;
    final style = GoogleFonts.inter(
      fontSize: fontSize,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.45,
      height: 1.2,
      color: Colors.white.withValues(alpha: 0.96),
      shadows: const [
        Shadow(
          color: Color(0x59000000),
          blurRadius: 10,
          offset: Offset(0, 2),
        ),
      ],
    );

    return Align(
      alignment: Alignment.center,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '+$phoneCode',
              style: style,
              textAlign: TextAlign.center,
            ),
            const SizedBox(width: 6),
            if (!hasDigits)
              _DialerBlinkingCaret(
                height: fontSize * 1.08,
                color: premiumDialCallGreen.withValues(alpha: 0.92),
              )
            else
              FadeTransition(
                opacity: digitFade,
                child: Text(
                  prettyDigits,
                  style: style,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DialerBlinkingCaret extends StatefulWidget {
  const _DialerBlinkingCaret({
    required this.height,
    required this.color,
  });

  final double height;
  final Color color;

  @override
  State<_DialerBlinkingCaret> createState() => _DialerBlinkingCaretState();
}

class _DialerBlinkingCaretState extends State<_DialerBlinkingCaret>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 530),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.35, end: 1.0).animate(
        CurvedAnimation(parent: _c, curve: Curves.easeInOut),
      ),
      child: Container(
        width: 2,
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(1),
          color: widget.color,
          boxShadow: [
            BoxShadow(
              color: widget.color.withValues(alpha: 0.45),
              blurRadius: 4,
            ),
          ],
        ),
      ),
    );
  }
}

class _DialerGetTwoMinsFab extends StatefulWidget {
  const _DialerGetTwoMinsFab({
    required this.busy,
    required this.cooldownRemaining,
    required this.cycleProgress,
    required this.dailyLimitReached,
    required this.onPressed,
  });

  final bool busy;
  final int cooldownRemaining;
  final int cycleProgress;
  final bool dailyLimitReached;
  final Future<void> Function() onPressed;

  @override
  State<_DialerGetTwoMinsFab> createState() => _DialerGetTwoMinsFabState();
}

class _DialerGetTwoMinsFabState extends State<_DialerGetTwoMinsFab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );
  late final Animation<double> _scale = Tween<double>(
    begin: 1.0,
    end: 1.055,
  ).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut));

  @override
  void initState() {
    super.initState();
    if (!widget.busy && !widget.dailyLimitReached && widget.cooldownRemaining <= 0) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant _DialerGetTwoMinsFab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.busy || widget.dailyLimitReached || widget.cooldownRemaining > 0) {
      _pulse.stop();
    } else if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tapLocked =
        widget.busy || widget.dailyLimitReached || widget.cooldownRemaining > 0;
    const fabSize = 56.0;
    final p = widget.cycleProgress.clamp(
      0,
      CreditsPolicy.adsRequiredForMinuteGrant,
    );
    final progressValue =
        CreditsPolicy.adsRequiredForMinuteGrant == 0
            ? 0.0
            : p / CreditsPolicy.adsRequiredForMinuteGrant;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          'Ad $p/${CreditsPolicy.adsRequiredForMinuteGrant} watched',
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: premiumDialCallGreen.withValues(alpha: 0.95),
            letterSpacing: 0.2,
            shadows: [
              Shadow(
                color: premiumDialCallGreen.withValues(alpha: 0.35),
                blurRadius: 8,
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: fabSize + 16,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progressValue,
              minHeight: 5,
              backgroundColor: Colors.white.withValues(alpha: 0.12),
              color: premiumDialCallGreen.withValues(alpha: 0.92),
            ),
          ),
        ),
        const SizedBox(height: 8),
        AnimatedBuilder(
          animation: _scale,
          builder: (context, child) {
            return Transform.scale(
              scale: (tapLocked) ? 1.0 : _scale.value,
              child: child,
            );
          },
          child: SizedBox(
            width: fabSize,
            height: fabSize,
            child: Material(
              color: Colors.transparent,
              elevation: 0,
              clipBehavior: Clip.antiAlias,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: tapLocked
                    ? null
                    : () async {
                        HapticFeedback.mediumImpact();
                        await widget.onPressed();
                      },
                splashColor: Colors.white.withValues(alpha: 0.22),
                child: Ink(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        premiumDialCallGreen.withValues(alpha: 0.92),
                        const Color(0xFF00A86B),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: premiumDialCallGreen.withValues(alpha: 0.2),
                        blurRadius: 20,
                        spreadRadius: -2,
                      ),
                      BoxShadow(
                        color: premiumDialCallGreen.withValues(alpha: 0.35),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Center(
                    child: widget.busy
                        ? SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: Colors.white.withValues(alpha: 0.95),
                            ),
                          )
                        : widget.dailyLimitReached
                            ? Icon(
                                Icons.block_rounded,
                                color: Colors.white.withValues(alpha: 0.75),
                                size: 26,
                              )
                        : widget.cooldownRemaining > 0
                            ? Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.timer_outlined,
                                    color: Colors.white.withValues(alpha: 0.95),
                                    size: 20,
                                  ),
                                  Text(
                                    '${widget.cooldownRemaining}s',
                                    style: GoogleFonts.inter(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white.withValues(alpha: 0.95),
                                      height: 1.0,
                                    ),
                                  ),
                                ],
                              )
                            : const Text(
                                '🎁',
                                style: TextStyle(fontSize: 28),
                              ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        if (widget.dailyLimitReached)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Text(
              'Limit Reached',
              textAlign: TextAlign.end,
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.5),
                height: 1.2,
              ),
            ),
          ),
      ],
    );
  }
}

class _DialerDeleteIconButton extends StatefulWidget {
  const _DialerDeleteIconButton({
    required this.enabled,
    required this.compact,
    required this.onTap,
    required this.onLongPress,
  });

  final bool enabled;
  final bool compact;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  State<_DialerDeleteIconButton> createState() =>
      _DialerDeleteIconButtonState();
}

class _DialerDeleteIconButtonState extends State<_DialerDeleteIconButton>
    with TickerProviderStateMixin {
  static const double _size = 50;
  static const Color _accent = premiumDialCallGreen;

  late final AnimationController _tapCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 120),
  );
  late final Animation<double> _tapScale = Tween<double>(begin: 1.0, end: 0.88)
      .animate(CurvedAnimation(parent: _tapCtrl, curve: Curves.easeOutCubic));

  /// Fluid pulse when long-press clears all digits.
  late final AnimationController _burstCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  late final Animation<double> _burstScale = Tween<double>(begin: 1.0, end: 1.12)
      .animate(CurvedAnimation(parent: _burstCtrl, curve: Curves.easeOutCubic));
  late final Animation<double> _glowT = CurvedAnimation(
    parent: _burstCtrl,
    curve: const Interval(0.0, 0.55, curve: Curves.easeOut),
  );

  @override
  void dispose() {
    _tapCtrl.dispose();
    _burstCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleTap() async {
    if (!widget.enabled) return;
    HapticFeedback.lightImpact();
    await _tapCtrl.forward();
    await _tapCtrl.reverse();
    widget.onTap();
  }

  Future<void> _handleLongPress() async {
    if (!widget.enabled) return;
    HapticFeedback.mediumImpact();
    try {
      await _burstCtrl.forward();
      widget.onLongPress();
      HapticFeedback.lightImpact();
      await _burstCtrl.reverse();
    } catch (_) {
      if (_burstCtrl.isAnimating || _burstCtrl.value > 0) {
        await _burstCtrl.reverse();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final iconSize = widget.compact ? 22.0 : 24.0;
    final enabled = widget.enabled;

    Widget buildButton(double tapS, double burstS, double glow) {
      final scale = tapS * burstS;
      return Transform.scale(
        scale: scale,
        child: ClipOval(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              width: _size,
              height: _size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.1),
                border: Border.all(
                  color: _accent.withValues(
                    alpha: enabled ? 0.14 + glow * 0.28 : 0.08,
                  ),
                ),
              ),
              child: Material(
                type: MaterialType.transparency,
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: enabled ? _handleTap : null,
                  onLongPress: enabled ? _handleLongPress : null,
                  splashFactory: InkRipple.splashFactory,
                  splashColor: _accent.withValues(alpha: 0.38),
                  highlightColor: _accent.withValues(alpha: 0.14),
                  radius: _size / 2,
                  child: SizedBox(
                    width: _size,
                    height: _size,
                    child: Center(
                      child: Icon(
                        Icons.backspace_rounded,
                        size: iconSize,
                        color: _accent.withValues(alpha: enabled ? 0.95 : 0.28),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Tooltip(
      message: 'Delete · long-press to clear all',
      child: AnimatedBuilder(
        animation: Listenable.merge([_tapCtrl, _burstCtrl]),
        builder: (context, child) {
          return buildButton(
            _tapScale.value,
            _burstScale.value,
            _glowT.value,
          );
        },
      ),
    );
  }
}
