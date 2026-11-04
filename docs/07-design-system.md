# 设计系统

> 这一页决定 Bookloom 长什么样。所有颜色、字体、间距、圆角、动效都从 `lib/design/tokens/` 出发；页面里不应该出现魔法值。

![书架 · 浅色](design/home-light.png)

## 1. 目标与原则

1. **像一张纸，不像一块屏幕**：暖白纸面、墨色文字、极细的分隔线；信息密度服从阅读节奏。
2. **结构优先**：字号层级和间距先立住，装饰后放。避免渐变按钮、发光卡片、大面积高饱和色。
3. **玻璃是点缀，不是主题**：只有侧栏、浮层、对话框允许磨砂；正文永远落在不透明纸面。
4. **一处改，全站变**：换配色或字体，只改 token；页面组件不覆写主题。
5. **桌面与移动共享一套语言**：同一组 token、同一套组件，只切换壳层布局。

## 2. 为什么玻璃只做浮层

磨砂半透明（frosted glass）在 Flutter 里的真实成本与限制，决定了它只能当点缀：

| 问题 | 说明 | 我们的对策 |
| --- | --- | --- |
| 性能 | 每块 `BackdropFilter` 都要对背景做一次模糊；大面积、滚动中、多层叠加会掉帧 | 只给少量静态浮层用；圆角裁剪 + `RepaintBoundary` |
| 可读性 | 背景越花，文字对比越低；长文校对最忌讳灰底灰字 | 玻璃 tint 不透明度保持 ≥ 0.46（浅）/ 0.50（深），正文不放玻璃上 |
| 平台一致性 | Flutter 只能模糊「应用内」内容，做不到 Windows Mica / macOS Vibrancy 那种窗口级透明；Linux 上也没有原生毛玻璃 | 不承诺「透出桌面」，只做应用内层次 |
| 可降级 | 低端机、远程桌面、无障碍「减少透明度」 | `GlassQuality.off` 自动退化为不透明纸面，代码零改动 |
| 测试稳定 | 模糊结果依赖 GPU | 截图基准只覆盖不透明状态；golden 里关闭玻璃 |

结论：**玻璃用来提示「这是浮在上面的东西」**（侧栏、底部导航、弹出菜单、对话框），不用来表达品牌，也不用来承载正文。

## 3. Token 地图

```
lib/design/
  tokens/
    app_colors.dart      # 语义色板（light / dark）
    app_typography.dart  # 字体栈与字号级别
    app_metrics.dart     # 间距、圆角、动效、布局常量
    glass.dart           # 磨砂参数（质量档位）
  theme/
    app_tokens.dart      # ThemeExtension：context.colors / context.glass
    app_theme.dart       # Material 组件统一主题
  components/
    app_canvas.dart      # 纸面底色 + 墨晕
    app_surface.dart     # 透明 Scaffold（提供 Material / SnackBar host）
    glass_surface.dart   # 磨砂面板
    app_page.dart        # 页面骨架：标题 / 副标题 / 操作区
    empty_state.dart     # 空状态
    book_plate.dart      # 无封面时的书封占位
```

页面里读色：

```dart
final colors = context.colors;   // AppColors
final glass = context.glass;     // GlassTokens
```

## 4. 色彩

浅色以暖纸为底，深色是暖黑；主色是克制的靛青，朱砂只用于危险与提示。

| 语义 | 浅色 | 深色 | 用途 |
| --- | --- | --- | --- |
| `canvas` | `#F1EBDF` | `#121110` | 页面底色（渐变底部） |
| `canvasAlt` | `#FBF7EF` | `#1A1815` | 页面底色（渐变顶部） |
| `surface` | `#FBF8F2` | `#1C1A17` | 卡片、面板 |
| `surfaceRaised` | `#FFFFFF` | `#242019` | 输入框、抬升层 |
| `surfaceSunken` | `#EDE7DB` | `#0E0D0C` | 凹陷区域、徽标底 |
| `ink` | `#1B1916` | `#F3EEE4` | 主文字 |
| `inkSecondary` | `#5B554B` | `#C4BCAD` | 次级文字 |
| `inkMuted` | `#6E675C` | `#9A9285` | 提示、弱化文字（仍达 AA） |
| `hairline` | `#DFD7C8` | `#35302A` | 1px 分隔线、描边 |
| `accent` | `#2F4E66` | `#9CBBD1` | 品牌、链接、选中态 |
| `accentContrast` | `#F7FAFC` | `#10202B` | 主色上的文字 |
| `accentSoft` | `#DDE6EC` | `#22323D` | 选中底、标签底 |
| `success` / `warning` / `danger` | `#3B6F55` / `#94641C` / `#A13C33` | `#7FB79A` / `#D3A45E` / `#DE8B80` | 状态 |

对比度由 `test/design/theme_test.dart` 守护：`ink` ≥ 7:1，`inkSecondary` / `inkMuted` / `accent` / `danger` ≥ 4.5:1。

## 5. 文字

标题用衬线（Noto Serif CJK SC），界面用无衬线（Noto Sans CJK SC）；中文与拉丁共用一套字号，避免中英混排时基线跳动。

| Token | 字号 / 行高 | 用途 |
| --- | --- | --- |
| `displayLarge` | 40 / 1.18 | 极少用，封面/欢迎页 |
| `displayMedium` | 32 / 1.22 | 空状态大标题（备用） |
| `headlineLarge` | 25 / 1.3 | 页面标题 |
| `headlineMedium` | 21 / 1.35 | 空状态标题 |
| `titleLarge` | 16.5 / 1.45 | 区块标题、品牌 |
| `titleMedium` | 15 / 1.45 | 列表项标题 |
| `bodyLarge` | 15 / 1.75 | 正文 |
| `bodyMedium` | 14 / 1.7 | 说明文字 |
| `bodySmall` | 12.5 / 1.6 | 辅助说明 |
| `labelLarge` | 13.5 / 1.4 | 按钮、导航 |
| `labelSmall` | 11 / 1.3 | 徽标、eyebrow（字距 1.6） |

阅读/编辑正文：衬线 16.5 / 1.9，字距 0.15，首行缩进 2 字符，见 `AppTypography.reading`。

字体栈按平台回退：Linux 用 Noto CJK，Windows 回退微软雅黑/宋体，macOS 回退苹方/宋体。后续可内嵌字体子集，保证三端完全一致。

## 6. 间距、圆角、动效

- 间距：4 的倍数（`xxs 2 / xs 4 / sm 8 / md 12 / lg 16 / xl 24 / xxl 32 / xxxl 48 / huge 64`）。
- 圆角：控件 10、卡片 16、浮层 22、标签 999。
- 动效：`fast 120ms`、`base 200ms`、`slow 320ms`、页面 `240ms`；进入 `easeOutCubic`，强调 `easeInOutCubic`。页面切换是 240ms 淡入 + 1% 上移，不做花哨转场。
- 尊重系统「减少动态效果」：动画时长由 `MediaQuery.disableAnimations` 兜底（后续接入）。

## 7. 壳层与断点

| 宽度 | 布局 |
| --- | --- |
| ≥ 960 | 玻璃侧栏 252px + 内容区，四周留 16px，侧栏圆角 22 |
| < 960 | 内容区 + 悬浮玻璃底部导航（高 68，圆角 22，留安全区） |

内容列最宽 1080，页面左右内边距 32（窄屏 20）。列表永远用 `ListView.builder` / `SliverList`，不整页 `SingleChildScrollView` 包长列表。

玻璃面板把「模糊底」和「内容」分成两个绘制层：模糊结果被 `RepaintBoundary` 缓存，选中态动画或墨水涟漪只重绘内容，不会每帧重跑一次背景模糊。

**切换 tab 不做转场动画**：三个分支用 `NoTransitionPage` 直接换页，并开启 `StatefulShellBranch(preload: true)` 预加载。理由：转场每帧都要整页重绘，还会让玻璃浮层重新做一次背景模糊，第一次切换尤其容易读成卡顿；tab 属于「即时」操作，动效只会拖慢它。推入页（如 `/design`）仍保留 240ms 淡入。

## 8. 组件约定

- 按钮、输入框、分段选择、开关、Chip 全部由 `AppTheme` 统一，页面不得局部覆写。
- 卡片：`surface` + 1px `hairline`，不加阴影；只有浮层与书封允许阴影。
- 空状态：`EmptyState`（图示 + 标题 + 一句说明 + 至多两个操作 + 可选提示）。
- 页面骨架：`AppPage`（eyebrow / 标题 / 副标题 / 操作 / 滚动体），推入页传 `leading` 返回键。
- 图标默认 20px，线性风格；选中态用 `accent` + `accentSoft` 药丸底。

## 9. 怎么改视觉

1. 换配色 → 改 `AppColors.light` / `AppColors.dark`，跑对比度测试。
2. 换字体 → 改 `AppTypography` 的字族与回退栈；需要内嵌字体时再加 `pubspec.yaml` 的 `fonts`。
3. 换玻璃强度 → 改 `GlassTokens.forQuality`；关闭档必须保持完全不透明。
4. 换布局 → 改 `AppLayout`（断点、侧栏宽度、内容宽度）。
5. 新增组件 → 放 `lib/design/components/`，不依赖任何 feature。

预览入口：设置 → 设计系统（`/design`），或直接打开 `DesignSystemPage`。

## 10. 截图

| 浅色书架 | 深色书架 |
| --- | --- |
| ![浅色](design/home-light.png) | ![深色](design/home-dark.png) |

| 设置 | 设计系统 |
| --- | --- |
| ![设置](design/settings-light.png) | ![设计系统](design/design-system.png) |

移动/窄窗（< 960）：![窄窗](design/home-compact.png)

## 11. 尚未定稿

- 字体是否内嵌（体积 vs 三端一致），M2 前决定。
- 图标集：先用 Material 线性图标，后续可换 Lucide/Phosphor 以统一笔画粗细。
- 封面编辑器的取色与模板，随 M2 封面功能单独设计。
- 高对比度模式（`MediaQuery.highContrast`）待接入。
