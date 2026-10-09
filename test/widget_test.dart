// Kept so `flutter create .` does not add its default counter-app test.
import 'package:flutter_test/flutter_test.dart';
import 'package:stripsnap/engine/profiles.dart';

void main() {
  test('profiles load', () => expect(profiles.length, greaterThan(1)));
}
