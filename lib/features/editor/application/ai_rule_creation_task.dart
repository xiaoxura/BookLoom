import 'package:bookloom/core/ai/ai_analysis_result.dart';
import 'package:bookloom/core/ai/ai_client.dart';
import 'package:bookloom/core/ai/ai_configuration.dart';
import 'package:bookloom/core/ai/ai_context.dart';
import 'package:bookloom/core/ai/ai_protocol.dart';
import 'package:bookloom/core/ai/ai_rule_creation_prompt.dart';
import 'package:bookloom/core/editing/proofreading_rule.dart';
import 'package:bookloom/core/errors/app_failure.dart';
import 'package:bookloom/core/model/block.dart';
import 'package:bookloom/core/platform/background_jobs.dart';
import 'package:bookloom/features/editor/application/editor_session.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

enum AiRuleCreationPhase {
  idle,
  preparing,
  awaitingConsent,
  running,
  completed,
  cancelled,
  stale,
  failed,
}

final class AiRuleSelection {
  const AiRuleSelection({
    required this.chapterId,
    required this.blockId,
    required this.startUtf16,
    required this.endUtf16,
    required this.original,
  });

  final String chapterId;
  final String blockId;
  final int startUtf16;
  final int endUtf16;
  final String original;
}

final class AiRuleCreationConsent {
  AiRuleCreationConsent._({
    required this.configuration,
    required this.chunk,
    required this.request,
    required this.intent,
    required List<ProofreadingRule> relatedRules,
  }) : relatedRules = List<ProofreadingRule>.unmodifiable(relatedRules);

  final AiConfiguration configuration;
  final AiContextChunk chunk;
  final AiRuleRequest request;
  final String intent;
  final List<ProofreadingRule> relatedRules;
}

class AiRuleCreationTask extends ChangeNotifier {
  factory AiRuleCreationTask({
    required EditorSession session,
    required Future<AiConfiguration> Function() loadConfiguration,
    required AiCredentialStore credentials,
    required AiTextClient Function() createClient,
    Future<List<ProofreadingRule>> Function(String bookId)? loadRelatedRules,
    BackgroundJobs? jobs,
  }) => AiRuleCreationTask._(
    session,
    loadConfiguration,
    credentials,
    createClient,
    loadRelatedRules,
    jobs,
  );

  AiRuleCreationTask._(
    this._session,
    this._loadConfiguration,
    this._credentials,
    this._createClient,
    this._loadRelatedRules,
    BackgroundJobs? jobs,
  ) : _jobs = jobs ?? BackgroundJobs(),
      _ownsJobs = jobs == null {
    _session.addListener(_sessionChanged);
  }

  final EditorSession _session;
  final Future<AiConfiguration> Function() _loadConfiguration;
  final AiCredentialStore _credentials;
  final AiTextClient Function() _createClient;
  final Future<List<ProofreadingRule>> Function(String bookId)?
  _loadRelatedRules;
  final BackgroundJobs _jobs;
  final bool _ownsJobs;
  static const Uuid _uuid = Uuid();

  AiRuleCreationPhase _phase = AiRuleCreationPhase.idle;
  AiRuleCreationConsent? _consent;
  List<RuleProposal> _proposals = const [];
  AppFailure? _failure;
  AiCancellation? _cancellation;
  AiTextClient? _client;
  String? _bookId;
  String? _sessionId;
  int? _revision;
  bool _working = false;
  bool _workerActive = false;
  bool _disposed = false;

  AiRuleCreationPhase get phase => _phase;
  AiRuleCreationConsent? get consent => _consent;
  List<RuleProposal> get proposals => _proposals;
  AppFailure? get failure => _failure;
  bool get isBusy => _working;
  bool get canUseProposals =>
      !_working &&
      _phase == AiRuleCreationPhase.completed &&
      _proposals.isNotEmpty &&
      _current;

  bool get _current =>
      !_disposed &&
      _sessionId != null &&
      _session.sessionId == _sessionId &&
      _session.book?.id == _bookId &&
      _session.saveSeq == _revision;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _check() {
    if (!_current) {
      throw const ValidationFailure('书稿已变化，请重新选择规则样例。');
    }
    _cancellation?.throwIfCancelled();
  }

  void _sessionChanged() {
    if (_disposed ||
        _sessionId == null ||
        _current ||
        _phase == AiRuleCreationPhase.idle ||
        _phase == AiRuleCreationPhase.stale) {
      return;
    }
    _cancellation?.cancel();
    if (_workerActive) _jobs.cancelActive();
    _consent = null;
    _proposals = const [];
    _failure = null;
    _phase = AiRuleCreationPhase.stale;
    _notify();
  }

  Future<void> prepare({
    required AiRuleSelection selection,
    required ProofreadingRuleKind kind,
    required String intent,
    required List<String> negativeExamples,
    List<ProofreadingRule> relatedRules = const [],
  }) async {
    if (_disposed || _working) return;
    _working = true;
    _phase = AiRuleCreationPhase.preparing;
    _failure = null;
    _consent = null;
    _proposals = const [];
    _cancellation = AiCancellation();
    _bookId = _session.book?.id;
    _sessionId = _session.sessionId;
    _revision = _session.saveSeq;
    _notify();
    try {
      _check();
      var selectedRelatedRules = List<ProofreadingRule>.unmodifiable(
        relatedRules,
      );
      final book = _session.book!;
      final chapter = _session.activeChapter;
      if (chapter == null ||
          chapter.id != selection.chapterId ||
          chapter.bookId != book.id ||
          chapter.isVolume) {
        throw const ValidationFailure('所选章节正文未加载，请重新选择。');
      }
      final blocks = chapter.blocks.where(
        (block) => block.id == selection.blockId,
      );
      if (blocks.length != 1 || blocks.single is! TextBlock) {
        throw const ValidationFailure('所选正文块无效，请重新选择。');
      }
      final source = (blocks.single as TextBlock).text;
      final start = selection.startUtf16;
      final end = selection.endUtf16;
      if (start < 0 ||
          end <= start ||
          end > source.length ||
          !_boundary(source, start) ||
          !_boundary(source, end) ||
          !_validSingleLine(selection.original, 2048) ||
          source.substring(start, end) != selection.original) {
        throw const ValidationFailure('所选文字已变化或不是有效的单行样例。');
      }
      if (!_validText(intent, 1024) ||
          intent.trim().isEmpty ||
          negativeExamples.length > 8 ||
          selectedRelatedRules.length > 16 ||
          negativeExamples.any((sample) => !_validSingleLine(sample, 2048)) ||
          negativeExamples.contains(selection.original) ||
          selectedRelatedRules.any((rule) => !rule.appliesToBook(book.id))) {
        throw const ValidationFailure('规则意图、反例或相关规则无效。');
      }
      final request = AiRuleRequest(
        kind: kind,
        positiveExamples: [selection.original],
        negativeExamples: negativeExamples,
      );
      var beforeStart = (start - 512).clamp(0, source.length);
      if (!_boundary(source, beforeStart)) beforeStart++;
      var afterEnd = (end + 512).clamp(0, source.length);
      if (!_boundary(source, afterEnd)) afterEnd--;
      var titleEnd = chapter.title.length.clamp(0, 512);
      if (!_boundary(chapter.title, titleEnd)) titleEnd--;
      final title = chapter.title.substring(0, titleEnd);
      final before = source.substring(beforeStart, start);
      final after = source.substring(end, afterEnd);
      if (!_validText(title, 512) ||
          !_validText(before, 512) ||
          !_validText(after, 512)) {
        throw const ValidationFailure('上下文包含无效字符。');
      }
      final selectedBlock = AiContextBlock(
        chapterId: chapter.id,
        chapterTitle: title,
        blockId: selection.blockId,
        text: source,
      );
      final chunk = AiContextChunk(
        bookId: book.id,
        sessionId: _sessionId!,
        sessionRevision: _revision!,
        index: 0,
        slices: [
          AiContextSlice(
            block: selectedBlock,
            startUtf16: start,
            endUtf16: end,
            before: before,
            text: selection.original,
            after: after,
          ),
        ],
      );
      if (selectedRelatedRules.isEmpty && _loadRelatedRules != null) {
        final loaded = await _loadRelatedRules(book.id);
        _check();
        final eligible =
            loaded
                .where(
                  (rule) =>
                      rule.enabled &&
                      rule.kind == kind &&
                      rule.appliesToBook(book.id),
                )
                .toList()
              ..sort((left, right) {
                final byPriority = right.priority.compareTo(left.priority);
                return byPriority != 0
                    ? byPriority
                    : left.id.compareTo(right.id);
              });
        selectedRelatedRules = List<ProofreadingRule>.unmodifiable(
          eligible.take(16),
        );
      }
      final configuration = (await _loadConfiguration()).canonicalized();
      _check();
      _validateConfiguration(configuration);
      AiRuleCreationPrompt.userContext(
        chunk: chunk,
        request: request,
        intent: intent,
        relatedRules: selectedRelatedRules,
      );
      _consent = AiRuleCreationConsent._(
        configuration: configuration,
        chunk: chunk,
        request: request,
        intent: intent,
        relatedRules: selectedRelatedRules,
      );
      _phase = AiRuleCreationPhase.awaitingConsent;
    } catch (error) {
      _fail(error);
    } finally {
      _working = false;
      _notify();
    }
  }

  Future<void> run(AiRuleCreationConsent consent) async {
    if (_disposed || _working) return;
    if (!identical(consent, _consent) ||
        _phase != AiRuleCreationPhase.awaitingConsent) {
      _failure = const ValidationFailure('规则生成确认已失效，请重新准备。');
      _notify();
      return;
    }
    _working = true;
    _phase = AiRuleCreationPhase.running;
    _failure = null;
    _cancellation = AiCancellation();
    _notify();
    try {
      _check();
      await _checkConfiguration(consent.configuration);
      final key = await _credentials.read(
        consent.configuration.credentialReference!,
      );
      _check();
      if (key == null || key.isEmpty) {
        throw const ValidationFailure('未找到 AI 密钥，请重新配置并测试连接。');
      }
      await _checkConfiguration(consent.configuration);
      final client = _createClient();
      _client = client;
      final response = await client.generate(
        endpoint: consent.configuration.endpoint,
        apiKey: key,
        model: consent.configuration.model,
        systemPrompt: AiRuleCreationPrompt.system(consent.request),
        userContext: AiRuleCreationPrompt.userContext(
          chunk: consent.chunk,
          request: consent.request,
          intent: consent.intent,
          relatedRules: consent.relatedRules,
        ),
        outputTokens: 4096,
        cancellation: _cancellation!,
      );
      _check();
      await _checkConfiguration(consent.configuration);
      final work = _jobs.run<_RuleDecodeInput, List<RuleProposal>>(
        _RuleDecodeInput(
          response,
          consent.chunk,
          consent.request,
          'rule-${_uuid.v4()}',
        ),
        _decodeRules,
        revision: _revision!,
      );
      _workerActive = true;
      final proposals = await work;
      _workerActive = false;
      _check();
      await _checkConfiguration(consent.configuration);
      _proposals = List<RuleProposal>.unmodifiable(proposals);
      _phase = AiRuleCreationPhase.completed;
    } catch (error) {
      _fail(error);
    } finally {
      _client?.dispose();
      _client = null;
      _workerActive = false;
      _working = false;
      _notify();
    }
  }

  Future<void> _checkConfiguration(AiConfiguration expected) async {
    final current = (await _loadConfiguration()).canonicalized();
    _check();
    if (current != expected) {
      throw const ValidationFailure('AI 服务配置已改变，请重新确认服务与样例。');
    }
    _validateConfiguration(current);
  }

  void _validateConfiguration(AiConfiguration configuration) {
    if (!configuration.enabled) {
      throw const ValidationFailure('AI 尚未启用，请先到设置配置并测试服务。');
    }
    if (configuration.credentialReference == null) {
      throw const ValidationFailure('AI 密钥未配置，请先到设置测试并保存。');
    }
  }

  void _fail(Object error) {
    _consent = null;
    _proposals = const [];
    if (_disposed) return;
    if (!_current) {
      _phase = AiRuleCreationPhase.stale;
      _failure = const ValidationFailure('书稿会话已变化，规则候选已失效。');
    } else if (_cancellation?.isCancelled == true ||
        error is TaskCancelled ||
        error is AiTransportException &&
            error.failure == AiTransportFailure.cancelled) {
      _phase = AiRuleCreationPhase.cancelled;
      _failure = null;
    } else {
      _phase = AiRuleCreationPhase.failed;
      _failure = switch (error) {
        AiProtocolException() => ValidationFailure(switch (error.failure) {
          AiProtocolFailure.authentication => 'AI 鉴权失败，请检查密钥与服务地址。',
          AiProtocolFailure.rateLimited => 'AI 服务限流，请稍后手动重试；重试可能再次计费。',
          AiProtocolFailure.refused => 'AI 服务拒绝了本次规则请求。',
          AiProtocolFailure.incomplete => 'AI 返回结果被截断，请缩小范围。',
          _ => 'AI 协议或模型返回不兼容，请检查配置。',
        }),
        AiTransportException() => ValidationFailure(switch (error.failure) {
          AiTransportFailure.timedOut => 'AI 请求超时；重试可能再次计费。',
          AiTransportFailure.responseTooLarge => 'AI 响应超过预算，请缩小范围。',
          AiTransportFailure.requestTooLarge => 'AI 请求超过预算，请缩小范围。',
          _ => 'AI 连接失败，未自动重试，请检查地址与网络。',
        }),
        ValidationFailure() => error,
        _ => const ValidationFailure('AI 规则生成失败，请检查服务设置或缩小范围。'),
      };
    }
  }

  void cancel() {
    if (_disposed) return;
    _cancellation?.cancel();
    if (_workerActive) _jobs.cancelActive();
    _consent = null;
    _proposals = const [];
    _failure = null;
    _phase = AiRuleCreationPhase.cancelled;
    _notify();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _cancellation?.cancel();
    if (_workerActive) _jobs.cancelActive();
    _client?.dispose();
    _client = null;
    if (_ownsJobs) _jobs.dispose();
    _session.removeListener(_sessionChanged);
    _disposed = true;
    _consent = null;
    _proposals = const [];
    super.dispose();
  }
}

final class _RuleDecodeInput {
  const _RuleDecodeInput(
    this.response,
    this.chunk,
    this.request,
    this.responseId,
  );

  final String response;
  final AiContextChunk chunk;
  final AiRuleRequest request;
  final String responseId;
}

List<RuleProposal> _decodeRules(
  _RuleDecodeInput input,
  void Function(double, String) progress,
) {
  final result = AiAnalysisResultDecoder.decode(
    input.response,
    context: input.chunk,
    responseId: input.responseId,
    ruleRequest: input.request,
  );
  if (result.findings.isNotEmpty ||
      result.textChanges.proposals.isNotEmpty ||
      result.chapterSplits.isNotEmpty) {
    throw const ValidationFailure('AI 返回结果超出规则生成范围，未修改书稿。');
  }
  return [
    for (final proposal in result.ruleProposals)
      _mergeRequiredExamples(proposal, input.chunk.bookId),
  ];
}

RuleProposal _mergeRequiredExamples(RuleProposal proposal, String bookId) {
  final source = proposal.rule;
  final positives = <String>{
    ...proposal.requiredPositiveExamples,
    ...source.positiveExamples,
  }.toList();
  final negatives = <String>{
    ...proposal.requiredNegativeExamples,
    ...source.negativeExamples,
  }.toList();
  final rule = ProofreadingRule.create(
    id: source.id,
    name: source.name,
    kind: source.kind,
    source: ProofreadingRuleSource.ai,
    bookId: bookId,
    target: source.target,
    mode: source.mode,
    pattern: source.pattern,
    titleCaptureGroup: source.titleCaptureGroup,
    numberCaptureGroup: source.numberCaptureGroup,
    headingLevel: source.headingLevel,
    caseSensitive: source.caseSensitive,
    action: source.action,
    positiveExamples: positives,
    negativeExamples: negatives,
    scope: ProofreadingRuleScope.book,
    enabled: true,
    priority: source.priority,
  );
  return RuleProposal(
    proposalId: proposal.proposalId,
    rule: rule,
    reason: proposal.reason,
    requiredPositiveExamples: proposal.requiredPositiveExamples,
    requiredNegativeExamples: proposal.requiredNegativeExamples,
  );
}

bool _validSingleLine(String value, int maxUtf16) =>
    _validText(value, maxUtf16) &&
    value.trim().isNotEmpty &&
    !value.contains('\n') &&
    !value.contains('\r');

bool _validText(String value, int maxUtf16) {
  if (value.length > maxUtf16) return false;
  for (var index = 0; index < value.length; index++) {
    final code = value.codeUnitAt(index);
    if (code >= 0xd800 && code <= 0xdbff) {
      if (++index >= value.length) return false;
      final next = value.codeUnitAt(index);
      if (next < 0xdc00 || next > 0xdfff) return false;
    } else if (code >= 0xdc00 && code <= 0xdfff) {
      return false;
    }
  }
  return true;
}

bool _boundary(String text, int offset) {
  if (offset == 0 || offset == text.length) return true;
  final before = text.codeUnitAt(offset - 1);
  final after = text.codeUnitAt(offset);
  return !(before >= 0xd800 &&
      before <= 0xdbff &&
      after >= 0xdc00 &&
      after <= 0xdfff);
}
