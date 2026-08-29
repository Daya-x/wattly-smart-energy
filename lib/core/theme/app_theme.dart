import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

class AppTheme {
  static ThemeData darkTheme = ThemeData(
    scaffoldBackgroundColor: AppColors.darkNavy,
    brightness: Brightness.dark,
    primaryColor: AppColors.neonGreen,
    textTheme: GoogleFonts.interTextTheme(
      ThemeData.dark().textTheme,
    ).apply(bodyColor: AppColors.white, displayColor: AppColors.white),
    cardColor: AppColors.cardNavy,
    useMaterial3: true,
    dividerColor: AppColors.border,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.neonGreen,
      secondary: AppColors.mint,
      surface: AppColors.cardNavy,
      error: AppColors.warningRed,
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        backgroundColor: AppColors.lightCard,
        foregroundColor: AppColors.white,
      ),
    ),
  );
}
