/// App Spacing (mirroring iOS AppSpacing.swift)
class AppSpacing {
  // MARK: - Padding values
  static const double xxSmall = 2;
  static const double xSmall = 4;
  static const double small = 6;
  static const double smallMedium = 8;
  static const double medium = 10;
  static const double mediumLarge = 12;
  static const double regular = 14;
  static const double large = 16;
  static const double xLarge = 20;
  static const double xxLarge = 30;
  static const double xxxLarge = 40;

  // MARK: - Specific padding values
  static const double padding4 = 4;
  static const double padding6 = 6;
  static const double padding8 = 8;
  static const double padding9 = 9;
  static const double padding10 = 10;
  static const double padding12 = 12;
  static const double padding14 = 14;
  static const double padding15 = 15;
  static const double padding16 = 16;
  static const double padding20 = 20;
  static const double padding24 = 24;
  static const double padding30 = 30;
  static const double padding32 = 32;
  static const double padding40 = 40;
  static const double padding60 = 60;
  static const double padding100 = 100;

  // MARK: - Icon sizes
  static const double iconSmall = 8;
  static const double iconRegular = 18;
  static const double iconMedium = 28;
  static const double iconLarge = 48;
  static const double iconXLarge = 60;
  static const double iconXXLarge = 72;
  static const double iconHuge = 80;

  // MARK: - Button sizes
  static const double buttonHeightSmall = 28;
  static const double buttonHeightRegular = 44;
  static const double buttonHeightLarge = 72;

  // MARK: - Corner radius
  static const double cornerRadiusSmall = 4;
  static const double cornerRadiusMedium = 6;
  static const double cornerRadiusRegular = 8;
  static const double cornerRadiusLarge = 10;
  static const double cornerRadiusXLarge = 12;
  static const double cornerRadiusXXLarge = 14;
  static const double cornerRadiusCard = 16;
  static const double cornerRadiusBubble = 18;
  static const double cornerRadiusModal = 20;

  // MARK: - Frame sizes
  static const double minFrameHeight = 150;
  static const double maxFrameHeight = 150;

  // MARK: - Stroke widths
  static const double strokeThin = 0.5;
  static const double strokeRegular = 1.0;
  static const double strokeMedium = 2.0;

  // MARK: - Shadow radius
  static const double shadowSmall = 2;
  static const double shadowMedium = 3;
  static const double shadowLarge = 4;
  static const double shadowXLarge = 10;
}

/// Layout Constants (mirroring iOS AppLayout)
class AppLayout {
  // MARK: - macOS specific (for desktop Flutter)
  static const double macOSMinWidth = 400;
  static const double macOSIdealWidth = 600;
  static const double macOSMaxWidth = 900;
  static const double macOSMinHeight = 300;
  static const double macOSIdealHeight = 500;
  static const double macOSMaxHeight = 800;

  // MARK: - Content width limits
  static const double maxContentWidth = 800;
  static const double maxContentWidthLarge = 1000;
  static const double maxContentWidthXLarge = 1200;

  // MARK: - Sheet sizes
  static const double sheetMinWidth = 500;
  static const double sheetIdealWidth = 600;
  static const double sheetMaxWidth = 700;
  static const double sheetMinHeight = 400;
  static const double sheetIdealHeight = 500;
  static const double sheetMaxHeight = 600;

  // MARK: - Animation durations
  static const Duration animationFast = Duration(milliseconds: 250);
  static const Duration animationRegular = Duration(milliseconds: 300);
  static const Duration animationSlow = Duration(milliseconds: 500);
  static const Duration animationVerySlow = Duration(milliseconds: 600);
  static const Duration animationLoop = Duration(seconds: 1);
  static const Duration animationLoopSlow = Duration(seconds: 2);
}
