/// A purchasable phone line (Twilio inventory or UI placeholder).
class VirtualNumber {
  const VirtualNumber({
    required this.e164,
    required this.phoneNumber,
    required this.country,
    this.price = defaultPrice,
  });

  static const int defaultPrice = 500;

  /// Twilio E.164 (e.g. `+12025550123`) — used for purchase API.
  final String e164;

  /// Human-friendly string shown in the list.
  final String phoneNumber;

  final String country;
  final int price;
}
