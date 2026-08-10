import 'package:flutter/material.dart';

enum AppThemeMode {
  system('auto'),
  dark('dark'),
  light('light'),
  eInk('eInk');

  const AppThemeMode(this.code);

  final String code;

  static AppThemeMode fromCode(String? code) => switch (code) {
        'dark' => dark,
        'light' => light,
        'eInk' => eInk,
        _ => system,
      };

  ThemeMode get effectiveThemeMode => switch (this) {
        AppThemeMode.dark => ThemeMode.dark,
        AppThemeMode.light || AppThemeMode.eInk => ThemeMode.light,
        AppThemeMode.system => ThemeMode.system,
      };
}
