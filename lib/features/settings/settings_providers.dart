import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../src/rust/api/llm.dart';

/// Provider/model/redaction settings, persisted by the Rust core in the OS
/// config directory. Keys never pass through here — they go straight to the
/// keychain via [saveApiKey].
class LlmSettingsController extends Notifier<LlmSettings> {
  @override
  LlmSettings build() => getLlmSettings();

  void update(LlmSettings settings) {
    setLlmSettings(settings: settings);
    state = settings;
  }

  /// Switch provider, restoring whatever base URL and model the user last
  /// saved for it (or that provider's defaults if never configured).
  void switchProvider(String provider) {
    update(settingsForProvider(provider: provider));
  }
}

final llmSettingsProvider =
    NotifierProvider<LlmSettingsController, LlmSettings>(
      LlmSettingsController.new,
    );

/// Whether a key is stored for the given provider. Bumped via invalidation
/// after a save.
final hasApiKeyProvider = Provider.family<bool, String>((ref, provider) {
  return hasApiKey(provider: provider);
});
