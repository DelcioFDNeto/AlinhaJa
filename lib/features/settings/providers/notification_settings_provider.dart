import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:alinha_ja/core/supabase_client.dart';
import 'package:alinha_ja/core/modules/module_registry.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Prefixo das chaves de SharedPreferences dos toggles por módulo
/// (ex.: `notif_mod_rh_alertas`). Também lido pelo background handler do FCM.
String moduleNotifPrefKey(String moduleId) => 'notif_mod_$moduleId';

class NotificationSettingsState {
  final bool notificationsEnabled;
  final bool notifyDm;
  final bool notifyGroups;
  final bool notifyChannels;
  final bool notifyWorkflow;
  final bool notifyCalls;
  final bool soundEnabled;
  final bool vibrationEnabled;
  final bool showPreview;
  final bool doNotDisturbEnabled;
  final TimeOfDay dndStartTime;
  final TimeOfDay dndEndTime;
  final bool isLoading;

  /// Toggle por módulo (broadcast de departamento): id do módulo -> habilitado.
  /// Persistido localmente (SharedPreferences), default `true`.
  final Map<String, bool> moduleEnabled;

  const NotificationSettingsState({
    this.notificationsEnabled = true,
    this.notifyDm = true,
    this.notifyGroups = true,
    this.notifyChannels = true,
    this.notifyWorkflow = true,
    this.notifyCalls = true,
    this.soundEnabled = true,
    this.vibrationEnabled = true,
    this.showPreview = true,
    this.doNotDisturbEnabled = false,
    this.dndStartTime = const TimeOfDay(hour: 22, minute: 0),
    this.dndEndTime = const TimeOfDay(hour: 8, minute: 0),
    this.isLoading = false,
    this.moduleEnabled = const {},
  });

  /// Retorna se as notificações do módulo estão habilitadas (default `true`).
  bool isModuleEnabled(String moduleId) => moduleEnabled[moduleId] ?? true;

  NotificationSettingsState copyWith({
    bool? notificationsEnabled,
    bool? notifyDm,
    bool? notifyGroups,
    bool? notifyChannels,
    bool? notifyWorkflow,
    bool? notifyCalls,
    bool? soundEnabled,
    bool? vibrationEnabled,
    bool? showPreview,
    bool? doNotDisturbEnabled,
    TimeOfDay? dndStartTime,
    TimeOfDay? dndEndTime,
    bool? isLoading,
    Map<String, bool>? moduleEnabled,
  }) {
    return NotificationSettingsState(
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      notifyDm: notifyDm ?? this.notifyDm,
      notifyGroups: notifyGroups ?? this.notifyGroups,
      notifyChannels: notifyChannels ?? this.notifyChannels,
      notifyWorkflow: notifyWorkflow ?? this.notifyWorkflow,
      notifyCalls: notifyCalls ?? this.notifyCalls,
      soundEnabled: soundEnabled ?? this.soundEnabled,
      vibrationEnabled: vibrationEnabled ?? this.vibrationEnabled,
      showPreview: showPreview ?? this.showPreview,
      doNotDisturbEnabled: doNotDisturbEnabled ?? this.doNotDisturbEnabled,
      dndStartTime: dndStartTime ?? this.dndStartTime,
      dndEndTime: dndEndTime ?? this.dndEndTime,
      isLoading: isLoading ?? this.isLoading,
      moduleEnabled: moduleEnabled ?? this.moduleEnabled,
    );
  }
}

class NotificationSettingsNotifier
    extends StateNotifier<NotificationSettingsState> {
  NotificationSettingsNotifier() : super(const NotificationSettingsState()) {
    loadSettings();
  }

  Future<void> loadSettings() async {
    state = state.copyWith(isLoading: true);

    // Toggles por módulo vêm do SharedPreferences (persistência local).
    final moduleEnabled = await _readModuleToggles();

    try {
      final resultList = await supabase.rpc('get_notification_settings');
      final result = (resultList as List?)?.isNotEmpty == true ? resultList![0] : null;

      if (result != null) {
        state = NotificationSettingsState(
          notificationsEnabled:
              result['notifications_enabled'] as bool? ?? true,
          notifyDm: result['notify_dm'] as bool? ?? true,
          notifyGroups: result['notify_groups'] as bool? ?? true,
          notifyChannels: result['notify_channels'] as bool? ?? true,
          notifyWorkflow: result['notify_workflow'] as bool? ?? true,
          notifyCalls: result['notify_calls'] as bool? ?? true,
          soundEnabled: result['sound_enabled'] as bool? ?? true,
          vibrationEnabled: result['vibration_enabled'] as bool? ?? true,
          showPreview: result['show_preview'] as bool? ?? true,
          doNotDisturbEnabled:
              result['do_not_disturb_enabled'] as bool? ?? false,
          dndStartTime: _parseTime(result['dnd_start_time'] as String?),
          dndEndTime: _parseTime(result['dnd_end_time'] as String?),
          isLoading: false,
          moduleEnabled: moduleEnabled,
        );
        await _syncPrefs();
      } else {
        state = state.copyWith(isLoading: false, moduleEnabled: moduleEnabled);
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, moduleEnabled: moduleEnabled);
    }
  }

  /// Lê os toggles por módulo do SharedPreferences (default `true`).
  Future<Map<String, bool>> _readModuleToggles() async {
    final map = <String, bool>{};
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final m in modulesWithNotification) {
        map[m.id] = prefs.getBool(moduleNotifPrefKey(m.id)) ?? true;
      }
    } catch (e) {
      debugPrint('Erro ao ler toggles de módulo: $e');
    }
    return map;
  }

  /// Habilita/desabilita as notificações de um módulo (persistência local).
  Future<void> toggleModule(String moduleId, bool value) async {
    final updated = Map<String, bool>.from(state.moduleEnabled)
      ..[moduleId] = value;
    state = state.copyWith(moduleEnabled: updated);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(moduleNotifPrefKey(moduleId), value);
    } catch (e) {
      debugPrint('Erro ao salvar toggle de módulo: $e');
    }
  }

  TimeOfDay _parseTime(String? timeStr) {
    if (timeStr == null) return const TimeOfDay(hour: 22, minute: 0);
    try {
      final parts = timeStr.split(':');
      return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    } catch (_) {
      return const TimeOfDay(hour: 22, minute: 0);
    }
  }

  Future<void> _syncPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('notif_enabled', state.notificationsEnabled);
      await prefs.setBool('notif_dm', state.notifyDm);
      await prefs.setBool('notif_groups', state.notifyGroups);
      await prefs.setBool('notif_channels', state.notifyChannels);
      await prefs.setBool('notif_dnd', state.doNotDisturbEnabled);
      await prefs.setString('notif_dnd_start',
          '${state.dndStartTime.hour}:${state.dndStartTime.minute}');
      await prefs.setString('notif_dnd_end',
          '${state.dndEndTime.hour}:${state.dndEndTime.minute}');
    } catch (e) {
      debugPrint('Erro ao sincronizar prefs: $e');
    }
  }

  Future<void> _saveSettings(Map<String, dynamic> params) async {
    try {
      await supabase.rpc('update_notification_settings', params: params);
      await _syncPrefs();
    } catch (e) {
      debugPrint('Erro ao salvar configurações: $e');
    }
  }

  void toggleNotifications(bool value) {
    state = state.copyWith(notificationsEnabled: value);
    _saveSettings({'p_notifications_enabled': value});
  }

  void toggleDm(bool value) {
    state = state.copyWith(notifyDm: value);
    _saveSettings({'p_notify_dm': value});
  }

  void toggleGroups(bool value) {
    state = state.copyWith(notifyGroups: value);
    _saveSettings({'p_notify_groups': value});
  }

  void toggleChannels(bool value) {
    state = state.copyWith(notifyChannels: value);
    _saveSettings({'p_notify_channels': value});
  }

  void toggleWorkflow(bool value) {
    state = state.copyWith(notifyWorkflow: value);
    _saveSettings({'p_notify_workflow': value});
  }

  void toggleCalls(bool value) {
    state = state.copyWith(notifyCalls: value);
    _saveSettings({'p_notify_calls': value});
  }

  void toggleSound(bool value) {
    state = state.copyWith(soundEnabled: value);
    _saveSettings({'p_sound_enabled': value});
  }

  void toggleVibration(bool value) {
    state = state.copyWith(vibrationEnabled: value);
    _saveSettings({'p_vibration_enabled': value});
  }

  void togglePreview(bool value) {
    state = state.copyWith(showPreview: value);
    _saveSettings({'p_show_preview': value});
  }

  void toggleDoNotDisturb(bool value) {
    state = state.copyWith(doNotDisturbEnabled: value);
    _saveSettings({'p_do_not_disturb': value});
  }

  Future<void> setDndStartTime(TimeOfDay time) async {
    state = state.copyWith(dndStartTime: time);
    final timeStr =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:00';
    await _saveSettings({'p_dnd_start': timeStr});
  }

  Future<void> setDndEndTime(TimeOfDay time) async {
    state = state.copyWith(dndEndTime: time);
    final timeStr =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:00';
    await _saveSettings({'p_dnd_end': timeStr});
  }
}

final notificationSettingsProvider = StateNotifierProvider<
    NotificationSettingsNotifier, NotificationSettingsState>(
  (ref) => NotificationSettingsNotifier(),
);
