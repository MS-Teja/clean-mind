import 'package:clean_mind/util/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formatBytes uses decimal units like the OS storage panel', () {
    expect(formatBytes(BigInt.from(0)), '0 B');
    expect(formatBytes(BigInt.from(999)), '999 B');
    expect(formatBytes(BigInt.from(1000)), '1.0 KB');
    expect(formatBytes(BigInt.from(48200000000)), '48.2 GB');
    expect(formatBytes(BigInt.from(482000000000)), '482 GB');
    expect(formatBytes(BigInt.from(1500000)), '1.5 MB');
  });

  test('formatCount groups thousands', () {
    expect(formatCount(BigInt.from(999)), '999');
    expect(formatCount(BigInt.from(1234567)), '1,234,567');
  });
}
