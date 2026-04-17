import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../config/razorpay_config.dart';
import '../services/subscription_payment_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/neon_tokens.dart';
import '../widgets/glass_panel.dart';

/// Premium subscription plans + Razorpay Checkout (see also `premium_screen.dart`).
class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  static const routeName = '/subscription';

  static Route<void> createRoute() {
    return MaterialPageRoute<void>(
      settings: const RouteSettings(name: routeName),
      builder: (_) => const SubscriptionScreen(),
    );
  }

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  late Razorpay _razorpay;
  bool _checkoutOpen = false;

  @override
  void initState() {
    super.initState();
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onPaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _onPaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _onExternalWallet);
  }

  @override
  void dispose() {
    _razorpay.clear();
    super.dispose();
  }

  Future<void> _onPaymentSuccess(PaymentSuccessResponse r) async {
    if (!mounted) return;
    setState(() => _checkoutOpen = false);
    if (FirebaseAuth.instance.currentUser == null) {
      _showPaymentFailedDialog('Not signed in. Your payment may still be valid — sign in and contact support.');
      return;
    }
    final plan = _pendingPlanKey;
    if (plan == null) return;
    final paymentId = r.paymentId?.trim();
    final orderId = r.orderId?.trim();
    final signature = r.signature?.trim();
    if (paymentId == null ||
        paymentId.isEmpty ||
        orderId == null ||
        orderId.isEmpty ||
        signature == null ||
        signature.isEmpty) {
      _pendingPlanKey = null;
      _showPaymentFailedDialog(
        'Missing payment verification data. If you were charged, contact support with your receipt.',
      );
      return;
    }
    try {
      await SubscriptionPaymentService.instance.verifyPayment(
        razorpayPaymentId: paymentId,
        razorpayOrderId: orderId,
        razorpaySignature: signature,
      );
      _pendingPlanKey = null;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Welcome to TalkFree Pro — your plan is active.',
            style: GoogleFonts.inter(fontWeight: FontWeight.w600),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).maybePop();
    } on SubscriptionPaymentException catch (e) {
      _pendingPlanKey = null;
      if (!mounted) return;
      _showPaymentFailedDialog(
        'Payment could not be verified: ${e.message}',
      );
    } catch (e) {
      _pendingPlanKey = null;
      if (!mounted) return;
      _showPaymentFailedDialog(
        'Payment succeeded but verification failed: $e',
      );
    }
  }

  void _onPaymentError(PaymentFailureResponse r) {
    if (!mounted) return;
    _pendingPlanKey = null;
    setState(() => _checkoutOpen = false);
    final code = r.code;
    if (code == Razorpay.PAYMENT_CANCELLED) {
      _showPaymentFailedDialog('Payment cancelled.');
      return;
    }
    _showPaymentFailedDialog(r.message ?? 'Payment failed. Please try again.');
  }

  void _onExternalWallet(ExternalWalletResponse r) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Complete payment in ${r.walletName ?? "your wallet"}.',
          style: GoogleFonts.inter(),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String? _pendingPlanKey;

  Future<void> _startCheckout(_PlanCheckout plan) async {
    final key = RazorpayConfig.keyId;
    if (key == null || key.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Add RAZORPAY_KEY_ID to project root .env (copy .env.example), then flutter run. '
            'Or: flutter run --dart-define=RAZORPAY_KEY_ID=rzp_test_xxx',
            style: GoogleFonts.inter(),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sign in to subscribe.', style: GoogleFonts.inter()),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    _pendingPlanKey = plan.planKey;

    SubscriptionOrderResponse order;
    try {
      order = await SubscriptionPaymentService.instance
          .createSubscriptionOrder(plan.planKey);
    } on SubscriptionPaymentException catch (e) {
      if (!mounted) return;
      _pendingPlanKey = null;
      _showPaymentFailedDialog(
        e.message.isNotEmpty
            ? e.message
            : 'Could not start checkout (HTTP ${e.statusCode}).',
      );
      return;
    } catch (e) {
      if (!mounted) return;
      _pendingPlanKey = null;
      _showPaymentFailedDialog('Could not create order: $e');
      return;
    }

    if (order.keyId != key) {
      if (!mounted) return;
      _pendingPlanKey = null;
      _showPaymentFailedDialog(
        'Razorpay key mismatch: app .env RAZORPAY_KEY_ID must match server RAZORPAY_KEY_ID.',
      );
      return;
    }

    final options = <String, dynamic>{
      'key': order.keyId,
      'order_id': order.orderId,
      'amount': order.amount,
      'currency': order.currency,
      'name': 'TalkFree Pro',
      'description': '${plan.ui.name} — ${plan.ui.periodLabel}',
      'prefill': <String, String>{
        if (user.email != null && user.email!.isNotEmpty) 'email': user.email!,
        if (user.phoneNumber != null && user.phoneNumber!.isNotEmpty)
          'contact': user.phoneNumber!,
      },
      'theme': <String, String>{'color': '#00FF9C'},
    };

    setState(() => _checkoutOpen = true);
    try {
      _razorpay.open(options);
    } catch (e) {
      _pendingPlanKey = null;
      setState(() => _checkoutOpen = false);
      if (mounted) {
        _showPaymentFailedDialog('Could not open checkout: $e');
      }
    }
  }

  void _showPaymentFailedDialog(String message) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: (Theme.of(context).cardTheme.color ?? Theme.of(context).colorScheme.surface),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Icon(Icons.payments_rounded, color: AppTheme.neonGreen.withValues(alpha: 0.95)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Payment Failed',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            message,
            style: GoogleFonts.inter(
              fontSize: 14,
              height: 1.45,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
                style: FilledButton.styleFrom(
                backgroundColor: AppTheme.neonGreen,
                foregroundColor: AppColors.darkBackground,
              ),
              child: Text(
                'OK',
                style: GoogleFonts.inter(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final yearly = _planCheckouts.firstWhere((p) => p.planKey == 'yearly');
    final others =
        _planCheckouts.where((p) => p.planKey != 'yearly').toList(growable: false);

    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      appBar: AppBar(
        title: Text(
          'Go Pro',
          style: GoogleFonts.inter(fontWeight: FontWeight.w800),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _ProBullet('Unlimited calling'),
          _ProBullet('No ads'),
          _ProBullet('Private number'),
          const SizedBox(height: 22),
          Text(
            '🔥 Best Value',
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _yearlyHeroPriceLine(yearly),
            style: GoogleFonts.poppins(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 14),
          _PlanGlassCard(
            plan: yearly.ui,
            highlight: true,
            ctaLabel: 'BUY YEARLY',
            onTap: _checkoutOpen ? null : () => _startCheckout(yearly),
          ),
          const SizedBox(height: 28),
          Text(
            'Other plans',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
              color: Theme.of(context)
                  .colorScheme
                  .onSurfaceVariant
                  .withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(height: 10),
          ...others.map(
            (p) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Opacity(
                opacity: 0.52,
                child: _PlanGlassCard(
                  plan: p.ui,
                  highlight: false,
                  onTap: _checkoutOpen ? null : () => _startCheckout(p),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            RazorpayConfig.hasKeyId
                ? 'Secure checkout · ${RazorpayConfig.currency}'
                : 'Add RAZORPAY_KEY_ID to enable checkout (${RazorpayConfig.currency}).',
            style: GoogleFonts.inter(
              fontSize: 11,
              height: 1.35,
              color: Theme.of(context)
                  .colorScheme
                  .onSurfaceVariant
                  .withValues(alpha: 0.65),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProBullet extends StatelessWidget {
  const _ProBullet(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.check_circle_rounded,
            size: 18,
            color: AppColors.primary.withValues(alpha: 0.85),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                height: 1.3,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.95),
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

/// Maps UI plan → Firestore `premium_plan_type` + Razorpay amount (INR paise or USD cents).
class _PlanCheckout {
  const _PlanCheckout({
    required this.planKey,
    required this.ui,
    required this.amountInrPaise,
    required this.amountUsdCents,
  });

  final String planKey;
  final _PlanData ui;
  final int amountInrPaise;
  final int amountUsdCents;

  int amountSmallestUnit(String currency) {
    switch (currency.toUpperCase()) {
      case 'USD':
        return amountUsdCents;
      case 'INR':
      default:
        return amountInrPaise;
    }
  }
}

/// Display prices in USD; charged in INR (paise) or USD (cents) per [RazorpayConfig.currency].
const _planCheckouts = <_PlanCheckout>[
  _PlanCheckout(
    planKey: 'daily',
    ui: _PlanData(
      name: 'Daily',
      price: r'$0.99',
      periodLabel: 'per day',
      benefits: ['No Ads', 'Bonus Credits', 'Private Number'],
    ),
    amountInrPaise: 8300,
    amountUsdCents: 99,
  ),
  _PlanCheckout(
    planKey: 'weekly',
    ui: _PlanData(
      name: 'Weekly',
      price: r'$4.99',
      periodLabel: 'per week',
      benefits: ['No Ads', 'Bonus Credits', 'Private Number'],
    ),
    amountInrPaise: 41500,
    amountUsdCents: 499,
  ),
  _PlanCheckout(
    planKey: 'monthly',
    ui: _PlanData(
      name: 'Monthly',
      price: r'$14.99',
      periodLabel: 'per month',
      benefits: ['No Ads', 'Bonus Credits', 'Private Number'],
    ),
    amountInrPaise: 124900,
    amountUsdCents: 1499,
  ),
  _PlanCheckout(
    planKey: 'yearly',
    ui: _PlanData(
      name: 'Yearly',
      price: r'$99.99',
      periodLabel: 'per year',
      benefits: ['No Ads', 'Bonus Credits', 'Private Number', 'Best value'],
    ),
    amountInrPaise: 829900,
    amountUsdCents: 9999,
  ),
];

String _yearlyHeroPriceLine(_PlanCheckout plan) {
  switch (RazorpayConfig.currency.toUpperCase()) {
    case 'INR':
      final r = (plan.amountInrPaise / 100).round();
      return '₹$r/year';
    case 'USD':
    default:
      return '${plan.ui.price}/year';
  }
}

/// Same glass + green accent pattern as [VirtualNumberScreen] subscription rows.
class _PlanGlassCard extends StatelessWidget {
  const _PlanGlassCard({
    required this.plan,
    required this.onTap,
    this.highlight = false,
    this.ctaLabel,
  });

  final _PlanData plan;
  final VoidCallback? onTap;
  final bool highlight;
  /// Primary plan CTA (e.g. yearly); defaults to "Buy Now" / "Choose".
  final String? ctaLabel;

  @override
  Widget build(BuildContext context) {
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                plan.name,
                style: GoogleFonts.inter(
                  fontWeight: highlight ? FontWeight.w800 : FontWeight.w600,
                  fontSize: highlight ? 16 : 15,
                  color: Theme.of(context).colorScheme.onSurface.withValues(
                        alpha: highlight ? 1 : 0.88,
                      ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                plan.periodLabel,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              if (plan.benefits.length > 3) ...[
                const SizedBox(height: 6),
                Text(
                  plan.benefits.last,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: highlight
                        ? AppColors.primary.withValues(alpha: 0.9)
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              plan.price,
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700,
                fontSize: highlight ? 16 : 15,
                color: highlight
                    ? AppColors.primary
                    : Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            highlight
                ? Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: NeonTokens.glowPrimary(0.5),
                    ),
                    child: FilledButton(
                      onPressed: onTap,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Theme.of(context).colorScheme.onPrimary,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        ctaLabel ?? 'Buy Now',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  )
                : OutlinedButton(
                    onPressed: onTap,
                    style: OutlinedButton.styleFrom(
                      foregroundColor:
                          Theme.of(context).colorScheme.onSurfaceVariant,
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.12),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text(
                      'Choose',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
          ],
        ),
      ],
    );

    final panel = GlassPanel(
      borderRadius: 16,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      accentNeon: false,
      child: row,
    );

    if (highlight) {
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.primary.withValues(alpha: 0.35),
              AppColors.primary.withValues(alpha: 0.08),
              AppColors.primary.withValues(alpha: 0.2),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.18),
              blurRadius: 20,
              spreadRadius: -2,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        padding: const EdgeInsets.all(1),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(19),
          child: panel,
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.cardDark,
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: row,
      ),
    );
  }
}
