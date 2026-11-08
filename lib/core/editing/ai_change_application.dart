import 'dart:convert';

import 'package:bookloom/core/ai/ai_limits.dart';
import 'package:bookloom/core/editing/ai_chapter_split_proposal.dart';
import 'package:bookloom/core/editing/ai_text_application.dart';
import 'package:bookloom/core/editing/ai_text_proposal.dart';
import 'package:bookloom/core/editing/chapter_edits.dart';
import 'package:bookloom/core/editing/proposal_target.dart';
import 'package:bookloom/core/errors/app_failure.dart';
import 'package:bookloom/core/model/block.dart';
import 'package:bookloom/core/model/book.dart';
import 'package:bookloom/core/model/chapter.dart';

abstract final class AiChangeApplication {
  static List<Chapter> compile({
    required Book book,
    required String sessionId,
    required int saveSeq,
    required List<AiTextProposal> textProposals,
    required List<AiChapterSplitProposal> splitProposals,
    required Set<String> selectedIds,
    required Map<String, AiChapterSplitIdentity> splitIdentities,
    required int byteBudget,
  }) {
    final ids = <String>{};
    if (textProposals.length + splitProposals.length > 100 ||
        selectedIds.length > 100 ||
        sessionId.isEmpty ||
        saveSeq < 0 ||
        byteBudget <= 0) {
      _invalid();
    }
    for (final id in [
      ...textProposals.map((proposal) => proposal.id),
      ...splitProposals.map((proposal) => proposal.id),
    ]) {
      if (id.trim().isEmpty || id.length > 128 || !ids.add(id)) _invalid();
    }
    if (!selectedIds.every(ids.contains)) _invalid();
    final selectedText = textProposals
        .where((proposal) => selectedIds.contains(proposal.id))
        .toList();
    final selectedSplits = splitProposals
        .where((proposal) => selectedIds.contains(proposal.id))
        .toList();
    final selectedChapterIds = {
      ...selectedText.map((proposal) => proposal.target.chapterId),
      ...selectedSplits.map((proposal) => proposal.target.chapterId),
    };
    var targetCharacters = 0;
    var targetBlocks = 0;
    final chapterIds = book.chapters.map((chapter) => chapter.id).toSet();
    final blockIds = <String>{};
    if (chapterIds.length != book.chapters.length) _invalid();
    for (final chapter in book.chapters) {
      if (chapter.bookId != book.id) _invalid();
      for (final block in chapter.blocks) {
        if (!blockIds.add(block.id)) _invalid();
        if (selectedChapterIds.contains(chapter.id)) {
          targetCharacters += block.plainText.length;
          targetBlocks++;
          if (targetCharacters > aiMaxContextCharacters ||
              targetBlocks > 10000) {
            _invalid();
          }
        }
      }
    }
    final titleChanges = <String, AiTextProposal>{};
    var titleBytes = 0;
    for (final proposal in selectedText) {
      if (proposal.action != AiTextProposalAction.renameChapter) {
        if (proposal.originalTitle != null) _invalid();
        continue;
      }
      final target = proposal.target;
      final chapters = book.chapters.where(
        (chapter) => chapter.id == target.chapterId && !chapter.isVolume,
      );
      if (chapters.length != 1 || titleChanges.containsKey(target.chapterId)) {
        _invalid();
      }
      final chapter = chapters.single;
      final blocks = chapter.blocks.whereType<TextBlock>().where(
        (block) => block.text.trim().isNotEmpty,
      );
      if (blocks.isEmpty || blocks.first.id != target.blockId) _invalid();
      final text = blocks.first.text;
      final located = target.locate(
        currentBookId: book.id,
        currentSessionId: sessionId,
        currentSessionRevision: saveSeq,
        currentChapterId: chapter.id,
        currentBlockId: blocks.first.id,
        currentText: text,
      );
      if (located.start != proposal.range.start ||
          located.end != proposal.range.end) {
        _invalid();
      }
      final conflictRange = proposal.chapterTitleConflictRangeIn(
        chapter.title,
        text,
      );
      if (selectedSplits.any((split) => split.target.chapterId == chapter.id) ||
          selectedText.any(
            (other) =>
                other.id != proposal.id &&
                other.target.blockId == target.blockId &&
                conflictRange.overlaps(other.range),
          )) {
        _invalid();
      }
      titleChanges[chapter.id] = proposal;
      titleBytes +=
          utf8.encode(chapter.title).length +
          utf8.encode(proposal.replacement).length +
          utf8.encode(chapter.id).length;
      if (titleBytes > byteBudget) _invalid();
    }
    final contentChanges = selectedText
        .where(
          (proposal) => proposal.action != AiTextProposalAction.renameChapter,
        )
        .toList();
    if (titleBytes == byteBudget && contentChanges.isNotEmpty) _invalid();
    final splitLocations = <String, (int, int, ProposalTextRange)>{};
    for (final proposal in selectedSplits) {
      final target = proposal.target;
      final chapterIndex = book.chapters.indexWhere(
        (chapter) => chapter.id == target.chapterId && !chapter.isVolume,
      );
      if (chapterIndex < 0 ||
          proposal.reason.trim().isEmpty ||
          proposal.reason.length > 1024) {
        _invalid();
      }
      final chapter = book.chapters[chapterIndex];
      final blockIndex = chapter.blocks.indexWhere(
        (block) => block.id == target.blockId,
      );
      if (blockIndex < 0 || chapter.blocks[blockIndex] is! TextBlock) {
        _invalid();
      }
      final text = (chapter.blocks[blockIndex] as TextBlock).text;
      final located = target.locate(
        currentBookId: book.id,
        currentSessionId: sessionId,
        currentSessionRevision: saveSeq,
        currentChapterId: chapter.id,
        currentBlockId: target.blockId,
        currentText: text,
      );
      if (located.start != proposal.range.start ||
          located.end != proposal.range.end) {
        _invalid();
      }
      final line = proposal.titleLineIn(text, located);
      for (final previous in selectedSplits) {
        if (previous.id == proposal.id) break;
        final previousLocation = splitLocations[previous.id];
        if (previousLocation != null &&
            previous.target.blockId == target.blockId &&
            previousLocation.$3.overlaps(line)) {
          _invalid();
        }
      }
      for (final change in selectedText) {
        if (change.target.blockId == target.blockId &&
            change.range.overlaps(proposal.textConflictRangeIn(text))) {
          _invalid();
        }
      }
      final identity = splitIdentities[proposal.id];
      if (identity == null ||
          !_safeId(identity.chapterId) ||
          !_safeId(identity.blockId) ||
          !chapterIds.add(identity.chapterId) ||
          !blockIds.add(identity.blockId)) {
        _invalid();
      }
      final volumeId = identity.volumeId;
      if (proposal.headingLevel == 1) {
        if (volumeId == null ||
            !_safeId(volumeId) ||
            !chapterIds.add(volumeId)) {
          _invalid();
        }
      } else if (volumeId != null) {
        _invalid();
      }
      splitLocations[proposal.id] = (chapterIndex, blockIndex, line);
    }
    final removedBlockIds = <String>{};
    for (final proposal in selectedText) {
      if (proposal.action != AiTextProposalAction.removeBlock) continue;
      final target = proposal.target;
      final chapters = book.chapters.where(
        (chapter) => chapter.id == target.chapterId && !chapter.isVolume,
      );
      if (chapters.length != 1) _invalid();
      final blocks = chapters.single.blocks.where(
        (block) => block.id == target.blockId,
      );
      if (blocks.length != 1 || blocks.single is! TextBlock) _invalid();
      final text = (blocks.single as TextBlock).text;
      if (proposal.range.start != 0 ||
          proposal.range.end != text.length ||
          target.originalText != text ||
          target.before.isNotEmpty ||
          target.after.isNotEmpty ||
          proposal.replacement.isNotEmpty) {
        _invalid();
      }
      removedBlockIds.add(target.blockId);
    }
    final preview = AiTextApplication.compile(
      book: book,
      sessionId: sessionId,
      saveSeq: saveSeq,
      proposals: [
        for (final proposal in textProposals)
          if (proposal.action != AiTextProposalAction.renameChapter)
            if (proposal.action == AiTextProposalAction.removeBlock)
              AiTextProposal(
                id: proposal.id,
                action: AiTextProposalAction.deleteText,
                target: proposal.target,
                range: proposal.range,
                replacement: proposal.replacement,
                reason: proposal.reason,
              )
            else
              proposal,
      ],
      selectedIds: contentChanges.map((proposal) => proposal.id).toSet(),
      byteBudget: byteBudget > titleBytes ? byteBudget - titleBytes : 1,
    );
    final next = List<Chapter>.of(book.chapters);
    for (final patch in preview.patches) {
      final index = next.indexWhere((chapter) => chapter.id == patch.chapterId);
      final chapter = next[index];
      next[index] = chapter.copyWith(
        blocks: List<Block>.unmodifiable([
          for (final block in chapter.blocks)
            if (block.id != patch.blockId)
              block
            else if (!removedBlockIds.contains(block.id))
              TextBlock(id: block.id, text: patch.after),
        ]),
      );
    }
    for (final entry in titleChanges.entries) {
      final index = next.indexWhere((chapter) => chapter.id == entry.key);
      next[index] = next[index].copyWith(title: entry.value.replacement);
    }
    selectedSplits.sort((left, right) {
      final first = splitLocations[left.id]!;
      final second = splitLocations[right.id]!;
      final chapterOrder = second.$1.compareTo(first.$1);
      if (chapterOrder != 0) return chapterOrder;
      final blockOrder = second.$2.compareTo(first.$2);
      return blockOrder != 0
          ? blockOrder
          : right.range.start.compareTo(left.range.start);
    });
    for (final proposal in selectedSplits) {
      final target = proposal.target;
      final index = next.indexWhere(
        (chapter) => chapter.id == target.chapterId,
      );
      final chapter = next[index];
      final blockIndex = chapter.blocks.indexWhere(
        (block) => block.id == target.blockId,
      );
      if (blockIndex < 0 || chapter.blocks[blockIndex] is! TextBlock) {
        _invalid();
      }
      final block = chapter.blocks[blockIndex] as TextBlock;
      var shift = 0;
      for (final change in selectedText) {
        if (change.target.blockId == target.blockId &&
            change.range.end <= proposal.range.start) {
          shift +=
              change.replacement.length - change.target.originalText.length;
        }
      }
      final located = ProposalTextRange(
        proposal.range.start + shift,
        proposal.range.end + shift,
      );
      final line = proposal.titleLineIn(block.text, located);
      final prefix = block.text.substring(0, line.start);
      final suffix = block.text.substring(
        proposal.removeTitleLine ? line.end : line.start,
      );
      final identity = splitIdentities[proposal.id]!;
      next[index] = chapter.copyWith(
        blocks: List<Block>.unmodifiable([
          ...chapter.blocks.take(blockIndex),
          if (prefix.isNotEmpty) TextBlock(id: block.id, text: prefix),
        ]),
      );
      final suffixBlocks = List<Block>.unmodifiable([
        if (suffix.isNotEmpty)
          TextBlock(
            id: prefix.isEmpty ? block.id : identity.blockId,
            text: suffix,
          ),
        ...chapter.blocks.skip(blockIndex + 1),
      ]);
      if (proposal.headingLevel == 1) {
        final volumeId = identity.volumeId!;
        final inserted = <Chapter>[
          Chapter(
            id: volumeId,
            bookId: book.id,
            title: proposal.title,
            level: 1,
          ),
          if (suffixBlocks.isNotEmpty)
            Chapter(
              id: identity.chapterId,
              bookId: book.id,
              title: '',
              parentId: volumeId,
              blocks: suffixBlocks,
              frontMatter: true,
            ),
        ];
        next.insertAll(index + 1, inserted);
        for (
          var following = index + inserted.length + 1;
          following < next.length;
          following++
        ) {
          final sibling = next[following];
          if (sibling.isVolume || sibling.parentId != chapter.parentId) break;
          next[following] = sibling.copyWith(parentId: volumeId);
        }
      } else {
        next.insert(
          index + 1,
          Chapter(
            id: identity.chapterId,
            bookId: book.id,
            title: proposal.title,
            parentId: chapter.parentId,
            blocks: suffixBlocks,
          ),
        );
      }
    }
    final normalized = ChapterEdits.normalize(next);
    return List<Chapter>.unmodifiable(
      selectedSplits.isEmpty ? next : normalized,
    );
  }

  static bool _safeId(String value) =>
      RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$').hasMatch(value);

  static Never _invalid() =>
      throw const ValidationFailure('变更提案存在冲突或已失效，未修改书稿；请重新分析或缩小范围。');
}
