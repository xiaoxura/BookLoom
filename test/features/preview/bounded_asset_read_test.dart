import 'dart:io';

import 'package:bookloom/features/preview/bounded_asset_read.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stored asset reads enforce the byte budget', () async {
    final directory = await Directory.systemTemp.createTemp(
      'bookloom-bounded-asset-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/asset.bin');
    await file.writeAsBytes([1, 2, 3, 4]);

    expect(await readBoundedAssetFile(file, 4), [1, 2, 3, 4]);
    await expectLater(readBoundedAssetFile(file, 3), throwsFormatException);
  });
}
