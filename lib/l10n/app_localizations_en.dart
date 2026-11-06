// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'Bookloom';

  @override
  String get navLibrary => 'Library';

  @override
  String get navImport => 'Import';

  @override
  String get navSettings => 'Settings';

  @override
  String get libraryEmptyTitle => 'Your shelf is empty';

  @override
  String get libraryEmptyMessage =>
      'Import a manuscript to view and organize your books here.';

  @override
  String get libraryEmptyAction => 'Import a manuscript';

  @override
  String get importFormatsTitle => 'Formats and handling';

  @override
  String get importFormatTxt => 'TXT';

  @override
  String get importFormatEpub => 'EPUB';

  @override
  String get importFormatDocx => 'DOCX';

  @override
  String get importStatusPlanned => 'Planned';

  @override
  String get importStatusNext => 'M1';

  @override
  String get settingsAppearance => 'Appearance';

  @override
  String get settingsThemeMode => 'Theme';

  @override
  String get themeSystem => 'System';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get settingsGlass => 'Frosted glass';

  @override
  String get glassStrong => 'Strong';

  @override
  String get glassSoft => 'Soft';

  @override
  String get glassOff => 'Off';

  @override
  String get settingsData => 'Data';

  @override
  String get settingsPreferences => 'Preferences';

  @override
  String get settingsMaintenance => 'Data & maintenance';

  @override
  String get settingsHelp => 'Help';

  @override
  String get settingsAppearanceDesc => 'Theme and frosted glass.';

  @override
  String get settingsDefaultsTitle => 'Defaults for new books';

  @override
  String get settingsDefaultsDesc => 'Only affects books imported from now on.';

  @override
  String get settingsStorageTitle => 'Data & backup';

  @override
  String get settingsStorageDesc =>
      'Data folder, batch runs and backup location.';

  @override
  String get settingsDiagnostics => 'Runtime';

  @override
  String get settingsDiagnosticsDesc => 'Memory, uptime and the last minute.';

  @override
  String get settingsRuntimeMemory => 'Resident memory';

  @override
  String get settingsRuntimePeak => 'Peak memory';

  @override
  String get settingsRuntimeUptime => 'Uptime';

  @override
  String get settingsRuntimePid => 'Process ID';

  @override
  String get settingsRuntimePlatform => 'Platform';

  @override
  String get settingsRuntimeRefresh =>
      'Refreshed once a second, read on this device only.';

  @override
  String get settingsRuntimeUnavailable => 'Not available on this platform';

  @override
  String get settingsCollapseSidebar => 'Collapse sidebar';

  @override
  String get settingsExpandSidebar => 'Expand sidebar';

  @override
  String get settingsDataLocation => 'Data folder';

  @override
  String get settingsCopyPath => 'Copy path';

  @override
  String get settingsCopied => 'Path copied to clipboard';

  @override
  String get designTitle => 'Design system';

  @override
  String get designSubtitle =>
      'The single source of visual truth: change tokens, and everything follows.';

  @override
  String get designSectionColors => 'Color';

  @override
  String get designSectionColorsDesc => 'Semantic palette, light and dark.';

  @override
  String get designSectionType => 'Type';

  @override
  String get designSectionTypeDesc =>
      'Serif for headings, sans for UI; CJK and Latin share one scale.';

  @override
  String get designSectionSpacing => 'Spacing & radii';

  @override
  String get designSectionGlass => 'Glass & elevation';

  @override
  String get designSectionGlassDesc =>
      'Glass appears only on floating chrome; turning it off degrades to opaque paper.';

  @override
  String get designSectionComponents => 'Components';

  @override
  String get designSectionComponentsDesc =>
      'Buttons, inputs, chips and selectors inherit the theme; pages never restyle them.';

  @override
  String get designTypeHeading => 'Weave text into books';

  @override
  String get designTypeBody =>
      'Spring river meets the sea, and the bright moon rises with the tide.';

  @override
  String get designSampleCardTitle => 'Chapter card';

  @override
  String get designSampleCardBody =>
      'Sample copy to check leading, tracking and gray levels.';

  @override
  String get designGlassPanelTitle => 'Floating panel';

  @override
  String get designGlassPanelBody =>
      'Content behind a glass pane is softly blurred. Body text never lives here.';

  @override
  String get designLabelPrimary => 'Primary';

  @override
  String get designLabelSecondary => 'Secondary';

  @override
  String get designLabelText => 'Text';

  @override
  String get designLabelChip => 'Chips';

  @override
  String get designLabelSwitch => 'Switch';

  @override
  String get designPlaceholderInput => 'Search or type a title';

  @override
  String get bootstrapFailureTitle => 'Cannot start';

  @override
  String get bootstrapFailureBody =>
      'The data folder or local database could not be opened.';

  @override
  String get notFoundTitle => 'Page not found';

  @override
  String get notFoundBack => 'Back to library';

  @override
  String get importFormatTxtDesc =>
      'Detect UTF-8 / GBK / Big5, split chapters by heading density';

  @override
  String get importFormatEpubDesc =>
      'Keep spine order, navigation hierarchy and cover';

  @override
  String get importFormatDocxDesc =>
      'Restore volumes and chapters from Heading 1 / Heading 2';

  @override
  String get importPendingTitle => 'Import is being built';

  @override
  String get importPendingMessage =>
      'M1 starts with TXT: encoding detection, chapter scoring, then manual review. This build only proves the interface language and data model.';

  @override
  String get settingsGlassDesc =>
      'Used only for sidebar, overlays and dialogs. Body text always sits on opaque paper.';

  @override
  String get settingsDataLocationDesc =>
      'Books, covers and backups live here. Copy the folder to take everything with you.';

  @override
  String get settingsDataLocationMobileDesc =>
      'Books are stored in the app\'s private folder, which file managers cannot open directly. Uninstalling the app may delete this data. Choose where to save exported books and backups.';

  @override
  String get windowMinimize => 'Minimize';

  @override
  String get windowMaximize => 'Maximize';

  @override
  String get windowClose => 'Close';

  @override
  String get navAbout => 'About';

  @override
  String get aboutTech => 'Tech stack';

  @override
  String get aboutDesignSystem => 'Design system';

  @override
  String get appTagline => 'Weave text into books';

  @override
  String get aboutHeading => 'About Bookloom';

  @override
  String aboutVersionLabel(String version) {
    return 'Version $version';
  }

  @override
  String get appDescription => 'A local-first ebook workspace';

  @override
  String get aboutLocalNote =>
      'No account needed. Manuscripts and edits stay on your device.';

  @override
  String get aboutChangelog => 'Changelog';

  @override
  String get aboutTechIntro =>
      'Pure Dart at the core, Flutter for the interface, everything stored in local SQLite.';

  @override
  String get aboutOpenSource => 'Open source';

  @override
  String get aboutDeveloper => 'Developer';

  @override
  String get aboutBio => 'Indie developer / open-source enthusiast';

  @override
  String get aboutHomepage => 'Homepage';

  @override
  String get aboutContact => 'Contact';

  @override
  String get aboutThanks => 'Thanks to every open-source contributor';

  @override
  String get aboutViewLicense => 'View license';

  @override
  String get techFlutter => 'Flutter';

  @override
  String get techFlutterDesc => 'Cross-platform UI toolkit';

  @override
  String get techDart => 'Dart 3';

  @override
  String get techDartDesc => 'Core language';

  @override
  String get techRiverpod => 'Riverpod';

  @override
  String get techRiverpodDesc => 'State management';

  @override
  String get techDrift => 'Drift';

  @override
  String get techDriftDesc => 'Type-safe SQLite';

  @override
  String get techRouter => 'go_router';

  @override
  String get techRouterDesc => 'Routing and deep links';

  @override
  String get techWindow => 'window_manager';

  @override
  String get techWindowDesc => 'Desktop window control';

  @override
  String get commonRetry => 'Retry';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonSave => 'Save';

  @override
  String get libraryLoadFailed => 'Could not load the library';

  @override
  String get libraryNoMatch => 'No matching books';

  @override
  String get librarySearch => 'Search titles or authors';

  @override
  String get libraryClearSearch => 'Clear search';

  @override
  String get librarySortBy => 'Sort by';

  @override
  String get librarySortRecent => 'Recently edited';

  @override
  String get librarySortTitle => 'Title';

  @override
  String get librarySortOpened => 'Recently opened';

  @override
  String get libraryUnknownAuthor => 'Author not set';

  @override
  String get libraryBookActions => 'Book actions';

  @override
  String get libraryRename => 'Rename';

  @override
  String get libraryDelete => 'Delete book';

  @override
  String get libraryBookTitle => 'Title';

  @override
  String get libraryOperationFailed => 'The operation failed. Please retry.';

  @override
  String libraryBookStats(int chapters, int words) {
    return '$chapters chapters · $words words';
  }

  @override
  String libraryDeleteConfirm(String title) {
    return 'Delete “$title”? Its manuscript and local assets will be removed.';
  }

  @override
  String get importSelectTitle => 'Select a manuscript';

  @override
  String get importTxtReady =>
      'Import TXT, EPUB or DOCX. Review the chapters, text and format-loss notices before adding the book to your library.';

  @override
  String get importChooseFile => 'Choose a file';

  @override
  String get importChooseAnother => 'Choose another file';

  @override
  String importFileSize(String size) {
    return 'Size: $size';
  }

  @override
  String get importSizeUnknown => 'Unknown';

  @override
  String get importOptions => 'Parsing options';

  @override
  String get importEncoding => 'Text encoding';

  @override
  String get importEncodingAuto => 'Auto detect';

  @override
  String get importFilterAds => 'Filter obvious ads';

  @override
  String get importAnalyze => 'Parse and preview';

  @override
  String get importReviewTitle => 'Import preview';

  @override
  String importReviewStats(int chapters, int words) {
    return '$chapters chapters · $words words';
  }

  @override
  String importActualEncoding(String encoding) {
    return 'Detected encoding: $encoding';
  }

  @override
  String get importWarnings => 'Please review';

  @override
  String get importExcerpt => 'Text excerpt';

  @override
  String get importWarningEncoding =>
      'Encoding detection is uncertain. Choose an encoding and parse again if needed.';

  @override
  String get importWarningNoHeadings =>
      'No chapter headings were found; the text was placed in one chapter.';

  @override
  String get importWarningManyChapters =>
      'Many chapters were found. Review the outline.';

  @override
  String importWarningGeneric(String code) {
    return 'Parsing notice: $code';
  }

  @override
  String get importAddToLibrary => 'Add to library and edit';

  @override
  String get importSaving => 'Saving manuscript…';

  @override
  String get importStagePrepare => 'Preparing…';

  @override
  String get importStageDecode => 'Detecting encoding…';

  @override
  String get importStageParse => 'Organizing chapters…';

  @override
  String get importStageReady => 'Parsing complete';

  @override
  String get importPickFailed =>
      'Could not choose a file. Check permissions and retry.';

  @override
  String get importAnalyzeFailed =>
      'Parsing failed. Check the file or try another encoding.';

  @override
  String get importSaveFailed =>
      'Saving failed. The preview is still available; retry.';

  @override
  String get importDiscardFailed =>
      'Could not clean up the temporary file. Retry.';

  @override
  String importFormatAvailable(String format) {
    return '$format · Available';
  }

  @override
  String importFormatLater(String format) {
    return '$format · Coming in a later batch';
  }

  @override
  String get editorOpenFailed => 'Could not open the manuscript';

  @override
  String get editorBack => 'Back to library';

  @override
  String get editorChapters => 'Chapter outline';

  @override
  String get editorBookInfo => 'Book information';

  @override
  String get editorExport => 'Export manuscript';

  @override
  String get editorUndo => 'Undo';

  @override
  String get editorUndoDone => 'Undone';

  @override
  String get editorRedoDone => 'Redone';

  @override
  String get editorRedo => 'Redo';

  @override
  String get editorEdit => 'Edit';

  @override
  String get editorPreview => 'Preview';

  @override
  String get editorSaving => 'Saving…';

  @override
  String get editorUnsaved => 'Unsaved changes';

  @override
  String get editorSaved => 'Saved';

  @override
  String get editorSaveFailed => 'Save failed';

  @override
  String get editorSaveFailedStay =>
      'Saving failed. You are still in this manuscript; please retry.';

  @override
  String get editorSearchChapters => 'Search chapters';

  @override
  String get editorNoChapters => 'No chapters';

  @override
  String get editorEmptyChapter => 'This chapter has no body text';

  @override
  String get editorChapterActions => 'Chapter actions';

  @override
  String get editorNewVolume => 'New volume';

  @override
  String get editorNewChapter => 'New chapter';

  @override
  String get editorMoveChapters => 'Move chapters';

  @override
  String get editorVolumeTitle => 'Volume title';

  @override
  String get editorTargetVolume => 'Volume';

  @override
  String get editorUnassigned => 'Unassigned';

  @override
  String get editorInsertPosition => 'Insert position';

  @override
  String get editorBeforeFirst => 'Before the first chapter';

  @override
  String editorAfterChapter(String title) {
    return 'After “$title”';
  }

  @override
  String get editorSelectChapters => 'Select chapters to move';

  @override
  String get editorCreate => 'Create';

  @override
  String get editorMove => 'Move';

  @override
  String get editorSelectAll => 'Select all';

  @override
  String get editorClearSelection => 'Clear selection';

  @override
  String get editorRenameVolume => 'Rename volume';

  @override
  String get editorRenameChapter => 'Rename chapter';

  @override
  String get editorChapterTitle => 'Chapter title';

  @override
  String get editorMergePrevious => 'Merge into previous chapter';

  @override
  String get editorPromote => 'Promote to volume';

  @override
  String get editorDemote => 'Demote to chapter';

  @override
  String get editorDeleteChapter => 'Delete chapter';

  @override
  String get editorDeleteVolume => 'Delete volume';

  @override
  String editorDeleteChapterConfirm(String title) {
    return 'Delete “$title” and its body text?';
  }

  @override
  String get editorParagraphActions => 'Paragraph actions';

  @override
  String get editorSplitHere => 'Split chapter here';

  @override
  String get editorSetAsTitle => 'Use as chapter title';

  @override
  String get editorImageBlock => 'Image block';

  @override
  String get editorBookTitle => 'Title';

  @override
  String get editorBookAuthor => 'Author';

  @override
  String get editorMoreMetadata => 'More information';

  @override
  String get editorDescription => 'Description';

  @override
  String get editorSeries => 'Series';

  @override
  String get editorPublisher => 'Publisher';

  @override
  String get editorLanguage => 'Language';

  @override
  String get editorTags => 'Tags (comma separated)';

  @override
  String get editorPublishedAt => 'Publication date';

  @override
  String get editorInvalidDate => 'Enter a valid date as YYYY-MM-DD.';

  @override
  String get editorTitleRequired => 'A title is required.';

  @override
  String get editorLanguageRequired => 'A language is required.';

  @override
  String get editorMetaSavedAutomatically => 'Changes save automatically.';

  @override
  String get editorActionFailed =>
      'The action did not complete. Check this chapter and retry.';

  @override
  String get editorExportSaved => 'Export file saved.';

  @override
  String get editorExportFailed => 'Export failed. Please retry.';

  @override
  String get workbenchOpenBatch => 'Process multiple books';

  @override
  String get workbenchOpenData => 'Manage books and backups';

  @override
  String get workbenchSharingOpened =>
      'Sharing panel opened. Complete the transfer in the receiving app.';

  @override
  String get workbenchCoverUnavailable => 'Cover image unavailable';

  @override
  String get editorWorkbenchMoreActions => 'More manuscript actions';

  @override
  String get editorWorkbenchTools => 'Manuscript tools';

  @override
  String get editorWorkbenchReparse => 'Reparse from source file';

  @override
  String get editorWorkbenchShare => 'Share to another app';

  @override
  String get editorWorkbenchCloseLocation => 'Dismiss location hint';

  @override
  String get editorWorkbenchLocationChanged =>
      'This paragraph has changed. Check it again.';

  @override
  String editorWorkbenchLocationAt(int index, String text) {
    return 'Located paragraph $index: $text';
  }

  @override
  String editorWorkbenchDeleteVolumeConfirm(String title) {
    return 'Delete volume “$title”? Its chapters and text will be kept as top-level chapters.';
  }

  @override
  String get editorWorkbenchShareFailed =>
      'Could not open the share panel. Please retry.';

  @override
  String get editorWorkbenchToolFailed =>
      'The operation failed. Check the manuscript and retry.';

  @override
  String get editorWorkbenchToolsIntro =>
      'Checks and bulk edits apply to this manuscript. Preview changes first; each applied batch can be undone in one step.';

  @override
  String get editorWorkbenchPreparingBook => 'Preparing manuscript…';

  @override
  String get editorWorkbenchCancelTask => 'Cancel task';

  @override
  String get editorWorkbenchAuditTitle => 'Manuscript check';

  @override
  String get editorWorkbenchAuditDesc =>
      'Checks numbering, empty chapters, duplicate titles and ad traces; short chapters (<120 characters) and long chapters (>30,000) are heuristic notices.';

  @override
  String get editorWorkbenchAuditRun => 'Check this manuscript';

  @override
  String editorWorkbenchAuditTotal(int count) {
    return '$count notices in total';
  }

  @override
  String editorWorkbenchIssueCount(String label, int count) {
    return '$label: $count';
  }

  @override
  String get editorWorkbenchAuditLimit =>
      'Up to 20 examples are shown per type; totals include all notices.';

  @override
  String get editorWorkbenchMissedTitle => 'Possible missed chapters';

  @override
  String get editorWorkbenchMissedDesc =>
      'Locate body paragraphs that resemble chapter headings; use the paragraph menu to split them after checking.';

  @override
  String get editorWorkbenchMissedRun => 'Find possible missed chapters';

  @override
  String editorWorkbenchMissedCount(int count) {
    return '$count candidates found';
  }

  @override
  String editorWorkbenchMissedLocation(int chapter, int paragraph) {
    return 'Outline item $chapter · paragraph $paragraph';
  }

  @override
  String get editorWorkbenchMissedLimit =>
      'Only the first 100 candidates are shown.';

  @override
  String get editorWorkbenchFindReplace => 'Find and replace';

  @override
  String get editorWorkbenchFindText => 'Find';

  @override
  String get editorWorkbenchReplaceWith => 'Replace with';

  @override
  String get editorWorkbenchScope => 'Scope';

  @override
  String get editorWorkbenchScopeAll => 'Titles and body text';

  @override
  String get editorWorkbenchScopeTitle => 'Chapter titles only';

  @override
  String get editorWorkbenchScopeBody => 'Body text only';

  @override
  String get editorWorkbenchRegex => 'Regular expression';

  @override
  String get editorWorkbenchCaseSensitive => 'Case-sensitive';

  @override
  String get editorWorkbenchPreviewReplace => 'Preview replacement';

  @override
  String get editorWorkbenchRenumberTitle => 'Renumber by volume';

  @override
  String get editorWorkbenchRenumberDesc =>
      'Check chapter numbering within each volume and preview title changes. Body text is unchanged.';

  @override
  String get editorWorkbenchPreviewRenumber => 'Preview renumbering';

  @override
  String get editorWorkbenchConvertTitle => 'Convert this manuscript';

  @override
  String get editorWorkbenchConvertDesc =>
      'Convert chapter titles and body text in this manuscript; the source file is not reparsed.';

  @override
  String get editorWorkbenchConvertDirection => 'Conversion direction';

  @override
  String get editorWorkbenchConvertSimplified =>
      'Traditional to simplified Chinese';

  @override
  String get editorWorkbenchConvertTraditional =>
      'Simplified to Taiwan traditional Chinese';

  @override
  String get editorWorkbenchPreviewConvert => 'Preview conversion';

  @override
  String get editorWorkbenchReplaceLabel => 'Replacement';

  @override
  String get editorWorkbenchRenumberLabel => 'Renumbering';

  @override
  String get editorWorkbenchConvertLabel => 'Chinese character conversion';

  @override
  String get editorWorkbenchBatchEdit => 'Bulk edit';

  @override
  String editorWorkbenchPreviewTitle(String operation) {
    return '$operation preview';
  }

  @override
  String editorWorkbenchPreviewStats(int hits, int fields) {
    return '$hits matches; $fields fields changed.';
  }

  @override
  String get editorWorkbenchBodyParagraph => 'Body paragraph';

  @override
  String get editorWorkbenchApplyOneUndo => 'Apply changes (one undo step)';

  @override
  String get editorWorkbenchIssueMissingNumber => 'Missing chapter number';

  @override
  String get editorWorkbenchIssueDuplicateNumber => 'Duplicate chapter number';

  @override
  String get editorWorkbenchIssueEmptyChapter => 'Empty chapter';

  @override
  String get editorWorkbenchIssueDuplicateTitle => 'Duplicate title';

  @override
  String get editorWorkbenchIssueTooLong => 'Long chapter';

  @override
  String get editorWorkbenchIssueTooShort => 'Short chapter';

  @override
  String get editorWorkbenchIssueEmptyVolume => 'Empty volume';

  @override
  String get editorWorkbenchIssueAdLeftover => 'Ad traces';

  @override
  String get editorWorkbenchReparseInvalidRuleUtf8 =>
      'The rules JSON is not valid UTF-8 text.';

  @override
  String get editorWorkbenchReparseFailed =>
      'Reparsing failed. Check the source text and rules, then retry.';

  @override
  String get editorWorkbenchOriginalCacheFailed =>
      'Could not clean up the selected source file. Retry later.';

  @override
  String get editorWorkbenchRuleCacheFailed =>
      'Could not clean up the temporary rules file. Retry later.';

  @override
  String get editorWorkbenchRuleTooLarge => 'Rules JSON exceeds 16 KiB';

  @override
  String get editorWorkbenchRuleExported => 'Rules JSON exported.';

  @override
  String get editorWorkbenchReparseChanged =>
      'The manuscript changed. Prepare the reparse preview again.';

  @override
  String get editorWorkbenchReparseConfirmTitle =>
      'Replace all current chapters?';

  @override
  String editorWorkbenchReparseConfirmBody(int count) {
    return 'Replace every chapter and its body text with the $count outline items just recognized. This clears the current undo history. Title, author, cover and layout settings are kept; edited chapter text is not.';
  }

  @override
  String get editorWorkbenchReparseConfirmAction => 'Replace chapters';

  @override
  String get editorWorkbenchPreparedCacheFailed =>
      'Could not clean up the temporary reparse result. Retry later.';

  @override
  String get editorWorkbenchReparseIntro =>
      'Only TXT manuscripts with their original source retained can be reparsed. Prepare a preview, then confirm replacing all chapters. Use Manuscript tools to convert the current manuscript.';

  @override
  String get editorWorkbenchSelectOriginal =>
      'Choose the same TXT if the source is missing';

  @override
  String get editorWorkbenchForgetOriginal => 'Stop using selected source';

  @override
  String get editorWorkbenchSourceEncoding => 'Source encoding';

  @override
  String get editorWorkbenchAutoDetect => 'Auto detect';

  @override
  String get editorWorkbenchFilterAds => 'Filter ads';

  @override
  String get editorWorkbenchRules => 'Parsing rules';

  @override
  String get editorWorkbenchCustomRules => 'Custom rules';

  @override
  String get editorWorkbenchImportRulesJson => 'Import rules JSON';

  @override
  String get editorWorkbenchExportRulesJson => 'Export current rules JSON';

  @override
  String get editorWorkbenchRulesJsonFields =>
      'Rules JSON (name / chapter / volume / drop / inlineJunk)';

  @override
  String get editorWorkbenchRulesOnlyReparse =>
      'Rules only apply when reparsing the source. Use Manuscript tools for ordinary bulk replacement.';

  @override
  String get editorWorkbenchPrepareReparse => 'Prepare reparse preview';

  @override
  String get editorWorkbenchPreparing => 'Preparing…';

  @override
  String get editorWorkbenchReparseAppliedUnsaved =>
      'Chapters were replaced but not saved. Use Retry at the top.';

  @override
  String get editorWorkbenchReparseAppliedSaved =>
      'Current chapters replaced and saved.';

  @override
  String get editorWorkbenchReparsePreview => 'Reparse result preview';

  @override
  String editorWorkbenchReparseStats(int chapters, int words) {
    return '$chapters outline items · $words words';
  }

  @override
  String get editorWorkbenchSourceEncodingSelected =>
      'Encoding: selected setting';

  @override
  String editorWorkbenchSourceEncodingActual(String encoding) {
    return 'Actual encoding: $encoding';
  }

  @override
  String get editorWorkbenchReparseWarningsLimit =>
      'Only the first 20 notices are shown.';

  @override
  String get editorWorkbenchReparseApply => 'Replace all current chapters…';

  @override
  String get editorWorkbenchOptionsFileEncoding => 'File encoding';

  @override
  String get editorWorkbenchOptionsAuto => 'Auto';

  @override
  String get editorWorkbenchOptionsChapterRules => 'Chapter rules';

  @override
  String get editorWorkbenchOptionsFilterAds => 'Filter common ads';

  @override
  String get editorWorkbenchOptionsEditRules => 'Edit JSON rules';

  @override
  String get editorWorkbenchOptionsImportRules => 'Import rules';

  @override
  String get editorWorkbenchOptionsExportRules => 'Export rules';

  @override
  String get editorWorkbenchOptionsRemoveRules => 'Remove custom rules';

  @override
  String editorWorkbenchOptionsCurrentRules(String name) {
    return 'Current rules: $name';
  }

  @override
  String get editorWorkbenchOptionsConvertAtImport => 'Convert imported text';

  @override
  String get editorWorkbenchOptionsKeepOriginal => 'Keep original';

  @override
  String get editorWorkbenchOptionsToSimplified => 'Simplified Chinese';

  @override
  String get editorWorkbenchOptionsToTaiwan => 'Taiwan traditional Chinese';

  @override
  String get editorWorkbenchOptionsRulesTitle => 'JSON chapter rules';

  @override
  String get editorWorkbenchOptionsRulesHelp =>
      'Fields: name, chapter, volume, drop, inlineJunk. Rules are independent of the ad filter; unsafe or unsupported regex is rejected.';

  @override
  String get editorWorkbenchOptionsValidateApply => 'Validate and apply';

  @override
  String get editorWorkbenchRulePresetIxdzs => 'ixdzs';

  @override
  String get editorWorkbenchRulePresetBiquge => 'Biquge';

  @override
  String get editorWorkbenchRulePresetNumbered => 'Numbered titles';

  @override
  String get editorWorkbenchRulePresetBareNumber => 'Bare numbers';

  @override
  String get editorWorkbenchRulePresetEnglish => 'English headings';

  @override
  String get bookWorkbenchSettings => 'Book settings';

  @override
  String get bookWorkbenchMetadata => 'Metadata';

  @override
  String get bookWorkbenchLayoutFonts => 'Layout and fonts';

  @override
  String get bookWorkbenchCover => 'Cover';

  @override
  String get bookWorkbenchReadingPreview => 'Reading preview';

  @override
  String get bookWorkbenchTitleRequired => 'Title is required';

  @override
  String get bookWorkbenchMoreInformation => 'More information';

  @override
  String get bookWorkbenchLanguageCodeHint => 'Use a language code like en-US';

  @override
  String get bookWorkbenchPublicationDate => 'Publication date (YYYY-MM-DD)';

  @override
  String get bookWorkbenchInvalidDate => 'Enter a valid date';

  @override
  String bookWorkbenchLineHeight(String value) {
    return 'Line height $value';
  }

  @override
  String bookWorkbenchParagraphSpacing(String value) {
    return 'Paragraph space $value em';
  }

  @override
  String get bookWorkbenchTwoCharacterIndent =>
      'Two-character first-line indent';

  @override
  String get bookWorkbenchJustify => 'Justify text';

  @override
  String get bookWorkbenchSeparateChapterNumber => 'Separate chapter number';

  @override
  String get bookWorkbenchBodyFontStyle => 'Body font style';

  @override
  String get bookWorkbenchSerif => 'Serif';

  @override
  String get bookWorkbenchSans => 'Sans serif';

  @override
  String get bookWorkbenchKai => 'Kai';

  @override
  String get bookWorkbenchEmbeddedFontInfo =>
      'Embedded fonts affect supported exports and may increase file size.';

  @override
  String get bookWorkbenchImportFont => 'Import font';

  @override
  String get bookWorkbenchRemoveFont => 'Remove font';

  @override
  String get bookWorkbenchCustomCssLabel => 'Additional CSS (EPUB / HTML only)';

  @override
  String get bookWorkbenchUnsafeCss =>
      'CSS cannot contain links, scripts, or unsafe characters';

  @override
  String get bookWorkbenchCssNativeNote =>
      'Native preview does not execute additional CSS.';

  @override
  String get bookWorkbenchTemplate => 'Template';

  @override
  String get bookWorkbenchImage => 'Image';

  @override
  String get bookWorkbenchChooseCoverFirst => 'Choose a cover image first.';

  @override
  String get bookWorkbenchChooseCoverImage => 'Choose cover image';

  @override
  String get bookWorkbenchCoverLimits =>
      'JPEG, PNG, WebP; images over 12 megapixels are rejected before decoding.';

  @override
  String get bookWorkbenchVertical => 'Vertical';

  @override
  String get bookWorkbenchBlocks => 'Blocks';

  @override
  String get bookWorkbenchPalette => 'Palette';

  @override
  String get bookWorkbenchAuto => 'Auto';

  @override
  String get bookWorkbenchSand => 'Sand';

  @override
  String get bookWorkbenchInk => 'Ink';

  @override
  String get bookWorkbenchSea => 'Sea';

  @override
  String get bookWorkbenchWine => 'Wine';

  @override
  String get bookWorkbenchForest => 'Forest';

  @override
  String bookWorkbenchTitleScale(String value) {
    return 'Title scale $value';
  }

  @override
  String get bookWorkbenchAuthorPosition => 'Author position';

  @override
  String get bookWorkbenchTop => 'Top';

  @override
  String get bookWorkbenchBottom => 'Bottom';

  @override
  String get bookWorkbenchHidden => 'Hidden';

  @override
  String get bookWorkbenchImageModeNote =>
      'Template changes do not replace the selected image until you switch modes.';

  @override
  String get bookWorkbenchPreviewCss =>
      'Additional CSS affects EPUB / HTML exports only; native preview does not execute it.';

  @override
  String get bookWorkbenchPreviewWoff =>
      'WOFF fonts are embedded in EPUB; native preview cannot load them.';

  @override
  String get bookWorkbenchPreviewFontMissing =>
      'The font asset is unavailable; native preview uses a system font.';

  @override
  String get bookWorkbenchPreviewFontFailed =>
      'The font could not load in native preview; it remains available for export.';

  @override
  String get bookWorkbenchPreviewFontUnsupported =>
      'This font format is unsupported in native preview.';

  @override
  String get bookWorkbenchPreviewFontLoaded =>
      'Embedded font loaded in native preview.';

  @override
  String get bookWorkbenchPreviewLimits =>
      'Native preview shows basic layout; reader pagination and font substitution may differ. TXT / Markdown do not retain visual layout.';

  @override
  String bookWorkbenchPreviewIllustration(String caption) {
    return 'Illustration (caption only in this preview): $caption';
  }

  @override
  String get bookWorkbenchNewBookDefaults => 'New book defaults';

  @override
  String get bookWorkbenchDefaultsScope =>
      'Applies to future imports. Existing books keep their own layout.';

  @override
  String get bookWorkbenchDefaultExportFormat => 'Default export format';

  @override
  String get bookWorkbenchDefaultFontRole => 'Default font role';

  @override
  String bookWorkbenchDefaultsLineHeight(String value) {
    return 'Line height: $value';
  }

  @override
  String get bookWorkbenchDefaultsIndent => 'Indent first line';

  @override
  String bookWorkbenchSelectedFont(String mime) {
    return 'Selected font: $mime';
  }

  @override
  String get bookWorkbenchLoading => 'loading';

  @override
  String bookWorkbenchCoverSemantics(String title) {
    return '$title cover';
  }

  @override
  String get bookWorkbenchCoverUnavailable => 'Cover image unavailable';

  @override
  String get dataWorkbenchBatchTitle => 'Batch tasks';

  @override
  String get dataWorkbenchBatchSubtitle =>
      'Process files one at a time. Converted files leave the app only when you save the ZIP.';

  @override
  String get dataWorkbenchBatchSettings => 'Task settings';

  @override
  String get dataWorkbenchBatchAction => 'Action';

  @override
  String get dataWorkbenchBatchAddToLibrary => 'Add to library';

  @override
  String get dataWorkbenchBatchConvertFiles => 'Convert files';

  @override
  String get dataWorkbenchOutputFormat => 'Output format';

  @override
  String get dataWorkbenchBatchTxtEncoding => 'TXT encoding';

  @override
  String get dataWorkbenchBatchChineseConversion => 'Chinese conversion';

  @override
  String get dataWorkbenchBatchNoConversion => 'None';

  @override
  String get dataWorkbenchBatchSimplified => 'Simplified';

  @override
  String get dataWorkbenchBatchTaiwanTraditional => 'Taiwan Traditional';

  @override
  String get dataWorkbenchBatchFilterAds => 'Filter ads';

  @override
  String get dataWorkbenchBatchChooseFiles => 'Choose TXT / EPUB / DOCX';

  @override
  String get dataWorkbenchBatchStart => 'Start';

  @override
  String get dataWorkbenchBatchCancelAfterSave => 'Cancel remaining after save';

  @override
  String get dataWorkbenchBatchCancelRemaining => 'Cancel remaining';

  @override
  String get dataWorkbenchBatchQueue => 'Queue';

  @override
  String get dataWorkbenchRetryFailedOnly => 'Retry failed only';

  @override
  String get dataWorkbenchBatchSaveZip => 'Save ZIP';

  @override
  String get dataWorkbenchZipSaved => 'ZIP saved.';

  @override
  String get dataWorkbenchBatchSaveCancelled =>
      'Save cancelled. You can save the results again.';

  @override
  String get dataWorkbenchBatchRetryEncoding => 'Retry encoding';

  @override
  String get dataWorkbenchBatchAuto => 'Auto';

  @override
  String get dataWorkbenchStatusWaiting => 'Waiting';

  @override
  String get dataWorkbenchStatusProcessing => 'Processing';

  @override
  String get dataWorkbenchStatusSuccess => 'Success';

  @override
  String get dataWorkbenchStatusFailed => 'Failed';

  @override
  String get dataWorkbenchStatusCancelled => 'Cancelled';

  @override
  String get dataWorkbenchBatchPickFailed =>
      'Could not select or release files.';

  @override
  String get dataWorkbenchBatchStartFailed => 'Could not start the batch.';

  @override
  String get dataWorkbenchZipSaveFailed => 'Could not save ZIP. Please retry.';

  @override
  String get dataWorkbenchLibraryTitle => 'Export selected books';

  @override
  String get dataWorkbenchLibraryExportSelected => 'Export selected';

  @override
  String get dataWorkbenchLibraryFinishingSave => 'Finishing save';

  @override
  String get dataWorkbenchLibraryCancelRemaining => 'Cancel remaining';

  @override
  String get dataWorkbenchLibrarySaveSuccessfulZip => 'Save successful ZIP';

  @override
  String get dataWorkbenchLibrarySaveCancelled =>
      'Save cancelled. Results are still available.';

  @override
  String get dataWorkbenchLibraryStartFailed => 'Could not start export.';

  @override
  String get dataWorkbenchBackupTitle => 'Books and backups';

  @override
  String get dataWorkbenchBackupBack => 'Back';

  @override
  String get dataWorkbenchBackupCurrentBooks => 'Back up current books';

  @override
  String get dataWorkbenchBackupIncludes =>
      'Includes current text, contents, metadata, cover, fonts, layout and rules. Undo history is excluded.';

  @override
  String get dataWorkbenchBackupIncludeSources => 'Include source files';

  @override
  String get dataWorkbenchBackupWithoutSources =>
      'Without source files you can still edit, but cannot reparse the original.';

  @override
  String get dataWorkbenchBackupSaveFile => 'Save .bookloom backup';

  @override
  String get dataWorkbenchBackupRestore => 'Restore backup';

  @override
  String get dataWorkbenchBackupMaxData => 'Maximum restored data (MiB)';

  @override
  String get dataWorkbenchBackupMaxDataHelp =>
      'Counts actual extracted data. Backup copies, temporary databases and committed files need extra space.';

  @override
  String get dataWorkbenchBackupChooseInspect => 'Choose and inspect backup';

  @override
  String get dataWorkbenchBackupConflictPolicy => 'Books with the same ID';

  @override
  String get dataWorkbenchBackupKeepBoth => 'Keep both';

  @override
  String get dataWorkbenchBackupSkipConflicts => 'Skip conflicting books';

  @override
  String get dataWorkbenchBackupOverwriteConflicts =>
      'Overwrite conflicting books';

  @override
  String get dataWorkbenchBackupCommitHelp =>
      'Commits one book at a time. Earlier successes remain if another fails. Unrelated books are preserved.';

  @override
  String get dataWorkbenchBackupConfirmRestore => 'Restore books';

  @override
  String get dataWorkbenchBackupDiscardPreview => 'Discard preview';

  @override
  String get dataWorkbenchBackupCancelAfterCommit =>
      'Finish current commit and cancel remaining books';

  @override
  String get dataWorkbenchBackupCancelTask => 'Cancel task';

  @override
  String get dataWorkbenchBackupSaved => 'Backup saved.';

  @override
  String get dataWorkbenchBackupOverwriteTitle =>
      'Overwrite conflicting books?';

  @override
  String get dataWorkbenchBackupOverwriteBody =>
      'Backup content will replace books with matching IDs. This is not a session undo action.';

  @override
  String get dataWorkbenchBackupOverwriteRestore => 'Overwrite and restore';

  @override
  String get dataWorkbenchBackupTaskCancelled => 'Task cancelled.';

  @override
  String dataWorkbenchBatchSelectedFiles(int count) {
    return '$count files selected';
  }

  @override
  String dataWorkbenchBatchSummary(int success, int failed, int total) {
    return '$success succeeded · $failed failed · $total total';
  }

  @override
  String dataWorkbenchLibrarySelected(int count) {
    return '$count selected; up to 40 per batch.';
  }

  @override
  String dataWorkbenchLibrarySummary(int success, int failed, int total) {
    return 'This queue: $success succeeded · $failed failed · $total total';
  }

  @override
  String dataWorkbenchBackupStorage(String support, String cache) {
    return 'Application data: $support; cache: $cache';
  }

  @override
  String dataWorkbenchBackupValidated(int count, String size) {
    return 'Validated $count books; data $size';
  }

  @override
  String dataWorkbenchBackupEstimatedSpace(String size) {
    return 'Estimated required space: $size';
  }

  @override
  String dataWorkbenchBackupPreviewBook(String title, int chapters, int words) {
    return '$title · $chapters chapters · $words';
  }

  @override
  String dataWorkbenchBackupRestored(int count) {
    return 'Restored $count';
  }

  @override
  String dataWorkbenchBackupSkipped(int count) {
    return 'Skipped $count';
  }

  @override
  String dataWorkbenchBackupCancelled(int count) {
    return 'Cancelled $count';
  }

  @override
  String get exportWorkbenchShareTitle => 'Share book';

  @override
  String get exportWorkbenchExportTitle => 'Export book';

  @override
  String get exportWorkbenchFormatLabel => 'Format';

  @override
  String get exportWorkbenchEpubDescription =>
      'Includes cover, contents, metadata, layout and embedded fonts. Reader pagination may differ.';

  @override
  String get exportWorkbenchDocxDescription =>
      'Editable headings and paragraphs with basic layout. Cover, illustrations and extended metadata are omitted.';

  @override
  String get exportWorkbenchHtmlDescription =>
      'One offline HTML file with contents and inline styles. Cover, images and external resources are omitted.';

  @override
  String get exportWorkbenchTextDescription =>
      'Text and chapter structure. Fonts, cover, CSS and visual layout do not apply.';

  @override
  String get exportWorkbenchDeviceHelpAction => 'Transfer to a reading device';

  @override
  String get exportWorkbenchShareAction => 'Open sharing panel';

  @override
  String get exportWorkbenchSaveAction => 'Choose save location';

  @override
  String get exportWorkbenchDeviceHelpTitle => 'Move a book to a reader';

  @override
  String get exportWorkbenchDeviceHelpIntro =>
      'Export and save a file first, then transfer it using your reader’s import method. Formats and menus vary by model and firmware; check your device guide. Open the file on the reader to check its contents and layout.';

  @override
  String get exportWorkbenchOfficialInfoAction => 'Open official information';

  @override
  String get exportWorkbenchKindleName => 'Kindle';

  @override
  String get exportWorkbenchKindleSteps =>
      'Amazon Send to Kindle accepts EPUB. After saving the file, open its web page and upload it, then look for the personal document on your Kindle. This service needs an internet connection; check the book on the device.';

  @override
  String get exportWorkbenchKoboName => 'Kobo';

  @override
  String get exportWorkbenchKoboSteps =>
      'Kobo documents USB transfer of non-DRM EPUB files: connect the reader, confirm the connection on it, copy the file to its drive, eject the drive, then check My Books.';

  @override
  String get exportWorkbenchBooxName => 'BOOX / 文石';

  @override
  String get exportWorkbenchBooxSteps =>
      'Some firmware versions include BooxDrop. If your device has it, use the address shown on the reader to transfer a file from a computer on the same Wi-Fi network. Check menus and formats for your model.';

  @override
  String get exportWorkbenchHanvonName => '汉王 / Hanvon';

  @override
  String get exportWorkbenchHanvonSteps =>
      'Check the manual for your exact model to confirm formats and its USB, transfer or local-import method. Open the file on the reader after transfer. The linked product page describes only its listed model.';

  @override
  String get exportWorkbenchIreaderName => '掌阅 / iReader';

  @override
  String get exportWorkbenchIreaderSteps =>
      'Check help for your exact device or app version to confirm formats and the local-import or transfer option. Select the exported file and check it on the bookshelf. iReader devices and app versions may differ.';

  @override
  String get dataWorkbenchBackupAnotherTaskRunning =>
      'Another task is running.';

  @override
  String get dataWorkbenchBackupInvalidBudget =>
      'Enter a restore budget from 1 to 1048576 MiB.';

  @override
  String get dataWorkbenchBackupFileTooLarge =>
      'The backup file exceeds this restore budget.';

  @override
  String get dataWorkbenchBackupActualSizeTooLarge =>
      'The backup file exceeds this budget while reading.';

  @override
  String get editorWorkbenchReparsePresetBiquge => 'Biquge-style';

  @override
  String get editorWorkbenchReparsePresetBareNumber => 'Bare-number headings';

  @override
  String get editorWorkbenchReparsePresetEnglish => 'English Chapter / Section';

  @override
  String get settingsPermissions => 'Permissions and access';

  @override
  String get permissionsIntro =>
      'Access is limited to what each action needs. This page checks app-owned folders. Access to external files and destinations is confirmed by the system when you select them.';

  @override
  String get permissionsRefresh => 'Check again';

  @override
  String get permissionsStorageTitle => 'App data and cache';

  @override
  String get permissionsStorageHelp =>
      'Your library, edits, covers and fonts live in app-owned folders. Checks create and remove a small temporary marker without reading or changing manuscripts. A system path alias or damaged file is not the same as a missing storage permission.';

  @override
  String get permissionsSupport => 'App data';

  @override
  String get permissionsBooks => 'Manuscripts and assets';

  @override
  String get permissionsCache => 'Temporary cache';

  @override
  String get permissionsReadReady => 'Read: available';

  @override
  String get permissionsReadFailed => 'Read: unavailable';

  @override
  String get permissionsWriteReady => 'Write: available';

  @override
  String get permissionsWriteFailed => 'Write: unavailable';

  @override
  String get permissionsCheckFailed =>
      'The check did not complete. Try again; access has not been confirmed.';

  @override
  String get permissionsSystemTitle => 'System permissions';

  @override
  String get permissionsNoRuntime =>
      'This installed build declares no runtime permissions. Manuscript features do not require all-files storage, photo-library, camera, microphone, contacts or location access.';

  @override
  String get permissionsDesktopSystem =>
      'On desktop, your system account and each file or folder’s access controls determine access. A single permission switch cannot make every location accessible.';

  @override
  String get permissionsSystemUnavailable =>
      'The system permission status could not be read. Try again or check the app’s system settings.';

  @override
  String get permissionsGranted => 'Allowed';

  @override
  String get permissionsNotGranted => 'Not allowed';

  @override
  String get permissionsInternetDeclared =>
      'This build declares network access.';

  @override
  String get permissionsStorageDeclared =>
      'This build declares broad storage access. Review it in system settings.';

  @override
  String get permissionsOpenSystemSettings => 'Open app system settings';

  @override
  String get permissionsSettingsFailed =>
      'Could not open app settings. Open Bookloom from your system settings.';

  @override
  String get permissionsImportTitle => 'Import files, covers and fonts';

  @override
  String get permissionsImportAndroid =>
      'Choose files in the system picker. Only selected items are read and copied into app storage. Other files are not scanned and originals are not overwritten. Cancelling grants no access. Select again if a provider’s grant expires.';

  @override
  String get permissionsImportDesktop =>
      'Only files you select in the picker are opened. Your system account must be able to read them. The read check does not import them into your library or modify originals.';

  @override
  String get permissionsReadAction => 'Choose a manuscript to check reading';

  @override
  String get permissionsReadSuccess =>
      'The selected file is readable. It was not imported or modified.';

  @override
  String get permissionsReadFailure =>
      'The selected file could not be read. Select it again or check its provider and system access controls.';

  @override
  String get permissionsCancelled =>
      'Cancelled. No new file access was granted.';

  @override
  String get permissionsExportTitle => 'Export and backup';

  @override
  String get permissionsExportAndroid =>
      'Choose a destination in the system Save as dialog. Output or backup data is written only to the destination you confirm; all-files access is not required. The check below saves a small test TXT without manuscript content. You can cancel in the system dialog.';

  @override
  String get permissionsExportDesktop =>
      'Only your chosen destination is written. The target folder must be writable. Locked files, read-only locations and low disk space can also prevent saving. The check below saves a small test TXT without manuscript content.';

  @override
  String get permissionsSaveAction => 'Choose a destination for a test file';

  @override
  String get permissionsSaveSuccess =>
      'The test file was saved to your chosen destination.';

  @override
  String get permissionsSaveFailure =>
      'The test file could not be saved. Access to that destination has not been confirmed.';

  @override
  String get permissionsShareTitle => 'Sharing and offline processing';

  @override
  String get permissionsShareAndroid =>
      'Sharing grants your chosen receiving app temporary read access to that output file only, without exposing your library folder. Opening the share sheet does not confirm delivery. Local editing and conversion work offline; external links open in your browser.';

  @override
  String get permissionsShareDesktop =>
      'Local editing and conversion work offline. You decide whether to transfer exported files with other tools. External links open in your browser and do not grant a website access to your library.';

  @override
  String get permissionsScopeNote =>
      'Results apply only to current app folders or the file and destination selected for this check. Other permissions are not requested automatically.';

  @override
  String get permissionsRuntimePolicy =>
      'Some systems list additional permissions. Current manuscript features do not need or request the runtime permissions below. They can remain off while you import and save through system pickers.';

  @override
  String get permissionsRuntimeNotRequired =>
      'Not needed by manuscript features. It is not requested and can remain off.';
}
