import 'package:app/core/presentation/app_chrome.dart';
import 'package:app/core/routing/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

class BoxOsApp extends ConsumerWidget {
  const BoxOsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    const seed = appPrimary;
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.light,
      surface: appSurface,
      background: appPageBackground,
    );
    final baseTextTheme = ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
    ).textTheme;
    // Oswald is the BoxOS brand display face; apply it to the large
    // display/headline ramp and leave titles, body, and labels on the
    // default UI font for readability.
    final textTheme = baseTextTheme.copyWith(
      displayLarge: GoogleFonts.oswald(textStyle: baseTextTheme.displayLarge),
      displayMedium: GoogleFonts.oswald(textStyle: baseTextTheme.displayMedium),
      displaySmall: GoogleFonts.oswald(textStyle: baseTextTheme.displaySmall),
      headlineLarge: GoogleFonts.oswald(textStyle: baseTextTheme.headlineLarge),
      headlineMedium: GoogleFonts.oswald(
        textStyle: baseTextTheme.headlineMedium,
      ),
      headlineSmall: GoogleFonts.oswald(textStyle: baseTextTheme.headlineSmall),
    );

    return MaterialApp.router(
      title: 'BoxOS',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        textTheme: textTheme,
        scaffoldBackgroundColor: appPageBackground,
        appBarTheme: const AppBarTheme(
          backgroundColor: appSurface,
          foregroundColor: appText,
          elevation: 0,
          centerTitle: false,
        ),
        cardTheme: const CardThemeData(
          color: appSurface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(appRadiusLg)),
            side: BorderSide(color: appBorder),
          ),
        ),
        dividerColor: appBorder,
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: appSurface,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
          labelStyle: const TextStyle(color: appMutedText),
          hintStyle: const TextStyle(color: appSubtleText),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(appRadiusSm),
            borderSide: const BorderSide(color: appBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(appRadiusSm),
            borderSide: const BorderSide(color: seed, width: 1.6),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(appRadiusSm),
            borderSide: const BorderSide(color: appDanger),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(appRadiusSm),
            borderSide: const BorderSide(color: appDanger, width: 1.6),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: seed,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(appRadiusSm),
            ),
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: appText,
            side: const BorderSide(color: appBorder),
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(appRadiusSm),
            ),
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: seed,
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ),
      routerConfig: router,
    );
  }
}
