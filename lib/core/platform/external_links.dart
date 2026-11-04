import 'package:url_launcher/url_launcher.dart';

/// Opening external links. Wrapped so the UI can fire and forget, and so tests
/// (where no platform handler exists) never crash.
abstract final class ExternalLinks {
  static Future<void> open(String url) async {
    try {
      final Uri uri = Uri.parse(url);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on Object {
      // No browser / no platform handler: silently ignore.
    }
  }
}
