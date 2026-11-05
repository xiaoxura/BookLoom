# 开发指南

## 1. 环境要求

### 通用

- Flutter stable（团队统一版本，建议用 FVM 固定）
- Dart 3（随 Flutter）
- Git
- 一个能跑 Android 模拟器/真机的环境

### Linux

```bash
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev
```

打包 AppImage / deb 时再装对应工具；Flatpak 需要 `flatpak` 与 `flatpak-builder`。

### Windows

- Visual Studio 2022 Build Tools，勾选「使用 C++ 的桌面开发」（含 MSVC、CMake、Ninja）
- Windows 10/11 SDK（随上面的工作负载安装）
- 开启开发者模式（调试）

装 VS 时不必装 IDE 本体，只装 Build Tools 即可；`flutter doctor -v` 能列出 MSVC 与 SDK 版本就说明就绪。

桌面构建还依赖两处平台能力，缺一个都会在构建前失败：

- **插件符号链接**：Flutter 在 `windows/flutter/ephemeral/.plugin_symlinks/` 建符号链接。未开开发者模式时 `flutter pub get` 之后会报 `Building with plugins requires symlink support`。开发者模式开关写在用户登录令牌里，**开启后需要重新登录或重启**才对已运行的会话生效。
- **注册表探测**：Flutter 用 `reg query` 定位 Windows SDK 的 `InstallationFolder`，再把 SDK 的 `INCLUDE`/`LIB` 交给 `native_toolchain_c` 编译 `sqlite3`、`nativeapi` 等原生资产。若 `reg.exe` 被安全软件或策略拦截，原生资产会以 `fatal error C1083: 无法打开包括文件: windows.h` 失败。

构建：

```bash
flutter build windows --release   # 产物在 build/windows/x64/runner/Release/
```

### Android

- Android Studio（含 SDK、platform-tools、emulator）
- JDK 使用 Android Studio 自带版本
- 真机比模拟器更能暴露 SAF、输入法、内存问题

检查：

```bash
flutter doctor -v
flutter devices
```

## 2. 初始化

在 `/home/xiaoxura/Code/bookloom`：

```bash
flutter create \
  --org com.xiaoxura \
  --project-name bookloom \
  --platforms=android,linux,windows \
  .
```

然后按 M0 需要加依赖（版本以当时 stable 为准，不要盲目追新）：

```bash
flutter pub add flutter_riverpod go_router drift drift_flutter path_provider file_picker archive xml image share_plus intl logging
flutter pub add --dev drift_dev build_runner flutter_lints
dart run build_runner build --delete-conflicting-outputs
```

说明：

- Drift 的表和 DAO 用 `build_runner` 生成；生成文件是否提交团队内统一（建议提交，保证 checkout 即可构建）。
- 不要为了“以后可能用”提前引入 Rust、FFI、字体子集化依赖。
- 每个新依赖记录到 `docs/02-tech-stack.md` 的选型表，并确认许可证。

## 3. 常用命令

```bash
flutter pub get
dart format lib test
flutter analyze
flutter test
dart run build_runner watch --delete-conflicting-outputs

flutter run -d linux
flutter run -d windows
flutter run -d <android-device-id>

flutter build linux --release
flutter build windows --release
flutter build apk --release --split-per-abi
```

## 4. 编码规范

- 文件/目录：`snake_case`；类/枚举：`PascalCase`；变量/方法：`camelCase`。
- 禁止 `print`；用 `logging`，日志不写正文。
- 禁止无类型 `dynamic`；JSON 解析显式转换。
- 业务错误用 `AppFailure` 子类，不把 `Exception('...')` 直接抛到 UI。
- 一个文件只放一个主要公开类；超过 400 行考虑拆分。
- import 使用 `package:bookloom/...`，不跨 feature 走相对路径。
- 不在 widget 里做解析/导出；调用 application 层。
- UI 文案走 `l10n`（即使先只有中文），避免以后全量替换。
- 颜色、间距、字号走主题 token，不散落魔法值。

### 提交规范

Conventional Commits：

```text
feat(import): 支持 GB18030 手动切换
fix(export): 修正 EPUB 2 的 NCX 层级
refactor(core): 拆分章节识别评分
docs: 补充应用 ID 说明
test(cover): 增加封面配色 golden
```

分支：`main` 保持可构建；功能用 `feat/xxx`，合并前 squash 或保持清晰提交。

## 5. 分层约定

```text
features/xxx/presentation  → 只能依赖 application/domain
features/xxx/data          → 实现 repository，依赖 core/storage
core/domain                → 纯 Dart，无 Flutter import
core/platform              → 接口 + 平台实现
```

- `core` 不 import `flutter/material.dart`；封面绘制放 `features/cover` 或 `core/rendering` 的 Flutter 子目录。
- Repository 接口放 domain，Drift 实现放 data。
- 解析器返回 `ParseResult`，不直接写数据库；由 application 决定事务。
- 导出器接收 `ExportSnapshot`，不读全局 state。

## 6. 测试

### 单元测试

重点覆盖：

- 编码探测（UTF-8/GBK/Big5/UTF-16 边界）；
- 章节识别（卷/章、目录页、空行、英文 Section）；
- 章号解析与重编号；
- 替换/审计规则；
- EPUB / DOCX / HTML 输出结构；
- 备份 manifest 校验与迁移；
- 封面参数归一化与配色。

### Widget / Golden

- 书架空状态、章节列表、元数据表单、封面编辑器；
- 固定字体、固定尺寸，避免 CI 字体差异；
- Golden 只覆盖稳定视觉，不追每个像素。

### 集成测试

至少三端各一条：

```text
启动 → 导入 fixtures/sample.txt → 改标题 → 导出 EPUB → 文件存在
```

Android 另测 SAF 选文件/目录；Linux/Windows 测原生保存对话框。

### 性能基准

在 `benchmark/` 放脚本或测试：

- 100 万字 TXT 导入耗时；
- 1,000 章列表构建；
- 5 万字单章渲染；
- EPUB 导出耗时与内存峰值。

记录在 `docs/performance.md`，每次大改前后对比。

## 7. CI

GitHub Actions 示例（M0 先跑 Linux analyze/test，再补矩阵）：

```yaml
name: ci
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
      - run: flutter pub get
      - run: dart run build_runner build --delete-conflicting-outputs
      - run: flutter analyze
      - run: flutter test
```

后续加：

- ~~`build-linux`：安装 GTK/CMake 依赖，`flutter build linux`；~~ 已接入
- ~~`build-windows`：`windows-latest` + VS Build Tools；~~ 已接入
- `build-android`：JDK + Android SDK，`flutter build apk --debug`；
- 产物上传，PR 保留 7 天。

Windows 桌面构建把三个平台的差异都串起来了：MSVC 工具链、开发者模式下的符号链接、`reg query` 探测 SDK。`windows-latest` 运行器已具备这三项，本地复现路径见 §1「Windows」。

CI 不跑真实设备 smoke；三端手工验收另建清单。

## 8. 从 txt2book 移植

现有 Web 项目的逻辑可以作为行为参考和黄金用例，但不要逐行翻译。

| txt2book | Bookloom | 说明 |
| --- | --- | --- |
| `src/core/chapters.ts` | `core/parsing/chapters` | 标题评分、卷章、目录剔除；先搬测试 |
| `src/core/audit.ts` | `core/validation/audit` | 缺号、重复、空章、长短章 |
| `src/core/replace.ts` | `core/editing/replace` | 正则、范围、预算 |
| `src/core/history.ts` | `core/editing/history` | 命令栈，最多 50 步 |
| `src/core/export/epub.ts` | `core/formatting/epub` | EPUB 3/2、nav/NCX、内嵌目录 |
| `src/core/import/docx.ts` | `core/parsing/docx` | Heading 映射、单章退化 |
| `src/core/import/epub.ts` | `core/parsing/epub` | spine/nav/NCX、封面、元数据 |
| `src/core/cover.ts` | `features/cover` + `CustomPainter` | 配色、字号、作者位置 |
| `src/core/draft.ts` | `core/storage` + Drift | 书架、草稿、原文、字体 |
| `src/core/convert.ts` | `core/conversion/opencc` | 先验证 Dart/FFI 方案 |

移植顺序：**先测试后实现**。把 txt2book 的测试输入/期望输出复制成 Dart fixture，再写实现；这样能快速发现行为差异。

## 9. 性能与内存

- 大书不要在内存里保留多份完整 `List<Chapter>` 深拷贝。
- 编辑器只加载当前章 blocks；目录只加载标题和 id。
- 列表用 `ListView.builder` / `SliverList`；禁止 `SingleChildScrollView` 包 1,000 章。
- 导出时逐章生成，避免把整个 EPUB 的所有 XHTML 同时留在内存。
- 图片生成缩略图，正文按需解码；不要把所有原图常驻。
- 自动保存用事务 + 增量更新，不每次全表重写。
- Isolate 之间传 `Uint8List` 时注意复制成本；必要时用 `TransferableTypedData`。

## 10. 安全与隐私检查

- 无网络依赖；新增网络能力必须走设计评审。
- ZIP 解压限制总大小、单文件大小、路径穿越。
- XML 解析禁用外部实体。
- 文件名 sanitize，不直接拼接用户输入到路径。
- 备份恢复前校验 schema，不执行任意代码。
- 日志不写正文、不写完整文件路径（可写文件名 + 大小）。

## 11. Definition of Done

一个功能完成需要：

- [ ] 有单元测试或集成测试；
- [ ] `flutter analyze` 0 issue；
- [ ] 三端至少手动验证目标平台；
- [ ] 错误提示可操作，不是裸异常；
- [ ] 不引入网络/账号依赖；
- [ ] 文档和 CHANGELOG 更新；
- [ ] 性能和内存无明显回退。

## 12. M0 第一周清单

- [ ] `flutter create` + 初始目录
- [ ] 主题、路由、Riverpod、Drift 最小闭环
- [ ] `Book` / `Chapter` / `Block` 模型
- [ ] 文件选择 + TXT 读取 + 章节列表竖切
- [ ] 10 个分章黄金用例
- [ ] CI（analyze + test）
- [ ] Linux / Windows 输入法记录
- [ ] Android SAF 选文件记录
- [ ] 把 Spike 结论写回 `docs/04-roadmap.md`
