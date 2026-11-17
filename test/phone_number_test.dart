import 'package:flutter_test/flutter_test.dart';
import 'package:workplace_app/features/auth/domain/phone_number.dart';

void main() {
  test('Egyptian local numbers get +20', () {
    expect(PhoneNumber.normalize('01001234567'), '+201001234567');
    expect(PhoneNumber.normalize('0100 123 4567'), '+201001234567');
    expect(PhoneNumber.normalize('1001234567'), '+201001234567');
  });

  test('international formats are kept', () {
    expect(PhoneNumber.normalize('+201001234567'), '+201001234567');
    expect(PhoneNumber.normalize('00201001234567'), '+201001234567');
    expect(PhoneNumber.normalize('201001234567'), '+201001234567');
    expect(PhoneNumber.normalize('+966 50 123 4567'), '+966501234567');
  });

  test('Arabic digits work', () {
    expect(PhoneNumber.normalize('٠١٠٠١٢٣٤٥٦٧'), '+201001234567');
  });

  test('invalid input returns null', () {
    expect(PhoneNumber.normalize(''), isNull);
    expect(PhoneNumber.normalize('abc'), isNull);
    expect(PhoneNumber.normalize('123'), isNull);
  });
}
