import 'dart:io' show Platform;

/// Human-readable byte count in the convention of the platform's own tools:
/// decimal KB/MB/GB on macOS (Finder), 1024-based KB/MB/GB on Windows
/// (Explorer, storage settings), 1024-based KiB/MiB/GiB on Linux (df, du,
/// KDE). Anything else would read as "slightly wrong" next to the OS.
String formatBytes(int bytes) => formatBytesForOs(Platform.operatingSystem, bytes);

/// [formatBytes] with the platform pinned; `os` is a
/// `Platform.operatingSystem` value. Split out so tests can cover every
/// platform's convention regardless of the host they run on.
String formatBytesForOs(String os, int bytes) {
  final base = os == 'macos' ? 1000 : 1024;
  final units = os == 'linux'
      ? const ['B', 'KiB', 'MiB', 'GiB', 'TiB', 'PiB']
      : const ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= base && unit < units.length - 1) {
    value /= base;
    unit++;
  }
  final digits = value >= 100 || unit == 0 ? 0 : 1;
  return '${value.toStringAsFixed(digits)} ${units[unit]}';
}

/// Grouped integer, e.g. 1234567 → "1,234,567".
String formatCount(int n) {
  final s = n.toString();
  final out = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
    out.write(s[i]);
  }
  return out.toString();
}

/// "untouched for 14 months" style staleness, from days. Empty when unknown.
String formatStaleness(int days) {
  if (days < 0) return '';
  if (days < 1) return 'touched today';
  if (days < 31) return 'untouched for $days day${days == 1 ? '' : 's'}';
  final months = days ~/ 30;
  if (months < 24) return 'untouched for $months month${months == 1 ? '' : 's'}';
  return 'untouched for ${months ~/ 12} years';
}
