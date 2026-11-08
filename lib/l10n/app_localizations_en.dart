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
  String get aiSettingsTitle => 'AI service';

  @override
  String get aiSettingsDescription =>
      'Optional and off by default. You choose the service and start each task explicitly.';

  @override
  String get aiEnabled => 'Enable AI assistance';

  @override
  String get aiOfflineNotice =>
      'No AI requests are sent while disabled. Import, editing, rule scans and export remain available offline.';

  @override
  String get aiFormat => 'API format';

  @override
  String get aiAddress => 'API address';

  @override
  String get aiOpenAiAddressHint => 'https://api.example.com/v1';

  @override
  String get aiClaudeAddressHint => 'https://api.example.com (no /v1 needed)';

  @override
  String get aiApiKey => 'API key';

  @override
  String get aiKeyNewHint =>
      'Enter a key; it is stored only in system secure storage';

  @override
  String get aiKeyReuseHint =>
      'Leave blank to reuse the saved key; it is never filled into this form';

  @override
  String get aiKeyChangedAddressHint =>
      'The address or format changed; enter the key again';

  @override
  String get aiShowKey => 'Show key';

  @override
  String get aiHideKey => 'Hide key';

  @override
  String get aiModel => 'Model identifier';

  @override
  String get aiModelHint => 'Enter a model supported by this service';

  @override
  String get aiNormalizedAddress => 'Normalized base address';

  @override
  String get aiRequestAddress => 'Final request address';

  @override
  String get aiEndpointInvalid =>
      'Check the scheme, address, port and selected API format.';

  @override
  String get aiRemoteHttpConsent =>
      'I understand remote HTTP exposes keys and content in plaintext and still want to use this address';

  @override
  String get aiTestDisclosure =>
      'The connection test sends a fixed small sample, never manuscript content, and may incur a small charge. Confirm manuscript analysis separately in the proofreading tools.';

  @override
  String get aiProofreadingTitle => 'AI proofreading';

  @override
  String get editorAiCreateChapterRule => 'Create chapter rule with AI';

  @override
  String get editorAiCreateAdvertisementRule =>
      'Create advertisement rule with AI';

  @override
  String get aiJointRuleRequest => 'Also request rule candidates';

  @override
  String get aiJointRuleHelp =>
      'Rules use only the examples you provide. Candidates are not saved or applied automatically; check and trial them separately in the rule workbench.';

  @override
  String get aiJointRuleLimits =>
      'One example per line: 1–12 positives, 0–12 negatives; at most 2048 UTF-16 units per example and 8192 in total. All positives must appear completely within one sent chunk.';

  @override
  String get aiJointRuleAuthorization =>
      'Explicit rule candidate authorization';

  @override
  String aiJointRuleChunk(int index) {
    return 'Only chunk $index may return rules (numbered from 1).';
  }

  @override
  String get aiJointRuleNotRequested =>
      'Rule candidates were not requested. This analysis has no permission to generate rules.';

  @override
  String aiJointRuleCount(int count) {
    return 'Independent rule candidates: $count';
  }

  @override
  String get aiRuleTitle => 'Create rule from selection';

  @override
  String get aiRuleSelected => 'Selected text';

  @override
  String get aiRuleIntent => 'Rule intent';

  @override
  String get aiRuleNegative => 'Examples that must not match';

  @override
  String get aiRuleChapterTitle => 'Chapter title';

  @override
  String get aiRuleBefore => 'Text before selection';

  @override
  String get aiRuleAfter => 'Text after selection';

  @override
  String get aiRuleRelated => 'Related rule summaries sent (up to 16)';

  @override
  String get aiRuleRunning => 'Generating candidates';

  @override
  String get aiRuleCompleted => 'Candidates generated';

  @override
  String get aiRuleNoProposals =>
      'No rule candidate was generated. Adjust the intent or examples and prepare again.';

  @override
  String get aiRuleCheckAndTrial => 'Check and trial';

  @override
  String get ruleWorkbenchTitle => 'Custom rules';

  @override
  String get ruleWorkbenchNumberCaptureGroup =>
      'Number capture group (optional)';

  @override
  String get ruleWorkbenchNumberCaptureHelper =>
      'Requires a title capture group. Extracts only explicit source numbers; never auto-numbers. Empty means no mapping; 0 is the whole match, 1 onwards are groups. Clearing the title group or switching to literal/advertisement clears this number setting.';

  @override
  String get ruleWorkbenchNumberCaptureInvalid =>
      'Set a title capture group and enter a non-negative integer within the available groups.';

  @override
  String get ruleWorkbenchNumberToken => 'Source number token';

  @override
  String get ruleWorkbenchParsedNumber => 'Parsed number';

  @override
  String get ruleWorkbenchDefinition => 'Full rule definition';

  @override
  String get ruleWorkbenchId => 'Rule ID';

  @override
  String get ruleWorkbenchBookId => 'Book ID';

  @override
  String get ruleWorkbenchSource => 'Source';

  @override
  String get ruleWorkbenchInitialRejected =>
      'The rule candidate expired or conflicts with an existing rule. Select a new example.';

  @override
  String get ruleWorkbenchOffline =>
      'Trial rules across this book locally. No AI is called. Choose rules and matches before changing the manuscript.';

  @override
  String get ruleWorkbenchImportRules => 'Built-in import rules (read-only)';

  @override
  String ruleWorkbenchImportPreset(String name) {
    return 'Preset: $name';
  }

  @override
  String get ruleWorkbenchImportCustom => 'Custom';

  @override
  String get ruleWorkbenchImportAutoNote =>
      'Automatic detection uses the importer\'s built-in heuristics and advertisement rules; the workbench neither copies nor replays them.';

  @override
  String get ruleWorkbenchImportCustomNote =>
      'Custom rules were also stored for import; they are read-only here and do not take part in this trial.';

  @override
  String get ruleWorkbenchImportInvalid =>
      'The stored import rules cannot be resolved (unknown preset or invalid custom rule). Check the import settings.';

  @override
  String get ruleWorkbenchImportReadOnly =>
      'Import rules run only while importing or reparsing, never in this trial; the workbench runs only the saved rules explicitly checked above. Create a new rule to reuse a pattern in the editor.';

  @override
  String get ruleWorkbenchImportEmpty =>
      'This preset has no chapter, volume or drop patterns to show.';

  @override
  String get ruleWorkbenchImportEntryChapter =>
      'Chapter heading rule (whole line)';

  @override
  String get ruleWorkbenchImportEntryVolume =>
      'Volume heading rule (whole line)';

  @override
  String get ruleWorkbenchImportEntryDrop => 'Whole-line drop rule';

  @override
  String get ruleWorkbenchImportEntryInlineJunk =>
      'Inline promotion cleanup rule';

  @override
  String get ruleWorkbenchRules => 'Rules for this trial';

  @override
  String get ruleWorkbenchEmpty => 'No rules yet. Create a rule for this book.';

  @override
  String get ruleWorkbenchBookScope => 'This book';

  @override
  String get ruleWorkbenchGlobalScope => 'Across books';

  @override
  String get ruleWorkbenchEnabled => 'Enabled';

  @override
  String get ruleWorkbenchDisabled => 'Disabled';

  @override
  String get ruleWorkbenchUnsaved => 'Unsaved';

  @override
  String get ruleWorkbenchCurrent => 'Current rule';

  @override
  String get ruleWorkbenchBuiltIn => 'Built-in';

  @override
  String get ruleWorkbenchUser => 'User';

  @override
  String get ruleWorkbenchAiSource => 'AI source';

  @override
  String get ruleWorkbenchActions => 'Rule actions';

  @override
  String get ruleWorkbenchEdit => 'Edit';

  @override
  String get ruleWorkbenchEnable => 'Enable rule';

  @override
  String get ruleWorkbenchDisable => 'Disable rule';

  @override
  String get ruleWorkbenchDelete => 'Delete rule';

  @override
  String get ruleWorkbenchDeleteTitle => 'Delete this rule?';

  @override
  String get ruleWorkbenchNew => 'New rule';

  @override
  String get ruleWorkbenchScan => 'Trial whole book';

  @override
  String get ruleWorkbenchIdentify => 'What to identify';

  @override
  String get ruleWorkbenchExclude => 'What to exclude';

  @override
  String get ruleWorkbenchExcludePattern =>
      'Exclude matches containing (optional)';

  @override
  String get ruleWorkbenchExcludePatternHelper =>
      'Skip a match when the line containing it also contains this text; case sensitivity follows the switch above.';

  @override
  String get ruleWorkbenchExcludePatternInvalid =>
      'The exclude text cannot span lines and must stay within 256 UTF-16 code units.';

  @override
  String get ruleWorkbenchWholeLine => 'Whole-line matches only';

  @override
  String get ruleWorkbenchNoGlobalRules => 'There are no rules to export.';

  @override
  String get ruleWorkbenchRulesNoSharedInFile =>
      'The file contains no usable rules.';

  @override
  String get ruleWorkbenchExportSharedRules => 'Export rule file';

  @override
  String get ruleWorkbenchImportSharedRules => 'Import rule file';

  @override
  String ruleWorkbenchRulesExported(int count) {
    return 'Exported $count rules.';
  }

  @override
  String get ruleWorkbenchRulesImportTitle => 'Import rule file';

  @override
  String ruleWorkbenchRulesImportBody(int global, int book, int existing) {
    return 'The file contains $global shared rules and $book book-scoped rules (copied to the open book); $existing same-ID rules already exist and will be skipped. Only missing definitions are added; nothing is overwritten, enabled, or run.';
  }

  @override
  String ruleWorkbenchRulesImported(int added, int skipped) {
    return 'Imported: $added added, $skipped already present.';
  }

  @override
  String get ruleWorkbenchRulesImportInvalid =>
      'The rule file is invalid or has an unsupported version.';

  @override
  String get ruleWorkbenchWholeLineHelper =>
      'After trimming leading and trailing whitespace, a match must cover the whole line. Only available for heading and body lines.';

  @override
  String get ruleWorkbenchEffect => 'What will change';

  @override
  String get ruleWorkbenchName => 'Rule name';

  @override
  String get ruleWorkbenchKind => 'Rule type';

  @override
  String get ruleWorkbenchChapter => 'Chapter heading';

  @override
  String get ruleWorkbenchHeadingLevel => 'Heading level';

  @override
  String get ruleWorkbenchVolumeLevel => 'Volume';

  @override
  String get ruleWorkbenchChapterLevel => 'Chapter';

  @override
  String get ruleWorkbenchVolumeCandidate => 'Volume heading';

  @override
  String get ruleWorkbenchVolumeEffect =>
      'Remove the full heading line and its line ending to create a top-level volume. Preserve content after the boundary as untitled front matter and move consecutive sibling chapters into the new volume. Do not create an empty chapter when there is no content.';

  @override
  String get ruleWorkbenchNewVolumeTitle => 'New volume title';

  @override
  String get ruleWorkbenchVolumeFrontMatter =>
      'Volume front matter (no invented chapter title)';

  @override
  String get ruleWorkbenchVolumePreview =>
      'Single volume boundary preview. The new volume is a top-level entry with no body. Content before the boundary stays in the source chapter. Following text, images, footnotes and dividers become untitled front matter in their original order; no empty chapter is created when there is no content. Consecutive chapters with the source chapter\'s parent move into the new volume, stopping at a volume or a different parent. Batch application assigns content at each volume boundary and can be undone once.';

  @override
  String get ruleWorkbenchVolumeFollowingBlockCount =>
      'Following blocks preserved as front matter';

  @override
  String get ruleWorkbenchVolumeFollowingBlocks =>
      'Expand all following front matter blocks';

  @override
  String get ruleWorkbenchVolumeFollowingChapterCount =>
      'Following chapters moved by this single change';

  @override
  String get ruleWorkbenchVolumeFollowingChapters =>
      'Expand the list of chapters moving into the new volume';

  @override
  String get ruleWorkbenchMoreChapters => 'Load more chapters';

  @override
  String get ruleWorkbenchAdvertisement => 'Advertisement';

  @override
  String get ruleWorkbenchTarget => 'Match target';

  @override
  String get ruleWorkbenchHeadingLine => 'Match target: heading line';

  @override
  String get ruleWorkbenchBodyLine => 'Body line';

  @override
  String get ruleWorkbenchParagraph => 'Paragraph';

  @override
  String get ruleWorkbenchMode => 'Match mode';

  @override
  String get ruleWorkbenchLiteral => 'Literal text';

  @override
  String get ruleWorkbenchSafeRegex => 'Restricted regex (advanced)';

  @override
  String get ruleWorkbenchPattern => 'Text or expression to match';

  @override
  String get ruleWorkbenchAdvanced => 'Advanced options';

  @override
  String get ruleWorkbenchTitleCaptureGroup =>
      'Table of contents title from capture group';

  @override
  String get ruleWorkbenchTitleCaptureHelper =>
      'Blank = full heading line; 0 = whole match; 1 onward = capture group.';

  @override
  String get ruleWorkbenchAvailableGroups => 'Available numbers';

  @override
  String get ruleWorkbenchTitleCaptureInvalid =>
      'Enter a non-negative integer in the available range.';

  @override
  String get ruleWorkbenchFullHeadingLine => 'Full heading line';

  @override
  String get ruleWorkbenchCaseSensitive => 'Case sensitive';

  @override
  String get ruleWorkbenchPositive => 'Positive examples (at least one line)';

  @override
  String get ruleWorkbenchNegative => 'Negative examples (optional lines)';

  @override
  String get ruleWorkbenchOnePerLine => 'One single-line example per row';

  @override
  String get ruleWorkbenchAction => 'Action';

  @override
  String get ruleWorkbenchCandidate => 'Mark ad candidate (no deletion)';

  @override
  String get ruleWorkbenchExactDeletion => 'Delete exact matched text';

  @override
  String get ruleWorkbenchChapterEffect =>
      'Remove the full heading line and its line ending from the body. The new table of contents title defaults to that line or can come from a capture group.';

  @override
  String get ruleWorkbenchScope => 'Scope';

  @override
  String get ruleWorkbenchPriority => 'Priority (-1000 to 1000)';

  @override
  String get ruleWorkbenchPriorityInvalid => 'Priority must be an integer.';

  @override
  String get ruleWorkbenchOpenBook => 'Open a manuscript first.';

  @override
  String get ruleWorkbenchUseDefinition => 'Add to rule set';

  @override
  String get ruleWorkbenchGlobalConfirmTitle => 'Use across books?';

  @override
  String get ruleWorkbenchGlobalConfirmBody =>
      'The rule will appear for other books, but will never be selected for a trial or edit their text automatically.';

  @override
  String get ruleWorkbenchConfirm => 'Confirm';

  @override
  String get ruleWorkbenchLoading => 'Loading rules';

  @override
  String get ruleWorkbenchScanning => 'Trialing whole book';

  @override
  String get ruleWorkbenchReady => 'Trial complete';

  @override
  String get ruleWorkbenchSaving => 'Saving rule';

  @override
  String get ruleWorkbenchSaved =>
      'Rule saved. The trial has expired; run a new trial before applying.';

  @override
  String get ruleWorkbenchDeleted => 'Rule deleted.';

  @override
  String get ruleWorkbenchResults => 'Whole-book trial results';

  @override
  String get ruleWorkbenchCoverage => 'Covered';

  @override
  String get ruleWorkbenchChapters => 'chapter/volume nodes';

  @override
  String get ruleWorkbenchBlocks => 'text blocks';

  @override
  String get ruleWorkbenchLines => 'body lines';

  @override
  String get ruleWorkbenchTotalMatches => 'Total hits';

  @override
  String get ruleWorkbenchDistinctMatches => 'Distinct hits';

  @override
  String get ruleWorkbenchConflicts => 'Total conflicts';

  @override
  String get ruleWorkbenchConflictSamples => 'Conflict samples';

  @override
  String get ruleWorkbenchTruncated => 'Not shown';

  @override
  String get ruleWorkbenchShown => 'Hits shown';

  @override
  String get ruleWorkbenchExecuted => 'Executed, hits';

  @override
  String get ruleWorkbenchNotExecuted => 'Not executed (disabled)';

  @override
  String get ruleWorkbenchConflictDetails => 'View conflict samples';

  @override
  String get ruleWorkbenchChapterConflict =>
      'Multiple split boundaries on one line';

  @override
  String get ruleWorkbenchDeleteChapterConflict =>
      'Deletion conflicts with chapter split';

  @override
  String get ruleWorkbenchDeletionConflict => 'Overlapping deletions';

  @override
  String get ruleWorkbenchMaxApply => 'Apply at most 100 changes per batch.';

  @override
  String get ruleWorkbenchSaveOnly => 'Save current rule only';

  @override
  String get ruleWorkbenchApplySelected => 'Apply selected (one undo)';

  @override
  String get ruleWorkbenchSaveApply =>
      'Save and apply selected hits of this rule';

  @override
  String get ruleWorkbenchCandidateNotice =>
      'Ad candidates are for review and cannot be selected for deletion.';

  @override
  String get aiAdvertisementAnalyze => 'Analyze advertisement with AI';

  @override
  String aiAdvertisementSource(String name) {
    return 'From rule candidate: $name';
  }

  @override
  String get aiAdvertisementSelectedText =>
      'Exact selection (only this range can be edited)';

  @override
  String get aiAdvertisementReadOnlyContext =>
      'Read-only adjacent text included in the request';

  @override
  String get aiAdvertisementSelectionScope =>
      'Select up to 8192 UTF-16 code units. Only the selection and read-only adjacent context are analyzed. Changing chapter scope cancels this selection request.';

  @override
  String get aiAdvertisementSelectionLimit =>
      'The selection exceeds 8192 UTF-16 code units. Select less text to analyze it.';

  @override
  String get aiAdvertisementSelectionExpired =>
      'This advertisement selection has expired. Select the text again to analyze it.';

  @override
  String get ruleWorkbenchMore => 'Load more hits';

  @override
  String get ruleWorkbenchReload => 'Reload saved rules';

  @override
  String get ruleWorkbenchReloadTitle => 'Reload rules?';

  @override
  String get ruleWorkbenchReloadWarning =>
      'Unsaved rule definitions, form contents and trial results will be discarded.';

  @override
  String get ruleWorkbenchLine => 'line';

  @override
  String get ruleWorkbenchRule => 'Matched rules';

  @override
  String get ruleWorkbenchOffset => 'Range';

  @override
  String get ruleWorkbenchSplitPrefix =>
      'Boundary block kept in source chapter';

  @override
  String get ruleWorkbenchRemoveHeadingLine => 'Full heading line to remove';

  @override
  String get ruleWorkbenchSplitTitle => 'New table of contents title';

  @override
  String get ruleWorkbenchUnsupportedCrLine =>
      'A heading line ending in a lone CR cannot be split yet. Adjust the line ending and run the trial again.';

  @override
  String get ruleWorkbenchSplitSuffix => 'Boundary block text in new chapter';

  @override
  String get ruleWorkbenchFollowingCount =>
      'Following blocks moved to new chapter in order';

  @override
  String get ruleWorkbenchFollowingBlocks =>
      'Expand all following chapter content';

  @override
  String get ruleWorkbenchTextBlock => 'Text block';

  @override
  String get ruleWorkbenchImageBlock => 'Image block';

  @override
  String get ruleWorkbenchFootnoteBlock => 'Footnote block';

  @override
  String get ruleWorkbenchDividerBlock => 'Divider block';

  @override
  String get ruleWorkbenchAssetId => 'Asset ID';

  @override
  String get ruleWorkbenchDeleteExact => 'Remove exactly';

  @override
  String get ruleWorkbenchAfter => 'Complete block after deletion';

  @override
  String get aiProofreadingIntro =>
      'Choose a purpose and chapters. Preparing a review sends no manuscript text.';

  @override
  String get aiAuditGapSource => 'From manuscript check: chapter numbering gap';

  @override
  String aiAuditGapRange(int first, int last) {
    return 'Missing numbers: $first–$last';
  }

  @override
  String aiAuditGapBefore(String title) {
    return 'Before: $title';
  }

  @override
  String aiAuditGapAfter(String title) {
    return 'After: $title';
  }

  @override
  String get aiAuditGapNoBefore =>
      'No preceding chapter in this volume; analyze the first numbered chapter.';

  @override
  String get aiAuditGapNoAutoSend =>
      'Opening this analysis sends nothing. Review the request and confirm before sending.';

  @override
  String get aiAuditGapExpired =>
      'This check result has expired. Run the manuscript check again to analyze this gap.';

  @override
  String get aiProofreadingAdvertisement => 'Advertisement review';

  @override
  String get aiProofreadingMissingChapter => 'Missing chapter diagnosis';

  @override
  String get aiProofreadingChapters => 'Chapters to analyze';

  @override
  String get aiProofreadingScope =>
      'Choose the current chapter or several chapters; all selected text is chunked for analysis.';

  @override
  String get aiProofreadingMissingScope =>
      'The adjacent pair is selected by default. You can change the pair. Selected chapters are covered in full, without fixed trimming.';

  @override
  String get aiProofreadingCurrentChapter => 'Current chapter';

  @override
  String get aiProofreadingSelectedChapters => 'Selected chapters';

  @override
  String get aiProofreadingPrepare => 'Prepare and review request';

  @override
  String get aiProofreadingPhase => 'Task status';

  @override
  String get aiProofreadingIdle => 'Ready';

  @override
  String get aiProofreadingPreparing => 'Preparing';

  @override
  String get aiProofreadingAwaitingConsent => 'Awaiting send confirmation';

  @override
  String get aiProofreadingRunning => 'Analyzing';

  @override
  String get aiProofreadingCompleted => 'Analysis complete';

  @override
  String get aiProofreadingApplying => 'Applying';

  @override
  String get aiProofreadingApplied => 'Applied';

  @override
  String get aiProofreadingCancelled => 'Cancelled';

  @override
  String get aiProofreadingStale => 'Manuscript changed; results expired';

  @override
  String get aiProofreadingFailed => 'Failed';

  @override
  String get aiProofreadingCompletedChunks => 'Completed chunks';

  @override
  String get aiProofreadingReview => 'Review before sending';

  @override
  String get aiProofreadingCharacters => 'Source characters';

  @override
  String get aiProofreadingBlocks => 'Paragraphs';

  @override
  String get aiProofreadingChunks => 'Request chunks';

  @override
  String get aiProofreadingSystemPrompt => 'Full system prompt';

  @override
  String get aiProofreadingChunk => 'Full request content, chunk';

  @override
  String get aiProofreadingCompleteScope =>
      'Each chunk shows its complete userContext JSON. The system prompt above is also sent with each request.';

  @override
  String get aiProofreadingStart => 'Confirm and start sending';

  @override
  String get aiProofreadingCancelCost =>
      'Cancellation stops later processing. Requests already sent and any charges cannot be undone.';

  @override
  String get aiProofreadingAppliedCount => 'Applied changes';

  @override
  String get aiProofreadingNoFindings =>
      'No confirmed issue or edit was found. This does not prove that the source has no missing chapter.';

  @override
  String get aiProofreadingApplicableChanges => 'Applicable changes';

  @override
  String get aiProofreadingPending => 'Findings to review';

  @override
  String aiProofreadingIgnoredCount(int count) {
    return '$count ignored (this run only)';
  }

  @override
  String get aiProofreadingRestoreIgnored =>
      'Restore all ignored from this run';

  @override
  String get aiProofreadingIgnoreFinding =>
      'Ignore finding and related suggestions';

  @override
  String get aiProofreadingRulesUnavailable =>
      'Rule proposals are not enabled yet.';

  @override
  String get aiProofreadingConflict =>
      'Selected changes conflict. Deselect one of them.';

  @override
  String get aiProofreadingApplySelected => 'Apply selected changes';

  @override
  String get aiProofreadingOriginal => 'Full original text';

  @override
  String get aiProofreadingOriginalEvidence => 'Full source evidence';

  @override
  String get aiProofreadingOriginalChapterTitle =>
      'Current table-of-contents title';

  @override
  String get aiProofreadingNewChapterTitle => 'New table-of-contents title';

  @override
  String get aiProofreadingReplacement => 'Replacement';

  @override
  String get aiProofreadingDelete =>
      'Delete the text shown above (keep the text block)';

  @override
  String get aiProofreadingRemoveBlock => 'Remove entire text block';

  @override
  String get aiProofreadingRemoveBlockImpact =>
      'This text block is removed without leaving an empty paragraph. The chapter and other text blocks, images, footnotes, and dividers remain.';

  @override
  String get aiProofreadingReplace => 'Replace text';

  @override
  String get aiProofreadingRenameChapter => 'Correct chapter title';

  @override
  String get aiProofreadingRenameChapterImpact =>
      'Only this chapter\'s table-of-contents title changes. Its heading line stays in the body; all other text, images, footnotes, dividers, and the chapter hierarchy remain unchanged.';

  @override
  String get aiProofreadingSplit => 'Split and restore chapter';

  @override
  String get aiProofreadingSplitSource =>
      'Boundary paragraph remaining in the source chapter';

  @override
  String get aiProofreadingSplitNew => 'New chapter and its body';

  @override
  String get aiProofreadingSplitRemoveTitle =>
      'Remove the whole heading line, including its line ending, from the body and use it as the new chapter title.';

  @override
  String get aiProofreadingSplitKeepTitle =>
      'Keep the heading line in the body as well; no source text is deleted.';

  @override
  String get aiProofreadingSplitResources =>
      'Single-split impact preview. Preceding blocks and body text before the boundary remain in the source chapter; body text and blocks after it move to the new chapter in their original order. Later existing chapters stay unchanged. Batch splits remain subject to conflict and application checks.';

  @override
  String get aiProofreadingSplitParent =>
      'Parent volume (same for both chapters)';

  @override
  String get aiProofreadingSplitTopLevel =>
      'Top-level chapters (neither belongs to a volume)';

  @override
  String aiProofreadingSplitBeforeCount(int count) {
    return 'Preceding blocks retained in source chapter: $count';
  }

  @override
  String aiProofreadingSplitAfterCount(int count) {
    return 'Following blocks moved to new chapter: $count';
  }

  @override
  String get aiProofreadingSplitMore => 'Show up to 100 more blocks';

  @override
  String get aiProofreadingSplitCaption => 'Caption';

  @override
  String get aiProofreadingSplitAlt => 'Alternative text';

  @override
  String get aiProofreadingSplitMarker => 'Footnote marker';

  @override
  String get aiProofreadingReason => 'Reason';

  @override
  String get aiProofreadingLocate => 'Locate source';

  @override
  String get aiProofreadingApplyOne => 'Apply this change';

  @override
  String get aiProofreadingUndetermined => 'Undetermined';

  @override
  String get aiProofreadingSuspectedMissing =>
      'Possible missing source content';

  @override
  String get aiProofreadingMissedHeading => 'Possible missed heading';

  @override
  String get aiProofreadingMergedContent => 'Possible merged chapters';

  @override
  String get aiProofreadingNumberingSuspect => 'Possible numbering error';

  @override
  String get aiProofreadingAuthorNote => 'Author\'s note';

  @override
  String get aiProofreadingStoryQuote => 'Quotation in story';

  @override
  String get aiProofreadingNotAdvertisement => 'Not an advertisement';

  @override
  String get aiProofreadingObserved => 'Finding';

  @override
  String get aiTestConnection => 'Test connection';

  @override
  String get aiTesting => 'Testing connection…';

  @override
  String get aiCancelTest => 'Cancel test';

  @override
  String get aiTestPassed =>
      'The test passed. You can save this configuration. Changes to format, address, key or model require a new test.';

  @override
  String get aiNotTested => 'This configuration has not been tested.';

  @override
  String get aiSaved => 'The current AI configuration was saved.';

  @override
  String get aiSave => 'Save configuration';

  @override
  String get aiClear => 'Clear AI configuration and key';

  @override
  String get aiClearTitle => 'Clear AI configuration?';

  @override
  String get aiClearDescription =>
      'Disable AI and delete the key linked to the current configuration. Manuscripts are unchanged.';

  @override
  String get aiClearConfirm => 'Clear';

  @override
  String get aiCleared =>
      'AI is disabled. The current configuration and linked key were cleared.';

  @override
  String get aiCleanupWarning =>
      'The current configuration was safely committed, but the old key still needs cleanup. Retry without affecting manuscripts.';

  @override
  String get aiRetryCleanup => 'Retry old-key cleanup';

  @override
  String get aiCleanupDone => 'The old key was removed.';

  @override
  String get aiLoadFailed =>
      'Could not load AI settings. Try again; networking will not be enabled as a fallback.';

  @override
  String get aiReload => 'Reload configuration';

  @override
  String get aiBusy =>
      'The previous operation has not finished. Try again shortly.';

  @override
  String get aiInvalidConfiguration =>
      'Check the address, model and key. Test the current configuration before enabling it.';

  @override
  String get aiMissingCredential =>
      'Enter a key. Changing the address or format cannot automatically reuse the old key.';

  @override
  String get aiCredentialUnavailable =>
      'System secure storage is unavailable. Check that the keyring is unlocked and retry; keys will not be stored in plaintext.';

  @override
  String get aiStaleConfiguration =>
      'Another operation changed this configuration. Reload before saving.';

  @override
  String get aiProofRequired =>
      'This configuration has not passed a connection test, or changed after testing. Test it again.';

  @override
  String get aiConnectionFailed =>
      'The service did not return the expected test result. Check the model and API format.';

  @override
  String get aiCancelled =>
      'The test was cancelled. Server-side processing or charges already incurred cannot be undone.';

  @override
  String get aiSaveFailed =>
      'Could not save. The previous configuration is retained; try again.';

  @override
  String get aiCommitUnknown =>
      'The save status could not be confirmed. Reload before continuing.';

  @override
  String get aiCleanupFailed =>
      'The old key could not be removed. Retry later; a key still in use will not be deleted.';

  @override
  String get aiAuthenticationFailed =>
      'Authentication failed. Check the key and its permissions.';

  @override
  String get aiRateLimited =>
      'The service is rate limiting requests. Retry manually later; no automatic retry will be sent.';

  @override
  String get aiTimedOut =>
      'The test timed out. Check the service address and retry.';

  @override
  String get aiRedirectRejected =>
      'The service redirected the request. Key forwarding was blocked; enter the final address.';

  @override
  String get aiBudgetExceeded =>
      'The request or response exceeded its safety budget. Check the service endpoint.';

  @override
  String get aiProtocolFailed =>
      'The response does not match the selected protocol, was refused or was truncated. Check the model and format.';

  @override
  String get aiNetworkFailed =>
      'Could not connect. Check the network, address and certificate.';

  @override
  String get settingsThemeMode => 'Theme';

  @override
  String get themeSystem => 'System';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get settingsData => 'Data';

  @override
  String get settingsPreferences => 'Preferences';

  @override
  String get settingsMaintenance => 'Data & maintenance';

  @override
  String get settingsHelp => 'Help';

  @override
  String get settingsAppearanceDesc => 'App theme and colors.';

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
  String editorTotalWords(int count) {
    return '$count words in book';
  }

  @override
  String editorTotalWordsWan(String count) {
    return 'Book total $count 万字';
  }

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
  String get importTaskTitle => 'Import manuscript';

  @override
  String get importPreparing => 'Preparing';

  @override
  String get importCancelling => 'Cancelling…';

  @override
  String importProgressPercent(int percent) {
    return '$percent%';
  }

  @override
  String get importSaving => 'Saving manuscript…';

  @override
  String get importSavingNotice => 'Saving in progress. Do not exit.';

  @override
  String get importStagePrepare => 'Preparing…';

  @override
  String get importStageDecode => 'Detecting encoding…';

  @override
  String get importStageParse => 'Organizing chapters…';

  @override
  String get importStageConvert => 'Converting text…';

  @override
  String get importStageReady => 'Parsing complete';

  @override
  String get importStageSavePrepare => 'Preparing to save…';

  @override
  String get importStageSaveChapters => 'Saving chapters…';

  @override
  String get importStageSaveBlocks => 'Saving text…';

  @override
  String get importStageSaveFinalize => 'Finishing save…';

  @override
  String get importPickFailed =>
      'Could not choose a file. Check permissions and retry.';

  @override
  String get importDropHint => 'Drop a file here or click to choose.';

  @override
  String get importDropUnsupported =>
      'Only TXT, EPUB and DOCX files are supported.';

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
  String get editorNewChapterBefore => 'New chapter before';

  @override
  String get editorNewChapterAfter => 'New chapter after';

  @override
  String get editorNewVolumeBefore => 'New volume before';

  @override
  String get editorNewVolumeAfter => 'New volume after';

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
  String get editorWorkbenchAnalyzeGapWithAi => 'Analyze with AI';

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
  String get editorWorkbenchIssueTitleFormat => 'Inconsistent title format';

  @override
  String get editorWorkbenchIssueDuplicateContent => 'Duplicate content';

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
  String get bookWorkbenchLayoutSampleTitle => 'Live layout sample';

  @override
  String get bookWorkbenchLayoutSampleScope =>
      'This sample, reading preview, and visually formatted exports use these settings. The body editor keeps the original text and does not display first-line indents.';

  @override
  String get bookWorkbenchLayoutSampleFirst =>
      'After the rain, lamplight crossed the wet stones.';

  @override
  String get bookWorkbenchLayoutSampleSecond => 'A new page begins.';

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
  String dataWorkbenchBackupSavedWithRules(int count) {
    return 'Backup saved with $count book-scoped rules.';
  }

  @override
  String dataWorkbenchBackupRules(int count) {
    return 'This backup contains $count book-scoped rules. Restore only adds missing definitions; existing rules are never overwritten, enabled, or run.';
  }

  @override
  String dataWorkbenchBackupRulesMerged(int added, int skipped) {
    return 'Rules restored: $added added, $skipped already present.';
  }

  @override
  String dataWorkbenchBackupRulesFailed(String message) {
    return 'Books were restored, but rules were not: $message';
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
      'Network access supports optional AI, which is off by default. Explicit connection tests send a fixed small sample, not your manuscript.';

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

  @override
  String get ruleWorkbenchRulesCopyConflicts =>
      'If an ID already exists, save it as a new rule (otherwise skip)';

  @override
  String get ruleWorkbenchDuplicate => 'Duplicate rule';

  @override
  String get ruleWorkbenchCopySuffix => ' (copy)';

  @override
  String ruleWorkbenchDuplicated(String name) {
    return 'Created “$name”.';
  }

  @override
  String get ruleWorkbenchSearch => 'Search rules';

  @override
  String get ruleWorkbenchNoMatches => 'No matching rules.';

  @override
  String get ruleWorkbenchClearSearch => 'Clear search';

  @override
  String get ruleWorkbenchExportSelectTitle => 'Select rules to export';

  @override
  String get ruleWorkbenchSelectAll => 'Select all';

  @override
  String ruleWorkbenchExportSelected(int count) {
    return 'Export selected ($count)';
  }

  @override
  String get ruleWorkbenchImportPreview => 'Rules to import';

  @override
  String get ruleWorkbenchImportWillSkip => 'already exists, will be skipped';
}
