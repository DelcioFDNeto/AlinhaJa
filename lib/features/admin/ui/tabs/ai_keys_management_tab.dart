import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:alinha_ja/core/constants.dart';
import 'package:alinha_ja/core/supabase_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// Metadados de cada provedor de IA suportado (BYOK multi-tenant).
class _Provider {
  final String id;
  final String label;
  final String short;

  /// Prefixos aceitos para a chave. A validação passa se a chave começar
  /// com qualquer um deles (ex.: Gemini aceita 'AIza' e o novo 'AQ.').
  final List<String> prefixes;
  final String hint;
  final String consoleUrl;
  final List<String> steps;

  const _Provider({
    required this.id,
    required this.label,
    required this.short,
    required this.prefixes,
    required this.hint,
    required this.consoleUrl,
    required this.steps,
  });
}

const List<_Provider> _providers = [
  _Provider(
    id: 'anthropic',
    label: 'Anthropic (Claude)',
    short: 'Claude',
    prefixes: ['sk-ant-'],
    hint: 'sk-ant-api03-...',
    consoleUrl: 'https://console.anthropic.com/settings/keys',
    steps: [
      'Acesse o console da Anthropic e faça login (ou crie uma conta corporativa).',
      'Em "Billing", adicione um método de pagamento e créditos — a API Claude é pré-paga por uso. Atenção: a assinatura Claude Pro/Max NÃO cobre a API; o faturamento é separado.',
      'Abra "API Keys" e clique em "Create Key". Dê um nome (ex.: "AlinhaJá RH").',
      'Copie a chave gerada (sk-ant-...). Ela só é exibida UMA vez pelo console.',
      'Cole a chave no campo abaixo e salve.',
    ],
  ),
  _Provider(
    id: 'openai',
    label: 'OpenAI (GPT)',
    short: 'GPT',
    prefixes: ['sk-'],
    hint: 'sk-...',
    consoleUrl: 'https://platform.openai.com/api-keys',
    steps: [
      'Acesse platform.openai.com e faça login (ou crie uma conta).',
      'Em "Billing", adicione um método de pagamento e créditos — a API é paga por uso e é separada da assinatura ChatGPT Plus.',
      'Abra "API keys" e clique em "Create new secret key". Dê um nome (ex.: "AlinhaJá RH").',
      'Copie a chave gerada (sk-...). Ela só é exibida UMA vez.',
      'Cole a chave no campo abaixo e salve.',
    ],
  ),
  _Provider(
    id: 'gemini',
    label: 'Google (Gemini)',
    short: 'Gemini',
    prefixes: ['AIza', 'AQ.'],
    hint: 'AIza... ou AQ.Ab...',
    consoleUrl: 'https://aistudio.google.com/app/apikey',
    steps: [
      'Acesse aistudio.google.com e faça login com uma conta Google.',
      'Abra "Get API key" e clique em "Create API key" (pode ser necessário um projeto do Google Cloud).',
      'Para uso além da cota gratuita, ative o faturamento no projeto — o nível gratuito do Gemini tem limites de uso.',
      'Copie a chave gerada (começa com "AIza..." ou, nas contas mais novas, "AQ.Ab...").',
      'Cole a chave no campo abaixo e salve.',
    ],
  ),
  _Provider(
    id: 'groq',
    label: 'Groq (Llama)',
    short: 'Groq',
    prefixes: ['gsk_'],
    hint: 'gsk_...',
    consoleUrl: 'https://console.groq.com/keys',
    steps: [
      'Acesse console.groq.com e faça login (ou crie uma conta).',
      'Abra "API Keys" e clique em "Create API Key". Dê um nome (ex.: "AlinhaJá RH").',
      'Copie a chave gerada (gsk_...). Ela só é exibida UMA vez.',
      'O Groq tem um tier gratuito generoso (ideal para extração ultrarrápida); há faturamento por uso apenas acima da cota.',
      'Cole a chave no campo abaixo e salve.',
    ],
  ),
];

class AiKeysManagementTab extends ConsumerStatefulWidget {
  const AiKeysManagementTab({super.key});

  @override
  ConsumerState<AiKeysManagementTab> createState() => _AiKeysManagementTabState();
}

class _AiKeysManagementTabState extends ConsumerState<AiKeysManagementTab> {
  final _formKey = GlobalKey<FormState>();
  final _keyCtrl = TextEditingController();

  String _selected = 'anthropic';
  String _activeProvider = 'anthropic';

  final Map<String, bool> _configured = {};
  final Map<String, String?> _last4 = {};

  bool _isObscured = true;
  bool _isLoadingStatus = true;
  bool _isLoading = false;
  bool _isDeleting = false;
  bool _isSettingActive = false;

  _Provider get _sel => _providers.firstWhere((p) => p.id == _selected);

  @override
  void initState() {
    super.initState();
    _fetchStatus();
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchStatus() async {
    setState(() => _isLoadingStatus = true);
    try {
      final results = await Future.wait([
        for (final p in _providers)
          supabase.rpc('has_org_ai_key', params: {'p_provider': p.id}),
        supabase.rpc('get_org_ai_provider'),
      ]);

      for (var i = 0; i < _providers.length; i++) {
        final res = results[i];
        final data = res is Map ? res : const {};
        _configured[_providers[i].id] = data['configured'] == true;
        _last4[_providers[i].id] = data['last4'] as String?;
      }
      final active = results.last;
      if (active is String && active.isNotEmpty) _activeProvider = active;
    } catch (_) {
      // Falha ao consultar não impede configurar uma nova chave.
    } finally {
      if (mounted) setState(() => _isLoadingStatus = false);
    }
  }

  Future<void> _saveKey() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      await supabase.rpc('set_org_ai_key', params: {
        'p_provider': _selected,
        'p_key': _keyCtrl.text.trim(),
      });
      if (mounted) {
        _snack('Chave da ${_sel.label} salva com sucesso!', ok: true);
        _keyCtrl.clear();
        await _fetchStatus();
      }
    } catch (e) {
      if (mounted) _snack(_errText(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteKey() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remover chave da ${_sel.label}?'),
        content: const Text(
          'A chave será apagada permanentemente do Vault de segurança — nenhum '
          'material criptografado permanece no banco. Se este for o provedor '
          'ativo, a extração automatizada por IA ficará desativada até que uma '
          'nova chave seja configurada.\n\nEsta ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppConstants.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isDeleting = true);
    try {
      await supabase.rpc('delete_org_ai_key', params: {'p_provider': _selected});
      if (mounted) {
        _snack('Chave da ${_sel.label} removida do Vault.', ok: true);
        _keyCtrl.clear();
        await _fetchStatus();
      }
    } catch (e) {
      if (mounted) _snack(_errText(e));
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  Future<void> _setActive() async {
    setState(() => _isSettingActive = true);
    try {
      await supabase.rpc('set_org_ai_provider', params: {'p_provider': _selected});
      if (mounted) {
        _snack('${_sel.label} definido como provedor de extração.', ok: true);
        await _fetchStatus();
      }
    } catch (e) {
      if (mounted) _snack(_errText(e));
    } finally {
      if (mounted) setState(() => _isSettingActive = false);
    }
  }

  Future<void> _openConsole() async {
    try {
      final ok = await launchUrl(Uri.parse(_sel.consoleUrl),
          mode: LaunchMode.externalApplication);
      if (!ok) throw Exception('launch retornou false');
    } catch (_) {
      if (mounted) {
        _snack('Não foi possível abrir o navegador. Acesse ${_sel.consoleUrl} manualmente.');
      }
    }
  }

  void _snack(String msg, {bool ok = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: ok ? AppConstants.success : AppConstants.danger,
    ));
  }

  String _errText(Object e) {
    if (e is PostgrestException) return e.message;
    final s = e.toString();
    return s.length > 120 ? '${s.substring(0, 120)}...' : s;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool configured = _configured[_selected] == true;
    final bool isActive = _activeProvider == _selected;
    final String? last4 = _last4[_selected];

    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 600),
        padding: const EdgeInsets.all(24.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _activeBanner(theme),
              const SizedBox(height: 16),
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(28.0),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _header(theme),
                        const SizedBox(height: 24),
                        // ── Seletor de provedor ─────────────────
                        Align(
                          alignment: Alignment.centerLeft,
                          child: SegmentedButton<String>(
                            segments: [
                              for (final p in _providers)
                                ButtonSegment(value: p.id, label: Text(p.short)),
                            ],
                            selected: {_selected},
                            showSelectedIcon: false,
                            onSelectionChanged: (s) {
                              setState(() {
                                _selected = s.first;
                                _keyCtrl.clear();
                                _isObscured = true;
                              });
                            },
                          ),
                        ),
                        const SizedBox(height: 16),
                        _statusBanner(theme, configured, isActive, last4),
                        const SizedBox(height: 20),
                        _instructions(theme),
                        const SizedBox(height: 16),
                        Text('Chave de API (${_sel.label})',
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _keyCtrl,
                          obscureText: _isObscured,
                          autocorrect: false,
                          enableSuggestions: false,
                          decoration: InputDecoration(
                            hintText: _sel.hint,
                            prefixIcon: const Icon(Icons.password),
                            suffixIcon: IconButton(
                              icon: Icon(
                                  _isObscured ? Icons.visibility : Icons.visibility_off),
                              onPressed: () =>
                                  setState(() => _isObscured = !_isObscured),
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            fillColor: theme.colorScheme.surfaceContainerHighest,
                          ),
                          validator: (val) {
                            final v = val?.trim() ?? '';
                            if (v.isEmpty) return 'Informe a chave de API.';
                            if (!_sel.prefixes.any(v.startsWith)) {
                              return 'A chave deve começar com ${_sel.prefixes.map((p) => '"$p"').join(' ou ')}.';
                            }
                            if (v.length < 20) {
                              return 'Chave muito curta ou inválida.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'A chave é armazenada criptografada no Vault e nunca é exposta. Ao salvar uma nova chave, a anterior deste provedor é substituída.',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.outline),
                        ),
                        const SizedBox(height: 24),
                        _saveButton(theme),
                        if (configured && !isActive) ...[
                          const SizedBox(height: 12),
                          _setActiveButton(theme),
                        ],
                        if (configured) ...[
                          const SizedBox(height: 12),
                          _deleteButton(theme),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(ThemeData theme) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.vpn_key, color: theme.colorScheme.primary, size: 32),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Configuração de Inteligência Artificial',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(
                'Configure a chave de API do provedor de IA da sua organização para habilitar a extração automatizada de dados em currículos e documentos do RH.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _activeBanner(ThemeData theme) {
    if (_isLoadingStatus) {
      return Row(
        children: [
          const SizedBox(
              width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 12),
          Text('Verificando configuração...',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.outline)),
        ],
      );
    }
    final active = _providers.firstWhere((p) => p.id == _activeProvider,
        orElse: () => _providers.first);
    final bool activeHasKey = _configured[_activeProvider] == true;
    final Color color = activeHasKey ? AppConstants.success : theme.colorScheme.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(activeHasKey ? Icons.check_circle : Icons.warning, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              activeHasKey
                  ? 'Provedor de extração ativo: ${active.label} — a IA está ativa.'
                  : 'Provedor de extração ativo: ${active.label} — SEM chave configurada; a extração está desativada.',
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusBanner(ThemeData theme, bool configured, bool isActive, String? last4) {
    final Color color = configured ? AppConstants.success : theme.colorScheme.outline;
    final String label = configured
        ? 'Chave configurada${last4 != null ? ' (••••$last4)' : ''}${isActive ? ' • ativo para extração' : ''}'
        : 'Nenhuma chave configurada para ${_sel.label}';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(configured ? Icons.check_circle : Icons.info_outline,
              color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label,
                style: TextStyle(
                    color: configured ? color : theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  Widget _instructions(ThemeData theme) {
    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        leading: Icon(Icons.help_outline, color: theme.colorScheme.primary),
        title: Text('Como obter uma chave da ${_sel.label}?',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        children: [
          for (var i = 0; i < _sel.steps.length; i++)
            _buildStep(theme, '${i + 1}', _sel.steps[i]),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _openConsole,
              icon: const Icon(Icons.open_in_new, size: 18),
              label: Text('Abrir ${Uri.parse(_sel.consoleUrl).host}'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep(ThemeData theme, String n, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 11,
            backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
            child: Text(n,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary)),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }

  Widget _saveButton(ThemeData theme) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton.icon(
        onPressed: _isLoading ? null : _saveKey,
        icon: _isLoading
            ? const SizedBox(
                width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.save),
        label: Text(_isLoading ? 'Salvando...' : 'Salvar Chave de API'),
        style: ElevatedButton.styleFrom(
          backgroundColor: theme.colorScheme.primary,
          foregroundColor: theme.colorScheme.onPrimary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  Widget _setActiveButton(ThemeData theme) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton.icon(
        onPressed: _isSettingActive ? null : _setActive,
        icon: _isSettingActive
            ? const SizedBox(
                width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.bolt),
        label: Text(_isSettingActive
            ? 'Definindo...'
            : 'Usar ${_sel.label} na extração'),
        style: OutlinedButton.styleFrom(
          foregroundColor: theme.colorScheme.primary,
          side: BorderSide(color: theme.colorScheme.primary),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  Widget _deleteButton(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 48,
          child: OutlinedButton.icon(
            onPressed: (_isDeleting || _isLoading) ? null : _deleteKey,
            icon: _isDeleting
                ? const SizedBox(
                    width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.delete_outline),
            label: Text(_isDeleting ? 'Removendo...' : 'Remover chave do sistema'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppConstants.danger,
              side: const BorderSide(color: AppConstants.danger),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'A remoção apaga a chave por completo do Vault, evitando qualquer risco de vazamento de dados sensíveis.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
        ),
      ],
    );
  }
}
