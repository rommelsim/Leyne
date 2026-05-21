// Localization wiring for Leyne.
//
// The locale the user picks in Settings (or the device default when they
// haven't picked one) drives Flutter's built-in Material / Cupertino /
// Widgets localizations — date pickers, semantics, text direction and
// number/date formatting all follow it.
//
// `supportedLocales` is also what the Settings language picker offers.
// English is the fully-authored copy; translating Leyne's own strings into
// the other supported languages is tracked as follow-up content work.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

class AppLocalizations {
  AppLocalizations._();

  /// The four official languages of Singapore.
  static const List<Locale> supportedLocales = [
    Locale('en'), // English
    Locale('zh'), // 中文
    Locale('ms'), // Bahasa Melayu
    Locale('ta'), // தமிழ்
  ];

  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = [
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];

  /// Human-readable, self-named label for a language code — used by the
  /// Settings language picker so each option reads in its own script.
  static String labelFor(String languageCode) {
    switch (languageCode) {
      case 'zh':
        return '中文';
      case 'ms':
        return 'Bahasa Melayu';
      case 'ta':
        return 'தமிழ்';
      case 'en':
      default:
        return 'English (SG)';
    }
  }
}
