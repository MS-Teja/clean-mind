import 'package:clean_mind/util/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formatBytes uses decimal units like the OS storage panel', () {
    expect(formatBytes(0), '0 B');
    expect(formatBytes(999), '999 B');
    expect(formatBytes(1000), '1.0 KB');
    expect(formatBytes(48200000000), '48.2 GB');
    expect(formatBytes(482000000000), '482 GB');
    expect(formatBytes(1500000), '1.5 MB');
  });

  test('formatCount groups thousands', () {
    expect(formatCount(999), '999');
    expect(formatCount(1234567), '1,234,567');
  });

  test('formatStaleness reads naturally', () {
    expect(formatStaleness(-1), '');
    expect(formatStaleness(0), 'touched today');
    expect(formatStaleness(1), 'untouched for 1 day');
    expect(formatStaleness(400), 'untouched for 13 months');
    expect(formatStaleness(900), 'untouched for 2 years');
  });
}
