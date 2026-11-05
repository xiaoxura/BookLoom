import 'dart:io';

import 'package:bookloom/core/platform/app_paths.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

enum AccessDirectory { support, books, cache }

/// An observation of one app-owned directory, never an external SAF target.
final class DirectoryAccessCheck {
  const DirectoryAccessCheck(
    this.target,
    this.readable,
    this.writable, {
    this.failureKind,
  });

  final AccessDirectory target;
  final bool readable;
  final bool writable;
  final String? failureKind;
}

final class RuntimePermissionCheck {
  const RuntimePermissionCheck(this.name, this.label, this.granted);

  final String name;
  final String label;
  final bool granted;
}

final class PlatformPermissionReport {
  PlatformPermissionReport({
    required this.android,
    required this.systemCheckAvailable,
    required List<RuntimePermissionCheck> runtimePermissions,
    required this.declaresInternet,
    required this.declaresBroadStorage,
  }) : runtimePermissions = List.unmodifiable(runtimePermissions);

  final bool android;
  final bool systemCheckAvailable;
  final List<RuntimePermissionCheck> runtimePermissions;
  final bool declaresInternet;
  final bool declaresBroadStorage;
}

/// Checks app-owned directories and reads Android's installed permission state.
class PermissionAccess {
  PermissionAccess({MethodChannel? channel, bool Function()? isAndroid})
    : _channel = channel ?? const MethodChannel('bookloom/permissions'),
      _isAndroid = isAndroid ?? (() => Platform.isAndroid);

  final MethodChannel _channel;
  final bool Function() _isAndroid;

  Future<List<DirectoryAccessCheck>> checkDirectories(AppPaths paths) async {
    return <DirectoryAccessCheck>[
      await _checkDirectory(AccessDirectory.support, paths.support),
      await _checkDirectory(AccessDirectory.books, paths.books),
      await _checkDirectory(AccessDirectory.cache, paths.cache),
    ];
  }

  Future<DirectoryAccessCheck> _checkDirectory(
    AccessDirectory target,
    Directory directory,
  ) async {
    try {
      final type = await FileSystemEntity.type(
        directory.path,
        followLinks: false,
      );
      if (type == FileSystemEntityType.notFound) {
        return DirectoryAccessCheck(
          target,
          false,
          false,
          failureKind: 'missing',
        );
      }
      if (type != FileSystemEntityType.directory) {
        return DirectoryAccessCheck(
          target,
          false,
          false,
          failureKind: 'not_directory',
        );
      }
    } on FileSystemException {
      return DirectoryAccessCheck(
        target,
        false,
        false,
        failureKind: 'check_failed',
      );
    }

    var readable = false;
    var writable = false;
    String? failureKind;
    try {
      // Listing one entry checks directory access without opening book data.
      await directory.list(followLinks: false).take(1).toList();
      readable = true;
    } on FileSystemException {
      failureKind = 'read_failed';
    }

    Directory? probe;
    try {
      probe = await directory.createTemp('.bookloom-access-');
      final marker = File(p.join(probe.path, 'probe'));
      const content = 'bookloom access probe\n';
      await marker.writeAsString(content, flush: true);
      if (await marker.readAsString() != content) {
        throw const FileSystemException('Probe content mismatch');
      }
      writable = true;
    } on FileSystemException {
      failureKind ??= 'write_failed';
    } finally {
      if (probe != null) {
        try {
          await probe.delete(recursive: true);
        } on FileSystemException {
          writable = false;
          failureKind = 'cleanup_failed';
        }
      }
    }
    return DirectoryAccessCheck(
      target,
      readable,
      writable,
      failureKind: failureKind,
    );
  }

  Future<PlatformPermissionReport> inspectSystemPermissions() async {
    if (!_isAndroid()) return _unavailable(android: false);
    try {
      final response = await _channel.invokeMethod<Object?>(
        'inspectPermissions',
      );
      if (response is! Map) return _unavailable(android: true);
      final permissions = response['runtimePermissions'];
      final internet = response['declaresInternet'];
      final storage = response['declaresBroadStorage'];
      if (permissions is! List || internet is! bool || storage is! bool) {
        return _unavailable(android: true);
      }
      final runtimePermissions = <RuntimePermissionCheck>[];
      for (final item in permissions) {
        if (item is! Map ||
            item['name'] is! String ||
            item['label'] is! String ||
            item['granted'] is! bool ||
            (item['name'] as String).isEmpty ||
            (item['label'] as String).isEmpty) {
          return _unavailable(android: true);
        }
        runtimePermissions.add(
          RuntimePermissionCheck(
            item['name'] as String,
            item['label'] as String,
            item['granted'] as bool,
          ),
        );
      }
      return PlatformPermissionReport(
        android: true,
        systemCheckAvailable: true,
        runtimePermissions: runtimePermissions,
        declaresInternet: internet,
        declaresBroadStorage: storage,
      );
    } on Object {
      return _unavailable(android: true);
    }
  }

  Future<bool> openSystemSettings() async {
    if (!_isAndroid()) return false;
    try {
      return await _channel.invokeMethod<bool>('openSystemSettings') == true;
    } on Object {
      return false;
    }
  }

  PlatformPermissionReport _unavailable({required bool android}) {
    return PlatformPermissionReport(
      android: android,
      systemCheckAvailable: false,
      runtimePermissions: const <RuntimePermissionCheck>[],
      declaresInternet: false,
      declaresBroadStorage: false,
    );
  }
}
