import 'package:bookloom/core/app_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('startup time is recorded before diagnostics first reads it', () async {
    final beforeStartup = DateTime.now();
    AppInfo.initialize();
    final afterStartup = DateTime.now();

    await Future<void>.delayed(const Duration(milliseconds: 30));
    AppInfo.initialize();
    final startedAt = AppInfo.startedAt;

    expect(startedAt.isBefore(beforeStartup), isFalse);
    expect(startedAt.isAfter(afterStartup), isFalse);
    expect(AppInfo.startedAt, startedAt);
  });
}
