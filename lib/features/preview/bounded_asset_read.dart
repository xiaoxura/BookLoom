import 'dart:io';
import 'dart:typed_data';

/// A stored asset can be missing or replaced independently of its database
/// row. Check both the file size and the bytes actually streamed from disk.
Future<Uint8List> readBoundedAssetFile(File file, int maxBytes) async {
  if (await file.length() > maxBytes) {
    throw const FormatException('Asset exceeds its size limit.');
  }
  final bytes = BytesBuilder(copy: false);
  var length = 0;
  await for (final chunk in file.openRead()) {
    length += chunk.length;
    if (length > maxBytes) {
      throw const FormatException('Asset exceeds its size limit.');
    }
    bytes.add(chunk);
  }
  return bytes.takeBytes();
}
