/// Shared, explicit input budgets for untrusted files.
///
/// ZIP budgets are checked against both central-directory claims and bytes
/// actually produced by decompression. Callers must also enforce these limits
/// for non-ZIP inputs such as TXT, fonts, and cover images.
class InputLimits {
  const InputLimits({
    this.maxArchiveBytes,
    required this.maxEntries,
    this.maxEntryBytes,
    required this.maxOutputBytes,
    required this.maxXmlBytes,
    required this.maxXmlDepth,
    required this.maxXmlContentCharacters,
    this.maxMetadataBytes = 32 * 1024 * 1024,
  });

  final int? maxArchiveBytes;
  final int maxEntries;
  final int? maxEntryBytes;
  final int maxOutputBytes;
  final int maxXmlBytes;
  final int maxXmlDepth;
  final int maxXmlContentCharacters;
  final int maxMetadataBytes;

  int? entryLimit(String path) => maxEntryBytes;
}

class ImportLimits extends InputLimits {
  const ImportLimits({bool isAndroid = false})
    : super(
        maxArchiveBytes: maxSingleInputBytes,
        maxEntries: maxFormatEntries,
        maxEntryBytes: maxFormatEntryBytes,
        maxOutputBytes: isAndroid
            ? maxAndroidOutputBytes
            : maxDesktopOutputBytes,
        maxXmlBytes: 8 * mebibyte,
        maxXmlDepth: 64,
        maxXmlContentCharacters: 4 * mebibyte,
      );

  static const int mebibyte = 1024 * 1024;
  static const int maxSingleInputBytes = 80 * mebibyte;
  static const int maxBatchInputs = 40;
  static const int maxBatchInputBytes = 200 * mebibyte;
  static const int maxInputBytes = maxSingleInputBytes;
  static const int maxBatchFiles = maxBatchInputs;
  static const int maxBatchBytes = maxBatchInputBytes;
  static const int maxFontBytes = 20 * mebibyte;
  static const int maxEncodedCoverBytes = 24 * mebibyte;
  static const int maxFormatEntries = 10000;
  static const int maxFormatEntryBytes = 32 * mebibyte;
  static const int maxDesktopOutputBytes = 256 * mebibyte;
  static const int maxAndroidOutputBytes = 128 * mebibyte;

  // Provisional cover Spike value; enforce before image decode on each entry.
  static const int maxCoverPixels = 12 * 1000 * 1000;
}

/// Backups use a caller-approved write budget based on available target space.
/// This deliberately has no EPUB/DOCX 32 MiB entry or 128/256 MiB total cap.
/// Source entries use the same total write budget rather than ImportLimits'
/// default 80 MiB single-import cap.
class BackupLimits extends InputLimits {
  const BackupLimits({required super.maxOutputBytes, super.maxEntries = 100000})
    : super(
        maxXmlBytes: 8 * ImportLimits.mebibyte,
        maxXmlDepth: 64,
        maxXmlContentCharacters: 4 * ImportLimits.mebibyte,
      );

  static const int maxManifestBytes = ImportLimits.mebibyte;

  @override
  int? entryLimit(String path) {
    if (path == 'manifest.json') return maxManifestBytes;
    return null;
  }
}
