import 'package:bookloom/core/ai/ai_analysis_result.dart';
import 'package:bookloom/core/ai/ai_client.dart';
import 'package:bookloom/core/ai/ai_configuration.dart';
import 'package:bookloom/core/ai/ai_context.dart';
import 'package:bookloom/core/ai/ai_proofreading_prompt.dart';
import 'package:bookloom/core/ai/ai_protocol.dart';
import 'package:bookloom/core/editing/ai_chapter_split_proposal.dart';
import 'package:bookloom/core/editing/ai_text_proposal.dart';
import 'package:bookloom/core/editing/proofreading_finding.dart';
import 'package:bookloom/core/editing/proofreading_rule.dart';
import 'package:bookloom/core/errors/app_failure.dart';
import 'package:bookloom/core/model/block.dart';
import 'package:bookloom/core/model/chapter.dart';
import 'package:bookloom/core/platform/background_jobs.dart';
import 'package:bookloom/features/editor/application/ai_advertisement_request.dart';
import 'package:bookloom/features/editor/application/ai_audit_gap_request.dart';
import 'package:bookloom/features/editor/application/ai_proofreading_snapshot.dart';
import 'package:bookloom/features/editor/application/editor_session.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

enum AiProofreadingPhase {
  idle,
  preparing,
  awaitingConsent,
  running,
  completed,
  applying,
  applied,
  cancelled,
  stale,
  failed,
}

final class AiProofreadingConsent {
  AiProofreadingConsent._({
    required this.configuration,
    required this.plan,
    required this.intent,
    required this.auditGap,
    required this.advertisementSelection,
    required this.ruleRequest,
    required this.ruleChunkIndex,
    required Map<String, String> chapterTitles,
  }) : chapterTitles = Map<String, String>.unmodifiable(chapterTitles);

  final AiConfiguration configuration;
  final AiContextPlan plan;
  final AiProofreadingIntent intent;
  final AiAuditGapRequest? auditGap;
  final AiAdvertisementRequest? advertisementSelection;
  final AiRuleRequest? ruleRequest;
  final int? ruleChunkIndex;
  final Map<String, String> chapterTitles;
}

final class AiProofreadingChange {
  const AiProofreadingChange({
    required this.id,
    required this.proposal,
    required this.finding,
  });
  final String id;
  final AiTextProposal proposal;
  final Finding finding;
}

final class AiProofreadingSplitChange {
  const AiProofreadingSplitChange({
    required this.id,
    required this.proposal,
    required this.finding,
    required this.sourceBlock,
    required this.sourceChapter,
    required this.sourceBlockIndex,
    this.parentTitle,
  });

  final String id;
  final AiChapterSplitProposal proposal;
  final Finding finding;
  final AiContextBlock sourceBlock;
  final Chapter sourceChapter;
  final int sourceBlockIndex;
  final String? parentTitle;

  Iterable<Block> get precedingBlocks =>
      sourceChapter.blocks.take(sourceBlockIndex);
  int get precedingBlockCount => sourceBlockIndex;
  Iterable<Block> get followingBlocks =>
      sourceChapter.blocks.skip(sourceBlockIndex + 1);
  int get followingBlockCount =>
      sourceChapter.blocks.length - sourceBlockIndex - 1;
}

class AiProofreadingTask extends ChangeNotifier {
  factory AiProofreadingTask({
    required EditorSession session,
    required Future<AiConfiguration> Function() loadConfiguration,
    required AiCredentialStore credentials,
    required AiTextClient Function() createClient,
    BackgroundJobs? jobs,
  }) => AiProofreadingTask._(
    session,
    loadConfiguration,
    credentials,
    createClient,
    jobs,
  );

  AiProofreadingTask._(
    this._session,
    this._loadConfiguration,
    this._credentials,
    this._createClient,
    BackgroundJobs? jobs,
  ) : _jobs = jobs ?? BackgroundJobs(),
      _ownsJobs = jobs == null {
    _session.addListener(_sessionChanged);
  }

  final EditorSession _session;
  final Future<AiConfiguration> Function() _loadConfiguration;
  final AiCredentialStore _credentials;
  final AiTextClient Function() _createClient;
  final BackgroundJobs _jobs;
  final bool _ownsJobs;
  AiProofreadingPhase _phase = AiProofreadingPhase.idle;
  AiProofreadingConsent? _consent;
  AiProofreadingSnapshot? _snapshot;
  List<Finding> _findings = const [];
  List<AiProofreadingChange> _changes = const [];
  List<AiProofreadingSplitChange> _splitChanges = const [];
  List<RuleProposal> _ruleProposals = const [];
  final Set<String> _ignoredFindingIds = {};
  List<AiTextProposalConflict> _conflicts = const [];
  AppFailure? _failure;
  AiCancellation? _cancellation;
  AiTextClient? _client;
  bool _working = false;
  bool _workerActive = false;
  bool _disposed = false;
  String? _bookId;
  String? _sessionId;
  int? _revision;
  int _completedChunks = 0;
  int _taskId = 0;
  int _lastAppliedCount = 0;

  AiProofreadingPhase get phase => _phase;
  AiProofreadingConsent? get consent => _consent;
  List<Finding> get findings => _findings;
  List<AiProofreadingChange> get changes => _changes;
  List<AiProofreadingSplitChange> get splitChanges => _splitChanges;
  List<RuleProposal> get ruleProposals => _ruleProposals;
  bool get canUseRuleProposals => canApply && _ruleProposals.isNotEmpty;
  List<Finding> get visibleFindings => List<Finding>.unmodifiable(
    _findings.where((finding) => !_ignoredFindingIds.contains(finding.id)),
  );
  List<AiProofreadingChange> get visibleChanges =>
      List<AiProofreadingChange>.unmodifiable(
        _changes.where(
          (change) => !_ignoredFindingIds.contains(change.finding.id),
        ),
      );
  List<AiProofreadingSplitChange> get visibleSplitChanges =>
      List<AiProofreadingSplitChange>.unmodifiable(
        _splitChanges.where(
          (change) => !_ignoredFindingIds.contains(change.finding.id),
        ),
      );
  int get ignoredFindingCount => _ignoredFindingIds.length;
  List<AiTextProposalConflict> get conflicts => _conflicts;
  AppFailure? get failure => _failure;
  bool get isBusy => _working;
  int get completedChunks => _completedChunks;
  int get totalChunks => _consent?.plan.chunks.length ?? 0;
  int get lastAppliedCount => _lastAppliedCount;
  bool get canApply =>
      !_working && _phase == AiProofreadingPhase.completed && _current;

  bool get _current =>
      !_disposed &&
      _sessionId != null &&
      _session.sessionId == _sessionId &&
      _session.book?.id == _bookId &&
      _session.saveSeq == _revision;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _clearResults() {
    _snapshot = null;
    _findings = const [];
    _changes = const [];
    _splitChanges = const [];
    _ruleProposals = const [];
    _ignoredFindingIds.clear();
    _conflicts = const [];
  }

  void _check([
    AiAuditGapRequest? auditGap,
    AiAdvertisementRequest? advertisementSelection,
  ]) {
    if (!_current) throw const ValidationFailure('书稿已变化，请重新确认分析范围。');
    auditGap?.validate(
      book: _session.book!,
      sessionId: _sessionId!,
      sessionRevision: _revision!,
    );
    advertisementSelection?.validate(
      book: _session.book!,
      sessionId: _sessionId!,
      sessionRevision: _revision!,
    );
    _cancellation?.throwIfCancelled();
  }

  void _sessionChanged() {
    if (_disposed ||
        _sessionId == null ||
        _current ||
        _phase == AiProofreadingPhase.applying ||
        _phase == AiProofreadingPhase.applied ||
        _phase == AiProofreadingPhase.idle) {
      return;
    }
    _cancellation?.cancel();
    if (_workerActive) _jobs.cancelActive();
    _phase = AiProofreadingPhase.stale;
    _clearResults();
    _notify();
  }

  Future<void> prepare({
    required AiProofreadingIntent intent,
    required List<String> chapterIds,
    AiAuditGapRequest? auditGap,
    AiAdvertisementRequest? advertisementSelection,
    AiRuleRequest? ruleRequest,
  }) async {
    if (_disposed || _working) return;
    final selected = List<String>.unmodifiable(chapterIds);
    _working = true;
    _phase = AiProofreadingPhase.preparing;
    _failure = null;
    _consent = null;
    _completedChunks = 0;
    _lastAppliedCount = 0;
    _clearResults();
    _cancellation = AiCancellation();
    _bookId = _session.book?.id;
    _sessionId = _session.sessionId;
    _revision = _session.saveSeq;
    _taskId++;
    _notify();
    try {
      _check(auditGap, advertisementSelection);
      if (ruleRequest != null) {
        ruleRequest.validate();
        if (ruleRequest.kind !=
            (intent == AiProofreadingIntent.advertisement
                ? ProofreadingRuleKind.advertisement
                : ProofreadingRuleKind.chapter)) {
          throw const ValidationFailure('规则种类与本次校对任务不一致。');
        }
      }
      if (auditGap != null &&
          (intent != AiProofreadingIntent.missingChapter ||
              !listEquals(selected, auditGap.chapterIds))) {
        throw const ValidationFailure('体检断档分析范围与发现项不一致，请重新体检后再分析。');
      }
      if (advertisementSelection != null &&
          (auditGap != null ||
              intent != AiProofreadingIntent.advertisement ||
              selected.length != 1 ||
              selected.single != advertisementSelection.chapterId)) {
        throw const ValidationFailure('广告选区与分析范围不一致，请重新选择正文。');
      }
      if (intent == AiProofreadingIntent.missingChapter &&
          selected.length < (auditGap == null ? 2 : 1)) {
        throw const ValidationFailure('缺章诊断至少需要前后两个章节。');
      }
      final configuration = (await _loadConfiguration()).canonicalized();
      _check(auditGap, advertisementSelection);
      _validateConfiguration(configuration);
      final AiContextPlan plan;
      if (advertisementSelection != null) {
        plan = advertisementSelection.buildPlan(book: _session.book!);
      } else {
        final snapshot = await _session.readAiContextSnapshot(
          selected,
          isCancelled: () => _cancellation!.isCancelled || !_current,
        );
        _check(auditGap);
        _snapshot = snapshot;
        final work = _jobs.run<_PlanInput, AiContextPlan>(
          _PlanInput(_bookId!, _sessionId!, _revision!, snapshot.blocks),
          _planContext,
          revision: _revision!,
        );
        _workerActive = true;
        plan = await work;
        _workerActive = false;
      }
      _check(auditGap, advertisementSelection);
      int? ruleChunkIndex;
      if (ruleRequest != null) {
        for (final chunk in plan.chunks) {
          if (ruleRequest.isCoveredBy(chunk)) {
            ruleChunkIndex = chunk.index;
            break;
          }
        }
        if (ruleChunkIndex == null) {
          throw const ValidationFailure('所有规则正例必须完整位于同一发送片段的正文核心中。');
        }
      }
      for (final chunk in plan.chunks) {
        final chunkRuleRequest = chunk.index == ruleChunkIndex
            ? ruleRequest
            : null;
        AiProofreadingPrompt.system(
          intent,
          auditGap: auditGap != null,
          advertisementSelection: advertisementSelection != null,
          ruleRequest: chunkRuleRequest,
        );
        AiProofreadingPrompt.userContext(
          intent,
          chunk,
          auditGap: auditGap?.toJson(),
          advertisementSelection: advertisementSelection?.toJson(),
          ruleRequest: chunkRuleRequest,
        );
      }
      final chapters = <String, String>{};
      for (final chapter in _session.book!.chapters) {
        if (selected.contains(chapter.id)) chapters[chapter.id] = chapter.title;
      }
      _consent = AiProofreadingConsent._(
        configuration: configuration,
        plan: plan,
        intent: intent,
        auditGap: auditGap,
        advertisementSelection: advertisementSelection,
        ruleRequest: ruleRequest,
        ruleChunkIndex: ruleChunkIndex,
        chapterTitles: chapters,
      );
      _phase = AiProofreadingPhase.awaitingConsent;
    } catch (error) {
      _fail(error);
    } finally {
      _workerActive = false;
      _working = false;
      _notify();
    }
  }

  Future<void> run(AiProofreadingConsent consent) async {
    if (_disposed || _working) return;
    if (!identical(consent, _consent) ||
        _phase != AiProofreadingPhase.awaitingConsent) {
      _failure = const ValidationFailure('分析确认已失效，请重新准备。');
      _notify();
      return;
    }
    _working = true;
    _phase = AiProofreadingPhase.running;
    _failure = null;
    _cancellation = AiCancellation();
    _notify();
    try {
      _check(consent.auditGap, consent.advertisementSelection);
      await _checkConfiguration(
        consent.configuration,
        consent.auditGap,
        consent.advertisementSelection,
      );
      final key = await _credentials.read(
        consent.configuration.credentialReference!,
      );
      _check(consent.auditGap, consent.advertisementSelection);
      if (key == null || key.isEmpty) {
        throw const ValidationFailure('未找到 AI 密钥，请重新配置并测试连接。');
      }
      final client = _createClient();
      _client = client;
      final results = <AiAnalysisResult>[];
      for (final chunk in consent.plan.chunks) {
        final chunkRuleRequest = chunk.index == consent.ruleChunkIndex
            ? consent.ruleRequest
            : null;
        _check(consent.auditGap, consent.advertisementSelection);
        await _checkConfiguration(
          consent.configuration,
          consent.auditGap,
          consent.advertisementSelection,
        );
        final response = await client.generate(
          endpoint: consent.configuration.endpoint,
          apiKey: key,
          model: consent.configuration.model,
          systemPrompt: AiProofreadingPrompt.system(
            consent.intent,
            auditGap: consent.auditGap != null,
            advertisementSelection: consent.advertisementSelection != null,
            ruleRequest: chunkRuleRequest,
          ),
          userContext: AiProofreadingPrompt.userContext(
            consent.intent,
            chunk,
            auditGap: consent.auditGap?.toJson(),
            advertisementSelection: consent.advertisementSelection?.toJson(),
            ruleRequest: chunkRuleRequest,
          ),
          outputTokens: 4096,
          cancellation: _cancellation!,
        );
        _check(consent.auditGap, consent.advertisementSelection);
        final work = _jobs.run<_DecodeInput, AiAnalysisResult>(
          _DecodeInput(
            response,
            chunk,
            chunkRuleRequest == null
                ? 'task-$_taskId-chunk-${chunk.index}'
                : 'joint-${const Uuid().v4()}',
            consent.intent,
            chunkRuleRequest,
          ),
          _decodeResult,
          revision: _revision!,
        );
        _workerActive = true;
        final result = await work;
        _workerActive = false;
        _check(consent.auditGap, consent.advertisementSelection);
        results.add(result);
        _completedChunks++;
        _notify();
      }
      await _checkConfiguration(
        consent.configuration,
        consent.auditGap,
        consent.advertisementSelection,
      );
      _publish(results);
      _phase = AiProofreadingPhase.completed;
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

  Future<void> _checkConfiguration(
    AiConfiguration expected,
    AiAuditGapRequest? auditGap,
    AiAdvertisementRequest? advertisementSelection,
  ) async {
    final current = (await _loadConfiguration()).canonicalized();
    _check(auditGap, advertisementSelection);
    if (current != expected) {
      throw const ValidationFailure('AI 服务配置已改变，请重新确认服务与范围。');
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

  void _publish(List<AiAnalysisResult> results) {
    final selection = _consent!.advertisementSelection;
    if (selection != null &&
        results.any(
          (result) =>
              result.chapterSplits.isNotEmpty ||
              result.textChanges.proposals.any(
                (proposal) =>
                    proposal.target.chapterId != selection.chapterId ||
                    proposal.target.blockId != selection.blockId ||
                    proposal.range.start < selection.startUtf16 ||
                    proposal.range.end > selection.endUtf16 ||
                    proposal.action == AiTextProposalAction.removeBlock &&
                        (selection.startUtf16 != 0 ||
                            selection.endUtf16 !=
                                result.context.slices
                                    .singleWhere(
                                      (slice) =>
                                          slice.block.blockId ==
                                          selection.blockId,
                                    )
                                    .block
                                    .text
                                    .length),
              ),
        )) {
      throw const ValidationFailure('AI 返回了广告选区外的修改，整批结果已拒绝。');
    }
    final findings = <Finding>[];
    final changes = <AiProofreadingChange>[];
    final splits = <AiProofreadingSplitChange>[];
    final blocks = <String, AiContextBlock>{
      for (final chunk in _consent!.plan.chunks)
        for (final slice in chunk.slices) slice.block.blockId: slice.block,
    };
    final firstNonEmptyBlockByChapter = <String, String>{};
    for (final block in blocks.values) {
      if (block.text.trim().isNotEmpty) {
        firstNonEmptyBlockByChapter.putIfAbsent(
          block.chapterId,
          () => block.blockId,
        );
      }
    }
    for (final (index, result) in results.indexed) {
      final localFindings = <String, Finding>{};
      for (final finding in result.findings) {
        final local = finding.withId(
          'task-$_taskId-chunk-$index-finding-${findings.length}',
        );
        findings.add(local);
        localFindings[finding.id] = local;
      }
      for (final proposal in result.textChanges.proposals) {
        if (proposal.action == AiTextProposalAction.renameChapter &&
            firstNonEmptyBlockByChapter[proposal.target.chapterId] !=
                proposal.target.blockId) {
          throw const ValidationFailure('章节标题提案并非首个正文块的标题，未修改书稿。');
        }
        final id = 'task-$_taskId-chunk-$index-change-${changes.length}';
        changes.add(
          AiProofreadingChange(
            id: id,
            finding:
                localFindings[result.findingIdByTextProposalId[proposal.id]]!,
            proposal: AiTextProposal(
              id: id,
              action: proposal.action,
              target: proposal.target,
              range: proposal.range,
              replacement: proposal.replacement,
              originalTitle: proposal.originalTitle,
              reason: proposal.reason,
            ),
          ),
        );
      }
      for (final proposal in result.chapterSplits) {
        final id = 'task-$_taskId-chunk-$index-split-${splits.length}';
        final source = blocks[proposal.target.blockId];
        final chapter = _snapshot?.chapters[proposal.target.chapterId];
        final sourceBlockIndex = chapter?.blocks.indexWhere(
          (block) => block.id == proposal.target.blockId,
        );
        if (source == null ||
            chapter == null ||
            chapter.id != source.chapterId ||
            chapter.bookId != _bookId ||
            source.blockId != proposal.target.blockId ||
            sourceBlockIndex == null ||
            sourceBlockIndex < 0 ||
            chapter.blocks[sourceBlockIndex] is! TextBlock ||
            (chapter.blocks[sourceBlockIndex] as TextBlock).text !=
                source.text) {
          throw const ValidationFailure('拆章来源与本地书稿快照不一致，请重新分析。');
        }
        final parentId = chapter.parentId;
        final parent = parentId == null
            ? null
            : _session.book!.chapters
                  .where((item) => item.id == parentId && item.isVolume)
                  .firstOrNull;
        splits.add(
          AiProofreadingSplitChange(
            id: id,
            finding:
                localFindings[result.findingIdBySplitProposalId[proposal.id]]!,
            proposal: AiChapterSplitProposal(
              id: id,
              target: proposal.target,
              range: proposal.range,
              title: proposal.title,
              removeTitleLine: proposal.removeTitleLine,
              reason: proposal.reason,
              titleEvidenceRange: proposal.titleEvidenceRange,
              headingLevel: proposal.headingLevel,
              headingNumber: proposal.headingNumber,
              numberEvidenceRange: proposal.numberEvidenceRange,
            ),
            sourceBlock: source,
            sourceChapter: chapter,
            sourceBlockIndex: sourceBlockIndex,
            parentTitle: parent?.title,
          ),
        );
      }
    }
    final conflicts = <AiTextProposalConflict>[];
    for (var leftIndex = 0; leftIndex < changes.length; leftIndex++) {
      final left = changes[leftIndex].proposal;
      for (final change in changes.skip(leftIndex + 1)) {
        final right = change.proposal;
        if (left.target.chapterId == right.target.chapterId &&
            (left.action == AiTextProposalAction.renameChapter &&
                    right.action == AiTextProposalAction.renameChapter ||
                left.target.blockId == right.target.blockId &&
                    (left.action == AiTextProposalAction.renameChapter
                            ? left.chapterTitleConflictRangeIn(
                                left.originalTitle!,
                                blocks[left.target.blockId]!.text,
                              )
                            : left.range)
                        .overlaps(
                          right.action == AiTextProposalAction.renameChapter
                              ? right.chapterTitleConflictRangeIn(
                                  right.originalTitle!,
                                  blocks[right.target.blockId]!.text,
                                )
                              : right.range,
                        ))) {
          conflicts.add(AiTextProposalConflict(left.id, right.id));
        }
      }
    }
    for (final (index, split) in splits.indexed) {
      final proposal = split.proposal;
      final line = proposal.titleLineIn(split.sourceBlock.text, proposal.range);
      for (final other in splits.skip(index + 1)) {
        if (proposal.target.blockId == other.proposal.target.blockId &&
            line.overlaps(
              other.proposal.titleLineIn(
                other.sourceBlock.text,
                other.proposal.range,
              ),
            )) {
          conflicts.add(AiTextProposalConflict(split.id, other.id));
        }
      }
      for (final text in changes) {
        if (proposal.target.chapterId == text.proposal.target.chapterId &&
            (text.proposal.action == AiTextProposalAction.renameChapter ||
                proposal.target.blockId == text.proposal.target.blockId &&
                    proposal
                        .textConflictRangeIn(split.sourceBlock.text)
                        .overlaps(text.proposal.range))) {
          conflicts.add(AiTextProposalConflict(split.id, text.id));
        }
      }
    }
    _findings = List<Finding>.unmodifiable(findings);
    _changes = List<AiProofreadingChange>.unmodifiable(changes);
    _splitChanges = List<AiProofreadingSplitChange>.unmodifiable(splits);
    _conflicts = List<AiTextProposalConflict>.unmodifiable(conflicts);
    _ruleProposals = List<RuleProposal>.unmodifiable(
      results.expand((result) => result.ruleProposals),
    );
  }

  void ignoreFinding(String findingId) {
    if (!canApply ||
        !_findings.any((finding) => finding.id == findingId) ||
        !_ignoredFindingIds.add(findingId)) {
      return;
    }
    _notify();
  }

  void restoreIgnoredFindings() {
    if (!canApply || _ignoredFindingIds.isEmpty) return;
    _ignoredFindingIds.clear();
    _notify();
  }

  Future<void> applySelected(Set<String> ids) async {
    if (_disposed || _working || !canApply) return;
    final selected = Set<String>.unmodifiable(ids);
    if (selected.isEmpty ||
        selected.length > 100 ||
        !selected.every(
          (id) =>
              _changes.any(
                (change) =>
                    change.id == id &&
                    !_ignoredFindingIds.contains(change.finding.id),
              ) ||
              _splitChanges.any(
                (change) =>
                    change.id == id &&
                    !_ignoredFindingIds.contains(change.finding.id),
              ),
        ) ||
        _conflicts.any(
          (pair) =>
              selected.contains(pair.firstId) &&
              selected.contains(pair.secondId),
        )) {
      _failure = const ValidationFailure('请选择有效且不冲突的变更，一次最多 100 项。');
      _notify();
      return;
    }
    _working = true;
    _phase = AiProofreadingPhase.applying;
    _failure = null;
    _notify();
    try {
      _check(_consent?.auditGap, _consent?.advertisementSelection);
      await _session.applyAiChanges(
        textProposals: [
          for (final change in _changes)
            if (selected.contains(change.id)) change.proposal,
        ],
        splitProposals: [
          for (final change in _splitChanges)
            if (selected.contains(change.id)) change.proposal,
        ],
        selectedIds: selected,
      );
      _lastAppliedCount = selected.length;
      _clearResults();
      _phase = AiProofreadingPhase.applied;
    } catch (error) {
      _fail(error);
    } finally {
      _working = false;
      _notify();
    }
  }

  void cancel() {
    if (_disposed) return;
    _failure = null;
    _cancellation?.cancel();
    if (_workerActive) _jobs.cancelActive();
    if (_phase == AiProofreadingPhase.applying) _session.cancelTool();
    _clearResults();
    _phase = AiProofreadingPhase.cancelled;
    _notify();
  }

  void _fail(Object error) {
    _clearResults();
    if (!_current) {
      _phase = AiProofreadingPhase.stale;
      _failure = const ValidationFailure('书稿会话已变化，分析结果已失效，请重新分析。');
    } else if (_cancellation?.isCancelled == true ||
        error is TaskCancelled ||
        error is AiTransportException &&
            error.failure == AiTransportFailure.cancelled) {
      _phase = AiProofreadingPhase.cancelled;
      _failure = null;
    } else {
      _phase = AiProofreadingPhase.failed;
      _failure = switch (error) {
        AiProtocolException() => ValidationFailure(switch (error.failure) {
          AiProtocolFailure.authentication => 'AI 鉴权失败，请检查密钥与服务地址。',
          AiProtocolFailure.rateLimited => 'AI 服务限流，请稍后手动重试；重试可能再次计费。',
          AiProtocolFailure.refused => 'AI 服务拒绝了本次分析，书稿未修改。',
          AiProtocolFailure.incomplete => 'AI 返回结果被截断，书稿未修改，请缩小范围。',
          _ => 'AI 协议或模型返回不兼容，书稿未修改，请检查配置。',
        }),
        AiTransportException() => ValidationFailure(switch (error.failure) {
          AiTransportFailure.timedOut => 'AI 请求超时，请检查网络或缩小范围；重试可能再次计费。',
          AiTransportFailure.responseTooLarge => 'AI 响应超过预算，请缩小分析范围。',
          AiTransportFailure.requestTooLarge => 'AI 请求超过预算，请缩小分析范围。',
          _ => 'AI 连接失败，未自动重试，请检查地址与网络。',
        }),
        AppFailure() => ValidationFailure(error.message),
        _ => const ValidationFailure('AI 分析无法完成，书稿未修改，请检查服务设置或缩小范围。'),
      };
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _cancellation?.cancel();
    if (_workerActive) _jobs.cancelActive();
    if (_phase == AiProofreadingPhase.applying) _session.cancelTool();
    _client?.dispose();
    _client = null;
    if (_ownsJobs) _jobs.dispose();
    _session.removeListener(_sessionChanged);
    _disposed = true;
    _clearResults();
    _consent = null;
    super.dispose();
  }
}

final class _PlanInput {
  const _PlanInput(this.bookId, this.sessionId, this.revision, this.blocks);
  final String bookId;
  final String sessionId;
  final int revision;
  final List<AiContextBlock> blocks;
}

AiContextPlan _planContext(
  _PlanInput input,
  void Function(double, String) progress,
) => AiContextPlanner.plan(
  bookId: input.bookId,
  sessionId: input.sessionId,
  sessionRevision: input.revision,
  blocks: input.blocks,
);

final class _DecodeInput {
  const _DecodeInput(
    this.response,
    this.chunk,
    this.responseId,
    this.intent,
    this.ruleRequest,
  );
  final String response;
  final AiContextChunk chunk;
  final String responseId;
  final AiProofreadingIntent intent;
  final AiRuleRequest? ruleRequest;
}

AiAnalysisResult _decodeResult(
  _DecodeInput input,
  void Function(double, String) progress,
) => _validateIntent(
  AiAnalysisResultDecoder.decode(
    input.response,
    context: input.chunk,
    responseId: input.responseId,
    ruleRequest: input.ruleRequest,
  ),
  input.intent,
);

AiAnalysisResult _validateIntent(
  AiAnalysisResult result,
  AiProofreadingIntent intent,
) {
  final kind = intent == AiProofreadingIntent.advertisement
      ? FindingKind.advertisement
      : FindingKind.missingChapter;
  if (result.findings.any((finding) => finding.kind != kind) ||
      intent == AiProofreadingIntent.missingChapter &&
          result.textChanges.proposals.any(
            (proposal) => proposal.action != AiTextProposalAction.renameChapter,
          ) ||
      intent == AiProofreadingIntent.advertisement &&
          (result.chapterSplits.isNotEmpty ||
              result.textChanges.proposals.any(
                (proposal) =>
                    proposal.action == AiTextProposalAction.renameChapter,
              ))) {
    throw const ValidationFailure('AI 返回结果超出本次任务范围，未修改书稿。');
  }
  return result;
}
