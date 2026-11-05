import 'dart:convert';

import 'package:xml/xml.dart';
import 'package:xml/xml_events.dart';

import '../errors/app_failure.dart';
import 'input_limits.dart';

/// Parses one already bounded XML resource. DTD and entity declarations are
/// rejected before the XML package can process them.
XmlDocument safeXml(String source, {required InputLimits limits}) {
  if (source.length > limits.maxXmlContentCharacters ||
      utf8.encode(source).length > limits.maxXmlBytes) {
    throw const ImportFailure('XML 内容超过允许大小。');
  }
  if (RegExp(
    r'<!\s*(?:DOCTYPE|ENTITY)\b',
    caseSensitive: false,
  ).hasMatch(source)) {
    throw const ImportFailure('XML 不允许 DTD 或实体声明。');
  }

  var depth = 0;
  var contentCharacters = 0;
  try {
    for (final event in parseEvents(
      source,
      validateDocument: true,
      validateNesting: true,
      validateNamespace: true,
    )) {
      if (event is XmlDoctypeEvent) {
        throw const ImportFailure('XML 不允许 DTD 或实体声明。');
      }
      if (event is XmlStartElementEvent) {
        depth++;
        if (depth > limits.maxXmlDepth) {
          throw const ImportFailure('XML 嵌套层级超过允许范围。');
        }
        for (final attribute in event.attributes) {
          contentCharacters += attribute.value.length;
        }
        if (event.isSelfClosing) depth--;
      } else if (event is XmlEndElementEvent) {
        depth--;
      } else if (event is XmlTextEvent) {
        contentCharacters += event.value.length;
      } else if (event is XmlCDATAEvent) {
        contentCharacters += event.value.length;
      }
      if (contentCharacters > limits.maxXmlContentCharacters) {
        throw const ImportFailure('XML 文本内容超过允许大小。');
      }
    }
    return XmlDocument.parse(source);
  } on ImportFailure {
    rethrow;
  } on XmlException catch (error, stackTrace) {
    throw ImportFailure('XML 格式无效。', cause: error, stackTrace: stackTrace);
  }
}
