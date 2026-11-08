import 'package:bookloom/core/ai/ai_context.dart';
import 'package:bookloom/core/model/block.dart';
import 'package:bookloom/core/model/chapter.dart';

final class AiProofreadingSnapshot {
  AiProofreadingSnapshot({
    required List<AiContextBlock> blocks,
    required Map<String, Chapter> chapters,
  }) : blocks = List<AiContextBlock>.unmodifiable(blocks),
       chapters = Map<String, Chapter>.unmodifiable({
         for (final entry in chapters.entries)
           entry.key: entry.value.copyWith(
             blocks: List<Block>.unmodifiable(entry.value.blocks),
           ),
       });

  final List<AiContextBlock> blocks;
  final Map<String, Chapter> chapters;
}
