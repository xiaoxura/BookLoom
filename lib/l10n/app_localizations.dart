import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// 应用中文名
  ///
  /// In zh, this message translates to:
  /// **'书织'**
  String get appName;

  /// No description provided for @navLibrary.
  ///
  /// In zh, this message translates to:
  /// **'书架'**
  String get navLibrary;

  /// No description provided for @navImport.
  ///
  /// In zh, this message translates to:
  /// **'导入'**
  String get navImport;

  /// No description provided for @navSettings.
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get navSettings;

  /// No description provided for @libraryEmptyTitle.
  ///
  /// In zh, this message translates to:
  /// **'书架里还没有书稿'**
  String get libraryEmptyTitle;

  /// No description provided for @libraryEmptyMessage.
  ///
  /// In zh, this message translates to:
  /// **'导入书稿后，在这里查看和整理。'**
  String get libraryEmptyMessage;

  /// No description provided for @libraryEmptyAction.
  ///
  /// In zh, this message translates to:
  /// **'导入书稿'**
  String get libraryEmptyAction;

  /// No description provided for @importFormatsTitle.
  ///
  /// In zh, this message translates to:
  /// **'格式与处理方式'**
  String get importFormatsTitle;

  /// No description provided for @importFormatTxt.
  ///
  /// In zh, this message translates to:
  /// **'TXT'**
  String get importFormatTxt;

  /// No description provided for @importFormatEpub.
  ///
  /// In zh, this message translates to:
  /// **'EPUB'**
  String get importFormatEpub;

  /// No description provided for @importFormatDocx.
  ///
  /// In zh, this message translates to:
  /// **'DOCX'**
  String get importFormatDocx;

  /// No description provided for @importStatusPlanned.
  ///
  /// In zh, this message translates to:
  /// **'计划中'**
  String get importStatusPlanned;

  /// No description provided for @importStatusNext.
  ///
  /// In zh, this message translates to:
  /// **'M1'**
  String get importStatusNext;

  /// No description provided for @settingsAppearance.
  ///
  /// In zh, this message translates to:
  /// **'外观'**
  String get settingsAppearance;

  /// No description provided for @settingsThemeMode.
  ///
  /// In zh, this message translates to:
  /// **'主题'**
  String get settingsThemeMode;

  /// No description provided for @themeSystem.
  ///
  /// In zh, this message translates to:
  /// **'跟随系统'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In zh, this message translates to:
  /// **'浅色'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In zh, this message translates to:
  /// **'深色'**
  String get themeDark;

  /// No description provided for @settingsGlass.
  ///
  /// In zh, this message translates to:
  /// **'磨砂玻璃'**
  String get settingsGlass;

  /// No description provided for @glassStrong.
  ///
  /// In zh, this message translates to:
  /// **'强'**
  String get glassStrong;

  /// No description provided for @glassSoft.
  ///
  /// In zh, this message translates to:
  /// **'轻'**
  String get glassSoft;

  /// No description provided for @glassOff.
  ///
  /// In zh, this message translates to:
  /// **'关'**
  String get glassOff;

  /// No description provided for @settingsData.
  ///
  /// In zh, this message translates to:
  /// **'数据'**
  String get settingsData;

  /// No description provided for @settingsDataLocation.
  ///
  /// In zh, this message translates to:
  /// **'数据目录'**
  String get settingsDataLocation;

  /// No description provided for @settingsCopyPath.
  ///
  /// In zh, this message translates to:
  /// **'复制路径'**
  String get settingsCopyPath;

  /// No description provided for @settingsCopied.
  ///
  /// In zh, this message translates to:
  /// **'路径已复制到剪贴板'**
  String get settingsCopied;

  /// No description provided for @designTitle.
  ///
  /// In zh, this message translates to:
  /// **'设计系统'**
  String get designTitle;

  /// No description provided for @designSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'这里是全站视觉的唯一来源，改 token 就能整体换装。'**
  String get designSubtitle;

  /// No description provided for @designSectionColors.
  ///
  /// In zh, this message translates to:
  /// **'色彩'**
  String get designSectionColors;

  /// No description provided for @designSectionColorsDesc.
  ///
  /// In zh, this message translates to:
  /// **'语义色板，浅色 / 深色两套。'**
  String get designSectionColorsDesc;

  /// No description provided for @designSectionType.
  ///
  /// In zh, this message translates to:
  /// **'文字'**
  String get designSectionType;

  /// No description provided for @designSectionTypeDesc.
  ///
  /// In zh, this message translates to:
  /// **'标题用衬线，界面用无衬线；中文与拉丁共用一套字号。'**
  String get designSectionTypeDesc;

  /// No description provided for @designSectionSpacing.
  ///
  /// In zh, this message translates to:
  /// **'间距与圆角'**
  String get designSectionSpacing;

  /// No description provided for @designSectionGlass.
  ///
  /// In zh, this message translates to:
  /// **'玻璃与层级'**
  String get designSectionGlass;

  /// No description provided for @designSectionGlassDesc.
  ///
  /// In zh, this message translates to:
  /// **'玻璃只出现在浮层上；关闭后自动退化为不透明纸面。'**
  String get designSectionGlassDesc;

  /// No description provided for @designSectionComponents.
  ///
  /// In zh, this message translates to:
  /// **'组件'**
  String get designSectionComponents;

  /// No description provided for @designSectionComponentsDesc.
  ///
  /// In zh, this message translates to:
  /// **'按钮、输入、标签与选择器继承主题，不在页面里覆写。'**
  String get designSectionComponentsDesc;

  /// No description provided for @designTypeHeading.
  ///
  /// In zh, this message translates to:
  /// **'把文字织成书'**
  String get designTypeHeading;

  /// No description provided for @designTypeBody.
  ///
  /// In zh, this message translates to:
  /// **'春江潮水连海平，海上明月共潮生。滟滟随波千万里，何处春江无月明。'**
  String get designTypeBody;

  /// No description provided for @designSampleCardTitle.
  ///
  /// In zh, this message translates to:
  /// **'章节卡片'**
  String get designSampleCardTitle;

  /// No description provided for @designSampleCardBody.
  ///
  /// In zh, this message translates to:
  /// **'样张文字，用来检查行高、字距与灰度。'**
  String get designSampleCardBody;

  /// No description provided for @designGlassPanelTitle.
  ///
  /// In zh, this message translates to:
  /// **'浮层面板'**
  String get designGlassPanelTitle;

  /// No description provided for @designGlassPanelBody.
  ///
  /// In zh, this message translates to:
  /// **'玻璃面板下的内容会轻微模糊，正文不放在这里。'**
  String get designGlassPanelBody;

  /// No description provided for @designLabelPrimary.
  ///
  /// In zh, this message translates to:
  /// **'主按钮'**
  String get designLabelPrimary;

  /// No description provided for @designLabelSecondary.
  ///
  /// In zh, this message translates to:
  /// **'次按钮'**
  String get designLabelSecondary;

  /// No description provided for @designLabelText.
  ///
  /// In zh, this message translates to:
  /// **'文字按钮'**
  String get designLabelText;

  /// No description provided for @designLabelChip.
  ///
  /// In zh, this message translates to:
  /// **'标签'**
  String get designLabelChip;

  /// No description provided for @designLabelSwitch.
  ///
  /// In zh, this message translates to:
  /// **'开关'**
  String get designLabelSwitch;

  /// No description provided for @designPlaceholderInput.
  ///
  /// In zh, this message translates to:
  /// **'搜索或输入书名'**
  String get designPlaceholderInput;

  /// No description provided for @bootstrapFailureTitle.
  ///
  /// In zh, this message translates to:
  /// **'无法启动'**
  String get bootstrapFailureTitle;

  /// No description provided for @bootstrapFailureBody.
  ///
  /// In zh, this message translates to:
  /// **'数据目录或本地数据库无法打开。'**
  String get bootstrapFailureBody;

  /// No description provided for @notFoundTitle.
  ///
  /// In zh, this message translates to:
  /// **'页面不存在'**
  String get notFoundTitle;

  /// No description provided for @notFoundBack.
  ///
  /// In zh, this message translates to:
  /// **'返回书架'**
  String get notFoundBack;

  /// No description provided for @importFormatTxtDesc.
  ///
  /// In zh, this message translates to:
  /// **'自动识别 UTF-8 / GBK / Big5，按标题密度分章'**
  String get importFormatTxtDesc;

  /// No description provided for @importFormatEpubDesc.
  ///
  /// In zh, this message translates to:
  /// **'保留 spine 顺序、目录层级与封面'**
  String get importFormatEpubDesc;

  /// No description provided for @importFormatDocxDesc.
  ///
  /// In zh, this message translates to:
  /// **'还原「标题 1 / 标题 2」的卷章结构'**
  String get importFormatDocxDesc;

  /// No description provided for @importPendingTitle.
  ///
  /// In zh, this message translates to:
  /// **'导入流程正在搭建'**
  String get importPendingTitle;

  /// No description provided for @importPendingMessage.
  ///
  /// In zh, this message translates to:
  /// **'M1 会先打通 TXT：编码探测、分章评分、目录校对。当前版本先确认界面语言与数据结构。'**
  String get importPendingMessage;

  /// No description provided for @settingsGlassDesc.
  ///
  /// In zh, this message translates to:
  /// **'只用于侧栏、浮层与对话框；正文始终落在不透明的纸面上。'**
  String get settingsGlassDesc;

  /// No description provided for @settingsDataLocationDesc.
  ///
  /// In zh, this message translates to:
  /// **'书籍、封面和备份都保存在这里，可以直接拷贝带走。'**
  String get settingsDataLocationDesc;

  /// No description provided for @windowMinimize.
  ///
  /// In zh, this message translates to:
  /// **'最小化'**
  String get windowMinimize;

  /// No description provided for @windowMaximize.
  ///
  /// In zh, this message translates to:
  /// **'最大化'**
  String get windowMaximize;

  /// No description provided for @windowClose.
  ///
  /// In zh, this message translates to:
  /// **'关闭'**
  String get windowClose;

  /// No description provided for @navAbout.
  ///
  /// In zh, this message translates to:
  /// **'关于'**
  String get navAbout;

  /// No description provided for @aboutTech.
  ///
  /// In zh, this message translates to:
  /// **'技术栈'**
  String get aboutTech;

  /// No description provided for @aboutDesignSystem.
  ///
  /// In zh, this message translates to:
  /// **'设计系统'**
  String get aboutDesignSystem;

  /// No description provided for @appTagline.
  ///
  /// In zh, this message translates to:
  /// **'把文字织成书'**
  String get appTagline;

  /// No description provided for @aboutHeading.
  ///
  /// In zh, this message translates to:
  /// **'关于书织'**
  String get aboutHeading;

  /// No description provided for @aboutVersionLabel.
  ///
  /// In zh, this message translates to:
  /// **'版本 {version}'**
  String aboutVersionLabel(String version);

  /// No description provided for @appDescription.
  ///
  /// In zh, this message translates to:
  /// **'本地优先的电子书工作台'**
  String get appDescription;

  /// No description provided for @aboutLocalNote.
  ///
  /// In zh, this message translates to:
  /// **'无需账号，书稿与编辑数据保存在本机。'**
  String get aboutLocalNote;

  /// No description provided for @aboutChangelog.
  ///
  /// In zh, this message translates to:
  /// **'更新日志'**
  String get aboutChangelog;

  /// No description provided for @aboutTechIntro.
  ///
  /// In zh, this message translates to:
  /// **'核心用纯 Dart，界面用 Flutter，所有数据落在本机 SQLite。'**
  String get aboutTechIntro;

  /// No description provided for @aboutOpenSource.
  ///
  /// In zh, this message translates to:
  /// **'开放源代码'**
  String get aboutOpenSource;

  /// No description provided for @aboutDeveloper.
  ///
  /// In zh, this message translates to:
  /// **'开发者'**
  String get aboutDeveloper;

  /// No description provided for @aboutBio.
  ///
  /// In zh, this message translates to:
  /// **'独立开发者 / 开源爱好者'**
  String get aboutBio;

  /// No description provided for @aboutHomepage.
  ///
  /// In zh, this message translates to:
  /// **'个人主页'**
  String get aboutHomepage;

  /// No description provided for @aboutContact.
  ///
  /// In zh, this message translates to:
  /// **'联系作者'**
  String get aboutContact;

  /// No description provided for @aboutThanks.
  ///
  /// In zh, this message translates to:
  /// **'感谢每一位开源贡献者'**
  String get aboutThanks;

  /// No description provided for @aboutViewLicense.
  ///
  /// In zh, this message translates to:
  /// **'查看开源许可'**
  String get aboutViewLicense;

  /// No description provided for @techFlutter.
  ///
  /// In zh, this message translates to:
  /// **'Flutter'**
  String get techFlutter;

  /// No description provided for @techFlutterDesc.
  ///
  /// In zh, this message translates to:
  /// **'跨平台界面框架'**
  String get techFlutterDesc;

  /// No description provided for @techDart.
  ///
  /// In zh, this message translates to:
  /// **'Dart 3'**
  String get techDart;

  /// No description provided for @techDartDesc.
  ///
  /// In zh, this message translates to:
  /// **'核心语言'**
  String get techDartDesc;

  /// No description provided for @techRiverpod.
  ///
  /// In zh, this message translates to:
  /// **'Riverpod'**
  String get techRiverpod;

  /// No description provided for @techRiverpodDesc.
  ///
  /// In zh, this message translates to:
  /// **'状态管理'**
  String get techRiverpodDesc;

  /// No description provided for @techDrift.
  ///
  /// In zh, this message translates to:
  /// **'Drift'**
  String get techDrift;

  /// No description provided for @techDriftDesc.
  ///
  /// In zh, this message translates to:
  /// **'类型安全 SQLite'**
  String get techDriftDesc;

  /// No description provided for @techRouter.
  ///
  /// In zh, this message translates to:
  /// **'go_router'**
  String get techRouter;

  /// No description provided for @techRouterDesc.
  ///
  /// In zh, this message translates to:
  /// **'路由与深链'**
  String get techRouterDesc;

  /// No description provided for @techWindow.
  ///
  /// In zh, this message translates to:
  /// **'window_manager'**
  String get techWindow;

  /// No description provided for @techWindowDesc.
  ///
  /// In zh, this message translates to:
  /// **'桌面窗口控制'**
  String get techWindowDesc;

  /// No description provided for @commonRetry.
  ///
  /// In zh, this message translates to:
  /// **'重试'**
  String get commonRetry;

  /// No description provided for @commonCancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get commonCancel;

  /// No description provided for @commonSave.
  ///
  /// In zh, this message translates to:
  /// **'保存'**
  String get commonSave;

  /// No description provided for @libraryLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法读取书架'**
  String get libraryLoadFailed;

  /// No description provided for @libraryNoMatch.
  ///
  /// In zh, this message translates to:
  /// **'没有找到匹配的书稿'**
  String get libraryNoMatch;

  /// No description provided for @librarySearch.
  ///
  /// In zh, this message translates to:
  /// **'搜索书名或作者'**
  String get librarySearch;

  /// No description provided for @libraryClearSearch.
  ///
  /// In zh, this message translates to:
  /// **'清除搜索'**
  String get libraryClearSearch;

  /// No description provided for @librarySortRecent.
  ///
  /// In zh, this message translates to:
  /// **'最近修改'**
  String get librarySortRecent;

  /// No description provided for @librarySortTitle.
  ///
  /// In zh, this message translates to:
  /// **'书名'**
  String get librarySortTitle;

  /// No description provided for @librarySortOpened.
  ///
  /// In zh, this message translates to:
  /// **'最近打开'**
  String get librarySortOpened;

  /// No description provided for @libraryUnknownAuthor.
  ///
  /// In zh, this message translates to:
  /// **'作者未填'**
  String get libraryUnknownAuthor;

  /// No description provided for @libraryBookActions.
  ///
  /// In zh, this message translates to:
  /// **'书籍操作'**
  String get libraryBookActions;

  /// No description provided for @libraryRename.
  ///
  /// In zh, this message translates to:
  /// **'重命名'**
  String get libraryRename;

  /// No description provided for @libraryDelete.
  ///
  /// In zh, this message translates to:
  /// **'删除书籍'**
  String get libraryDelete;

  /// No description provided for @libraryBookTitle.
  ///
  /// In zh, this message translates to:
  /// **'书名'**
  String get libraryBookTitle;

  /// No description provided for @libraryOperationFailed.
  ///
  /// In zh, this message translates to:
  /// **'操作失败，请重试。'**
  String get libraryOperationFailed;

  /// No description provided for @libraryBookStats.
  ///
  /// In zh, this message translates to:
  /// **'{chapters} 章 · {words} 字'**
  String libraryBookStats(int chapters, int words);

  /// No description provided for @libraryDeleteConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确定删除《{title}》吗？书稿和本地资源将一并删除。'**
  String libraryDeleteConfirm(String title);

  /// No description provided for @importSelectTitle.
  ///
  /// In zh, this message translates to:
  /// **'选择书稿'**
  String get importSelectTitle;

  /// No description provided for @importTxtReady.
  ///
  /// In zh, this message translates to:
  /// **'支持 TXT、EPUB 和 DOCX。解析完成后检查章节、文字与格式损失提示，再加入书架。'**
  String get importTxtReady;

  /// No description provided for @importChooseFile.
  ///
  /// In zh, this message translates to:
  /// **'选择文件'**
  String get importChooseFile;

  /// No description provided for @importChooseAnother.
  ///
  /// In zh, this message translates to:
  /// **'重新选择文件'**
  String get importChooseAnother;

  /// No description provided for @importFileSize.
  ///
  /// In zh, this message translates to:
  /// **'大小：{size}'**
  String importFileSize(String size);

  /// No description provided for @importSizeUnknown.
  ///
  /// In zh, this message translates to:
  /// **'未知'**
  String get importSizeUnknown;

  /// No description provided for @importOptions.
  ///
  /// In zh, this message translates to:
  /// **'解析选项'**
  String get importOptions;

  /// No description provided for @importEncoding.
  ///
  /// In zh, this message translates to:
  /// **'文字编码'**
  String get importEncoding;

  /// No description provided for @importEncodingAuto.
  ///
  /// In zh, this message translates to:
  /// **'自动识别'**
  String get importEncodingAuto;

  /// No description provided for @importFilterAds.
  ///
  /// In zh, this message translates to:
  /// **'过滤明显广告'**
  String get importFilterAds;

  /// No description provided for @importAnalyze.
  ///
  /// In zh, this message translates to:
  /// **'解析并预览'**
  String get importAnalyze;

  /// No description provided for @importReviewTitle.
  ///
  /// In zh, this message translates to:
  /// **'导入预览'**
  String get importReviewTitle;

  /// No description provided for @importReviewStats.
  ///
  /// In zh, this message translates to:
  /// **'{chapters} 章 · {words} 字'**
  String importReviewStats(int chapters, int words);

  /// No description provided for @importActualEncoding.
  ///
  /// In zh, this message translates to:
  /// **'识别编码：{encoding}'**
  String importActualEncoding(String encoding);

  /// No description provided for @importWarnings.
  ///
  /// In zh, this message translates to:
  /// **'请留意'**
  String get importWarnings;

  /// No description provided for @importExcerpt.
  ///
  /// In zh, this message translates to:
  /// **'正文片段'**
  String get importExcerpt;

  /// No description provided for @importWarningEncoding.
  ///
  /// In zh, this message translates to:
  /// **'编码识别信心较低；可改选编码并重新解析。'**
  String get importWarningEncoding;

  /// No description provided for @importWarningNoHeadings.
  ///
  /// In zh, this message translates to:
  /// **'未识别到章节标题，已按单章整理。'**
  String get importWarningNoHeadings;

  /// No description provided for @importWarningManyChapters.
  ///
  /// In zh, this message translates to:
  /// **'识别出较多章节，请检查目录。'**
  String get importWarningManyChapters;

  /// No description provided for @importWarningGeneric.
  ///
  /// In zh, this message translates to:
  /// **'解析提示：{code}'**
  String importWarningGeneric(String code);

  /// No description provided for @importAddToLibrary.
  ///
  /// In zh, this message translates to:
  /// **'加入书架并编辑'**
  String get importAddToLibrary;

  /// No description provided for @importSaving.
  ///
  /// In zh, this message translates to:
  /// **'正在保存书稿…'**
  String get importSaving;

  /// No description provided for @importStagePrepare.
  ///
  /// In zh, this message translates to:
  /// **'正在准备…'**
  String get importStagePrepare;

  /// No description provided for @importStageDecode.
  ///
  /// In zh, this message translates to:
  /// **'正在识别编码…'**
  String get importStageDecode;

  /// No description provided for @importStageParse.
  ///
  /// In zh, this message translates to:
  /// **'正在整理章节…'**
  String get importStageParse;

  /// No description provided for @importStageReady.
  ///
  /// In zh, this message translates to:
  /// **'解析完成'**
  String get importStageReady;

  /// No description provided for @importPickFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法选择文件，请检查权限后重试。'**
  String get importPickFailed;

  /// No description provided for @importAnalyzeFailed.
  ///
  /// In zh, this message translates to:
  /// **'解析失败，请检查文件或尝试其他编码。'**
  String get importAnalyzeFailed;

  /// No description provided for @importSaveFailed.
  ///
  /// In zh, this message translates to:
  /// **'保存失败，预览仍保留，可重试。'**
  String get importSaveFailed;

  /// No description provided for @importDiscardFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法清理暂存文件，请重试。'**
  String get importDiscardFailed;

  /// No description provided for @importFormatAvailable.
  ///
  /// In zh, this message translates to:
  /// **'{format} · 可导入'**
  String importFormatAvailable(String format);

  /// No description provided for @importFormatLater.
  ///
  /// In zh, this message translates to:
  /// **'{format} · 后续批次支持'**
  String importFormatLater(String format);

  /// No description provided for @editorOpenFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法打开书稿'**
  String get editorOpenFailed;

  /// No description provided for @editorBack.
  ///
  /// In zh, this message translates to:
  /// **'返回书架'**
  String get editorBack;

  /// No description provided for @editorChapters.
  ///
  /// In zh, this message translates to:
  /// **'章节目录'**
  String get editorChapters;

  /// No description provided for @editorBookInfo.
  ///
  /// In zh, this message translates to:
  /// **'书籍信息'**
  String get editorBookInfo;

  /// No description provided for @editorExport.
  ///
  /// In zh, this message translates to:
  /// **'导出书稿'**
  String get editorExport;

  /// No description provided for @editorUndo.
  ///
  /// In zh, this message translates to:
  /// **'撤销'**
  String get editorUndo;

  /// No description provided for @editorRedo.
  ///
  /// In zh, this message translates to:
  /// **'重做'**
  String get editorRedo;

  /// No description provided for @editorEdit.
  ///
  /// In zh, this message translates to:
  /// **'编辑'**
  String get editorEdit;

  /// No description provided for @editorPreview.
  ///
  /// In zh, this message translates to:
  /// **'预览'**
  String get editorPreview;

  /// No description provided for @editorSaving.
  ///
  /// In zh, this message translates to:
  /// **'正在保存…'**
  String get editorSaving;

  /// No description provided for @editorUnsaved.
  ///
  /// In zh, this message translates to:
  /// **'尚有未保存修改'**
  String get editorUnsaved;

  /// No description provided for @editorSaved.
  ///
  /// In zh, this message translates to:
  /// **'已保存'**
  String get editorSaved;

  /// No description provided for @editorSaveFailed.
  ///
  /// In zh, this message translates to:
  /// **'保存失败'**
  String get editorSaveFailed;

  /// No description provided for @editorSaveFailedStay.
  ///
  /// In zh, this message translates to:
  /// **'保存失败，已留在当前书稿。请重试。'**
  String get editorSaveFailedStay;

  /// No description provided for @editorSearchChapters.
  ///
  /// In zh, this message translates to:
  /// **'搜索章节'**
  String get editorSearchChapters;

  /// No description provided for @editorNoChapters.
  ///
  /// In zh, this message translates to:
  /// **'暂无章节'**
  String get editorNoChapters;

  /// No description provided for @editorEmptyChapter.
  ///
  /// In zh, this message translates to:
  /// **'本章没有正文'**
  String get editorEmptyChapter;

  /// No description provided for @editorChapterActions.
  ///
  /// In zh, this message translates to:
  /// **'章节操作'**
  String get editorChapterActions;

  /// No description provided for @editorRenameChapter.
  ///
  /// In zh, this message translates to:
  /// **'重命名章节'**
  String get editorRenameChapter;

  /// No description provided for @editorChapterTitle.
  ///
  /// In zh, this message translates to:
  /// **'章节标题'**
  String get editorChapterTitle;

  /// No description provided for @editorMergePrevious.
  ///
  /// In zh, this message translates to:
  /// **'并入上一章'**
  String get editorMergePrevious;

  /// No description provided for @editorPromote.
  ///
  /// In zh, this message translates to:
  /// **'升为卷'**
  String get editorPromote;

  /// No description provided for @editorDemote.
  ///
  /// In zh, this message translates to:
  /// **'降为章'**
  String get editorDemote;

  /// No description provided for @editorDeleteChapter.
  ///
  /// In zh, this message translates to:
  /// **'删除章节'**
  String get editorDeleteChapter;

  /// No description provided for @editorDeleteChapterConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确定删除“{title}”吗？其正文也会删除。'**
  String editorDeleteChapterConfirm(String title);

  /// No description provided for @editorParagraphActions.
  ///
  /// In zh, this message translates to:
  /// **'段落操作'**
  String get editorParagraphActions;

  /// No description provided for @editorSplitHere.
  ///
  /// In zh, this message translates to:
  /// **'从此段拆章'**
  String get editorSplitHere;

  /// No description provided for @editorSetAsTitle.
  ///
  /// In zh, this message translates to:
  /// **'设为章节标题'**
  String get editorSetAsTitle;

  /// No description provided for @editorImageBlock.
  ///
  /// In zh, this message translates to:
  /// **'图片段落'**
  String get editorImageBlock;

  /// No description provided for @editorBookTitle.
  ///
  /// In zh, this message translates to:
  /// **'书名'**
  String get editorBookTitle;

  /// No description provided for @editorBookAuthor.
  ///
  /// In zh, this message translates to:
  /// **'作者'**
  String get editorBookAuthor;

  /// No description provided for @editorMoreMetadata.
  ///
  /// In zh, this message translates to:
  /// **'更多信息'**
  String get editorMoreMetadata;

  /// No description provided for @editorDescription.
  ///
  /// In zh, this message translates to:
  /// **'简介'**
  String get editorDescription;

  /// No description provided for @editorSeries.
  ///
  /// In zh, this message translates to:
  /// **'系列'**
  String get editorSeries;

  /// No description provided for @editorPublisher.
  ///
  /// In zh, this message translates to:
  /// **'出版社'**
  String get editorPublisher;

  /// No description provided for @editorLanguage.
  ///
  /// In zh, this message translates to:
  /// **'语言'**
  String get editorLanguage;

  /// No description provided for @editorTags.
  ///
  /// In zh, this message translates to:
  /// **'标签（用逗号分隔）'**
  String get editorTags;

  /// No description provided for @editorPublishedAt.
  ///
  /// In zh, this message translates to:
  /// **'出版日期'**
  String get editorPublishedAt;

  /// No description provided for @editorInvalidDate.
  ///
  /// In zh, this message translates to:
  /// **'请输入有效日期，格式为 YYYY-MM-DD。'**
  String get editorInvalidDate;

  /// No description provided for @editorTitleRequired.
  ///
  /// In zh, this message translates to:
  /// **'书名不能为空。'**
  String get editorTitleRequired;

  /// No description provided for @editorLanguageRequired.
  ///
  /// In zh, this message translates to:
  /// **'语言不能为空。'**
  String get editorLanguageRequired;

  /// No description provided for @editorMetaSavedAutomatically.
  ///
  /// In zh, this message translates to:
  /// **'更改会自动保存。'**
  String get editorMetaSavedAutomatically;

  /// No description provided for @editorActionFailed.
  ///
  /// In zh, this message translates to:
  /// **'操作未完成，请检查当前章节后重试。'**
  String get editorActionFailed;

  /// No description provided for @editorExportSaved.
  ///
  /// In zh, this message translates to:
  /// **'导出文件已保存。'**
  String get editorExportSaved;

  /// No description provided for @editorExportFailed.
  ///
  /// In zh, this message translates to:
  /// **'导出失败，请重试。'**
  String get editorExportFailed;

  /// No description provided for @workbenchOpenBatch.
  ///
  /// In zh, this message translates to:
  /// **'批量处理多本书'**
  String get workbenchOpenBatch;

  /// No description provided for @workbenchOpenData.
  ///
  /// In zh, this message translates to:
  /// **'管理书籍数据与备份'**
  String get workbenchOpenData;

  /// No description provided for @workbenchSharingOpened.
  ///
  /// In zh, this message translates to:
  /// **'分享面板已打开，请在目标应用中完成传输。'**
  String get workbenchSharingOpened;

  /// No description provided for @workbenchCoverUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'封面图片不可用'**
  String get workbenchCoverUnavailable;

  /// No description provided for @editorWorkbenchMoreActions.
  ///
  /// In zh, this message translates to:
  /// **'更多书稿操作'**
  String get editorWorkbenchMoreActions;

  /// No description provided for @editorWorkbenchTools.
  ///
  /// In zh, this message translates to:
  /// **'书稿工具'**
  String get editorWorkbenchTools;

  /// No description provided for @editorWorkbenchReparse.
  ///
  /// In zh, this message translates to:
  /// **'从原文件重新识别'**
  String get editorWorkbenchReparse;

  /// No description provided for @editorWorkbenchShare.
  ///
  /// In zh, this message translates to:
  /// **'分享到其他应用'**
  String get editorWorkbenchShare;

  /// No description provided for @editorWorkbenchCloseLocation.
  ///
  /// In zh, this message translates to:
  /// **'关闭定位提示'**
  String get editorWorkbenchCloseLocation;

  /// No description provided for @editorWorkbenchLocationChanged.
  ///
  /// In zh, this message translates to:
  /// **'该段落已变化，请重新检查。'**
  String get editorWorkbenchLocationChanged;

  /// No description provided for @editorWorkbenchLocationAt.
  ///
  /// In zh, this message translates to:
  /// **'定位到第 {index} 段：{text}'**
  String editorWorkbenchLocationAt(int index, String text);

  /// No description provided for @editorWorkbenchDeleteVolumeConfirm.
  ///
  /// In zh, this message translates to:
  /// **'删除卷“{title}”后，卷内子章和正文会保留，并提升为顶层章节。'**
  String editorWorkbenchDeleteVolumeConfirm(String title);

  /// No description provided for @editorWorkbenchShareFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法打开分享面板，请重试。'**
  String get editorWorkbenchShareFailed;

  /// No description provided for @editorWorkbenchToolFailed.
  ///
  /// In zh, this message translates to:
  /// **'处理失败，请检查书稿后重试。'**
  String get editorWorkbenchToolFailed;

  /// No description provided for @editorWorkbenchToolsIntro.
  ///
  /// In zh, this message translates to:
  /// **'检查与批量修改作用于当前书稿；修改先预览，执行后可撤销一步。'**
  String get editorWorkbenchToolsIntro;

  /// No description provided for @editorWorkbenchPreparingBook.
  ///
  /// In zh, this message translates to:
  /// **'准备书稿…'**
  String get editorWorkbenchPreparingBook;

  /// No description provided for @editorWorkbenchCancelTask.
  ///
  /// In zh, this message translates to:
  /// **'取消任务'**
  String get editorWorkbenchCancelTask;

  /// No description provided for @editorWorkbenchAuditTitle.
  ///
  /// In zh, this message translates to:
  /// **'全书体检'**
  String get editorWorkbenchAuditTitle;

  /// No description provided for @editorWorkbenchAuditDesc.
  ///
  /// In zh, this message translates to:
  /// **'编号、空章、重复标题及广告痕迹；短章 <120 字、长章 >30000 字为启发式提示'**
  String get editorWorkbenchAuditDesc;

  /// No description provided for @editorWorkbenchAuditRun.
  ///
  /// In zh, this message translates to:
  /// **'检查当前书稿'**
  String get editorWorkbenchAuditRun;

  /// No description provided for @editorWorkbenchAuditTotal.
  ///
  /// In zh, this message translates to:
  /// **'共 {count} 项提示'**
  String editorWorkbenchAuditTotal(int count);

  /// No description provided for @editorWorkbenchIssueCount.
  ///
  /// In zh, this message translates to:
  /// **'{label}：{count}'**
  String editorWorkbenchIssueCount(String label, int count);

  /// No description provided for @editorWorkbenchAuditLimit.
  ///
  /// In zh, this message translates to:
  /// **'每类最多显示 20 条示例；总数包含全部提示。'**
  String get editorWorkbenchAuditLimit;

  /// No description provided for @editorWorkbenchMissedTitle.
  ///
  /// In zh, this message translates to:
  /// **'疑似漏章'**
  String get editorWorkbenchMissedTitle;

  /// No description provided for @editorWorkbenchMissedDesc.
  ///
  /// In zh, this message translates to:
  /// **'定位看起来像章节标题的正文段落，确认后可用段落菜单拆章'**
  String get editorWorkbenchMissedDesc;

  /// No description provided for @editorWorkbenchMissedRun.
  ///
  /// In zh, this message translates to:
  /// **'查找疑似漏章'**
  String get editorWorkbenchMissedRun;

  /// No description provided for @editorWorkbenchMissedCount.
  ///
  /// In zh, this message translates to:
  /// **'找到 {count} 处候选'**
  String editorWorkbenchMissedCount(int count);

  /// No description provided for @editorWorkbenchMissedLocation.
  ///
  /// In zh, this message translates to:
  /// **'目录第 {chapter} 项 · 段落第 {paragraph} 项'**
  String editorWorkbenchMissedLocation(int chapter, int paragraph);

  /// No description provided for @editorWorkbenchMissedLimit.
  ///
  /// In zh, this message translates to:
  /// **'仅显示前 100 处候选。'**
  String get editorWorkbenchMissedLimit;

  /// No description provided for @editorWorkbenchFindReplace.
  ///
  /// In zh, this message translates to:
  /// **'查找与替换'**
  String get editorWorkbenchFindReplace;

  /// No description provided for @editorWorkbenchFindText.
  ///
  /// In zh, this message translates to:
  /// **'查找内容'**
  String get editorWorkbenchFindText;

  /// No description provided for @editorWorkbenchReplaceWith.
  ///
  /// In zh, this message translates to:
  /// **'替换为'**
  String get editorWorkbenchReplaceWith;

  /// No description provided for @editorWorkbenchScope.
  ///
  /// In zh, this message translates to:
  /// **'范围'**
  String get editorWorkbenchScope;

  /// No description provided for @editorWorkbenchScopeAll.
  ///
  /// In zh, this message translates to:
  /// **'标题和正文'**
  String get editorWorkbenchScopeAll;

  /// No description provided for @editorWorkbenchScopeTitle.
  ///
  /// In zh, this message translates to:
  /// **'仅章节标题'**
  String get editorWorkbenchScopeTitle;

  /// No description provided for @editorWorkbenchScopeBody.
  ///
  /// In zh, this message translates to:
  /// **'仅正文'**
  String get editorWorkbenchScopeBody;

  /// No description provided for @editorWorkbenchRegex.
  ///
  /// In zh, this message translates to:
  /// **'正则表达式'**
  String get editorWorkbenchRegex;

  /// No description provided for @editorWorkbenchCaseSensitive.
  ///
  /// In zh, this message translates to:
  /// **'区分大小写'**
  String get editorWorkbenchCaseSensitive;

  /// No description provided for @editorWorkbenchPreviewReplace.
  ///
  /// In zh, this message translates to:
  /// **'预览替换'**
  String get editorWorkbenchPreviewReplace;

  /// No description provided for @editorWorkbenchRenumberTitle.
  ///
  /// In zh, this message translates to:
  /// **'按卷重编号'**
  String get editorWorkbenchRenumberTitle;

  /// No description provided for @editorWorkbenchRenumberDesc.
  ///
  /// In zh, this message translates to:
  /// **'检查各卷章号并预览标题修改，不改动正文。'**
  String get editorWorkbenchRenumberDesc;

  /// No description provided for @editorWorkbenchPreviewRenumber.
  ///
  /// In zh, this message translates to:
  /// **'预览重编号'**
  String get editorWorkbenchPreviewRenumber;

  /// No description provided for @editorWorkbenchConvertTitle.
  ///
  /// In zh, this message translates to:
  /// **'转换当前书稿'**
  String get editorWorkbenchConvertTitle;

  /// No description provided for @editorWorkbenchConvertDesc.
  ///
  /// In zh, this message translates to:
  /// **'只转换当前章节标题和正文；原文件不会重新识别'**
  String get editorWorkbenchConvertDesc;

  /// No description provided for @editorWorkbenchConvertDirection.
  ///
  /// In zh, this message translates to:
  /// **'转换方向'**
  String get editorWorkbenchConvertDirection;

  /// No description provided for @editorWorkbenchConvertSimplified.
  ///
  /// In zh, this message translates to:
  /// **'繁体转简体'**
  String get editorWorkbenchConvertSimplified;

  /// No description provided for @editorWorkbenchConvertTraditional.
  ///
  /// In zh, this message translates to:
  /// **'简体转台湾繁体'**
  String get editorWorkbenchConvertTraditional;

  /// No description provided for @editorWorkbenchPreviewConvert.
  ///
  /// In zh, this message translates to:
  /// **'预览转换'**
  String get editorWorkbenchPreviewConvert;

  /// No description provided for @editorWorkbenchReplaceLabel.
  ///
  /// In zh, this message translates to:
  /// **'替换'**
  String get editorWorkbenchReplaceLabel;

  /// No description provided for @editorWorkbenchRenumberLabel.
  ///
  /// In zh, this message translates to:
  /// **'重编号'**
  String get editorWorkbenchRenumberLabel;

  /// No description provided for @editorWorkbenchConvertLabel.
  ///
  /// In zh, this message translates to:
  /// **'繁简转换'**
  String get editorWorkbenchConvertLabel;

  /// No description provided for @editorWorkbenchBatchEdit.
  ///
  /// In zh, this message translates to:
  /// **'批量修改'**
  String get editorWorkbenchBatchEdit;

  /// No description provided for @editorWorkbenchPreviewTitle.
  ///
  /// In zh, this message translates to:
  /// **'{operation}预览'**
  String editorWorkbenchPreviewTitle(String operation);

  /// No description provided for @editorWorkbenchPreviewStats.
  ///
  /// In zh, this message translates to:
  /// **'命中 {hits} 处，实际修改 {fields} 个字段。'**
  String editorWorkbenchPreviewStats(int hits, int fields);

  /// No description provided for @editorWorkbenchBodyParagraph.
  ///
  /// In zh, this message translates to:
  /// **'正文段落'**
  String get editorWorkbenchBodyParagraph;

  /// No description provided for @editorWorkbenchApplyOneUndo.
  ///
  /// In zh, this message translates to:
  /// **'执行修改（可撤销一步）'**
  String get editorWorkbenchApplyOneUndo;

  /// No description provided for @editorWorkbenchIssueMissingNumber.
  ///
  /// In zh, this message translates to:
  /// **'缺失章号'**
  String get editorWorkbenchIssueMissingNumber;

  /// No description provided for @editorWorkbenchIssueDuplicateNumber.
  ///
  /// In zh, this message translates to:
  /// **'重复章号'**
  String get editorWorkbenchIssueDuplicateNumber;

  /// No description provided for @editorWorkbenchIssueEmptyChapter.
  ///
  /// In zh, this message translates to:
  /// **'空章'**
  String get editorWorkbenchIssueEmptyChapter;

  /// No description provided for @editorWorkbenchIssueDuplicateTitle.
  ///
  /// In zh, this message translates to:
  /// **'重复标题'**
  String get editorWorkbenchIssueDuplicateTitle;

  /// No description provided for @editorWorkbenchIssueTooLong.
  ///
  /// In zh, this message translates to:
  /// **'长章'**
  String get editorWorkbenchIssueTooLong;

  /// No description provided for @editorWorkbenchIssueTooShort.
  ///
  /// In zh, this message translates to:
  /// **'短章'**
  String get editorWorkbenchIssueTooShort;

  /// No description provided for @editorWorkbenchIssueEmptyVolume.
  ///
  /// In zh, this message translates to:
  /// **'空卷'**
  String get editorWorkbenchIssueEmptyVolume;

  /// No description provided for @editorWorkbenchIssueAdLeftover.
  ///
  /// In zh, this message translates to:
  /// **'广告痕迹'**
  String get editorWorkbenchIssueAdLeftover;

  /// No description provided for @editorWorkbenchReparseInvalidRuleUtf8.
  ///
  /// In zh, this message translates to:
  /// **'规则 JSON 不是有效的 UTF-8 文本。'**
  String get editorWorkbenchReparseInvalidRuleUtf8;

  /// No description provided for @editorWorkbenchReparseFailed.
  ///
  /// In zh, this message translates to:
  /// **'重新识别失败，请检查原文与规则后重试。'**
  String get editorWorkbenchReparseFailed;

  /// No description provided for @editorWorkbenchOriginalCacheFailed.
  ///
  /// In zh, this message translates to:
  /// **'所选原文临时文件未清理，请稍后重试。'**
  String get editorWorkbenchOriginalCacheFailed;

  /// No description provided for @editorWorkbenchRuleCacheFailed.
  ///
  /// In zh, this message translates to:
  /// **'规则临时文件未清理，请稍后重试。'**
  String get editorWorkbenchRuleCacheFailed;

  /// No description provided for @editorWorkbenchRuleTooLarge.
  ///
  /// In zh, this message translates to:
  /// **'规则 JSON 超过 16 KiB'**
  String get editorWorkbenchRuleTooLarge;

  /// No description provided for @editorWorkbenchRuleExported.
  ///
  /// In zh, this message translates to:
  /// **'规则 JSON 已导出。'**
  String get editorWorkbenchRuleExported;

  /// No description provided for @editorWorkbenchReparseChanged.
  ///
  /// In zh, this message translates to:
  /// **'书稿已改变，请重新准备识别结果。'**
  String get editorWorkbenchReparseChanged;

  /// No description provided for @editorWorkbenchReparseConfirmTitle.
  ///
  /// In zh, this message translates to:
  /// **'替换当前全部章节？'**
  String get editorWorkbenchReparseConfirmTitle;

  /// No description provided for @editorWorkbenchReparseConfirmBody.
  ///
  /// In zh, this message translates to:
  /// **'将用刚识别的 {count} 个目录项替换当前书稿的全部章节和正文。此操作会清空当前撤销历史；书名、作者、封面和排版设置会保留。已编辑内容不会保留在新章节中。'**
  String editorWorkbenchReparseConfirmBody(int count);

  /// No description provided for @editorWorkbenchReparseConfirmAction.
  ///
  /// In zh, this message translates to:
  /// **'确认替换'**
  String get editorWorkbenchReparseConfirmAction;

  /// No description provided for @editorWorkbenchPreparedCacheFailed.
  ///
  /// In zh, this message translates to:
  /// **'识别结果临时文件未清理，请稍后重试。'**
  String get editorWorkbenchPreparedCacheFailed;

  /// No description provided for @editorWorkbenchReparseIntro.
  ///
  /// In zh, this message translates to:
  /// **'仅支持已保留原文的 TXT。先准备预览，再明确确认替换当前全部章节。转换当前书稿请使用书稿工具。'**
  String get editorWorkbenchReparseIntro;

  /// No description provided for @editorWorkbenchSelectOriginal.
  ///
  /// In zh, this message translates to:
  /// **'原文缺失时重新选择同一个 TXT'**
  String get editorWorkbenchSelectOriginal;

  /// No description provided for @editorWorkbenchForgetOriginal.
  ///
  /// In zh, this message translates to:
  /// **'不再使用所选原文'**
  String get editorWorkbenchForgetOriginal;

  /// No description provided for @editorWorkbenchSourceEncoding.
  ///
  /// In zh, this message translates to:
  /// **'原文编码'**
  String get editorWorkbenchSourceEncoding;

  /// No description provided for @editorWorkbenchAutoDetect.
  ///
  /// In zh, this message translates to:
  /// **'自动检测'**
  String get editorWorkbenchAutoDetect;

  /// No description provided for @editorWorkbenchFilterAds.
  ///
  /// In zh, this message translates to:
  /// **'过滤广告'**
  String get editorWorkbenchFilterAds;

  /// No description provided for @editorWorkbenchRules.
  ///
  /// In zh, this message translates to:
  /// **'识别规则'**
  String get editorWorkbenchRules;

  /// No description provided for @editorWorkbenchCustomRules.
  ///
  /// In zh, this message translates to:
  /// **'自定义规则'**
  String get editorWorkbenchCustomRules;

  /// No description provided for @editorWorkbenchImportRulesJson.
  ///
  /// In zh, this message translates to:
  /// **'导入规则 JSON'**
  String get editorWorkbenchImportRulesJson;

  /// No description provided for @editorWorkbenchExportRulesJson.
  ///
  /// In zh, this message translates to:
  /// **'导出当前规则 JSON'**
  String get editorWorkbenchExportRulesJson;

  /// No description provided for @editorWorkbenchRulesJsonFields.
  ///
  /// In zh, this message translates to:
  /// **'规则 JSON（name / chapter / volume / drop / inlineJunk）'**
  String get editorWorkbenchRulesJsonFields;

  /// No description provided for @editorWorkbenchRulesOnlyReparse.
  ///
  /// In zh, this message translates to:
  /// **'规则只用于重新识别原文；普通批量替换请使用书稿工具。'**
  String get editorWorkbenchRulesOnlyReparse;

  /// No description provided for @editorWorkbenchPrepareReparse.
  ///
  /// In zh, this message translates to:
  /// **'准备重新识别预览'**
  String get editorWorkbenchPrepareReparse;

  /// No description provided for @editorWorkbenchPreparing.
  ///
  /// In zh, this message translates to:
  /// **'准备中…'**
  String get editorWorkbenchPreparing;

  /// No description provided for @editorWorkbenchReparseAppliedUnsaved.
  ///
  /// In zh, this message translates to:
  /// **'章节已替换，尚未保存成功；请使用顶部“重试”。'**
  String get editorWorkbenchReparseAppliedUnsaved;

  /// No description provided for @editorWorkbenchReparseAppliedSaved.
  ///
  /// In zh, this message translates to:
  /// **'已替换当前章节并保存。'**
  String get editorWorkbenchReparseAppliedSaved;

  /// No description provided for @editorWorkbenchReparsePreview.
  ///
  /// In zh, this message translates to:
  /// **'识别结果预览'**
  String get editorWorkbenchReparsePreview;

  /// No description provided for @editorWorkbenchReparseStats.
  ///
  /// In zh, this message translates to:
  /// **'{chapters} 个目录项 · {words} 字'**
  String editorWorkbenchReparseStats(int chapters, int words);

  /// No description provided for @editorWorkbenchSourceEncodingSelected.
  ///
  /// In zh, this message translates to:
  /// **'编码：按所选设置'**
  String get editorWorkbenchSourceEncodingSelected;

  /// No description provided for @editorWorkbenchSourceEncodingActual.
  ///
  /// In zh, this message translates to:
  /// **'实际编码：{encoding}'**
  String editorWorkbenchSourceEncodingActual(String encoding);

  /// No description provided for @editorWorkbenchReparseWarningsLimit.
  ///
  /// In zh, this message translates to:
  /// **'仅显示前 20 条提示。'**
  String get editorWorkbenchReparseWarningsLimit;

  /// No description provided for @editorWorkbenchReparseApply.
  ///
  /// In zh, this message translates to:
  /// **'替换当前全部章节…'**
  String get editorWorkbenchReparseApply;

  /// No description provided for @editorWorkbenchOptionsFileEncoding.
  ///
  /// In zh, this message translates to:
  /// **'文件编码'**
  String get editorWorkbenchOptionsFileEncoding;

  /// No description provided for @editorWorkbenchOptionsAuto.
  ///
  /// In zh, this message translates to:
  /// **'自动'**
  String get editorWorkbenchOptionsAuto;

  /// No description provided for @editorWorkbenchOptionsChapterRules.
  ///
  /// In zh, this message translates to:
  /// **'章节识别'**
  String get editorWorkbenchOptionsChapterRules;

  /// No description provided for @editorWorkbenchOptionsFilterAds.
  ///
  /// In zh, this message translates to:
  /// **'过滤常见广告'**
  String get editorWorkbenchOptionsFilterAds;

  /// No description provided for @editorWorkbenchOptionsEditRules.
  ///
  /// In zh, this message translates to:
  /// **'编辑 JSON 规则'**
  String get editorWorkbenchOptionsEditRules;

  /// No description provided for @editorWorkbenchOptionsImportRules.
  ///
  /// In zh, this message translates to:
  /// **'导入规则'**
  String get editorWorkbenchOptionsImportRules;

  /// No description provided for @editorWorkbenchOptionsExportRules.
  ///
  /// In zh, this message translates to:
  /// **'导出规则'**
  String get editorWorkbenchOptionsExportRules;

  /// No description provided for @editorWorkbenchOptionsRemoveRules.
  ///
  /// In zh, this message translates to:
  /// **'移除自定义规则'**
  String get editorWorkbenchOptionsRemoveRules;

  /// No description provided for @editorWorkbenchOptionsCurrentRules.
  ///
  /// In zh, this message translates to:
  /// **'当前规则：{name}'**
  String editorWorkbenchOptionsCurrentRules(String name);

  /// No description provided for @editorWorkbenchOptionsConvertAtImport.
  ///
  /// In zh, this message translates to:
  /// **'导入时简繁转换'**
  String get editorWorkbenchOptionsConvertAtImport;

  /// No description provided for @editorWorkbenchOptionsKeepOriginal.
  ///
  /// In zh, this message translates to:
  /// **'保持原样'**
  String get editorWorkbenchOptionsKeepOriginal;

  /// No description provided for @editorWorkbenchOptionsToSimplified.
  ///
  /// In zh, this message translates to:
  /// **'转为简体'**
  String get editorWorkbenchOptionsToSimplified;

  /// No description provided for @editorWorkbenchOptionsToTaiwan.
  ///
  /// In zh, this message translates to:
  /// **'台湾标准繁体'**
  String get editorWorkbenchOptionsToTaiwan;

  /// No description provided for @editorWorkbenchOptionsRulesTitle.
  ///
  /// In zh, this message translates to:
  /// **'JSON 识别规则'**
  String get editorWorkbenchOptionsRulesTitle;

  /// No description provided for @editorWorkbenchOptionsRulesHelp.
  ///
  /// In zh, this message translates to:
  /// **'字段：name、chapter、volume、drop、inlineJunk。规则独立于广告开关；危险或不支持的正则会被拒绝。'**
  String get editorWorkbenchOptionsRulesHelp;

  /// No description provided for @editorWorkbenchOptionsValidateApply.
  ///
  /// In zh, this message translates to:
  /// **'校验并应用'**
  String get editorWorkbenchOptionsValidateApply;

  /// No description provided for @editorWorkbenchRulePresetIxdzs.
  ///
  /// In zh, this message translates to:
  /// **'爱下电子书'**
  String get editorWorkbenchRulePresetIxdzs;

  /// No description provided for @editorWorkbenchRulePresetBiquge.
  ///
  /// In zh, this message translates to:
  /// **'笔趣阁'**
  String get editorWorkbenchRulePresetBiquge;

  /// No description provided for @editorWorkbenchRulePresetNumbered.
  ///
  /// In zh, this message translates to:
  /// **'数字标题'**
  String get editorWorkbenchRulePresetNumbered;

  /// No description provided for @editorWorkbenchRulePresetBareNumber.
  ///
  /// In zh, this message translates to:
  /// **'裸数字'**
  String get editorWorkbenchRulePresetBareNumber;

  /// No description provided for @editorWorkbenchRulePresetEnglish.
  ///
  /// In zh, this message translates to:
  /// **'英文标题'**
  String get editorWorkbenchRulePresetEnglish;

  /// No description provided for @bookWorkbenchSettings.
  ///
  /// In zh, this message translates to:
  /// **'成书设置'**
  String get bookWorkbenchSettings;

  /// No description provided for @bookWorkbenchMetadata.
  ///
  /// In zh, this message translates to:
  /// **'书籍信息'**
  String get bookWorkbenchMetadata;

  /// No description provided for @bookWorkbenchLayoutFonts.
  ///
  /// In zh, this message translates to:
  /// **'排版与字体'**
  String get bookWorkbenchLayoutFonts;

  /// No description provided for @bookWorkbenchCover.
  ///
  /// In zh, this message translates to:
  /// **'封面'**
  String get bookWorkbenchCover;

  /// No description provided for @bookWorkbenchReadingPreview.
  ///
  /// In zh, this message translates to:
  /// **'阅读预览'**
  String get bookWorkbenchReadingPreview;

  /// No description provided for @bookWorkbenchTitleRequired.
  ///
  /// In zh, this message translates to:
  /// **'书名不能为空'**
  String get bookWorkbenchTitleRequired;

  /// No description provided for @bookWorkbenchMoreInformation.
  ///
  /// In zh, this message translates to:
  /// **'扩展信息'**
  String get bookWorkbenchMoreInformation;

  /// No description provided for @bookWorkbenchLanguageCodeHint.
  ///
  /// In zh, this message translates to:
  /// **'使用 zh-CN 这类语言代码'**
  String get bookWorkbenchLanguageCodeHint;

  /// No description provided for @bookWorkbenchPublicationDate.
  ///
  /// In zh, this message translates to:
  /// **'出版日期（YYYY-MM-DD）'**
  String get bookWorkbenchPublicationDate;

  /// No description provided for @bookWorkbenchInvalidDate.
  ///
  /// In zh, this message translates to:
  /// **'请输入有效日期'**
  String get bookWorkbenchInvalidDate;

  /// No description provided for @bookWorkbenchLineHeight.
  ///
  /// In zh, this message translates to:
  /// **'行高 {value}'**
  String bookWorkbenchLineHeight(String value);

  /// No description provided for @bookWorkbenchParagraphSpacing.
  ///
  /// In zh, this message translates to:
  /// **'段间距 {value} em'**
  String bookWorkbenchParagraphSpacing(String value);

  /// No description provided for @bookWorkbenchTwoCharacterIndent.
  ///
  /// In zh, this message translates to:
  /// **'首行缩进两字'**
  String get bookWorkbenchTwoCharacterIndent;

  /// No description provided for @bookWorkbenchJustify.
  ///
  /// In zh, this message translates to:
  /// **'两端对齐'**
  String get bookWorkbenchJustify;

  /// No description provided for @bookWorkbenchSeparateChapterNumber.
  ///
  /// In zh, this message translates to:
  /// **'章号独行'**
  String get bookWorkbenchSeparateChapterNumber;

  /// No description provided for @bookWorkbenchBodyFontStyle.
  ///
  /// In zh, this message translates to:
  /// **'正文样式'**
  String get bookWorkbenchBodyFontStyle;

  /// No description provided for @bookWorkbenchSerif.
  ///
  /// In zh, this message translates to:
  /// **'衬线'**
  String get bookWorkbenchSerif;

  /// No description provided for @bookWorkbenchSans.
  ///
  /// In zh, this message translates to:
  /// **'无衬线'**
  String get bookWorkbenchSans;

  /// No description provided for @bookWorkbenchKai.
  ///
  /// In zh, this message translates to:
  /// **'楷体'**
  String get bookWorkbenchKai;

  /// No description provided for @bookWorkbenchEmbeddedFontInfo.
  ///
  /// In zh, this message translates to:
  /// **'嵌入字体仅作用于支持的导出格式，可能增大文件。'**
  String get bookWorkbenchEmbeddedFontInfo;

  /// No description provided for @bookWorkbenchImportFont.
  ///
  /// In zh, this message translates to:
  /// **'导入字体'**
  String get bookWorkbenchImportFont;

  /// No description provided for @bookWorkbenchRemoveFont.
  ///
  /// In zh, this message translates to:
  /// **'移除引用'**
  String get bookWorkbenchRemoveFont;

  /// No description provided for @bookWorkbenchCustomCssLabel.
  ///
  /// In zh, this message translates to:
  /// **'附加 CSS（仅 EPUB / HTML 导出）'**
  String get bookWorkbenchCustomCssLabel;

  /// No description provided for @bookWorkbenchUnsafeCss.
  ///
  /// In zh, this message translates to:
  /// **'CSS 不允许外链、脚本或不安全字符'**
  String get bookWorkbenchUnsafeCss;

  /// No description provided for @bookWorkbenchCssNativeNote.
  ///
  /// In zh, this message translates to:
  /// **'原生预览不会执行附加 CSS。'**
  String get bookWorkbenchCssNativeNote;

  /// No description provided for @bookWorkbenchTemplate.
  ///
  /// In zh, this message translates to:
  /// **'模板'**
  String get bookWorkbenchTemplate;

  /// No description provided for @bookWorkbenchImage.
  ///
  /// In zh, this message translates to:
  /// **'图片'**
  String get bookWorkbenchImage;

  /// No description provided for @bookWorkbenchChooseCoverFirst.
  ///
  /// In zh, this message translates to:
  /// **'请先选择封面图片。'**
  String get bookWorkbenchChooseCoverFirst;

  /// No description provided for @bookWorkbenchChooseCoverImage.
  ///
  /// In zh, this message translates to:
  /// **'选择封面图片'**
  String get bookWorkbenchChooseCoverImage;

  /// No description provided for @bookWorkbenchCoverLimits.
  ///
  /// In zh, this message translates to:
  /// **'支持 JPEG、PNG、WebP；超过 1200 万像素的图片不会解码。'**
  String get bookWorkbenchCoverLimits;

  /// No description provided for @bookWorkbenchVertical.
  ///
  /// In zh, this message translates to:
  /// **'竖排'**
  String get bookWorkbenchVertical;

  /// No description provided for @bookWorkbenchBlocks.
  ///
  /// In zh, this message translates to:
  /// **'色块'**
  String get bookWorkbenchBlocks;

  /// No description provided for @bookWorkbenchPalette.
  ///
  /// In zh, this message translates to:
  /// **'配色'**
  String get bookWorkbenchPalette;

  /// No description provided for @bookWorkbenchAuto.
  ///
  /// In zh, this message translates to:
  /// **'自动'**
  String get bookWorkbenchAuto;

  /// No description provided for @bookWorkbenchSand.
  ///
  /// In zh, this message translates to:
  /// **'原木'**
  String get bookWorkbenchSand;

  /// No description provided for @bookWorkbenchInk.
  ///
  /// In zh, this message translates to:
  /// **'墨夜'**
  String get bookWorkbenchInk;

  /// No description provided for @bookWorkbenchSea.
  ///
  /// In zh, this message translates to:
  /// **'深海'**
  String get bookWorkbenchSea;

  /// No description provided for @bookWorkbenchWine.
  ///
  /// In zh, this message translates to:
  /// **'酒红'**
  String get bookWorkbenchWine;

  /// No description provided for @bookWorkbenchForest.
  ///
  /// In zh, this message translates to:
  /// **'松林'**
  String get bookWorkbenchForest;

  /// No description provided for @bookWorkbenchTitleScale.
  ///
  /// In zh, this message translates to:
  /// **'标题倍率 {value}'**
  String bookWorkbenchTitleScale(String value);

  /// No description provided for @bookWorkbenchAuthorPosition.
  ///
  /// In zh, this message translates to:
  /// **'作者位置'**
  String get bookWorkbenchAuthorPosition;

  /// No description provided for @bookWorkbenchTop.
  ///
  /// In zh, this message translates to:
  /// **'上方'**
  String get bookWorkbenchTop;

  /// No description provided for @bookWorkbenchBottom.
  ///
  /// In zh, this message translates to:
  /// **'下方'**
  String get bookWorkbenchBottom;

  /// No description provided for @bookWorkbenchHidden.
  ///
  /// In zh, this message translates to:
  /// **'隐藏'**
  String get bookWorkbenchHidden;

  /// No description provided for @bookWorkbenchImageModeNote.
  ///
  /// In zh, this message translates to:
  /// **'调整模板参数不会覆盖当前图片；切换到模板后应用。'**
  String get bookWorkbenchImageModeNote;

  /// No description provided for @bookWorkbenchPreviewCss.
  ///
  /// In zh, this message translates to:
  /// **'附加 CSS 仅影响 EPUB / HTML 导出，原生预览不会执行。'**
  String get bookWorkbenchPreviewCss;

  /// No description provided for @bookWorkbenchPreviewWoff.
  ///
  /// In zh, this message translates to:
  /// **'WOFF 字体会嵌入 EPUB；原生预览暂不加载此格式。'**
  String get bookWorkbenchPreviewWoff;

  /// No description provided for @bookWorkbenchPreviewFontMissing.
  ///
  /// In zh, this message translates to:
  /// **'字体资源暂不可用；原生预览使用系统字型。'**
  String get bookWorkbenchPreviewFontMissing;

  /// No description provided for @bookWorkbenchPreviewFontFailed.
  ///
  /// In zh, this message translates to:
  /// **'字体无法在原生预览加载；导出仍会保留此资源。'**
  String get bookWorkbenchPreviewFontFailed;

  /// No description provided for @bookWorkbenchPreviewFontUnsupported.
  ///
  /// In zh, this message translates to:
  /// **'此字体格式不支持原生预览。'**
  String get bookWorkbenchPreviewFontUnsupported;

  /// No description provided for @bookWorkbenchPreviewFontLoaded.
  ///
  /// In zh, this message translates to:
  /// **'嵌入字体已在原生预览加载。'**
  String get bookWorkbenchPreviewFontLoaded;

  /// No description provided for @bookWorkbenchPreviewLimits.
  ///
  /// In zh, this message translates to:
  /// **'原生预览展示基础排版；阅读器分页与字体替换可能不同。TXT / Markdown 不保留视觉排版。'**
  String get bookWorkbenchPreviewLimits;

  /// No description provided for @bookWorkbenchPreviewIllustration.
  ///
  /// In zh, this message translates to:
  /// **'插图（此预览只显示说明）：{caption}'**
  String bookWorkbenchPreviewIllustration(String caption);

  /// No description provided for @bookWorkbenchNewBookDefaults.
  ///
  /// In zh, this message translates to:
  /// **'新书默认设置'**
  String get bookWorkbenchNewBookDefaults;

  /// No description provided for @bookWorkbenchDefaultsScope.
  ///
  /// In zh, this message translates to:
  /// **'只影响以后导入的新书；已有书籍使用自己的排版。'**
  String get bookWorkbenchDefaultsScope;

  /// No description provided for @bookWorkbenchDefaultExportFormat.
  ///
  /// In zh, this message translates to:
  /// **'默认导出格式'**
  String get bookWorkbenchDefaultExportFormat;

  /// No description provided for @bookWorkbenchDefaultFontRole.
  ///
  /// In zh, this message translates to:
  /// **'默认字体角色'**
  String get bookWorkbenchDefaultFontRole;

  /// No description provided for @bookWorkbenchDefaultsLineHeight.
  ///
  /// In zh, this message translates to:
  /// **'行高：{value}'**
  String bookWorkbenchDefaultsLineHeight(String value);

  /// No description provided for @bookWorkbenchDefaultsIndent.
  ///
  /// In zh, this message translates to:
  /// **'首行缩进'**
  String get bookWorkbenchDefaultsIndent;

  /// No description provided for @bookWorkbenchSelectedFont.
  ///
  /// In zh, this message translates to:
  /// **'已选择字体：{mime}'**
  String bookWorkbenchSelectedFont(String mime);

  /// No description provided for @bookWorkbenchLoading.
  ///
  /// In zh, this message translates to:
  /// **'正在读取'**
  String get bookWorkbenchLoading;

  /// No description provided for @bookWorkbenchCoverSemantics.
  ///
  /// In zh, this message translates to:
  /// **'{title} 的封面'**
  String bookWorkbenchCoverSemantics(String title);

  /// No description provided for @bookWorkbenchCoverUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'封面图片不可用'**
  String get bookWorkbenchCoverUnavailable;

  /// No description provided for @dataWorkbenchBatchTitle.
  ///
  /// In zh, this message translates to:
  /// **'批量任务'**
  String get dataWorkbenchBatchTitle;

  /// No description provided for @dataWorkbenchBatchSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'逐本处理，转换结果只在保存 ZIP 后离开应用。'**
  String get dataWorkbenchBatchSubtitle;

  /// No description provided for @dataWorkbenchBatchSettings.
  ///
  /// In zh, this message translates to:
  /// **'任务设置'**
  String get dataWorkbenchBatchSettings;

  /// No description provided for @dataWorkbenchBatchAction.
  ///
  /// In zh, this message translates to:
  /// **'操作'**
  String get dataWorkbenchBatchAction;

  /// No description provided for @dataWorkbenchBatchAddToLibrary.
  ///
  /// In zh, this message translates to:
  /// **'加入书架'**
  String get dataWorkbenchBatchAddToLibrary;

  /// No description provided for @dataWorkbenchBatchConvertFiles.
  ///
  /// In zh, this message translates to:
  /// **'批量转换'**
  String get dataWorkbenchBatchConvertFiles;

  /// No description provided for @dataWorkbenchOutputFormat.
  ///
  /// In zh, this message translates to:
  /// **'输出格式'**
  String get dataWorkbenchOutputFormat;

  /// No description provided for @dataWorkbenchBatchTxtEncoding.
  ///
  /// In zh, this message translates to:
  /// **'TXT 编码'**
  String get dataWorkbenchBatchTxtEncoding;

  /// No description provided for @dataWorkbenchBatchChineseConversion.
  ///
  /// In zh, this message translates to:
  /// **'简繁转换'**
  String get dataWorkbenchBatchChineseConversion;

  /// No description provided for @dataWorkbenchBatchNoConversion.
  ///
  /// In zh, this message translates to:
  /// **'不转换'**
  String get dataWorkbenchBatchNoConversion;

  /// No description provided for @dataWorkbenchBatchSimplified.
  ///
  /// In zh, this message translates to:
  /// **'转简体'**
  String get dataWorkbenchBatchSimplified;

  /// No description provided for @dataWorkbenchBatchTaiwanTraditional.
  ///
  /// In zh, this message translates to:
  /// **'转台湾繁体'**
  String get dataWorkbenchBatchTaiwanTraditional;

  /// No description provided for @dataWorkbenchBatchFilterAds.
  ///
  /// In zh, this message translates to:
  /// **'过滤广告'**
  String get dataWorkbenchBatchFilterAds;

  /// No description provided for @dataWorkbenchBatchChooseFiles.
  ///
  /// In zh, this message translates to:
  /// **'选择 TXT / EPUB / DOCX'**
  String get dataWorkbenchBatchChooseFiles;

  /// No description provided for @dataWorkbenchBatchStart.
  ///
  /// In zh, this message translates to:
  /// **'开始'**
  String get dataWorkbenchBatchStart;

  /// No description provided for @dataWorkbenchBatchCancelAfterSave.
  ///
  /// In zh, this message translates to:
  /// **'完成当前保存后取消剩余项'**
  String get dataWorkbenchBatchCancelAfterSave;

  /// No description provided for @dataWorkbenchBatchCancelRemaining.
  ///
  /// In zh, this message translates to:
  /// **'取消剩余任务'**
  String get dataWorkbenchBatchCancelRemaining;

  /// No description provided for @dataWorkbenchBatchQueue.
  ///
  /// In zh, this message translates to:
  /// **'队列'**
  String get dataWorkbenchBatchQueue;

  /// No description provided for @dataWorkbenchRetryFailedOnly.
  ///
  /// In zh, this message translates to:
  /// **'只重试失败项'**
  String get dataWorkbenchRetryFailedOnly;

  /// No description provided for @dataWorkbenchBatchSaveZip.
  ///
  /// In zh, this message translates to:
  /// **'保存 ZIP'**
  String get dataWorkbenchBatchSaveZip;

  /// No description provided for @dataWorkbenchZipSaved.
  ///
  /// In zh, this message translates to:
  /// **'ZIP 已保存。'**
  String get dataWorkbenchZipSaved;

  /// No description provided for @dataWorkbenchBatchSaveCancelled.
  ///
  /// In zh, this message translates to:
  /// **'已取消保存，转换结果仍可重试保存。'**
  String get dataWorkbenchBatchSaveCancelled;

  /// No description provided for @dataWorkbenchBatchRetryEncoding.
  ///
  /// In zh, this message translates to:
  /// **'重试编码'**
  String get dataWorkbenchBatchRetryEncoding;

  /// No description provided for @dataWorkbenchBatchAuto.
  ///
  /// In zh, this message translates to:
  /// **'自动'**
  String get dataWorkbenchBatchAuto;

  /// No description provided for @dataWorkbenchStatusWaiting.
  ///
  /// In zh, this message translates to:
  /// **'等待'**
  String get dataWorkbenchStatusWaiting;

  /// No description provided for @dataWorkbenchStatusProcessing.
  ///
  /// In zh, this message translates to:
  /// **'处理中'**
  String get dataWorkbenchStatusProcessing;

  /// No description provided for @dataWorkbenchStatusSuccess.
  ///
  /// In zh, this message translates to:
  /// **'成功'**
  String get dataWorkbenchStatusSuccess;

  /// No description provided for @dataWorkbenchStatusFailed.
  ///
  /// In zh, this message translates to:
  /// **'失败'**
  String get dataWorkbenchStatusFailed;

  /// No description provided for @dataWorkbenchStatusCancelled.
  ///
  /// In zh, this message translates to:
  /// **'已取消'**
  String get dataWorkbenchStatusCancelled;

  /// No description provided for @dataWorkbenchBatchPickFailed.
  ///
  /// In zh, this message translates to:
  /// **'文件选择或清理失败。'**
  String get dataWorkbenchBatchPickFailed;

  /// No description provided for @dataWorkbenchBatchStartFailed.
  ///
  /// In zh, this message translates to:
  /// **'批量任务无法启动。'**
  String get dataWorkbenchBatchStartFailed;

  /// No description provided for @dataWorkbenchZipSaveFailed.
  ///
  /// In zh, this message translates to:
  /// **'ZIP 保存失败，请重试。'**
  String get dataWorkbenchZipSaveFailed;

  /// No description provided for @dataWorkbenchLibraryTitle.
  ///
  /// In zh, this message translates to:
  /// **'批量导出已选书籍'**
  String get dataWorkbenchLibraryTitle;

  /// No description provided for @dataWorkbenchLibraryExportSelected.
  ///
  /// In zh, this message translates to:
  /// **'生成所选书籍'**
  String get dataWorkbenchLibraryExportSelected;

  /// No description provided for @dataWorkbenchLibraryFinishingSave.
  ///
  /// In zh, this message translates to:
  /// **'正在完成保存'**
  String get dataWorkbenchLibraryFinishingSave;

  /// No description provided for @dataWorkbenchLibraryCancelRemaining.
  ///
  /// In zh, this message translates to:
  /// **'取消剩余项'**
  String get dataWorkbenchLibraryCancelRemaining;

  /// No description provided for @dataWorkbenchLibrarySaveSuccessfulZip.
  ///
  /// In zh, this message translates to:
  /// **'保存成功项 ZIP'**
  String get dataWorkbenchLibrarySaveSuccessfulZip;

  /// No description provided for @dataWorkbenchLibrarySaveCancelled.
  ///
  /// In zh, this message translates to:
  /// **'已取消保存，结果仍可再次保存。'**
  String get dataWorkbenchLibrarySaveCancelled;

  /// No description provided for @dataWorkbenchLibraryStartFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法启动书架导出。'**
  String get dataWorkbenchLibraryStartFailed;

  /// No description provided for @dataWorkbenchBackupTitle.
  ///
  /// In zh, this message translates to:
  /// **'书籍数据与备份'**
  String get dataWorkbenchBackupTitle;

  /// No description provided for @dataWorkbenchBackupBack.
  ///
  /// In zh, this message translates to:
  /// **'返回'**
  String get dataWorkbenchBackupBack;

  /// No description provided for @dataWorkbenchBackupCurrentBooks.
  ///
  /// In zh, this message translates to:
  /// **'备份当前书籍'**
  String get dataWorkbenchBackupCurrentBooks;

  /// No description provided for @dataWorkbenchBackupIncludes.
  ///
  /// In zh, this message translates to:
  /// **'备份包含当前文字、目录、书籍信息、封面、字体、排版与规则，不包含撤销记录。'**
  String get dataWorkbenchBackupIncludes;

  /// No description provided for @dataWorkbenchBackupIncludeSources.
  ///
  /// In zh, this message translates to:
  /// **'包含原始文件'**
  String get dataWorkbenchBackupIncludeSources;

  /// No description provided for @dataWorkbenchBackupWithoutSources.
  ///
  /// In zh, this message translates to:
  /// **'不含原文的备份仍可续编，但无法从原文件换编码或重新分章。'**
  String get dataWorkbenchBackupWithoutSources;

  /// No description provided for @dataWorkbenchBackupSaveFile.
  ///
  /// In zh, this message translates to:
  /// **'生成并保存 .bookloom'**
  String get dataWorkbenchBackupSaveFile;

  /// No description provided for @dataWorkbenchBackupRestore.
  ///
  /// In zh, this message translates to:
  /// **'恢复备份'**
  String get dataWorkbenchBackupRestore;

  /// No description provided for @dataWorkbenchBackupMaxData.
  ///
  /// In zh, this message translates to:
  /// **'最大恢复数据量（MiB）'**
  String get dataWorkbenchBackupMaxData;

  /// No description provided for @dataWorkbenchBackupMaxDataHelp.
  ///
  /// In zh, this message translates to:
  /// **'按实际解压数据计量；备份副本、临时数据库与提交副本还需额外空间。'**
  String get dataWorkbenchBackupMaxDataHelp;

  /// No description provided for @dataWorkbenchBackupChooseInspect.
  ///
  /// In zh, this message translates to:
  /// **'选择并检查备份'**
  String get dataWorkbenchBackupChooseInspect;

  /// No description provided for @dataWorkbenchBackupConflictPolicy.
  ///
  /// In zh, this message translates to:
  /// **'相同 ID 的书籍'**
  String get dataWorkbenchBackupConflictPolicy;

  /// No description provided for @dataWorkbenchBackupKeepBoth.
  ///
  /// In zh, this message translates to:
  /// **'保留两份'**
  String get dataWorkbenchBackupKeepBoth;

  /// No description provided for @dataWorkbenchBackupSkipConflicts.
  ///
  /// In zh, this message translates to:
  /// **'跳过备份中的同 ID 书'**
  String get dataWorkbenchBackupSkipConflicts;

  /// No description provided for @dataWorkbenchBackupOverwriteConflicts.
  ///
  /// In zh, this message translates to:
  /// **'用备份覆盖同 ID 书'**
  String get dataWorkbenchBackupOverwriteConflicts;

  /// No description provided for @dataWorkbenchBackupCommitHelp.
  ///
  /// In zh, this message translates to:
  /// **'逐本提交；若中途失败，已成功恢复的书会保留，失败项会明确列出。未涉及的书籍保持原状。'**
  String get dataWorkbenchBackupCommitHelp;

  /// No description provided for @dataWorkbenchBackupConfirmRestore.
  ///
  /// In zh, this message translates to:
  /// **'确认恢复'**
  String get dataWorkbenchBackupConfirmRestore;

  /// No description provided for @dataWorkbenchBackupDiscardPreview.
  ///
  /// In zh, this message translates to:
  /// **'放弃预览'**
  String get dataWorkbenchBackupDiscardPreview;

  /// No description provided for @dataWorkbenchBackupCancelAfterCommit.
  ///
  /// In zh, this message translates to:
  /// **'正在完成当前书的提交，取消后续项目'**
  String get dataWorkbenchBackupCancelAfterCommit;

  /// No description provided for @dataWorkbenchBackupCancelTask.
  ///
  /// In zh, this message translates to:
  /// **'取消任务'**
  String get dataWorkbenchBackupCancelTask;

  /// No description provided for @dataWorkbenchBackupSaved.
  ///
  /// In zh, this message translates to:
  /// **'备份已保存。'**
  String get dataWorkbenchBackupSaved;

  /// No description provided for @dataWorkbenchBackupOverwriteTitle.
  ///
  /// In zh, this message translates to:
  /// **'覆盖同 ID 书稿？'**
  String get dataWorkbenchBackupOverwriteTitle;

  /// No description provided for @dataWorkbenchBackupOverwriteBody.
  ///
  /// In zh, this message translates to:
  /// **'备份中的当前内容将替换同 ID 书稿，不能通过会话撤销恢复。'**
  String get dataWorkbenchBackupOverwriteBody;

  /// No description provided for @dataWorkbenchBackupOverwriteRestore.
  ///
  /// In zh, this message translates to:
  /// **'覆盖并恢复'**
  String get dataWorkbenchBackupOverwriteRestore;

  /// No description provided for @dataWorkbenchBackupTaskCancelled.
  ///
  /// In zh, this message translates to:
  /// **'任务已取消。'**
  String get dataWorkbenchBackupTaskCancelled;

  /// No description provided for @dataWorkbenchBatchSelectedFiles.
  ///
  /// In zh, this message translates to:
  /// **'已选 {count} 个文件'**
  String dataWorkbenchBatchSelectedFiles(int count);

  /// No description provided for @dataWorkbenchBatchSummary.
  ///
  /// In zh, this message translates to:
  /// **'成功 {success} · 失败 {failed} · 共 {total}'**
  String dataWorkbenchBatchSummary(int success, int failed, int total);

  /// No description provided for @dataWorkbenchLibrarySelected.
  ///
  /// In zh, this message translates to:
  /// **'当前选中 {count} 本；每批最多 40 本。'**
  String dataWorkbenchLibrarySelected(int count);

  /// No description provided for @dataWorkbenchLibrarySummary.
  ///
  /// In zh, this message translates to:
  /// **'本次队列：成功 {success} · 失败 {failed} · 共 {total}'**
  String dataWorkbenchLibrarySummary(int success, int failed, int total);

  /// No description provided for @dataWorkbenchBackupStorage.
  ///
  /// In zh, this message translates to:
  /// **'应用数据：{support}；缓存：{cache}'**
  String dataWorkbenchBackupStorage(String support, String cache);

  /// No description provided for @dataWorkbenchBackupValidated.
  ///
  /// In zh, this message translates to:
  /// **'已校验 {count} 本；数据 {size}'**
  String dataWorkbenchBackupValidated(int count, String size);

  /// No description provided for @dataWorkbenchBackupEstimatedSpace.
  ///
  /// In zh, this message translates to:
  /// **'预计所需空间（估算）：{size}'**
  String dataWorkbenchBackupEstimatedSpace(String size);

  /// No description provided for @dataWorkbenchBackupPreviewBook.
  ///
  /// In zh, this message translates to:
  /// **'{title} · {chapters} 章 · {words}'**
  String dataWorkbenchBackupPreviewBook(String title, int chapters, int words);

  /// No description provided for @dataWorkbenchBackupRestored.
  ///
  /// In zh, this message translates to:
  /// **'恢复成功 {count}'**
  String dataWorkbenchBackupRestored(int count);

  /// No description provided for @dataWorkbenchBackupSkipped.
  ///
  /// In zh, this message translates to:
  /// **'跳过 {count}'**
  String dataWorkbenchBackupSkipped(int count);

  /// No description provided for @dataWorkbenchBackupCancelled.
  ///
  /// In zh, this message translates to:
  /// **'取消 {count}'**
  String dataWorkbenchBackupCancelled(int count);

  /// No description provided for @exportWorkbenchShareTitle.
  ///
  /// In zh, this message translates to:
  /// **'分享书稿'**
  String get exportWorkbenchShareTitle;

  /// No description provided for @exportWorkbenchExportTitle.
  ///
  /// In zh, this message translates to:
  /// **'导出书稿'**
  String get exportWorkbenchExportTitle;

  /// No description provided for @exportWorkbenchFormatLabel.
  ///
  /// In zh, this message translates to:
  /// **'文件格式'**
  String get exportWorkbenchFormatLabel;

  /// No description provided for @exportWorkbenchEpubDescription.
  ///
  /// In zh, this message translates to:
  /// **'保留封面、卷章目录、书籍信息、排版和嵌入字体。阅读器可能使用自己的分页与字体。'**
  String get exportWorkbenchEpubDescription;

  /// No description provided for @exportWorkbenchDocxDescription.
  ///
  /// In zh, this message translates to:
  /// **'生成可编辑的标题和段落，映射基础排版。此格式不包含封面、插图和全部扩展元数据。'**
  String get exportWorkbenchDocxDescription;

  /// No description provided for @exportWorkbenchHtmlDescription.
  ///
  /// In zh, this message translates to:
  /// **'生成离线单文件网页，包含目录和内联样式，不包含封面、插图或外部资源。'**
  String get exportWorkbenchHtmlDescription;

  /// No description provided for @exportWorkbenchTextDescription.
  ///
  /// In zh, this message translates to:
  /// **'保留文字与卷章结构；字体、封面、CSS 和视觉排版不适用于此格式。'**
  String get exportWorkbenchTextDescription;

  /// No description provided for @exportWorkbenchDeviceHelpAction.
  ///
  /// In zh, this message translates to:
  /// **'如何传到阅读设备'**
  String get exportWorkbenchDeviceHelpAction;

  /// No description provided for @exportWorkbenchShareAction.
  ///
  /// In zh, this message translates to:
  /// **'打开分享面板'**
  String get exportWorkbenchShareAction;

  /// No description provided for @exportWorkbenchSaveAction.
  ///
  /// In zh, this message translates to:
  /// **'选择保存位置'**
  String get exportWorkbenchSaveAction;

  /// No description provided for @exportWorkbenchDeviceHelpTitle.
  ///
  /// In zh, this message translates to:
  /// **'导入到阅读设备'**
  String get exportWorkbenchDeviceHelpTitle;

  /// No description provided for @exportWorkbenchDeviceHelpIntro.
  ///
  /// In zh, this message translates to:
  /// **'先把书稿导出并保存为文件，再按阅读设备的导入方式传送。不同机型和固件支持的格式、菜单可能不同，请以设备说明为准；传送后在设备上打开文件检查目录和排版。'**
  String get exportWorkbenchDeviceHelpIntro;

  /// No description provided for @exportWorkbenchOfficialInfoAction.
  ///
  /// In zh, this message translates to:
  /// **'打开官方说明'**
  String get exportWorkbenchOfficialInfoAction;

  /// No description provided for @exportWorkbenchKindleName.
  ///
  /// In zh, this message translates to:
  /// **'Kindle'**
  String get exportWorkbenchKindleName;

  /// No description provided for @exportWorkbenchKindleSteps.
  ///
  /// In zh, this message translates to:
  /// **'Amazon 的 Send to Kindle 可接收 EPUB。保存文件后，主动打开其网页上传，再在 Kindle 上查看个人文档。该服务需要联网；设备收到文件后再检查显示效果。'**
  String get exportWorkbenchKindleSteps;

  /// No description provided for @exportWorkbenchKoboName.
  ///
  /// In zh, this message translates to:
  /// **'Kobo'**
  String get exportWorkbenchKoboName;

  /// No description provided for @exportWorkbenchKoboSteps.
  ///
  /// In zh, this message translates to:
  /// **'Kobo 官方说明提供未加 DRM 的 EPUB 文件的 USB 传送步骤：连接设备、在设备上确认连接、把文件复制到设备盘，安全弹出后在“我的书籍”查看。'**
  String get exportWorkbenchKoboSteps;

  /// No description provided for @exportWorkbenchBooxName.
  ///
  /// In zh, this message translates to:
  /// **'BOOX / 文石'**
  String get exportWorkbenchBooxName;

  /// No description provided for @exportWorkbenchBooxSteps.
  ///
  /// In zh, this message translates to:
  /// **'部分固件提供 BooxDrop。若你的设备有此入口，可按设备显示的地址，在同一 Wi-Fi 网络中从电脑传送文件；菜单和支持格式请按当前机型核对。'**
  String get exportWorkbenchBooxSteps;

  /// No description provided for @exportWorkbenchHanvonName.
  ///
  /// In zh, this message translates to:
  /// **'汉王 / Hanvon'**
  String get exportWorkbenchHanvonName;

  /// No description provided for @exportWorkbenchHanvonSteps.
  ///
  /// In zh, this message translates to:
  /// **'先核对当前机型的说明书，确认可读取的格式和 USB、传书或本地导入入口。完成传送后在设备书架中打开检查。官方页面只描述其所列机型，不代表所有汉王设备。'**
  String get exportWorkbenchHanvonSteps;

  /// No description provided for @exportWorkbenchIreaderName.
  ///
  /// In zh, this message translates to:
  /// **'掌阅 / iReader'**
  String get exportWorkbenchIreaderName;

  /// No description provided for @exportWorkbenchIreaderSteps.
  ///
  /// In zh, this message translates to:
  /// **'先在当前机型或应用的帮助中确认支持格式及本地导入、传书入口；导出后按其提示选择文件，并在书架检查。不同 iReader 设备和应用版本可能不同。'**
  String get exportWorkbenchIreaderSteps;

  /// No description provided for @dataWorkbenchBackupAnotherTaskRunning.
  ///
  /// In zh, this message translates to:
  /// **'另一项任务正在运行。'**
  String get dataWorkbenchBackupAnotherTaskRunning;

  /// No description provided for @dataWorkbenchBackupInvalidBudget.
  ///
  /// In zh, this message translates to:
  /// **'请输入 1 到 1048576 MiB 的写入预算。'**
  String get dataWorkbenchBackupInvalidBudget;

  /// No description provided for @dataWorkbenchBackupFileTooLarge.
  ///
  /// In zh, this message translates to:
  /// **'备份文件超过本次写入预算。'**
  String get dataWorkbenchBackupFileTooLarge;

  /// No description provided for @dataWorkbenchBackupActualSizeTooLarge.
  ///
  /// In zh, this message translates to:
  /// **'备份文件实际大小超过本次预算。'**
  String get dataWorkbenchBackupActualSizeTooLarge;

  /// No description provided for @editorWorkbenchReparsePresetBiquge.
  ///
  /// In zh, this message translates to:
  /// **'笔趣阁系'**
  String get editorWorkbenchReparsePresetBiquge;

  /// No description provided for @editorWorkbenchReparsePresetBareNumber.
  ///
  /// In zh, this message translates to:
  /// **'裸数字标题'**
  String get editorWorkbenchReparsePresetBareNumber;

  /// No description provided for @editorWorkbenchReparsePresetEnglish.
  ///
  /// In zh, this message translates to:
  /// **'英文 Chapter / Section'**
  String get editorWorkbenchReparsePresetEnglish;

  /// No description provided for @settingsPermissions.
  ///
  /// In zh, this message translates to:
  /// **'权限与访问检查'**
  String get settingsPermissions;

  /// No description provided for @permissionsIntro.
  ///
  /// In zh, this message translates to:
  /// **'仅在使用相关功能时访问必要数据。这里检查应用自身目录；外部文件与保存位置的访问权，需要在实际选择时由系统确认。'**
  String get permissionsIntro;

  /// No description provided for @permissionsRefresh.
  ///
  /// In zh, this message translates to:
  /// **'重新检查'**
  String get permissionsRefresh;

  /// No description provided for @permissionsStorageTitle.
  ///
  /// In zh, this message translates to:
  /// **'应用数据与缓存'**
  String get permissionsStorageTitle;

  /// No description provided for @permissionsStorageHelp.
  ///
  /// In zh, this message translates to:
  /// **'书架、编辑内容、封面和字体保存在应用自身目录。检查只读写一份临时标记并立即清理，不读取或修改已有书稿。系统目录别名或文件损坏不等同于缺少存储权限。'**
  String get permissionsStorageHelp;

  /// No description provided for @permissionsSupport.
  ///
  /// In zh, this message translates to:
  /// **'应用数据'**
  String get permissionsSupport;

  /// No description provided for @permissionsBooks.
  ///
  /// In zh, this message translates to:
  /// **'书稿与资源'**
  String get permissionsBooks;

  /// No description provided for @permissionsCache.
  ///
  /// In zh, this message translates to:
  /// **'临时缓存'**
  String get permissionsCache;

  /// No description provided for @permissionsReadReady.
  ///
  /// In zh, this message translates to:
  /// **'读取：可用'**
  String get permissionsReadReady;

  /// No description provided for @permissionsReadFailed.
  ///
  /// In zh, this message translates to:
  /// **'读取：不可用'**
  String get permissionsReadFailed;

  /// No description provided for @permissionsWriteReady.
  ///
  /// In zh, this message translates to:
  /// **'写入：可用'**
  String get permissionsWriteReady;

  /// No description provided for @permissionsWriteFailed.
  ///
  /// In zh, this message translates to:
  /// **'写入：不可用'**
  String get permissionsWriteFailed;

  /// No description provided for @permissionsCheckFailed.
  ///
  /// In zh, this message translates to:
  /// **'检查未完成，请重试；不要据此判断权限已允许。'**
  String get permissionsCheckFailed;

  /// No description provided for @permissionsSystemTitle.
  ///
  /// In zh, this message translates to:
  /// **'系统权限'**
  String get permissionsSystemTitle;

  /// No description provided for @permissionsNoRuntime.
  ///
  /// In zh, this message translates to:
  /// **'当前安装包没有需要弹窗申请的运行时权限。无需授予全盘存储、照片库、相机、麦克风、通讯录或定位权限来使用书稿功能。'**
  String get permissionsNoRuntime;

  /// No description provided for @permissionsDesktopSystem.
  ///
  /// In zh, this message translates to:
  /// **'桌面端按当前系统账户和目标文件、文件夹的访问控制读写。不能通过一个统一授权开关保证所有位置都可访问。'**
  String get permissionsDesktopSystem;

  /// No description provided for @permissionsSystemUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'无法读取系统权限状态。可重试，或在系统应用设置中查看。'**
  String get permissionsSystemUnavailable;

  /// No description provided for @permissionsGranted.
  ///
  /// In zh, this message translates to:
  /// **'已允许'**
  String get permissionsGranted;

  /// No description provided for @permissionsNotGranted.
  ///
  /// In zh, this message translates to:
  /// **'未允许'**
  String get permissionsNotGranted;

  /// No description provided for @permissionsInternetDeclared.
  ///
  /// In zh, this message translates to:
  /// **'安装包声明了网络访问权限。'**
  String get permissionsInternetDeclared;

  /// No description provided for @permissionsStorageDeclared.
  ///
  /// In zh, this message translates to:
  /// **'安装包声明了广泛存储访问权限，请在系统设置中核对。'**
  String get permissionsStorageDeclared;

  /// No description provided for @permissionsOpenSystemSettings.
  ///
  /// In zh, this message translates to:
  /// **'打开系统应用设置'**
  String get permissionsOpenSystemSettings;

  /// No description provided for @permissionsSettingsFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法打开系统应用设置，请从系统设置中进入书织。'**
  String get permissionsSettingsFailed;

  /// No description provided for @permissionsImportTitle.
  ///
  /// In zh, this message translates to:
  /// **'导入文件、封面与字体'**
  String get permissionsImportTitle;

  /// No description provided for @permissionsImportAndroid.
  ///
  /// In zh, this message translates to:
  /// **'在系统文件选择器中主动选择文件，应用只读取所选项目并复制到自身目录。不扫描其他文件，不覆盖原件；取消选择不会取得访问权。文件提供者的授权失效时，需要重新选择。'**
  String get permissionsImportAndroid;

  /// No description provided for @permissionsImportDesktop.
  ///
  /// In zh, this message translates to:
  /// **'应用只打开你在文件选择器中选定的文件。需要系统账户能够读取该文件；只读检查不会导入书架或修改原件。'**
  String get permissionsImportDesktop;

  /// No description provided for @permissionsReadAction.
  ///
  /// In zh, this message translates to:
  /// **'选择书稿检查读取'**
  String get permissionsReadAction;

  /// No description provided for @permissionsReadSuccess.
  ///
  /// In zh, this message translates to:
  /// **'所选文件可以读取，未导入或修改。'**
  String get permissionsReadSuccess;

  /// No description provided for @permissionsReadFailure.
  ///
  /// In zh, this message translates to:
  /// **'无法读取所选文件，请重新选择或检查文件提供者和系统权限。'**
  String get permissionsReadFailure;

  /// No description provided for @permissionsCancelled.
  ///
  /// In zh, this message translates to:
  /// **'已取消，未取得新的文件访问权。'**
  String get permissionsCancelled;

  /// No description provided for @permissionsExportTitle.
  ///
  /// In zh, this message translates to:
  /// **'导出与备份'**
  String get permissionsExportTitle;

  /// No description provided for @permissionsExportAndroid.
  ///
  /// In zh, this message translates to:
  /// **'由系统“另存为”选择目标，仅向你确认的目标写入成品或备份。无需全盘存储权限。下面的检查会保存一份小型测试 TXT，不包含书稿；可在系统对话框中取消。'**
  String get permissionsExportAndroid;

  /// No description provided for @permissionsExportDesktop.
  ///
  /// In zh, this message translates to:
  /// **'仅写入你选择的保存位置，目标目录需可写。占用、只读、磁盘空间不足等也会导致保存失败。下面的检查会保存一份不含书稿的小型测试 TXT。'**
  String get permissionsExportDesktop;

  /// No description provided for @permissionsSaveAction.
  ///
  /// In zh, this message translates to:
  /// **'选择位置保存测试文件'**
  String get permissionsSaveAction;

  /// No description provided for @permissionsSaveSuccess.
  ///
  /// In zh, this message translates to:
  /// **'测试文件已保存到所选位置。'**
  String get permissionsSaveSuccess;

  /// No description provided for @permissionsSaveFailure.
  ///
  /// In zh, this message translates to:
  /// **'测试文件保存失败，目标访问权尚未确认。'**
  String get permissionsSaveFailure;

  /// No description provided for @permissionsShareTitle.
  ///
  /// In zh, this message translates to:
  /// **'分享与离线处理'**
  String get permissionsShareTitle;

  /// No description provided for @permissionsShareAndroid.
  ///
  /// In zh, this message translates to:
  /// **'分享时只向你选择的接收应用临时授予该成品的只读访问权，不暴露书架目录。打开分享面板不代表对方已收到文件。本地编辑和转换无需联网；外部网页由系统浏览器打开。'**
  String get permissionsShareAndroid;

  /// No description provided for @permissionsShareDesktop.
  ///
  /// In zh, this message translates to:
  /// **'本地编辑和转换无需联网。导出后由你决定是否使用其他工具传送；打开外部网页时交给系统浏览器，不授予该网页书架访问权。'**
  String get permissionsShareDesktop;

  /// No description provided for @permissionsScopeNote.
  ///
  /// In zh, this message translates to:
  /// **'检查结果仅代表当前应用目录或本次选定的文件、目标；不会自动申请其他权限。'**
  String get permissionsScopeNote;

  /// No description provided for @permissionsRuntimePolicy.
  ///
  /// In zh, this message translates to:
  /// **'部分系统会额外列出权限项。当前书稿功能不需要下面这些运行时权限，也不会主动申请；保持关闭不影响通过系统选择器导入和保存。'**
  String get permissionsRuntimePolicy;

  /// No description provided for @permissionsRuntimeNotRequired.
  ///
  /// In zh, this message translates to:
  /// **'非书稿功能所需，不会主动申请，可保持关闭。'**
  String get permissionsRuntimeNotRequired;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
