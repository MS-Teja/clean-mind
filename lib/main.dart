import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/scan/scan_screen.dart';
import 'src/rust/frb_generated.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Attribute the bundled OFL fonts in the Licenses page.
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(
      ['SpaceGrotesk'],
      await rootBundle.loadString('assets/fonts/OFL-SpaceGrotesk.txt'),
    );
    yield LicenseEntryWithLineBreaks(
      ['JetBrainsMono'],
      await rootBundle.loadString('assets/fonts/OFL-JetBrainsMono.txt'),
    );
  });
  await RustLib.init();
  runApp(const ProviderScope(child: CleanMindApp()));
}

class CleanMindApp extends StatelessWidget {
  const CleanMindApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Clean Mind',
      debugShowCheckedModeBanner: false,
      theme: CleanMindTheme.light,
      darkTheme: CleanMindTheme.dark,
      themeMode: ThemeMode.system,
      home: const ScanScreen(),
    );
  }
}
