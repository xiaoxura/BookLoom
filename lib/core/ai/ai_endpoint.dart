/// The wire format selected by the user, independent of the API provider.
enum AiEndpointFormat { openAiChatCompletions, openAiResponses, claudeMessages }

/// A locally validated base address and the request address for one format.
final class AiEndpoint {
  const AiEndpoint._({
    required this.format,
    required this.baseUri,
    required this.requestUri,
    required this.isInsecureRemoteHttp,
  });

  final AiEndpointFormat format;
  final Uri baseUri;
  final Uri requestUri;
  final bool isInsecureRemoteHttp;

  static AiEndpoint normalize(
    String input,
    AiEndpointFormat format, {
    bool acknowledgeRemoteHttp = false,
  }) {
    final source = input.trim();
    if (source.contains(RegExp(r'[\s\\\x00-\x1f\x7f]')) ||
        source.contains('?') ||
        source.contains('#')) {
      throw const FormatException('API 地址不能包含空白、反斜杠、查询参数或 fragment。');
    }

    final schemeEnd = source.indexOf('://');
    if (schemeEnd < 0) {
      throw const FormatException('API 地址需要明确的 http:// 或 https:// 协议。');
    }
    final authorityStart = schemeEnd + 3;
    final pathStart = source.indexOf('/', authorityStart);
    final authority = source.substring(
      authorityStart,
      pathStart < 0 ? source.length : pathStart,
    );
    if (authority.contains('@') || authority.contains('%')) {
      throw const FormatException('API 地址不能包含凭据或编码后的主机。');
    }
    if (authority.endsWith(':')) {
      throw const FormatException('API 地址端口无效。');
    }

    final rawPath = pathStart < 0 ? '' : source.substring(pathStart);
    final segments = rawPath.isEmpty
        ? <String>[]
        : rawPath.split('/').skip(1).toList();
    while (segments.isNotEmpty && segments.last.isEmpty) {
      segments.removeLast();
    }
    for (final segment in segments) {
      if (segment.isEmpty || segment == '.' || segment == '..') {
        throw const FormatException('API 地址路径不能包含空段或路径穿越。');
      }
      _validateEncoding(segment);
      if (segment != 'v1' && _versionLike.hasMatch(segment)) {
        throw const FormatException('API 地址包含歧义版本路径，请核对路径拼接约定。');
      }
    }

    late final Uri uri;
    try {
      uri = Uri.parse(source);
    } on FormatException {
      throw const FormatException('API 地址格式无效。');
    }
    if ((uri.scheme != 'http' && uri.scheme != 'https') ||
        !uri.hasAuthority ||
        uri.host.isEmpty) {
      throw const FormatException('API 地址需要有效的 HTTP(S) 主机。');
    }
    if (uri.hasPort && (uri.port < 1 || uri.port > 65535)) {
      throw const FormatException('API 地址端口无效。');
    }

    final insecureRemoteHttp =
        uri.scheme == 'http' &&
        uri.host != 'localhost' &&
        uri.host != '127.0.0.1' &&
        uri.host != '::1';
    if (insecureRemoteHttp && !acknowledgeRemoteHttp) {
      throw const FormatException('远程 HTTP 地址需要显式确认明文传输风险。');
    }

    final endpoint = _knownEndpoint(segments);
    if (endpoint != null) {
      if (endpoint != format) {
        throw const FormatException('地址与所选格式不一致，请检查地址或格式。');
      }
      segments.removeRange(
        segments.length - _endpointSuffix(format).length,
        segments.length,
      );
    }
    while (segments.isNotEmpty && segments.last == 'v1') {
      segments.removeLast();
    }

    final baseSegments = <String>[
      ...segments,
      if (format != AiEndpointFormat.claudeMessages) 'v1',
    ];
    final requestSegments = <String>[
      ...baseSegments,
      if (format == AiEndpointFormat.claudeMessages) 'v1',
      ..._endpointSuffix(format),
    ];
    final origin = uri.replace(path: '').toString();
    return AiEndpoint._(
      format: format,
      baseUri: Uri.parse(
        baseSegments.isEmpty ? origin : '$origin/${baseSegments.join('/')}',
      ),
      requestUri: Uri.parse('$origin/${requestSegments.join('/')}'),
      isInsecureRemoteHttp: insecureRemoteHttp,
    );
  }

  static final RegExp _versionLike = RegExp(r'^[vV][0-9]');

  static AiEndpointFormat? _knownEndpoint(List<String> segments) {
    for (final format in AiEndpointFormat.values) {
      final suffix = _endpointSuffix(format);
      if (segments.length >= suffix.length && _endsWith(segments, suffix)) {
        return format;
      }
    }
    return null;
  }

  static bool _endsWith(List<String> segments, List<String> suffix) {
    final offset = segments.length - suffix.length;
    for (var index = 0; index < suffix.length; index++) {
      if (segments[offset + index] != suffix[index]) return false;
    }
    return true;
  }

  static List<String> _endpointSuffix(AiEndpointFormat format) =>
      switch (format) {
        AiEndpointFormat.openAiChatCompletions => const ['chat', 'completions'],
        AiEndpointFormat.openAiResponses => const ['responses'],
        AiEndpointFormat.claudeMessages => const ['messages'],
      };

  static void _validateEncoding(String segment) {
    for (var index = 0; index < segment.length; index++) {
      if (segment.codeUnitAt(index) != 0x25) continue;
      if (index + 2 >= segment.length) {
        throw const FormatException('API 地址路径包含无效或歧义编码。');
      }
      final byte = int.tryParse(
        segment.substring(index + 1, index + 3),
        radix: 16,
      );
      if (byte == null ||
          byte <= 0x1f ||
          byte == 0x7f ||
          byte == 0x2f ||
          byte == 0x5c ||
          byte == 0x25 ||
          byte == 0x3f ||
          byte == 0x23 ||
          _isUnreserved(byte)) {
        throw const FormatException('API 地址路径包含无效或歧义编码。');
      }
      index += 2;
    }
    try {
      for (final codePoint in Uri.decodeComponent(segment).runes) {
        if (codePoint <= 0x1f ||
            (codePoint >= 0x7f && codePoint <= 0x9f) ||
            codePoint == 0x5c) {
          throw const FormatException('API 地址路径包含控制字符或反斜杠。');
        }
      }
    } on FormatException {
      throw const FormatException('API 地址路径包含无效或歧义编码。');
    }
  }

  static bool _isUnreserved(int byte) =>
      (byte >= 0x41 && byte <= 0x5a) ||
      (byte >= 0x61 && byte <= 0x7a) ||
      (byte >= 0x30 && byte <= 0x39) ||
      byte == 0x2d ||
      byte == 0x2e ||
      byte == 0x5f ||
      byte == 0x7e;
}
