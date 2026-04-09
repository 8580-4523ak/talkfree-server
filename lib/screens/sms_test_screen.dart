import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/twilio_sms_service.dart';
import '../theme/talkfree_colors.dart';

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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a recipient phone number (E.164).')),
      );
      return;
    }
    final digitsOnly = to.replaceAll(RegExp(r'\D'), '');
    if (digitsOnly.length < 10 || to == '+1…' || to.contains('…')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Use a full E.164 number (e.g. +15551234567), not the hint text.',
          ),
        ),
      );
      return;
    }
    if (body.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a message.')),
      );
      return;
    }

    setState(() => _sending = true);
    try {
      await sendTwilioSMS(to, body);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('SMS sent. Check console for status code.')),
      );
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      final is401 = msg.contains('401') || msg.contains('20003');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            is401
                ? '401: Twilio rejected login. Fix .env — copy Account SID + '
                    'Auth Token from console.twilio.com (exact match, no spaces). '
                    'Then full restart the app.'
                : 'Failed: $e',
          ),
          duration: const Duration(seconds: 8),
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
                      color: TalkFreeColors.onPrimary,
                    ),
                  )
                : const Icon(Icons.sms_rounded, color: Colors.white),
            label: Text(
              _sending ? 'Sending…' : 'Send SMS',
              style: GoogleFonts.manrope(
                fontWeight: FontWeight.w700,
                color: TalkFreeColors.onPrimary,
              ),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: TalkFreeColors.beigeGold,
              foregroundColor: TalkFreeColors.onPrimary,
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
