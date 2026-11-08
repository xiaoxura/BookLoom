import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/ai_providers.dart';
import '../../../core/ai/ai_client.dart';
import '../../../core/ai/ai_configuration.dart';
import '../../../core/ai/ai_endpoint.dart';
import '../../../core/ai/ai_protocol.dart';
import '../../../design/components/app_page.dart';
import '../../../design/theme/app_tokens.dart';
import '../../../design/tokens/app_metrics.dart';
import '../../../l10n/app_localizations.dart';
import '../application/ai_configuration_service.dart';
import 'settings_widgets.dart';

class AiSettingsPage extends ConsumerStatefulWidget {
  const AiSettingsPage({super.key, this.service});

  final AiConfigurationService? service;

  @override
  ConsumerState<AiSettingsPage> createState() => _AiSettingsPageState();
}

class _AiSettingsPageState extends ConsumerState<AiSettingsPage> {
  final _address = TextEditingController();
  final _key = TextEditingController();
  final _model = TextEditingController();

  late final AiConfigurationService _service;
  AiConfiguration? _expected;
  AiEndpointFormat _format = AiEndpointFormat.openAiChatCompletions;
  AiConnectionProof? _proof;
  final Map<AiCredentialCleanupWarning, String> _cleanupWarnings = {};
  AiCancellation? _cancellation;
  bool _enabled = false;
  bool _acknowledgeRemoteHttp = false;
  bool _obscureKey = true;
  bool _loading = true;
  bool _loadFailed = false;
  bool _testing = false;
  bool _working = false;
  String? _feedback;
  int _editEpoch = 0;
  int _loadEpoch = 0;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? ref.read(aiConfigurationServiceProvider);
    _load();
  }

  @override
  void dispose() {
    _loadEpoch++;
    _editEpoch++;
    _cancellation?.cancel();
    _service.invalidateProof();
    _address.dispose();
    _key.dispose();
    _model.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final epoch = ++_loadEpoch;
    setState(() {
      _loading = true;
      _loadFailed = false;
      _feedback = null;
    });
    try {
      final configuration = await _service.load();
      if (!mounted || epoch != _loadEpoch) return;
      final warnings = await _service.pendingCleanupWarnings;
      if (!mounted || epoch != _loadEpoch) return;
      _service.invalidateProof();
      _cancellation?.cancel();
      _editEpoch++;
      _address.text = configuration.address;
      _model.text = configuration.model;
      _key.clear();
      setState(() {
        _expected = configuration;
        _enabled = configuration.enabled;
        _format = configuration.format;
        _acknowledgeRemoteHttp = configuration.acknowledgeRemoteHttp;
        _proof = null;
        _cleanupWarnings
          ..clear()
          ..addEntries(
            warnings.map(
              (warning) => MapEntry(
                warning,
                AppLocalizations.of(context).aiCleanupWarning,
              ),
            ),
          );
        _loading = false;
      });
    } catch (_) {
      if (!mounted || epoch != _loadEpoch) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  void _edited({bool resetHttpConsent = false}) {
    _editEpoch++;
    _cancellation?.cancel();
    _service.invalidateProof();
    setState(() {
      _proof = null;
      _feedback = null;
      if (resetHttpConsent) _acknowledgeRemoteHttp = false;
    });
  }

  AiEndpoint? _previewEndpoint() {
    if (_address.text.trim().isEmpty) return null;
    try {
      return AiEndpoint.normalize(
        _address.text,
        _format,
        acknowledgeRemoteHttp: true,
      );
    } on FormatException {
      return null;
    }
  }

  bool get _requiresRemoteHttpConsent {
    final endpoint = _previewEndpoint();
    return endpoint?.isInsecureRemoteHttp ?? false;
  }

  bool get _needsNewKey {
    final expected = _expected;
    if (expected?.credentialReference == null) return false;
    final endpoint = _previewEndpoint();
    return _format != expected!.format ||
        endpoint == null ||
        endpoint.baseUri.toString() != expected.address;
  }

  AiConfiguration _configuration() => AiConfiguration(
    enabled: _enabled,
    format: _format,
    address: _address.text,
    model: _model.text,
    credentialReference: _expected!.credentialReference,
    acknowledgeRemoteHttp: _acknowledgeRemoteHttp,
  );

  bool get _validForm {
    if (_expected == null || _loadFailed || _working || _testing) return false;
    if (_address.text.isNotEmpty && _previewEndpoint() == null) return false;
    if (_requiresRemoteHttpConsent && !_acknowledgeRemoteHttp) return false;
    if (_key.text.isNotEmpty &&
        (_key.text.trim() != _key.text ||
            _key.text.contains(RegExp(r'[\x00-\x1f\x7f]')))) {
      return false;
    }
    if (_needsNewKey && _key.text.isEmpty) return false;
    try {
      _configuration().canonicalized();
      return true;
    } on FormatException {
      return false;
    }
  }

  String _errorText(AiConfigurationException error, AppLocalizations l10n) {
    switch (error.protocolFailure) {
      case AiProtocolFailure.authentication:
        return l10n.aiAuthenticationFailed;
      case AiProtocolFailure.rateLimited:
        return l10n.aiRateLimited;
      case AiProtocolFailure.responseTooLarge:
        return l10n.aiBudgetExceeded;
      case AiProtocolFailure.invalidRequest:
      case AiProtocolFailure.httpError:
      case AiProtocolFailure.malformedResponse:
      case AiProtocolFailure.refused:
      case AiProtocolFailure.incomplete:
      case AiProtocolFailure.emptyResponse:
        return l10n.aiProtocolFailed;
      case null:
        break;
    }
    switch (error.transportFailure) {
      case AiTransportFailure.cancelled:
        return l10n.aiCancelled;
      case AiTransportFailure.timedOut:
        return l10n.aiTimedOut;
      case AiTransportFailure.redirect:
        return l10n.aiRedirectRejected;
      case AiTransportFailure.requestTooLarge:
      case AiTransportFailure.responseTooLarge:
        return l10n.aiBudgetExceeded;
      case AiTransportFailure.invalidUtf8:
        return l10n.aiProtocolFailed;
      case AiTransportFailure.connection:
      case AiTransportFailure.concurrentRequest:
      case AiTransportFailure.disposed:
        return l10n.aiNetworkFailed;
      case null:
        break;
    }
    return switch (error.failure) {
      AiConfigurationFailure.busy => l10n.aiBusy,
      AiConfigurationFailure.invalidConfiguration =>
        l10n.aiInvalidConfiguration,
      AiConfigurationFailure.missingCredential => l10n.aiMissingCredential,
      AiConfigurationFailure.credentialUnavailable =>
        l10n.aiCredentialUnavailable,
      AiConfigurationFailure.staleConfiguration => l10n.aiStaleConfiguration,
      AiConfigurationFailure.proofRequired => l10n.aiProofRequired,
      AiConfigurationFailure.connectionFailed => l10n.aiConnectionFailed,
      AiConfigurationFailure.cancelled => l10n.aiCancelled,
      AiConfigurationFailure.saveFailed => l10n.aiSaveFailed,
      AiConfigurationFailure.commitUnknown => l10n.aiCommitUnknown,
      AiConfigurationFailure.cleanupFailed => l10n.aiCleanupFailed,
    };
  }

  void _showFailure(Object error) {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _feedback = error is AiConfigurationException
          ? _errorText(error, l10n)
          : l10n.aiSaveFailed;
      if (error is AiConfigurationException && error.cleanupWarning != null) {
        _cleanupWarnings[error.cleanupWarning!] = _errorText(error, l10n);
      }
    });
  }

  Future<void> _testConnection() async {
    if (!_validForm || !_enabled) return;
    final epoch = _editEpoch;
    final cancellation = AiCancellation();
    _cancellation = cancellation;
    setState(() {
      _testing = true;
      _feedback = null;
      _proof = null;
    });
    try {
      final proof = await _service.testConnection(
        configuration: _configuration(),
        expected: _expected!,
        apiKey: _key.text.isEmpty ? null : _key.text,
        cancellation: cancellation,
      );
      if (!mounted || epoch != _editEpoch || cancellation.isCancelled) return;
      setState(() => _proof = proof);
    } catch (error) {
      if (!mounted || epoch != _editEpoch) return;
      _showFailure(error);
    } finally {
      if (mounted) {
        setState(() {
          _testing = false;
          if (identical(_cancellation, cancellation)) _cancellation = null;
        });
      }
    }
  }

  void _cancelTest() {
    _cancellation?.cancel();
    _service.invalidateProof();
    _editEpoch++;
    setState(() {
      _proof = null;
      _feedback = AppLocalizations.of(context).aiCancelled;
    });
  }

  Future<void> _save() async {
    if (!_validForm || _enabled && _proof == null) return;
    setState(() {
      _working = true;
      _feedback = null;
    });
    try {
      final result = await _service.save(
        configuration: _configuration(),
        expected: _expected!,
        apiKey: _key.text.isEmpty ? null : _key.text,
        proof: _proof,
      );
      if (!mounted) return;
      _expected = result.configuration;
      _address.text = result.configuration.address;
      _model.text = result.configuration.model;
      _key.clear();
      _service.invalidateProof();
      setState(() {
        _proof = null;
        if (result.cleanupWarning != null) {
          _cleanupWarnings[result.cleanupWarning!] = AppLocalizations.of(
            context,
          ).aiCleanupWarning;
        }
        _feedback = AppLocalizations.of(context).aiSaved;
      });
    } catch (error) {
      _showFailure(error);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _clear() async {
    if (_working || _testing || _expected == null) return;
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.aiClearTitle),
        content: Text(l10n.aiClearDescription),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(
              MaterialLocalizations.of(dialogContext).cancelButtonLabel,
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.aiClearConfirm),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() {
      _working = true;
      _feedback = null;
    });
    try {
      final result = await _service.clear(expected: _expected!);
      if (!mounted) return;
      _expected = result.configuration;
      _service.invalidateProof();
      _address.clear();
      _model.clear();
      _key.clear();
      setState(() {
        _enabled = false;
        _format = AiEndpointFormat.openAiChatCompletions;
        _acknowledgeRemoteHttp = false;
        _proof = null;
        if (result.cleanupWarning != null) {
          _cleanupWarnings[result.cleanupWarning!] = l10n.aiCleanupWarning;
        }
        _feedback = l10n.aiCleared;
      });
    } catch (error) {
      _showFailure(error);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _retryCleanup() async {
    final warning = _cleanupWarnings.keys.firstOrNull;
    if (_working || warning == null) return;
    setState(() => _working = true);
    try {
      await _service.retryCleanup(warning);
      if (!mounted) return;
      setState(() {
        _cleanupWarnings.remove(warning);
        _feedback = AppLocalizations.of(context).aiCleanupDone;
      });
    } catch (error) {
      _showFailure(error);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = context.colors;
    final endpoint = _previewEndpoint();
    final locked = _loading || _loadFailed || _working;
    final keyHint = _needsNewKey
        ? l10n.aiKeyChangedAddressHint
        : _expected?.credentialReference != null
        ? l10n.aiKeyReuseHint
        : l10n.aiKeyNewHint;

    return AppPage(
      title: l10n.aiSettingsTitle,
      leading: BackButton(onPressed: () => context.pop()),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            l10n.aiSettingsDescription,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.inkSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (_loading) const LinearProgressIndicator(),
          if (_loadFailed) ...<Widget>[
            Text(l10n.aiLoadFailed),
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: Text(l10n.aiReload),
              ),
            ),
          ],
          if (!_loading && !_loadFailed) ...<Widget>[
            SettingsCard(
              children: <Widget>[
                SettingsRow(
                  title: l10n.aiEnabled,
                  description: l10n.aiOfflineNotice,
                  control: Switch(
                    key: const ValueKey('ai-enabled'),
                    value: _enabled,
                    onChanged: locked
                        ? null
                        : (value) {
                            _enabled = value;
                            _edited();
                          },
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            SettingsCard(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      KeyedSubtree(
                        key: const ValueKey('ai-format'),
                        child: DropdownButtonFormField<AiEndpointFormat>(
                          key: ValueKey(_format),
                          initialValue: _format,
                          isExpanded: true,
                          decoration: InputDecoration(labelText: l10n.aiFormat),
                          items: AiEndpointFormat.values
                              .map(
                                (format) => DropdownMenuItem(
                                  value: format,
                                  child: Text(_formatName(format)),
                                ),
                              )
                              .toList(),
                          onChanged: locked
                              ? null
                              : (format) {
                                  if (format == null || format == _format) {
                                    return;
                                  }
                                  _format = format;
                                  _edited(resetHttpConsent: true);
                                },
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      TextField(
                        key: const ValueKey('ai-address'),
                        controller: _address,
                        enabled: !locked,
                        keyboardType: TextInputType.url,
                        inputFormatters: [
                          LengthLimitingTextInputFormatter(2048),
                        ],
                        decoration: InputDecoration(
                          labelText: l10n.aiAddress,
                          hintText: _format == AiEndpointFormat.claudeMessages
                              ? l10n.aiClaudeAddressHint
                              : l10n.aiOpenAiAddressHint,
                        ),
                        onChanged: (_) => _edited(resetHttpConsent: true),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      TextField(
                        key: const ValueKey('ai-api-key'),
                        controller: _key,
                        enabled: !locked,
                        obscureText: _obscureKey,
                        autocorrect: false,
                        enableSuggestions: false,
                        enableIMEPersonalizedLearning: false,
                        autofillHints: const <String>[],
                        inputFormatters: [
                          LengthLimitingTextInputFormatter(4096),
                        ],
                        decoration: InputDecoration(
                          labelText: l10n.aiApiKey,
                          helperText: keyHint,
                          suffixIcon: IconButton(
                            tooltip: _obscureKey
                                ? l10n.aiShowKey
                                : l10n.aiHideKey,
                            onPressed: () =>
                                setState(() => _obscureKey = !_obscureKey),
                            icon: Icon(
                              _obscureKey
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                        onChanged: (_) => _edited(),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      TextField(
                        key: const ValueKey('ai-model'),
                        controller: _model,
                        enabled: !locked,
                        inputFormatters: [
                          LengthLimitingTextInputFormatter(200),
                        ],
                        decoration: InputDecoration(
                          labelText: l10n.aiModel,
                          hintText: l10n.aiModelHint,
                        ),
                        onChanged: (_) => _edited(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            SettingsCard(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _previewLine(
                        l10n.aiNormalizedAddress,
                        endpoint?.baseUri.toString(),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _previewLine(
                        l10n.aiRequestAddress,
                        endpoint?.requestUri.toString(),
                      ),
                      if (_address.text.trim().isNotEmpty &&
                          endpoint == null) ...<Widget>[
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          l10n.aiEndpointInvalid,
                          style: TextStyle(color: colors.danger),
                        ),
                      ],
                      if (_requiresRemoteHttpConsent) ...<Widget>[
                        const SizedBox(height: AppSpacing.md),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          value: _acknowledgeRemoteHttp,
                          onChanged: locked
                              ? null
                              : (value) {
                                  _acknowledgeRemoteHttp = value ?? false;
                                  _edited();
                                },
                          title: Text(l10n.aiRemoteHttpConsent),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              l10n.aiTestDisclosure,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.inkSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            if (_testing) ...<Widget>[
              const LinearProgressIndicator(),
              const SizedBox(height: AppSpacing.sm),
              Text(l10n.aiTesting),
            ],
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: <Widget>[
                if (_testing)
                  OutlinedButton.icon(
                    onPressed: _cancellation?.isCancelled == true
                        ? null
                        : _cancelTest,
                    icon: const Icon(Icons.close),
                    label: Text(l10n.aiCancelTest),
                  )
                else
                  OutlinedButton.icon(
                    key: const ValueKey('ai-test-connection'),
                    onPressed: _enabled && _validForm ? _testConnection : null,
                    icon: const Icon(Icons.wifi_tethering_outlined),
                    label: Text(l10n.aiTestConnection),
                  ),
                FilledButton.icon(
                  key: const ValueKey('ai-save'),
                  onPressed: _validForm && (!_enabled || _proof != null)
                      ? _save
                      : null,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(l10n.aiSave),
                ),
                TextButton.icon(
                  key: const ValueKey('ai-clear'),
                  onPressed: _working || _testing ? null : _clear,
                  icon: const Icon(Icons.delete_outline),
                  label: Text(l10n.aiClear),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              _proof == null ? l10n.aiNotTested : l10n.aiTestPassed,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.inkSecondary,
              ),
            ),
            if (_feedback != null) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              Text(_feedback!, style: theme.textTheme.bodySmall),
            ],
            if (_cleanupWarnings.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              Text(
                _cleanupWarnings.values.first,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.warning,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _working || _testing ? null : _retryCleanup,
                  icon: const Icon(Icons.refresh),
                  label: Text(l10n.aiRetryCleanup),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
          ],
        ],
      ),
    );
  }

  Widget _previewLine(String label, String? address) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Text(label, style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: AppSpacing.xs),
      Text(
        address ?? AppLocalizations.of(context).aiEndpointInvalid,
        softWrap: true,
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: context.colors.inkSecondary),
      ),
    ],
  );

  String _formatName(AiEndpointFormat format) => switch (format) {
    AiEndpointFormat.openAiChatCompletions => 'OpenAI Chat Completions',
    AiEndpointFormat.openAiResponses => 'OpenAI Responses',
    AiEndpointFormat.claudeMessages => 'Claude Messages',
  };
}
