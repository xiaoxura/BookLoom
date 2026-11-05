import 'package:bookloom/core/conversion/opencc_converter.dart';
import 'package:flutter/services.dart';

/// Bundled resources; conversion never downloads dictionaries at first use.
Future<Map<String, String>> loadOfflineDictionaries() async => <String, String>{
  for (final name in OpenCcConverter.requiredDictionaryFiles)
    name: await rootBundle.loadString('${OpenCcConverter.assetPrefix}$name'),
};
