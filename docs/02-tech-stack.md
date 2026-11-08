# 技术栈

## 1. 结论

**Flutter + Dart 3 + Riverpod + Drift + 自定义格式层。**

不选 Tauri：虽然能复用现有 TypeScript，但 Android 依赖系统 WebView，Linux 依赖 WebKitGTK，移动端手势、文本选择和插件生态都要额外处理；新项目既然可以重写，就用一套自绘 UI 换三端一致性。

不选 Compose Multiplatform：Android 很强，但 Windows/Linux 的桌面分发、Linux 输入法、后续 Apple 的确定性不如 Flutter。

不选 Electron：桌面包体和内存不划算，且 Android 仍要 Capacitor 另起一个壳。

## 2. 核心技术栈

| 层 | 选择 | 说明 |
| --- | --- | --- |
| UI | Flutter stable + Material 3 | 自定义主题，不直接用默认 Material 视觉 |
| 语言 | Dart 3 | sound null safety、sealed class、patterns |
| 状态 | Riverpod | 编译期安全、易测试；不混用 provider/get_it |
| 路由 | go_router | 桌面/移动统一，支持深链 |
| 数据库 | Drift + SQLite | 类型安全、迁移、事务、FTS5 可选 |
| 文件 | file_picker + path_provider | Android 走 SAF，桌面走原生对话框 |
| 分享 | Android 原生 MethodChannel + FileProvider | 仅暴露任务导出缓存，系统分享面板打开不等于传输完成 |
| ZIP | archive | EPUB / DOCX 解压与打包 |
| XML | xml | OOXML / OPF / XHTML 解析与生成 |
| 图片 | image | 封面 JPEG 编码、尺寸处理 |
| 国际化 | flutter_localizations + gen_l10n | 先 zh-CN，后续 en |
| 日志 | logging | 本地滚动日志，默认不含正文 |
| 测试 | flutter_test + integration_test + golden | 解析器用纯 Dart 单测，UI 用 widget/golden |
| Lint | flutter_lints + 自定义 analysis_options | 禁止隐式 dynamic、未使用依赖 |

包的选择原则：

- 优先官方 / flutter.dev / 维护活跃的包；
- 锁大版本，升级前跑完整测试；
- 许可证必须允许分发（MIT / Apache-2.0 / BSD）；
- 不引入依赖云端服务的核心 SDK；可选 AI 使用自有、显式触发的 HTTP 协议适配器，不引入供应商 SDK，离线核心不依赖该配置。

## 3. 脚手架

在项目根目录执行（M0 阶段）：

```bash
flutter create \
  --org com.xiaoxura \
  --project-name bookloom \
  --platforms=android,linux,windows \
  .
```

会得到：

- Android `applicationId`: `com.xiaoxura.bookloom`
- Android `namespace`: `com.xiaoxura.bookloom`
- Linux 应用 ID / D-Bus 名：`com.xiaoxura.bookloom`
- Dart 包名：`bookloom`

后续加 Apple：

```bash
flutter create --platforms=macos,ios .
```

macOS / iOS 的 Bundle Identifier 统一设为 `com.xiaoxura.bookloom`。

## 4. 格式层的现实评估

这是项目最需要提前验证的部分。**不要假设 Dart 生态和 npm 一样成熟。**

| 能力 | 首选 | 备选 | 风险 |
| --- | --- | --- | --- |
| TXT 编码 | 纯 Dart 严格 UTF-8 / UTF-16 + 固定 WHATWG GB18030 / Big5 表 | 人工覆盖编码后重试 | 不采用只有 GBK 的库声称完整 GB18030 |
| EPUB 读 | `archive` + `xml` 自己解析 OPF/nav/NCX | `epubx` 等第三方包 | 第三方包对 EPUB 3、封面、DRM 支持参差 |
| EPUB 写 | 自己生成 OPF/XHTML/NCX + `archive` | 模板库 | 必须自己保证 EPUB 3/2 结构正确 |
| DOCX 读 | `archive` + `xml` 解析 `word/document.xml` | 第三方 docx 包 | 样式名、表格、图片、脚注复杂 |
| DOCX 写 | 最小 OOXML 包 | 第三方库 | 兼容 Word 的细节多 |
| 繁简转换 | 纯 Dart OpenCC 词典链、mmseg 分词，词典随包 | 仅有性能证据时再评估 FFI | Windows / Android 首用打包仍需设备验收 |
| 字体子集化 | harfbuzz/fonttools FFI | 暂不做，嵌整字体 | 成本高，后续再做 |
| 封面 | Flutter `CustomPainter` + `ui.Image` | `image` 画布 | JPEG 编码质量、字体渲染差异 |

建议把现有 `txt2book` 的解析/导出用例作为黄金样本移植过来，保证行为不回退。

## 5. 必须先做的技术验证

### Spike A：Flutter 三端脚手架

- Linux / Windows / Android 各跑一个空页面；
- 验证窗口最小尺寸、DPI、深色主题、文件选择、SQLite 读写；
- 记录打包产物体积。

### Spike B：中文输入法

在 Linux（fcitx5 / ibus）和 Windows 上测：

- 中文候选框位置；
- 长按/Shift 选择、复制粘贴；
- 全角标点；
- 大段文字输入延迟。

这是文字编辑器最大的隐性风险。

### Spike C：Android SAF

- 从「下载 / 文档 / 网盘」选 TXT；
- 选目录并持久授权；
- 导出到用户选择的位置；
- 应用被杀后重新授权；
- 分享 EPUB 到微信 / 邮件 / 阅读器。

### Spike D：格式往返

用三本真实书稿：

1. 纯文本 100 万字；
2. 带封面、卷章、脚注、图片的 EPUB；
3. 带 Heading 1/2、表格、图片的 DOCX。

分别测导入 → 编辑 → 导出 → 再导入，记录丢失项。

### Spike E：OpenCC

- 纯 Dart 词典方案的包体积和转换速度；
- C++/Rust FFI 在 Linux / Windows / Android 的构建；
- 是否能在不联网的情况下加载词典。

### Spike F：性能

- 100 万字分章 < 10s；
- 1,000 章目录滚动；
- 单章 5 万字预览；
- 导出 EPUB < 10s；
- 内存峰值 < 500MB。

## 6. 不建议的依赖

- 任何需要账号/云服务的富文本或转换 SDK。
- 需要 WebView 承载核心编辑器的方案（会退回 Tauri 的问题）。
- 直接依赖桌面系统 WebView 的 HTML 编辑器。
- 未维护的 EPUB/DOCX 包，除非准备 fork。

## 7. 版本与工具链

- Flutter：stable channel，团队统一版本，写入 `.fvmrc` 或文档。
- Dart：随 Flutter stable。
- Android：Gradle / AGP 跟随 Flutter 模板；当前工程继承已安装 Flutter 的 `minSdk 24`，不再沿用早期规划的 23；`targetSdk` 跟随实际锁定工具链。
- Linux：Ubuntu 22.04/24.04 与 Fedora 最新版验证；打包 AppImage + Flatpak + deb。
- Windows：Windows 10 1809+ / 11；MSIX 或 Inno Setup。
- CI：GitHub Actions，三端矩阵；Linux runner 装 GTK/CMake/Ninja，Windows runner 装 VS Build Tools，Android 用 SDK。

## 8. 决策记录

| 决策 | 结论 | 理由 |
| --- | --- | --- |
| 客户端框架 | Flutter | 三端一致、Android 强、后续 Apple 可行 |
| 不用 WebView | 是 | 避免 Linux WebKitGTK / Android WebView 差异 |
| 数据库 | SQLite + Drift | 事务、迁移、FTS、跨平台 |
| 内容模型 | Chapter → Block | 为图片、脚注、分页留扩展位 |
| 状态管理 | Riverpod | 可测试、无全局单例 |
| 初始平台 | Linux / Windows / Android | 用户目标平台 |
| Apple | 后续 | 代码保留扩展位，不阻塞 1.0 |

## 9. 本轮已锁定的基础依赖

本轮锁定 file_picker 13.3.2、archive 4.6.0、xml 7.1.0、uuid 4.6.0、image 4.12.0（MIT）及 crypto 3.0.8（BSD-3-Clause）；实际锁文件为 `pubspec.lock`。Linux / Windows 的流式保存由原生对话框返回目标后复制私有暂存文件；Android 用 ACTION_CREATE_DOCUMENT / ContentResolver 桥接。file_picker 的 bytes 保存接口不用于大备份。测试新增 Flutter SDK 自带 integration_test，不作为生产依赖。平台编译与交互证据统一记在 [本轮实施文档](development/00-native-workbench.md#143-当前实施依据与-spike-记录2026-11-05)。

TXT 编码使用 WHATWG 固定索引生成纯 Dart 常量，包含 GB18030 四字节范围与 Big5 特例；没有运行期下载，许可证与归属保留于 `licenses/whatwg/LICENSE`。OpenCC 采用官方 1.4.2 固定提交的 10 个离线词典，支持 t2s / s2twp，Apache-2.0 LICENSE / NOTICE 随包注册。算法金样通过不代表三端首用验收，实际结果仍以实施文档为准。

可选 AI 配置锁定 `flutter_secure_storage 11.2.0`（BSD-3-Clause），Linux 使用 libsecret / Secret Service，Windows 使用系统凭据存储，Android 使用平台密钥保护的专用命名空间。Linux 编译需要 libsecret 开发头文件；运行时需要可用的系统密钥环，失败不得改存明文。Android 最低版本与当前 Flutter 的 24 一致。Android 明文网络能力仅为用户主动配置的 HTTP 兼容端点开放，远程 HTTP 的确认仍由应用执行；默认关闭与无自动请求不变。凭据命名空间的三份偏好文件不参与 Android 系统备份／迁移。
