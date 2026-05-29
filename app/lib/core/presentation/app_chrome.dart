import 'package:flutter/material.dart';

const appPageBackground = Color(0xFFF5F9FF);
const appPageBackgroundSoft = Color(0xFFEAF2FF);
const appPageBackgroundEnd = Color(0xFFF9FBFF);
const appSurface = Colors.white;
const appSurfaceAlt = Color(0xFFF8FBFF);
const appBorder = Color(0xFFD8E4F2);
const appText = Color(0xFF0F172A);
const appMutedText = Color(0xFF475569);
const appSubtleText = Color(0xFF64748B);
const appPrimary = Color(0xFF2563EB);
const appDanger = Color(0xFFD64545);

BoxDecoration appPageDecoration() => const BoxDecoration(
  gradient: LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [appPageBackground, appPageBackgroundSoft, appPageBackgroundEnd],
  ),
);

BoxDecoration appPanelDecoration({double radius = 28}) => BoxDecoration(
  color: appSurface,
  borderRadius: BorderRadius.circular(radius),
  border: Border.all(color: appBorder),
  boxShadow: const [
    BoxShadow(color: Color(0x120F172A), blurRadius: 24, offset: Offset(0, 12)),
  ],
);

BoxDecoration appHeroDecoration({double radius = 28}) => BoxDecoration(
  color: appSurface,
  borderRadius: BorderRadius.circular(radius),
  border: Border.all(color: appBorder),
  boxShadow: const [
    BoxShadow(color: Color(0x120F172A), blurRadius: 28, offset: Offset(0, 14)),
  ],
);
