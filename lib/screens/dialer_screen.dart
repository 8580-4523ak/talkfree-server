import 'dart:math' show min;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/credits_policy.dart';
import '../services/firestore_user_service.dart';
import '../widgets/premium_ios_dial_pad.dart';
import 'calling_screen.dart';

class DialerScreen extends StatefulWidget {
  const DialerScreen({super.key, required this.user});

  final User user;

  @override
  State<DialerScreen> createState() => _DialerScreenState();
}

class _DialerScreenState extends State<DialerScreen> {
  final StringBuffer _digits = StringBuffer();
  bool _callBusy = false;

  String get _display => _digits.toString();

  void _append(String ch) {
    setState(() => _digits.write(ch));
  }

  void _backspace() {
    final s = _display;
    if (s.isEmpty) return;
    setState(() {
      _digits.clear();
      if (s.length > 1) _digits.write(s.substring(0, s.length - 1));
    });
  }

  void _clearNumber() {
    if (_display.isEmpty) return;
    setState(_digits.clear);
  }

  static String normalizeToE164(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return '';
    if (t.startsWith('+')) {
      final d = t.substring(1).replaceAll(RegExp(r'\D'), '');
      return d.isEmpty ? '' : '+$d';
    }
    final d = t.replaceAll(RegExp(r'\D'), '');
    if (d.length == 10) return '+1$d';
    if (d.isNotEmpty) return '+$d';
    return '';
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
    if (s.isEmpty) return '+1 234 XXX XXXX';
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

  Future<void> _onCall(int credits) async {
    if (_callBusy) return;

    final to = normalizeToE164(_display);
    if (to.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a full number in E.164 (e.g. +1… or +91…).'),
        ),
      );
      return;
    }

    if (credits < CreditsPolicy.creditsPerCallTick) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Insufficient credits'),
        ),
      );
      return;
    }

    setState(() => _callBusy = true);
    try {
      final insufficient = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (_) => CallingScreen(
            user: widget.user,
            dialE164: to,
          ),
        ),
      );
      if (!mounted) return;
      if (insufficient == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Insufficient credits')),
        );
      }
    } finally {
      if (mounted) setState(() => _callBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: FirestoreUserService.watchCredits(widget.user.uid),
      builder: (context, creditSnap) {
        final credits = creditSnap.data ?? 0;
        final compactDial = MediaQuery.sizeOf(context).height < 700;

        return Scaffold(
              backgroundColor: premiumDialBackground,
              body: SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 24, 12, 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const SizedBox(width: 46),
                          Expanded(
                            child: Text(
                              _prettyDial(_display),
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(
                                fontSize: compactDial ? 24 : 30,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.65,
                                height: 1.2,
                                color: Colors.white.withValues(alpha: 0.98),
                                shadows: const [
                                  Shadow(
                                    color: Color(0x59000000),
                                    blurRadius: 12,
                                    offset: Offset(0, 2),
                                  ),
                                  Shadow(
                                    color: Color(0x33000000),
                                    blurRadius: 4,
                                    offset: Offset(0, 1),
                                  ),
                                ],
                              ),
                            ),
                          ),
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
                                  SizedBox(height: compactDial ? 28 : 36),
                                  PremiumIosCallButton(
                                    busy: _callBusy,
                                    onPressed: () => _onCall(credits),
                                  ),
                                  SizedBox(height: compactDial ? 20 : 28),
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
            );
      },
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
    with SingleTickerProviderStateMixin {
  static const double _size = 46;

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 115),
  );
  late final Animation<double> _scale = Tween<double>(begin: 1.0, end: 0.9)
      .animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic));
  late final Animation<double> _opacity = Tween<double>(begin: 1.0, end: 0.68)
      .animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _handleTap() async {
    if (!widget.enabled) return;
    await _c.forward();
    await _c.reverse();
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final iconSize = widget.compact ? 24.0 : 26.0;

    final core = Material(
      color: Colors.transparent,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: widget.enabled ? _handleTap : null,
        onLongPress: widget.enabled ? widget.onLongPress : null,
        splashColor: Colors.white.withValues(alpha: 0.14),
        highlightColor: Colors.white.withValues(alpha: 0.07),
        child: Ink(
          width: _size,
          height: _size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(
              alpha: widget.enabled ? 0.1 : 0.05,
            ),
            border: Border.all(
              color: Colors.white.withValues(
                alpha: widget.enabled ? 0.2 : 0.12,
              ),
            ),
          ),
          child: Center(
            child: Icon(
              Icons.backspace_outlined,
              size: iconSize,
              color: Colors.white.withValues(
                alpha: widget.enabled ? 0.84 : 0.26,
              ),
            ),
          ),
        ),
      ),
    );

    return Tooltip(
      message: 'Delete · long-press to clear',
      child: widget.enabled
          ? AnimatedBuilder(
              animation: _c,
              builder: (context, child) {
                return Transform.scale(
                  scale: _scale.value,
                  child: Opacity(
                    opacity: _opacity.value,
                    child: child,
                  ),
                );
              },
              child: core,
            )
          : core,
    );
  }
}
