import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../theme/app_theme.dart';

import '../models/virtual_number.dart';
import '../services/browse_inventory_client.dart';
import '../services/browse_number_purchase_service.dart';
import '../services/firestore_user_service.dart';
import '../utils/user_facing_service_error.dart';
import 'virtual_number_claim_flow.dart';

/// Arguments for [Navigator.pushNamed] → [NumberSelectionScreen.routeName].
class NumberSelectionRouteArgs {
  const NumberSelectionRouteArgs({
    required this.userUid,
    required this.userCredits,
  });

  final String userUid;
  final int userCredits;
}

class NumberSelectionScreen extends StatefulWidget {
  const NumberSelectionScreen({
    super.key,
    required this.userUid,
    required this.userCredits,
  });

  /// Registered in [MaterialApp.onGenerateRoute] in `main.dart`.
  static const String routeName = '/number-selection';

  /// Builds the [MaterialPageRoute] for [routeName] (uses [settings.arguments]).
  static Route<void> createRoute(RouteSettings settings) {
    final args = settings.arguments;
    final uid = args is NumberSelectionRouteArgs ? args.userUid : '';
    final credits = args is NumberSelectionRouteArgs ? args.userCredits : 0;
    return MaterialPageRoute<void>(
      settings: settings,
      builder: (_) => NumberSelectionScreen(
        userUid: uid,
        userCredits: credits,
      ),
    );
  }

  final String userUid;
  final int userCredits;

  @override
  State<NumberSelectionScreen> createState() => _NumberSelectionScreenState();
}

class _NumberSelectionScreenState extends State<NumberSelectionScreen> {
  final _areaCodeCtrl = TextEditingController();
  final _containsCtrl = TextEditingController();
  final _stateCtrl = TextEditingController();

  List<VirtualNumber> _numbers = [];
  String? _nextPageUri;
  bool _loading = true;
  bool _loadingMore = false;
  bool _activateBusy = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _fetch(reset: true);
  }

  @override
  void dispose() {
    _areaCodeCtrl.dispose();
    _containsCtrl.dispose();
    _stateCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetch({required bool reset, bool loadMore = false}) async {
    if (loadMore) {
      if (_nextPageUri == null || _nextPageUri!.isEmpty || _loadingMore) {
        return;
      }
      setState(() => _loadingMore = true);
    } else {
      setState(() {
        _loading = true;
        _error = null;
        if (reset) {
          _numbers = [];
          _nextPageUri = null;
        }
      });
    }

    try {
      if (loadMore) {
        final page = await BrowseInventoryClient.instance.fetchLocalPage(
          country: 'US',
          pageSize: 100,
          nextPage: _nextPageUri,
        );
        if (!mounted) return;
        setState(() {
          _numbers = [..._numbers, ...page.numbers];
          _loadingMore = false;
          _nextPageUri = page.nextPage;
        });
      } else {
        final usPage = await BrowseInventoryClient.instance.fetchLocalPage(
          country: 'US',
          pageSize: 100,
          areaCode: _areaCodeCtrl.text,
          contains: _containsCtrl.text,
          inRegion: _stateCtrl.text,
        );
        var combined = List<VirtualNumber>.from(usPage.numbers);
        if (_stateCtrl.text.trim().isEmpty) {
          try {
            final caPage = await BrowseInventoryClient.instance.fetchLocalPage(
              country: 'CA',
              pageSize: 100,
              areaCode: _areaCodeCtrl.text,
              contains: _containsCtrl.text,
            );
            combined = [...combined, ...caPage.numbers];
          } catch (e, st) {
            debugPrint('CA inventory optional fetch failed: $e\n$st');
          }
        }
        if (!mounted) return;
        setState(() {
          _numbers = combined;
          _loading = false;
          _nextPageUri = usPage.nextPage;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (loadMore) {
          _loadingMore = false;
        } else {
          _error = e;
          _loading = false;
        }
      });
    }
  }

  void _onSearch() => _fetch(reset: true);

  void _onClearFilters() {
    _areaCodeCtrl.clear();
    _containsCtrl.clear();
    _stateCtrl.clear();
    _fetch(reset: true);
  }

  Future<void> _onLoadMore() => _fetch(reset: false, loadMore: true);

  Future<void> _activate(
    VirtualNumber vn,
    int liveCredits,
    bool isPremium,
  ) async {
    if (_activateBusy) return;
    setState(() => _activateBusy = true);
    try {
      final confirmed = await VirtualNumberClaimFlow.showClaimNumberConfirmation(
        context,
        vn.phoneNumber,
      );
      if (!confirmed || !mounted) return;

      if (isPremium) {
        await VirtualNumberClaimFlow.executePremiumProvisionFromBrowse(
          context,
          vn.e164,
        );
        return;
      }

      if (liveCredits < vn.price) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Not enough credits (500 required).'),
          ),
        );
        return;
      }

      if (!mounted) return;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const AlertDialog(
          content: Row(
            children: [
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              SizedBox(width: 20),
              Expanded(child: Text('Processing…')),
            ],
          ),
        ),
      );

      try {
        await BrowseNumberPurchaseService.instance.purchaseNumber(
          phoneE164: vn.e164,
          price: vn.price,
        );

        if (!mounted) return;
        Navigator.of(context, rootNavigator: true).pop();

        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            icon: Icon(
              Icons.check_circle_rounded,
              color: Colors.green.shade600,
              size: 48,
            ),
            title: const Text('Success'),
            content: Text(
              'Your new number is ${vn.phoneNumber}.\n'
              'It has been saved to your profile.',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.neonGreen,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                ),
                child: const Text('Great'),
              ),
            ],
          ),
        );

        if (!mounted) return;
        Navigator.of(context).pop();
      } on BrowseNumberPurchaseException catch (e) {
        if (mounted) Navigator.of(context, rootNavigator: true).pop();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.statusCode == 402
                  ? 'Insufficient credits. Earn more and try again.'
                  : e.message,
            ),
          ),
        );
      } catch (e) {
        if (mounted) Navigator.of(context, rootNavigator: true).pop();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_activateErrorMessage(e)),
            duration: const Duration(seconds: 10),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _activateBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      appBar: AppBar(
        title: const Text('Choose your number'),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirestoreUserService.watchUserDocument(widget.userUid),
        builder: (context, creditSnap) {
          final credits = creditSnap.hasData
              ? FirestoreUserService.usableCreditsFromSnapshot(creditSnap.data!)
              : widget.userCredits;
          final userData =
              creditSnap.hasData ? creditSnap.data!.data() : null;
          final isPremium =
              FirestoreUserService.isPremiumFromUserData(userData);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Card(
                  elevation: 0,
                  color: (Theme.of(context).cardTheme.color ?? Theme.of(context).colorScheme.surface),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: AppTheme.neonGreen.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 48,
                          height: 48,
                          child: Lottie.asset(
                            AppTheme.lottieMoney,
                            fit: BoxFit.contain,
                            repeat: true,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Your balance',
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              ),
                              Text(
                                '$credits credits',
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.neonGreen,
                                ),
                              ),
                              Text(
                                'Activation costs ${VirtualNumber.defaultPrice} credits each',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurface
                                      .withValues(alpha: 0.75),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Card(
                  elevation: 0,
                  color: (Theme.of(context).cardTheme.color ?? Theme.of(context).colorScheme.surface),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: AppTheme.neonGreen.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Search available numbers',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Filter by area code or digits in the number. US state '
                          'filters US results only; without a state, Canadian local '
                          'numbers are included too. Use Load more for the next US page.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _areaCodeCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Area code',
                            hintText: 'e.g. 740',
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _containsCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Digits in number (Contains)',
                            hintText: 'e.g. 5626 (up to 7 digits)',
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _stateCtrl,
                          textCapitalization: TextCapitalization.characters,
                          decoration: const InputDecoration(
                            labelText: 'US state',
                            hintText: 'e.g. OH, GA, CA',
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton(
                                onPressed: _loading ? null : _onSearch,
                                child: const Text('Search'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _loading ? null : _onClearFilters,
                                child: const Text('Clear'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _buildNumbersBody(
                  theme,
                  colorScheme,
                  credits,
                  isPremium,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildNumbersBody(
    ThemeData theme,
    ColorScheme colorScheme,
    int credits,
    bool isPremium,
  ) {
    if (_loading && _numbers.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _numbers.isEmpty) {
      return _NumbersLoadError(
        error: _error!,
        onRetry: _onSearch,
      );
    }
    if (!_loading && _numbers.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.search_off_rounded,
                size: 48,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 12),
              Text(
                'No numbers match these filters. Try Clear or a different search.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: _onClearFilters,
                child: const Text('Clear filters'),
              ),
            ],
          ),
        ),
      );
    }

    final extra = (_loadingMore ? 1 : 0) +
        (!_loadingMore && _nextPageUri != null ? 1 : 0);

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      itemCount: _numbers.length + extra,
      itemBuilder: (context, index) {
        if (index < _numbers.length) {
          final vn = _numbers[index];
          return Padding(
            padding: EdgeInsets.only(
              bottom: index < _numbers.length - 1 ? 12 : 0,
            ),
            child: _NumberListCard(
              virtualNumber: vn,
              userCredits: credits,
              onActivate: () => _activate(vn, credits, isPremium),
              activateLocked: _activateBusy,
            ),
          );
        }
        final after = index - _numbers.length;
        if (_loadingMore && after == 0) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (_nextPageUri != null && !_loadingMore) {
          return Padding(
            padding: const EdgeInsets.only(top: 8),
            child: FilledButton.tonal(
              onPressed: _onLoadMore,
              child: const Text('Load more numbers'),
            ),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}

class _NumbersLoadError extends StatelessWidget {
  const _NumbersLoadError({
    required this.error,
    required this.onRetry,
  });

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final raw = '$error';
    final msg = userFacingServiceError(raw);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 48,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Could not load numbers',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              msg,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.tonal(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _NumberListCard extends StatelessWidget {
  const _NumberListCard({
    required this.virtualNumber,
    required this.userCredits,
    required this.onActivate,
    this.activateLocked = false,
  });

  final VirtualNumber virtualNumber;
  final int userCredits;
  final VoidCallback onActivate;
  final bool activateLocked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final canActivate =
        !activateLocked && userCredits >= virtualNumber.price;

    return Card(
      elevation: 0,
      shadowColor: Colors.black.withValues(alpha: 0.4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppTheme.neonGreen.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Lottie.asset(
                AppTheme.lottiePhoneCall,
                fit: BoxFit.contain,
                repeat: true,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('🇺🇸', style: theme.textTheme.titleMedium),
                      const SizedBox(width: 6),
                      Text('🇨🇦', style: theme.textTheme.titleMedium),
                      const SizedBox(width: 8),
                      Text(
                        'US / Canada',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    virtualNumber.phoneNumber,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
                  ),
                  Text(
                    virtualNumber.country,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${virtualNumber.price} cr',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: AppTheme.neonGreen,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: canActivate ? onActivate : null,
                  icon: Icon(
                    canActivate
                        ? Icons.check_rounded
                        : Icons.lock_outline_rounded,
                    size: 18,
                    color: canActivate ? Colors.white : null,
                  ),
                  label: const Text('Activate'),
                  style: FilledButton.styleFrom(
                    backgroundColor:
                        canActivate ? AppTheme.neonGreen : null,
                    foregroundColor:
                        canActivate ? Theme.of(context).colorScheme.onPrimary : null,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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

String _activateErrorMessage(Object e) {
  return userFacingServiceError('Something went wrong: $e');
}
