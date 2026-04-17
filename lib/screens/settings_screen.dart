import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../auth_service.dart';
import '../config/legal_urls.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'about_screen.dart';
import 'call_history_screen.dart';
import 'sms_test_screen.dart';
import 'subscription_screen.dart';
import 'virtual_number_screen.dart';

/// Hub for account, shortcuts, legal links, and sign-out (replaces crowded app-bar icons).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.user,
    required this.credits,
    this.isPremium = false,
  });

  final User user;
  final int credits;
  final bool isPremium;

  Future<void> _openUrl(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open link: $url')),
      );
    }
  }

  Future<void> _confirmSignOut(BuildContext context) async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: (Theme.of(context).cardTheme.color ?? Theme.of(context).colorScheme.surface),
            title: Text(
              'Sign out?',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            content: Text(
              'You will need to sign in again to use TalkFree.',
              style: GoogleFonts.inter(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(
                  'Cancel',
                  style: GoogleFonts.inter(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Sign out'),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok || !context.mounted) return;
    await AuthService().signOut();
  }

  String get _accountLine {
    if (user.isAnonymous) return 'Guest session · credits & number stay on this device';
    final e = user.email?.trim();
    if (e != null && e.isNotEmpty) return e;
    return 'Signed in with Google';
  }

  @override
  Widget build(BuildContext context) {
    final name = user.displayName?.trim();
    final displayName =
        name != null && name.isNotEmpty ? name : 'TalkFree user';
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      appBar: AppBar(
        backgroundColor: AppTheme.darkBg,
        elevation: 0,
        foregroundColor: Colors.white,
        title: Text(
          'Profile',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w800,
            fontSize: 18,
            letterSpacing: 0.2,
          ),
        ),
        centerTitle: true,
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        padding: EdgeInsets.fromLTRB(16, 8, 16, 24 + bottom),
        children: [
          _ProfileHeaderCard(
            displayName: displayName,
            credits: credits,
            isPremium: isPremium,
            subtitle: _accountLine,
          ),
          const SizedBox(height: 20),
          _SectionLabel('Account'),
          _SettingsCard(
            children: [
              _tile(
                context,
                icon: Icons.workspace_premium_outlined,
                title: 'TalkFree Pro',
                subtitle: 'Plans, billing & premium perks',
                onTap: () {
                  Navigator.of(context).push<void>(
                    SubscriptionScreen.createRoute(),
                  );
                },
              ),
              _divider(),
              _tile(
                context,
                icon: Icons.contact_phone_outlined,
                title: 'My US number',
                subtitle: 'Claim, renew, or browse numbers',
                onTap: () {
                  Navigator.of(context).pushNamed(
                    VirtualNumberScreen.routeName,
                    arguments: VirtualNumberRouteArgs(
                      userUid: user.uid,
                      userCredits: credits,
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 20),
          _SectionLabel('Calling'),
          _SettingsCard(
            children: [
              _tile(
                context,
                icon: Icons.history_rounded,
                title: 'Call history',
                subtitle: 'Recent calls on your TalkFree line',
                onTap: () {
                  Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => CallHistoryScreen(user: user),
                    ),
                  );
                },
              ),
              _divider(),
              _tile(
                context,
                icon: Icons.chat_bubble_outline_rounded,
                title: 'Messages',
                subtitle: 'SMS test & inbox shortcuts',
                onTap: () {
                  Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => const SmsTestScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 20),
          _SectionLabel('Support & legal'),
          _SettingsCard(
            children: [
              _tile(
                context,
                icon: Icons.info_outline_rounded,
                title: 'App info',
                subtitle: 'Version, credits progress, about TalkFree',
                onTap: () {
                  Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => const AboutScreen(),
                    ),
                  );
                },
              ),
              _divider(),
              _tile(
                context,
                icon: Icons.description_outlined,
                title: 'Terms of use',
                onTap: () => _openUrl(context, LegalUrls.termsOfUse),
              ),
              _divider(),
              _tile(
                context,
                icon: Icons.privacy_tip_outlined,
                title: 'Privacy policy',
                onTap: () => _openUrl(context, LegalUrls.privacyPolicy),
              ),
            ],
          ),
          const SizedBox(height: 28),
          _SettingsCard(
            children: [
              ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                leading: Icon(
                  Icons.logout_rounded,
                  color: AppColors.danger.withValues(alpha: 0.95),
                ),
                title: Text(
                  'Sign out',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: AppColors.danger,
                  ),
                ),
                subtitle: Text(
                  user.isAnonymous
                      ? 'Ends guest session on this device'
                      : 'Disconnect Google and return to login',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.85),
                    height: 1.35,
                  ),
                ),
                onTap: () => _confirmSignOut(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tile(
    BuildContext context, {
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Icon(
        icon,
        color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
      ),
      title: Text(
        title,
        style: GoogleFonts.inter(
          fontWeight: FontWeight.w600,
          fontSize: 16,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.88),
                height: 1.35,
              ),
            ),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.45),
      ),
      onTap: onTap,
    );
  }

  static Widget _divider() => Divider(
        height: 1,
        thickness: 1,
        indent: 56,
        color: Colors.white.withValues(alpha: 0.06),
      );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
      child: Text(
        text,
        style: GoogleFonts.inter(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: AppColors.primary.withValues(alpha: 0.85),
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

class _ProfileHeaderCard extends StatelessWidget {
  const _ProfileHeaderCard({
    required this.displayName,
    required this.credits,
    required this.isPremium,
    required this.subtitle,
  });

  final String displayName;
  final int credits;
  final bool isPremium;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              displayName,
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700,
                fontSize: 22,
                letterSpacing: -0.3,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              isPremium ? 'TalkFree Pro · unlimited calling' : 'Credits: $credits',
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: GoogleFonts.inter(
                fontSize: 12,
                height: 1.35,
                color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.85),
              ),
            ),
            if (!isPremium) ...[
              const SizedBox(height: 16),
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.22),
                      blurRadius: 16,
                      spreadRadius: -2,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: FilledButton(
                  onPressed: () {
                    Navigator.of(context).push<void>(
                      SubscriptionScreen.createRoute(),
                    );
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    'GO PRO',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
