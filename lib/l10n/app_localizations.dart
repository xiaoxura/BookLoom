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

  /// No description provided for @aiSettingsTitle.
  ///
  /// In zh, this message translates to:
  /// **'AI 服务'**
  String get aiSettingsTitle;

  /// No description provided for @aiSettingsDescription.
  ///
  /// In zh, this message translates to:
  /// **'可选联网能力，默认关闭。由你选择服务，并主动发起每次任务。'**
  String get aiSettingsDescription;

  /// No description provided for @aiEnabled.
  ///
  /// In zh, this message translates to:
  /// **'启用 AI 辅助'**
  String get aiEnabled;

  /// No description provided for @aiOfflineNotice.
  ///
  /// In zh, this message translates to:
  /// **'关闭时不发送 AI 请求；导入、编辑、规则扫描与导出仍可离线使用。'**
  String get aiOfflineNotice;

  /// No description provided for @aiFormat.
  ///
  /// In zh, this message translates to:
  /// **'接口格式'**
  String get aiFormat;

  /// No description provided for @aiAddress.
  ///
  /// In zh, this message translates to:
  /// **'API 地址'**
  String get aiAddress;

  /// No description provided for @aiOpenAiAddressHint.
  ///
  /// In zh, this message translates to:
  /// **'https://api.example.com/v1'**
  String get aiOpenAiAddressHint;

  /// No description provided for @aiClaudeAddressHint.
  ///
  /// In zh, this message translates to:
  /// **'https://api.example.com（无需填写 /v1）'**
  String get aiClaudeAddressHint;

  /// No description provided for @aiApiKey.
  ///
  /// In zh, this message translates to:
  /// **'API 密钥'**
  String get aiApiKey;

  /// No description provided for @aiKeyNewHint.
  ///
  /// In zh, this message translates to:
  /// **'输入密钥，仅保存到系统安全存储'**
  String get aiKeyNewHint;

  /// No description provided for @aiKeyReuseHint.
  ///
  /// In zh, this message translates to:
  /// **'留空沿用已保存密钥；不会把密钥填回表单'**
  String get aiKeyReuseHint;

  /// No description provided for @aiKeyChangedAddressHint.
  ///
  /// In zh, this message translates to:
  /// **'地址或格式已改变，请重新输入密钥'**
  String get aiKeyChangedAddressHint;

  /// No description provided for @aiShowKey.
  ///
  /// In zh, this message translates to:
  /// **'显示密钥'**
  String get aiShowKey;

  /// No description provided for @aiHideKey.
  ///
  /// In zh, this message translates to:
  /// **'隐藏密钥'**
  String get aiHideKey;

  /// No description provided for @aiModel.
  ///
  /// In zh, this message translates to:
  /// **'模型标识'**
  String get aiModel;

  /// No description provided for @aiModelHint.
  ///
  /// In zh, this message translates to:
  /// **'手动填写服务支持的模型名称'**
  String get aiModelHint;

  /// No description provided for @aiNormalizedAddress.
  ///
  /// In zh, this message translates to:
  /// **'规范化基础地址'**
  String get aiNormalizedAddress;

  /// No description provided for @aiRequestAddress.
  ///
  /// In zh, this message translates to:
  /// **'最终请求地址'**
  String get aiRequestAddress;

  /// No description provided for @aiEndpointInvalid.
  ///
  /// In zh, this message translates to:
  /// **'请检查协议、地址、端口与接口格式。'**
  String get aiEndpointInvalid;

  /// No description provided for @aiRemoteHttpConsent.
  ///
  /// In zh, this message translates to:
  /// **'我了解远程 HTTP 会明文传输密钥和内容，仍使用此地址'**
  String get aiRemoteHttpConsent;

  /// No description provided for @aiTestDisclosure.
  ///
  /// In zh, this message translates to:
  /// **'连接测试只发送固定小样例，不读取或发送书稿，可能产生少量费用。书稿分析需在校对工具中另行确认。'**
  String get aiTestDisclosure;

  /// No description provided for @aiProofreadingTitle.
  ///
  /// In zh, this message translates to:
  /// **'AI 校对'**
  String get aiProofreadingTitle;

  /// No description provided for @editorAiCreateChapterRule.
  ///
  /// In zh, this message translates to:
  /// **'AI 创建章节识别规则'**
  String get editorAiCreateChapterRule;

  /// No description provided for @editorAiCreateAdvertisementRule.
  ///
  /// In zh, this message translates to:
  /// **'AI 创建广告清理规则'**
  String get editorAiCreateAdvertisementRule;

  /// No description provided for @aiJointRuleRequest.
  ///
  /// In zh, this message translates to:
  /// **'同时请求规则候选'**
  String get aiJointRuleRequest;

  /// No description provided for @aiJointRuleHelp.
  ///
  /// In zh, this message translates to:
  /// **'仅基于你提供的样例生成规则候选，不会自动保存或应用；请在规则工作台独立检查并试跑。'**
  String get aiJointRuleHelp;

  /// No description provided for @aiJointRuleLimits.
  ///
  /// In zh, this message translates to:
  /// **'每行一个样例：正例 1–12 条、反例 0–12 条；每条最多 2048 个 UTF-16 单元，总计最多 8192。所有正例必须完整位于同一个实际发送分块中。'**
  String get aiJointRuleLimits;

  /// No description provided for @aiJointRuleAuthorization.
  ///
  /// In zh, this message translates to:
  /// **'规则候选显式授权'**
  String get aiJointRuleAuthorization;

  /// No description provided for @aiJointRuleChunk.
  ///
  /// In zh, this message translates to:
  /// **'仅第 {index} 个分块允许返回规则（从 1 开始编号）。'**
  String aiJointRuleChunk(int index);

  /// No description provided for @aiJointRuleNotRequested.
  ///
  /// In zh, this message translates to:
  /// **'本次未请求规则候选，分析无权生成规则。'**
  String get aiJointRuleNotRequested;

  /// No description provided for @aiJointRuleCount.
  ///
  /// In zh, this message translates to:
  /// **'独立规则候选：{count}'**
  String aiJointRuleCount(int count);

  /// No description provided for @aiRuleTitle.
  ///
  /// In zh, this message translates to:
  /// **'AI 样例建规则'**
  String get aiRuleTitle;

  /// No description provided for @aiRuleSelected.
  ///
  /// In zh, this message translates to:
  /// **'所选原文'**
  String get aiRuleSelected;

  /// No description provided for @aiRuleIntent.
  ///
  /// In zh, this message translates to:
  /// **'规则意图'**
  String get aiRuleIntent;

  /// No description provided for @aiRuleNegative.
  ///
  /// In zh, this message translates to:
  /// **'不得命中的反例'**
  String get aiRuleNegative;

  /// No description provided for @aiRuleChapterTitle.
  ///
  /// In zh, this message translates to:
  /// **'所在章节标题'**
  String get aiRuleChapterTitle;

  /// No description provided for @aiRuleBefore.
  ///
  /// In zh, this message translates to:
  /// **'选区前文'**
  String get aiRuleBefore;

  /// No description provided for @aiRuleAfter.
  ///
  /// In zh, this message translates to:
  /// **'选区后文'**
  String get aiRuleAfter;

  /// No description provided for @aiRuleRelated.
  ///
  /// In zh, this message translates to:
  /// **'发送的相关规则摘要（最多 16 条）'**
  String get aiRuleRelated;

  /// No description provided for @aiRuleRunning.
  ///
  /// In zh, this message translates to:
  /// **'正在生成候选'**
  String get aiRuleRunning;

  /// No description provided for @aiRuleCompleted.
  ///
  /// In zh, this message translates to:
  /// **'候选生成完成'**
  String get aiRuleCompleted;

  /// No description provided for @aiRuleNoProposals.
  ///
  /// In zh, this message translates to:
  /// **'未生成规则候选。可调整意图或反例后重新准备。'**
  String get aiRuleNoProposals;

  /// No description provided for @aiRuleCheckAndTrial.
  ///
  /// In zh, this message translates to:
  /// **'检查并试跑'**
  String get aiRuleCheckAndTrial;

  /// No description provided for @ruleWorkbenchTitle.
  ///
  /// In zh, this message translates to:
  /// **'自定义规则'**
  String get ruleWorkbenchTitle;

  /// No description provided for @ruleWorkbenchNumberCaptureGroup.
  ///
  /// In zh, this message translates to:
  /// **'章号来自捕获组（可选）'**
  String get ruleWorkbenchNumberCaptureGroup;

  /// No description provided for @ruleWorkbenchNumberCaptureHelper.
  ///
  /// In zh, this message translates to:
  /// **'须同时设置标题捕获组；仅提取原文明示数字，不自动编号。留空不映射；0=整体匹配，1 起为捕获组。清空标题捕获组或切换为字面量/广告时会清除此章号设置。'**
  String get ruleWorkbenchNumberCaptureHelper;

  /// No description provided for @ruleWorkbenchNumberCaptureInvalid.
  ///
  /// In zh, this message translates to:
  /// **'请先设置标题捕获组，并输入可用编号内的非负整数。'**
  String get ruleWorkbenchNumberCaptureInvalid;

  /// No description provided for @ruleWorkbenchNumberToken.
  ///
  /// In zh, this message translates to:
  /// **'原文章号数字'**
  String get ruleWorkbenchNumberToken;

  /// No description provided for @ruleWorkbenchParsedNumber.
  ///
  /// In zh, this message translates to:
  /// **'解析后的章号'**
  String get ruleWorkbenchParsedNumber;

  /// No description provided for @ruleWorkbenchDefinition.
  ///
  /// In zh, this message translates to:
  /// **'完整规则定义'**
  String get ruleWorkbenchDefinition;

  /// No description provided for @ruleWorkbenchId.
  ///
  /// In zh, this message translates to:
  /// **'规则 ID'**
  String get ruleWorkbenchId;

  /// No description provided for @ruleWorkbenchBookId.
  ///
  /// In zh, this message translates to:
  /// **'书稿 ID'**
  String get ruleWorkbenchBookId;

  /// No description provided for @ruleWorkbenchSource.
  ///
  /// In zh, this message translates to:
  /// **'来源'**
  String get ruleWorkbenchSource;

  /// No description provided for @ruleWorkbenchInitialRejected.
  ///
  /// In zh, this message translates to:
  /// **'规则候选已过期或与现有规则冲突，请重新选择样例生成。'**
  String get ruleWorkbenchInitialRejected;

  /// No description provided for @ruleWorkbenchOffline.
  ///
  /// In zh, this message translates to:
  /// **'本地规则全书试跑；不会调用 AI。选定规则和命中后才会修改书稿。'**
  String get ruleWorkbenchOffline;

  /// No description provided for @ruleWorkbenchImportRules.
  ///
  /// In zh, this message translates to:
  /// **'导入内置规则（只读）'**
  String get ruleWorkbenchImportRules;

  /// No description provided for @ruleWorkbenchImportPreset.
  ///
  /// In zh, this message translates to:
  /// **'预设：{name}'**
  String ruleWorkbenchImportPreset(String name);

  /// No description provided for @ruleWorkbenchImportCustom.
  ///
  /// In zh, this message translates to:
  /// **'自定义'**
  String get ruleWorkbenchImportCustom;

  /// No description provided for @ruleWorkbenchImportAutoNote.
  ///
  /// In zh, this message translates to:
  /// **'自动识别由导入器内置启发式与广告规则完成；工作台不复制这部分逻辑，也不会在试跑中重放。'**
  String get ruleWorkbenchImportAutoNote;

  /// No description provided for @ruleWorkbenchImportCustomNote.
  ///
  /// In zh, this message translates to:
  /// **'导入时还附加了自定义规则；它们同样只读展示，不参与本次试跑。'**
  String get ruleWorkbenchImportCustomNote;

  /// No description provided for @ruleWorkbenchImportInvalid.
  ///
  /// In zh, this message translates to:
  /// **'无法解析当前导入规则（预设或自定义规则无效），请检查导入设置。'**
  String get ruleWorkbenchImportInvalid;

  /// No description provided for @ruleWorkbenchImportReadOnly.
  ///
  /// In zh, this message translates to:
  /// **'导入规则只在导入或重新解析时执行，不会在本次试跑中运行；工作台只运行上面显式勾选的已保存规则。如需在书中复用，请新建规则。'**
  String get ruleWorkbenchImportReadOnly;

  /// No description provided for @ruleWorkbenchImportEmpty.
  ///
  /// In zh, this message translates to:
  /// **'该预设没有可展示的章节、卷或丢弃规则。'**
  String get ruleWorkbenchImportEmpty;

  /// No description provided for @ruleWorkbenchImportEntryChapter.
  ///
  /// In zh, this message translates to:
  /// **'章节标题规则（整行匹配）'**
  String get ruleWorkbenchImportEntryChapter;

  /// No description provided for @ruleWorkbenchImportEntryVolume.
  ///
  /// In zh, this message translates to:
  /// **'卷标题规则（整行匹配）'**
  String get ruleWorkbenchImportEntryVolume;

  /// No description provided for @ruleWorkbenchImportEntryDrop.
  ///
  /// In zh, this message translates to:
  /// **'整行丢弃规则'**
  String get ruleWorkbenchImportEntryDrop;

  /// No description provided for @ruleWorkbenchImportEntryInlineJunk.
  ///
  /// In zh, this message translates to:
  /// **'行内推广清理规则'**
  String get ruleWorkbenchImportEntryInlineJunk;

  /// No description provided for @ruleWorkbenchRules.
  ///
  /// In zh, this message translates to:
  /// **'本次规则集'**
  String get ruleWorkbenchRules;

  /// No description provided for @ruleWorkbenchEmpty.
  ///
  /// In zh, this message translates to:
  /// **'还没有规则。可以先创建一条本书规则。'**
  String get ruleWorkbenchEmpty;

  /// No description provided for @ruleWorkbenchBookScope.
  ///
  /// In zh, this message translates to:
  /// **'本书'**
  String get ruleWorkbenchBookScope;

  /// No description provided for @ruleWorkbenchGlobalScope.
  ///
  /// In zh, this message translates to:
  /// **'跨书'**
  String get ruleWorkbenchGlobalScope;

  /// No description provided for @ruleWorkbenchEnabled.
  ///
  /// In zh, this message translates to:
  /// **'启用'**
  String get ruleWorkbenchEnabled;

  /// No description provided for @ruleWorkbenchDisabled.
  ///
  /// In zh, this message translates to:
  /// **'停用'**
  String get ruleWorkbenchDisabled;

  /// No description provided for @ruleWorkbenchUnsaved.
  ///
  /// In zh, this message translates to:
  /// **'未保存'**
  String get ruleWorkbenchUnsaved;

  /// No description provided for @ruleWorkbenchCurrent.
  ///
  /// In zh, this message translates to:
  /// **'当前规则'**
  String get ruleWorkbenchCurrent;

  /// No description provided for @ruleWorkbenchBuiltIn.
  ///
  /// In zh, this message translates to:
  /// **'内置'**
  String get ruleWorkbenchBuiltIn;

  /// No description provided for @ruleWorkbenchUser.
  ///
  /// In zh, this message translates to:
  /// **'用户'**
  String get ruleWorkbenchUser;

  /// No description provided for @ruleWorkbenchAiSource.
  ///
  /// In zh, this message translates to:
  /// **'AI 来源'**
  String get ruleWorkbenchAiSource;

  /// No description provided for @ruleWorkbenchActions.
  ///
  /// In zh, this message translates to:
  /// **'规则操作'**
  String get ruleWorkbenchActions;

  /// No description provided for @ruleWorkbenchEdit.
  ///
  /// In zh, this message translates to:
  /// **'编辑'**
  String get ruleWorkbenchEdit;

  /// No description provided for @ruleWorkbenchEnable.
  ///
  /// In zh, this message translates to:
  /// **'启用规则'**
  String get ruleWorkbenchEnable;

  /// No description provided for @ruleWorkbenchDisable.
  ///
  /// In zh, this message translates to:
  /// **'停用规则'**
  String get ruleWorkbenchDisable;

  /// No description provided for @ruleWorkbenchDelete.
  ///
  /// In zh, this message translates to:
  /// **'删除规则'**
  String get ruleWorkbenchDelete;

  /// No description provided for @ruleWorkbenchDeleteTitle.
  ///
  /// In zh, this message translates to:
  /// **'确认删除规则？'**
  String get ruleWorkbenchDeleteTitle;

  /// No description provided for @ruleWorkbenchNew.
  ///
  /// In zh, this message translates to:
  /// **'新建规则'**
  String get ruleWorkbenchNew;

  /// No description provided for @ruleWorkbenchScan.
  ///
  /// In zh, this message translates to:
  /// **'试跑全书'**
  String get ruleWorkbenchScan;

  /// No description provided for @ruleWorkbenchIdentify.
  ///
  /// In zh, this message translates to:
  /// **'识别什么'**
  String get ruleWorkbenchIdentify;

  /// No description provided for @ruleWorkbenchExclude.
  ///
  /// In zh, this message translates to:
  /// **'排除什么'**
  String get ruleWorkbenchExclude;

  /// No description provided for @ruleWorkbenchExcludePattern.
  ///
  /// In zh, this message translates to:
  /// **'命中排除文本（可选）'**
  String get ruleWorkbenchExcludePattern;

  /// No description provided for @ruleWorkbenchExcludePatternHelper.
  ///
  /// In zh, this message translates to:
  /// **'匹配所在行包含该文本时跳过该命中；区分大小写沿用上方设置。'**
  String get ruleWorkbenchExcludePatternHelper;

  /// No description provided for @ruleWorkbenchExcludePatternInvalid.
  ///
  /// In zh, this message translates to:
  /// **'排除文本不能跨行，且不超过 256 个 UTF-16 字符。'**
  String get ruleWorkbenchExcludePatternInvalid;

  /// No description provided for @ruleWorkbenchWholeLine.
  ///
  /// In zh, this message translates to:
  /// **'仅整行匹配'**
  String get ruleWorkbenchWholeLine;

  /// No description provided for @ruleWorkbenchNoGlobalRules.
  ///
  /// In zh, this message translates to:
  /// **'没有可导出的规则。'**
  String get ruleWorkbenchNoGlobalRules;

  /// No description provided for @ruleWorkbenchRulesNoSharedInFile.
  ///
  /// In zh, this message translates to:
  /// **'文件中没有可用规则。'**
  String get ruleWorkbenchRulesNoSharedInFile;

  /// No description provided for @ruleWorkbenchExportSharedRules.
  ///
  /// In zh, this message translates to:
  /// **'导出规则文件'**
  String get ruleWorkbenchExportSharedRules;

  /// No description provided for @ruleWorkbenchImportSharedRules.
  ///
  /// In zh, this message translates to:
  /// **'导入规则文件'**
  String get ruleWorkbenchImportSharedRules;

  /// No description provided for @ruleWorkbenchRulesExported.
  ///
  /// In zh, this message translates to:
  /// **'已导出 {count} 条规则。'**
  String ruleWorkbenchRulesExported(int count);

  /// No description provided for @ruleWorkbenchRulesImportTitle.
  ///
  /// In zh, this message translates to:
  /// **'导入规则文件'**
  String get ruleWorkbenchRulesImportTitle;

  /// No description provided for @ruleWorkbenchRulesImportBody.
  ///
  /// In zh, this message translates to:
  /// **'文件含 {global} 条跨书规则、{book} 条本书规则（复制到当前书）；{existing} 条同 ID 已存在将跳过。只补充缺失定义，不覆盖、不自动启用或运行。'**
  String ruleWorkbenchRulesImportBody(int global, int book, int existing);

  /// No description provided for @ruleWorkbenchRulesImported.
  ///
  /// In zh, this message translates to:
  /// **'已导入：新增 {added} 条，跳过已有 {skipped} 条。'**
  String ruleWorkbenchRulesImported(int added, int skipped);

  /// No description provided for @ruleWorkbenchRulesImportInvalid.
  ///
  /// In zh, this message translates to:
  /// **'规则文件无效或版本不兼容。'**
  String get ruleWorkbenchRulesImportInvalid;

  /// No description provided for @ruleWorkbenchWholeLineHelper.
  ///
  /// In zh, this message translates to:
  /// **'忽略首尾空白后，命中必须覆盖整行；仅适用于标题行和正文行。'**
  String get ruleWorkbenchWholeLineHelper;

  /// No description provided for @ruleWorkbenchEffect.
  ///
  /// In zh, this message translates to:
  /// **'会改什么'**
  String get ruleWorkbenchEffect;

  /// No description provided for @ruleWorkbenchName.
  ///
  /// In zh, this message translates to:
  /// **'规则名称'**
  String get ruleWorkbenchName;

  /// No description provided for @ruleWorkbenchKind.
  ///
  /// In zh, this message translates to:
  /// **'规则类型'**
  String get ruleWorkbenchKind;

  /// No description provided for @ruleWorkbenchChapter.
  ///
  /// In zh, this message translates to:
  /// **'章节识别'**
  String get ruleWorkbenchChapter;

  /// No description provided for @ruleWorkbenchHeadingLevel.
  ///
  /// In zh, this message translates to:
  /// **'识别层级'**
  String get ruleWorkbenchHeadingLevel;

  /// No description provided for @ruleWorkbenchVolumeLevel.
  ///
  /// In zh, this message translates to:
  /// **'卷'**
  String get ruleWorkbenchVolumeLevel;

  /// No description provided for @ruleWorkbenchChapterLevel.
  ///
  /// In zh, this message translates to:
  /// **'章节'**
  String get ruleWorkbenchChapterLevel;

  /// No description provided for @ruleWorkbenchVolumeCandidate.
  ///
  /// In zh, this message translates to:
  /// **'卷识别'**
  String get ruleWorkbenchVolumeCandidate;

  /// No description provided for @ruleWorkbenchVolumeEffect.
  ///
  /// In zh, this message translates to:
  /// **'将完整标题行及换行从正文移除并建立顶层卷。边界后内容保留为不另拟目录标题的卷前内容，后续连续同归属章节移入新卷；无内容时不创建空章节。'**
  String get ruleWorkbenchVolumeEffect;

  /// No description provided for @ruleWorkbenchNewVolumeTitle.
  ///
  /// In zh, this message translates to:
  /// **'新卷标题'**
  String get ruleWorkbenchNewVolumeTitle;

  /// No description provided for @ruleWorkbenchVolumeFrontMatter.
  ///
  /// In zh, this message translates to:
  /// **'卷前内容（不另拟章节标题）'**
  String get ruleWorkbenchVolumeFrontMatter;

  /// No description provided for @ruleWorkbenchVolumePreview.
  ///
  /// In zh, this message translates to:
  /// **'这是单项卷边界预览。新卷是顶层目录项，本身不承载正文。原章边界前内容保留；边界后的正文、图片、脚注与分隔符按原序归入新卷的卷前内容，目录中不另拟标题，无内容时不创建空章节。后续连续且与原章同归属的章节移入新卷，遇到卷或不同归属时停止。批量应用时按各卷边界分配，一次撤销。'**
  String get ruleWorkbenchVolumePreview;

  /// No description provided for @ruleWorkbenchVolumeFollowingBlockCount.
  ///
  /// In zh, this message translates to:
  /// **'归入卷前内容的后续块数'**
  String get ruleWorkbenchVolumeFollowingBlockCount;

  /// No description provided for @ruleWorkbenchVolumeFollowingBlocks.
  ///
  /// In zh, this message translates to:
  /// **'展开卷前内容的后续全部块'**
  String get ruleWorkbenchVolumeFollowingBlocks;

  /// No description provided for @ruleWorkbenchVolumeFollowingChapterCount.
  ///
  /// In zh, this message translates to:
  /// **'单项应用将移入新卷的后续章节数'**
  String get ruleWorkbenchVolumeFollowingChapterCount;

  /// No description provided for @ruleWorkbenchVolumeFollowingChapters.
  ///
  /// In zh, this message translates to:
  /// **'展开将移入新卷的后续章节列表'**
  String get ruleWorkbenchVolumeFollowingChapters;

  /// No description provided for @ruleWorkbenchMoreChapters.
  ///
  /// In zh, this message translates to:
  /// **'加载更多章节'**
  String get ruleWorkbenchMoreChapters;

  /// No description provided for @ruleWorkbenchAdvertisement.
  ///
  /// In zh, this message translates to:
  /// **'广告识别'**
  String get ruleWorkbenchAdvertisement;

  /// No description provided for @ruleWorkbenchTarget.
  ///
  /// In zh, this message translates to:
  /// **'匹配目标'**
  String get ruleWorkbenchTarget;

  /// No description provided for @ruleWorkbenchHeadingLine.
  ///
  /// In zh, this message translates to:
  /// **'匹配目标：标题行'**
  String get ruleWorkbenchHeadingLine;

  /// No description provided for @ruleWorkbenchBodyLine.
  ///
  /// In zh, this message translates to:
  /// **'正文行'**
  String get ruleWorkbenchBodyLine;

  /// No description provided for @ruleWorkbenchParagraph.
  ///
  /// In zh, this message translates to:
  /// **'段落'**
  String get ruleWorkbenchParagraph;

  /// No description provided for @ruleWorkbenchMode.
  ///
  /// In zh, this message translates to:
  /// **'匹配方式'**
  String get ruleWorkbenchMode;

  /// No description provided for @ruleWorkbenchLiteral.
  ///
  /// In zh, this message translates to:
  /// **'普通文本'**
  String get ruleWorkbenchLiteral;

  /// No description provided for @ruleWorkbenchSafeRegex.
  ///
  /// In zh, this message translates to:
  /// **'受限正则（高级）'**
  String get ruleWorkbenchSafeRegex;

  /// No description provided for @ruleWorkbenchPattern.
  ///
  /// In zh, this message translates to:
  /// **'识别文本或表达式'**
  String get ruleWorkbenchPattern;

  /// No description provided for @ruleWorkbenchAdvanced.
  ///
  /// In zh, this message translates to:
  /// **'高级选项'**
  String get ruleWorkbenchAdvanced;

  /// No description provided for @ruleWorkbenchTitleCaptureGroup.
  ///
  /// In zh, this message translates to:
  /// **'目录标题来自捕获组'**
  String get ruleWorkbenchTitleCaptureGroup;

  /// No description provided for @ruleWorkbenchTitleCaptureHelper.
  ///
  /// In zh, this message translates to:
  /// **'留空=完整标题行；0=整体匹配；1 起为捕获组。'**
  String get ruleWorkbenchTitleCaptureHelper;

  /// No description provided for @ruleWorkbenchAvailableGroups.
  ///
  /// In zh, this message translates to:
  /// **'可用编号'**
  String get ruleWorkbenchAvailableGroups;

  /// No description provided for @ruleWorkbenchTitleCaptureInvalid.
  ///
  /// In zh, this message translates to:
  /// **'请输入可用编号内的非负整数。'**
  String get ruleWorkbenchTitleCaptureInvalid;

  /// No description provided for @ruleWorkbenchFullHeadingLine.
  ///
  /// In zh, this message translates to:
  /// **'完整标题行'**
  String get ruleWorkbenchFullHeadingLine;

  /// No description provided for @ruleWorkbenchCaseSensitive.
  ///
  /// In zh, this message translates to:
  /// **'区分大小写'**
  String get ruleWorkbenchCaseSensitive;

  /// No description provided for @ruleWorkbenchPositive.
  ///
  /// In zh, this message translates to:
  /// **'必命中的正例（至少一行）'**
  String get ruleWorkbenchPositive;

  /// No description provided for @ruleWorkbenchNegative.
  ///
  /// In zh, this message translates to:
  /// **'不得命中的反例（可多行）'**
  String get ruleWorkbenchNegative;

  /// No description provided for @ruleWorkbenchOnePerLine.
  ///
  /// In zh, this message translates to:
  /// **'每行一个样例；单行内不换行'**
  String get ruleWorkbenchOnePerLine;

  /// No description provided for @ruleWorkbenchAction.
  ///
  /// In zh, this message translates to:
  /// **'动作'**
  String get ruleWorkbenchAction;

  /// No description provided for @ruleWorkbenchCandidate.
  ///
  /// In zh, this message translates to:
  /// **'标记广告候选（不删除）'**
  String get ruleWorkbenchCandidate;

  /// No description provided for @ruleWorkbenchExactDeletion.
  ///
  /// In zh, this message translates to:
  /// **'精确删除命中文本'**
  String get ruleWorkbenchExactDeletion;

  /// No description provided for @ruleWorkbenchChapterEffect.
  ///
  /// In zh, this message translates to:
  /// **'将完整标题行及换行从正文移除；新目录标题默认取整行，可映射捕获组。'**
  String get ruleWorkbenchChapterEffect;

  /// No description provided for @ruleWorkbenchScope.
  ///
  /// In zh, this message translates to:
  /// **'作用域'**
  String get ruleWorkbenchScope;

  /// No description provided for @ruleWorkbenchPriority.
  ///
  /// In zh, this message translates to:
  /// **'优先级（-1000 至 1000）'**
  String get ruleWorkbenchPriority;

  /// No description provided for @ruleWorkbenchPriorityInvalid.
  ///
  /// In zh, this message translates to:
  /// **'优先级必须为整数。'**
  String get ruleWorkbenchPriorityInvalid;

  /// No description provided for @ruleWorkbenchOpenBook.
  ///
  /// In zh, this message translates to:
  /// **'请先打开书稿。'**
  String get ruleWorkbenchOpenBook;

  /// No description provided for @ruleWorkbenchUseDefinition.
  ///
  /// In zh, this message translates to:
  /// **'加入规则集'**
  String get ruleWorkbenchUseDefinition;

  /// No description provided for @ruleWorkbenchGlobalConfirmTitle.
  ///
  /// In zh, this message translates to:
  /// **'改为跨书规则？'**
  String get ruleWorkbenchGlobalConfirmTitle;

  /// No description provided for @ruleWorkbenchGlobalConfirmBody.
  ///
  /// In zh, this message translates to:
  /// **'规则将出现在其他书稿的规则列表中，但不会自动参与试跑或修改正文。'**
  String get ruleWorkbenchGlobalConfirmBody;

  /// No description provided for @ruleWorkbenchConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确认'**
  String get ruleWorkbenchConfirm;

  /// No description provided for @ruleWorkbenchLoading.
  ///
  /// In zh, this message translates to:
  /// **'正在加载规则'**
  String get ruleWorkbenchLoading;

  /// No description provided for @ruleWorkbenchScanning.
  ///
  /// In zh, this message translates to:
  /// **'正在试跑全书'**
  String get ruleWorkbenchScanning;

  /// No description provided for @ruleWorkbenchReady.
  ///
  /// In zh, this message translates to:
  /// **'试跑完成'**
  String get ruleWorkbenchReady;

  /// No description provided for @ruleWorkbenchSaving.
  ///
  /// In zh, this message translates to:
  /// **'正在保存规则'**
  String get ruleWorkbenchSaving;

  /// No description provided for @ruleWorkbenchSaved.
  ///
  /// In zh, this message translates to:
  /// **'规则已保存；试跑结果已失效，请重新试跑后再应用。'**
  String get ruleWorkbenchSaved;

  /// No description provided for @ruleWorkbenchDeleted.
  ///
  /// In zh, this message translates to:
  /// **'规则已删除。'**
  String get ruleWorkbenchDeleted;

  /// No description provided for @ruleWorkbenchResults.
  ///
  /// In zh, this message translates to:
  /// **'全书试跑结果'**
  String get ruleWorkbenchResults;

  /// No description provided for @ruleWorkbenchCoverage.
  ///
  /// In zh, this message translates to:
  /// **'覆盖'**
  String get ruleWorkbenchCoverage;

  /// No description provided for @ruleWorkbenchChapters.
  ///
  /// In zh, this message translates to:
  /// **'卷章节点'**
  String get ruleWorkbenchChapters;

  /// No description provided for @ruleWorkbenchBlocks.
  ///
  /// In zh, this message translates to:
  /// **'文本块'**
  String get ruleWorkbenchBlocks;

  /// No description provided for @ruleWorkbenchLines.
  ///
  /// In zh, this message translates to:
  /// **'正文行'**
  String get ruleWorkbenchLines;

  /// No description provided for @ruleWorkbenchTotalMatches.
  ///
  /// In zh, this message translates to:
  /// **'总命中'**
  String get ruleWorkbenchTotalMatches;

  /// No description provided for @ruleWorkbenchDistinctMatches.
  ///
  /// In zh, this message translates to:
  /// **'去重命中'**
  String get ruleWorkbenchDistinctMatches;

  /// No description provided for @ruleWorkbenchConflicts.
  ///
  /// In zh, this message translates to:
  /// **'冲突总数'**
  String get ruleWorkbenchConflicts;

  /// No description provided for @ruleWorkbenchConflictSamples.
  ///
  /// In zh, this message translates to:
  /// **'冲突样本'**
  String get ruleWorkbenchConflictSamples;

  /// No description provided for @ruleWorkbenchTruncated.
  ///
  /// In zh, this message translates to:
  /// **'未展示'**
  String get ruleWorkbenchTruncated;

  /// No description provided for @ruleWorkbenchShown.
  ///
  /// In zh, this message translates to:
  /// **'已展示命中'**
  String get ruleWorkbenchShown;

  /// No description provided for @ruleWorkbenchExecuted.
  ///
  /// In zh, this message translates to:
  /// **'已执行，命中'**
  String get ruleWorkbenchExecuted;

  /// No description provided for @ruleWorkbenchNotExecuted.
  ///
  /// In zh, this message translates to:
  /// **'未执行（已停用）'**
  String get ruleWorkbenchNotExecuted;

  /// No description provided for @ruleWorkbenchConflictDetails.
  ///
  /// In zh, this message translates to:
  /// **'查看冲突样本'**
  String get ruleWorkbenchConflictDetails;

  /// No description provided for @ruleWorkbenchChapterConflict.
  ///
  /// In zh, this message translates to:
  /// **'同一行多个拆章边界'**
  String get ruleWorkbenchChapterConflict;

  /// No description provided for @ruleWorkbenchDeleteChapterConflict.
  ///
  /// In zh, this message translates to:
  /// **'删除与拆章冲突'**
  String get ruleWorkbenchDeleteChapterConflict;

  /// No description provided for @ruleWorkbenchDeletionConflict.
  ///
  /// In zh, this message translates to:
  /// **'删除范围重叠'**
  String get ruleWorkbenchDeletionConflict;

  /// No description provided for @ruleWorkbenchMaxApply.
  ///
  /// In zh, this message translates to:
  /// **'每批最多应用 100 项。'**
  String get ruleWorkbenchMaxApply;

  /// No description provided for @ruleWorkbenchSaveOnly.
  ///
  /// In zh, this message translates to:
  /// **'仅保存当前规则'**
  String get ruleWorkbenchSaveOnly;

  /// No description provided for @ruleWorkbenchApplySelected.
  ///
  /// In zh, this message translates to:
  /// **'应用所选变更（一次撤销）'**
  String get ruleWorkbenchApplySelected;

  /// No description provided for @ruleWorkbenchSaveApply.
  ///
  /// In zh, this message translates to:
  /// **'保存并应用所选本规则命中'**
  String get ruleWorkbenchSaveApply;

  /// No description provided for @ruleWorkbenchCandidateNotice.
  ///
  /// In zh, this message translates to:
  /// **'广告候选仅供核对，不能勾选删除。'**
  String get ruleWorkbenchCandidateNotice;

  /// No description provided for @aiAdvertisementAnalyze.
  ///
  /// In zh, this message translates to:
  /// **'AI 判断广告'**
  String get aiAdvertisementAnalyze;

  /// No description provided for @aiAdvertisementSource.
  ///
  /// In zh, this message translates to:
  /// **'来自规则候选：{name}'**
  String aiAdvertisementSource(String name);

  /// No description provided for @aiAdvertisementSelectedText.
  ///
  /// In zh, this message translates to:
  /// **'精确选区（仅此范围允许修改）'**
  String get aiAdvertisementSelectedText;

  /// No description provided for @aiAdvertisementReadOnlyContext.
  ///
  /// In zh, this message translates to:
  /// **'实际发送的只读相邻正文'**
  String get aiAdvertisementReadOnlyContext;

  /// No description provided for @aiAdvertisementSelectionScope.
  ///
  /// In zh, this message translates to:
  /// **'选区最多 8192 个 UTF-16 单元；仅分析所选文字及只读相邻上下文。更改章节范围将取消此选区请求。'**
  String get aiAdvertisementSelectionScope;

  /// No description provided for @aiAdvertisementSelectionLimit.
  ///
  /// In zh, this message translates to:
  /// **'选区超过 8192 个 UTF-16 单元，请缩小后再分析。'**
  String get aiAdvertisementSelectionLimit;

  /// No description provided for @aiAdvertisementSelectionExpired.
  ///
  /// In zh, this message translates to:
  /// **'此广告选区已失效，请重新选择内容后再分析。'**
  String get aiAdvertisementSelectionExpired;

  /// No description provided for @ruleWorkbenchMore.
  ///
  /// In zh, this message translates to:
  /// **'加载更多命中'**
  String get ruleWorkbenchMore;

  /// No description provided for @ruleWorkbenchReload.
  ///
  /// In zh, this message translates to:
  /// **'重新载入已保存规则'**
  String get ruleWorkbenchReload;

  /// No description provided for @ruleWorkbenchReloadTitle.
  ///
  /// In zh, this message translates to:
  /// **'重新载入规则？'**
  String get ruleWorkbenchReloadTitle;

  /// No description provided for @ruleWorkbenchReloadWarning.
  ///
  /// In zh, this message translates to:
  /// **'当前未保存的规则定义、表单内容与试跑结果将被丢弃。'**
  String get ruleWorkbenchReloadWarning;

  /// No description provided for @ruleWorkbenchLine.
  ///
  /// In zh, this message translates to:
  /// **'行'**
  String get ruleWorkbenchLine;

  /// No description provided for @ruleWorkbenchRule.
  ///
  /// In zh, this message translates to:
  /// **'命中规则'**
  String get ruleWorkbenchRule;

  /// No description provided for @ruleWorkbenchOffset.
  ///
  /// In zh, this message translates to:
  /// **'范围'**
  String get ruleWorkbenchOffset;

  /// No description provided for @ruleWorkbenchSplitPrefix.
  ///
  /// In zh, this message translates to:
  /// **'原章保留的边界块内容'**
  String get ruleWorkbenchSplitPrefix;

  /// No description provided for @ruleWorkbenchRemoveHeadingLine.
  ///
  /// In zh, this message translates to:
  /// **'将移除的完整标题行'**
  String get ruleWorkbenchRemoveHeadingLine;

  /// No description provided for @ruleWorkbenchSplitTitle.
  ///
  /// In zh, this message translates to:
  /// **'新目录标题'**
  String get ruleWorkbenchSplitTitle;

  /// No description provided for @ruleWorkbenchUnsupportedCrLine.
  ///
  /// In zh, this message translates to:
  /// **'孤立 CR 标题行暂不支持拆章，请调整换行后重新试跑。'**
  String get ruleWorkbenchUnsupportedCrLine;

  /// No description provided for @ruleWorkbenchSplitSuffix.
  ///
  /// In zh, this message translates to:
  /// **'新章边界块剩余正文'**
  String get ruleWorkbenchSplitSuffix;

  /// No description provided for @ruleWorkbenchFollowingCount.
  ///
  /// In zh, this message translates to:
  /// **'按原序移入新章的后续块数'**
  String get ruleWorkbenchFollowingCount;

  /// No description provided for @ruleWorkbenchFollowingBlocks.
  ///
  /// In zh, this message translates to:
  /// **'展开新章后续全部内容'**
  String get ruleWorkbenchFollowingBlocks;

  /// No description provided for @ruleWorkbenchTextBlock.
  ///
  /// In zh, this message translates to:
  /// **'正文块'**
  String get ruleWorkbenchTextBlock;

  /// No description provided for @ruleWorkbenchImageBlock.
  ///
  /// In zh, this message translates to:
  /// **'图片块'**
  String get ruleWorkbenchImageBlock;

  /// No description provided for @ruleWorkbenchFootnoteBlock.
  ///
  /// In zh, this message translates to:
  /// **'脚注块'**
  String get ruleWorkbenchFootnoteBlock;

  /// No description provided for @ruleWorkbenchDividerBlock.
  ///
  /// In zh, this message translates to:
  /// **'分隔块'**
  String get ruleWorkbenchDividerBlock;

  /// No description provided for @ruleWorkbenchAssetId.
  ///
  /// In zh, this message translates to:
  /// **'资源标识'**
  String get ruleWorkbenchAssetId;

  /// No description provided for @ruleWorkbenchDeleteExact.
  ///
  /// In zh, this message translates to:
  /// **'精确移除'**
  String get ruleWorkbenchDeleteExact;

  /// No description provided for @ruleWorkbenchAfter.
  ///
  /// In zh, this message translates to:
  /// **'改后完整文本块'**
  String get ruleWorkbenchAfter;

  /// No description provided for @aiProofreadingIntro.
  ///
  /// In zh, this message translates to:
  /// **'选择分析目的与章节；准备范围不会发送书稿。'**
  String get aiProofreadingIntro;

  /// No description provided for @aiAuditGapSource.
  ///
  /// In zh, this message translates to:
  /// **'来自书稿体检：章节编号断档'**
  String get aiAuditGapSource;

  /// No description provided for @aiAuditGapRange.
  ///
  /// In zh, this message translates to:
  /// **'缺失章号：{first}–{last}'**
  String aiAuditGapRange(int first, int last);

  /// No description provided for @aiAuditGapBefore.
  ///
  /// In zh, this message translates to:
  /// **'前一章：{title}'**
  String aiAuditGapBefore(String title);

  /// No description provided for @aiAuditGapAfter.
  ///
  /// In zh, this message translates to:
  /// **'后一章：{title}'**
  String aiAuditGapAfter(String title);

  /// No description provided for @aiAuditGapNoBefore.
  ///
  /// In zh, this message translates to:
  /// **'本卷没有前一章，仅分析首个编号章节。'**
  String get aiAuditGapNoBefore;

  /// No description provided for @aiAuditGapNoAutoSend.
  ///
  /// In zh, this message translates to:
  /// **'进入分析不会自动上传；请先核对请求范围，再确认发送。'**
  String get aiAuditGapNoAutoSend;

  /// No description provided for @aiAuditGapExpired.
  ///
  /// In zh, this message translates to:
  /// **'此体检断档已失效，请重新体检后再分析。'**
  String get aiAuditGapExpired;

  /// No description provided for @aiProofreadingAdvertisement.
  ///
  /// In zh, this message translates to:
  /// **'广告判断'**
  String get aiProofreadingAdvertisement;

  /// No description provided for @aiProofreadingMissingChapter.
  ///
  /// In zh, this message translates to:
  /// **'缺章诊断'**
  String get aiProofreadingMissingChapter;

  /// No description provided for @aiProofreadingChapters.
  ///
  /// In zh, this message translates to:
  /// **'分析章节'**
  String get aiProofreadingChapters;

  /// No description provided for @aiProofreadingScope.
  ///
  /// In zh, this message translates to:
  /// **'可选当前章或多个章节；选中的正文完整分块分析。'**
  String get aiProofreadingScope;

  /// No description provided for @aiProofreadingMissingScope.
  ///
  /// In zh, this message translates to:
  /// **'默认取相邻两章；可调整章对。选中章节完整覆盖，不固定截取首尾。'**
  String get aiProofreadingMissingScope;

  /// No description provided for @aiProofreadingCurrentChapter.
  ///
  /// In zh, this message translates to:
  /// **'当前章'**
  String get aiProofreadingCurrentChapter;

  /// No description provided for @aiProofreadingSelectedChapters.
  ///
  /// In zh, this message translates to:
  /// **'已选章节'**
  String get aiProofreadingSelectedChapters;

  /// No description provided for @aiProofreadingPrepare.
  ///
  /// In zh, this message translates to:
  /// **'准备并预览发送内容'**
  String get aiProofreadingPrepare;

  /// No description provided for @aiProofreadingPhase.
  ///
  /// In zh, this message translates to:
  /// **'任务状态'**
  String get aiProofreadingPhase;

  /// No description provided for @aiProofreadingIdle.
  ///
  /// In zh, this message translates to:
  /// **'待开始'**
  String get aiProofreadingIdle;

  /// No description provided for @aiProofreadingPreparing.
  ///
  /// In zh, this message translates to:
  /// **'准备中'**
  String get aiProofreadingPreparing;

  /// No description provided for @aiProofreadingAwaitingConsent.
  ///
  /// In zh, this message translates to:
  /// **'待确认发送'**
  String get aiProofreadingAwaitingConsent;

  /// No description provided for @aiProofreadingRunning.
  ///
  /// In zh, this message translates to:
  /// **'分析中'**
  String get aiProofreadingRunning;

  /// No description provided for @aiProofreadingCompleted.
  ///
  /// In zh, this message translates to:
  /// **'分析完成'**
  String get aiProofreadingCompleted;

  /// No description provided for @aiProofreadingApplying.
  ///
  /// In zh, this message translates to:
  /// **'应用中'**
  String get aiProofreadingApplying;

  /// No description provided for @aiProofreadingApplied.
  ///
  /// In zh, this message translates to:
  /// **'已应用'**
  String get aiProofreadingApplied;

  /// No description provided for @aiProofreadingCancelled.
  ///
  /// In zh, this message translates to:
  /// **'已取消'**
  String get aiProofreadingCancelled;

  /// No description provided for @aiProofreadingStale.
  ///
  /// In zh, this message translates to:
  /// **'书稿已变化，结果失效'**
  String get aiProofreadingStale;

  /// No description provided for @aiProofreadingFailed.
  ///
  /// In zh, this message translates to:
  /// **'失败'**
  String get aiProofreadingFailed;

  /// No description provided for @aiProofreadingCompletedChunks.
  ///
  /// In zh, this message translates to:
  /// **'已完成分块'**
  String get aiProofreadingCompletedChunks;

  /// No description provided for @aiProofreadingReview.
  ///
  /// In zh, this message translates to:
  /// **'发送前确认'**
  String get aiProofreadingReview;

  /// No description provided for @aiProofreadingCharacters.
  ///
  /// In zh, this message translates to:
  /// **'原文字符数'**
  String get aiProofreadingCharacters;

  /// No description provided for @aiProofreadingBlocks.
  ///
  /// In zh, this message translates to:
  /// **'段落数'**
  String get aiProofreadingBlocks;

  /// No description provided for @aiProofreadingChunks.
  ///
  /// In zh, this message translates to:
  /// **'请求分块数'**
  String get aiProofreadingChunks;

  /// No description provided for @aiProofreadingSystemPrompt.
  ///
  /// In zh, this message translates to:
  /// **'完整系统提示词'**
  String get aiProofreadingSystemPrompt;

  /// No description provided for @aiProofreadingChunk.
  ///
  /// In zh, this message translates to:
  /// **'完整发送内容，分块'**
  String get aiProofreadingChunk;

  /// No description provided for @aiProofreadingCompleteScope.
  ///
  /// In zh, this message translates to:
  /// **'以下各块展示完整 userContext JSON；请求还会附带上方系统提示词。'**
  String get aiProofreadingCompleteScope;

  /// No description provided for @aiProofreadingStart.
  ///
  /// In zh, this message translates to:
  /// **'确认并开始发送'**
  String get aiProofreadingStart;

  /// No description provided for @aiProofreadingCancelCost.
  ///
  /// In zh, this message translates to:
  /// **'取消只能停止后续处理；已发送请求和可能产生的费用无法撤回。'**
  String get aiProofreadingCancelCost;

  /// No description provided for @aiProofreadingAppliedCount.
  ///
  /// In zh, this message translates to:
  /// **'已应用变更'**
  String get aiProofreadingAppliedCount;

  /// No description provided for @aiProofreadingNoFindings.
  ///
  /// In zh, this message translates to:
  /// **'未找到可确认的异常或变更；缺章不等于原稿一定完整。'**
  String get aiProofreadingNoFindings;

  /// No description provided for @aiProofreadingApplicableChanges.
  ///
  /// In zh, this message translates to:
  /// **'可应用变更'**
  String get aiProofreadingApplicableChanges;

  /// No description provided for @aiProofreadingPending.
  ///
  /// In zh, this message translates to:
  /// **'待判断发现'**
  String get aiProofreadingPending;

  /// No description provided for @aiProofreadingIgnoredCount.
  ///
  /// In zh, this message translates to:
  /// **'已忽略 {count} 项（仅本轮结果）'**
  String aiProofreadingIgnoredCount(int count);

  /// No description provided for @aiProofreadingRestoreIgnored.
  ///
  /// In zh, this message translates to:
  /// **'恢复本轮全部忽略项'**
  String get aiProofreadingRestoreIgnored;

  /// No description provided for @aiProofreadingIgnoreFinding.
  ///
  /// In zh, this message translates to:
  /// **'忽略此发现及关联建议'**
  String get aiProofreadingIgnoreFinding;

  /// No description provided for @aiProofreadingRulesUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'规则提案尚未启用。'**
  String get aiProofreadingRulesUnavailable;

  /// No description provided for @aiProofreadingConflict.
  ///
  /// In zh, this message translates to:
  /// **'所选变更相互冲突，请取消其中一项。'**
  String get aiProofreadingConflict;

  /// No description provided for @aiProofreadingApplySelected.
  ///
  /// In zh, this message translates to:
  /// **'应用所选变更'**
  String get aiProofreadingApplySelected;

  /// No description provided for @aiProofreadingOriginal.
  ///
  /// In zh, this message translates to:
  /// **'完整原文'**
  String get aiProofreadingOriginal;

  /// No description provided for @aiProofreadingOriginalEvidence.
  ///
  /// In zh, this message translates to:
  /// **'完整原文证据'**
  String get aiProofreadingOriginalEvidence;

  /// No description provided for @aiProofreadingOriginalChapterTitle.
  ///
  /// In zh, this message translates to:
  /// **'原目录标题'**
  String get aiProofreadingOriginalChapterTitle;

  /// No description provided for @aiProofreadingNewChapterTitle.
  ///
  /// In zh, this message translates to:
  /// **'新目录标题'**
  String get aiProofreadingNewChapterTitle;

  /// No description provided for @aiProofreadingReplacement.
  ///
  /// In zh, this message translates to:
  /// **'替换内容'**
  String get aiProofreadingReplacement;

  /// No description provided for @aiProofreadingDelete.
  ///
  /// In zh, this message translates to:
  /// **'删除所示文字（保留正文块）'**
  String get aiProofreadingDelete;

  /// No description provided for @aiProofreadingRemoveBlock.
  ///
  /// In zh, this message translates to:
  /// **'删除整个正文块'**
  String get aiProofreadingRemoveBlock;

  /// No description provided for @aiProofreadingRemoveBlockImpact.
  ///
  /// In zh, this message translates to:
  /// **'此正文块会移除，不保留空段落；章节及其他文字块、图片、脚注、分隔符不删除。'**
  String get aiProofreadingRemoveBlockImpact;

  /// No description provided for @aiProofreadingReplace.
  ///
  /// In zh, this message translates to:
  /// **'替换原文'**
  String get aiProofreadingReplace;

  /// No description provided for @aiProofreadingRenameChapter.
  ///
  /// In zh, this message translates to:
  /// **'修正章节标题'**
  String get aiProofreadingRenameChapter;

  /// No description provided for @aiProofreadingRenameChapterImpact.
  ///
  /// In zh, this message translates to:
  /// **'仅修改本章目录标题；正文中的标题行保留，其他文字、图片、脚注、分隔符和层级不变。'**
  String get aiProofreadingRenameChapterImpact;

  /// No description provided for @aiProofreadingSplit.
  ///
  /// In zh, this message translates to:
  /// **'拆分并恢复章节'**
  String get aiProofreadingSplit;

  /// No description provided for @aiProofreadingSplitSource.
  ///
  /// In zh, this message translates to:
  /// **'原章节保留的边界段落'**
  String get aiProofreadingSplitSource;

  /// No description provided for @aiProofreadingSplitNew.
  ///
  /// In zh, this message translates to:
  /// **'新章节及其正文'**
  String get aiProofreadingSplitNew;

  /// No description provided for @aiProofreadingSplitRemoveTitle.
  ///
  /// In zh, this message translates to:
  /// **'从正文移除整行标题（含行尾换行），作为新章节标题。'**
  String get aiProofreadingSplitRemoveTitle;

  /// No description provided for @aiProofreadingSplitKeepTitle.
  ///
  /// In zh, this message translates to:
  /// **'同时保留正文中的标题行，不删除任何原文。'**
  String get aiProofreadingSplitKeepTitle;

  /// No description provided for @aiProofreadingSplitResources.
  ///
  /// In zh, this message translates to:
  /// **'这是单项拆分影响预览。原章前置块与边界前正文保留，边界后正文及后续块按原序归入新章；后续现有章节不变。批量拆分仍以冲突检查和应用校验为准。'**
  String get aiProofreadingSplitResources;

  /// No description provided for @aiProofreadingSplitParent.
  ///
  /// In zh, this message translates to:
  /// **'所属卷（新旧章节相同）'**
  String get aiProofreadingSplitParent;

  /// No description provided for @aiProofreadingSplitTopLevel.
  ///
  /// In zh, this message translates to:
  /// **'顶层章节（新旧章节均无所属卷）'**
  String get aiProofreadingSplitTopLevel;

  /// No description provided for @aiProofreadingSplitBeforeCount.
  ///
  /// In zh, this message translates to:
  /// **'原章保留的前置块：{count}'**
  String aiProofreadingSplitBeforeCount(int count);

  /// No description provided for @aiProofreadingSplitAfterCount.
  ///
  /// In zh, this message translates to:
  /// **'归入新章的后续块：{count}'**
  String aiProofreadingSplitAfterCount(int count);

  /// No description provided for @aiProofreadingSplitMore.
  ///
  /// In zh, this message translates to:
  /// **'再显示最多 100 块'**
  String get aiProofreadingSplitMore;

  /// No description provided for @aiProofreadingSplitCaption.
  ///
  /// In zh, this message translates to:
  /// **'图片说明'**
  String get aiProofreadingSplitCaption;

  /// No description provided for @aiProofreadingSplitAlt.
  ///
  /// In zh, this message translates to:
  /// **'替代文本'**
  String get aiProofreadingSplitAlt;

  /// No description provided for @aiProofreadingSplitMarker.
  ///
  /// In zh, this message translates to:
  /// **'脚注标记'**
  String get aiProofreadingSplitMarker;

  /// No description provided for @aiProofreadingReason.
  ///
  /// In zh, this message translates to:
  /// **'原因'**
  String get aiProofreadingReason;

  /// No description provided for @aiProofreadingLocate.
  ///
  /// In zh, this message translates to:
  /// **'定位原文'**
  String get aiProofreadingLocate;

  /// No description provided for @aiProofreadingApplyOne.
  ///
  /// In zh, this message translates to:
  /// **'应用此项'**
  String get aiProofreadingApplyOne;

  /// No description provided for @aiProofreadingUndetermined.
  ///
  /// In zh, this message translates to:
  /// **'无法确定'**
  String get aiProofreadingUndetermined;

  /// No description provided for @aiProofreadingSuspectedMissing.
  ///
  /// In zh, this message translates to:
  /// **'疑似原稿缺失'**
  String get aiProofreadingSuspectedMissing;

  /// No description provided for @aiProofreadingMissedHeading.
  ///
  /// In zh, this message translates to:
  /// **'疑似标题漏识别'**
  String get aiProofreadingMissedHeading;

  /// No description provided for @aiProofreadingMergedContent.
  ///
  /// In zh, this message translates to:
  /// **'疑似章节合并'**
  String get aiProofreadingMergedContent;

  /// No description provided for @aiProofreadingNumberingSuspect.
  ///
  /// In zh, this message translates to:
  /// **'疑似章号错误'**
  String get aiProofreadingNumberingSuspect;

  /// No description provided for @aiProofreadingAuthorNote.
  ///
  /// In zh, this message translates to:
  /// **'作者的话'**
  String get aiProofreadingAuthorNote;

  /// No description provided for @aiProofreadingStoryQuote.
  ///
  /// In zh, this message translates to:
  /// **'正文引用'**
  String get aiProofreadingStoryQuote;

  /// No description provided for @aiProofreadingNotAdvertisement.
  ///
  /// In zh, this message translates to:
  /// **'非广告'**
  String get aiProofreadingNotAdvertisement;

  /// No description provided for @aiProofreadingObserved.
  ///
  /// In zh, this message translates to:
  /// **'发现'**
  String get aiProofreadingObserved;

  /// No description provided for @aiTestConnection.
  ///
  /// In zh, this message translates to:
  /// **'测试连接'**
  String get aiTestConnection;

  /// No description provided for @aiTesting.
  ///
  /// In zh, this message translates to:
  /// **'正在测试连接…'**
  String get aiTesting;

  /// No description provided for @aiCancelTest.
  ///
  /// In zh, this message translates to:
  /// **'取消测试'**
  String get aiCancelTest;

  /// No description provided for @aiTestPassed.
  ///
  /// In zh, this message translates to:
  /// **'连接测试通过，可保存当前配置。修改格式、地址、密钥或模型后需重新测试。'**
  String get aiTestPassed;

  /// No description provided for @aiNotTested.
  ///
  /// In zh, this message translates to:
  /// **'尚未测试当前配置。'**
  String get aiNotTested;

  /// No description provided for @aiSaved.
  ///
  /// In zh, this message translates to:
  /// **'当前 AI 配置已保存。'**
  String get aiSaved;

  /// No description provided for @aiSave.
  ///
  /// In zh, this message translates to:
  /// **'保存配置'**
  String get aiSave;

  /// No description provided for @aiClear.
  ///
  /// In zh, this message translates to:
  /// **'清除 AI 配置与密钥'**
  String get aiClear;

  /// No description provided for @aiClearTitle.
  ///
  /// In zh, this message translates to:
  /// **'清除 AI 配置？'**
  String get aiClearTitle;

  /// No description provided for @aiClearDescription.
  ///
  /// In zh, this message translates to:
  /// **'停用 AI 并删除当前配置关联的密钥，不修改书稿。'**
  String get aiClearDescription;

  /// No description provided for @aiClearConfirm.
  ///
  /// In zh, this message translates to:
  /// **'清除'**
  String get aiClearConfirm;

  /// No description provided for @aiCleared.
  ///
  /// In zh, this message translates to:
  /// **'AI 已停用，当前配置与关联密钥已清除。'**
  String get aiCleared;

  /// No description provided for @aiCleanupWarning.
  ///
  /// In zh, this message translates to:
  /// **'当前配置已安全提交，但旧密钥清理尚未完成。可以重试，不影响书稿。'**
  String get aiCleanupWarning;

  /// No description provided for @aiRetryCleanup.
  ///
  /// In zh, this message translates to:
  /// **'重试清理旧密钥'**
  String get aiRetryCleanup;

  /// No description provided for @aiCleanupDone.
  ///
  /// In zh, this message translates to:
  /// **'旧密钥已清理。'**
  String get aiCleanupDone;

  /// No description provided for @aiLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法读取 AI 配置，请重试；不会据此启用联网。'**
  String get aiLoadFailed;

  /// No description provided for @aiReload.
  ///
  /// In zh, this message translates to:
  /// **'重新读取配置'**
  String get aiReload;

  /// No description provided for @aiBusy.
  ///
  /// In zh, this message translates to:
  /// **'上一项操作尚未结束，请稍后再试。'**
  String get aiBusy;

  /// No description provided for @aiInvalidConfiguration.
  ///
  /// In zh, this message translates to:
  /// **'请检查地址、模型与密钥；启用前需完成当前配置的连接测试。'**
  String get aiInvalidConfiguration;

  /// No description provided for @aiMissingCredential.
  ///
  /// In zh, this message translates to:
  /// **'请输入密钥；更换地址或格式后不能自动沿用旧密钥。'**
  String get aiMissingCredential;

  /// No description provided for @aiCredentialUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'无法访问系统安全存储。请检查密钥环是否已解锁后重试，不会改用明文保存。'**
  String get aiCredentialUnavailable;

  /// No description provided for @aiStaleConfiguration.
  ///
  /// In zh, this message translates to:
  /// **'配置已被其他操作修改，请重新读取后再保存。'**
  String get aiStaleConfiguration;

  /// No description provided for @aiProofRequired.
  ///
  /// In zh, this message translates to:
  /// **'当前配置尚未通过连接测试，或测试后已经修改，请重新测试。'**
  String get aiProofRequired;

  /// No description provided for @aiConnectionFailed.
  ///
  /// In zh, this message translates to:
  /// **'服务没有返回符合要求的连接测试结果，请核对模型与接口格式。'**
  String get aiConnectionFailed;

  /// No description provided for @aiCancelled.
  ///
  /// In zh, this message translates to:
  /// **'测试已取消；服务端已经发生的处理或费用无法撤回。'**
  String get aiCancelled;

  /// No description provided for @aiSaveFailed.
  ///
  /// In zh, this message translates to:
  /// **'配置保存失败，原配置仍保留，请重试。'**
  String get aiSaveFailed;

  /// No description provided for @aiCommitUnknown.
  ///
  /// In zh, this message translates to:
  /// **'无法确认配置保存状态，请重新读取配置后再操作。'**
  String get aiCommitUnknown;

  /// No description provided for @aiCleanupFailed.
  ///
  /// In zh, this message translates to:
  /// **'旧密钥尚未清理，请稍后重试；不会删除当前仍在使用的密钥。'**
  String get aiCleanupFailed;

  /// No description provided for @aiAuthenticationFailed.
  ///
  /// In zh, this message translates to:
  /// **'服务拒绝鉴权，请检查密钥及其权限。'**
  String get aiAuthenticationFailed;

  /// No description provided for @aiRateLimited.
  ///
  /// In zh, this message translates to:
  /// **'服务暂时限流，请稍后手动重试；不会自动重复发送。'**
  String get aiRateLimited;

  /// No description provided for @aiTimedOut.
  ///
  /// In zh, this message translates to:
  /// **'连接测试超时，请检查服务地址后重试。'**
  String get aiTimedOut;

  /// No description provided for @aiRedirectRejected.
  ///
  /// In zh, this message translates to:
  /// **'服务返回了重定向，已阻止转发密钥；请填写最终服务地址。'**
  String get aiRedirectRejected;

  /// No description provided for @aiBudgetExceeded.
  ///
  /// In zh, this message translates to:
  /// **'请求或响应超过安全预算，请核对服务端点。'**
  String get aiBudgetExceeded;

  /// No description provided for @aiProtocolFailed.
  ///
  /// In zh, this message translates to:
  /// **'响应不符合所选协议，或已拒答、截断，请检查模型和接口格式。'**
  String get aiProtocolFailed;

  /// No description provided for @aiNetworkFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法连接服务，请检查网络、地址及证书。'**
  String get aiNetworkFailed;

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

  /// No description provided for @settingsData.
  ///
  /// In zh, this message translates to:
  /// **'数据'**
  String get settingsData;

  /// No description provided for @settingsPreferences.
  ///
  /// In zh, this message translates to:
  /// **'偏好设置'**
  String get settingsPreferences;

  /// No description provided for @settingsMaintenance.
  ///
  /// In zh, this message translates to:
  /// **'数据与维护'**
  String get settingsMaintenance;

  /// No description provided for @settingsHelp.
  ///
  /// In zh, this message translates to:
  /// **'帮助'**
  String get settingsHelp;

  /// No description provided for @settingsAppearanceDesc.
  ///
  /// In zh, this message translates to:
  /// **'应用主题与色彩。'**
  String get settingsAppearanceDesc;

  /// No description provided for @settingsDefaultsTitle.
  ///
  /// In zh, this message translates to:
  /// **'新书默认设置'**
  String get settingsDefaultsTitle;

  /// No description provided for @settingsDefaultsDesc.
  ///
  /// In zh, this message translates to:
  /// **'只影响以后导入的新书。'**
  String get settingsDefaultsDesc;

  /// No description provided for @settingsStorageTitle.
  ///
  /// In zh, this message translates to:
  /// **'数据与备份'**
  String get settingsStorageTitle;

  /// No description provided for @settingsStorageDesc.
  ///
  /// In zh, this message translates to:
  /// **'数据目录、批量处理与备份位置。'**
  String get settingsStorageDesc;

  /// No description provided for @settingsDiagnostics.
  ///
  /// In zh, this message translates to:
  /// **'运行状态'**
  String get settingsDiagnostics;

  /// No description provided for @settingsDiagnosticsDesc.
  ///
  /// In zh, this message translates to:
  /// **'内存、运行时长与最近一分钟走势。'**
  String get settingsDiagnosticsDesc;

  /// No description provided for @settingsRuntimeMemory.
  ///
  /// In zh, this message translates to:
  /// **'常驻内存'**
  String get settingsRuntimeMemory;

  /// No description provided for @settingsRuntimePeak.
  ///
  /// In zh, this message translates to:
  /// **'峰值内存'**
  String get settingsRuntimePeak;

  /// No description provided for @settingsRuntimeUptime.
  ///
  /// In zh, this message translates to:
  /// **'运行时长'**
  String get settingsRuntimeUptime;

  /// No description provided for @settingsRuntimePid.
  ///
  /// In zh, this message translates to:
  /// **'进程 ID'**
  String get settingsRuntimePid;

  /// No description provided for @settingsRuntimePlatform.
  ///
  /// In zh, this message translates to:
  /// **'平台'**
  String get settingsRuntimePlatform;

  /// No description provided for @settingsRuntimeRefresh.
  ///
  /// In zh, this message translates to:
  /// **'每秒刷新一次，仅在本机读取。'**
  String get settingsRuntimeRefresh;

  /// No description provided for @settingsRuntimeUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'当前平台不提供该数据'**
  String get settingsRuntimeUnavailable;

  /// No description provided for @settingsCollapseSidebar.
  ///
  /// In zh, this message translates to:
  /// **'收起侧栏'**
  String get settingsCollapseSidebar;

  /// No description provided for @settingsExpandSidebar.
  ///
  /// In zh, this message translates to:
  /// **'展开侧栏'**
  String get settingsExpandSidebar;

  /// No description provided for @editorTotalWords.
  ///
  /// In zh, this message translates to:
  /// **'全书 {count} 字'**
  String editorTotalWords(int count);

  /// No description provided for @editorTotalWordsWan.
  ///
  /// In zh, this message translates to:
  /// **'全书 {count} 万字'**
  String editorTotalWordsWan(String count);

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

  /// No description provided for @settingsDataLocationDesc.
  ///
  /// In zh, this message translates to:
  /// **'书籍、封面和备份都保存在这里，可以直接拷贝带走。'**
  String get settingsDataLocationDesc;

  /// No description provided for @settingsDataLocationMobileDesc.
  ///
  /// In zh, this message translates to:
  /// **'书籍保存在应用私有目录，文件管理器无法直接打开。卸载应用可能删除这些数据；导出书籍或备份时，可自行选择保存位置。'**
  String get settingsDataLocationMobileDesc;

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

  /// No description provided for @librarySortBy.
  ///
  /// In zh, this message translates to:
  /// **'排序'**
  String get librarySortBy;

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

  /// No description provided for @importTaskTitle.
  ///
  /// In zh, this message translates to:
  /// **'导入书稿'**
  String get importTaskTitle;

  /// No description provided for @importPreparing.
  ///
  /// In zh, this message translates to:
  /// **'准备中'**
  String get importPreparing;

  /// No description provided for @importCancelling.
  ///
  /// In zh, this message translates to:
  /// **'正在取消…'**
  String get importCancelling;

  /// No description provided for @importProgressPercent.
  ///
  /// In zh, this message translates to:
  /// **'{percent}%'**
  String importProgressPercent(int percent);

  /// No description provided for @importSaving.
  ///
  /// In zh, this message translates to:
  /// **'正在保存书稿…'**
  String get importSaving;

  /// No description provided for @importSavingNotice.
  ///
  /// In zh, this message translates to:
  /// **'正在保存，请勿退出。'**
  String get importSavingNotice;

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

  /// No description provided for @importStageConvert.
  ///
  /// In zh, this message translates to:
  /// **'正在转换文字…'**
  String get importStageConvert;

  /// No description provided for @importStageReady.
  ///
  /// In zh, this message translates to:
  /// **'解析完成'**
  String get importStageReady;

  /// No description provided for @importStageSavePrepare.
  ///
  /// In zh, this message translates to:
  /// **'正在准备保存…'**
  String get importStageSavePrepare;

  /// No description provided for @importStageSaveChapters.
  ///
  /// In zh, this message translates to:
  /// **'正在保存章节…'**
  String get importStageSaveChapters;

  /// No description provided for @importStageSaveBlocks.
  ///
  /// In zh, this message translates to:
  /// **'正在保存正文…'**
  String get importStageSaveBlocks;

  /// No description provided for @importStageSaveFinalize.
  ///
  /// In zh, this message translates to:
  /// **'正在完成保存…'**
  String get importStageSaveFinalize;

  /// No description provided for @importPickFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法选择文件，请检查权限后重试。'**
  String get importPickFailed;

  /// No description provided for @importDropHint.
  ///
  /// In zh, this message translates to:
  /// **'把文件拖到这里，或点击选择。'**
  String get importDropHint;

  /// No description provided for @importDropUnsupported.
  ///
  /// In zh, this message translates to:
  /// **'仅支持 TXT / EPUB / DOCX 文件。'**
  String get importDropUnsupported;

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

  /// No description provided for @editorUndoDone.
  ///
  /// In zh, this message translates to:
  /// **'已撤销'**
  String get editorUndoDone;

  /// No description provided for @editorRedoDone.
  ///
  /// In zh, this message translates to:
  /// **'已重做'**
  String get editorRedoDone;

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

  /// No description provided for @editorNewVolume.
  ///
  /// In zh, this message translates to:
  /// **'新建卷'**
  String get editorNewVolume;

  /// No description provided for @editorNewChapter.
  ///
  /// In zh, this message translates to:
  /// **'新建章节'**
  String get editorNewChapter;

  /// No description provided for @editorNewChapterBefore.
  ///
  /// In zh, this message translates to:
  /// **'在此前新建章节'**
  String get editorNewChapterBefore;

  /// No description provided for @editorNewChapterAfter.
  ///
  /// In zh, this message translates to:
  /// **'在此后新建章节'**
  String get editorNewChapterAfter;

  /// No description provided for @editorNewVolumeBefore.
  ///
  /// In zh, this message translates to:
  /// **'在此前新建卷'**
  String get editorNewVolumeBefore;

  /// No description provided for @editorNewVolumeAfter.
  ///
  /// In zh, this message translates to:
  /// **'在此后新建卷'**
  String get editorNewVolumeAfter;

  /// No description provided for @editorMoveChapters.
  ///
  /// In zh, this message translates to:
  /// **'批量移动章节'**
  String get editorMoveChapters;

  /// No description provided for @editorVolumeTitle.
  ///
  /// In zh, this message translates to:
  /// **'卷名'**
  String get editorVolumeTitle;

  /// No description provided for @editorTargetVolume.
  ///
  /// In zh, this message translates to:
  /// **'所属卷'**
  String get editorTargetVolume;

  /// No description provided for @editorUnassigned.
  ///
  /// In zh, this message translates to:
  /// **'未分卷'**
  String get editorUnassigned;

  /// No description provided for @editorInsertPosition.
  ///
  /// In zh, this message translates to:
  /// **'插入位置'**
  String get editorInsertPosition;

  /// No description provided for @editorBeforeFirst.
  ///
  /// In zh, this message translates to:
  /// **'首章之前'**
  String get editorBeforeFirst;

  /// No description provided for @editorAfterChapter.
  ///
  /// In zh, this message translates to:
  /// **'在“{title}”之后'**
  String editorAfterChapter(String title);

  /// No description provided for @editorSelectChapters.
  ///
  /// In zh, this message translates to:
  /// **'选择要移动的章节'**
  String get editorSelectChapters;

  /// No description provided for @editorCreate.
  ///
  /// In zh, this message translates to:
  /// **'创建'**
  String get editorCreate;

  /// No description provided for @editorMove.
  ///
  /// In zh, this message translates to:
  /// **'移动'**
  String get editorMove;

  /// No description provided for @editorSelectAll.
  ///
  /// In zh, this message translates to:
  /// **'全选'**
  String get editorSelectAll;

  /// No description provided for @editorClearSelection.
  ///
  /// In zh, this message translates to:
  /// **'清空选择'**
  String get editorClearSelection;

  /// No description provided for @editorRenameVolume.
  ///
  /// In zh, this message translates to:
  /// **'重命名卷'**
  String get editorRenameVolume;

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

  /// No description provided for @editorDeleteVolume.
  ///
  /// In zh, this message translates to:
  /// **'删除卷'**
  String get editorDeleteVolume;

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

  /// No description provided for @editorWorkbenchAnalyzeGapWithAi.
  ///
  /// In zh, this message translates to:
  /// **'用 AI 分析'**
  String get editorWorkbenchAnalyzeGapWithAi;

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

  /// No description provided for @editorWorkbenchIssueTitleFormat.
  ///
  /// In zh, this message translates to:
  /// **'标题格式不一致'**
  String get editorWorkbenchIssueTitleFormat;

  /// No description provided for @editorWorkbenchIssueDuplicateContent.
  ///
  /// In zh, this message translates to:
  /// **'内容重复'**
  String get editorWorkbenchIssueDuplicateContent;

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

  /// No description provided for @bookWorkbenchLayoutSampleTitle.
  ///
  /// In zh, this message translates to:
  /// **'即时排版样例'**
  String get bookWorkbenchLayoutSampleTitle;

  /// No description provided for @bookWorkbenchLayoutSampleScope.
  ///
  /// In zh, this message translates to:
  /// **'此处样例、阅读预览和支持视觉排版的导出使用这些设置；正文编辑区保留原文，首行缩进不会显示在编辑区。'**
  String get bookWorkbenchLayoutSampleScope;

  /// No description provided for @bookWorkbenchLayoutSampleFirst.
  ///
  /// In zh, this message translates to:
  /// **'雨停后，街灯映在石板路上，书声渐近。'**
  String get bookWorkbenchLayoutSampleFirst;

  /// No description provided for @bookWorkbenchLayoutSampleSecond.
  ///
  /// In zh, this message translates to:
  /// **'新的一页徐徐展开。'**
  String get bookWorkbenchLayoutSampleSecond;

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

  /// No description provided for @dataWorkbenchBackupSavedWithRules.
  ///
  /// In zh, this message translates to:
  /// **'已保存书稿备份，包含 {count} 条本书规则。'**
  String dataWorkbenchBackupSavedWithRules(int count);

  /// No description provided for @dataWorkbenchBackupRules.
  ///
  /// In zh, this message translates to:
  /// **'备份包含 {count} 条本书规则；恢复时只补充缺失定义，不覆盖现有规则，也不会自动启用或试跑。'**
  String dataWorkbenchBackupRules(int count);

  /// No description provided for @dataWorkbenchBackupRulesMerged.
  ///
  /// In zh, this message translates to:
  /// **'规则恢复：新增 {added} 条，跳过已有 {skipped} 条。'**
  String dataWorkbenchBackupRulesMerged(int added, int skipped);

  /// No description provided for @dataWorkbenchBackupRulesFailed.
  ///
  /// In zh, this message translates to:
  /// **'书稿已恢复，但规则恢复失败：{message}'**
  String dataWorkbenchBackupRulesFailed(String message);

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
  /// **'安装包声明网络权限，用于可选 AI；默认关闭，仅主动测试连接时发送固定小样本，不发送书稿。'**
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

  /// No description provided for @ruleWorkbenchRulesCopyConflicts.
  ///
  /// In zh, this message translates to:
  /// **'同 ID 冲突时另存为新规则（否则跳过）'**
  String get ruleWorkbenchRulesCopyConflicts;

  /// No description provided for @ruleWorkbenchDuplicate.
  ///
  /// In zh, this message translates to:
  /// **'复制规则'**
  String get ruleWorkbenchDuplicate;

  /// No description provided for @ruleWorkbenchCopySuffix.
  ///
  /// In zh, this message translates to:
  /// **'（副本）'**
  String get ruleWorkbenchCopySuffix;

  /// No description provided for @ruleWorkbenchDuplicated.
  ///
  /// In zh, this message translates to:
  /// **'已创建「{name}」。'**
  String ruleWorkbenchDuplicated(String name);

  /// No description provided for @ruleWorkbenchSearch.
  ///
  /// In zh, this message translates to:
  /// **'搜索规则'**
  String get ruleWorkbenchSearch;

  /// No description provided for @ruleWorkbenchNoMatches.
  ///
  /// In zh, this message translates to:
  /// **'没有匹配的规则。'**
  String get ruleWorkbenchNoMatches;

  /// No description provided for @ruleWorkbenchClearSearch.
  ///
  /// In zh, this message translates to:
  /// **'清除搜索'**
  String get ruleWorkbenchClearSearch;

  /// No description provided for @ruleWorkbenchExportSelectTitle.
  ///
  /// In zh, this message translates to:
  /// **'选择要导出的规则'**
  String get ruleWorkbenchExportSelectTitle;

  /// No description provided for @ruleWorkbenchSelectAll.
  ///
  /// In zh, this message translates to:
  /// **'全选'**
  String get ruleWorkbenchSelectAll;

  /// No description provided for @ruleWorkbenchExportSelected.
  ///
  /// In zh, this message translates to:
  /// **'导出所选（{count}）'**
  String ruleWorkbenchExportSelected(int count);

  /// No description provided for @ruleWorkbenchImportPreview.
  ///
  /// In zh, this message translates to:
  /// **'将导入的规则'**
  String get ruleWorkbenchImportPreview;

  /// No description provided for @ruleWorkbenchImportWillSkip.
  ///
  /// In zh, this message translates to:
  /// **'已存在，将跳过'**
  String get ruleWorkbenchImportWillSkip;
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
