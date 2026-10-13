import 'package:app/core/presentation/app_chrome.dart';
import 'package:app/core/routing/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

class BoxOsApp extends ConsumerWidget {
  const BoxOsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    // Match the system chrome to the page background so the status bar reads
    // as part of the surface, not a separate strip.
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarBrightness: Brightness.dark,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: appPageBackground,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );

    final colorScheme = ColorScheme.fromSeed(
      seedColor: appPrimary,
      brightness: Brightness.dark,
      surface: appSurface,
      onSurface: appText,
      surfaceContainerHighest: appSurfaceAlt,
      primary: appPrimary,
      onPrimary: Colors.white,
      secondary: appPrimary,
      onSecondary: Colors.white,
      error: appDanger,
      onError: Colors.white,
      outline: appBorder,
      outlineVariant: appBorderStrong,
    );

    final baseTextTheme = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
    ).textTheme;

    // Oswald carries the brand display ramp; the rest stays on the system UI
    // font for readability. Tighter letter spacing on the body face reads
    // sharper at small sizes.
    TextStyle? tighten(TextStyle? style, {double letterSpacing = -0.2}) {
      if (style == null) return null;
      return style.copyWith(
        color: appText,
        letterSpacing: letterSpacing,
        height: style.height ?? 1.25,
      );
    }

    final textTheme = baseTextTheme
        .copyWith(
          displayLarge: GoogleFonts.chakraPetch(
            textStyle: baseTextTheme.displayLarge?.copyWith(
              color: appText,
              letterSpacing: -1.0,
              fontWeight: FontWeight.w700,
            ),
          ),
          displayMedium: GoogleFonts.chakraPetch(
            textStyle: baseTextTheme.displayMedium?.copyWith(
              color: appText,
              letterSpacing: -0.8,
              fontWeight: FontWeight.w700,
            ),
          ),
          displaySmall: GoogleFonts.chakraPetch(
            textStyle: baseTextTheme.displaySmall?.copyWith(
              color: appText,
              letterSpacing: -0.6,
              fontWeight: FontWeight.w700,
            ),
          ),
          headlineLarge: GoogleFonts.chakraPetch(
            textStyle: baseTextTheme.headlineLarge?.copyWith(
              color: appText,
              letterSpacing: -0.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          headlineMedium: GoogleFonts.chakraPetch(
            textStyle: baseTextTheme.headlineMedium?.copyWith(
              color: appText,
              letterSpacing: -0.4,
              fontWeight: FontWeight.w700,
            ),
          ),
          headlineSmall: GoogleFonts.chakraPetch(
            textStyle: baseTextTheme.headlineSmall?.copyWith(
              color: appText,
              letterSpacing: -0.3,
              fontWeight: FontWeight.w700,
            ),
          ),
          titleLarge: tighten(baseTextTheme.titleLarge, letterSpacing: -0.3)
              ?.copyWith(fontWeight: FontWeight.w700),
          titleMedium: tighten(baseTextTheme.titleMedium, letterSpacing: -0.2)
              ?.copyWith(fontWeight: FontWeight.w700),
          titleSmall: tighten(baseTextTheme.titleSmall, letterSpacing: -0.1)
              ?.copyWith(fontWeight: FontWeight.w700),
          bodyLarge: tighten(baseTextTheme.bodyLarge, letterSpacing: -0.1),
          bodyMedium: tighten(baseTextTheme.bodyMedium, letterSpacing: -0.05),
          bodySmall: baseTextTheme.bodySmall?.copyWith(color: appMutedText),
          labelLarge: baseTextTheme.labelLarge?.copyWith(
            color: appText,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.1,
          ),
          labelMedium: baseTextTheme.labelMedium?.copyWith(
            color: appMutedText,
            fontWeight: FontWeight.w600,
          ),
          labelSmall: baseTextTheme.labelSmall?.copyWith(
            color: appSubtleText,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        );

    return MaterialApp.router(
      title: 'BoxOS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: colorScheme,
        textTheme: textTheme,
        scaffoldBackgroundColor: appPageBackground,
        canvasColor: appPageBackground,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        splashFactory: InkSparkle.splashFactory,
        appBarTheme: const AppBarTheme(
          backgroundColor: appPageBackground,
          foregroundColor: appText,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          surfaceTintColor: Colors.transparent,
        ),
        cardTheme: const CardThemeData(
          color: appSurface,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(appRadiusLg)),
            side: BorderSide(color: appBorder),
          ),
        ),
        dialogTheme: const DialogThemeData(
          backgroundColor: appSurface,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(appRadiusXl)),
            side: BorderSide(color: appBorderStrong),
          ),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: appSurface,
          surfaceTintColor: Colors.transparent,
          modalBackgroundColor: appSurface,
          modalElevation: 0,
          showDragHandle: true,
          dragHandleColor: appBorderStrong,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(appRadiusXl),
            ),
          ),
        ),
        snackBarTheme: const SnackBarThemeData(
          backgroundColor: appSurfaceElevated,
          contentTextStyle: TextStyle(color: appText, fontWeight: FontWeight.w600),
          behavior: SnackBarBehavior.floating,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(appRadiusMd)),
          ),
        ),
        dividerColor: appBorder,
        dividerTheme: const DividerThemeData(
          color: appBorder,
          thickness: 1,
          space: 1,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: appSurfaceAlt,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
          labelStyle: const TextStyle(color: appMutedText),
          hintStyle: const TextStyle(color: appSubtleText),
          floatingLabelStyle: const TextStyle(color: appPrimary),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(appRadiusSm),
            borderSide: const BorderSide(color: appBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(appRadiusSm),
            borderSide: const BorderSide(color: appPrimary, width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(appRadiusSm),
            borderSide: const BorderSide(color: appDanger),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(appRadiusSm),
            borderSide: const BorderSide(color: appDanger, width: 1.5),
          ),
          disabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(appRadiusSm),
            borderSide: const BorderSide(color: appBorder),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: appPrimary,
            foregroundColor: Colors.white,
            disabledBackgroundColor: appSurfaceAlt,
            disabledForegroundColor: appSubtleText,
            minimumSize: const Size.fromHeight(52),
            shape: appButtonShape(),
            textStyle: const TextStyle(
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
              fontSize: 15,
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: appText,
            backgroundColor: appSurfaceAlt,
            side: const BorderSide(color: appBorderStrong),
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(appRadiusSm),
            ),
            textStyle: const TextStyle(
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
              fontSize: 15,
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: appPrimary,
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(
            foregroundColor: appText,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(appRadiusSm),
            ),
          ),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: appSurfaceAlt,
          selectedColor: appPrimarySoft,
          disabledColor: appSurfaceAlt,
          labelStyle: const TextStyle(
            color: appText,
            fontWeight: FontWeight.w600,
          ),
          side: const BorderSide(color: appBorder),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(appRadiusSm),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: appPrimary,
          linearTrackColor: appSurfaceAlt,
          circularTrackColor: appSurfaceAlt,
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return Colors.white;
            return appMutedText;
          }),
          trackColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return appPrimary;
            return appSurfaceAlt;
          }),
          trackOutlineColor:
              WidgetStateProperty.all(appBorderStrong),
        ),
        checkboxTheme: CheckboxThemeData(
          fillColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return appPrimary;
            return Colors.transparent;
          }),
          checkColor: WidgetStateProperty.all(Colors.white),
          side: const BorderSide(color: appBorderStrong, width: 1.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        popupMenuTheme: const PopupMenuThemeData(
          color: appSurfaceElevated,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(appRadiusMd)),
            side: BorderSide(color: appBorderStrong),
          ),
          textStyle: TextStyle(color: appText, fontWeight: FontWeight.w600),
        ),
        listTileTheme: const ListTileThemeData(
          tileColor: Colors.transparent,
          textColor: appText,
          iconColor: appMutedText,
          titleTextStyle: TextStyle(
            color: appText,
            fontWeight: FontWeight.w700,
          ),
          subtitleTextStyle: TextStyle(color: appSubtleText),
        ),
        tabBarTheme: const TabBarThemeData(
          labelColor: appText,
          unselectedLabelColor: appSubtleText,
          indicatorColor: appPrimary,
          indicatorSize: TabBarIndicatorSize.label,
          dividerColor: appBorder,
          overlayColor: WidgetStatePropertyAll(appPrimarySoft),
        ),
      ),
      routerConfig: router,
    );
  }
}
