import 'package:app/app.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Fonts ship in assets/fonts; no requests to Google's servers (GDPR).
  GoogleFonts.config.allowRuntimeFetching = false;
  runApp(const ProviderScope(child: BoxOsApp()));
}
