import 'dart:io';

import 'package:bookloom/core/platform/file_names.dart';
import 'package:flutter/services.dart';

/// Starting the Android chooser does not prove that another app received a file.
sealed class ShareOutcome {
  const ShareOutcome();
}

final class SharePanelOpened extends ShareOutcome {
  const SharePanelOpened();
}

final class ShareCancelled extends ShareOutcome {
  const ShareCancelled();
}

final class ShareFailed extends ShareOutcome {
  const ShareFailed(this.message);

  final String message;
}

/// Shares only a completed, app-owned export through the Android native bridge.
///
/// The bridge copies the export into its narrowly exposed share cache before
/// returning, so the export task may release its own temporary directory.
final class NativeSharingService {
  NativeSharingService({MethodChannel? channel, bool Function()? isAndroid})
    : _channel = channel ?? const MethodChannel('bookloom/sharing'),
      _isAndroid = isAndroid ?? (() => Platform.isAndroid);

  final MethodChannel _channel;
  final bool Function() _isAndroid;

  bool get isSupported => _isAndroid();

  Future<ShareOutcome> sharePreparedFile(
    File prepared, {
    required String suggestedName,
    required String mimeType,
  }) async {
    if (!isSupported) {
      return const ShareFailed('当前平台暂不支持系统分享。');
    }
    if (!await prepared.exists()) {
      return const ShareFailed('待分享的文件已不存在，请重新导出。');
    }
    final String safeName = FileNames.sanitize(suggestedName);
    if (mimeType.isEmpty || mimeType.contains(RegExp(r'[\r\n]'))) {
      return const ShareFailed('文件类型无效，无法分享。');
    }
    try {
      final String? response = await _channel.invokeMethod<String>(
        'sharePreparedFile',
        <String, String>{
          'path': prepared.absolute.path,
          'fileName': safeName,
          'mimeType': mimeType,
        },
      );
      return switch (response) {
        'opened' => const SharePanelOpened(),
        'cancelled' => const ShareCancelled(),
        _ => const ShareFailed('系统未确认分享面板已打开，请重试。'),
      };
    } on PlatformException catch (error) {
      if (error.code == 'cache_full') {
        return const ShareFailed('分享暂存空间已满，请稍后重试。');
      }
      return const ShareFailed('无法打开系统分享面板，请检查文件后重试。');
    } on MissingPluginException {
      return const ShareFailed('当前应用版本尚不支持系统分享。');
    } on Object {
      return const ShareFailed('无法准备分享文件，请重新导出后重试。');
    }
  }
}
