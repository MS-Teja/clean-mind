import 'dart:io';
import 'dart:math' as math;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../src/rust/api/scan.dart';
import '../../src/rust/api/system.dart';
import '../../theme.dart';
import '../../ui/widgets.dart';
import '../../util/format.dart';
import '../../util/platform.dart';
import '../insights/insights_providers.dart';
import '../results/results_screen.dart';
import '../results/tree_providers.dart';
import '../settings/settings_dialog.dart';
import 'scan_providers.dart';

/// Root of the app: landing → scanning → results, driven by [ScanState].
/// A folder dropped anywhere on the window starts a scan of it.
class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  bool _dragging = false;
  bool _settingsOpen = false;

  /// Cmd+, (Ctrl+, elsewhere) — the platform-standard settings shortcut.
  void _openSettings() {
    if (_settingsOpen) return;
    _settingsOpen = true;
    showSettingsDialog(context).whenComplete(() => _settingsOpen = false);
  }

  void _onDrop(DropDoneDetails details) {
    if (details.files.isEmpty) return;
    final path = details.files.first.path;
    final String dir;
    try {
      // A dropped file scans its containing folder; a folder scans itself.
      dir = FileSystemEntity.isDirectorySync(path)
          ? path
          : File(path).parent.path;
    } catch (_) {
      return;
    }
    ref.read(scanRootProvider.notifier).set(dir);
    ref.read(scanControllerProvider.notifier).start();
  }

  @override
  Widget build(BuildContext context) {
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
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.comma, meta: true):
            _openSettings,
        const SingleActivator(LogicalKeyboardKey.comma, control: true):
            _openSettings,
      },
      child: DropTarget(
        onDragEntered: (_) => setState(() => _dragging = true),
        onDragExited: (_) => setState(() => _dragging = false),
        onDragDone: (details) {
          setState(() => _dragging = false);
          _onDrop(details);
        },
        child: Focus(
          // The shortcut needs a focus node in scope even on the landing view.
          autofocus: true,
          child: Stack(
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: switch (scan) {
                  ScanIdle() => const _LandingView(key: ValueKey('landing')),
                  ScanRunning(:final progress) => _ScanningView(
                    key: const ValueKey('scanning'),
                    progress: progress,
                  ),
                  ScanDone() => const ResultsScreen(key: ValueKey('results')),
                  ScanFailed(:final message) => _FailedView(
                    key: const ValueKey('failed'),
                    message: message,
                  ),
                },
              ),
              if (_dragging) const _DropOverlay(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Full-window hint shown while a folder is dragged over the app.
class _DropOverlay extends StatelessWidget {
  const _DropOverlay();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          color: scheme.scrim.withValues(alpha: 0.45),
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 22),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: scheme.primary.withValues(alpha: 0.6),
                  width: 2,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.download_rounded, size: 34, color: scheme.primary),
                  const SizedBox(height: 10),
                  Text(
                    'Drop a folder to scan it',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
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
      body: Stack(
        children: [
          // Settings should be reachable before the first scan too.
          Positioned(
            top: 34,
            right: 14,
            child: IconButton(
              tooltip: 'Settings',
              icon: const Icon(Icons.settings_rounded),
              color: scheme.onSurfaceVariant,
              onPressed: () => showSettingsDialog(context),
            ),
          ),
          _buildBody(context, theme, scheme, root, ref),
        ],
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    ThemeData theme,
    ColorScheme scheme,
    String root,
    WidgetRef ref,
  ) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const _OrbitHero(),
              const SizedBox(height: 20),
              Text(
                'Clean Mind',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineMedium,
              ),
              const SizedBox(height: 6),
              Text(
                'See what fills your disk — and what is safe to reclaim.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 32),
              const _ScanTargetCard(),
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
              const SizedBox(height: 18),
              Text(
                'Nothing leaves your machine — even optional AI analysis '
                'sees only folder names and sizes.',
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.outline,
                ),
              ),
              if (fullDiskAccessStatus() == FdaStatus.denied) ...[
                const SizedBox(height: 6),
                const _FullDiskAccessHint(),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The one card that owns "what will be scanned": current target + Change +
/// recent-scans menu on top, quick-pick locations below. Replaces the old
/// stack of chips + path panel + recents list that crowded the landing view.
class _ScanTargetCard extends ConsumerWidget {
  const _ScanTargetCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final root = ref.watch(scanRootProvider);
    return SizedBox(
      width: double.infinity,
      child: GlassPanel(
        padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const IconTile(icon: Icons.folder_rounded, size: 34),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    root,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: mono(12.5, color: scheme.onSurface),
                  ),
                ),
                const SizedBox(width: 4),
                const _RecentMenu(),
                TextButton(
                  onPressed: () async {
                    final picked = await getDirectoryPath(
                      initialDirectory: root,
                    );
                    if (picked != null) {
                      ref.read(scanRootProvider.notifier).set(picked);
                    }
                  },
                  child: const Text('Change'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Divider(height: 1, color: scheme.outlineVariant),
            const SizedBox(height: 10),
            const _LocationChips(),
          ],
        ),
      ),
    );
  }
}

/// History dropdown for recently-scanned roots. Hidden until there is at
/// least one recent path other than the current target.
class _RecentMenu extends ConsumerWidget {
  const _RecentMenu();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(scanRootProvider);
    final recents = recentScanRoots()
        .where((p) => p != current)
        .take(6)
        .toList(growable: false);
    if (recents.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return PopupMenuButton<String>(
      tooltip: 'Recent scans',
      icon: Icon(
        Icons.history_rounded,
        size: 18,
        color: scheme.onSurfaceVariant,
      ),
      onSelected: (path) => ref.read(scanRootProvider.notifier).set(path),
      itemBuilder: (context) => [
        for (final path in recents)
          PopupMenuItem(
            value: path,
            child: Text(
              path,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: mono(12, color: scheme.onSurface),
            ),
          ),
      ],
    );
  }
}

/// One quiet line + link shown when macOS Full Disk Access is missing, so a
/// home/disk scan under-reporting is explained without shouting at the user.
class _FullDiskAccessHint extends StatelessWidget {
  const _FullDiskAccessHint();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Some folders are off-limits without Full Disk Access.',
          style: theme.textTheme.labelSmall?.copyWith(color: scheme.outline),
        ),
        TextButton(
          onPressed: openFullDiskAccessSettings,
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            textStyle: const TextStyle(fontSize: 11),
          ),
          child: const Text('Grant access'),
        ),
      ],
    );
  }
}

/// Smart locations (Home, Desktop, Documents, Downloads, Applications, mounted
/// volumes) plus "Entire disk", built from the platform's real directories.
class _LocationChips extends ConsumerWidget {
  const _LocationChips();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locations = standardLocations()
        .where((l) => l.exists)
        .toList(growable: false);
    return Wrap(
      alignment: WrapAlignment.start,
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final loc in locations)
          _PresetChip(
            icon: _iconForKind(loc.kind),
            label: loc.label,
            path: loc.path,
          ),
        _PresetChip(
          icon: Icons.storage_rounded,
          label: 'Entire disk',
          path: diskRootPath,
        ),
      ],
    );
  }
}

IconData _iconForKind(String kind) {
  switch (kind) {
    case 'home':
      return Icons.home_rounded;
    case 'desktop':
      return Icons.desktop_mac_rounded;
    case 'documents':
      return Icons.description_rounded;
    case 'downloads':
      return Icons.download_rounded;
    case 'applications':
      return Icons.apps_rounded;
    case 'volume':
      return Icons.storage_rounded;
    default:
      return Icons.folder_rounded;
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
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: ShapeDecoration(
            // Quiet by default; only the selected pick draws attention.
            color: selected
                ? scheme.primary.withValues(alpha: 0.14)
                : scheme.onSurface.withValues(alpha: 0.05),
            shape: StadiumBorder(
              side: selected
                  ? BorderSide(color: scheme.primary.withValues(alpha: 0.5))
                  : BorderSide.none,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: fg),
              const SizedBox(width: 5),
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(color: fg),
              ),
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
                    style: mono(
                      44,
                      weight: FontWeight.w700,
                      color: scheme.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'found so far',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
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
          ..color = primary.withValues(alpha: 0.22)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }

    // Sweep wedge: brightest at the leading edge, fading out over the tail
    // behind it (a gradient across the full circle would leave the wedge
    // almost uniformly bright, with a hard cut at both edges).
    final lead = t * 2 * math.pi;
    const sweep = math.pi * 0.6;
    final rect = Rect.fromCircle(center: center, radius: radius - 1);
    final gradient = SweepGradient(
      transform: GradientRotation(lead - sweep),
      colors: [
        primary.withValues(alpha: 0),
        primary.withValues(alpha: 0.16),
        primary.withValues(alpha: 0.42),
      ],
      stops: const [0.0, 0.6 * sweep / (2 * math.pi), sweep / (2 * math.pi)],
    );
    canvas.drawArc(
      rect,
      lead - sweep,
      sweep,
      true,
      Paint()..shader = gradient.createShader(rect),
    );

    // Leading radius line with a soft glow, tipped by the scan dot.
    final tipDir = Offset(math.cos(lead), math.sin(lead));
    final tip = center + tipDir * (radius - 2);
    canvas.drawLine(
      center,
      tip,
      Paint()
        ..color = primary.withValues(alpha: 0.85)
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(
      tip,
      5,
      Paint()
        ..color = primary.withValues(alpha: 0.55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawCircle(tip, 2.6, Paint()..color = primary);
    canvas.drawCircle(center, 2.2, Paint()..color = primary);
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) => oldDelegate.t != t;
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
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge,
                ),
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
