/// Converts what a person types into the international (E.164) format used
/// by the database, e.g. "0100 123 4567" -> "+201001234567".
///
/// Numbers without a country code are treated as Egyptian. Returns `null`
/// when the input cannot be a valid phone number.
abstract final class PhoneNumber {
  static const String defaultCountryCode = '20'; // Egypt

  static String? normalize(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;

    // Arabic-Indic digits (٠١٢٣٤٥٦٧٨٩) -> Latin digits.
    final latin = trimmed.replaceAllMapped(
      RegExp('[٠-٩]'),
      (m) => String.fromCharCode(m[0]!.codeUnitAt(0) - 0x0660 + 0x30),
    );

    var digits = latin.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return null;

    if (latin.startsWith('+')) {
      // Already international.
    } else if (digits.startsWith('00')) {
      digits = digits.substring(2);
    } else if (digits.startsWith('0')) {
      // Local Egyptian format: 01001234567 -> 201001234567
      digits = defaultCountryCode + digits.substring(1);
    } else if (!digits.startsWith(defaultCountryCode) && digits.length == 10) {
      // 1001234567 (local number without the leading 0)
      digits = defaultCountryCode + digits;
    }

    final e164 = '+$digits';
    return RegExp(r'^\+[1-9][0-9]{7,14}$').hasMatch(e164) ? e164 : null;
  }
}
