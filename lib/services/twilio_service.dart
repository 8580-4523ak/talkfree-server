import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/twilio_env.dart';
import '../models/virtual_number.dart';

/// Twilio Account SID: `AC` + 32 hex chars (34 total).
final RegExp _twilioAccountSid = RegExp(r'^AC[a-fA-F0-9]{32}$');

/// Twilio REST error wrapper.
class TwilioApiException implements Exception {
  TwilioApiException(
    this.message, {
    this.statusCode,
    this.twilioCode,
  });
  final String message;
  final int? statusCode;

  /// Twilio JSON `code` when present (e.g. 21404 trial number limit).
  final int? twilioCode;

  @override
  String toString() =>
      'TwilioApiException($statusCode, code $twilioCode): $message';
}

/// One page of results from Twilio [AvailablePhoneNumbers] (Local resource).
class TwilioAvailableNumbersPage {
  const TwilioAvailableNumbersPage({
    required this.numbers,
    this.nextPageUri,
  });

  final List<VirtualNumber> numbers;

  /// When non-null, pass to [TwilioService.fetchAvailableUsLocalNumbersPage]
  /// as [nextPageUri] to load the next chunk.
  final String? nextPageUri;
}

/// Fetches available US local numbers and provisions incoming numbers.
///
/// **Trial accounts:** In Twilio Console, verify your personal number under
/// *Phone Numbers → Verified Caller IDs*; keep trial balance positive; US local
/// search may return empty sets until geographic permissions are enabled.
///
/// **Security:** Account SID + Auth Token in the app can be extracted from the
/// APK. Use a backend (e.g. Cloud Functions) for production.
class TwilioService {
  TwilioService._();

  static String get _sid {
    final v = TwilioEnv.accountSid?.trim();
    if (v == null || v.isEmpty) {
      throw StateError('TWILIO_ACCOUNT_SID missing in .env');
    }
    if (!_twilioAccountSid.hasMatch(v)) {
      throw StateError(
        'TWILIO_ACCOUNT_SID must be 34 chars: AC + 32 hex digits. '
        'Copy from Twilio Console → Account.',
      );
    }
    return v;
  }

  static String get _token {
    final v = TwilioEnv.authToken?.trim();
    if (v == null || v.isEmpty) {
      throw StateError('TWILIO_AUTH_TOKEN missing in .env');
    }
    return v;
  }

  static String get _basicAuthHeader {
    final raw = utf8.encode('$_sid:$_token');
    return 'Basic ${base64Encode(raw)}';
  }

  static Map<String, String> get _jsonHeaders => {
        'Authorization': _basicAuthHeader,
        'Accept': 'application/json',
      };

  static Map<String, String> get _formHeaders => {
        'Authorization': _basicAuthHeader,
        'Content-Type': 'application/x-www-form-urlencoded',
      };

  static Uri get _incomingUri => Uri.parse(
        'https://api.twilio.com/2010-04-01/Accounts/$_sid/IncomingPhoneNumbers.json',
      );

  /// Lists US local numbers Twilio currently has for sale, with optional filters.
  ///
  /// * [areaCode] — 3-digit US area code (e.g. `415`).
  /// * [contains] — digits the number should contain in order (Twilio `Contains`, 3–7 digits typical).
  /// * [inRegion] — US state code (e.g. `CA`, `OH`).
  /// * [nextPageUri] — from previous page’s [TwilioAvailableNumbersPage.nextPageUri]; ignores filters.
  static Future<TwilioAvailableNumbersPage> fetchAvailableUsLocalNumbersPage({
    int pageSize = 100,
    String? areaCode,
    String? contains,
    String? inRegion,
    String? nextPageUri,
  }) =>
      _fetchAvailableLocalNumbersPage(
        countryPathSegment: 'US',
        countryLabel: 'US',
        pageSize: pageSize,
        areaCode: areaCode,
        contains: contains,
        inRegion: inRegion,
        nextPageUri: nextPageUri,
      );

  /// Canadian local inventory (NANP +1). [inRegion] is a Canadian region/province code when used.
  static Future<TwilioAvailableNumbersPage> fetchAvailableCaLocalNumbersPage({
    int pageSize = 100,
    String? areaCode,
    String? contains,
    String? inRegion,
    String? nextPageUri,
  }) =>
      _fetchAvailableLocalNumbersPage(
        countryPathSegment: 'CA',
        countryLabel: 'CA',
        pageSize: pageSize,
        areaCode: areaCode,
        contains: contains,
        inRegion: inRegion,
        nextPageUri: nextPageUri,
      );

  /// Alias: first page of US local numbers (same as [fetchAvailableUsLocalNumbersPage] without pagination).
  static Future<TwilioAvailableNumbersPage> fetchAvailableNumbers({
    int pageSize = 100,
    String? areaCode,
    String? contains,
    String? inRegion,
  }) =>
      fetchAvailableUsLocalNumbersPage(
        pageSize: pageSize,
        areaCode: areaCode,
        contains: contains,
        inRegion: inRegion,
      );

  static Future<TwilioAvailableNumbersPage> _fetchAvailableLocalNumbersPage({
    required String countryPathSegment,
    required String countryLabel,
    int pageSize = 100,
    String? areaCode,
    String? contains,
    String? inRegion,
    String? nextPageUri,
  }) async {
    final Uri uri;
    final trimmedNext = nextPageUri?.trim();
    if (trimmedNext != null && trimmedNext.isNotEmpty) {
      uri = Uri.parse(
        trimmedNext.startsWith('http')
            ? trimmedNext
            : 'https://api.twilio.com$trimmedNext',
      );
    } else {
      final size = pageSize.clamp(1, 1000);
      final query = <String, String>{'PageSize': '$size'};
      final ac = areaCode?.trim().replaceAll(RegExp(r'\D'), '') ?? '';
      if (ac.length >= 3) {
        query['AreaCode'] = ac.substring(0, 3);
      }
      final rawContains = contains?.trim().replaceAll(RegExp(r'\D'), '') ?? '';
      if (rawContains.isNotEmpty) {
        query['Contains'] = rawContains.length > 7
            ? rawContains.substring(0, 7)
            : rawContains;
      }
      final reg = inRegion?.trim() ?? '';
      if (reg.isNotEmpty) {
        query['InRegion'] = reg.length <= 2 ? reg.toUpperCase() : reg;
      }
      uri = Uri.https(
        'api.twilio.com',
        '/2010-04-01/Accounts/$_sid/AvailablePhoneNumbers/$countryPathSegment/Local.json',
        query,
      );
    }

    final response = await http.get(uri, headers: _jsonHeaders);
    if (response.statusCode != 200) {
      _throwTwilioHttpError(response.statusCode, response.body);
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final list = decoded['available_phone_numbers'] as List<dynamic>? ?? [];
    final numbers = list
        .map(
          (e) => _virtualNumberFromAvailable(
            e as Map<String, dynamic>,
            countryLabel: countryLabel,
          ),
        )
        .toList();
    final nextRaw = decoded['next_page_uri'] as String?;
    final nextAbs = (nextRaw == null || nextRaw.isEmpty)
        ? null
        : (nextRaw.startsWith('http') ? nextRaw : 'https://api.twilio.com$nextRaw');
    return TwilioAvailableNumbersPage(numbers: numbers, nextPageUri: nextAbs);
  }

  static VirtualNumber _virtualNumberFromAvailable(
    Map<String, dynamic> json, {
    required String countryLabel,
  }) {
    final e164 = json['phone_number'] as String? ?? '';
    final locality = json['locality'] as String?;
    final region = json['region'] as String?;
    final sub = [locality, region].whereType<String>().where((s) => s.isNotEmpty).join(', ');
    final place = countryLabel == 'CA'
        ? (sub.isEmpty ? 'Canada' : '$sub · Canada')
        : (sub.isEmpty ? 'United States' : '$sub · US');
    return VirtualNumber(
      e164: e164,
      phoneNumber: formatUsDisplay(e164),
      country: place,
    );
  }

  /// Pretty-print US E.164 for UI.
  static String formatUsDisplay(String e164) {
    final digits = e164.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 11 && digits.startsWith('1')) {
      final a = digits.substring(1, 4);
      final b = digits.substring(4, 7);
      final c = digits.substring(7);
      return '+1 ($a) $b-$c';
    }
    if (digits.length == 10) {
      final a = digits.substring(0, 3);
      final b = digits.substring(3, 6);
      final c = digits.substring(6);
      return '+1 ($a) $b-$c';
    }
    return e164;
  }

  /// Buys/provisions [e164] on this account (IncomingPhoneNumbers).
  static Future<void> purchaseIncomingNumber(String e164) async {
    final response = await http.post(
      _incomingUri,
      headers: _formHeaders,
      body: 'PhoneNumber=${Uri.encodeQueryComponent(e164)}',
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      _throwTwilioHttpError(response.statusCode, response.body);
    }
  }

  /// Alias for [purchaseIncomingNumber] (Twilio IncomingPhoneNumbers API).
  static Future<void> provisionNumber(String e164) =>
      purchaseIncomingNumber(e164);

  static Never _throwTwilioHttpError(int statusCode, String body) {
    final p = _parseTwilioErrorJson(body);
    final text = p.message != null
        ? (p.code != null ? '${p.message} (code ${p.code})' : p.message!)
        : body;
    throw TwilioApiException(
      text,
      statusCode: statusCode,
      twilioCode: p.code,
    );
  }

  static ({String? message, int? code}) _parseTwilioErrorJson(String body) {
    try {
      final m = jsonDecode(body) as Map<String, dynamic>?;
      return (
        message: m?['message'] as String?,
        code: (m?['code'] as num?)?.toInt(),
      );
    } catch (_) {
      return (message: null, code: null);
    }
  }
}
