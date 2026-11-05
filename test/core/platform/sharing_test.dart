import 'dart:io';

import 'package:bookloom/core/platform/sharing.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Android bridge receives only the prepared path and safe metadata',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'bookloom-share-',
      );
      const channel = MethodChannel('bookloom-share-test');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final prepared = File(p.join(directory.path, 'book.epub'));
      try {
        await prepared.writeAsString('completed output');
        messenger.setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'sharePreparedFile');
          expect(call.arguments, {
            'path': prepared.absolute.path,
            'fileName': 'book.epub',
            'mimeType': 'application/epub+zip',
          });
          return 'opened';
        });

        final outcome =
            await NativeSharingService(
              channel: channel,
              isAndroid: () => true,
            ).sharePreparedFile(
              prepared,
              suggestedName: '../book.epub',
              mimeType: 'application/epub+zip',
            );
        expect(outcome, isA<SharePanelOpened>());
        expect(await prepared.readAsString(), 'completed output');
      } finally {
        messenger.setMockMethodCallHandler(channel, null);
        await directory.delete(recursive: true);
      }
    },
  );

  test('native cancellation remains distinct from opening the panel', () async {
    final directory = await Directory.systemTemp.createTemp('bookloom-share-');
    const channel = MethodChannel('bookloom-share-cancel-test');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final prepared = File(p.join(directory.path, 'book.txt'));
    try {
      await prepared.writeAsString('ready');
      messenger.setMockMethodCallHandler(channel, (call) async => 'cancelled');
      final outcome =
          await NativeSharingService(
            channel: channel,
            isAndroid: () => true,
          ).sharePreparedFile(
            prepared,
            suggestedName: 'book.txt',
            mimeType: 'text/plain',
          );
      expect(outcome, isA<ShareCancelled>());
    } finally {
      messenger.setMockMethodCallHandler(channel, null);
      await directory.delete(recursive: true);
    }
  });

  test('desktop, missing file and platform errors report failure', () async {
    const channel = MethodChannel('bookloom-share-failure-test');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final unsupported = NativeSharingService(
      channel: channel,
      isAndroid: () => false,
    );
    expect(unsupported.isSupported, isFalse);
    expect(
      await unsupported.sharePreparedFile(
        File('/not-a-book.epub'),
        suggestedName: 'book.epub',
        mimeType: 'application/epub+zip',
      ),
      isA<ShareFailed>(),
    );

    final android = NativeSharingService(
      channel: channel,
      isAndroid: () => true,
    );
    expect(
      await android.sharePreparedFile(
        File('/not-a-book.epub'),
        suggestedName: 'book.epub',
        mimeType: 'application/epub+zip',
      ),
      isA<ShareFailed>(),
    );

    final directory = await Directory.systemTemp.createTemp('bookloom-share-');
    final prepared = File(p.join(directory.path, 'book.epub'));
    try {
      await prepared.writeAsString('ready');
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => throw PlatformException(code: 'prepare_failed'),
      );
      final outcome = await android.sharePreparedFile(
        prepared,
        suggestedName: 'book.epub',
        mimeType: 'application/epub+zip',
      );
      expect(outcome, isA<ShareFailed>());
    } finally {
      messenger.setMockMethodCallHandler(channel, null);
      await directory.delete(recursive: true);
    }
  });
}
