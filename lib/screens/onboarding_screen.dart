import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/legal_urls.dart';
import '../theme/talkfree_colors.dart';
import '../widgets/premium_backdrop.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onCarouselComplete});

  /// After the last onboarding page, user continues to plan selection (not auth yet).
  final VoidCallback onCarouselComplete;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _page = 0;

  static const int _pageCount = 3;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _onContinue() async {
    if (_page < _pageCount - 1) {
      await _pageController.nextPage(
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    if (!mounted) return;
    widget.onCarouselComplete();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TalkFreeColors.backgroundTop,
      body: PremiumBackdrop(
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: PageView(
                  controller: _pageController,
                  onPageChanged: (i) => setState(() => _page = i),
                  children: const [
                    _OnboardingPagePrivateNumber(),
                    _OnboardingPageSmsVerification(),
                    _OnboardingPageConnectWorldwide(),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                child: _PageDots(
                  count: _pageCount,
                  index: _page,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: FilledButton(
                    onPressed: _onContinue,
                    style: FilledButton.styleFrom(
                      backgroundColor: TalkFreeColors.beigeGold,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      'Continue',
                      style: GoogleFonts.montserrat(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 20,
                  children: [
                    TextButton(
                      onPressed: () => _openUrl(LegalUrls.termsOfUse),
                      child: Text(
                        'Terms Of Use',
                        style: GoogleFonts.montserrat(
                          fontSize: 12,
                          color: TalkFreeColors.mutedWhite,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => _openUrl(LegalUrls.privacyPolicy),
                      child: Text(
                        'Privacy Policy',
                        style: GoogleFonts.montserrat(
                          fontSize: 12,
                          color: TalkFreeColors.mutedWhite,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PageDots extends StatelessWidget {
  const _PageDots({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final active = i == index;
        if (active) {
          return AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: 22,
            height: 8,
            decoration: BoxDecoration(
              color: TalkFreeColors.beigeGold,
              borderRadius: BorderRadius.circular(999),
            ),
          );
        }
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: TalkFreeColors.beigeGold.withValues(alpha: 0.28),
            shape: BoxShape.circle,
          ),
        );
      }),
    );
  }
}

class _HeroPhotoStrip extends StatelessWidget {
  const _HeroPhotoStrip({this.extraDark = false});

  final bool extraDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 200,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            TalkFreeColors.cardBg.withValues(alpha: 0.55),
            TalkFreeColors.backgroundTop.withValues(alpha: 0.95),
          ],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(painter: _SilhouettePainter(dark: extraDark)),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  TalkFreeColors.backgroundTop.withValues(alpha: 0.88),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SilhouettePainter extends CustomPainter {
  _SilhouettePainter({required this.dark});

  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = TalkFreeColors.offWhite.withValues(alpha: dark ? 0.04 : 0.07)
      ..style = PaintingStyle.fill;
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(w * 0.35, h * 0.95)
      ..quadraticBezierTo(w * 0.42, h * 0.35, w * 0.52, h * 0.28)
      ..quadraticBezierTo(w * 0.62, h * 0.22, w * 0.68, h * 0.45)
      ..lineTo(w * 0.72, h * 0.95)
      ..close();
    canvas.drawPath(path, paint);
    final phone = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.48, h * 0.38, w * 0.12, h * 0.22),
      const Radius.circular(6),
    );
    canvas.drawRRect(phone, paint);
  }

  @override
  bool shouldRepaint(covariant _SilhouettePainter oldDelegate) =>
      oldDelegate.dark != dark;
}

class _OnboardingPagePrivateNumber extends StatelessWidget {
  const _OnboardingPagePrivateNumber();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          const _HeroPhotoStrip(),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: TalkFreeColors.beigeGold.withValues(alpha: 0.65),
              ),
            ),
            child: Text(
              '***',
              style: GoogleFonts.montserrat(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: TalkFreeColors.offWhite,
                letterSpacing: 4,
              ),
            ),
          ),
          const SizedBox(height: 28),
          Text(
            'Get Your Private Second Number!',
            textAlign: TextAlign.center,
            style: GoogleFonts.montserrat(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              height: 1.25,
              color: TalkFreeColors.beigeGold,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Manage calls, send SMS, and MMS all from one app.',
            textAlign: TextAlign.center,
            style: GoogleFonts.montserrat(
              fontSize: 15,
              height: 1.45,
              fontWeight: FontWeight.w500,
              color: TalkFreeColors.offWhite.withValues(alpha: 0.92),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Your privacy, your control.',
            textAlign: TextAlign.center,
            style: GoogleFonts.montserrat(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: TalkFreeColors.offWhite,
            ),
          ),
          const SizedBox(height: 36),
          _FeatureIconRow(),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

class _FeatureIconRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    Widget line() => Expanded(
          child: Container(
            height: 1,
            color: TalkFreeColors.offWhite.withValues(alpha: 0.2),
          ),
        );
    Widget circle(IconData icon) {
      return Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: TalkFreeColors.offWhite.withValues(alpha: 0.45),
          ),
        ),
        child: Icon(icon, color: TalkFreeColors.offWhite, size: 24),
      );
    }

    return Row(
      children: [
        line(),
        circle(Icons.chat_bubble_outline_rounded),
        line(),
        circle(Icons.smartphone_outlined),
        line(),
        circle(Icons.phone_in_talk_outlined),
        line(),
      ],
    );
  }
}

class _OnboardingPageSmsVerification extends StatelessWidget {
  const _OnboardingPageSmsVerification();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          const _HeroPhotoStrip(extraDark: true),
          const SizedBox(height: 24),
          Icon(
            Icons.verified_user_outlined,
            size: 48,
            color: TalkFreeColors.offWhite.withValues(alpha: 0.9),
          ),
          const SizedBox(height: 24),
          Text(
            'Guaranteed SMS Verification',
            textAlign: TextAlign.center,
            style: GoogleFonts.montserrat(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              height: 1.25,
              color: TalkFreeColors.beigeGold,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Use virtual phone numbers for OTPs and calls, enhancing your online privacy.',
            textAlign: TextAlign.center,
            style: GoogleFonts.montserrat(
              fontSize: 15,
              height: 1.45,
              fontWeight: FontWeight.w500,
              color: TalkFreeColors.offWhite.withValues(alpha: 0.9),
            ),
          ),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(4, (i) {
              return Container(
                width: 44,
                margin: const EdgeInsets.symmetric(horizontal: 8),
                padding: const EdgeInsets.only(bottom: 6),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: TalkFreeColors.offWhite.withValues(alpha: 0.55),
                      width: 2,
                    ),
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  i == 0 ? '*' : '',
                  style: GoogleFonts.montserrat(
                    fontSize: 22,
                    color: TalkFreeColors.offWhite,
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 28),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: TalkFreeColors.cardBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: TalkFreeColors.beigeGold.withValues(alpha: 0.75),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.sms_outlined,
                  color: TalkFreeColors.beigeGold,
                  size: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Your verification code: 4769. Please enter the verification code on your phone.',
                    style: GoogleFonts.montserrat(
                      fontSize: 13,
                      height: 1.4,
                      color: TalkFreeColors.offWhite.withValues(alpha: 0.88),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

class _OnboardingPageConnectWorldwide extends StatelessWidget {
  const _OnboardingPageConnectWorldwide();

  static const _regions = [
    'Africa',
    'Asia',
    'Europe',
    'North America',
    'Latin America',
    'MENA',
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          const _HeroPhotoStrip(extraDark: true),
          const SizedBox(height: 28),
          Icon(
            Icons.sim_card_outlined,
            size: 48,
            color: TalkFreeColors.offWhite.withValues(alpha: 0.92),
          ),
          const SizedBox(height: 20),
          Text(
            'Connect Worldwide',
            textAlign: TextAlign.center,
            style: GoogleFonts.montserrat(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: TalkFreeColors.beigeGold,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Connect instantly all over the world with eSIM. Find affordable & high-quality data packages.',
            textAlign: TextAlign.center,
            style: GoogleFonts.montserrat(
              fontSize: 14,
              height: 1.45,
              fontWeight: FontWeight.w500,
              color: TalkFreeColors.offWhite.withValues(alpha: 0.9),
            ),
          ),
          const SizedBox(height: 28),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _regions.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.35,
            ),
            itemBuilder: (context, i) {
              final label = _regions[i];
              return Container(
                decoration: BoxDecoration(
                  color: TalkFreeColors.cardBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: TalkFreeColors.beigeGold.withValues(alpha: 0.55),
                  ),
                ),
                padding: const EdgeInsets.all(10),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(
                      child: CustomPaint(
                        painter: _MiniMapBlobPainter(seed: i),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.montserrat(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: TalkFreeColors.offWhite,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _MiniMapBlobPainter extends CustomPainter {
  _MiniMapBlobPainter({required this.seed});

  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = TalkFreeColors.beigeGold.withValues(alpha: 0.55)
      ..style = PaintingStyle.fill;
    final cx = size.width * 0.5;
    final cy = size.height * 0.45;
    final r = size.width * 0.22 + (seed % 3) * 2.0;
    canvas.drawCircle(Offset(cx, cy), r, paint);
    canvas.drawCircle(Offset(cx - r * 0.4, cy + r * 0.2), r * 0.35, paint);
  }

  @override
  bool shouldRepaint(covariant _MiniMapBlobPainter oldDelegate) =>
      oldDelegate.seed != seed;
}
