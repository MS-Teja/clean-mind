/// Human-readable byte count using decimal units, matching what Finder and
/// most OS storage panels report.
String formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1000 && unit < units.length - 1) {
    value /= 1000;
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
