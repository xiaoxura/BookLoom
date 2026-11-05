import 'package:bookloom/core/errors/app_failure.dart';
import 'package:bookloom/core/model/block.dart';
import 'package:bookloom/core/model/chapter.dart';

/// Pure structural edits. The input list is in reading order; [order] is
/// normalized within each parent after every structural change.
abstract final class ChapterEdits {
  static List<Chapter> rename(List<Chapter> chapters, String id, String title) {
    final index = _index(chapters, id);
    final next = List<Chapter>.of(chapters);
    next[index] = next[index].copyWith(title: title);
    return next;
  }

  static List<Chapter> mergeWithPrevious(List<Chapter> chapters, String id) {
    final index = _index(chapters, id);
    final source = chapters[index];
    if (source.isVolume) {
      throw const ValidationFailure('卷不能并入上一章。');
    }
    var previous = index - 1;
    while (previous >= 0 && chapters[previous].isVolume) {
      previous--;
    }
    if (previous < 0) {
      throw const ValidationFailure('首章不能并入上一章。');
    }
    final target = chapters[previous];
    final next = List<Chapter>.of(chapters);
    next[previous] = target.copyWith(
      blocks: <Block>[...target.blocks, ...source.blocks],
    );
    next.removeAt(index);
    return normalize(next);
  }

  static List<Chapter> delete(List<Chapter> chapters, String id) {
    final index = _index(chapters, id);
    final removed = chapters[index];
    final next = List<Chapter>.of(chapters)..removeAt(index);
    if (removed.isVolume) {
      for (var i = 0; i < next.length; i++) {
        if (next[i].parentId == id) {
          next[i] = next[i].copyWith(clearParent: true);
        }
      }
    }
    return normalize(next);
  }

  static List<Chapter> promoteToVolume(List<Chapter> chapters, String id) {
    final index = _index(chapters, id);
    final chapter = chapters[index];
    if (chapter.isVolume) return chapters;
    final next = List<Chapter>.of(chapters);
    next[index] = chapter.copyWith(level: 1, clearParent: true);
    // Following siblings belong to the new volume until the next top level
    // item. This keeps a contiguous two-level reading order.
    for (var i = index + 1; i < next.length; i++) {
      final current = next[i];
      if (current.parentId != chapter.parentId || current.isVolume) break;
      next[i] = current.copyWith(parentId: id);
    }
    return normalize(next);
  }

  static List<Chapter> demoteToChapter(List<Chapter> chapters, String id) {
    final index = _index(chapters, id);
    final volume = chapters[index];
    if (!volume.isVolume) return chapters;
    String? previousVolumeId;
    for (var i = index - 1; i >= 0; i--) {
      if (chapters[i].isVolume) {
        previousVolumeId = chapters[i].id;
        break;
      }
    }
    final next = List<Chapter>.of(chapters);
    next[index] = volume.copyWith(
      level: 2,
      parentId: previousVolumeId,
      clearParent: previousVolumeId == null,
    );
    for (var i = 0; i < next.length; i++) {
      if (next[i].parentId == id) {
        next[i] = next[i].copyWith(
          parentId: previousVolumeId,
          clearParent: previousVolumeId == null,
        );
      }
    }
    return normalize(next);
  }

  /// The selected paragraph becomes the new chapter title. Blocks after it
  /// move to the new chapter; earlier blocks remain in the original chapter.
  static List<Chapter> splitAtParagraph(
    List<Chapter> chapters,
    String chapterId,
    String blockId,
    String newChapterId,
  ) {
    final index = _index(chapters, chapterId);
    final chapter = chapters[index];
    if (chapter.isVolume) {
      throw const ValidationFailure('请在章的正文段落处分章。');
    }
    final blockIndex = chapter.blocks.indexWhere(
      (block) => block.id == blockId,
    );
    if (blockIndex < 0 || chapter.blocks[blockIndex] is! TextBlock) {
      throw const ValidationFailure('请选择正文段落分章。');
    }
    if (chapters.any((item) => item.id == newChapterId)) {
      throw const ValidationFailure('章节标识已存在，请重试。');
    }
    final title = (chapter.blocks[blockIndex] as TextBlock).text.trim();
    if (title.isEmpty) {
      throw const ValidationFailure('空段落不能作为章节标题。');
    }
    final next = List<Chapter>.of(chapters);
    next[index] = chapter.copyWith(
      blocks: chapter.blocks.sublist(0, blockIndex),
    );
    next.insert(
      index + 1,
      Chapter(
        id: newChapterId,
        bookId: chapter.bookId,
        title: title,
        parentId: chapter.parentId,
        level: 2,
        blocks: chapter.blocks.sublist(blockIndex + 1),
      ),
    );
    return normalize(next);
  }

  static List<Chapter> setParagraphAsTitle(
    List<Chapter> chapters,
    String chapterId,
    String blockId,
  ) {
    final index = _index(chapters, chapterId);
    final chapter = chapters[index];
    final blockIndex = chapter.blocks.indexWhere(
      (block) => block.id == blockId,
    );
    if (blockIndex < 0 || chapter.blocks[blockIndex] is! TextBlock) {
      throw const ValidationFailure('请选择正文段落设为标题。');
    }
    final title = (chapter.blocks[blockIndex] as TextBlock).text.trim();
    if (title.isEmpty) {
      throw const ValidationFailure('空段落不能作为章节标题。');
    }
    final nextBlocks = List<Block>.of(chapter.blocks)..removeAt(blockIndex);
    final next = List<Chapter>.of(chapters);
    next[index] = chapter.copyWith(title: title, blocks: nextBlocks);
    return next;
  }

  static List<Chapter> normalize(List<Chapter> chapters) {
    final bookId = chapters.firstOrNull?.bookId;
    final volumes = <String>{};
    final seen = <String>{};
    for (final chapter in chapters) {
      if (chapter.bookId != bookId) {
        throw const ValidationFailure('目录包含其他书籍的章节。');
      }
      if (!seen.add(chapter.id)) {
        throw const ValidationFailure('目录中有重复章节，请检查书稿。');
      }
      if (chapter.isVolume) volumes.add(chapter.id);
    }
    final siblingOrders = <String?, int>{};
    final result = <Chapter>[];
    String? activeVolumeId;
    for (final chapter in chapters) {
      if (chapter.level != 1 && chapter.level != 2) {
        throw const ValidationFailure('目录只支持卷和章两级。');
      }
      if (chapter.isVolume && chapter.parentId != null) {
        throw const ValidationFailure('卷不能属于其他卷。');
      }
      if (chapter.parentId != null && !volumes.contains(chapter.parentId)) {
        throw const ValidationFailure('章节所属卷不存在，请检查目录。');
      }
      if (chapter.isVolume) {
        activeVolumeId = chapter.id;
      } else if (chapter.parentId != null &&
          chapter.parentId != activeVolumeId) {
        throw const ValidationFailure('章节必须紧随所属卷，请检查目录顺序。');
      } else if (chapter.parentId == null) {
        activeVolumeId = null;
      }
      final sibling = chapter.parentId;
      final order = siblingOrders[sibling] ?? 0;
      siblingOrders[sibling] = order + 1;
      result.add(
        chapter.order == order ? chapter : chapter.copyWith(order: order),
      );
    }
    return result;
  }

  static int _index(List<Chapter> chapters, String id) {
    final index = chapters.indexWhere((chapter) => chapter.id == id);
    if (index < 0) {
      throw const ValidationFailure('章节不存在，请刷新书稿后重试。');
    }
    return index;
  }
}
