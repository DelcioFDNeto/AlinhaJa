import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:alinha_ja/features/hr/models/smtp_config.dart';
import 'package:alinha_ja/features/hr/models/email_template.dart';
import 'package:alinha_ja/features/hr/models/automation_rule.dart';

class AutomationsState {
  final SmtpConfig? smtpConfig;
  final List<EmailTemplate> templates;
  final List<AutomationRule> rules;
  final bool isLoading;

  AutomationsState({
    this.smtpConfig,
    this.templates = const [],
    this.rules = const [],
    this.isLoading = false,
  });

  AutomationsState copyWith({
    SmtpConfig? smtpConfig,
    List<EmailTemplate>? templates,
    List<AutomationRule>? rules,
    bool? isLoading,
  }) {
    return AutomationsState(
      smtpConfig: smtpConfig ?? this.smtpConfig,
      templates: templates ?? this.templates,
      rules: rules ?? this.rules,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class AutomationsNotifier extends StateNotifier<AutomationsState> {
  AutomationsNotifier() : super(AutomationsState());

  final _supabase = Supabase.instance.client;

  Future<void> fetchAll() async {
    state = state.copyWith(isLoading: true);
    try {
      await Future.wait([
        fetchSmtpConfig(),
        fetchTemplates(),
        fetchRules(),
      ]);
    } catch (e) {
      debugPrint('Erro ao carregar automações: $e');
    } finally {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> fetchSmtpConfig() async {
    try {
      final response = await _supabase.rpc('rh_get_smtp_config');
      if (response != null && response is List && response.isNotEmpty) {
        state = state.copyWith(smtpConfig: SmtpConfig.fromMap(response.first as Map<String, dynamic>));
      } else {
        state = AutomationsState(
          smtpConfig: null, 
          templates: state.templates, 
          rules: state.rules, 
          isLoading: state.isLoading
        ); // override with null correctly
      }
    } catch (e) {
      debugPrint('Erro fetchSmtpConfig: $e');
    }
  }

  Future<void> fetchTemplates() async {
    try {
      final response = await _supabase
          .from('rh_email_template')
          .select()
          .order('nome');
      final templates = (response as List).map((e) => EmailTemplate.fromMap(e)).toList();
      state = state.copyWith(templates: templates);
    } catch (e) {
      debugPrint('Erro fetchTemplates: $e');
    }
  }

  Future<void> fetchRules() async {
    try {
      final response = await _supabase
          .from('rh_automacao')
          .select('*, rh_email_template(*)')
          .order('created_at');
      final rules = (response as List).map((e) => AutomationRule.fromMap(e)).toList();
      state = state.copyWith(rules: rules);
    } catch (e) {
      debugPrint('Erro fetchRules: $e');
    }
  }

  /// Senha vazia = manter a já gravada (a RPC preserva o cipher atual).
  Future<void> saveSmtpConfig(SmtpConfig config) async {
    await _supabase.rpc('rh_save_smtp_config', params: {
      'p_host': config.host,
      'p_port': config.port,
      'p_username': config.username,
      'p_password': config.password ?? '',
      'p_from_email': config.fromEmail,
      'p_from_name': config.fromName,
    });
    await fetchSmtpConfig();
  }

  /// Dispara um teste de envio com o servidor SMTP configurado.
  Future<({bool success, String message})> testSmtpConnection({String? targetEmail}) async {
    try {
      final response = await _supabase.functions.invoke(
        'rh-automations',
        body: {
          'action': 'test_smtp',
          if (targetEmail != null && targetEmail.trim().isNotEmpty)
            'target_email': targetEmail.trim(),
        },
      );

      if (response.status == 200 && response.data != null) {
        final data = response.data;
        if (data is Map && data['success'] == true) {
          return (
            success: true,
            message: data['message'] as String? ?? 'E-mail de teste enviado com sucesso!',
          );
        } else if (data is Map && data['error'] != null) {
          return (
            success: false,
            message: data['error'] as String,
          );
        }
      }

      final errorMsg = response.data is Map ? response.data['error'] : 'Falha ao conectar';
      return (
        success: false,
        message: errorMsg?.toString() ?? 'Erro desconhecido ao testar conexão (status ${response.status}).',
      );
    } catch (e) {
      return (
        success: false,
        message: 'Erro ao invocar teste de SMTP: $e',
      );
    }
  }

  Future<void> saveTemplate(EmailTemplate template) async {
    if (template.id != null) {
      await _supabase
          .from('rh_email_template')
          .update(template.toMap())
          .eq('id', template.id!);
    } else {
      await _supabase
          .from('rh_email_template')
          .insert(template.toMap());
    }
    await fetchTemplates();
  }

  Future<void> deleteTemplate(String id) async {
    await _supabase.from('rh_email_template').delete().eq('id', id);
    await fetchTemplates();
    await fetchRules(); // cascade
  }

  Future<void> saveRule(AutomationRule rule) async {
    if (rule.id != null) {
      await _supabase
          .from('rh_automacao')
          .update(rule.toMap())
          .eq('id', rule.id!);
    } else {
      await _supabase
          .from('rh_automacao')
          .insert(rule.toMap());
    }
    await fetchRules();
  }

  Future<void> deleteRule(String id) async {
    await _supabase.from('rh_automacao').delete().eq('id', id);
    await fetchRules();
  }
}

final automationsProvider = StateNotifierProvider<AutomationsNotifier, AutomationsState>((ref) {
  return AutomationsNotifier();
});
