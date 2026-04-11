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

  static String _formatSettledDate(Timestamp? ts) {
    if (ts == null) return '—';
    final d = ts.toDate().toLocal();
    const w = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
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
    final day = w[d.weekday - 1];
    final month = mo[d.month - 1];
    final h = d.hour.toString().padLeft(2, '0');
    final min = d.minute.toString().padLeft(2, '0');
    return '$day, $month ${d.day}, ${d.year} · $h:$min';
  }

  static int _creditsDeducted(Map<String, dynamic> data) {
    final charged = data['creditsCharged'];
    if (charged is num && charged > 0) return charged.round();
    final attempt = data['creditsAttempted'] ?? data['finalCharge'];
    if (attempt is num) return attempt.round();
    return 0;
  }

  static String _displayNumber(Map<String, dynamic> data) {
    final to = data['to'];
    if (to is String && to.trim().isNotEmpty) return to.trim();
    final from = data['from'];
    if (from is String && from.trim().isNotEmpty) return from.trim();
    return 'Unknown';
  }

  @override
  Widget build(BuildContext context) {
    final bg = Color.lerp(AppColors.darkBackgroundDeep, AppColors.darkBackground, 0.55)!;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
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
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final data = docs[i].data();
              final durationSec = data['durationSeconds'];
              final sec = durationSec is num ? durationSec.toInt() : 0;
              final settled = data['settledAt'] is Timestamp
                  ? data['settledAt'] as Timestamp
                  : null;
              final credits = _creditsDeducted(data);
              final number = _displayNumber(data);

              return _CallHistoryCard(
                phoneNumber: number,
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
    required this.dateLine,
    required this.durationLine,
    required this.creditsDeducted,
  });

  final String phoneNumber;
  final String dateLine;
  final String durationLine;
  final int creditsDeducted;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.surfaceDark.withValues(alpha: 0.94),
            const Color(0xFF0F172A).withValues(alpha: 0.98),
          ],
        ),
        border: Border.all(
          color: const Color(0xFF334155).withValues(alpha: 0.85),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.call_rounded,
                    color: AppColors.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        phoneNumber,
                        style: GoogleFonts.poppins(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textOnDark,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            Icons.calendar_today_outlined,
                            size: 14,
                            color: AppColors.textMutedOnDark.withValues(alpha: 0.9),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              dateLine,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: AppColors.textMutedOnDark,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _MetaChip(
                    icon: Icons.schedule_rounded,
                    label: durationLine,
                    caption: 'Duration',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _MetaChip(
                    icon: Icons.account_balance_wallet_outlined,
                    label: '-$creditsDeducted Credits',
                    caption: 'Deducted',
                    emphasize: true,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.icon,
    required this.label,
    required this.caption,
    this.emphasize = false,
  });

  final IconData icon;
  final String label;
  final String caption;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final labelColor = emphasize ? const Color(0xFFFF6B6B) : AppColors.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: emphasize
              ? const Color(0xFFFF6B6B).withValues(alpha: 0.35)
              : AppColors.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: labelColor.withValues(alpha: 0.95)),
              const SizedBox(width: 6),
              Text(
                caption,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                  color: AppColors.textMutedOnDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: GoogleFonts.jetBrainsMono(
              fontSize: emphasize ? 15 : 16,
              fontWeight: FontWeight.w600,
              color: labelColor,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}
