import 'dart:io';

/// What the OS calls its trash can: "Recycle Bin" on Windows, "Trash"
/// everywhere else. Used in labels and dialogs so the UI speaks the
/// platform's language.
final String trashName = Platform.isWindows ? 'Recycle Bin' : 'Trash';

/// Root path for a whole-disk scan: the system drive on Windows, `/` on
/// Unix-likes.
final String diskRootPath = Platform.isWindows
    ? (Platform.environment['SystemDrive'] ?? 'C:') + r'\'
    : '/';
