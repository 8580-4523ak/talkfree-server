import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../config/credits_policy.dart';
import 'firestore_user_service.dart';
import 'voice_service.dart';

/// Real-time PSTN call billing: −[CreditsPolicy.creditsPerCallTick] every
/// [CreditsPolicy.callTickInterval] in Firestore (reward first, then paid).
class CallService {
  CallService._();
  static final CallService instance = CallService._();

  static const int _maxCatchUpTicks = 24;
  static const int _maxDeductRetries = 6;

  Timer? _timer;
  String? _uid;
  String? _twilioCallSid;
  DateTime? _lastSuccessfulBillAt;
  VoidCallback? _onInsufficientCredits;
  void Function(String message)? _onError;
  Future<void> Function()? _hangUpActiveCall;

  bool get isBillingActive => _timer != null;

  bool _isRetriable(Object e) {
    if (e is FirebaseException) {
      switch (e.code) {
        case 'unavailable':
        case 'deadline-exceeded':
        case 'resource-exhausted':
        case 'aborted':
          return true;
      }
    }
    if (e is SocketException) return true;
    if (e is TimeoutException) return true;
    return false;
  }

  Future<void> _deductWithRetry(String uid) async {
    for (var attempt = 0; attempt < _maxDeductRetries; attempt++) {
      try {
        await FirestoreUserService.deductCallUsageTick(
          uid,
          CreditsPolicy.creditsPerCallTick,
        );
        return;
      } catch (e) {
        if (!_isRetriable(e) || attempt == _maxDeductRetries - 1) {
          rethrow;
        }
        await Future<void>.delayed(Duration(milliseconds: 250 * (1 << attempt)));
      }
    }
  }

  Future<void> _shutdownForInsufficientCredits() async {
    final sid = _twilioCallSid;
    final cb = _onInsufficientCredits;
    final hangUp = _hangUpActiveCall;
    _clearTimerOnly();
    _uid = null;
    _twilioCallSid = null;
    _lastSuccessfulBillAt = null;
    _onInsufficientCredits = null;
    _onError = null;
    _hangUpActiveCall = null;
    if (hangUp != null) {
      try {
        await hangUp();
      } catch (_) {}
    }
    if (sid != null && sid.isNotEmpty) {
      try {
        await VoiceService.cancelCall(sid);
      } catch (_) {}
    }
    cb?.call();
  }

  void _clearTimerOnly() {
    _timer?.cancel();
    _timer = null;
  }

  /// Stops billing and clears state. Does **not** cancel Twilio (dialer does that).
  void stopBilling() {
    _clearTimerOnly();
    _uid = null;
    _twilioCallSid = null;
    _lastSuccessfulBillAt = null;
    _onInsufficientCredits = null;
    _onError = null;
    _hangUpActiveCall = null;
  }

  Future<void> _runOneCycle() async {
    final uid = _uid;
    if (uid == null) return;

    final balance = await FirestoreUserService.fetchUsableCredits(uid);
    if (balance < CreditsPolicy.creditsPerCallTick) {
      await _shutdownForInsufficientCredits();
      return;
    }

    try {
      await _deductWithRetry(uid);
      _lastSuccessfulBillAt = DateTime.now();
    } on InsufficientCreditsException {
      await _shutdownForInsufficientCredits();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('CallService billing cycle failed: $e\n$st');
      }
      _onError?.call('$e');
    }
  }

  void startBilling({
    required String uid,
    String? twilioCallSid,
    Future<void> Function()? hangUpActiveCall,
    required VoidCallback onInsufficientCredits,
    void Function(String message)? onError,
  }) {
    _timer?.cancel();
    _timer = null;

    _uid = uid;
    _twilioCallSid = twilioCallSid;
    _lastSuccessfulBillAt = DateTime.now();
    _hangUpActiveCall = hangUpActiveCall;
    _onInsufficientCredits = onInsufficientCredits;
    _onError = onError;

    _timer = Timer.periodic(CreditsPolicy.callTickInterval, (_) {
      unawaited(_runOneCycle());
    });
  }

  /// Catches up ticks after app pause / background (timer may not fire).
  Future<void> syncAfterAppResumed() async {
    if (_uid == null || _lastSuccessfulBillAt == null) {
      return;
    }

    var bursts = 0;
    while (bursts < _maxCatchUpTicks && _uid != null) {
      final last = _lastSuccessfulBillAt;
      if (last == null) break;
      final nextDue = last.add(CreditsPolicy.callTickInterval);
      if (!DateTime.now().isAfter(nextDue)) break;

      final uid = _uid!;
      final balance = await FirestoreUserService.fetchUsableCredits(uid);
      if (balance < CreditsPolicy.creditsPerCallTick) {
        await _shutdownForInsufficientCredits();
        break;
      }

      try {
        await _deductWithRetry(uid);
        _lastSuccessfulBillAt = nextDue;
        bursts++;
      } on InsufficientCreditsException {
        await _shutdownForInsufficientCredits();
        break;
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('CallService catch-up failed: $e\n$st');
        }
        _onError?.call('$e');
        break;
      }
    }
  }
}
