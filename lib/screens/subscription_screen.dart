import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';
import '../theme/talkfree_colors.dart';

/// Premium subscription plans UI (billing integration can wire [onSelectPlan] later).
class SubscriptionScreen extends StatelessWidget {
  const SubscriptionScreen({super.key});

  static const routeName = '/subscription';

  static Route<void> createRoute() {
    return MaterialPageRoute<void>(
      settings: const RouteSettings(name: routeName),
      builder: (_) => const SubscriptionScreen(),
    );
  }

  static const _goldPurple = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFE8C547),
      Color(0xFFC9A227),
      Color(0xFF9333EA),
      Color(0xFF581C87),
    ],
    stops: [0.0, 0.35, 0.62, 1.0],
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        title: Text(
          'TalkFree Pro',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(
            'Unlock ad-free calling, bonus credits, and a private number.',
            style: GoogleFonts.inter(
              fontSize: 15,
              height: 1.45,
              fontWeight: FontWeight.w500,
              color: TalkFreeColors.mutedWhite,
            ),
          ),
          const SizedBox(height: 20),
          ..._plans.map(
            (p) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _PlanGradientCard(
                plan: p,
                borderGradient: _goldPurple,
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        '${p.name} plan — checkout coming soon.',
                        style: GoogleFonts.inter(),
                      ),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanData {
  const _PlanData({
    required this.name,
    required this.price,
    required this.periodLabel,
    required this.benefits,
  });

  final String name;
  final String price;
  final String periodLabel;
  final List<String> benefits;
}

const _plans = <_PlanData>[
  _PlanData(
    name: 'Daily',
    price: r'$0.99',
    periodLabel: 'per day',
    benefits: ['No Ads', 'Bonus Credits', 'Private Number'],
  ),
  _PlanData(
    name: 'Weekly',
    price: r'$4.99',
    periodLabel: 'per week',
    benefits: ['No Ads', 'Bonus Credits', 'Private Number'],
  ),
  _PlanData(
    name: 'Monthly',
    price: r'$14.99',
    periodLabel: 'per month',
    benefits: ['No Ads', 'Bonus Credits', 'Private Number'],
  ),
  _PlanData(
    name: 'Yearly',
    price: r'$99.99',
    periodLabel: 'per year',
    benefits: ['No Ads', 'Bonus Credits', 'Private Number', 'Best value'],
  ),
];

class _PlanGradientCard extends StatelessWidget {
  const _PlanGradientCard({
    required this.plan,
    required this.borderGradient,
    required this.onTap,
  });

  final _PlanData plan;
  final Gradient borderGradient;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: borderGradient,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF9333EA).withValues(alpha: 0.25),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          padding: const EdgeInsets.all(2),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: TalkFreeColors.cardBg,
            ),
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        plan.name,
                        style: GoogleFonts.inter(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                          color: TalkFreeColors.offWhite,
                        ),
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        ShaderMask(
                          blendMode: BlendMode.srcIn,
                          shaderCallback: (bounds) =>
                              borderGradient.createShader(bounds),
                          child: Text(
                            plan.price,
                            style: GoogleFonts.inter(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          plan.periodLabel,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: TalkFreeColors.mutedWhite,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                ...plan.benefits.map(
                  (b) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.check_circle_rounded,
                          size: 18,
                          color: const Color(0xFFE8C547).withValues(alpha: 0.95),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            b,
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              height: 1.35,
                              fontWeight: FontWeight.w500,
                              color: TalkFreeColors.offWhite.withValues(
                                alpha: 0.92,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
