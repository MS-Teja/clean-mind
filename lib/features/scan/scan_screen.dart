import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../src/rust/api/scan.dart';
import '../../theme.dart';
import '../../ui/widgets.dart';
import '../../util/format.dart';
import '../insights/insights_providers.dart';
import '../results/results_screen.dart';
import '../results/tree_providers.dart';
import 'scan_providers.dart';

/// Root of the app: landing → scanning → results, driven by [ScanState].
class ScanScreen extends ConsumerWidget {
  const ScanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Flush the derived-provider chain as soon as a scan lands, while still
    // outside the widget build phase. After a rescan these providers are
    // stale; if the results screen flushes them lazily during its first
    // build, Riverpod must schedule a root-scope rebuild mid-build and
    // throws "setState() or markNeedsBuild() called during build".
    ref.listen<ScanState>(scanControllerProvider, (previous, next) {
      if (next is ScanDone) {
        ref
          ..read(focusTrailProvider)
          ..read(deletedIdsProvider)
          ..read(insightsProvider)
          ..read(reclaimableTotalProvider);
      }
    });
    final scan = ref.watch(scanControllerProvider);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: switch (scan) {
        ScanIdle() => const _LandingView(key: ValueKey('landing')),
        ScanRunning(:final progress) =>
          _ScanningView(key: const ValueKey('scanning'), progress: progress),
        ScanDone() => const ResultsScreen(key: ValueKey('results')),
        ScanFailed(:final message) =>
          _FailedView(key: const ValueKey('failed'), message: message),
      },
    );
  }
}

class _LandingView extends ConsumerWidget {
  const _LandingView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final root = ref.watch(scanRootProvider);
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const _OrbitHero(),
                const SizedBox(height: 24),
                Text(
                  'Clean Mind',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.displaySmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'See what fills your disk — and what is safe to reclaim.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 36),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _PresetChip(
                      icon: Icons.home_rounded,
                      label: 'Home folder',
                      path: homeDirPath(),
                    ),
                    const SizedBox(width: 8),
                    const _PresetChip(
                      icon: Icons.storage_rounded,
                      label: 'Entire disk',
                      path: '/',
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: GlassPanel(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        const IconTile(icon: Icons.folder_rounded, size: 34),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            root,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: mono(12.5, color: scheme.onSurfaceVariant),
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () async {
                            final picked = await getDirectoryPath(
                                initialDirectory: root);
                            if (picked != null) {
                              ref.read(scanRootProvider.notifier).set(picked);
                            }
                          },
                          child: const Text('Change'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: [
                      BoxShadow(
                        color: scheme.primary.withValues(alpha: 0.35),
                        blurRadius: 24,
                      ),
                    ],
                  ),
                  child: FilledButton.icon(
                    onPressed: () =>
                        ref.read(scanControllerProvider.notifier).start(),
                    icon: const Icon(Icons.radar_rounded),
                    label: const Text('Scan'),
                  ),
                ),
                const SizedBox(height: 20),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.shield_outlined,
                          size: 13, color: scheme.outline),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Fresh scan every time. Nothing leaves your machine '
                          'unless you turn on AI analysis — and even then, '
                          'only folder names and sizes.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: scheme.outline),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Quick-pick scan root: highlighted when it is the current root.
class _PresetChip extends ConsumerWidget {
  const _PresetChip({
    required this.icon,
    required this.label,
    required this.path,
  });

  final IconData icon;
  final String label;
  final String path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final selected = ref.watch(scanRootProvider) == path;
    final fg = selected ? scheme.primary : scheme.onSurfaceVariant;

    return Material(
      color: Colors.transparent,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => ref.read(scanRootProvider.notifier).set(path),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: ShapeDecoration(
            color: selected
                ? scheme.primary.withValues(alpha: 0.12)
                : Colors.transparent,
            shape: StadiumBorder(
              side: BorderSide(
                color: selected
                    ? scheme.primary.withValues(alpha: 0.5)
                    : scheme.outlineVariant,
              ),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: fg),
              const SizedBox(width: 6),
              Text(label,
                  style: theme.textTheme.labelMedium?.copyWith(color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Calm rotating "orbit" hero mark: concentric arcs at different phases and
/// alphas around a filled center holding the radar glyph.
class _OrbitHero extends StatefulWidget {
  const _OrbitHero();

  @override
  State<_OrbitHero> createState() => _OrbitHeroState();
}

class _OrbitHeroState extends State<_OrbitHero>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 104,
      height: 104,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return CustomPaint(
            painter: _OrbitPainter(t: _controller.value, color: scheme.primary),
            child: child,
          );
        },
        child: Center(
          child: Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: scheme.primaryContainer,
            ),
            child: Icon(Icons.radar_rounded, size: 34, color: scheme.primary),
          ),
        ),
      ),
    );
  }
}

class _OrbitPainter extends CustomPainter {
  _OrbitPainter({required this.t, required this.color});

  final double t;
  final Color color;

  static const _alphas = [0.8, 0.35, 0.18];
  static const _phases = [0.0, 0.28, 0.6];
  static const _sweeps = [130.0, 190.0, 95.0];
  static const _speeds = [1.0, -0.7, 1.4];

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    for (var i = 0; i < 3; i++) {
      final radius = size.width / 2 - 2 - i * 9;
      final paint = Paint()
        ..color = color.withValues(alpha: _alphas[i])
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      final start = (t * _speeds[i] + _phases[i]) * 2 * math.pi;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        start,
        _sweeps[i] * math.pi / 180,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _OrbitPainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.color != color;
}

class _ScanningView extends ConsumerWidget {
  const _ScanningView({super.key, required this.progress});

  final ScanProgress? progress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bytes = progress?.bytes ?? 0;
    final files = progress?.files ?? 0;
    final dirs = progress?.dirs ?? 0;
    final current = progress?.currentPath ?? '';

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const _RadarSweep(),
                const SizedBox(height: 28),
                TweenAnimationBuilder<double>(
                  tween: Tween(end: bytes.toDouble()),
                  duration: const Duration(milliseconds: 200),
                  builder: (context, value, _) => Text(
                    formatBytes(value.round()),
                    style: mono(44, weight: FontWeight.w700, color: scheme.primary),
                  ),
                ),
                const SizedBox(height: 4),
                Text('found so far',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: scheme.onSurfaceVariant)),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    StatPill(value: formatCount(files), label: 'FILES'),
                    const SizedBox(width: 40),
                    StatPill(value: formatCount(dirs), label: 'FOLDERS'),
                  ],
                ),
                const SizedBox(height: 24),
                SizedBox(
                  height: 20,
                  child: Text(
                    current,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: mono(11, color: scheme.outline),
                  ),
                ),
                const SizedBox(height: 24),
                OutlinedButton(
                  onPressed: () =>
                      ref.read(scanControllerProvider.notifier).cancel(),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Slow radar sweep: static outline + two faint inner rings, with a rotating
/// gradient wedge and leading dot.
class _RadarSweep extends StatefulWidget {
  const _RadarSweep();

  @override
  State<_RadarSweep> createState() => _RadarSweepState();
}

class _RadarSweepState extends State<_RadarSweep>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 96,
      height: 96,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          painter: _RadarPainter(
            t: _controller.value,
            primary: scheme.primary,
            outlineVariant: scheme.outlineVariant,
          ),
        ),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter({
    required this.t,
    required this.primary,
    required this.outlineVariant,
  });

  final double t;
  final Color primary;
  final Color outlineVariant;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 2;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = outlineVariant
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    for (final fraction in [0.66, 0.33]) {
      canvas.drawCircle(
        center,
        radius * fraction,
        Paint()
          ..color = primary.withValues(alpha: 0.15)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }

    final startAngle = t * 2 * math.pi;
    const sweep = math.pi / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final gradient = SweepGradient(
      transform: GradientRotation(startAngle),
      colors: [primary.withValues(alpha: 0.45), primary.withValues(alpha: 0)],
    );
    canvas.drawArc(
      rect,
      startAngle,
      sweep,
      true,
      Paint()..shader = gradient.createShader(rect),
    );

    final dotAngle = startAngle + sweep;
    final dotOffset = center +
        Offset(math.cos(dotAngle), math.sin(dotAngle)) * (radius - 1);
    canvas.drawCircle(dotOffset, 3, Paint()..color = primary);
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) =>
      oldDelegate.t != t;
}

class _FailedView extends ConsumerWidget {
  const _FailedView({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: GlassPanel(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconTile(
                  icon: Icons.error_outline_rounded,
                  color: scheme.error,
                  size: 44,
                ),
                const SizedBox(height: 16),
                Text(message,
                    textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () =>
                      ref.read(scanControllerProvider.notifier).reset(),
                  child: const Text('Back'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
