import 'dart:ui';

import 'package:clean_mind/features/results/treemap/squarify.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tiles cover the area and never overlap', () {
    const bounds = Rect.fromLTWH(0, 0, 400, 300);
    final values = [6.0, 6.0, 4.0, 3.0, 2.0, 2.0, 1.0];
    final rects = squarify(values, bounds);

    expect(rects.length, values.length);
    final totalArea =
        rects.fold<double>(0, (s, r) => s + r.width * r.height);
    expect(totalArea, closeTo(bounds.width * bounds.height, 1.0));

    for (var i = 0; i < rects.length; i++) {
      expect(bounds.left - 0.01 <= rects[i].left, isTrue);
      expect(rects[i].right <= bounds.right + 0.01, isTrue);
      for (var j = i + 1; j < rects.length; j++) {
        final overlap = rects[i].intersect(rects[j]);
        final overlapArea = overlap.isEmpty
            ? 0.0
            : (overlap.width.clamp(0, double.infinity)) *
                (overlap.height.clamp(0, double.infinity));
        expect(overlapArea, closeTo(0, 0.01),
            reason: 'tiles $i and $j overlap');
      }
    }
  });

  test('areas are proportional to values', () {
    const bounds = Rect.fromLTWH(0, 0, 200, 200);
    final rects = squarify([3.0, 1.0], bounds);
    final a0 = rects[0].width * rects[0].height;
    final a1 = rects[1].width * rects[1].height;
    expect(a0 / a1, closeTo(3.0, 0.01));
  });

  test('degenerate inputs do not crash', () {
    expect(squarify([], const Rect.fromLTWH(0, 0, 100, 100)), isEmpty);
    expect(squarify([0.0, 0.0], const Rect.fromLTWH(0, 0, 100, 100)),
        everyElement(Rect.zero));
    expect(squarify([1.0], Rect.zero), everyElement(Rect.zero));
  });
}
