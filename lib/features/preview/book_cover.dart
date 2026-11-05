import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bookloom/core/io/input_limits.dart';
import 'package:bookloom/core/model/book.dart';
import 'package:bookloom/core/model/cover_options.dart';
import 'package:bookloom/core/platform/files.dart';
import 'package:bookloom/l10n/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as image;

import 'bounded_asset_read.dart';

/// The exact same 1200×1800 picture is used by the editor and the exporter.
/// JPEG encoding strips source EXIF and other attached metadata.
abstract final class BookCoverRenderer {
  static const int width = 1200;
  static const int height = 1800;
  static const int maxPixels = ImportLimits.maxCoverPixels;
  static const int maxInputBytes = ImportLimits.maxEncodedCoverBytes;

  static Future<Uint8List> renderJpeg(Book book, {File? imageFile}) async {
    if (book.coverMode == CoverMode.image) {
      if (imageFile == null) {
        throw StateError('封面图片资源不可用。');
      }
      final bytes = await readBoundedAssetFile(imageFile, maxInputBytes);
      final decoded = await _decode(bytes);
      try {
        return await _drawJpeg((canvas) => _drawImage(canvas, decoded.image));
      } finally {
        decoded.image.dispose();
      }
    }
    return _drawJpeg(
      (canvas) => paintTemplate(
        canvas,
        title: book.meta.title,
        author: book.meta.author,
        options: book.coverOptions,
        size: const Size(1200, 1800),
      ),
    );
  }

  /// Checks encoded dimensions before creating a codec or a full pixel image.
  /// The result is a centered, metadata-free cover ready for book asset storage.
  static Future<PreparedCover> prepareUpload(PickedInput input) async {
    if (input.size != null && input.size! > maxInputBytes) {
      throw const FormatException('封面文件超过 24 MiB。');
    }
    final builder = BytesBuilder(copy: false);
    var length = 0;
    await for (final chunk in input.openRead()) {
      length += chunk.length;
      if (length > maxInputBytes) {
        throw const FormatException('封面文件超过 24 MiB。');
      }
      builder.add(chunk);
    }
    final bytes = builder.takeBytes();
    _detectedMime(bytes);
    final decoded = await _decode(bytes);
    try {
      final jpeg = await _drawJpeg(
        (canvas) => _drawImage(canvas, decoded.image),
      );
      final thumbnail = await compute(_makeThumbnail, jpeg);
      return PreparedCover(
        jpeg: jpeg,
        thumbnail: thumbnail,
        sourceWidth: decoded.width,
        sourceHeight: decoded.height,
      );
    } finally {
      decoded.image.dispose();
    }
  }

  static Future<_Decoded> _decode(Uint8List bytes) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final sourceWidth = descriptor.width;
      final sourceHeight = descriptor.height;
      if (sourceWidth <= 0 ||
          sourceHeight <= 0 ||
          sourceWidth * sourceHeight > maxPixels) {
        throw const FormatException('封面图片像素超过 1200 万或尺寸无效。');
      }
      final targetWidth = math.min(sourceWidth, 2400);
      codec = await descriptor.instantiateCodec(targetWidth: targetWidth);
      final frame = await codec.getNextFrame();
      return _Decoded(frame.image, sourceWidth, sourceHeight);
    } on FormatException {
      rethrow;
    } on Object {
      throw const FormatException('无法读取封面图片，请选择 JPEG、PNG 或 WebP。');
    } finally {
      codec?.dispose();
      descriptor?.dispose();
      buffer.dispose();
    }
  }

  static String _detectedMime(Uint8List bytes) {
    if (bytes.length >= 4 &&
        bytes[0] == 0xff &&
        bytes[1] == 0xd8 &&
        bytes[2] == 0xff) {
      return 'image/jpeg';
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0d &&
        bytes[5] == 0x0a &&
        bytes[6] == 0x1a &&
        bytes[7] == 0x0a) {
      return 'image/png';
    }
    if (bytes.length >= 12 &&
        String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
        String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
      return 'image/webp';
    }
    throw const FormatException('封面仅支持 JPEG、PNG 或 WebP 图片。');
  }

  static Future<Uint8List> _drawJpeg(void Function(Canvas) draw) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    draw(canvas);
    final picture = recorder.endRecording();
    try {
      final rendered = await picture.toImage(width, height);
      try {
        final pixels = await rendered.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        if (pixels == null) throw StateError('封面无法编码。');
        return await compute(_encodeJpeg, pixels.buffer.asUint8List());
      } finally {
        rendered.dispose();
      }
    } finally {
      picture.dispose();
    }
  }

  static void _drawImage(Canvas canvas, ui.Image source) {
    final sourceRatio = source.width / source.height;
    const targetRatio = width / height;
    final Rect crop;
    if (sourceRatio > targetRatio) {
      final cropWidth = source.height * targetRatio;
      crop = Rect.fromLTWH(
        (source.width - cropWidth) / 2,
        0,
        cropWidth,
        source.height.toDouble(),
      );
    } else {
      final cropHeight = source.width / targetRatio;
      crop = Rect.fromLTWH(
        0,
        (source.height - cropHeight) / 2,
        source.width.toDouble(),
        cropHeight,
      );
    }
    canvas.drawImageRect(
      source,
      crop,
      const Rect.fromLTWH(0, 0, 1200, 1800),
      Paint()..filterQuality = FilterQuality.high,
    );
  }

  /// Paints a generated cover at any size without encoding a JPEG. The shelf
  /// thumbnail and export renderer share these exact drawing instructions.
  static void paintTemplate(
    Canvas canvas, {
    required String title,
    required String author,
    required CoverOptions options,
    required Size size,
  }) {
    canvas.save();
    canvas.scale(size.width / width, size.height / height);
    _drawTemplate(canvas, title, author, options);
    canvas.restore();
  }

  static void _drawTemplate(
    Canvas canvas,
    String title,
    String author,
    CoverOptions options,
  ) {
    final palette = _palette(options.palette, title);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 1200, 1800),
      Paint()..color = palette.background,
    );
    if (options.template == CoverTemplate.blocks) {
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 1200, 470),
        Paint()..color = palette.panel,
      );
      canvas.drawRect(
        const Rect.fromLTWH(0, 1440, 1200, 360),
        Paint()..color = palette.panel,
      );
      canvas.drawRect(
        const Rect.fromLTWH(90, 535, 1020, 9),
        Paint()..color = palette.ink.withValues(alpha: 0.6),
      );
    } else {
      canvas.drawRect(
        const Rect.fromLTWH(99, 119, 8, 1562),
        Paint()..color = palette.ink.withValues(alpha: 0.72),
      );
      canvas.drawRect(
        const Rect.fromLTWH(1090, 119, 8, 1562),
        Paint()..color = palette.ink.withValues(alpha: 0.72),
      );
    }

    title = title.trim().isEmpty ? '未命名' : title.trim();
    if (options.template == CoverTemplate.vertical &&
        !title.runes.any((rune) => rune > 0xffff || rune == 0x200d)) {
      _drawVerticalTitle(canvas, title, options.titleScale, palette.ink);
    } else {
      _drawHorizontalTitle(canvas, title, options.titleScale, palette.ink);
    }
    if (options.authorPosition != AuthorPosition.hidden &&
        author.trim().isNotEmpty) {
      final y = options.authorPosition == AuthorPosition.top ? 210.0 : 1508.0;
      _paintFittedText(
        canvas,
        author.trim(),
        Rect.fromLTWH(155, y, 890, 170),
        55,
        palette.ink,
        weight: FontWeight.w400,
        align: TextAlign.center,
      );
    }
  }

  static void _drawHorizontalTitle(
    Canvas canvas,
    String title,
    double scale,
    Color ink,
  ) {
    _paintFittedText(
      canvas,
      title,
      const Rect.fromLTWH(142, 580, 916, 830),
      114 * scale,
      ink,
      weight: FontWeight.w700,
      align: TextAlign.center,
    );
  }

  static void _drawVerticalTitle(
    Canvas canvas,
    String title,
    double scale,
    Color ink,
  ) {
    final glyphs = title.runes.map(String.fromCharCode).toList(growable: false);
    const area = Rect.fromLTWH(140, 330, 920, 1090);
    var fontSize = 116.0 * scale;
    var rows = 1;
    var columns = 1;
    while (fontSize > 29) {
      rows = math.max(1, (area.height / (fontSize * 1.12)).floor());
      columns = (glyphs.length / rows).ceil();
      if (columns * fontSize * 1.13 <= area.width) break;
      fontSize -= 2;
    }
    rows = math.max(1, (area.height / (fontSize * 1.12)).floor());
    columns = (glyphs.length / rows).ceil();
    final usedWidth = columns * fontSize * 1.13;
    final startX = area.center.dx + usedWidth / 2 - fontSize;
    for (var index = 0; index < glyphs.length; index++) {
      final column = index ~/ rows;
      final row = index % rows;
      final painter = _textPainter(
        glyphs[index],
        fontSize,
        ink,
        FontWeight.w700,
      );
      painter.layout(maxWidth: fontSize * 1.2);
      painter.paint(
        canvas,
        Offset(
          startX - column * fontSize * 1.13,
          area.top + row * fontSize * 1.12,
        ),
      );
      painter.dispose();
    }
  }

  static void _paintFittedText(
    Canvas canvas,
    String text,
    Rect area,
    double preferredSize,
    Color ink, {
    required FontWeight weight,
    required TextAlign align,
  }) {
    var fontSize = preferredSize;
    TextPainter painter;
    while (true) {
      painter = _textPainter(text, fontSize, ink, weight, align: align);
      painter.layout(maxWidth: area.width);
      if (painter.height <= area.height || fontSize <= 24) break;
      painter.dispose();
      fontSize -= 2;
    }
    painter.paint(
      canvas,
      Offset(area.left, area.top + (area.height - painter.height) / 2),
    );
    painter.dispose();
  }

  static TextPainter _textPainter(
    String text,
    double fontSize,
    Color ink,
    FontWeight weight, {
    TextAlign align = TextAlign.start,
  }) => TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        color: ink,
        fontSize: fontSize,
        fontWeight: weight,
        height: 1.22,
        fontFamily: 'Noto Serif CJK SC',
        fontFamilyFallback: const ['Noto Serif CJK SC', 'Songti SC', 'serif'],
      ),
    ),
    textDirection: TextDirection.ltr,
    textAlign: align,
  );

  static _CoverPalette _palette(String value, String title) {
    const names = ['sand', 'ink', 'sea', 'wine', 'forest'];
    final name = value == 'auto'
        ? names[title.runes.fold<int>(0, (sum, rune) => sum + rune) %
              names.length]
        : value;
    return switch (name) {
      'ink' => const _CoverPalette(
        Color(0xff1c2630),
        Color(0xff314050),
        Color(0xfff3eee5),
      ),
      'sea' => const _CoverPalette(
        Color(0xffd9e8e9),
        Color(0xff84a8af),
        Color(0xff173e50),
      ),
      'wine' => const _CoverPalette(
        Color(0xffeee0dc),
        Color(0xff994e54),
        Color(0xff4b252d),
      ),
      'forest' => const _CoverPalette(
        Color(0xffdce8dc),
        Color(0xff749078),
        Color(0xff203d31),
      ),
      _ => const _CoverPalette(
        Color(0xffeee6d8),
        Color(0xffc4ad89),
        Color(0xff433426),
      ),
    };
  }
}

class PreparedCover {
  const PreparedCover({
    required this.jpeg,
    required this.thumbnail,
    required this.sourceWidth,
    required this.sourceHeight,
  });
  final Uint8List jpeg;
  final Uint8List thumbnail;
  final int sourceWidth;
  final int sourceHeight;
}

class _Decoded {
  const _Decoded(this.image, this.width, this.height);
  final ui.Image image;
  final int width;
  final int height;
}

class _CoverPalette {
  const _CoverPalette(this.background, this.panel, this.ink);
  final Color background;
  final Color panel;
  final Color ink;
}

Uint8List _encodeJpeg(Uint8List rgba) {
  final decoded = image.Image.fromBytes(
    width: BookCoverRenderer.width,
    height: BookCoverRenderer.height,
    bytes: rgba.buffer,
    bytesOffset: rgba.offsetInBytes,
    numChannels: 4,
    order: image.ChannelOrder.rgba,
  );
  return image.encodeJpg(decoded, quality: 88);
}

Uint8List _makeThumbnail(Uint8List jpeg) {
  final decoded = image.decodeJpg(
    jpeg,
    maxPixels: BookCoverRenderer.maxPixels,
  )!;
  final resized = image.copyResize(decoded, width: 240, height: 360);
  return image.encodeJpg(resized, quality: 78);
}

/// Displayed preview uses the export renderer's JPEG bytes, at a smaller size.
class BookCover extends StatefulWidget {
  const BookCover({
    super.key,
    required this.book,
    this.imageFile,
    this.fit = BoxFit.contain,
  });

  final Book book;
  final File? imageFile;
  final BoxFit fit;

  @override
  State<BookCover> createState() => _BookCoverState();
}

class _BookCoverState extends State<BookCover> {
  late Future<Uint8List> _bytes = _render();

  Future<Uint8List> _render() =>
      BookCoverRenderer.renderJpeg(widget.book, imageFile: widget.imageFile);

  @override
  void didUpdateWidget(covariant BookCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.book.meta.title != widget.book.meta.title ||
        oldWidget.book.meta.author != widget.book.meta.author ||
        oldWidget.book.coverMode != widget.book.coverMode ||
        oldWidget.book.coverAssetId != widget.book.coverAssetId ||
        oldWidget.book.coverOptions.toJson().toString() !=
            widget.book.coverOptions.toJson().toString() ||
        oldWidget.imageFile?.path != widget.imageFile?.path) {
      _bytes = _render();
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
    future: _bytes,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Center(
          child: Text(AppLocalizations.of(context).workbenchCoverUnavailable),
        );
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      return Image.memory(
        snapshot.data!,
        fit: widget.fit,
        gaplessPlayback: true,
      );
    },
  );
}
