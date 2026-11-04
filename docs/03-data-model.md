# 数据模型

## 1. 设计原则

- **一本书一份草稿**：打开书就是编辑，不再区分「解析结果」和「草稿」两个 JSON。
- **章节和内容块分离**：章节只存结构，正文按块存，天然支持图片、脚注、分页。
- **原始文件只读保留**：重新解析、换编码、恢复原文都依赖它，不覆盖。
- **数据库存引用，不存大二进制**：图片、封面、原文件放应用数据目录，SQLite 只存路径和元数据。
- **所有时间存 UTC 毫秒**，展示时转本地时区。
- **ID 用 UUID v4 字符串**：跨设备合并/备份恢复不冲突。

## 2. 实体关系

```text
Book 1 ── N Chapter 1 ── N Block
  │                         │
  │                         └── 0..1 Asset
  ├── 0..1 Source
  ├── 0..1 Cover Asset
  └── 0..1 原始导入文件
```

## 3. SQLite 表

> 下面是逻辑 schema，实际由 Drift 生成；类型以 Dart/Drift 为准。建表顺序和循环外键以 Drift 迁移为准，不要求照抄 SQL 顺序。

```sql
CREATE TABLE books (
  id                TEXT PRIMARY KEY,
  title             TEXT NOT NULL,
  author            TEXT NOT NULL DEFAULT '',
  language          TEXT NOT NULL DEFAULT 'zh-CN',
  description       TEXT NOT NULL DEFAULT '',
  series            TEXT,
  publisher         TEXT,
  tags_json         TEXT NOT NULL DEFAULT '[]',
  published_at      TEXT,              -- YYYY-MM-DD
  cover_asset_id    TEXT REFERENCES assets(id),
  chapter_count     INTEGER NOT NULL DEFAULT 0,
  word_count        INTEGER NOT NULL DEFAULT 0,
  layout_json       TEXT NOT NULL DEFAULT '{}',
  cover_options_json TEXT NOT NULL DEFAULT '{}',
  created_at        INTEGER NOT NULL,
  updated_at        INTEGER NOT NULL,
  last_opened_at    INTEGER,
  progress          REAL NOT NULL DEFAULT 0
);

CREATE TABLE sources (
  id             TEXT PRIMARY KEY,
  book_id        TEXT NOT NULL UNIQUE REFERENCES books(id) ON DELETE CASCADE,
  format         TEXT NOT NULL,        -- txt / epub / docx
  original_name  TEXT NOT NULL,
  stored_path    TEXT NOT NULL,        -- 相对 app support 目录
  byte_size      INTEGER NOT NULL,
  sha256         TEXT NOT NULL,
  created_at     INTEGER NOT NULL
);

CREATE TABLE chapters (
  id          TEXT PRIMARY KEY,
  book_id     TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
  parent_id   TEXT REFERENCES chapters(id) ON DELETE CASCADE,
  title       TEXT NOT NULL,
  level       INTEGER NOT NULL DEFAULT 2,  -- 1 卷 / 2 章
  sort_order  INTEGER NOT NULL,
  word_count  INTEGER NOT NULL DEFAULT 0,
  created_at  INTEGER NOT NULL,
  updated_at  INTEGER NOT NULL
);

CREATE TABLE blocks (
  id          TEXT PRIMARY KEY,
  chapter_id  TEXT NOT NULL REFERENCES chapters(id) ON DELETE CASCADE,
  sort_order  INTEGER NOT NULL,
  kind        TEXT NOT NULL,            -- paragraph / image / footnote / divider
  text        TEXT,                     -- 纯文字块
  asset_id    TEXT REFERENCES assets(id),
  meta_json   TEXT NOT NULL DEFAULT '{}',
  created_at  INTEGER NOT NULL
);

CREATE TABLE assets (
  id           TEXT PRIMARY KEY,
  book_id      TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
  kind         TEXT NOT NULL,           -- image / cover / font
  mime         TEXT NOT NULL,
  stored_path  TEXT NOT NULL,
  width        INTEGER,
  height       INTEGER,
  byte_size    INTEGER NOT NULL,
  sha256       TEXT NOT NULL,
  created_at   INTEGER NOT NULL
);

CREATE TABLE settings (
  key    TEXT PRIMARY KEY,
  value  TEXT NOT NULL
);
```

索引：

- `chapters(book_id, sort_order)`
- `blocks(chapter_id, sort_order)`
- `blocks(asset_id)`
- `books(updated_at DESC)`
- `assets(book_id, kind)`

全文搜索（后续）：

- 用 FTS5 建 `blocks_fts(text)`，只索引 `kind='paragraph'` 且非空内容；
- 搜索前先按 book_id 缩小范围，避免全库扫描；
- 索引可在后台重建，不阻塞打开书。

## 4. Dart 模型

```dart
enum BlockKind { paragraph, image, footnote, divider }

sealed class Block {
  final String id;
  Block(this.id);
}

final class TextBlock extends Block {
  final String text;
  TextBlock(super.id, this.text);
}

final class ImageBlock extends Block {
  final String assetId;
  final String? caption;
  final String alt;
  ImageBlock(super.id, {required this.assetId, this.caption, this.alt = ''});
}

final class Chapter {
  final String id;
  final String bookId;
  final String? parentId;
  final String title;
  final int level; // 1 卷，2 章
  final int order;
  final List<Block> blocks;
}

final class Book {
  final String id;
  final BookMeta meta;
  final List<Chapter> chapters;
  final CoverOptions coverOptions;
  final LayoutOptions layout;
}
```

### 为什么不用 `List<String> paragraphs`

现有 txt2book 用 `paragraphs: string[]`，做纯文本转换够用，但一旦支持 EPUB/DOCX 图片、脚注、分页、表格，就必须重构。Bookloom 从第一天用 Block：

- 文字块：`TextBlock`
- 图片块：`ImageBlock`（asset 引用）
- 脚注块：`FootnoteBlock`（后续）
- 分隔/分页：`DividerBlock`（后续）

TXT 导入时每个段落生成一个 `TextBlock`；导出 TXT 时把 `ImageBlock` 转成 `[插图]`，脚注转成脚注文本。

## 5. 章节与卷

- `level = 1` 表示卷，`level = 2` 表示章；暂不引入三级。
- `parentId` 指向所属卷；顶层章为 `null`。
- `sort_order` 是同级顺序，插入/移动时重排，不必连续。
- 卷本身可以没有正文；导出 EPUB 时卷标题作为第一个章节的标题页，或单独一个空章节（实现时定一种，保持稳定）。
- 章号识别与重编号逻辑复用 txt2book 的 `audit.ts` 规则，用 Dart 重写并配同样的测试语料。

## 6. 字数统计

统一规则，避免书架、导出、审计三处不一致：

- 中文按字符计，英文按单词计；空白、换行不计。
- 标点是否计入：与现有 txt2book 保持一致，先按“非空白字符”计，后续可加开关。
- 章节字数为 blocks 内文字合计；书字数为章节合计。
- 统计在保存事务里增量更新，不每次全量扫描。

## 7. 原始文件与存储布局

```text
<app-support>/books/<bookId>/
  source.<ext>          # 原始导入文件，只读
  cover.jpg             # 当前封面（可选）
  assets/<assetId>.<ext>
  thumb.jpg             # 书架缩略图 120×180
```

- 原文件默认保留；设置里可关闭（关闭后不能重新解析 / 换编码 / 恢复原文，要明确提示）。
- 导入时先复制到临时目录，校验成功后再移动到正式目录，避免半成品。
- 大文件复制在 isolate 或分块进行，显示进度。
- Android 通过 SAF 读取 content URI，复制成本地文件；不要长期持有 content URI 作为唯一来源。
- 删除书时删除整个 `books/<bookId>/`，并清理数据库级联。

## 8. 封面与排版参数

每本书的 `layout_json` / `cover_options_json` 独立保存：

```json
{
  "template": "vertical",
  "palette": "sea",
  "titleScale": 1.2,
  "authorPosition": "top"
}
```

```json
{
  "lineHeight": 1.75,
  "indent": true,
  "paragraphSpacing": 0,
  "font": "serif",
  "justify": true,
  "separateChapterNumber": false
}
```

- 旧字段缺失时用默认值归一化。
- 书架预览、导出、封面编辑共用同一个 `CoverOptions` 模型。
- 封面绘制在 `CustomPainter` 里用逻辑坐标 1200×1800；预览缩放到控件大小，导出编码 JPEG 0.92。

## 9. 备份格式

扩展名：`.bookloom`（本质是 ZIP）。

```text
manifest.json
library.json
assets/<assetId>.<ext>
sources/<bookId>/source.<ext>   # 可选，默认包含
```

`manifest.json`：

```json
{
  "format": "bookloom-backup",
  "schemaVersion": 1,
  "appVersion": "0.1.0",
  "exportedAt": "2026-11-04T10:00:00Z",
  "bookCount": 3,
  "includesSources": true
}
```

`library.json`：books / chapters / blocks / sources / assets 的数组，字段与数据库一致，不含二进制。

规则：

- 恢复时先校验 manifest 和 schemaVersion，再写入临时数据库，全部成功才替换。
- 同 ID 冲突提供「跳过 / 覆盖 / 保留两份」；默认「保留两份」并生成新 ID。
- 备份不包含日志、缓存、临时文件。
- 大库备份显示进度，可在后台 isolate 打包。

## 10. 迁移策略

- 数据库用 Drift `schemaVersion` + `MigrationStrategy`；每次升级写迁移测试。
- 备份有独立的 `schemaVersion`；恢复旧备份时先升到当前结构。
- 不删除旧字段，先标记 deprecated，跨两个版本后再清理。
- 从 txt2book 迁移（后续）：读取其导出的 JSON / IndexedDB 备份，转换为 Bookloom schema；不直接读浏览器 IndexedDB。

## 11. 一致性与并发

- 单实例：桌面用 single instance 锁；Android 单 Activity。
- 一本书同一时间只允许一个编辑会话；多窗口后续再考虑。
- 写操作使用事务；自动保存失败要保留内存状态并提示，不能静默丢。
- 删除 / 恢复备份时暂停自动保存，完成后再恢复。
