import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/enums/app_theme_mode.dart';
import 'package:anx_reader/enums/code_highlight_theme.dart';
import 'package:anx_reader/models/read_theme.dart';
import 'package:anx_reader/widgets/reading_page/style_widget.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('migrates the legacy e-ink flag to the formal theme', () async {
    SharedPreferences.setMockInitialValues({
      'themeMode': 'dark',
      'eInkMode': true,
    });

    await Prefs().initPrefs();

    expect(Prefs().appThemeMode, AppThemeMode.eInk);
    expect(Prefs().effectiveThemeMode, AppThemeMode.eInk.effectiveThemeMode);
    expect(Prefs().prefs.containsKey('eInkMode'), isFalse);
  });

  test('e-ink uses temporary reader overrides without replacing preferences',
      () async {
    SharedPreferences.setMockInitialValues({
      'themeMode': 'light',
      'pageTurnStyle': PageTurn.scroll.name,
      'codeHighlightTheme': CodeHighlightThemeEnum.github.code,
      'readTheme': ReadTheme(
        backgroundColor: 'FFEEE8D5',
        textColor: 'FF123456',
        backgroundImagePath: '/paper.png',
      ).toJson(),
    });
    await Prefs().initPrefs();

    await Prefs().saveThemeModeToPrefs(AppThemeMode.eInk.code);

    expect(Prefs().effectiveReadTheme.backgroundColor, 'FFFFFFFF');
    expect(Prefs().effectiveReadTheme.textColor, 'FF000000');
    expect(Prefs().effectivePageTurnStyle, PageTurn.noAnimation);
    expect(Prefs().effectiveCodeHighlightTheme, CodeHighlightThemeEnum.off);

    await Prefs().saveThemeModeToPrefs(AppThemeMode.light.code);

    expect(Prefs().readTheme.backgroundColor, 'FFEEE8D5');
    expect(Prefs().readTheme.textColor, 'FF123456');
    expect(Prefs().pageTurnStyle, PageTurn.scroll);
    expect(Prefs().codeHighlightTheme, CodeHighlightThemeEnum.github);
  });
}
