# 架构设计

## 1. 总览

```text
┌─────────────────────────────────────────────┐
│ Flutter UI                                  │
│  features: library / import / editor /      │
│            preview / export / settings      │
├─────────────────────────────────────────────┤
│ Application                                 │
│  Riverpod controllers, commands, state      │
├─────────────────────────────────────────────┤
│ Domain / Core (pure Dart)                   │
│  model, parsing, formatting, validation,    │
│  EPUB/DOCX builders, cover geometry         │
├─────────────────────────────────────────────┤
│ Infrastructure                              │
│  SQLite/Drift, files, isolates, platform    │
│  adapters, FFI (Rust/C++ when needed)       │
└─────────────────────────────────────────────┘
```

依赖方向只能向下：

- UI 依赖 Application；
- Application 依赖 Domain；
- Domain 不依赖 Flutter、SQLite、文件系统；
- Infrastructure 实现 Domain 定义的接口，由 Application 注入。

这样解析、导出、章号算法都能用纯 Dart 单测覆盖，换存储或加 FFI 不影响业务层。

## 2. 目录结构

```text
lib/
  main.dart
  app/
    bootstrap.dart          # 初始化数据库、日志、平台服务
    app.dart                # MaterialApp.router + 画布 + 滚动行为
    router.dart             # go_router + StatefulShellRoute
    providers.dart          # 全局 provider（数据库、设置、外观）
    error_handling.dart     # 全局错误处理
    shell/app_shell.dart    # 纸面侧栏 / 底部导航
  features/
    library/
      data/                 # 书架 repository
      domain/
      presentation/
    import/
      data/                 # 文件选择、编码探测
      domain/
      presentation/
    editor/
      data/
      domain/
      presentation/
    preview/
    export/
    settings/
    design_system/          # /design 预览页（非产品页面）
  design/
    tokens/                 # 颜色、字体、间距、圆角、动效
    theme/                  # AppTheme + ThemeExtension
    components/             # PaperSurface / AppPage / EmptyState / BookPlate
  core/
    model/
      book.dart
      chapter.dart
      block.dart
      metadata.dart
      cover_options.dart
    parsing/
      txt/
      epub/
      docx/
      chapters/             # 章节识别评分
    conversion/
      opencc/               # FFI 或纯 Dart 词典
    formatting/
      epub/
      docx/
      html/
      markdown/
      txt/
    storage/
      database.dart         # Drift
      repositories/
      backup/
    platform/
      files.dart            # 抽象接口
      paths.dart
      share.dart
      system_fonts.dart
      background_tasks.dart
    utils/
  l10n/
test/
  core/
  features/
  fixtures/                 # 小体积、版权干净的样书
integration_test/
```

Feature 内部按 `data / domain / presentation` 分，但不要为了分层而分层：小功能可以只有 `presentation + repository`。

## 3. 应用状态

- 使用 **Riverpod**，不引入 `get_it` / `provider` 混搭。
- 表单态放本地 `StatefulWidget` 或 `Notifier`；跨页面共享的书籍、书架、设置放 provider。
- 大章节正文不要放进全局不可变 state 的深拷贝里；编辑器直接操作当前草稿 repository，UI 订阅摘要和版本号。
- 命令（导入、导出、批量）用 `AsyncNotifier` / `Command` 封装，统一处理 loading、取消、错误。

### 自动保存

1. 用户编辑 → 标记 dirty；
2. 800–1200ms debounce；
3. 在事务里写回当前章节的 blocks 和 book 摘要；
4. 保存成功清 dirty，失败保留并提示；
5. 应用进入后台 / 关闭窗口前强制 flush。

不要每次按键都写 SQLite；也不要等退出才保存。

## 4. 平台适配

Domain 只定义接口，Infrastructure 提供实现：

```dart
abstract interface class FilePickerService {
  Future<List<PickedFile>> pickImportFiles();
  Future<String?> pickSavePath({required String suggestedName});
  Future<String?> pickDirectory();
}

abstract interface class AppPathService {
  Future<Directory> booksDir();
  Future<Directory> cacheDir();
}
```

| 能力 | Linux / Windows | Android |
| --- | --- | --- |
| 选文件 | file_picker | SAF（file_picker） |
| 保存 | 原生保存对话框 | SAF 创建文档 |
| 目录 | 直接路径 | 用户选择的 tree URI，持久授权 |
| 分享 | 系统分享（可选） | share_plus |
| 后台任务 | isolate + 窗口存活 | 前台服务（后续） |
| 系统字体 | 读取字体目录 | 暂不支持/受限 |

平台差异只能在 `core/platform` 和少量 UI 适配里出现，解析/导出代码不判断 `Platform.isAndroid`。

## 5. Isolate 与重任务

以下任务放 `Isolate.run` 或长驻 worker isolate：

- TXT 编码探测 + 分章（大文件）；
- EPUB / DOCX 解压、XML 解析、图片抽取；
- 批量替换 / 全书扫描；
- EPUB / DOCX / ZIP 打包；
- 封面 JPEG 编码（可留主 isolate，1200×1800 很快）。

消息协议：

```dart
sealed class WorkerRequest {}
final class ParseTxtRequest extends WorkerRequest { ... }
final class PackEpubRequest extends WorkerRequest { ... }

sealed class WorkerResponse {}
final class Progress extends WorkerResponse { ... }
final class ParseDone extends WorkerResponse { ... }
final class WorkerError extends WorkerResponse { ... }
```

约束：

- 传给 isolate 的数据必须可发送；大 `Uint8List` 避免多次复制。
- 每个请求带 `jobId`，支持取消（协作式检查）。
- 错误带阶段和可展示文案，不能只抛 `Exception`。
- UI 不直接持有 isolate；由 repository 管理生命周期。

## 6. 导入数据流

```text
用户选文件
  → 复制到应用数据目录（原始文件保留）
  → 识别格式（扩展名 + ZIP 内容）
  → 解析为 BookDraft（meta + chapters + blocks + assets）
  → 写入 SQLite（事务）
  → 打开编辑器
```

- 原文件永远不修改；导入后保留只读副本，供“恢复原文 / 重新解析”使用。
- 解析失败时不要创建半成品书；临时数据先放内存/临时目录，成功后提交。
- 结构化格式（EPUB/DOCX）默认不再让用户改编码；TXT 才显示编码选项。

## 7. 导出数据流

```text
当前 Book
  → 读取 chapters + blocks + assets + meta + layout + cover
  → 生成目标格式字节
  → 写到临时文件或 SAF
  → 成功后提示路径 / 分享
```

- 导出不修改数据库；导出失败不能丢草稿。
- 批量导出串行执行，单本失败不阻塞后续，最后汇总失败列表。
- EPUB 3 / 2 共用文档生成器，只在包结构、nav、`epub:type` 上分支。
- 所有导出器接收同一份 `ExportSnapshot`，避免各自读状态。

## 8. 错误模型

```dart
sealed class AppFailure {
  final String message;
  final Object? cause;
  final StackTrace? stackTrace;
}
final class ImportFailure extends AppFailure {}
final class ExportFailure extends AppFailure {}
final class StorageFailure extends AppFailure {}
final class ValidationFailure extends AppFailure {}
```

- 用户看到中文可操作提示；日志保留技术细节。
- 导入/导出错误要带「下一步」：换编码、换 EPUB 2、检查文件是否加密、释放空间等。
- 不用 `catch (e) {}` 静默吞错；可恢复场景要 toast + 日志。

## 9. 可选 Rust / C++ 边界

第一版不引入 Rust。只有以下情况才加 FFI：

- OpenCC 的 Dart 方案体积/性能不可接受；
- 字体子集化需要 harfbuzz/fonttools；
- EPUB/DOCX 解析在百万字级别成为瓶颈。

约定：

- FFI 代码放 `native/`，通过 `flutter_rust_bridge` 或 C ABI；
- 输入输出用字节/JSON，不让 Rust 依赖 Flutter；
- 每个平台都提供构建产物，CI 覆盖 Linux / Windows / Android；
- 纯 Dart 路径保留为 fallback 和测试基准。

## 10. 安全与隐私

- 默认不发网络请求；可选 AI 适配器使用平台网络能力（Android 主包声明 INTERNET），配置默认关闭，只有用户主动测试或授权分析时才可请求。网络权限不等于后台联网或书稿上传授权。远程明文 HTTP 必须另行确认，循环回送 HTTP 供本机兼容服务使用。
- AI 密钥仅进入平台安全存储，不写入 SQLite、日志或书架备份；Android 排除该命名空间的系统备份与设备迁移。系统密钥环不可用时明确失败，不降级明文。
- 不记录书稿内容到日志；错误日志只记录文件名、格式、大小、错误类型。
- 备份文件由用户主动导出，不自动上传。
- 解析 ZIP 时防 Zip Slip、路径穿越、超大解压比（zip bomb）。
- EPUB / DOCX 的 XML 解析禁止外部实体（XXE）。
- 导入文件先复制到受控目录，不直接执行/打开原路径。
