// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appName => '书织';

  @override
  String get appNameLatin => 'Bookloom';

  @override
  String get appTagline => '把文字织成书';

  @override
  String get navLibrary => '书架';

  @override
  String get navImport => '导入';

  @override
  String get navSettings => '设置';

  @override
  String get sidebarFooter => '本地运行 · 不联网';

  @override
  String sidebarVersion(String version) {
    return 'v$version';
  }

  @override
  String get quickToggleTheme => '切换主题';

  @override
  String get quickToggleGlass => '切换玻璃强度';

  @override
  String get libraryTitle => '书架';

  @override
  String get librarySubtitle => '书稿都在本机，随时可以带走';

  @override
  String get libraryEmptyTitle => '书架还是空的';

  @override
  String get libraryEmptyMessage => '导入第一份 TXT、EPUB 或 DOCX，把散落的文字整理成一本书。';

  @override
  String get libraryEmptyAction => '导入书稿';

  @override
  String get libraryEmptyHint => '支持 TXT · EPUB · DOCX';

  @override
  String get importTitle => '导入';

  @override
  String get importSubtitle => '解析全部在本机完成，文件不会离开设备';

  @override
  String get importPendingTitle => '导入流程正在搭建';

  @override
  String get importPendingMessage =>
      'M1 会先打通 TXT：编码探测、分章评分、目录校对。当前版本先确认界面语言与数据结构。';

  @override
  String get importFormatsTitle => '计划支持的格式';

  @override
  String get importFormatTxt => 'TXT';

  @override
  String get importFormatTxtDesc => '自动识别 UTF-8 / GBK / Big5，按标题密度分章';

  @override
  String get importFormatEpub => 'EPUB';

  @override
  String get importFormatEpubDesc => '保留 spine 顺序、目录层级与封面';

  @override
  String get importFormatDocx => 'DOCX';

  @override
  String get importFormatDocxDesc => '还原「标题 1 / 标题 2」的卷章结构';

  @override
  String get importStatusPlanned => '计划中';

  @override
  String get importStatusNext => 'M1';

  @override
  String get settingsTitle => '设置';

  @override
  String get settingsSubtitle => '外观、数据与关于';

  @override
  String get settingsAppearance => '外观';

  @override
  String get settingsThemeMode => '主题';

  @override
  String get themeSystem => '跟随系统';

  @override
  String get themeLight => '浅色';

  @override
  String get themeDark => '深色';

  @override
  String get settingsGlass => '磨砂玻璃';

  @override
  String get settingsGlassDesc => '只用于侧栏、浮层与对话框；正文始终落在不透明的纸面上。';

  @override
  String get glassStrong => '强';

  @override
  String get glassSoft => '轻';

  @override
  String get glassOff => '关';

  @override
  String get settingsData => '数据';

  @override
  String get settingsDataLocation => '数据目录';

  @override
  String get settingsDataLocationDesc => '书籍、封面和备份都保存在这里，可以直接拷贝带走。';

  @override
  String get settingsCopyPath => '复制路径';

  @override
  String get settingsCopied => '路径已复制到剪贴板';

  @override
  String get settingsAbout => '关于';

  @override
  String get settingsVersion => '版本';

  @override
  String get settingsLicense => '许可证';

  @override
  String get settingsLicenseValue => 'MIT';

  @override
  String get settingsDesignSystem => '设计系统';

  @override
  String get settingsDesignSystemDesc => '颜色、字体、间距、玻璃与组件状态';

  @override
  String get settingsOpen => '打开';

  @override
  String get designTitle => '设计系统';

  @override
  String get designSubtitle => '这里是全站视觉的唯一来源，改 token 就能整体换装。';

  @override
  String get designSectionColors => '色彩';

  @override
  String get designSectionColorsDesc => '语义色板，浅色 / 深色两套。';

  @override
  String get designSectionType => '文字';

  @override
  String get designSectionTypeDesc => '标题用衬线，界面用无衬线；中文与拉丁共用一套字号。';

  @override
  String get designSectionSpacing => '间距与圆角';

  @override
  String get designSectionGlass => '玻璃与层级';

  @override
  String get designSectionGlassDesc => '玻璃只出现在浮层上；关闭后自动退化为不透明纸面。';

  @override
  String get designSectionComponents => '组件';

  @override
  String get designSectionComponentsDesc => '按钮、输入、标签与选择器继承主题，不在页面里覆写。';

  @override
  String get designTypeHeading => '把文字织成书';

  @override
  String get designTypeBody => '春江潮水连海平，海上明月共潮生。滟滟随波千万里，何处春江无月明。';

  @override
  String get designSampleCardTitle => '章节卡片';

  @override
  String get designSampleCardBody => '样张文字，用来检查行高、字距与灰度。';

  @override
  String get designGlassPanelTitle => '浮层面板';

  @override
  String get designGlassPanelBody => '玻璃面板下的内容会轻微模糊，正文不放在这里。';

  @override
  String get designLabelPrimary => '主按钮';

  @override
  String get designLabelSecondary => '次按钮';

  @override
  String get designLabelText => '文字按钮';

  @override
  String get designLabelDisabled => '禁用';

  @override
  String get designLabelInput => '输入框';

  @override
  String get designLabelChip => '标签';

  @override
  String get designLabelSwitch => '开关';

  @override
  String get designLabelSegmented => '分段选择';

  @override
  String get designPlaceholderInput => '搜索或输入书名';

  @override
  String get errorTitle => '出了点问题';

  @override
  String get errorBody => '界面遇到未预期的错误，已记录日志。';

  @override
  String get bootstrapFailureTitle => '无法启动';

  @override
  String get bootstrapFailureBody => '数据目录或本地数据库无法打开。';

  @override
  String get bootstrapFailureRetry => '重试';

  @override
  String get notFoundTitle => '页面不存在';

  @override
  String get notFoundBack => '返回书架';
}
