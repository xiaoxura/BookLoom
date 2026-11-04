# 路线图

## 1. 总览

| 里程碑 | 目标 | 预估 | 出口标准 |
| --- | --- | --- | --- |
| M0 基础与验证 | 脚手架、三端跑通、格式/输入法验证 | 1–2 周 | Linux/Windows/Android 能打开空壳；Spike A–F 有结论 |
| M1 文本核心 | TXT 导入、分章、编辑、EPUB 3 导出 | 3–4 周 | 100 万字 TXT 可完整走通；EPUB 校验通过 |
| M2 格式与成书 | EPUB/DOCX 导入、元数据、封面、EPUB 2 | 3–4 周 | 三种格式往返；封面/元数据/目录正确 |
| M3 书架与数据安全 | 书架、SQLite 迁移、备份/恢复、批量导出 | 2–3 周 | 清数据后可用备份完整恢复；批量失败可重试 |
| M4 三端发布 | Android SAF/分享、桌面打包、签名、自动更新评估 | 2–3 周 | 三端安装包可分发；核心导出结果一致 |
| M5 进阶 | 图片/脚注/表格、字体子集、i18n、Apple | 持续 | 按用户反馈排优先级 |

> 时间是单人全职的粗略估计，不含应用商店审核和签名采购。

## 2. M0：基础与验证（先做，不要跳）

### 交付

- `flutter create --org com.xiaoxura --project-name bookloom --platforms=android,linux,windows`
- 目录结构、主题、路由、Riverpod、Drift、日志、错误边界。
- `FilePickerService` / `AppPathService` 的桌面与 Android 实现。
- GitHub Actions：analyze、test、build（三端至少 Linux + Android；Windows 可先手动）。
- 测试夹具：自写样书 TXT / EPUB / DOCX 各一份，版权干净。

### Spike 清单

| 编号 | 内容 | 通过标准 |
| --- | --- | --- |
| A | 三端空壳 + 文件选择 + SQLite | 三端都能读一个 TXT 并写入数据库 |
| B | 中文输入法 | Linux fcitx5/ibus、Windows 输入无候选框错位/丢字 |
| C | Android SAF | 选文件、选目录、导出、重启后授权仍可用 |
| D | 格式往返 | 三份样书导入导出后主要结构不丢 |
| E | OpenCC | 纯 Dart 或 FFI 方案至少一种在三端可构建 |
| F | 性能基准 | 100 万字分章 < 10s，内存峰值有记录 |

### 不做

- 不做最终视觉稿；
- 不做批量、书架高级功能；
- 不接 Apple；
- 不为“以后可能用”引入 Rust。

## 3. M1：文本核心

### 范围

- TXT 编码探测：BOM、UTF-8 有效性、GB18030、Big5、UTF-16。
- 分章引擎：移植 txt2book 的标题形态 + 密度评分、卷/章、目录页剔除、空行兜底。
- 编辑：标题、合并、拆分、删除、升降级、搜索、章节跳转。
- 撤销/重做：命令栈，最多 50 步，批量操作合并。
- 自动保存 + 崩溃恢复。
- EPUB 3 导出：封面、nav、NCX、内嵌目录页、元数据基础字段。
- 基础书架（先单本也能用，多本预留）。

### 验收

- 100 万字 TXT 导入 10s 内可编辑；
- 分章结果与 txt2book 的黄金用例一致；
- EPUB 3 通过 epubcheck（或等价结构校验）；
- 连续 20 次编辑可逐步撤销/重做；
- 杀进程后重开，最近一次自动保存不丢。

## 4. M2：格式与成书

### 范围

- EPUB 导入：spine、nav/NCX、封面、书名/作者、简介/系列/出版社/标签/日期。
- DOCX 导入：Heading 1/2、中文「标题 1/2」、outlineLvl；无样式退化为单章。
- 元数据编辑与 EPUB 输出（dc:*、belongs-to-collection）。
- 封面编辑器：竖排/色块、5 套配色、字号、作者位置、实时预览。
- EPUB 2 导出：XHTML 1.1 + NCX，去掉 EPUB 3 专有字段。
- DOCX / 单文件 HTML / TXT / Markdown 导出。

### 验收

- 带封面、卷章、元数据的 EPUB 导入再导出，结构不丢；
- EPUB 3 的系列/简介/标签可被 Calibre 读取；
- DOCX 在 Word 打开无修复提示；
- 封面预览与导出 JPEG 视觉一致；
- EPUB 2 在旧阅读器（如文石/Kobo）打开正常。

## 5. M3：书架与数据安全

### 范围

- 多书书架：封面、标题、作者、字数、更新时间、最近打开。
- 搜索书架；按更新时间/书名排序。
- 删除、重命名、复制一本书。
- 备份 / 恢复 `.bookloom` ZIP（含原文可选）。
- 批量导入 / 批量导出 / 失败重试。
- 数据库迁移框架与迁移测试。
- 本地占用统计。

### 验收

- 20 本书切换无丢数据；
- 清空应用数据后，用备份恢复书籍、章节、封面、元数据；
- 批量 10 本中 1 本失败，其余成功且失败可单独重试；
- 旧 schema 备份可升级恢复。

## 6. M4：三端发布

### 范围

- Android：SAF 目录、分享、软键盘适配、返回键、后台恢复。
- Linux：AppImage / Flatpak / deb；桌面菜单、窗口状态。
- Windows：MSIX 或 Inno Setup；高 DPI；文件关联（可选）。
- 统一空状态、错误提示、首次使用引导。
- 性能优化：列表虚拟化、图片缩略图、导出进度。
- 自动更新评估：Android 走商店；桌面先做“检查新版本 + 打开下载页”。

### 验收

- 三端安装包在干净环境可安装、启动、导入、导出；
- Android 从系统文件管理器“打开方式”能导入；
- 桌面包卸载后用户数据默认保留（明确提示）；
- 无网络环境完整可用。

## 7. M5：进阶（按反馈排序）

- 图片 / 脚注 / 表格（Block 模型已预留）。
- 字体子集化（harfbuzz/fonttools）。
- 英文界面（gen_l10n）。
- macOS / iOS（Bundle ID 已预留）。
- 跨书全文搜索（FTS5）。
- 阅读进度、最近阅读、书签。
- 导出预设 / 系列模板。
- 与 Calibre 目录互操作。

## 8. 风险台账

| 风险 | 概率 | 影响 | 缓解 |
| --- | --- | --- | --- |
| Flutter Linux 中文输入法问题 | 中 | 高 | M0 Spike B；必要时接 GTK IM 或调整输入组件 |
| Dart EPUB/DOCX 库不成熟 | 高 | 高 | 自己用 archive+xml 实现；移植 txt2book 测试 |
| OpenCC FFI 三端构建困难 | 中 | 中 | 先纯 Dart 词典；FFI 作为优化；不阻塞 1.0 |
| Android SAF 兼容性 | 中 | 高 | M0 Spike C；保留“复制到应用目录”兜底 |
| 大书内存/滚动性能 | 中 | 高 | Block 分页、ListView.builder、isolate、懒加载 |
| 桌面打包/签名成本 | 高 | 中 | 先提供未签名安装包；后续再买证书 |
| 字体渲染/度量差异 | 中 | 中 | 统一内置字体；封面用固定字体；golden 测试 |
| 范围膨胀 | 高 | 高 | 严格按 M0–M4 验收；图片/i18n 放 M5 |

## 9. 第一轮任务（M0 可直接开工）

> 进度（2026-11-04）：脚手架、设计系统、数据层骨架、CI 已完成，见 [设计系统](07-design-system.md)。

- [x] 1. `flutter create` 并提交初始脚手架（Flutter 3.47.9，`--platforms=android,linux,windows`）。
- [x] 2. 建立 `lib/core/model/`：`book.dart`、`chapter.dart`、`block.dart`、`metadata.dart`、`cover_options.dart`、`layout_options.dart`。
- [x] 3. 建 SQLite + Drift 表：books/chapters/blocks/sources/assets/settings，含外键与索引。
- [ ] 4. 实现 `FilePickerService` 桌面版，Android 版留接口。
- [ ] 5. 写一个“导入 TXT → 显示章节列表”的竖切。
- [ ] 6. 写 10 个分章黄金用例（从 txt2book 搬）。
- [ ] 7. 在 Linux 和 Windows 上各跑一次，记录输入法问题。
- [ ] 8. 在 Android 真机/模拟器上跑一次 SAF 选文件。
- [x] 9. 建立 CI（analyze + test + Linux 构建）。
- [ ] 10. 把 Spike A–F 结论写回本文档。

已完成但原清单未列的：设计 token 与主题（`lib/design/`）、玻璃壳层、设置页外观开关、`/design` 预览页、22 个单测/widget 测试、日志与错误边界。

## 10. 发布节奏

- `0.1.0`：M0–M1 完成，文本核心可用。
- `0.2.0`：M2 完成，格式与成书。
- `0.3.0`：M3 完成，书架与备份。
- `1.0.0`：M4 完成，三端正式版。
- M5 功能按 minor 递进；不为了版本号赶功能。
