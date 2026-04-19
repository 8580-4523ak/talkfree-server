import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/firestore_user_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/rewarded_ad_grant_flow.dart';
import '../utils/call_log_format.dart';

/// Neon-black call log list (`users/{uid}/call_history`).
class CallHistoryScreen extends StatelessWidget {
  const CallHistoryScreen({
    super.key,
    required this.user,
    this.onStartCalling,
    this.onWatchAd,
  });

  final User user;

  /// When set (e.g. from [DashboardScreen]), closes this route then switches to the Dialer tab.
  final VoidCallback? onStartCalling;

  /// Free tier: runs rewarded-ad flow from empty state.
  final Future<void> Function()? onWatchAd;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      appBar: AppBar(
        backgroundColor: AppTheme.darkBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          'Recent Calls',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w800,
            fontSize: 18,
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
            return _EmptyRecentsState(
              user: user,
              onStartCalling: onStartCalling,
              onWatchAd: onWatchAd,
            );
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
              final credits = CallLogFormat.creditsDeducted(data);
              final outgoing = CallLogFormat.isOutgoingFromDocument(data);
              final labels = CallLogFormat.callHistoryLabels(data, outgoing);
              final kind = CallLogFormat.callKind(data, outgoing, sec);
              final region = CallLogFormat.regionForPhone(labels.primary);

              return _CallHistoryCard(
                displayNumber: CallLogFormat.prettyDisplayNumber(labels.primary),
                regionFlag: region.flag,
                regionLabel: region.label,
                kind: kind,
                dateLine: CallLogFormat.formatSettledDate(settled),
                clockLine: CallLogFormat.formatClockTime(settled),
                durationLine: CallLogFormat.formatDurationMmSs(sec),
                creditsDeducted: credits,
              );
            },
          );
        },
      ),
    );
  }
}

class _EmptyRecentsState extends StatelessWidget {
  const _EmptyRecentsState({
    required this.user,
    this.onStartCalling,
    this.onWatchAd,
  });

  final User user;
  final VoidCallback? onStartCalling;
  final Future<void> Function()? onWatchAd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.call_outlined,
              size: 56,
              color: AppColors.textMutedOnDark.withValues(alpha: 0.45),
            ),
            const SizedBox(height: 20),
            Text(
              'Make your first call 🚀',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: AppColors.textOnDark,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Earn credits with ads, then call any number from the dialer.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 14,
                height: 1.5,
                color: AppColors.textMutedOnDark,
              ),
            ),
            const SizedBox(height: 28),
            if (onWatchAd != null) ...[
              StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: FirestoreUserService.watchUserDocument(user.uid),
                builder: (context, userSnap) {
                  final isPremium = FirestoreUserService.isPremiumFromUserData(
                    userSnap.data?.data(),
                  );
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () async {
                            await runRewardedAdGrantFlow(
                              context,
                              isPremium: isPremium,
                            );
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: AppColors.onPrimary,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            elevation: 0,
                          ),
                          child: Text(
                            'WATCH AD TO START',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.35,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                            onStartCalling?.call();
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.textOnDark,
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.2),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Text(
                            'Open dialer',
                            style: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ] else
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    onStartCalling?.call();
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                    shadowColor: Colors.transparent,
                  ),
                  child: Text(
                    'Start calling',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
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
    required this.displayNumber,
    required this.regionFlag,
    required this.regionLabel,
    required this.kind,
    required this.dateLine,
    required this.clockLine,
    required this.durationLine,
    required this.creditsDeducted,
  });

  final String displayNumber;
  final String regionFlag;
  final String regionLabel;
  final CallLogKind kind;
  final String dateLine;
  final String clockLine;
  final String durationLine;
  final int creditsDeducted;

  static const double _r = 18;

  IconData get _kindIcon {
    switch (kind) {
      case CallLogKind.outgoing:
        return Icons.call_made_rounded;
      case CallLogKind.incoming:
        return Icons.call_received_rounded;
      case CallLogKind.missed:
        return Icons.call_missed_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppTheme.surfaceCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_r),
        side: BorderSide(
          color: Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
              child: Icon(
                _kindIcon,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayNumber,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textOnDark,
                      letterSpacing: 0.1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        regionFlag,
                        style: const TextStyle(fontSize: 16),
                      ),
                      const SizedBox(width: 6),
                      if (regionLabel.isNotEmpty)
                        Text(
                          regionLabel,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textMutedOnDark,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$dateLine · $clockLine',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMutedOnDark.withValues(alpha: 0.95),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  durationLine,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textOnDark,
                  ),
                ),
                if (creditsDeducted > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    '-$creditsDeducted ⚡',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMutedOnDark.withValues(alpha: 0.75),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
