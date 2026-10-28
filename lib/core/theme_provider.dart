import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kThemeModeKey = 'theme_mode';
const _kThemeSchemeKey = 'theme_scheme';

enum AppThemeScheme {
  alinha,
  whatsapp,
}

class ThemeSettings {
  final ThemeMode mode;
  final AppThemeScheme scheme;

  const ThemeSettings({
    this.mode = ThemeMode.system,
    this.scheme = AppThemeScheme.alinha,
  });

  ThemeSettings copyWith({ThemeMode? mode, AppThemeScheme? scheme}) {
    return ThemeSettings(
      mode: mode ?? this.mode,
      scheme: scheme ?? this.scheme,
    );
  }
}

/// Provider que carrega e persiste as preferências de tema (modo e esquema visual).
final themeSettingsProvider =
    StateNotifierProvider<ThemeSettingsNotifier, ThemeSettings>((ref) {
  return ThemeSettingsNotifier();
});

class ThemeSettingsNotifier extends StateNotifier<ThemeSettings> {
  ThemeSettingsNotifier() : super(const ThemeSettings()) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();

    // Load Mode
    final modeStr = prefs.getString(_kThemeModeKey) ?? 'system';
    ThemeMode mode;
    if (modeStr == 'dark') {
      mode = ThemeMode.dark;
    } else if (modeStr == 'light') {
      mode = ThemeMode.light;
    } else {
      mode = ThemeMode.system;
    }

    // Load Scheme
    final schemeStr = prefs.getString(_kThemeSchemeKey) ?? 'alinha';
    AppThemeScheme scheme;
    if (schemeStr == 'whatsapp') {
      scheme = AppThemeScheme.whatsapp;
    } else {
      scheme = AppThemeScheme.alinha;
    }

    state = ThemeSettings(mode: mode, scheme: scheme);
  }

  Future<void> setMode(ThemeMode newMode) async {
    state = state.copyWith(mode: newMode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemeModeKey, newMode.name);
  }

  Future<void> setScheme(AppThemeScheme newScheme) async {
    state = state.copyWith(scheme: newScheme);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemeSchemeKey, newScheme.name);
  }
}
