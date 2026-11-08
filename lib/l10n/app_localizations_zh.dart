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
  String get navLibrary => '书架';

  @override
  String get navImport => '导入';

  @override
  String get navSettings => '设置';

  @override
  String get libraryEmptyTitle => '书架里还没有书稿';

  @override
  String get libraryEmptyMessage => '导入书稿后，在这里查看和整理。';

  @override
  String get libraryEmptyAction => '导入书稿';

  @override
  String get importFormatsTitle => '格式与处理方式';

  @override
  String get importFormatTxt => 'TXT';

  @override
  String get importFormatEpub => 'EPUB';

  @override
  String get importFormatDocx => 'DOCX';

  @override
  String get importStatusPlanned => '计划中';

  @override
  String get importStatusNext => 'M1';

  @override
  String get settingsAppearance => '外观';

  @override
  String get aiSettingsTitle => 'AI 服务';

  @override
  String get aiSettingsDescription => '可选联网能力，默认关闭。由你选择服务，并主动发起每次任务。';

  @override
  String get aiEnabled => '启用 AI 辅助';

  @override
  String get aiOfflineNotice => '关闭时不发送 AI 请求；导入、编辑、规则扫描与导出仍可离线使用。';

  @override
  String get aiFormat => '接口格式';

  @override
  String get aiAddress => 'API 地址';

  @override
  String get aiOpenAiAddressHint => 'https://api.example.com/v1';

  @override
  String get aiClaudeAddressHint => 'https://api.example.com（无需填写 /v1）';

  @override
  String get aiApiKey => 'API 密钥';

  @override
  String get aiKeyNewHint => '输入密钥，仅保存到系统安全存储';

  @override
  String get aiKeyReuseHint => '留空沿用已保存密钥；不会把密钥填回表单';

  @override
  String get aiKeyChangedAddressHint => '地址或格式已改变，请重新输入密钥';

  @override
  String get aiShowKey => '显示密钥';

  @override
  String get aiHideKey => '隐藏密钥';

  @override
  String get aiModel => '模型标识';

  @override
  String get aiModelHint => '手动填写服务支持的模型名称';

  @override
  String get aiNormalizedAddress => '规范化基础地址';

  @override
  String get aiRequestAddress => '最终请求地址';

  @override
  String get aiEndpointInvalid => '请检查协议、地址、端口与接口格式。';

  @override
  String get aiRemoteHttpConsent => '我了解远程 HTTP 会明文传输密钥和内容，仍使用此地址';

  @override
  String get aiTestDisclosure =>
      '连接测试只发送固定小样例，不读取或发送书稿，可能产生少量费用。书稿分析需在校对工具中另行确认。';

  @override
  String get aiProofreadingTitle => 'AI 校对';

  @override
  String get editorAiCreateChapterRule => 'AI 创建章节识别规则';

  @override
  String get editorAiCreateAdvertisementRule => 'AI 创建广告清理规则';

  @override
  String get editorAiAnalyzeAdvertisement => 'AI 广告判断';

  @override
  String get aiJointRuleRequest => '同时请求规则候选';

  @override
  String get aiJointRuleHelp => '仅基于你提供的样例生成规则候选，不会自动保存或应用；请在规则工作台独立检查并试跑。';

  @override
  String get aiJointRuleLimits =>
      '每行一个样例：正例 1–12 条、反例 0–12 条；每条最多 2048 个 UTF-16 单元，总计最多 8192。所有正例必须完整位于同一个实际发送分块中。';

  @override
  String get aiJointRuleAuthorization => '规则候选显式授权';

  @override
  String aiJointRuleChunk(int index) {
    return '仅第 $index 个分块允许返回规则（从 1 开始编号）。';
  }

  @override
  String get aiJointRuleNotRequested => '本次未请求规则候选，分析无权生成规则。';

  @override
  String aiJointRuleCount(int count) {
    return '独立规则候选：$count';
  }

  @override
  String get aiRuleTitle => 'AI 样例建规则';

  @override
  String get aiRuleSelected => '所选原文';

  @override
  String get aiRuleIntent => '规则意图';

  @override
  String get aiRuleNegative => '不得命中的反例';

  @override
  String get aiRuleChapterTitle => '所在章节标题';

  @override
  String get aiRuleBefore => '选区前文';

  @override
  String get aiRuleAfter => '选区后文';

  @override
  String get aiRuleRelated => '发送的相关规则摘要（最多 16 条）';

  @override
  String get aiRuleRunning => '正在生成候选';

  @override
  String get aiRuleCompleted => '候选生成完成';

  @override
  String get aiRuleNoProposals => '未生成规则候选。可调整意图或反例后重新准备。';

  @override
  String get aiRuleCheckAndTrial => '检查并试跑';

  @override
  String get ruleWorkbenchTitle => '自定义规则';

  @override
  String get ruleWorkbenchNumberCaptureGroup => '章号来自捕获组（可选）';

  @override
  String get ruleWorkbenchNumberCaptureHelper =>
      '须同时设置标题捕获组；仅提取原文明示数字，不自动编号。留空不映射；0=整体匹配，1 起为捕获组。清空标题捕获组或切换为字面量/广告时会清除此章号设置。';

  @override
  String get ruleWorkbenchNumberCaptureInvalid => '请先设置标题捕获组，并输入可用编号内的非负整数。';

  @override
  String get ruleWorkbenchNumberToken => '原文章号数字';

  @override
  String get ruleWorkbenchParsedNumber => '解析后的章号';

  @override
  String get ruleWorkbenchDefinition => '完整规则定义';

  @override
  String get ruleWorkbenchId => '规则 ID';

  @override
  String get ruleWorkbenchBookId => '书稿 ID';

  @override
  String get ruleWorkbenchSource => '来源';

  @override
  String get ruleWorkbenchInitialRejected => '规则候选已过期或与现有规则冲突，请重新选择样例生成。';

  @override
  String get ruleWorkbenchOffline => '本地规则全书试跑；不会调用 AI。选定规则和命中后才会修改书稿。';

  @override
  String get ruleWorkbenchImportRules => '导入内置规则（只读）';

  @override
  String ruleWorkbenchImportPreset(String name) {
    return '预设：$name';
  }

  @override
  String get ruleWorkbenchImportCustom => '自定义';

  @override
  String get ruleWorkbenchImportAutoNote =>
      '自动识别由导入器内置启发式与广告规则完成；工作台不复制这部分逻辑，也不会在试跑中重放。';

  @override
  String get ruleWorkbenchImportCustomNote => '导入时还附加了自定义规则；它们同样只读展示，不参与本次试跑。';

  @override
  String get ruleWorkbenchImportInvalid => '无法解析当前导入规则（预设或自定义规则无效），请检查导入设置。';

  @override
  String get ruleWorkbenchImportReadOnly =>
      '导入规则只在导入或重新解析时执行，不会在本次试跑中运行；工作台只运行上面显式勾选的已保存规则。如需在书中复用，请新建规则。';

  @override
  String get ruleWorkbenchImportEmpty => '该预设没有可展示的章节、卷或丢弃规则。';

  @override
  String get ruleWorkbenchImportEntryChapter => '章节标题规则（整行匹配）';

  @override
  String get ruleWorkbenchImportEntryVolume => '卷标题规则（整行匹配）';

  @override
  String get ruleWorkbenchImportEntryDrop => '整行丢弃规则';

  @override
  String get ruleWorkbenchImportEntryInlineJunk => '行内推广清理规则';

  @override
  String get ruleWorkbenchRules => '本次规则集';

  @override
  String get ruleWorkbenchEmpty => '还没有规则。可以先创建一条本书规则。';

  @override
  String get ruleWorkbenchBookScope => '本书';

  @override
  String get ruleWorkbenchGlobalScope => '跨书';

  @override
  String get ruleWorkbenchEnabled => '启用';

  @override
  String get ruleWorkbenchDisabled => '停用';

  @override
  String get ruleWorkbenchUnsaved => '未保存';

  @override
  String get ruleWorkbenchCurrent => '当前规则';

  @override
  String get ruleWorkbenchBuiltIn => '内置';

  @override
  String get ruleWorkbenchUser => '用户';

  @override
  String get ruleWorkbenchAiSource => 'AI 来源';

  @override
  String get ruleWorkbenchActions => '规则操作';

  @override
  String get ruleWorkbenchEdit => '编辑';

  @override
  String get ruleWorkbenchEnable => '启用规则';

  @override
  String get ruleWorkbenchDisable => '停用规则';

  @override
  String get ruleWorkbenchDelete => '删除规则';

  @override
  String get ruleWorkbenchDeleteTitle => '确认删除规则？';

  @override
  String get ruleWorkbenchNew => '新建规则';

  @override
  String get ruleWorkbenchScan => '试跑全书';

  @override
  String get ruleWorkbenchIdentify => '识别什么';

  @override
  String get ruleWorkbenchExclude => '排除什么';

  @override
  String get ruleWorkbenchExcludePattern => '命中排除文本（可选）';

  @override
  String get ruleWorkbenchExcludePatternHelper =>
      '匹配所在行包含该文本时跳过该命中；区分大小写沿用上方设置。';

  @override
  String get ruleWorkbenchExcludePatternInvalid =>
      '排除文本不能跨行，且不超过 256 个 UTF-16 字符。';

  @override
  String get ruleWorkbenchWholeLine => '仅整行匹配';

  @override
  String get ruleWorkbenchNoGlobalRules => '没有可导出的规则。';

  @override
  String get ruleWorkbenchRulesNoSharedInFile => '文件中没有可用规则。';

  @override
  String get ruleWorkbenchExportSharedRules => '导出规则文件';

  @override
  String get ruleWorkbenchImportSharedRules => '导入规则文件';

  @override
  String ruleWorkbenchRulesExported(int count) {
    return '已导出 $count 条规则。';
  }

  @override
  String get ruleWorkbenchRulesImportTitle => '导入规则文件';

  @override
  String ruleWorkbenchRulesImportBody(int global, int book, int existing) {
    return '文件含 $global 条跨书规则、$book 条本书规则（复制到当前书）；$existing 条同 ID 已存在将跳过。只补充缺失定义，不覆盖、不自动启用或运行。';
  }

  @override
  String ruleWorkbenchRulesImported(int added, int skipped) {
    return '已导入：新增 $added 条，跳过已有 $skipped 条。';
  }

  @override
  String get ruleWorkbenchRulesImportInvalid => '规则文件无效或版本不兼容。';

  @override
  String get ruleWorkbenchWholeLineHelper => '忽略首尾空白后，命中必须覆盖整行；仅适用于标题行和正文行。';

  @override
  String get ruleWorkbenchEffect => '会改什么';

  @override
  String get ruleWorkbenchName => '规则名称';

  @override
  String get ruleWorkbenchKind => '规则类型';

  @override
  String get ruleWorkbenchChapter => '章节识别';

  @override
  String get ruleWorkbenchHeadingLevel => '识别层级';

  @override
  String get ruleWorkbenchVolumeLevel => '卷';

  @override
  String get ruleWorkbenchChapterLevel => '章节';

  @override
  String get ruleWorkbenchVolumeCandidate => '卷识别';

  @override
  String get ruleWorkbenchVolumeEffect =>
      '将完整标题行及换行从正文移除并建立顶层卷。边界后内容保留为不另拟目录标题的卷前内容，后续连续同归属章节移入新卷；无内容时不创建空章节。';

  @override
  String get ruleWorkbenchNewVolumeTitle => '新卷标题';

  @override
  String get ruleWorkbenchVolumeFrontMatter => '卷前内容（不另拟章节标题）';

  @override
  String get ruleWorkbenchVolumePreview =>
      '这是单项卷边界预览。新卷是顶层目录项，本身不承载正文。原章边界前内容保留；边界后的正文、图片、脚注与分隔符按原序归入新卷的卷前内容，目录中不另拟标题，无内容时不创建空章节。后续连续且与原章同归属的章节移入新卷，遇到卷或不同归属时停止。批量应用时按各卷边界分配，一次撤销。';

  @override
  String get ruleWorkbenchVolumeFollowingBlockCount => '归入卷前内容的后续块数';

  @override
  String get ruleWorkbenchVolumeFollowingBlocks => '展开卷前内容的后续全部块';

  @override
  String get ruleWorkbenchVolumeFollowingChapterCount => '单项应用将移入新卷的后续章节数';

  @override
  String get ruleWorkbenchVolumeFollowingChapters => '展开将移入新卷的后续章节列表';

  @override
  String get ruleWorkbenchMoreChapters => '加载更多章节';

  @override
  String get ruleWorkbenchAdvertisement => '广告识别';

  @override
  String get ruleWorkbenchTarget => '匹配目标';

  @override
  String get ruleWorkbenchHeadingLine => '匹配目标：标题行';

  @override
  String get ruleWorkbenchBodyLine => '正文行';

  @override
  String get ruleWorkbenchParagraph => '段落';

  @override
  String get ruleWorkbenchMode => '匹配方式';

  @override
  String get ruleWorkbenchLiteral => '普通文本';

  @override
  String get ruleWorkbenchSafeRegex => '受限正则（高级）';

  @override
  String get ruleWorkbenchPattern => '识别文本或表达式';

  @override
  String get ruleWorkbenchAdvanced => '高级选项';

  @override
  String get ruleWorkbenchTitleCaptureGroup => '目录标题来自捕获组';

  @override
  String get ruleWorkbenchTitleCaptureHelper => '留空=完整标题行；0=整体匹配；1 起为捕获组。';

  @override
  String get ruleWorkbenchAvailableGroups => '可用编号';

  @override
  String get ruleWorkbenchTitleCaptureInvalid => '请输入可用编号内的非负整数。';

  @override
  String get ruleWorkbenchFullHeadingLine => '完整标题行';

  @override
  String get ruleWorkbenchCaseSensitive => '区分大小写';

  @override
  String get ruleWorkbenchPositive => '必命中的正例（至少一行）';

  @override
  String get ruleWorkbenchNegative => '不得命中的反例（可多行）';

  @override
  String get ruleWorkbenchOnePerLine => '每行一个样例；单行内不换行';

  @override
  String get ruleWorkbenchAction => '动作';

  @override
  String get ruleWorkbenchCandidate => '标记广告候选（不删除）';

  @override
  String get ruleWorkbenchExactDeletion => '精确删除命中文本';

  @override
  String get ruleWorkbenchChapterEffect => '将完整标题行及换行从正文移除；新目录标题默认取整行，可映射捕获组。';

  @override
  String get ruleWorkbenchScope => '作用域';

  @override
  String get ruleWorkbenchPriority => '优先级（-1000 至 1000）';

  @override
  String get ruleWorkbenchPriorityInvalid => '优先级必须为整数。';

  @override
  String get ruleWorkbenchOpenBook => '请先打开书稿。';

  @override
  String get ruleWorkbenchUseDefinition => '加入规则集';

  @override
  String get ruleWorkbenchGlobalConfirmTitle => '改为跨书规则？';

  @override
  String get ruleWorkbenchGlobalConfirmBody =>
      '规则将出现在其他书稿的规则列表中，但不会自动参与试跑或修改正文。';

  @override
  String get ruleWorkbenchConfirm => '确认';

  @override
  String get ruleWorkbenchLoading => '正在加载规则';

  @override
  String get ruleWorkbenchScanning => '正在试跑全书';

  @override
  String get ruleWorkbenchReady => '试跑完成';

  @override
  String get ruleWorkbenchSaving => '正在保存规则';

  @override
  String get ruleWorkbenchSaved => '规则已保存；试跑结果已失效，请重新试跑后再应用。';

  @override
  String get ruleWorkbenchDeleted => '规则已删除。';

  @override
  String get ruleWorkbenchResults => '全书试跑结果';

  @override
  String get ruleWorkbenchCoverage => '覆盖';

  @override
  String get ruleWorkbenchChapters => '卷章节点';

  @override
  String get ruleWorkbenchBlocks => '文本块';

  @override
  String get ruleWorkbenchLines => '正文行';

  @override
  String get ruleWorkbenchTotalMatches => '总命中';

  @override
  String get ruleWorkbenchDistinctMatches => '去重命中';

  @override
  String get ruleWorkbenchConflicts => '冲突总数';

  @override
  String get ruleWorkbenchConflictSamples => '冲突样本';

  @override
  String get ruleWorkbenchTruncated => '未展示';

  @override
  String get ruleWorkbenchShown => '已展示命中';

  @override
  String get ruleWorkbenchExecuted => '已执行，命中';

  @override
  String get ruleWorkbenchNotExecuted => '未执行（已停用）';

  @override
  String get ruleWorkbenchConflictDetails => '查看冲突样本';

  @override
  String get ruleWorkbenchChapterConflict => '同一行多个拆章边界';

  @override
  String get ruleWorkbenchDeleteChapterConflict => '删除与拆章冲突';

  @override
  String get ruleWorkbenchDeletionConflict => '删除范围重叠';

  @override
  String get ruleWorkbenchMaxApply => '每批最多应用 100 项。';

  @override
  String get ruleWorkbenchSaveOnly => '仅保存当前规则';

  @override
  String get ruleWorkbenchApplySelected => '应用所选变更（一次撤销）';

  @override
  String get ruleWorkbenchSaveApply => '保存并应用所选本规则命中';

  @override
  String get ruleWorkbenchCandidateNotice => '广告候选仅供核对，不能勾选删除。';

  @override
  String get aiAdvertisementAnalyze => 'AI 判断广告';

  @override
  String aiAdvertisementSource(String name) {
    return '来自规则候选：$name';
  }

  @override
  String get aiAdvertisementSelectedText => '精确选区（仅此范围允许修改）';

  @override
  String get aiAdvertisementReadOnlyContext => '实际发送的只读相邻正文';

  @override
  String get aiAdvertisementSelectionScope =>
      '选区最多 8192 个 UTF-16 单元；仅分析所选文字及只读相邻上下文。更改章节范围将取消此选区请求。';

  @override
  String get aiAdvertisementSelectionLimit => '选区超过 8192 个 UTF-16 单元，请缩小后再分析。';

  @override
  String get aiAdvertisementSelectionExpired => '此广告选区已失效，请重新选择内容后再分析。';

  @override
  String get ruleWorkbenchMore => '加载更多命中';

  @override
  String get ruleWorkbenchReload => '重新载入已保存规则';

  @override
  String get ruleWorkbenchReloadTitle => '重新载入规则？';

  @override
  String get ruleWorkbenchReloadWarning => '当前未保存的规则定义、表单内容与试跑结果将被丢弃。';

  @override
  String get ruleWorkbenchLine => '行';

  @override
  String get ruleWorkbenchRule => '命中规则';

  @override
  String get ruleWorkbenchOffset => '范围';

  @override
  String get ruleWorkbenchSplitPrefix => '原章保留的边界块内容';

  @override
  String get ruleWorkbenchRemoveHeadingLine => '将移除的完整标题行';

  @override
  String get ruleWorkbenchSplitTitle => '新目录标题';

  @override
  String get ruleWorkbenchUnsupportedCrLine => '孤立 CR 标题行暂不支持拆章，请调整换行后重新试跑。';

  @override
  String get ruleWorkbenchSplitSuffix => '新章边界块剩余正文';

  @override
  String get ruleWorkbenchFollowingCount => '按原序移入新章的后续块数';

  @override
  String get ruleWorkbenchFollowingBlocks => '展开新章后续全部内容';

  @override
  String get ruleWorkbenchTextBlock => '正文块';

  @override
  String get ruleWorkbenchImageBlock => '图片块';

  @override
  String get ruleWorkbenchFootnoteBlock => '脚注块';

  @override
  String get ruleWorkbenchDividerBlock => '分隔块';

  @override
  String get ruleWorkbenchAssetId => '资源标识';

  @override
  String get ruleWorkbenchDeleteExact => '精确移除';

  @override
  String get ruleWorkbenchAfter => '改后完整文本块';

  @override
  String get aiProofreadingIntro => '选择分析目的与章节；准备范围不会发送书稿。';

  @override
  String get aiAuditGapSource => '来自书稿体检：章节编号断档';

  @override
  String aiAuditGapRange(int first, int last) {
    return '缺失章号：$first–$last';
  }

  @override
  String aiAuditGapBefore(String title) {
    return '前一章：$title';
  }

  @override
  String aiAuditGapAfter(String title) {
    return '后一章：$title';
  }

  @override
  String get aiAuditGapNoBefore => '本卷没有前一章，仅分析首个编号章节。';

  @override
  String get aiAuditGapNoAutoSend => '进入分析不会自动上传；请先核对请求范围，再确认发送。';

  @override
  String get aiAuditGapExpired => '此体检断档已失效，请重新体检后再分析。';

  @override
  String get aiProofreadingAdvertisement => '广告判断';

  @override
  String get aiProofreadingMissingChapter => '缺章诊断';

  @override
  String get aiProofreadingChapters => '分析章节';

  @override
  String get aiProofreadingScope => '可选当前章或多个章节；选中的正文完整分块分析。';

  @override
  String get aiProofreadingMissingScope => '默认取相邻两章；可调整章对。选中章节完整覆盖，不固定截取首尾。';

  @override
  String get aiProofreadingCurrentChapter => '当前章';

  @override
  String get aiProofreadingSelectedChapters => '已选章节';

  @override
  String get aiProofreadingPrepare => '准备并预览发送内容';

  @override
  String get aiProofreadingPhase => '任务状态';

  @override
  String get aiProofreadingIdle => '待开始';

  @override
  String get aiProofreadingPreparing => '准备中';

  @override
  String get aiProofreadingAwaitingConsent => '待确认发送';

  @override
  String get aiProofreadingRunning => '分析中';

  @override
  String get aiProofreadingCompleted => '分析完成';

  @override
  String get aiProofreadingApplying => '应用中';

  @override
  String get aiProofreadingApplied => '已应用';

  @override
  String get aiProofreadingCancelled => '已取消';

  @override
  String get aiProofreadingStale => '书稿已变化，结果失效';

  @override
  String get aiProofreadingFailed => '失败';

  @override
  String get aiProofreadingCompletedChunks => '已完成分块';

  @override
  String get aiProofreadingReview => '发送前确认';

  @override
  String get aiProofreadingCharacters => '原文字符数';

  @override
  String get aiProofreadingBlocks => '段落数';

  @override
  String get aiProofreadingChunks => '请求分块数';

  @override
  String get aiProofreadingSystemPrompt => '完整系统提示词';

  @override
  String get aiProofreadingChunk => '完整发送内容，分块';

  @override
  String get aiProofreadingCompleteScope =>
      '以下各块展示完整 userContext JSON；请求还会附带上方系统提示词。';

  @override
  String get aiProofreadingStart => '确认并开始发送';

  @override
  String get aiProofreadingCancelCost => '取消只能停止后续处理；已发送请求和可能产生的费用无法撤回。';

  @override
  String get aiProofreadingAppliedCount => '已应用变更';

  @override
  String get aiProofreadingNoFindings => '未找到可确认的异常或变更；缺章不等于原稿一定完整。';

  @override
  String get aiProofreadingApplicableChanges => '可应用变更';

  @override
  String get aiProofreadingPending => '待判断发现';

  @override
  String aiProofreadingIgnoredCount(int count) {
    return '已忽略 $count 项（仅本轮结果）';
  }

  @override
  String get aiProofreadingRestoreIgnored => '恢复本轮全部忽略项';

  @override
  String get aiProofreadingIgnoreFinding => '忽略此发现及关联建议';

  @override
  String get aiProofreadingRulesUnavailable => '规则提案尚未启用。';

  @override
  String get aiProofreadingConflict => '所选变更相互冲突，请取消其中一项。';

  @override
  String get aiProofreadingApplySelected => '应用所选变更';

  @override
  String get aiProofreadingOriginal => '完整原文';

  @override
  String get aiProofreadingOriginalEvidence => '完整原文证据';

  @override
  String get aiProofreadingOriginalChapterTitle => '原目录标题';

  @override
  String get aiProofreadingNewChapterTitle => '新目录标题';

  @override
  String get aiProofreadingReplacement => '替换内容';

  @override
  String get aiProofreadingDelete => '删除所示文字（保留正文块）';

  @override
  String get aiProofreadingRemoveBlock => '删除整个正文块';

  @override
  String get aiProofreadingRemoveBlockImpact =>
      '此正文块会移除，不保留空段落；章节及其他文字块、图片、脚注、分隔符不删除。';

  @override
  String get aiProofreadingReplace => '替换原文';

  @override
  String get aiProofreadingRenameChapter => '修正章节标题';

  @override
  String get aiProofreadingRenameChapterImpact =>
      '仅修改本章目录标题；正文中的标题行保留，其他文字、图片、脚注、分隔符和层级不变。';

  @override
  String get aiProofreadingSplit => '拆分并恢复章节';

  @override
  String get aiProofreadingSplitSource => '原章节保留的边界段落';

  @override
  String get aiProofreadingSplitNew => '新章节及其正文';

  @override
  String get aiProofreadingSplitRemoveTitle => '从正文移除整行标题（含行尾换行），作为新章节标题。';

  @override
  String get aiProofreadingSplitKeepTitle => '同时保留正文中的标题行，不删除任何原文。';

  @override
  String get aiProofreadingSplitResources =>
      '这是单项拆分影响预览。原章前置块与边界前正文保留，边界后正文及后续块按原序归入新章；后续现有章节不变。批量拆分仍以冲突检查和应用校验为准。';

  @override
  String get aiProofreadingSplitParent => '所属卷（新旧章节相同）';

  @override
  String get aiProofreadingSplitTopLevel => '顶层章节（新旧章节均无所属卷）';

  @override
  String aiProofreadingSplitBeforeCount(int count) {
    return '原章保留的前置块：$count';
  }

  @override
  String aiProofreadingSplitAfterCount(int count) {
    return '归入新章的后续块：$count';
  }

  @override
  String get aiProofreadingSplitMore => '再显示最多 100 块';

  @override
  String get aiProofreadingSplitCaption => '图片说明';

  @override
  String get aiProofreadingSplitAlt => '替代文本';

  @override
  String get aiProofreadingSplitMarker => '脚注标记';

  @override
  String get aiProofreadingReason => '原因';

  @override
  String get aiProofreadingLocate => '定位原文';

  @override
  String get aiProofreadingApplyOne => '应用此项';

  @override
  String get aiProofreadingUndetermined => '无法确定';

  @override
  String get aiProofreadingSuspectedMissing => '疑似原稿缺失';

  @override
  String get aiProofreadingMissedHeading => '疑似标题漏识别';

  @override
  String get aiProofreadingMergedContent => '疑似章节合并';

  @override
  String get aiProofreadingNumberingSuspect => '疑似章号错误';

  @override
  String get aiProofreadingAuthorNote => '作者的话';

  @override
  String get aiProofreadingStoryQuote => '正文引用';

  @override
  String get aiProofreadingNotAdvertisement => '非广告';

  @override
  String get aiProofreadingObserved => '发现';

  @override
  String get aiTestConnection => '测试连接';

  @override
  String get aiTesting => '正在测试连接…';

  @override
  String get aiCancelTest => '取消测试';

  @override
  String get aiTestPassed => '连接测试通过，可保存当前配置。修改格式、地址、密钥或模型后需重新测试。';

  @override
  String get aiNotTested => '尚未测试当前配置。';

  @override
  String get aiSaved => '当前 AI 配置已保存。';

  @override
  String get aiSave => '保存配置';

  @override
  String get aiClear => '清除 AI 配置与密钥';

  @override
  String get aiClearTitle => '清除 AI 配置？';

  @override
  String get aiClearDescription => '停用 AI 并删除当前配置关联的密钥，不修改书稿。';

  @override
  String get aiClearConfirm => '清除';

  @override
  String get aiCleared => 'AI 已停用，当前配置与关联密钥已清除。';

  @override
  String get aiCleanupWarning => '当前配置已安全提交，但旧密钥清理尚未完成。可以重试，不影响书稿。';

  @override
  String get aiRetryCleanup => '重试清理旧密钥';

  @override
  String get aiCleanupDone => '旧密钥已清理。';

  @override
  String get aiLoadFailed => '无法读取 AI 配置，请重试；不会据此启用联网。';

  @override
  String get aiReload => '重新读取配置';

  @override
  String get aiBusy => '上一项操作尚未结束，请稍后再试。';

  @override
  String get aiInvalidConfiguration => '请检查地址、模型与密钥；启用前需完成当前配置的连接测试。';

  @override
  String get aiMissingCredential => '请输入密钥；更换地址或格式后不能自动沿用旧密钥。';

  @override
  String get aiCredentialUnavailable => '无法访问系统安全存储。请检查密钥环是否已解锁后重试，不会改用明文保存。';

  @override
  String get aiStaleConfiguration => '配置已被其他操作修改，请重新读取后再保存。';

  @override
  String get aiProofRequired => '当前配置尚未通过连接测试，或测试后已经修改，请重新测试。';

  @override
  String get aiConnectionFailed => '服务没有返回符合要求的连接测试结果，请核对模型与接口格式。';

  @override
  String get aiCancelled => '测试已取消；服务端已经发生的处理或费用无法撤回。';

  @override
  String get aiSaveFailed => '配置保存失败，原配置仍保留，请重试。';

  @override
  String get aiCommitUnknown => '无法确认配置保存状态，请重新读取配置后再操作。';

  @override
  String get aiCleanupFailed => '旧密钥尚未清理，请稍后重试；不会删除当前仍在使用的密钥。';

  @override
  String get aiAuthenticationFailed => '服务拒绝鉴权，请检查密钥及其权限。';

  @override
  String get aiRateLimited => '服务暂时限流，请稍后手动重试；不会自动重复发送。';

  @override
  String get aiTimedOut => '连接测试超时，请检查服务地址后重试。';

  @override
  String get aiRedirectRejected => '服务返回了重定向，已阻止转发密钥；请填写最终服务地址。';

  @override
  String get aiBudgetExceeded => '请求或响应超过安全预算，请核对服务端点。';

  @override
  String get aiProtocolFailed => '响应不符合所选协议，或已拒答、截断，请检查模型和接口格式。';

  @override
  String get aiNetworkFailed => '无法连接服务，请检查网络、地址及证书。';

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
  String get glassStrong => '强';

  @override
  String get glassSoft => '轻';

  @override
  String get glassOff => '关';

  @override
  String get settingsData => '数据';

  @override
  String get settingsPreferences => '偏好设置';

  @override
  String get settingsMaintenance => '数据与维护';

  @override
  String get settingsHelp => '帮助';

  @override
  String get settingsAppearanceDesc => '主题与磨砂玻璃。';

  @override
  String get settingsDefaultsTitle => '新书默认设置';

  @override
  String get settingsDefaultsDesc => '只影响以后导入的新书。';

  @override
  String get settingsStorageTitle => '数据与备份';

  @override
  String get settingsStorageDesc => '数据目录、批量处理与备份位置。';

  @override
  String get settingsDiagnostics => '运行状态';

  @override
  String get settingsDiagnosticsDesc => '内存、运行时长与最近一分钟走势。';

  @override
  String get settingsRuntimeMemory => '常驻内存';

  @override
  String get settingsRuntimePeak => '峰值内存';

  @override
  String get settingsRuntimeUptime => '运行时长';

  @override
  String get settingsRuntimePid => '进程 ID';

  @override
  String get settingsRuntimePlatform => '平台';

  @override
  String get settingsRuntimeRefresh => '每秒刷新一次，仅在本机读取。';

  @override
  String get settingsRuntimeUnavailable => '当前平台不提供该数据';

  @override
  String get settingsCollapseSidebar => '收起侧栏';

  @override
  String get settingsExpandSidebar => '展开侧栏';

  @override
  String get settingsDataLocation => '数据目录';

  @override
  String get settingsCopyPath => '复制路径';

  @override
  String get settingsCopied => '路径已复制到剪贴板';

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
  String get designLabelChip => '标签';

  @override
  String get designLabelSwitch => '开关';

  @override
  String get designPlaceholderInput => '搜索或输入书名';

  @override
  String get bootstrapFailureTitle => '无法启动';

  @override
  String get bootstrapFailureBody => '数据目录或本地数据库无法打开。';

  @override
  String get notFoundTitle => '页面不存在';

  @override
  String get notFoundBack => '返回书架';

  @override
  String get importFormatTxtDesc => '自动识别 UTF-8 / GBK / Big5，按标题密度分章';

  @override
  String get importFormatEpubDesc => '保留 spine 顺序、目录层级与封面';

  @override
  String get importFormatDocxDesc => '还原「标题 1 / 标题 2」的卷章结构';

  @override
  String get importPendingTitle => '导入流程正在搭建';

  @override
  String get importPendingMessage =>
      'M1 会先打通 TXT：编码探测、分章评分、目录校对。当前版本先确认界面语言与数据结构。';

  @override
  String get settingsGlassDesc => '只用于侧栏、浮层与对话框；正文始终落在不透明的纸面上。';

  @override
  String get settingsDataLocationDesc => '书籍、封面和备份都保存在这里，可以直接拷贝带走。';

  @override
  String get settingsDataLocationMobileDesc =>
      '书籍保存在应用私有目录，文件管理器无法直接打开。卸载应用可能删除这些数据；导出书籍或备份时，可自行选择保存位置。';

  @override
  String get windowMinimize => '最小化';

  @override
  String get windowMaximize => '最大化';

  @override
  String get windowClose => '关闭';

  @override
  String get navAbout => '关于';

  @override
  String get aboutTech => '技术栈';

  @override
  String get aboutDesignSystem => '设计系统';

  @override
  String get appTagline => '把文字织成书';

  @override
  String get aboutHeading => '关于书织';

  @override
  String aboutVersionLabel(String version) {
    return '版本 $version';
  }

  @override
  String get appDescription => '本地优先的电子书工作台';

  @override
  String get aboutLocalNote => '无需账号，书稿与编辑数据保存在本机。';

  @override
  String get aboutChangelog => '更新日志';

  @override
  String get aboutTechIntro => '核心用纯 Dart，界面用 Flutter，所有数据落在本机 SQLite。';

  @override
  String get aboutOpenSource => '开放源代码';

  @override
  String get aboutDeveloper => '开发者';

  @override
  String get aboutBio => '独立开发者 / 开源爱好者';

  @override
  String get aboutHomepage => '个人主页';

  @override
  String get aboutContact => '联系作者';

  @override
  String get aboutThanks => '感谢每一位开源贡献者';

  @override
  String get aboutViewLicense => '查看开源许可';

  @override
  String get techFlutter => 'Flutter';

  @override
  String get techFlutterDesc => '跨平台界面框架';

  @override
  String get techDart => 'Dart 3';

  @override
  String get techDartDesc => '核心语言';

  @override
  String get techRiverpod => 'Riverpod';

  @override
  String get techRiverpodDesc => '状态管理';

  @override
  String get techDrift => 'Drift';

  @override
  String get techDriftDesc => '类型安全 SQLite';

  @override
  String get techRouter => 'go_router';

  @override
  String get techRouterDesc => '路由与深链';

  @override
  String get techWindow => 'window_manager';

  @override
  String get techWindowDesc => '桌面窗口控制';

  @override
  String get commonRetry => '重试';

  @override
  String get commonCancel => '取消';

  @override
  String get commonSave => '保存';

  @override
  String get libraryLoadFailed => '无法读取书架';

  @override
  String get libraryNoMatch => '没有找到匹配的书稿';

  @override
  String get librarySearch => '搜索书名或作者';

  @override
  String get libraryClearSearch => '清除搜索';

  @override
  String get librarySortBy => '排序';

  @override
  String get librarySortRecent => '最近修改';

  @override
  String get librarySortTitle => '书名';

  @override
  String get librarySortOpened => '最近打开';

  @override
  String get libraryUnknownAuthor => '作者未填';

  @override
  String get libraryBookActions => '书籍操作';

  @override
  String get libraryRename => '重命名';

  @override
  String get libraryDelete => '删除书籍';

  @override
  String get libraryBookTitle => '书名';

  @override
  String get libraryOperationFailed => '操作失败，请重试。';

  @override
  String libraryBookStats(int chapters, int words) {
    return '$chapters 章 · $words 字';
  }

  @override
  String libraryDeleteConfirm(String title) {
    return '确定删除《$title》吗？书稿和本地资源将一并删除。';
  }

  @override
  String get importSelectTitle => '选择书稿';

  @override
  String get importTxtReady => '支持 TXT、EPUB 和 DOCX。解析完成后检查章节、文字与格式损失提示，再加入书架。';

  @override
  String get importChooseFile => '选择文件';

  @override
  String get importChooseAnother => '重新选择文件';

  @override
  String importFileSize(String size) {
    return '大小：$size';
  }

  @override
  String get importSizeUnknown => '未知';

  @override
  String get importOptions => '解析选项';

  @override
  String get importEncoding => '文字编码';

  @override
  String get importEncodingAuto => '自动识别';

  @override
  String get importFilterAds => '过滤明显广告';

  @override
  String get importAnalyze => '解析并预览';

  @override
  String get importReviewTitle => '导入预览';

  @override
  String importReviewStats(int chapters, int words) {
    return '$chapters 章 · $words 字';
  }

  @override
  String importActualEncoding(String encoding) {
    return '识别编码：$encoding';
  }

  @override
  String get importWarnings => '请留意';

  @override
  String get importExcerpt => '正文片段';

  @override
  String get importWarningEncoding => '编码识别信心较低；可改选编码并重新解析。';

  @override
  String get importWarningNoHeadings => '未识别到章节标题，已按单章整理。';

  @override
  String get importWarningManyChapters => '识别出较多章节，请检查目录。';

  @override
  String importWarningGeneric(String code) {
    return '解析提示：$code';
  }

  @override
  String get importAddToLibrary => '加入书架并编辑';

  @override
  String get importTaskTitle => '导入书稿';

  @override
  String get importPreparing => '准备中';

  @override
  String get importCancelling => '正在取消…';

  @override
  String importProgressPercent(int percent) {
    return '$percent%';
  }

  @override
  String get importSaving => '正在保存书稿…';

  @override
  String get importSavingNotice => '正在保存，请勿退出。';

  @override
  String get importStagePrepare => '正在准备…';

  @override
  String get importStageDecode => '正在识别编码…';

  @override
  String get importStageParse => '正在整理章节…';

  @override
  String get importStageConvert => '正在转换文字…';

  @override
  String get importStageReady => '解析完成';

  @override
  String get importStageSavePrepare => '正在准备保存…';

  @override
  String get importStageSaveChapters => '正在保存章节…';

  @override
  String get importStageSaveBlocks => '正在保存正文…';

  @override
  String get importStageSaveFinalize => '正在完成保存…';

  @override
  String get importPickFailed => '无法选择文件，请检查权限后重试。';

  @override
  String get importAnalyzeFailed => '解析失败，请检查文件或尝试其他编码。';

  @override
  String get importSaveFailed => '保存失败，预览仍保留，可重试。';

  @override
  String get importDiscardFailed => '无法清理暂存文件，请重试。';

  @override
  String importFormatAvailable(String format) {
    return '$format · 可导入';
  }

  @override
  String importFormatLater(String format) {
    return '$format · 后续批次支持';
  }

  @override
  String get editorOpenFailed => '无法打开书稿';

  @override
  String get editorBack => '返回书架';

  @override
  String get editorChapters => '章节目录';

  @override
  String get editorBookInfo => '书籍信息';

  @override
  String get editorExport => '导出书稿';

  @override
  String get editorUndo => '撤销';

  @override
  String get editorUndoDone => '已撤销';

  @override
  String get editorRedoDone => '已重做';

  @override
  String get editorRedo => '重做';

  @override
  String get editorEdit => '编辑';

  @override
  String get editorPreview => '预览';

  @override
  String get editorSaving => '正在保存…';

  @override
  String get editorUnsaved => '尚有未保存修改';

  @override
  String get editorSaved => '已保存';

  @override
  String get editorSaveFailed => '保存失败';

  @override
  String get editorSaveFailedStay => '保存失败，已留在当前书稿。请重试。';

  @override
  String get editorSearchChapters => '搜索章节';

  @override
  String get editorNoChapters => '暂无章节';

  @override
  String get editorEmptyChapter => '本章没有正文';

  @override
  String get editorChapterActions => '章节操作';

  @override
  String get editorNewVolume => '新建卷';

  @override
  String get editorNewChapter => '新建章节';

  @override
  String get editorMoveChapters => '批量移动章节';

  @override
  String get editorVolumeTitle => '卷名';

  @override
  String get editorTargetVolume => '所属卷';

  @override
  String get editorUnassigned => '未分卷';

  @override
  String get editorInsertPosition => '插入位置';

  @override
  String get editorBeforeFirst => '首章之前';

  @override
  String editorAfterChapter(String title) {
    return '在“$title”之后';
  }

  @override
  String get editorSelectChapters => '选择要移动的章节';

  @override
  String get editorCreate => '创建';

  @override
  String get editorMove => '移动';

  @override
  String get editorSelectAll => '全选';

  @override
  String get editorClearSelection => '清空选择';

  @override
  String get editorRenameVolume => '重命名卷';

  @override
  String get editorRenameChapter => '重命名章节';

  @override
  String get editorChapterTitle => '章节标题';

  @override
  String get editorMergePrevious => '并入上一章';

  @override
  String get editorPromote => '升为卷';

  @override
  String get editorDemote => '降为章';

  @override
  String get editorDeleteChapter => '删除章节';

  @override
  String get editorDeleteVolume => '删除卷';

  @override
  String editorDeleteChapterConfirm(String title) {
    return '确定删除“$title”吗？其正文也会删除。';
  }

  @override
  String get editorParagraphActions => '段落操作';

  @override
  String get editorSplitHere => '从此段拆章';

  @override
  String get editorSetAsTitle => '设为章节标题';

  @override
  String get editorImageBlock => '图片段落';

  @override
  String get editorBookTitle => '书名';

  @override
  String get editorBookAuthor => '作者';

  @override
  String get editorMoreMetadata => '更多信息';

  @override
  String get editorDescription => '简介';

  @override
  String get editorSeries => '系列';

  @override
  String get editorPublisher => '出版社';

  @override
  String get editorLanguage => '语言';

  @override
  String get editorTags => '标签（用逗号分隔）';

  @override
  String get editorPublishedAt => '出版日期';

  @override
  String get editorInvalidDate => '请输入有效日期，格式为 YYYY-MM-DD。';

  @override
  String get editorTitleRequired => '书名不能为空。';

  @override
  String get editorLanguageRequired => '语言不能为空。';

  @override
  String get editorMetaSavedAutomatically => '更改会自动保存。';

  @override
  String get editorActionFailed => '操作未完成，请检查当前章节后重试。';

  @override
  String get editorExportSaved => '导出文件已保存。';

  @override
  String get editorExportFailed => '导出失败，请重试。';

  @override
  String get workbenchOpenBatch => '批量处理多本书';

  @override
  String get workbenchOpenData => '管理书籍数据与备份';

  @override
  String get workbenchSharingOpened => '分享面板已打开，请在目标应用中完成传输。';

  @override
  String get workbenchCoverUnavailable => '封面图片不可用';

  @override
  String get editorWorkbenchMoreActions => '更多书稿操作';

  @override
  String get editorWorkbenchTools => '书稿工具';

  @override
  String get editorWorkbenchReparse => '从原文件重新识别';

  @override
  String get editorWorkbenchShare => '分享到其他应用';

  @override
  String get editorWorkbenchCloseLocation => '关闭定位提示';

  @override
  String get editorWorkbenchLocationChanged => '该段落已变化，请重新检查。';

  @override
  String editorWorkbenchLocationAt(int index, String text) {
    return '定位到第 $index 段：$text';
  }

  @override
  String editorWorkbenchDeleteVolumeConfirm(String title) {
    return '删除卷“$title”后，卷内子章和正文会保留，并提升为顶层章节。';
  }

  @override
  String get editorWorkbenchShareFailed => '无法打开分享面板，请重试。';

  @override
  String get editorWorkbenchToolFailed => '处理失败，请检查书稿后重试。';

  @override
  String get editorWorkbenchToolsIntro => '检查与批量修改作用于当前书稿；修改先预览，执行后可撤销一步。';

  @override
  String get editorWorkbenchPreparingBook => '准备书稿…';

  @override
  String get editorWorkbenchCancelTask => '取消任务';

  @override
  String get editorWorkbenchAuditTitle => '全书体检';

  @override
  String get editorWorkbenchAuditDesc =>
      '编号、空章、重复标题及广告痕迹；短章 <120 字、长章 >30000 字为启发式提示';

  @override
  String get editorWorkbenchAuditRun => '检查当前书稿';

  @override
  String get editorWorkbenchAnalyzeGapWithAi => '用 AI 分析';

  @override
  String editorWorkbenchAuditTotal(int count) {
    return '共 $count 项提示';
  }

  @override
  String editorWorkbenchIssueCount(String label, int count) {
    return '$label：$count';
  }

  @override
  String get editorWorkbenchAuditLimit => '每类最多显示 20 条示例；总数包含全部提示。';

  @override
  String get editorWorkbenchMissedTitle => '疑似漏章';

  @override
  String get editorWorkbenchMissedDesc => '定位看起来像章节标题的正文段落，确认后可用段落菜单拆章';

  @override
  String get editorWorkbenchMissedRun => '查找疑似漏章';

  @override
  String editorWorkbenchMissedCount(int count) {
    return '找到 $count 处候选';
  }

  @override
  String editorWorkbenchMissedLocation(int chapter, int paragraph) {
    return '目录第 $chapter 项 · 段落第 $paragraph 项';
  }

  @override
  String get editorWorkbenchMissedLimit => '仅显示前 100 处候选。';

  @override
  String get editorWorkbenchFindReplace => '查找与替换';

  @override
  String get editorWorkbenchFindText => '查找内容';

  @override
  String get editorWorkbenchReplaceWith => '替换为';

  @override
  String get editorWorkbenchScope => '范围';

  @override
  String get editorWorkbenchScopeAll => '标题和正文';

  @override
  String get editorWorkbenchScopeTitle => '仅章节标题';

  @override
  String get editorWorkbenchScopeBody => '仅正文';

  @override
  String get editorWorkbenchRegex => '正则表达式';

  @override
  String get editorWorkbenchCaseSensitive => '区分大小写';

  @override
  String get editorWorkbenchPreviewReplace => '预览替换';

  @override
  String get editorWorkbenchRenumberTitle => '按卷重编号';

  @override
  String get editorWorkbenchRenumberDesc => '检查各卷章号并预览标题修改，不改动正文。';

  @override
  String get editorWorkbenchPreviewRenumber => '预览重编号';

  @override
  String get editorWorkbenchConvertTitle => '转换当前书稿';

  @override
  String get editorWorkbenchConvertDesc => '只转换当前章节标题和正文；原文件不会重新识别';

  @override
  String get editorWorkbenchConvertDirection => '转换方向';

  @override
  String get editorWorkbenchConvertSimplified => '繁体转简体';

  @override
  String get editorWorkbenchConvertTraditional => '简体转台湾繁体';

  @override
  String get editorWorkbenchPreviewConvert => '预览转换';

  @override
  String get editorWorkbenchReplaceLabel => '替换';

  @override
  String get editorWorkbenchRenumberLabel => '重编号';

  @override
  String get editorWorkbenchConvertLabel => '繁简转换';

  @override
  String get editorWorkbenchBatchEdit => '批量修改';

  @override
  String editorWorkbenchPreviewTitle(String operation) {
    return '$operation预览';
  }

  @override
  String editorWorkbenchPreviewStats(int hits, int fields) {
    return '命中 $hits 处，实际修改 $fields 个字段。';
  }

  @override
  String get editorWorkbenchBodyParagraph => '正文段落';

  @override
  String get editorWorkbenchApplyOneUndo => '执行修改（可撤销一步）';

  @override
  String get editorWorkbenchIssueMissingNumber => '缺失章号';

  @override
  String get editorWorkbenchIssueDuplicateNumber => '重复章号';

  @override
  String get editorWorkbenchIssueEmptyChapter => '空章';

  @override
  String get editorWorkbenchIssueDuplicateTitle => '重复标题';

  @override
  String get editorWorkbenchIssueTooLong => '长章';

  @override
  String get editorWorkbenchIssueTooShort => '短章';

  @override
  String get editorWorkbenchIssueEmptyVolume => '空卷';

  @override
  String get editorWorkbenchIssueAdLeftover => '广告痕迹';

  @override
  String get editorWorkbenchIssueTitleFormat => '标题格式不一致';

  @override
  String get editorWorkbenchIssueDuplicateContent => '内容重复';

  @override
  String get editorWorkbenchReparseInvalidRuleUtf8 => '规则 JSON 不是有效的 UTF-8 文本。';

  @override
  String get editorWorkbenchReparseFailed => '重新识别失败，请检查原文与规则后重试。';

  @override
  String get editorWorkbenchOriginalCacheFailed => '所选原文临时文件未清理，请稍后重试。';

  @override
  String get editorWorkbenchRuleCacheFailed => '规则临时文件未清理，请稍后重试。';

  @override
  String get editorWorkbenchRuleTooLarge => '规则 JSON 超过 16 KiB';

  @override
  String get editorWorkbenchRuleExported => '规则 JSON 已导出。';

  @override
  String get editorWorkbenchReparseChanged => '书稿已改变，请重新准备识别结果。';

  @override
  String get editorWorkbenchReparseConfirmTitle => '替换当前全部章节？';

  @override
  String editorWorkbenchReparseConfirmBody(int count) {
    return '将用刚识别的 $count 个目录项替换当前书稿的全部章节和正文。此操作会清空当前撤销历史；书名、作者、封面和排版设置会保留。已编辑内容不会保留在新章节中。';
  }

  @override
  String get editorWorkbenchReparseConfirmAction => '确认替换';

  @override
  String get editorWorkbenchPreparedCacheFailed => '识别结果临时文件未清理，请稍后重试。';

  @override
  String get editorWorkbenchReparseIntro =>
      '仅支持已保留原文的 TXT。先准备预览，再明确确认替换当前全部章节。转换当前书稿请使用书稿工具。';

  @override
  String get editorWorkbenchSelectOriginal => '原文缺失时重新选择同一个 TXT';

  @override
  String get editorWorkbenchForgetOriginal => '不再使用所选原文';

  @override
  String get editorWorkbenchSourceEncoding => '原文编码';

  @override
  String get editorWorkbenchAutoDetect => '自动检测';

  @override
  String get editorWorkbenchFilterAds => '过滤广告';

  @override
  String get editorWorkbenchRules => '识别规则';

  @override
  String get editorWorkbenchCustomRules => '自定义规则';

  @override
  String get editorWorkbenchImportRulesJson => '导入规则 JSON';

  @override
  String get editorWorkbenchExportRulesJson => '导出当前规则 JSON';

  @override
  String get editorWorkbenchRulesJsonFields =>
      '规则 JSON（name / chapter / volume / drop / inlineJunk）';

  @override
  String get editorWorkbenchRulesOnlyReparse => '规则只用于重新识别原文；普通批量替换请使用书稿工具。';

  @override
  String get editorWorkbenchPrepareReparse => '准备重新识别预览';

  @override
  String get editorWorkbenchPreparing => '准备中…';

  @override
  String get editorWorkbenchReparseAppliedUnsaved => '章节已替换，尚未保存成功；请使用顶部“重试”。';

  @override
  String get editorWorkbenchReparseAppliedSaved => '已替换当前章节并保存。';

  @override
  String get editorWorkbenchReparsePreview => '识别结果预览';

  @override
  String editorWorkbenchReparseStats(int chapters, int words) {
    return '$chapters 个目录项 · $words 字';
  }

  @override
  String get editorWorkbenchSourceEncodingSelected => '编码：按所选设置';

  @override
  String editorWorkbenchSourceEncodingActual(String encoding) {
    return '实际编码：$encoding';
  }

  @override
  String get editorWorkbenchReparseWarningsLimit => '仅显示前 20 条提示。';

  @override
  String get editorWorkbenchReparseApply => '替换当前全部章节…';

  @override
  String get editorWorkbenchOptionsFileEncoding => '文件编码';

  @override
  String get editorWorkbenchOptionsAuto => '自动';

  @override
  String get editorWorkbenchOptionsChapterRules => '章节识别';

  @override
  String get editorWorkbenchOptionsFilterAds => '过滤常见广告';

  @override
  String get editorWorkbenchOptionsEditRules => '编辑 JSON 规则';

  @override
  String get editorWorkbenchOptionsImportRules => '导入规则';

  @override
  String get editorWorkbenchOptionsExportRules => '导出规则';

  @override
  String get editorWorkbenchOptionsRemoveRules => '移除自定义规则';

  @override
  String editorWorkbenchOptionsCurrentRules(String name) {
    return '当前规则：$name';
  }

  @override
  String get editorWorkbenchOptionsConvertAtImport => '导入时简繁转换';

  @override
  String get editorWorkbenchOptionsKeepOriginal => '保持原样';

  @override
  String get editorWorkbenchOptionsToSimplified => '转为简体';

  @override
  String get editorWorkbenchOptionsToTaiwan => '台湾标准繁体';

  @override
  String get editorWorkbenchOptionsRulesTitle => 'JSON 识别规则';

  @override
  String get editorWorkbenchOptionsRulesHelp =>
      '字段：name、chapter、volume、drop、inlineJunk。规则独立于广告开关；危险或不支持的正则会被拒绝。';

  @override
  String get editorWorkbenchOptionsValidateApply => '校验并应用';

  @override
  String get editorWorkbenchRulePresetIxdzs => '爱下电子书';

  @override
  String get editorWorkbenchRulePresetBiquge => '笔趣阁';

  @override
  String get editorWorkbenchRulePresetNumbered => '数字标题';

  @override
  String get editorWorkbenchRulePresetBareNumber => '裸数字';

  @override
  String get editorWorkbenchRulePresetEnglish => '英文标题';

  @override
  String get bookWorkbenchSettings => '成书设置';

  @override
  String get bookWorkbenchMetadata => '书籍信息';

  @override
  String get bookWorkbenchLayoutFonts => '排版与字体';

  @override
  String get bookWorkbenchLayoutSampleTitle => '即时排版样例';

  @override
  String get bookWorkbenchLayoutSampleScope =>
      '此处样例、阅读预览和支持视觉排版的导出使用这些设置；正文编辑区保留原文，首行缩进不会显示在编辑区。';

  @override
  String get bookWorkbenchLayoutSampleFirst => '雨停后，街灯映在石板路上，书声渐近。';

  @override
  String get bookWorkbenchLayoutSampleSecond => '新的一页徐徐展开。';

  @override
  String get bookWorkbenchCover => '封面';

  @override
  String get bookWorkbenchReadingPreview => '阅读预览';

  @override
  String get bookWorkbenchTitleRequired => '书名不能为空';

  @override
  String get bookWorkbenchMoreInformation => '扩展信息';

  @override
  String get bookWorkbenchLanguageCodeHint => '使用 zh-CN 这类语言代码';

  @override
  String get bookWorkbenchPublicationDate => '出版日期（YYYY-MM-DD）';

  @override
  String get bookWorkbenchInvalidDate => '请输入有效日期';

  @override
  String bookWorkbenchLineHeight(String value) {
    return '行高 $value';
  }

  @override
  String bookWorkbenchParagraphSpacing(String value) {
    return '段间距 $value em';
  }

  @override
  String get bookWorkbenchTwoCharacterIndent => '首行缩进两字';

  @override
  String get bookWorkbenchJustify => '两端对齐';

  @override
  String get bookWorkbenchSeparateChapterNumber => '章号独行';

  @override
  String get bookWorkbenchBodyFontStyle => '正文样式';

  @override
  String get bookWorkbenchSerif => '衬线';

  @override
  String get bookWorkbenchSans => '无衬线';

  @override
  String get bookWorkbenchKai => '楷体';

  @override
  String get bookWorkbenchEmbeddedFontInfo => '嵌入字体仅作用于支持的导出格式，可能增大文件。';

  @override
  String get bookWorkbenchImportFont => '导入字体';

  @override
  String get bookWorkbenchRemoveFont => '移除引用';

  @override
  String get bookWorkbenchCustomCssLabel => '附加 CSS（仅 EPUB / HTML 导出）';

  @override
  String get bookWorkbenchUnsafeCss => 'CSS 不允许外链、脚本或不安全字符';

  @override
  String get bookWorkbenchCssNativeNote => '原生预览不会执行附加 CSS。';

  @override
  String get bookWorkbenchTemplate => '模板';

  @override
  String get bookWorkbenchImage => '图片';

  @override
  String get bookWorkbenchChooseCoverFirst => '请先选择封面图片。';

  @override
  String get bookWorkbenchChooseCoverImage => '选择封面图片';

  @override
  String get bookWorkbenchCoverLimits => '支持 JPEG、PNG、WebP；超过 1200 万像素的图片不会解码。';

  @override
  String get bookWorkbenchVertical => '竖排';

  @override
  String get bookWorkbenchBlocks => '色块';

  @override
  String get bookWorkbenchPalette => '配色';

  @override
  String get bookWorkbenchAuto => '自动';

  @override
  String get bookWorkbenchSand => '原木';

  @override
  String get bookWorkbenchInk => '墨夜';

  @override
  String get bookWorkbenchSea => '深海';

  @override
  String get bookWorkbenchWine => '酒红';

  @override
  String get bookWorkbenchForest => '松林';

  @override
  String bookWorkbenchTitleScale(String value) {
    return '标题倍率 $value';
  }

  @override
  String get bookWorkbenchAuthorPosition => '作者位置';

  @override
  String get bookWorkbenchTop => '上方';

  @override
  String get bookWorkbenchBottom => '下方';

  @override
  String get bookWorkbenchHidden => '隐藏';

  @override
  String get bookWorkbenchImageModeNote => '调整模板参数不会覆盖当前图片；切换到模板后应用。';

  @override
  String get bookWorkbenchPreviewCss => '附加 CSS 仅影响 EPUB / HTML 导出，原生预览不会执行。';

  @override
  String get bookWorkbenchPreviewWoff => 'WOFF 字体会嵌入 EPUB；原生预览暂不加载此格式。';

  @override
  String get bookWorkbenchPreviewFontMissing => '字体资源暂不可用；原生预览使用系统字型。';

  @override
  String get bookWorkbenchPreviewFontFailed => '字体无法在原生预览加载；导出仍会保留此资源。';

  @override
  String get bookWorkbenchPreviewFontUnsupported => '此字体格式不支持原生预览。';

  @override
  String get bookWorkbenchPreviewFontLoaded => '嵌入字体已在原生预览加载。';

  @override
  String get bookWorkbenchPreviewLimits =>
      '原生预览展示基础排版；阅读器分页与字体替换可能不同。TXT / Markdown 不保留视觉排版。';

  @override
  String bookWorkbenchPreviewIllustration(String caption) {
    return '插图（此预览只显示说明）：$caption';
  }

  @override
  String get bookWorkbenchNewBookDefaults => '新书默认设置';

  @override
  String get bookWorkbenchDefaultsScope => '只影响以后导入的新书；已有书籍使用自己的排版。';

  @override
  String get bookWorkbenchDefaultExportFormat => '默认导出格式';

  @override
  String get bookWorkbenchDefaultFontRole => '默认字体角色';

  @override
  String bookWorkbenchDefaultsLineHeight(String value) {
    return '行高：$value';
  }

  @override
  String get bookWorkbenchDefaultsIndent => '首行缩进';

  @override
  String bookWorkbenchSelectedFont(String mime) {
    return '已选择字体：$mime';
  }

  @override
  String get bookWorkbenchLoading => '正在读取';

  @override
  String bookWorkbenchCoverSemantics(String title) {
    return '$title 的封面';
  }

  @override
  String get bookWorkbenchCoverUnavailable => '封面图片不可用';

  @override
  String get dataWorkbenchBatchTitle => '批量任务';

  @override
  String get dataWorkbenchBatchSubtitle => '逐本处理，转换结果只在保存 ZIP 后离开应用。';

  @override
  String get dataWorkbenchBatchSettings => '任务设置';

  @override
  String get dataWorkbenchBatchAction => '操作';

  @override
  String get dataWorkbenchBatchAddToLibrary => '加入书架';

  @override
  String get dataWorkbenchBatchConvertFiles => '批量转换';

  @override
  String get dataWorkbenchOutputFormat => '输出格式';

  @override
  String get dataWorkbenchBatchTxtEncoding => 'TXT 编码';

  @override
  String get dataWorkbenchBatchChineseConversion => '简繁转换';

  @override
  String get dataWorkbenchBatchNoConversion => '不转换';

  @override
  String get dataWorkbenchBatchSimplified => '转简体';

  @override
  String get dataWorkbenchBatchTaiwanTraditional => '转台湾繁体';

  @override
  String get dataWorkbenchBatchFilterAds => '过滤广告';

  @override
  String get dataWorkbenchBatchChooseFiles => '选择 TXT / EPUB / DOCX';

  @override
  String get dataWorkbenchBatchStart => '开始';

  @override
  String get dataWorkbenchBatchCancelAfterSave => '完成当前保存后取消剩余项';

  @override
  String get dataWorkbenchBatchCancelRemaining => '取消剩余任务';

  @override
  String get dataWorkbenchBatchQueue => '队列';

  @override
  String get dataWorkbenchRetryFailedOnly => '只重试失败项';

  @override
  String get dataWorkbenchBatchSaveZip => '保存 ZIP';

  @override
  String get dataWorkbenchZipSaved => 'ZIP 已保存。';

  @override
  String get dataWorkbenchBatchSaveCancelled => '已取消保存，转换结果仍可重试保存。';

  @override
  String get dataWorkbenchBatchRetryEncoding => '重试编码';

  @override
  String get dataWorkbenchBatchAuto => '自动';

  @override
  String get dataWorkbenchStatusWaiting => '等待';

  @override
  String get dataWorkbenchStatusProcessing => '处理中';

  @override
  String get dataWorkbenchStatusSuccess => '成功';

  @override
  String get dataWorkbenchStatusFailed => '失败';

  @override
  String get dataWorkbenchStatusCancelled => '已取消';

  @override
  String get dataWorkbenchBatchPickFailed => '文件选择或清理失败。';

  @override
  String get dataWorkbenchBatchStartFailed => '批量任务无法启动。';

  @override
  String get dataWorkbenchZipSaveFailed => 'ZIP 保存失败，请重试。';

  @override
  String get dataWorkbenchLibraryTitle => '批量导出已选书籍';

  @override
  String get dataWorkbenchLibraryExportSelected => '生成所选书籍';

  @override
  String get dataWorkbenchLibraryFinishingSave => '正在完成保存';

  @override
  String get dataWorkbenchLibraryCancelRemaining => '取消剩余项';

  @override
  String get dataWorkbenchLibrarySaveSuccessfulZip => '保存成功项 ZIP';

  @override
  String get dataWorkbenchLibrarySaveCancelled => '已取消保存，结果仍可再次保存。';

  @override
  String get dataWorkbenchLibraryStartFailed => '无法启动书架导出。';

  @override
  String get dataWorkbenchBackupTitle => '书籍数据与备份';

  @override
  String get dataWorkbenchBackupBack => '返回';

  @override
  String get dataWorkbenchBackupCurrentBooks => '备份当前书籍';

  @override
  String get dataWorkbenchBackupIncludes =>
      '备份包含当前文字、目录、书籍信息、封面、字体、排版与规则，不包含撤销记录。';

  @override
  String get dataWorkbenchBackupIncludeSources => '包含原始文件';

  @override
  String get dataWorkbenchBackupWithoutSources =>
      '不含原文的备份仍可续编，但无法从原文件换编码或重新分章。';

  @override
  String get dataWorkbenchBackupSaveFile => '生成并保存 .bookloom';

  @override
  String get dataWorkbenchBackupRestore => '恢复备份';

  @override
  String get dataWorkbenchBackupMaxData => '最大恢复数据量（MiB）';

  @override
  String get dataWorkbenchBackupMaxDataHelp =>
      '按实际解压数据计量；备份副本、临时数据库与提交副本还需额外空间。';

  @override
  String get dataWorkbenchBackupChooseInspect => '选择并检查备份';

  @override
  String get dataWorkbenchBackupConflictPolicy => '相同 ID 的书籍';

  @override
  String get dataWorkbenchBackupKeepBoth => '保留两份';

  @override
  String get dataWorkbenchBackupSkipConflicts => '跳过备份中的同 ID 书';

  @override
  String get dataWorkbenchBackupOverwriteConflicts => '用备份覆盖同 ID 书';

  @override
  String get dataWorkbenchBackupCommitHelp =>
      '逐本提交；若中途失败，已成功恢复的书会保留，失败项会明确列出。未涉及的书籍保持原状。';

  @override
  String get dataWorkbenchBackupConfirmRestore => '确认恢复';

  @override
  String get dataWorkbenchBackupDiscardPreview => '放弃预览';

  @override
  String get dataWorkbenchBackupCancelAfterCommit => '正在完成当前书的提交，取消后续项目';

  @override
  String get dataWorkbenchBackupCancelTask => '取消任务';

  @override
  String get dataWorkbenchBackupSaved => '备份已保存。';

  @override
  String get dataWorkbenchBackupOverwriteTitle => '覆盖同 ID 书稿？';

  @override
  String get dataWorkbenchBackupOverwriteBody =>
      '备份中的当前内容将替换同 ID 书稿，不能通过会话撤销恢复。';

  @override
  String get dataWorkbenchBackupOverwriteRestore => '覆盖并恢复';

  @override
  String get dataWorkbenchBackupTaskCancelled => '任务已取消。';

  @override
  String dataWorkbenchBatchSelectedFiles(int count) {
    return '已选 $count 个文件';
  }

  @override
  String dataWorkbenchBatchSummary(int success, int failed, int total) {
    return '成功 $success · 失败 $failed · 共 $total';
  }

  @override
  String dataWorkbenchLibrarySelected(int count) {
    return '当前选中 $count 本；每批最多 40 本。';
  }

  @override
  String dataWorkbenchLibrarySummary(int success, int failed, int total) {
    return '本次队列：成功 $success · 失败 $failed · 共 $total';
  }

  @override
  String dataWorkbenchBackupStorage(String support, String cache) {
    return '应用数据：$support；缓存：$cache';
  }

  @override
  String dataWorkbenchBackupValidated(int count, String size) {
    return '已校验 $count 本；数据 $size';
  }

  @override
  String dataWorkbenchBackupSavedWithRules(int count) {
    return '已保存书稿备份，包含 $count 条本书规则。';
  }

  @override
  String dataWorkbenchBackupRules(int count) {
    return '备份包含 $count 条本书规则；恢复时只补充缺失定义，不覆盖现有规则，也不会自动启用或试跑。';
  }

  @override
  String dataWorkbenchBackupRulesMerged(int added, int skipped) {
    return '规则恢复：新增 $added 条，跳过已有 $skipped 条。';
  }

  @override
  String dataWorkbenchBackupRulesFailed(String message) {
    return '书稿已恢复，但规则恢复失败：$message';
  }

  @override
  String dataWorkbenchBackupEstimatedSpace(String size) {
    return '预计所需空间（估算）：$size';
  }

  @override
  String dataWorkbenchBackupPreviewBook(String title, int chapters, int words) {
    return '$title · $chapters 章 · $words';
  }

  @override
  String dataWorkbenchBackupRestored(int count) {
    return '恢复成功 $count';
  }

  @override
  String dataWorkbenchBackupSkipped(int count) {
    return '跳过 $count';
  }

  @override
  String dataWorkbenchBackupCancelled(int count) {
    return '取消 $count';
  }

  @override
  String get exportWorkbenchShareTitle => '分享书稿';

  @override
  String get exportWorkbenchExportTitle => '导出书稿';

  @override
  String get exportWorkbenchFormatLabel => '文件格式';

  @override
  String get exportWorkbenchEpubDescription =>
      '保留封面、卷章目录、书籍信息、排版和嵌入字体。阅读器可能使用自己的分页与字体。';

  @override
  String get exportWorkbenchDocxDescription =>
      '生成可编辑的标题和段落，映射基础排版。此格式不包含封面、插图和全部扩展元数据。';

  @override
  String get exportWorkbenchHtmlDescription =>
      '生成离线单文件网页，包含目录和内联样式，不包含封面、插图或外部资源。';

  @override
  String get exportWorkbenchTextDescription =>
      '保留文字与卷章结构；字体、封面、CSS 和视觉排版不适用于此格式。';

  @override
  String get exportWorkbenchDeviceHelpAction => '如何传到阅读设备';

  @override
  String get exportWorkbenchShareAction => '打开分享面板';

  @override
  String get exportWorkbenchSaveAction => '选择保存位置';

  @override
  String get exportWorkbenchDeviceHelpTitle => '导入到阅读设备';

  @override
  String get exportWorkbenchDeviceHelpIntro =>
      '先把书稿导出并保存为文件，再按阅读设备的导入方式传送。不同机型和固件支持的格式、菜单可能不同，请以设备说明为准；传送后在设备上打开文件检查目录和排版。';

  @override
  String get exportWorkbenchOfficialInfoAction => '打开官方说明';

  @override
  String get exportWorkbenchKindleName => 'Kindle';

  @override
  String get exportWorkbenchKindleSteps =>
      'Amazon 的 Send to Kindle 可接收 EPUB。保存文件后，主动打开其网页上传，再在 Kindle 上查看个人文档。该服务需要联网；设备收到文件后再检查显示效果。';

  @override
  String get exportWorkbenchKoboName => 'Kobo';

  @override
  String get exportWorkbenchKoboSteps =>
      'Kobo 官方说明提供未加 DRM 的 EPUB 文件的 USB 传送步骤：连接设备、在设备上确认连接、把文件复制到设备盘，安全弹出后在“我的书籍”查看。';

  @override
  String get exportWorkbenchBooxName => 'BOOX / 文石';

  @override
  String get exportWorkbenchBooxSteps =>
      '部分固件提供 BooxDrop。若你的设备有此入口，可按设备显示的地址，在同一 Wi-Fi 网络中从电脑传送文件；菜单和支持格式请按当前机型核对。';

  @override
  String get exportWorkbenchHanvonName => '汉王 / Hanvon';

  @override
  String get exportWorkbenchHanvonSteps =>
      '先核对当前机型的说明书，确认可读取的格式和 USB、传书或本地导入入口。完成传送后在设备书架中打开检查。官方页面只描述其所列机型，不代表所有汉王设备。';

  @override
  String get exportWorkbenchIreaderName => '掌阅 / iReader';

  @override
  String get exportWorkbenchIreaderSteps =>
      '先在当前机型或应用的帮助中确认支持格式及本地导入、传书入口；导出后按其提示选择文件，并在书架检查。不同 iReader 设备和应用版本可能不同。';

  @override
  String get dataWorkbenchBackupAnotherTaskRunning => '另一项任务正在运行。';

  @override
  String get dataWorkbenchBackupInvalidBudget => '请输入 1 到 1048576 MiB 的写入预算。';

  @override
  String get dataWorkbenchBackupFileTooLarge => '备份文件超过本次写入预算。';

  @override
  String get dataWorkbenchBackupActualSizeTooLarge => '备份文件实际大小超过本次预算。';

  @override
  String get editorWorkbenchReparsePresetBiquge => '笔趣阁系';

  @override
  String get editorWorkbenchReparsePresetBareNumber => '裸数字标题';

  @override
  String get editorWorkbenchReparsePresetEnglish => '英文 Chapter / Section';

  @override
  String get settingsPermissions => '权限与访问检查';

  @override
  String get permissionsIntro =>
      '仅在使用相关功能时访问必要数据。这里检查应用自身目录；外部文件与保存位置的访问权，需要在实际选择时由系统确认。';

  @override
  String get permissionsRefresh => '重新检查';

  @override
  String get permissionsStorageTitle => '应用数据与缓存';

  @override
  String get permissionsStorageHelp =>
      '书架、编辑内容、封面和字体保存在应用自身目录。检查只读写一份临时标记并立即清理，不读取或修改已有书稿。系统目录别名或文件损坏不等同于缺少存储权限。';

  @override
  String get permissionsSupport => '应用数据';

  @override
  String get permissionsBooks => '书稿与资源';

  @override
  String get permissionsCache => '临时缓存';

  @override
  String get permissionsReadReady => '读取：可用';

  @override
  String get permissionsReadFailed => '读取：不可用';

  @override
  String get permissionsWriteReady => '写入：可用';

  @override
  String get permissionsWriteFailed => '写入：不可用';

  @override
  String get permissionsCheckFailed => '检查未完成，请重试；不要据此判断权限已允许。';

  @override
  String get permissionsSystemTitle => '系统权限';

  @override
  String get permissionsNoRuntime =>
      '当前安装包没有需要弹窗申请的运行时权限。无需授予全盘存储、照片库、相机、麦克风、通讯录或定位权限来使用书稿功能。';

  @override
  String get permissionsDesktopSystem =>
      '桌面端按当前系统账户和目标文件、文件夹的访问控制读写。不能通过一个统一授权开关保证所有位置都可访问。';

  @override
  String get permissionsSystemUnavailable => '无法读取系统权限状态。可重试，或在系统应用设置中查看。';

  @override
  String get permissionsGranted => '已允许';

  @override
  String get permissionsNotGranted => '未允许';

  @override
  String get permissionsInternetDeclared =>
      '安装包声明网络权限，用于可选 AI；默认关闭，仅主动测试连接时发送固定小样本，不发送书稿。';

  @override
  String get permissionsStorageDeclared => '安装包声明了广泛存储访问权限，请在系统设置中核对。';

  @override
  String get permissionsOpenSystemSettings => '打开系统应用设置';

  @override
  String get permissionsSettingsFailed => '无法打开系统应用设置，请从系统设置中进入书织。';

  @override
  String get permissionsImportTitle => '导入文件、封面与字体';

  @override
  String get permissionsImportAndroid =>
      '在系统文件选择器中主动选择文件，应用只读取所选项目并复制到自身目录。不扫描其他文件，不覆盖原件；取消选择不会取得访问权。文件提供者的授权失效时，需要重新选择。';

  @override
  String get permissionsImportDesktop =>
      '应用只打开你在文件选择器中选定的文件。需要系统账户能够读取该文件；只读检查不会导入书架或修改原件。';

  @override
  String get permissionsReadAction => '选择书稿检查读取';

  @override
  String get permissionsReadSuccess => '所选文件可以读取，未导入或修改。';

  @override
  String get permissionsReadFailure => '无法读取所选文件，请重新选择或检查文件提供者和系统权限。';

  @override
  String get permissionsCancelled => '已取消，未取得新的文件访问权。';

  @override
  String get permissionsExportTitle => '导出与备份';

  @override
  String get permissionsExportAndroid =>
      '由系统“另存为”选择目标，仅向你确认的目标写入成品或备份。无需全盘存储权限。下面的检查会保存一份小型测试 TXT，不包含书稿；可在系统对话框中取消。';

  @override
  String get permissionsExportDesktop =>
      '仅写入你选择的保存位置，目标目录需可写。占用、只读、磁盘空间不足等也会导致保存失败。下面的检查会保存一份不含书稿的小型测试 TXT。';

  @override
  String get permissionsSaveAction => '选择位置保存测试文件';

  @override
  String get permissionsSaveSuccess => '测试文件已保存到所选位置。';

  @override
  String get permissionsSaveFailure => '测试文件保存失败，目标访问权尚未确认。';

  @override
  String get permissionsShareTitle => '分享与离线处理';

  @override
  String get permissionsShareAndroid =>
      '分享时只向你选择的接收应用临时授予该成品的只读访问权，不暴露书架目录。打开分享面板不代表对方已收到文件。本地编辑和转换无需联网；外部网页由系统浏览器打开。';

  @override
  String get permissionsShareDesktop =>
      '本地编辑和转换无需联网。导出后由你决定是否使用其他工具传送；打开外部网页时交给系统浏览器，不授予该网页书架访问权。';

  @override
  String get permissionsScopeNote => '检查结果仅代表当前应用目录或本次选定的文件、目标；不会自动申请其他权限。';

  @override
  String get permissionsRuntimePolicy =>
      '部分系统会额外列出权限项。当前书稿功能不需要下面这些运行时权限，也不会主动申请；保持关闭不影响通过系统选择器导入和保存。';

  @override
  String get permissionsRuntimeNotRequired => '非书稿功能所需，不会主动申请，可保持关闭。';

  @override
  String get ruleWorkbenchRulesCopyConflicts => '同 ID 冲突时另存为新规则（否则跳过）';

  @override
  String get ruleWorkbenchDuplicate => '复制规则';

  @override
  String get ruleWorkbenchCopySuffix => '（副本）';

  @override
  String ruleWorkbenchDuplicated(String name) {
    return '已创建「$name」。';
  }

  @override
  String get ruleWorkbenchSearch => '搜索规则';

  @override
  String get ruleWorkbenchNoMatches => '没有匹配的规则。';

  @override
  String get ruleWorkbenchClearSearch => '清除搜索';

  @override
  String get ruleWorkbenchExportSelectTitle => '选择要导出的规则';

  @override
  String get ruleWorkbenchSelectAll => '全选';

  @override
  String ruleWorkbenchExportSelected(int count) {
    return '导出所选（$count）';
  }

  @override
  String get ruleWorkbenchImportPreview => '将导入的规则';

  @override
  String get ruleWorkbenchImportWillSkip => '已存在，将跳过';
}
