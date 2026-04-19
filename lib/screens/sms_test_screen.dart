import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/app_snackbar.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/twilio_sms_service.dart' show TwilioSmsException, sendTwilioSMS;
import '../utils/user_facing_service_error.dart';

/// Simple screen to exercise [sendTwilioSMS] (Twilio trial: To-number often must be verified).
class SmsTestScreen extends StatefulWidget {
  const SmsTestScreen({super.key});

  @override
  State<SmsTestScreen> createState() => _SmsTestScreenState();
}

class _SmsTestScreenState extends State<SmsTestScreen> {
  final _phoneCtrl = TextEditingController();
  final _messageCtrl = TextEditingController(text: 'Hello from TalkFree!');
  bool _sending = false;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final to = _phoneCtrl.text.trim();
    final body = _messageCtrl.text.trim();
    if (to.isEmpty) {
      AppSnackBar.show(
        context,
        SnackBar(
          content: const Text('Enter a recipient phone number (E.164).'),
          behavior: SnackBarBehavior.floating,
          margin: AppTheme.snackBarFloatingMargin(context),
          duration: AppTheme.snackBarCalmDuration,
        ),
      );
      return;
    }
    final digitsOnly = to.replaceAll(RegExp(r'\D'), '');
    if (digitsOnly.length < 10 || to == '+1…' || to.contains('…')) {
      AppSnackBar.show(
        context,
        SnackBar(
          content: const Text(
            'Use a full E.164 number (e.g. +15551234567), not the hint text.',
          ),
          behavior: SnackBarBehavior.floating,
          margin: AppTheme.snackBarFloatingMargin(context),
          duration: AppTheme.snackBarCalmDuration,
        ),
      );
      return;
    }
    if (body.isEmpty) {
      AppSnackBar.show(
        context,
        SnackBar(
          content: const Text('Enter a message.'),
          behavior: SnackBarBehavior.floating,
          margin: AppTheme.snackBarFloatingMargin(context),
          duration: AppTheme.snackBarCalmDuration,
        ),
      );
      return;
    }

    setState(() => _sending = true);
    try {
      await sendTwilioSMS(to, body);
      if (!mounted) return;
      AppSnackBar.show(
        context,
        SnackBar(
          content: const Text('SMS sent.'),
          behavior: SnackBarBehavior.floating,
          margin: AppTheme.snackBarFloatingMargin(context),
          duration: AppTheme.snackBarCalmDuration,
        ),
      );
    } on TwilioSmsException catch (e) {
      if (!mounted) return;
      final is502 = e.statusCode == 502;
      final is401 = e.statusCode == 401;
      final text = is401
          ? 'Sign-in expired or invalid. Sign out and back in, then try again.'
          : userFacingServiceError(e.message);
      AppSnackBar.show(
        context,
        SnackBar(
          content: SelectableText(
            text,
            style: GoogleFonts.inter(
              fontSize: 14,
              height: 1.35,
              color: Colors.white,
            ),
          ),
          duration: Duration(seconds: is502 ? 14 : is401 ? 8 : 10),
          behavior: SnackBarBehavior.floating,
          margin: AppTheme.snackBarFloatingMargin(context),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      AppSnackBar.show(
        context,
        SnackBar(
          content: Text('Failed: $e'),
          duration: const Duration(seconds: 8),
          behavior: SnackBarBehavior.floating,
          margin: AppTheme.snackBarFloatingMargin(context),
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      appBar: AppBar(
        title: const Text('Send test SMS'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Recipient (E.164, e.g. +15551234567)',
            style: theme.textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              hintText: '+1…',
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Message',
            style: theme.textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _messageCtrl,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: 'Type your message…',
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _sending ? null : _send,
            icon: _sending
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Theme.of(context).colorScheme.onPrimary,
                    ),
                  )
                : const Icon(Icons.sms_rounded, color: Colors.white),
            label: Text(
              _sending ? 'Sending…' : 'Send SMS',
              style: GoogleFonts.manrope(
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onPrimary,
              ),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.neonGreen,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
