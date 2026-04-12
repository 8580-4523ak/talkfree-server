import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/firestore_user_service.dart';
import '../theme/app_colors.dart';

/// Dark, styled list of completed calls (Firestore `users/{uid}/call_history`).
class CallHistoryScreen extends StatelessWidget {
  const CallHistoryScreen({super.key, required this.user});

  final User user;

  static String _formatDurationMmSs(int seconds) {
    final s = seconds < 0 ? 0 : seconds;
    final m = s ~/ 60;
    final r = s % 60;
    return '${m.toString().padLeft(2, '0')}:${r.toString().padLeft(2, '0')}';
  }

  /// `Today`, `Yesterday`, or `12 Apr` (adds year if not current year).
  static String _formatSettledDate(Timestamp? ts) {
    if (ts == null) return '—';
    final d = ts.toDate().toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final cal = DateTime(d.year, d.month, d.day);
    const mo = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    if (cal == today) return 'Today';
    if (cal == yesterday) return 'Yesterday';
    if (d.year == now.year) {
      return '${d.day} ${mo[d.month - 1]}';
    }
    return '${d.day} ${mo[d.month - 1]} ${d.year}';
  }

  static int _creditsDeducted(Map<String, dynamic> data) {
    final charged = data['creditsCharged'];
    if (charged is num && charged > 0) return charged.round();
    final attempt = data['creditsAttempted'] ?? data['finalCharge'];
    if (attempt is num) return attempt.round();
    return 0;
  }

  /// First human phone on either leg (skips `client:…` Voice SDK identities).
  static String? _firstPstnNumber(Map<String, dynamic> data) {
    for (final leg in <Object?>[data['from'], data['to']]) {
      final s = (leg ?? '').toString().trim();
      if (s.isEmpty) continue;
      if (s.toLowerCase().startsWith('client:')) continue;
      return s;
    }
    return null;
  }

  /// Prefer the **other party** number: outbound (`From`=client) → `To`; inbound (`To`=client) → `From`.
  static String _peerPhoneNumber(Map<String, dynamic> data) {
    final from = (data['from'] ?? '').toString().trim();
    final to = (data['to'] ?? '').toString().trim();
    final fl = from.toLowerCase();
    final tl = to.toLowerCase();
    if (fl.startsWith('client:')) return to;
    if (tl.startsWith('client:')) return from;
    if (to.isNotEmpty) return to;
    if (from.isNotEmpty) return from;
    return '';
  }

  /// Voice SDK outbound: `From` is `client:<firebaseUid>`. Inbound to app: `To` is `client:…`.
  static bool _isOutgoingCall(Map<String, dynamic> data) {
    final from = (data['from'] ?? '').toString().toLowerCase();
    return from.startsWith('client:');
  }

  /// Prefer explicit `direction` from Firestore (`outgoing` / `incoming`), else infer from `from`/`to`.
  static bool _isOutgoingFromDocument(Map<String, dynamic> data) {
    final raw = data['direction'];
    if (raw is String) {
      final t = raw.toLowerCase().trim();
      if (t == 'outgoing') return true;
      if (t == 'incoming') return false;
    }
    return _isOutgoingCall(data);
  }

  /// Mask `client:…` legs; real PSTN (+1…, +91…) shown as-is.
  static String _maskClientIdForTitle(String value, bool outgoing) {
    final t = value.trim();
    if (t.isEmpty) return value;
    if (t.toLowerCase().startsWith('client:')) {
      return outgoing ? 'Private Line' : 'TalkFree User';
    }
    return value;
  }

  /// Primary line: PSTN as-is; `client:` → Private Line (out) / TalkFree User (in).
  static ({String primary, String? subtitle}) _callHistoryLabels(
    Map<String, dynamic> data,
    bool outgoing,
  ) {
    final pstn = _firstPstnNumber(data);
    if (pstn != null) {
      return (primary: pstn, subtitle: null);
    }
    final peer = _peerPhoneNumber(data);
    if (peer.isEmpty) {
      return (primary: 'Unknown', subtitle: null);
    }
    return (
      primary: _maskClientIdForTitle(peer, outgoing),
      subtitle: null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        backgroundColor: AppColors.darkBackground,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          'Call history',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w700,
            fontSize: 20,
            color: AppColors.textOnDark,
          ),
        ),
        iconTheme: const IconThemeData(color: AppColors.textOnDark),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirestoreUserService.watchCallHistory(user.uid),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Could not load history.\n${snap.error}',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    color: AppColors.textMutedOnDark,
                    height: 1.45,
                  ),
                ),
              ),
            );
          }
          if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
            return const Center(
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: AppColors.primary,
              ),
            );
          }

          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return _EmptyHistoryState();
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            itemCount: docs.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final data = docs[i].data();
              final durationSec = data['durationSeconds'];
              final sec = durationSec is num ? durationSec.toInt() : 0;
              final settled = data['settledAt'] is Timestamp
                  ? data['settledAt'] as Timestamp
                  : null;
              final credits = _creditsDeducted(data);
              final outgoing = _isOutgoingFromDocument(data);
              final labels = _callHistoryLabels(data, outgoing);

              return _CallHistoryCard(
                phoneNumber: labels.primary,
                numberSubtitle: labels.subtitle,
                isOutgoing: outgoing,
                dateLine: _formatSettledDate(settled),
                durationLine: _formatDurationMmSs(sec),
                creditsDeducted: credits,
              );
            },
          );
        },
      ),
    );
  }
}

class _EmptyHistoryState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.phone_missed_outlined,
              size: 56,
              color: AppColors.textMutedOnDark.withValues(alpha: 0.65),
            ),
            const SizedBox(height: 20),
            Text(
              'No calls yet',
              style: GoogleFonts.poppins(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: AppColors.textOnDark,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Completed calls will appear here with duration and credits used.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 15,
                height: 1.5,
                color: AppColors.textMutedOnDark,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CallHistoryCard extends StatelessWidget {
  const _CallHistoryCard({
    required this.phoneNumber,
    this.numberSubtitle,
    required this.isOutgoing,
    required this.dateLine,
    required this.durationLine,
    required this.creditsDeducted,
  });

  final String phoneNumber;
  final String? numberSubtitle;
  final bool isOutgoing;
  final String dateLine;
  final String durationLine;
  final int creditsDeducted;

  static const double _r = 20;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_r),
        color: AppColors.cardDark.withValues(alpha: 0.88),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.06),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              isOutgoing ? '↗️' : '↙️',
              style: GoogleFonts.inter(
                fontSize: 20,
                height: 1,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  phoneNumber,
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textOnDark,
                    letterSpacing: 0.1,
                  ),
                ),
                if (numberSubtitle != null && numberSubtitle!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    numberSubtitle!,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: AppColors.textMutedOnDark,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  durationLine,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textMutedOnDark.withValues(alpha: 0.85),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  dateLine,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppColors.textMutedOnDark.withValues(alpha: 0.65),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.danger.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: AppColors.danger.withValues(alpha: 0.35),
              ),
            ),
            child: Text(
              '-$creditsDeducted',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: AppColors.danger.withValues(alpha: 0.95),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
