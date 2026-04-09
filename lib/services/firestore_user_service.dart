import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../config/credits_policy.dart';

class InsufficientCreditsException implements Exception {
  InsufficientCreditsException([this.message = 'Insufficient credits']);
  final String message;
  @override
  String toString() => message;
}

class AdRewardCooldownException implements Exception {
  AdRewardCooldownException([this.message = 'Wait before watching another ad.']);
  final String message;
  @override
  String toString() => message;
}

class AdRewardDailyCapException implements Exception {
  AdRewardDailyCapException([this.message = 'Daily ad limit reached.']);
  final String message;
  @override
  String toString() => message;
}

class FirestoreUserService {
  FirestoreUserService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static DocumentReference<Map<String, dynamic>> _userRef(String uid) =>
      _db.collection('users').doc(uid);

  static int _int(dynamic v, [int d = 0]) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return d;
  }

  static Timestamp? _ts(Map<String, dynamic> d, String k) => d[k] as Timestamp?;

  static void _migrateLegacyInPlace(Map<String, dynamic> d) {
    if (d.containsKey('paidCredits')) return;
    d['paidCredits'] = _int(d['credits']);
    d['rewardCredits'] = 0;
  }

  static bool _rewardExpired(Map<String, dynamic> d) {
    final exp = _ts(d, 'rewardCreditsExpiresAt');
    if (exp == null) return false;
    return DateTime.now().toUtc().isAfter(exp.toDate().toUtc());
  }

  static int computeUsableCredits(Map<String, dynamic>? data) {
    if (data == null) return 0;
    final d = Map<String, dynamic>.from(data);
    _migrateLegacyInPlace(d);
    final paid = _int(d['paidCredits']);
    var reward = _int(d['rewardCredits']);
    if (reward > 0 && _rewardExpired(d)) reward = 0;
    return paid + reward;
  }

  static Future<void> expireRewardCreditsIfNeeded(String uid) async {
    await _db.runTransaction((tx) async {
      final ref = _userRef(uid);
      final snap = await tx.get(ref);
      if (!snap.exists) return;
      final d = snap.data()!;
      final m = Map<String, dynamic>.from(d);
      _migrateLegacyInPlace(m);
      final paid = _int(m['paidCredits']);
      final reward = _int(m['rewardCredits']);
      if (reward <= 0) return;
      if (!_rewardExpired(m)) return;
      tx.update(ref, {
        'paidCredits': paid,
        'rewardCredits': 0,
        'rewardCreditsExpiresAt': null,
        'credits': paid,
      });
    });
  }

  static Future<void> ensureUserDocument(String uid) async {
    final ref = _userRef(uid);
    final snap = await ref.get();
    if (!snap.exists) {
      await ref.set({
        'credits': 0,
        'paidCredits': 0,
        'rewardCredits': 0,
        'number': 'none',
        'adRewardsCount': 0,
        'adRewardsDayKey': '',
        'createdAt': FieldValue.serverTimestamp(),
      });
      return;
    }
    final d = snap.data()!;
    if (!d.containsKey('paidCredits')) {
      final legacy = _int(d['credits']);
      await ref.update({
        'paidCredits': legacy,
        'rewardCredits': 0,
        'adRewardsCount': d['adRewardsCount'] ?? 0,
        'adRewardsDayKey': d['adRewardsDayKey'] ?? '',
      });
    }
  }

  /// +[CreditsPolicy.creditsPerRewardedAd] to [rewardCredits], cooldown, daily cap, 24h expiry.
  static Future<void> applyRewardedAdGrant(String uid) async {
    await _db.runTransaction((tx) async {
      final ref = _userRef(uid);
      final snap = await tx.get(ref);
      if (!snap.exists) throw StateError('User document missing');
      final m = Map<String, dynamic>.from(snap.data()!);
      _migrateLegacyInPlace(m);

      var paid = _int(m['paidCredits']);
      var reward = _int(m['rewardCredits']);
      var exp = _ts(m, 'rewardCreditsExpiresAt');

      if (reward > 0 && _rewardExpired(m)) {
        reward = 0;
        exp = null;
      }

      final now = DateTime.now().toUtc();
      final dayKey =
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      var count = _int(m['adRewardsCount']);
      var storedDay = m['adRewardsDayKey'] as String? ?? '';
      if (storedDay != dayKey) {
        count = 0;
        storedDay = dayKey;
      }

      final lastTs = _ts(m, 'lastAdRewardAt');
      if (lastTs != null) {
        final elapsed = now.difference(lastTs.toDate().toUtc()).inSeconds;
        if (elapsed < CreditsPolicy.adRewardCooldownSeconds) {
          throw AdRewardCooldownException();
        }
      }

      if (count >= CreditsPolicy.maxRewardedAdsPerDay) {
        throw AdRewardDailyCapException();
      }

      reward += CreditsPolicy.creditsPerRewardedAd;
      exp = Timestamp.fromDate(now.add(CreditsPolicy.freeRewardCreditTtl));

      tx.update(ref, {
        'paidCredits': paid,
        'rewardCredits': reward,
        'rewardCreditsExpiresAt': exp,
        'credits': paid + reward,
        'adRewardsCount': count + 1,
        'adRewardsDayKey': storedDay,
        'lastAdRewardAt': FieldValue.serverTimestamp(),
      });
    });
  }

  static Future<void> addPaidCredits(String uid, int amount) async {
    await _db.runTransaction((tx) async {
      final ref = _userRef(uid);
      final snap = await tx.get(ref);
      if (!snap.exists) throw StateError('User document missing');
      final m = Map<String, dynamic>.from(snap.data()!);
      _migrateLegacyInPlace(m);
      var paid = _int(m['paidCredits']);
      var reward = _int(m['rewardCredits']);
      Timestamp? exp = _ts(m, 'rewardCreditsExpiresAt');
      if (reward > 0 && _rewardExpired(m)) {
        paid += reward;
        reward = 0;
        exp = null;
      }
      paid += amount;
      tx.update(ref, {
        'paidCredits': paid,
        'rewardCredits': reward,
        'rewardCreditsExpiresAt': reward > 0 ? exp : null,
        'credits': paid + reward,
      });
    });
  }

  static Future<void> addCredits(String uid, int amount) async {
    await addPaidCredits(uid, amount);
  }

  static Future<void> deductCredits(String uid, int amount) async {
    await _db.runTransaction((tx) async {
      final ref = _userRef(uid);
      final snap = await tx.get(ref);
      if (!snap.exists) throw StateError('User document missing');
      final m = Map<String, dynamic>.from(snap.data()!);
      _migrateLegacyInPlace(m);
      var paid = _int(m['paidCredits']);
      var reward = _int(m['rewardCredits']);
      Timestamp? exp = _ts(m, 'rewardCreditsExpiresAt');

      if (reward > 0 && _rewardExpired(m)) {
        reward = 0;
        exp = null;
      }

      final usable = paid + reward;
      if (usable < amount) {
        throw InsufficientCreditsException();
      }

      var left = amount;
      final takeReward = left < reward ? left : reward;
      reward -= takeReward;
      left -= takeReward;
      paid -= left;

      tx.update(ref, {
        'paidCredits': paid,
        'rewardCredits': reward,
        'rewardCreditsExpiresAt': reward > 0 ? exp : null,
        'credits': paid + reward,
      });
    });
  }

  static Future<void> deductCallUsageTick(String uid, int amount) async {
    await deductCredits(uid, amount);
  }

  /// Latest usable total after expiring stale reward credits (server write when needed).
  static Future<int> fetchUsableCredits(String uid) async {
    await expireRewardCreditsIfNeeded(uid);
    final snap = await _userRef(uid).get();
    return computeUsableCredits(snap.data());
  }

  static Stream<int> watchCredits(String uid) {
    return _userRef(uid).snapshots().asyncMap((doc) async {
      if (!doc.exists) return 0;
      await expireRewardCreditsIfNeeded(uid);
      final fresh = await _userRef(uid).get();
      return computeUsableCredits(fresh.data());
    });
  }

  static ({int adsToday, int cooldownRemaining}) _adRewardStatusFromSnap(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    if (!doc.exists) return (adsToday: 0, cooldownRemaining: 0);
    final m = doc.data()!;
    final now = DateTime.now().toUtc();
    final dayKey =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final storedDay = m['adRewardsDayKey'] as String? ?? '';
    final count = storedDay == dayKey ? _int(m['adRewardsCount']) : 0;

    var cool = 0;
    final last = _ts(m, 'lastAdRewardAt');
    if (last != null) {
      final elapsed = now.difference(last.toDate().toUtc()).inSeconds;
      if (elapsed < CreditsPolicy.adRewardCooldownSeconds) {
        cool = CreditsPolicy.adRewardCooldownSeconds - elapsed;
      }
    }
    return (adsToday: count, cooldownRemaining: cool);
  }

  static Stream<({int adsToday, int cooldownRemaining})> watchAdRewardStatus(
    String uid,
  ) {
    return Stream.multi((listener) {
      listener.add((adsToday: 0, cooldownRemaining: 0));
      DocumentSnapshot<Map<String, dynamic>>? latest;
      Timer? timer;
      late final StreamSubscription<DocumentSnapshot<Map<String, dynamic>>> sub;
      sub = _userRef(uid).snapshots().listen(
        (snap) {
          latest = snap;
          listener.add(_adRewardStatusFromSnap(snap));
        },
        onError: listener.addError,
        onDone: () {
          timer?.cancel();
          listener.close();
        },
      );
      timer = Timer.periodic(const Duration(seconds: 1), (_) {
        final s = latest;
        if (s != null) {
          listener.add(_adRewardStatusFromSnap(s));
        }
      });
      listener.onCancel = () {
        sub.cancel();
        timer?.cancel();
      };
    });
  }

  static Stream<String?> watchAllocatedNumber(String uid) {
    return _userRef(uid).snapshots().map((doc) {
      final data = doc.data();
      if (data == null) return null;
      final allocated = data['allocatedNumber'];
      if (allocated is String && allocated.isNotEmpty && allocated != 'none') {
        return allocated;
      }
      final legacy = data['number'];
      if (legacy is String && legacy.isNotEmpty && legacy != 'none') {
        return legacy;
      }
      return null;
    });
  }

  static Future<void> setAllocatedNumber(String uid, String e164) async {
    await _userRef(uid).update({
      'allocatedNumber': e164,
      'number': e164,
    });
  }
}
