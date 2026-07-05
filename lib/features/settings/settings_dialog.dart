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
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: const SettingsPanel(),
      ),
    ),
  );
}

class SettingsPanel extends ConsumerStatefulWidget {
  const SettingsPanel({super.key});

  @override
  ConsumerState<SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends ConsumerState<SettingsPanel> {
  late final TextEditingController _baseUrl;
  late final TextEditingController _model;
  final _key = TextEditingController();
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

  void _persistFields() {
    final s = ref.read(llmSettingsProvider);
    ref.read(llmSettingsProvider.notifier).update(LlmSettings(
          provider: s.provider,
          baseUrl: _baseUrl.text.trim(),
          model: _model.text.trim(),
          redact: s.redact,
        ));
    if (_keyDirty && _key.text.trim().isNotEmpty) {
      saveApiKey(provider: s.provider, key: _key.text.trim());
      ref.invalidate(hasApiKeyProvider);
      _keyDirty = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final settings = ref.watch(llmSettingsProvider);
    final hasKey = ref.watch(hasApiKeyProvider(settings.provider));
    final needsKey = settings.provider != 'ollama';
    final monoFieldStyle = mono(13, color: scheme.onSurface);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('AI settings', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(
            'Bring your own model. Keys are stored in the system keychain, '
            'never in files.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          SegmentedButton<String>(
            expandedInsets: EdgeInsets.zero,
            segments: const [
              ButtonSegment(value: 'anthropic', label: Text('Anthropic')),
              ButtonSegment(value: 'openai', label: Text('OpenAI-compat.')),
              ButtonSegment(value: 'ollama', label: Text('Ollama')),
            ],
            selected: {settings.provider},
            onSelectionChanged: (selected) {
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
                helperText: hasKey
                    ? 'A key is stored in the keychain — leave empty to keep it'
                    : 'Stored in the system keychain',
              ),
            ),
          ] else ...[
            const SizedBox(height: 12),
            GlassPanel(
              color: scheme.surfaceContainer,
              radius: 10,
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  Icon(Icons.lock_rounded, size: 14, color: scheme.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Ollama runs fully on your machine — nothing is sent '
                      'to any cloud.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          GlassPanel(
            padding: const EdgeInsets.all(4),
            radius: 12,
            child: SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              title: const Text('Pseudonymize folder names'),
              subtitle: const Text(
                  'Replace personal folder names with placeholders before '
                  'anything leaves this machine'),
              value: settings.redact,
              onChanged: (v) {
                final s = ref.read(llmSettingsProvider);
                ref.read(llmSettingsProvider.notifier).update(LlmSettings(
                      provider: s.provider,
                      baseUrl: s.baseUrl,
                      model: s.model,
                      redact: v,
                    ));
              },
            ),
          ),
          const SizedBox(height: 12),
          if (_testResult != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
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
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: _testSuccess ? scheme.primary : scheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              OutlinedButton(
                onPressed: _testing
                    ? null
                    : () async {
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
                      },
                child: Text(_testing ? 'Testing…' : 'Test connection'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: () {
                  _persistFields();
                  Navigator.pop(context);
                },
                child: const Text('Done'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Divider(color: scheme.outlineVariant),
          const SizedBox(height: 20),
          _buildAbout(context, theme),
        ],
      ),
    );
  }

  Widget _buildAbout(BuildContext context, ThemeData theme) {
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
        Text('About', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 4),
        Row(
          children: [
            Text('Clean Mind', style: theme.textTheme.titleMedium),
            const SizedBox(width: 8),
            Text(
              versionLabel,
              style: mono(12, color: scheme.onSurfaceVariant),
            ),
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
          title: Text(result.updateAvailable ? 'Update available' : 'Up to date'),
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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Update check failed: $e')));
    } finally {
      if (mounted) setState(() => _checkingUpdate = false);
    }
  }
}
