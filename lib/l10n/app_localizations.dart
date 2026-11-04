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

  /// No description provided for @appNameLatin.
  ///
  /// In zh, this message translates to:
  /// **'Bookloom'**
  String get appNameLatin;

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

  /// No description provided for @sidebarFooter.
  ///
  /// In zh, this message translates to:
  /// **'本地运行 · 不联网'**
  String get sidebarFooter;

  /// No description provided for @sidebarVersion.
  ///
  /// In zh, this message translates to:
  /// **'v{version}'**
  String sidebarVersion(String version);

  /// No description provided for @quickToggleTheme.
  ///
  /// In zh, this message translates to:
  /// **'切换主题'**
  String get quickToggleTheme;

  /// No description provided for @quickToggleGlass.
  ///
  /// In zh, this message translates to:
  /// **'切换玻璃强度'**
  String get quickToggleGlass;

  /// No description provided for @libraryTitle.
  ///
  /// In zh, this message translates to:
  /// **'书架'**
  String get libraryTitle;

  /// No description provided for @libraryEmptyTitle.
  ///
  /// In zh, this message translates to:
  /// **'书架还是空的'**
  String get libraryEmptyTitle;

  /// No description provided for @libraryEmptyAction.
  ///
  /// In zh, this message translates to:
  /// **'导入书稿'**
  String get libraryEmptyAction;

  /// No description provided for @importTitle.
  ///
  /// In zh, this message translates to:
  /// **'导入'**
  String get importTitle;

  /// No description provided for @importFormatsTitle.
  ///
  /// In zh, this message translates to:
  /// **'计划支持的格式'**
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

  /// No description provided for @settingsTitle.
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get settingsTitle;

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

  /// No description provided for @settingsAbout.
  ///
  /// In zh, this message translates to:
  /// **'关于'**
  String get settingsAbout;

  /// No description provided for @settingsVersion.
  ///
  /// In zh, this message translates to:
  /// **'版本'**
  String get settingsVersion;

  /// No description provided for @settingsLicense.
  ///
  /// In zh, this message translates to:
  /// **'许可证'**
  String get settingsLicense;

  /// No description provided for @settingsLicenseValue.
  ///
  /// In zh, this message translates to:
  /// **'MIT'**
  String get settingsLicenseValue;

  /// No description provided for @settingsDesignSystem.
  ///
  /// In zh, this message translates to:
  /// **'设计系统'**
  String get settingsDesignSystem;

  /// No description provided for @settingsOpen.
  ///
  /// In zh, this message translates to:
  /// **'打开'**
  String get settingsOpen;

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

  /// No description provided for @designLabelDisabled.
  ///
  /// In zh, this message translates to:
  /// **'禁用'**
  String get designLabelDisabled;

  /// No description provided for @designLabelInput.
  ///
  /// In zh, this message translates to:
  /// **'输入框'**
  String get designLabelInput;

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

  /// No description provided for @designLabelSegmented.
  ///
  /// In zh, this message translates to:
  /// **'分段选择'**
  String get designLabelSegmented;

  /// No description provided for @designPlaceholderInput.
  ///
  /// In zh, this message translates to:
  /// **'搜索或输入书名'**
  String get designPlaceholderInput;

  /// No description provided for @errorTitle.
  ///
  /// In zh, this message translates to:
  /// **'出了点问题'**
  String get errorTitle;

  /// No description provided for @errorBody.
  ///
  /// In zh, this message translates to:
  /// **'界面遇到未预期的错误，已记录日志。'**
  String get errorBody;

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

  /// No description provided for @bootstrapFailureRetry.
  ///
  /// In zh, this message translates to:
  /// **'重试'**
  String get bootstrapFailureRetry;

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

  /// No description provided for @settingsDesignSystemDesc.
  ///
  /// In zh, this message translates to:
  /// **'颜色、字体、间距、玻璃与组件状态'**
  String get settingsDesignSystemDesc;
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
