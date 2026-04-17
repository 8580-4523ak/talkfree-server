import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/voice_backend_config.dart';
import '../models/virtual_number.dart';
import '../utils/nanp_phone_display.dart';

/// One page from GET `/browse-available-numbers` (server proxies Twilio inventory).
class BrowseInventoryPage {
  const BrowseInventoryPage({
    required this.numbers,
    this.nextPage,
  });

  final List<VirtualNumber> numbers;

  /// Opaque path+query for the next page (pass as [nextPage] on the following request).
  final String? nextPage;
}

/// US/CA local number inventory via backend (no Twilio credentials in the app).
class BrowseInventoryClient {
  BrowseInventoryClient._();
  static final BrowseInventoryClient instance = BrowseInventoryClient._();

  static VirtualNumber _virtualNumberFromJson(Map<String, dynamic> m) {
    final e164 = (m['phoneNumber'] as String?)?.trim() ?? '';
    final locality = m['locality'] as String?;
    final region = m['region'] as String?;
    final country = (m['country'] as String?)?.trim().toUpperCase() ?? 'US';
    final sub = [locality, region]
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .join(', ');
    final place = country == 'CA'
        ? (sub.isEmpty ? 'Canada' : '$sub · Canada')
        : (sub.isEmpty ? 'United States' : '$sub · US');
    return VirtualNumber(
      e164: e164,
      phoneNumber: NanpPhoneDisplay.format(e164),
      country: place,
    );
  }

  Future<BrowseInventoryPage> fetchLocalPage({
    required String country,
    int pageSize = 100,
    String? areaCode,
    String? contains,
    String? inRegion,
    String? nextPage,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('Not signed in');
    }
    final token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      throw StateError('Could not get Firebase ID token');
    }

    final uri = VoiceBackendConfig.browseAvailableNumbersUri(
      country: country,
      pageSize: pageSize,
      areaCode: areaCode,
      contains: contains,
      inRegion: inRegion,
      nextPage: nextPage,
    );

    final response = await http
        .get(
          uri,
          headers: <String, String>{
            'Authorization': 'Bearer $token',
            'Accept': 'application/json',
          },
        )
        .timeout(const Duration(seconds: 45));

    if (response.statusCode != 200) {
      if (kDebugMode) {
        debugPrint(
          'browse-available-numbers failed: ${response.statusCode} ${response.body}',
        );
      }
      throw StateError(
        'Could not load numbers (HTTP ${response.statusCode})',
      );
    }

    final j = jsonDecode(response.body) as Map<String, dynamic>?;
    final raw = j?['numbers'];
    if (raw is! List) {
      return const BrowseInventoryPage(numbers: []);
    }
    final out = <VirtualNumber>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final m = Map<String, dynamic>.from(item);
      final pn = (m['phoneNumber'] as String?)?.trim() ?? '';
      if (pn.isEmpty) continue;
      out.add(_virtualNumberFromJson(m));
    }
    final next = j?['nextPage'] as String?;
    final trimmed = next?.trim();
    return BrowseInventoryPage(
      numbers: out,
      nextPage: (trimmed != null && trimmed.isNotEmpty) ? trimmed : null,
    );
  }
}
