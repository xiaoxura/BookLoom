import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bookloom/core/io/input_limits.dart';
import 'package:bookloom/core/io/safe_xml.dart';
import 'package:bookloom/core/io/safe_zip_archive.dart';
import 'package:xml/xml.dart';

const _verificationLimits = InputLimits(
  maxArchiveBytes: 512 * 1024 * 1024,
  maxEntries: 10000,
  maxEntryBytes: 32 * 1024 * 1024,
  maxOutputBytes: 512 * 1024 * 1024,
  maxXmlBytes: 8 * 1024 * 1024,
  maxXmlDepth: 64,
  maxXmlContentCharacters: 4 * 1024 * 1024,
);

/// Checks the EPUB 3 container and its internal XML/file references.
///
/// This is a bounded structural check for Bookloom output, not an EPUBCheck
/// replacement or a promise that every reader renders the book identically.
void validateEpub(String path, {int version = 3}) {
  if (version != 2 && version != 3) {
    throw ArgumentError.value(version, 'version');
  }
  _checkFirstEntry(path);
  final zip = SafeZipArchive.open(path, limits: _verificationLimits);
  try {
    final names = <String>{for (final entry in zip.entries) entry.name};
    if (!names.contains('mimetype')) _fail('Missing mimetype');
    if (!names.contains('META-INF/container.xml')) _fail('Missing container');
    final container = zip.readXml('META-INF/container.xml');
    final roots = container
        .findAllElements('rootfile', namespaceUri: '*')
        .toList();
    if (roots.length != 1 ||
        roots.single.getAttribute('media-type') !=
            'application/oebps-package+xml') {
      _fail('Invalid rootfile declaration');
    }
    final opfPath = roots.single.getAttribute('full-path');
    if (opfPath == null || !names.contains(opfPath)) _fail('Missing OPF');
    final opf = zip.readXml(opfPath);
    if (opf.rootElement.name.local != 'package' ||
        opf.rootElement.getAttribute('version') !=
            (version == 2 ? '2.0' : '3.0')) {
      _fail('Invalid EPUB package version');
    }
    for (final requiredName in <String>['identifier', 'title', 'language']) {
      if (opf
          .findAllElements(requiredName, namespaceUri: '*')
          .every((element) => element.innerText.trim().isEmpty)) {
        _fail('Missing $requiredName metadata');
      }
    }
    final modifiedCount = opf
        .findAllElements('meta', namespaceUri: '*')
        .where(
          (element) => element.getAttribute('property') == 'dcterms:modified',
        )
        .length;
    if (modifiedCount != (version == 2 ? 0 : 1)) {
      _fail('Invalid modified timestamp metadata');
    }
    if (version == 2 &&
        opf
            .findAllElements('meta', namespaceUri: '*')
            .any(
              (element) =>
                  element.getAttribute('property') == 'belongs-to-collection',
            )) {
      _fail('EPUB 2 contains EPUB 3 collection metadata');
    }

    final manifest = <String, String>{};
    String? navPath;
    String? ncxPath;
    String? coverPath;
    for (final item in opf.findAllElements('item', namespaceUri: '*')) {
      final id = item.getAttribute('id');
      final href = item.getAttribute('href');
      final mediaType = item.getAttribute('media-type');
      if (id == null ||
          id.isEmpty ||
          href == null ||
          mediaType == null ||
          manifest.containsKey(id)) {
        _fail('Invalid manifest item');
      }
      final resolved = _resolve(opfPath, href);
      if (!names.contains(resolved)) _fail('Missing manifest resource: $href');
      manifest[id] = resolved;
      final properties = (item.getAttribute('properties') ?? '').split(' ');
      if (properties.contains('nav')) navPath = resolved;
      if (properties.contains('cover-image')) coverPath = resolved;
      if (mediaType == 'application/x-dtbncx+xml') ncxPath = resolved;
    }
    if ((version == 3 && navPath == null) ||
        (version == 2 &&
            (navPath != null || names.contains('OEBPS/nav.xhtml'))) ||
        ncxPath == null ||
        manifest.isEmpty) {
      _fail('Missing navigation or NCX');
    }
    coverPath ??= manifest['cover-image'];
    final spine = opf.findAllElements('spine', namespaceUri: '*').toList();
    if (spine.length != 1 ||
        spine.single.getAttribute('toc') == null ||
        manifest[spine.single.getAttribute('toc')] != ncxPath) {
      _fail('Invalid spine NCX reference');
    }
    final spineIds = <String>[];
    for (final item in spine.single.findElements(
      'itemref',
      namespaceUri: '*',
    )) {
      final idref = item.getAttribute('idref');
      if (idref == null || !manifest.containsKey(idref)) {
        _fail('Invalid spine itemref');
      }
      spineIds.add(idref);
    }
    if (spineIds.length < 2 ||
        spineIds[coverPath == null ? 0 : 1] != 'toc-page' ||
        (coverPath != null && spineIds.first != 'cover')) {
      _fail('Cover and table of contents spine order is invalid');
    }

    final anchors = <String, Set<String>>{};
    final references = <String>[];
    XmlDocument? nav;
    XmlDocument? toc;
    final tocPath = manifest['toc-page'];
    if (tocPath == null) _fail('Missing TOC page manifest item');
    for (final item in opf.findAllElements('item', namespaceUri: '*')) {
      if (item.getAttribute('media-type') == 'application/xhtml+xml') {
        final documentPath = manifest[item.getAttribute('id')]!;
        final document = _readXhtml(zip, documentPath, epub2: version == 2);
        if (document.rootElement.name.local != 'html') _fail('Invalid XHTML');
        anchors[documentPath] = <String>{
          for (final element in document.findAllElements(
            '*',
            namespaceUri: '*',
          ))
            if (element.getAttribute('id') case final String id) id,
        };
        for (final element in document.findAllElements(
          '*',
          namespaceUri: '*',
        )) {
          if (!<String>['a', 'link', 'img'].contains(element.name.local)) {
            continue;
          }
          final href = element.getAttribute(
            element.name.local == 'img' ? 'src' : 'href',
          );
          if (href == null) _fail('Missing XHTML resource reference');
          references.add(_resolve(documentPath, href));
        }
        if (documentPath == navPath) nav = document;
        if (documentPath == tocPath) toc = document;
      }
    }
    if ((version == 3 && nav == null) || toc == null) {
      _fail('Missing navigation XHTML');
    }
    final ncx = _readNcx(zip, ncxPath, epub2: version == 2);
    if (ncx.rootElement.name.local != 'ncx') _fail('Invalid NCX');

    final ncxTargets = <String>[
      for (final point in ncx.findAllElements('navPoint', namespaceUri: '*'))
        _resolve(
          ncxPath,
          point
                  .findElements('content', namespaceUri: '*')
                  .single
                  .getAttribute('src') ??
              '',
        ),
    ];
    final tocTargets = <String>[
      for (final link in toc.findAllElements('a', namespaceUri: '*'))
        _resolve(tocPath, link.getAttribute('href') ?? ''),
    ];
    final navTargets = <String>[];
    if (version == 3) {
      final tocNav = nav!
          .findAllElements('nav', namespaceUri: '*')
          .where(
            (element) =>
                element.getAttribute(
                  'type',
                  namespaceUri: 'http://www.idpf.org/2007/ops',
                ) ==
                'toc',
          )
          .toList();
      if (tocNav.length != 1) _fail('Missing EPUB navigation TOC');
      navTargets.addAll(<String>[
        for (final link in tocNav.single.findAllElements(
          'a',
          namespaceUri: '*',
        ))
          _resolve(navPath!, link.getAttribute('href') ?? ''),
      ]);
    }
    if (ncxTargets.isEmpty ||
        !_sameTargets(ncxTargets, tocTargets) ||
        (version == 3 && !_sameTargets(navTargets, ncxTargets))) {
      _fail('Navigation, NCX and TOC targets disagree');
    }
    for (final target in ncxTargets) {
      _checkTarget(target, names, anchors);
    }
    for (final reference in opf.findAllElements(
      'reference',
      namespaceUri: '*',
    )) {
      _checkTarget(
        _resolve(opfPath, reference.getAttribute('href') ?? ''),
        names,
        anchors,
      );
    }
    for (final target in references) {
      _checkTarget(target, names, anchors);
    }
  } finally {
    zip.close();
  }
}

XmlDocument _readXhtml(SafeZipArchive zip, String path, {required bool epub2}) {
  if (!epub2) return zip.readXml(path);
  const doctype =
      '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN" '
      '"http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">';
  final source = utf8.decode(zip.readXmlBytes(path), allowMalformed: false);
  if (!source.contains(doctype) ||
      source.contains('epub:type') ||
      source.contains('xmlns:epub')) {
    _fail('Invalid EPUB 2 XHTML');
  }
  return safeXml(source.replaceFirst(doctype, ''), limits: _verificationLimits);
}

XmlDocument _readNcx(SafeZipArchive zip, String path, {required bool epub2}) {
  if (!epub2) return zip.readXml(path);
  const doctype =
      '<!DOCTYPE ncx PUBLIC "-//NISO//DTD ncx 2005-1//EN" '
      '"http://www.daisy.org/z3986/2005/ncx-2005-1.dtd">';
  final source = utf8.decode(zip.readXmlBytes(path), allowMalformed: false);
  if (!source.contains(doctype)) _fail('Invalid EPUB 2 NCX doctype');
  return safeXml(source.replaceFirst(doctype, ''), limits: _verificationLimits);
}

void _checkFirstEntry(String path) {
  final file = File(path).openSync();
  try {
    final bytes = file.readSync(64);
    if (bytes.length < 38) _fail('Invalid ZIP local header');
    final header = ByteData.sublistView(Uint8List.fromList(bytes));
    if (header.getUint32(0, Endian.little) != 0x04034b50 ||
        header.getUint16(8, Endian.little) != 0 ||
        (header.getUint16(6, Endian.little) & 0x8) != 0) {
      _fail('Mimetype is not the first stored ZIP entry');
    }
    final nameLength = header.getUint16(26, Endian.little);
    final extraLength = header.getUint16(28, Endian.little);
    if (nameLength != 8 ||
        utf8.decode(bytes.sublist(30, 38)) != 'mimetype' ||
        header.getUint32(18, Endian.little) != 20 ||
        extraLength != 0) {
      _fail('Invalid EPUB mimetype header');
    }
    file.setPositionSync(30 + nameLength + extraLength);
    if (utf8.decode(file.readSync(20)) != 'application/epub+zip') {
      _fail('Invalid EPUB mimetype');
    }
  } finally {
    file.closeSync();
  }
}

String _resolve(String source, String href) {
  if (href.isEmpty ||
      href.startsWith('/') ||
      href.contains('\\') ||
      href.contains('?') ||
      href.contains(':')) {
    _fail('Invalid internal href: $href');
  }
  final pieces = href.split('#');
  if (pieces.length > 2) _fail('Invalid href fragment');
  final path = pieces.first;
  final fragment = pieces.length == 2 ? pieces.last : null;
  final parts = source.split('/')..removeLast();
  for (final part in path.split('/')) {
    if (part == '..') {
      if (parts.isEmpty) _fail('Href leaves EPUB root');
      parts.removeLast();
    } else if (part.isNotEmpty && part != '.') {
      parts.add(part);
    }
  }
  final target = parts.join('/');
  return fragment == null ? target : '$target#$fragment';
}

void _checkTarget(
  String target,
  Set<String> names,
  Map<String, Set<String>> anchors,
) {
  final pieces = target.split('#');
  final path = pieces.first;
  if (!names.contains(path)) _fail('Missing referenced file: $path');
  if (pieces.length == 2) {
    final ids = anchors[path];
    if (ids == null || pieces.last.isEmpty || !ids.contains(pieces.last)) {
      _fail('Missing referenced anchor: $target');
    }
  }
}

bool _sameTargets(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

Never _fail(String message) => throw FormatException('Invalid EPUB: $message');
