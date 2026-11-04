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
  String get appNameLatin => 'Bookloom';

  @override
  String get navLibrary => 'Library';

  @override
  String get navImport => 'Import';

  @override
  String get navSettings => 'Settings';

  @override
  String get sidebarFooter => 'Local only · offline';

  @override
  String sidebarVersion(String version) {
    return 'v$version';
  }

  @override
  String get quickToggleTheme => 'Toggle theme';

  @override
  String get quickToggleGlass => 'Toggle glass strength';

  @override
  String get libraryTitle => 'Library';

  @override
  String get libraryEmptyTitle => 'Your shelf is empty';

  @override
  String get libraryEmptyAction => 'Import a manuscript';

  @override
  String get importTitle => 'Import';

  @override
  String get importFormatsTitle => 'Planned formats';

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
  String get settingsTitle => 'Settings';

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
  String get settingsDataLocation => 'Data folder';

  @override
  String get settingsCopyPath => 'Copy path';

  @override
  String get settingsCopied => 'Path copied to clipboard';

  @override
  String get settingsAbout => 'About';

  @override
  String get settingsVersion => 'Version';

  @override
  String get settingsLicense => 'License';

  @override
  String get settingsLicenseValue => 'MIT';

  @override
  String get settingsDesignSystem => 'Design system';

  @override
  String get settingsOpen => 'Open';

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
  String get designLabelDisabled => 'Disabled';

  @override
  String get designLabelInput => 'Input';

  @override
  String get designLabelChip => 'Chips';

  @override
  String get designLabelSwitch => 'Switch';

  @override
  String get designLabelSegmented => 'Segmented';

  @override
  String get designPlaceholderInput => 'Search or type a title';

  @override
  String get errorTitle => 'Something went wrong';

  @override
  String get errorBody =>
      'The interface hit an unexpected error. Details were logged.';

  @override
  String get bootstrapFailureTitle => 'Cannot start';

  @override
  String get bootstrapFailureBody =>
      'The data folder or local database could not be opened.';

  @override
  String get bootstrapFailureRetry => 'Retry';

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
  String get settingsDesignSystemDesc =>
      'Colors, type, spacing, glass and component states';

  @override
  String get windowMinimize => 'Minimize';

  @override
  String get windowMaximize => 'Maximize';

  @override
  String get windowClose => 'Close';
}
