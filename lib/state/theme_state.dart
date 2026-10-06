import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ui/theme.dart';

/// Port of `src/context/ThemeContext.tsx`, backed by SharedPreferences under
/// the same `theme-preset` / `theme-font-size` keys.
class ThemeState extends ChangeNotifier {
  static const _presetKey = 'theme-preset';
  static const _fontKey = 'theme-font-size';

  AppTheme _theme = AppTheme.light;
  AppFontSize _fontSize = AppFontSize.md;
  bool _restored = false;

  AppTheme get theme => _theme;
  AppFontSize get fontSize => _fontSize;
  bool get restored => _restored;

  ThemeData get materialTheme => AppThemeData.build(_theme, _fontSize);

  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    final rawTheme = prefs.getString(_presetKey);
    final rawFont = prefs.getString(_fontKey);
    if (rawTheme != null) {
      _theme = AppTheme.values.firstWhere(
        (t) => t.name == rawTheme,
        orElse: () => AppTheme.light,
      );
    }
    if (rawFont != null) {
      _fontSize = AppFontSize.values.firstWhere(
        (f) => f.name == rawFont,
        orElse: () => AppFontSize.md,
      );
    }
    _restored = true;
    notifyListeners();
  }

  Future<void> setTheme(AppTheme value) async {
    if (_theme == value) return;
    _theme = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_presetKey, value.name);
  }

  Future<void> setFontSize(AppFontSize value) async {
    if (_fontSize == value) return;
    _fontSize = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_fontKey, value.name);
  }

  /// Convenience for the settings quick-toggle: light ⇄ dark, keeping the
  /// rest of the palette intact.
  Future<void> toggleDark() =>
      setTheme(_theme.isDark ? AppTheme.light : AppTheme.dark);
}
