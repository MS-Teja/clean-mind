import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../src/rust/api/llm.dart';
import '../../src/rust/api/system.dart';
import '../../theme.dart';
import '../../ui/widgets.dart';
import 'settings_providers.dart';

/// App version/build, read once from the platform bundle for the About section.
final packageInfoProvider = FutureProvider<PackageInfo>(
  (ref) => PackageInfo.fromPlatform(),
);

void showSettingsDialog(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 560),
        child: const SettingsPanel(),
      ),
    ),
  );
}

enum _Section { ai, privacy, about }

class SettingsPanel extends ConsumerStatefulWidget {
  const SettingsPanel({super.key});

  @override
  ConsumerState<SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends ConsumerState<SettingsPanel> {
  late final TextEditingController _baseUrl;
  late final TextEditingController _model;
  final _key = TextEditingController();
  _Section _section = _Section.ai;
  String? _testResult;
  bool _testSuccess = false;
  bool _testing = false;
  bool _keyDirty = false;
  bool _checkingUpdate = false;

  @override
  void initState() {
    super.initState();
    final s = ref.read(llmSettingsProvider);
    _baseUrl = TextEditingController(text: s.baseUrl);
    _model = TextEditingController(text: s.model);
  }

  @override
  void dispose() {
    _baseUrl.dispose();
    _model.dispose();
    _key.dispose();
    super.dispose();
  }

  /// Save everything the user typed. Called from Done, Test connection, a
  /// provider switch, and any other dismissal (Esc, click outside) — closing
  /// the dialog never loses the model name or base URL.
  void _persistFields() {
    final s = ref.read(llmSettingsProvider);
    ref
        .read(llmSettingsProvider.notifier)
        .update(
          LlmSettings(
            provider: s.provider,
            baseUrl: _baseUrl.text.trim(),
            model: _model.text.trim(),
            redact: s.redact,
          ),
        );
    if (_keyDirty && _key.text.trim().isNotEmpty) {
      saveApiKey(provider: s.provider, key: _key.text.trim());
      ref.invalidate(hasApiKeyProvider);
      _keyDirty = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Persist on ANY dismissal — Esc, barrier tap, or Done.
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _persistFields();
      },
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildRail(context),
          VerticalDivider(
            width: 1,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          Expanded(child: _buildContent(context)),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- nav rail

  Widget _buildRail(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final info = ref.watch(packageInfoProvider);
    final version = info.value?.version ?? '';

    return Container(
      width: 190,
      color: scheme.surfaceContainerLow,
      padding: const EdgeInsets.fromLTRB(12, 20, 12, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 18),
            child: Row(
              children: [
                const IconTile(icon: Icons.tune_rounded, size: 30),
                const SizedBox(width: 10),
                Text('Settings', style: theme.textTheme.titleMedium),
              ],
            ),
          ),
          _NavItem(
            icon: Icons.auto_awesome_rounded,
            label: 'AI assistant',
            selected: _section == _Section.ai,
            onTap: () => setState(() => _section = _Section.ai),
          ),
          _NavItem(
            icon: Icons.shield_outlined,
            label: 'Privacy',
            selected: _section == _Section.privacy,
            onTap: () => setState(() => _section = _Section.privacy),
          ),
          _NavItem(
            icon: Icons.info_outline_rounded,
            label: 'About',
            selected: _section == _Section.about,
            onTap: () => setState(() => _section = _Section.about),
          ),
          const Spacer(),
          if (version.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                'Clean Mind $version',
                style: mono(11, color: scheme.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------- content

  Widget _buildContent(BuildContext context) {
    final page = switch (_section) {
      _Section.ai => _buildAiPage(context),
      _Section.privacy => _buildPrivacyPage(context),
      _Section.about => _buildAboutPage(context),
    };

    return Column(
      children: [
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 150),
            child: SingleChildScrollView(
              key: ValueKey(_section),
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 16),
              child: page,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 0, 28, 20),
          child: Row(
            children: [
              if (_section == _Section.ai) ...[
                OutlinedButton(
                  onPressed: _testing ? null : _testConnection,
                  child: Text(_testing ? 'Testing…' : 'Test connection'),
                ),
              ],
              const Spacer(),
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _pageHeader(BuildContext context, String title, String subtitle) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  // ---------------------------------------------------------------- AI page

  Widget _buildAiPage(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final settings = ref.watch(llmSettingsProvider);
    final hasKey = ref.watch(hasApiKeyProvider(settings.provider));
    final needsKey = settings.provider != 'ollama';
    final monoFieldStyle = mono(13, color: scheme.onSurface);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _pageHeader(
          context,
          'AI assistant',
          'Clean Mind works fully without AI. Turn it on for extra '
              'suggestions — you stay in control.',
        ),
        _SectionLabel('Provider'),
        const SizedBox(height: 10),
        SegmentedButton<String>(
          expandedInsets: EdgeInsets.zero,
          segments: const [
            ButtonSegment(value: 'anthropic', label: Text('Anthropic')),
            ButtonSegment(value: 'openai', label: Text('OpenAI-compat.')),
            ButtonSegment(value: 'ollama', label: Text('Ollama')),
          ],
          selected: {settings.provider},
          onSelectionChanged: (selected) {
            // Save what was typed for the current provider first, then load
            // whatever was last saved for the new one — switching never
            // wipes a customized model or base URL.
            _persistFields();
            ref
                .read(llmSettingsProvider.notifier)
                .switchProvider(selected.first);
            final s = ref.read(llmSettingsProvider);
            _baseUrl.text = s.baseUrl;
            _model.text = s.model;
            setState(() => _testResult = null);
          },
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _baseUrl,
          style: monoFieldStyle,
          decoration: const InputDecoration(
            labelText: 'Base URL',
            helperText:
                'For OpenRouter, LM Studio, etc. change this to their endpoint',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _model,
          style: monoFieldStyle,
          decoration: const InputDecoration(
            labelText: 'Model',
            helperText: 'Remembered per provider',
          ),
        ),
        if (needsKey) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _key,
            obscureText: true,
            style: monoFieldStyle,
            onChanged: (_) => _keyDirty = true,
            decoration: InputDecoration(
              labelText: 'API key',
              hintText: hasKey ? '•••••••••• saved' : null,
              helperText: hasKey
                  ? 'A key is already saved — leave empty to keep it'
                  : 'Paste your key here',
            ),
          ),
          const SizedBox(height: 10),
          _ReassurancePanel(
            icon: Icons.lock_outline_rounded,
            text:
                'Your key lives in the system keychain, never in a file. It '
                'is only read when you run a connection test or analysis — '
                'opening this screen never touches it.',
          ),
        ] else ...[
          const SizedBox(height: 12),
          _ReassurancePanel(
            icon: Icons.verified_user_outlined,
            text:
                'Ollama runs fully on your machine — nothing is sent to '
                'any cloud, and no API key is needed.',
          ),
        ],
        if (_testResult != null) ...[
          const SizedBox(height: 14),
          Row(
            children: [
              Icon(
                _testSuccess
                    ? Icons.check_circle_rounded
                    : Icons.error_outline_rounded,
                size: 14,
                color: _testSuccess ? scheme.primary : scheme.error,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  _testResult!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _testSuccess ? scheme.primary : scheme.error,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _testConnection() async {
    _persistFields();
    setState(() {
      _testing = true;
      _testResult = null;
    });
    try {
      final reply = await testLlmConnection();
      setState(() {
        _testSuccess = true;
        _testResult = '✓ Connected: $reply';
      });
    } catch (e) {
      setState(() {
        _testSuccess = false;
        _testResult = '$e';
      });
    } finally {
      setState(() => _testing = false);
    }
  }

  // ------------------------------------------------------------ privacy page

  Widget _buildPrivacyPage(BuildContext context) {
    final settings = ref.watch(llmSettingsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _pageHeader(
          context,
          'Privacy',
          'No telemetry, no account, no background network calls. '
              'Scan data never leaves this machine unless you ask AI for help.',
        ),
        _SectionLabel('When using AI'),
        const SizedBox(height: 10),
        GlassPanel(
          padding: const EdgeInsets.all(4),
          radius: 12,
          child: SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            title: const Text('Pseudonymize folder names'),
            subtitle: const Text(
              'Replace personal folder names with placeholders before '
              'anything leaves this machine',
            ),
            value: settings.redact,
            onChanged: (v) {
              final s = ref.read(llmSettingsProvider);
              ref
                  .read(llmSettingsProvider.notifier)
                  .update(
                    LlmSettings(
                      provider: s.provider,
                      baseUrl: s.baseUrl,
                      model: s.model,
                      redact: v,
                    ),
                  );
            },
          ),
        ),
        const SizedBox(height: 14),
        _ReassurancePanel(
          icon: Icons.visibility_off_outlined,
          text:
              'Even with AI on, only folder metadata (names, sizes, counts) '
              'is ever sent — never file contents. The rules engine stays the '
              'source of truth, and AI can never mark anything as safe.',
        ),
        const SizedBox(height: 10),
        _ReassurancePanel(
          icon: Icons.storage_rounded,
          text:
              'Scan results live in memory only and are gone when you quit. '
              'Settings are a small local file; API keys stay in the system '
              'keychain.',
        ),
      ],
    );
  }

  // -------------------------------------------------------------- about page

  Widget _buildAboutPage(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final info = ref.watch(packageInfoProvider);
    final version = info.value?.version ?? '';
    final build = info.value?.buildNumber ?? '';
    final versionLabel = version.isEmpty
        ? '…'
        : 'Version $version${build.isEmpty ? '' : ' ($build)'}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _pageHeader(
          context,
          'About',
          'Free and open source, Apache-2.0 licensed.',
        ),
        Row(
          children: [
            Text('Clean Mind', style: theme.textTheme.titleMedium),
            const SizedBox(width: 8),
            Text(versionLabel, style: mono(12, color: scheme.onSurfaceVariant)),
          ],
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () =>
                  openUrl(url: 'https://github.com/MS-Teja/clean-mind'),
              icon: const Icon(Icons.code_rounded, size: 16),
              label: const Text('GitHub'),
            ),
            OutlinedButton.icon(
              onPressed: () => showLicensePage(
                context: context,
                applicationName: 'Clean Mind',
                applicationVersion: version,
              ),
              icon: const Icon(Icons.description_outlined, size: 16),
              label: const Text('Licenses'),
            ),
            OutlinedButton.icon(
              onPressed: _checkingUpdate || version.isEmpty
                  ? null
                  : () => _checkForUpdate(version),
              icon: _checkingUpdate
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.system_update_alt_rounded, size: 16),
              label: Text(_checkingUpdate ? 'Checking…' : 'Check for updates'),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _checkForUpdate(String version) async {
    setState(() => _checkingUpdate = true);
    try {
      final result = await checkForUpdate(currentVersion: version);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            result.updateAvailable ? 'Update available' : 'Up to date',
          ),
          content: Text(
            result.updateAvailable
                ? 'Version ${result.latest} is available.'
                : "You're up to date.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
            if (result.updateAvailable)
              FilledButton(
                onPressed: () {
                  Navigator.pop(context);
                  openUrl(url: result.releaseUrl);
                },
                child: const Text('View release'),
              ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Update check failed: $e')));
    } finally {
      if (mounted) setState(() => _checkingUpdate = false);
    }
  }
}

/// One entry in the settings navigation rail.
class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected
            ? scheme.primary.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: selected ? scheme.primary : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: selected ? scheme.primary : scheme.onSurface,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
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

/// Small uppercase section divider label used across the settings screen.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text.toUpperCase(),
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
      ),
    );
  }
}

/// Calm, non-alarming reassurance note (privacy / keychain), styled as a soft
/// primary-tinted panel rather than a warning.
class _ReassurancePanel extends StatelessWidget {
  const _ReassurancePanel({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: scheme.primary),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
