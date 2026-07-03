import 'dart:math' as math;
import 'dart:ui';

/// Squarified treemap layout (Bruls, Huizing & van Wijk). Lays `values`
/// (sorted descending) into `bounds`, keeping tile aspect ratios near 1.
List<Rect> squarify(List<double> values, Rect bounds) {
  final total = values.fold<double>(0, (a, b) => a + b);
  if (total <= 0 || bounds.isEmpty) {
    return List.filled(values.length, Rect.zero);
  }
  final scale = bounds.width * bounds.height / total;
  final areas = values.map((v) => math.max(v * scale, 0.0)).toList();

  final rects = List<Rect>.filled(areas.length, Rect.zero);
  var free = bounds;
  var start = 0;
  while (start < areas.length) {
    final shortSide = math.min(free.width, free.height);
    var end = start;
    var rowSum = 0.0;
    var rowWorst = double.infinity;
    // Grow the row while the worst aspect ratio keeps improving.
    while (end < areas.length) {
      final candidateSum = rowSum + areas[end];
      final candidateWorst =
          _worstAspect(areas, start, end + 1, candidateSum, shortSide);
      if (candidateWorst > rowWorst) break;
      rowSum = candidateSum;
      rowWorst = candidateWorst;
      end++;
    }
    if (end == start) end++; // always place at least one tile

    // Lay the row along the short side of the free rectangle.
    final horizontalRow = free.width >= free.height;
    final thickness = shortSide <= 0 ? 0.0 : rowSum / shortSide;
    var offset = horizontalRow ? free.top : free.left;
    for (var i = start; i < end; i++) {
      final length = rowSum <= 0 ? 0.0 : areas[i] / rowSum * shortSide;
      rects[i] = horizontalRow
          ? Rect.fromLTWH(free.left, offset, thickness, length)
          : Rect.fromLTWH(offset, free.top, length, thickness);
      offset += length;
    }
    free = horizontalRow
        ? Rect.fromLTRB(free.left + thickness, free.top, free.right, free.bottom)
        : Rect.fromLTRB(free.left, free.top + thickness, free.right, free.bottom);
    start = end;
  }
  return rects;
}

double _worstAspect(
    List<double> areas, int start, int end, double sum, double side) {
  if (sum <= 0 || side <= 0) return double.infinity;
  var maxArea = 0.0;
  var minArea = double.infinity;
  for (var i = start; i < end; i++) {
    maxArea = math.max(maxArea, areas[i]);
    minArea = math.min(minArea, areas[i]);
  }
  final s2 = sum * sum;
  final w2 = side * side;
  return math.max(w2 * maxArea / s2, s2 / (w2 * minArea));
}
