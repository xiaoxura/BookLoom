/// Static app facts. Keep [version] in sync with `pubspec.yaml`.
abstract final class AppInfo {
  static const String version = '0.1.0';
  static const String buildNumber = '1';
  static const String appId = 'com.xiaoxura.bookloom';
  static const String website = 'https://bookloom.xiaoxura.com';

  static String get displayVersion => 'v$version';
}
