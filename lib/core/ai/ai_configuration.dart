import 'package:bookloom/core/ai/ai_endpoint.dart';

abstract interface class AiCredentialStore {
  Future<String?> read(String reference);
  Future<void> write(String reference, String value);
  Future<void> delete(String reference);
}

abstract interface class AiConfigurationStore {
  /// Serializes credential mutations across services sharing one database.
  Future<T> withCredentialMutation<T>(Future<T> Function() action);

  Future<AiConfiguration> read();

  Future<List<String>> readPendingCleanup();
  Future<void> addPendingCleanup(String reference);
  Future<void> removePendingCleanup(String reference);

  /// Atomically switches the current value, queues the replaced credential,
  /// and removes the new current credential from the cleanup queue.
  Future<bool> writeIfCurrent({
    required AiConfiguration expected,
    required AiConfiguration configuration,
  });
}

final class AiConfiguration {
  const AiConfiguration({
    this.enabled = false,
    this.format = AiEndpointFormat.openAiChatCompletions,
    this.address = '',
    this.model = '',
    this.credentialReference,
    this.acknowledgeRemoteHttp = false,
  });

  final bool enabled;
  final AiEndpointFormat format;
  final String address;
  final String model;
  final String? credentialReference;
  final bool acknowledgeRemoteHttp;

  AiConfiguration canonicalized() {
    if (address.length > 2048 ||
        model.length > 200 ||
        model.contains(RegExp(r'[\x00-\x1f\x7f]')) ||
        (credentialReference != null &&
            (credentialReference!.isEmpty ||
                credentialReference!.length > 128 ||
                credentialReference!.contains(RegExp(r'[^a-zA-Z0-9_-]'))))) {
      throw const FormatException('AI 配置字段无效。');
    }
    final normalizedModel = model.trim();
    final normalizedAddress = address.trim();
    if (enabled && (normalizedAddress.isEmpty || normalizedModel.isEmpty)) {
      throw const FormatException('启用 AI 需要地址和模型。');
    }
    final endpoint = normalizedAddress.isEmpty
        ? null
        : AiEndpoint.normalize(
            normalizedAddress,
            format,
            acknowledgeRemoteHttp: acknowledgeRemoteHttp,
          );
    return AiConfiguration(
      enabled: enabled,
      format: format,
      address: endpoint?.baseUri.toString() ?? '',
      model: normalizedModel,
      credentialReference: credentialReference,
      acknowledgeRemoteHttp:
          endpoint?.isInsecureRemoteHttp == true && acknowledgeRemoteHttp,
    );
  }

  AiEndpoint get endpoint => AiEndpoint.normalize(
    address,
    format,
    acknowledgeRemoteHttp: acknowledgeRemoteHttp,
  );

  AiConfiguration withCredentialReference(String? reference) => AiConfiguration(
    enabled: enabled,
    format: format,
    address: address,
    model: model,
    credentialReference: reference,
    acknowledgeRemoteHttp: acknowledgeRemoteHttp,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'enabled': enabled,
    'format': format.name,
    'address': address,
    'model': model,
    'credentialReference': credentialReference,
    'acknowledgeRemoteHttp': acknowledgeRemoteHttp,
  };

  static AiConfiguration fromJson(Map<String, Object?> json) {
    final enabled = json['enabled'];
    final format = json['format'];
    final address = json['address'];
    final model = json['model'];
    final reference = json['credentialReference'];
    final acknowledgeRemoteHttp = json['acknowledgeRemoteHttp'];
    if (enabled is! bool ||
        format is! String ||
        address is! String ||
        model is! String ||
        (reference != null && reference is! String) ||
        acknowledgeRemoteHttp is! bool) {
      throw const FormatException('AI 配置数据无效。');
    }
    final selectedFormat = AiEndpointFormat.values.where(
      (value) => value.name == format,
    );
    if (selectedFormat.isEmpty) {
      throw const FormatException('AI 配置格式无效。');
    }
    return AiConfiguration(
      enabled: enabled,
      format: selectedFormat.single,
      address: address,
      model: model,
      credentialReference: reference as String?,
      acknowledgeRemoteHttp: acknowledgeRemoteHttp,
    ).canonicalized();
  }

  @override
  bool operator ==(Object other) =>
      other is AiConfiguration &&
      enabled == other.enabled &&
      format == other.format &&
      address == other.address &&
      model == other.model &&
      credentialReference == other.credentialReference &&
      acknowledgeRemoteHttp == other.acknowledgeRemoteHttp;

  @override
  int get hashCode => Object.hash(
    enabled,
    format,
    address,
    model,
    credentialReference,
    acknowledgeRemoteHttp,
  );
}
