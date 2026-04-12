import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/firestore_user_service.dart';
import '../theme/app_colors.dart';
import '../theme/talkfree_colors.dart';

/// OTP / SMS inbox for the virtual 2nd line (`users/{uid}/messages`).
class InboxScreen extends StatelessWidget {
  const InboxScreen({super.key, required this.user});

  final User user;

  static DateTime _messageTime(Map<String, dynamic> data) {
    for (final key in ['createdAt', 'timestamp', 'receivedAt', 'date']) {
      final v = data[key];
      if (v is Timestamp) return v.toDate().toLocal();
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  static String _messageBody(Map<String, dynamic> data) {
    for (final key in ['body', 'text', 'message', 'Body']) {
      final v = data[key];
      if (v != null && v.toString().trim().isNotEmpty) {
        return v.toString();
      }
    }
    return '';
  }

  static String _messageFrom(Map<String, dynamic> data) {
    for (final key in ['from', 'fromNumber', 'From', 'sender']) {
      final v = data[key];
      if (v != null && v.toString().trim().isNotEmpty) {
        return v.toString();
      }
    }
    return 'Message';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.darkBackground,
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirestoreUserService.watchInboxMessages(user.uid),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Could not load inbox.\n${snap.error}',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    color: TalkFreeColors.mutedWhite,
                    height: 1.4,
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
          final sorted = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(
            docs,
          )..sort((a, b) {
              final ta = _messageTime(a.data());
              final tb = _messageTime(b.data());
              return tb.compareTo(ta);
            });

          if (sorted.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SvgPicture.asset(
                      'assets/svg/inbox_empty.svg',
                      width: 220,
                      height: 180,
                    ),
                    const SizedBox(height: 28),
                    Text(
                      'No messages yet',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: TalkFreeColors.offWhite,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'OTPs and SMS to your US line will show up here in real time.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        height: 1.5,
                        fontWeight: FontWeight.w500,
                        color: TalkFreeColors.mutedWhite,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            itemCount: sorted.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final doc = sorted[i];
              final data = doc.data();
              final body = _messageBody(data);
              final from = _messageFrom(data);
              final t = _messageTime(data);
              final timeLabel = t.millisecondsSinceEpoch == 0
                  ? ''
                  : _formatTime(t);

              return _InboxBubble(
                from: from,
                body: body.isEmpty ? '(Empty message)' : body,
                timeLabel: timeLabel,
              );
            },
          );
        },
      ),
    );
  }

  static String _formatTime(DateTime t) {
    final now = DateTime.now();
    final d = t;
    if (now.difference(d).inDays < 1 &&
        now.day == d.day &&
        now.month == d.month &&
        now.year == d.year) {
      final h = d.hour.toString().padLeft(2, '0');
      final m = d.minute.toString().padLeft(2, '0');
      return '$h:$m';
    }
    return '${d.day}/${d.month}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}

class _InboxBubble extends StatelessWidget {
  const _InboxBubble({
    required this.from,
    required this.body,
    required this.timeLabel,
  });

  final String from;
  final String body;
  final String timeLabel;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: AppColors.cardDark.withValues(alpha: 0.88),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(8),
            topRight: Radius.circular(20),
            bottomLeft: Radius.circular(20),
            bottomRight: Radius.circular(20),
          ),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.06),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.28),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.sms_outlined,
                  size: 18,
                  color: AppColors.primary.withValues(alpha: 0.95),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    from,
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: TalkFreeColors.offWhite,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (timeLabel.isNotEmpty)
                  Text(
                    timeLabel,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: TalkFreeColors.mutedWhite.withValues(alpha: 0.75),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              body,
              style: GoogleFonts.inter(
                fontSize: 15,
                height: 1.4,
                color: TalkFreeColors.offWhite.withValues(alpha: 0.95),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
