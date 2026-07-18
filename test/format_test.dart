import 'package:clean_mind/util/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formatBytes on macOS uses decimal units like Finder', () {
    expect(formatBytesForOs('macos', 0), '0 B');
    expect(formatBytesForOs('macos', 999), '999 B');
    expect(formatBytesForOs('macos', 1000), '1.0 KB');
    expect(formatBytesForOs('macos', 48200000000), '48.2 GB');
    expect(formatBytesForOs('macos', 482000000000), '482 GB');
    expect(formatBytesForOs('macos', 1500000), '1.5 MB');
  });

  test('formatBytes on Windows uses 1024-based KB/MB/GB like Explorer', () {
    expect(formatBytesForOs('windows', 1000), '1000 B');
    expect(formatBytesForOs('windows', 1024), '1.0 KB');
    expect(formatBytesForOs('windows', 1536), '1.5 KB');
    // A "500 GB" drive: Explorer and Settings call this ~465 GB.
    expect(formatBytesForOs('windows', 500107862016), '466 GB');
    expect(formatBytesForOs('windows', 48318382080), '45.0 GB');
  });

  test('formatBytes on Linux uses IEC units like df and du', () {
    expect(formatBytesForOs('linux', 1000), '1000 B');
    expect(formatBytesForOs('linux', 1024), '1.0 KiB');
    expect(formatBytesForOs('linux', 1073741824), '1.0 GiB');
    expect(formatBytesForOs('linux', 500107862016), '466 GiB');
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
