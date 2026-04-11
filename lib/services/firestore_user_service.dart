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
  AdRewardCooldownException([this.message = 'Please wait before the next ad.']);
  final String message;
  @override
  String toString() => message;
}

class AdRewardDailyCapException implements Exception {
  AdRewardDailyCapException([this.message = 'Daily Limit Reached']);
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

  /// Canonical reward fields (see `firestore_schema.md`). Falls back to legacy keys.
  static int _readAdProgress(Map<String, dynamic> m) {
    if (m.containsKey('ad_progress')) return _int(m['ad_progress']);
    return _int(m['adRewardCycleCount']);
  }

  static int _readAdsWatchedToday(Map<String, dynamic> m, String dayKey) {
    final reset =
        m['last_reset_date'] as String? ?? m['adRewardsDayKey'] as String? ?? '';
    if (reset != dayKey) return 0;
    if (m.containsKey('ads_watched_today')) return _int(m['ads_watched_today']);
    return _int(m['adRewardsCount']);
  }

  static Timestamp? _readLastAdTimestamp(Map<String, dynamic> m) {
    final a = m['last_ad_timestamp'];
    if (a is Timestamp) return a;
    return m['lastAdRewardAt'] as Timestamp?;
  }

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

  /// Real-time user document — use for credits UI synced everywhere.
  static Stream<DocumentSnapshot<Map<String, dynamic>>> watchUserDocument(
    String uid,
  ) =>
      _userRef(uid).snapshots();

  /// Usable credits from a snapshot (same rules as [computeUsableCredits], no extra round-trip).
  static int usableCreditsFromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) =>
      computeUsableCredits(doc.data());

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
        'ad_progress': 0,
        'ads_watched_today': 0,
        'last_reset_date': '',
        'last_ad_timestamp': null,
        'adRewardsCount': 0,
        'adRewardsDayKey': '',
        'adRewardCycleCount': 0,
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
        'ad_progress': d['ad_progress'] ?? d['adRewardCycleCount'] ?? 0,
        'ads_watched_today': d['ads_watched_today'] ?? d['adRewardsCount'] ?? 0,
        'last_reset_date':
            d['last_reset_date'] ?? d['adRewardsDayKey'] ?? '',
        'adRewardsCount': d['adRewardsCount'] ?? 0,
        'adRewardsDayKey': d['adRewardsDayKey'] ?? '',
        'adRewardCycleCount': d['adRewardCycleCount'] ?? 0,
      });
    }
  }

  /// Records one rewarded-ad view: daily cap, cooldown, sub-counter toward 4 ads.
  /// If [serverGrantNeeded] is true, call [GrantRewardService.requestMinuteGrant].
  static Future<
      ({
        bool serverGrantNeeded,
        int cycleProgress,
      })> registerRewardedAdWatch(String uid) async {
    var serverGrantNeeded = false;
    var cycleProgressOut = 0;
    await _db.runTransaction((tx) async {
      final ref = _userRef(uid);
      final snap = await tx.get(ref);
      if (!snap.exists) throw StateError('User document missing');
      final m = Map<String, dynamic>.from(snap.data()!);
      _migrateLegacyInPlace(m);

      final now = DateTime.now().toUtc();
      final dayKey =
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      var count = _readAdsWatchedToday(m, dayKey);
      var storedDay =
          m['last_reset_date'] as String? ?? m['adRewardsDayKey'] as String? ?? '';
      if (storedDay != dayKey) {
        count = 0;
        storedDay = dayKey;
      }

      final lastTs = _readLastAdTimestamp(m);
      if (lastTs != null) {
        final elapsed = now.difference(lastTs.toDate().toUtc()).inSeconds;
        if (elapsed < CreditsPolicy.adRewardCooldownSeconds) {
          final wait = CreditsPolicy.adRewardCooldownSeconds - elapsed;
          throw AdRewardCooldownException('Please wait $wait seconds');
        }
      }

      if (count >= CreditsPolicy.maxRewardedAdsPerDay) {
        throw AdRewardDailyCapException();
      }

      var cycle = _readAdProgress(m);
      cycle += 1;
      if (cycle >= CreditsPolicy.adsRequiredForMinuteGrant) {
        cycle = 0;
        serverGrantNeeded = true;
      }
      cycleProgressOut = cycle;

      tx.update(ref, {
        'ad_progress': cycle,
        'ads_watched_today': count + 1,
        'last_reset_date': storedDay,
        'last_ad_timestamp': FieldValue.serverTimestamp(),
        'adRewardCycleCount': cycle,
        'adRewardsCount': count + 1,
        'adRewardsDayKey': storedDay,
        'lastAdRewardAt': FieldValue.serverTimestamp(),
      });
    });
    return (
      serverGrantNeeded: serverGrantNeeded,
      cycleProgress: cycleProgressOut,
    );
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

  /// Live usable total — maps [watchUserDocument] (Firestore pushes; stays in sync across screens).
  static Stream<int> watchCredits(String uid) {
    return watchUserDocument(uid).map(usableCreditsFromSnapshot);
  }

  static ({
    int adsToday,
    int cooldownRemaining,
    int cycleProgress,
    bool dailyLimitReached,
  }) _adRewardStatusFromSnap(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    if (!doc.exists) {
      return (
        adsToday: 0,
        cooldownRemaining: 0,
        cycleProgress: 0,
        dailyLimitReached: false,
      );
    }
    final m = doc.data()!;
    final now = DateTime.now().toUtc();
    final dayKey =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final count = _readAdsWatchedToday(m, dayKey);
    final cycleProgress = _readAdProgress(m);

    var cool = 0;
    final last = _readLastAdTimestamp(m);
    if (last != null) {
      final elapsed = now.difference(last.toDate().toUtc()).inSeconds;
      if (elapsed < CreditsPolicy.adRewardCooldownSeconds) {
        cool = CreditsPolicy.adRewardCooldownSeconds - elapsed;
      }
    }
    final cap = CreditsPolicy.maxRewardedAdsPerDay;
    final dailyLimitReached = count >= cap;
    return (
      adsToday: count,
      cooldownRemaining: cool,
      cycleProgress: cycleProgress,
      dailyLimitReached: dailyLimitReached,
    );
  }

  static Stream<
      ({
        int adsToday,
        int cooldownRemaining,
        int cycleProgress,
        bool dailyLimitReached,
      })> watchAdRewardStatus(
    String uid,
  ) {
    return Stream.multi((listener) {
      listener.add((
        adsToday: 0,
        cooldownRemaining: 0,
        cycleProgress: 0,
        dailyLimitReached: false,
      ));
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

  /// Outbound call rows — written by server Twilio `/call-status` (`settledAt`, `to`, etc.).
  static Stream<QuerySnapshot<Map<String, dynamic>>> watchCallHistory(
    String uid, {
    int limit = 100,
  }) =>
      _userRef(uid)
          .collection('call_history')
          .orderBy('settledAt', descending: true)
          .limit(limit)
          .snapshots();
}
