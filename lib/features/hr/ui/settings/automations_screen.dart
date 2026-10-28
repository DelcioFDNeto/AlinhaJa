import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:alinha_ja/features/hr/providers/automations_provider.dart';
import 'package:alinha_ja/features/hr/providers/talent_bank_provider.dart';
import 'package:alinha_ja/features/hr/models/pipeline_etapa_model.dart';
import 'package:alinha_ja/features/hr/models/smtp_config.dart';
import 'package:alinha_ja/features/hr/models/email_template.dart';
import 'package:alinha_ja/features/hr/models/automation_rule.dart';
import 'package:alinha_ja/core/rbac/providers/rbac_provider.dart';
import 'package:alinha_ja/core/utils/friendly_error.dart';
import 'package:alinha_ja/core/constants.dart';

class AutomationsScreen extends ConsumerStatefulWidget {
  const AutomationsScreen({super.key});

  @override
  ConsumerState<AutomationsScreen> createState() => _AutomationsScreenState();
}

class _AutomationsScreenState extends ConsumerState<AutomationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(automationsProvider.notifier).fetchAll();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(automationsProvider);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Comunicação & Automações'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Servidor SMTP'),
              Tab(text: 'Templates de E-mail'),
              Tab(text: 'Regras de Automação'),
            ],
          ),
        ),
        body: state.isLoading
            ? const Center(child: CircularProgressIndicator())
            : const TabBarView(
                children: [
                  _SmtpTab(),
                  _TemplatesTab(),
                  _RulesTab(),
                ],
              ),
      ),
    );
  }
}

class _SmtpTab extends ConsumerStatefulWidget {
  const _SmtpTab();

  @override
  ConsumerState<_SmtpTab> createState() => _SmtpTabState();
}

class _SmtpTabState extends ConsumerState<_SmtpTab> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _hostCtrl;
  late TextEditingController _portCtrl;
  late TextEditingController _userCtrl;
  late TextEditingController _passCtrl;
  late TextEditingController _fromEmailCtrl;
  late TextEditingController _fromNameCtrl;
  bool _isSaving = false;
  bool _isTesting = false;

  @override
  void initState() {
    super.initState();
    final config = ref.read(automationsProvider).smtpConfig;
    _hostCtrl = TextEditingController(text: config?.host ?? '');
    _portCtrl = TextEditingController(text: config?.port.toString() ?? '465');
    _userCtrl = TextEditingController(text: config?.username ?? '');
    // A senha nunca volta do banco — o campo sempre inicia vazio.
    _passCtrl = TextEditingController();
    _fromEmailCtrl = TextEditingController(text: config?.fromEmail ?? '');
    _fromNameCtrl = TextEditingController(text: config?.fromName ?? '');
  }

  @override
  void dispose() {
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _fromEmailCtrl.dispose();
    _fromNameCtrl.dispose();
    super.dispose();
  }

  void _syncFrom(SmtpConfig config) {
    _hostCtrl.text = config.host;
    _portCtrl.text = config.port.toString();
    _userCtrl.text = config.username;
    _fromEmailCtrl.text = config.fromEmail;
    _fromNameCtrl.text = config.fromName;
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    final config = SmtpConfig(
      host: _hostCtrl.text.trim(),
      port: int.tryParse(_portCtrl.text) ?? 465,
      username: _userCtrl.text.trim(),
      // Vazio = a RPC preserva a senha já gravada.
      password: _passCtrl.text.isNotEmpty ? _passCtrl.text : null,
      fromEmail: _fromEmailCtrl.text.trim(),
      fromName: _fromNameCtrl.text.trim(),
    );
    try {
      await ref.read(automationsProvider.notifier).saveSmtpConfig(config);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Configuração SMTP salva com sucesso!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar: ${friendlyError(e)}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _handleTestConnection() async {
    final state = ref.read(automationsProvider);
    if (state.smtpConfig == null && _passCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Salve a configuração SMTP antes de realizar o teste.'),
        ),
      );
      return;
    }

    final emailCtrl = TextEditingController(
      text: _fromEmailCtrl.text.isNotEmpty ? _fromEmailCtrl.text.trim() : '',
    );

    final targetEmail = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Testar Conexão SMTP'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Um e-mail de teste será enviado pelo servidor configurado para validar host, porta e credenciais.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: emailCtrl,
              decoration: const InputDecoration(
                labelText: 'Destinatário do Teste',
                hintText: 'seu-email@empresa.com.br',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(emailCtrl.text.trim()),
            child: const Text('Enviar Teste'),
          ),
        ],
      ),
    );

    if (targetEmail == null || targetEmail.isEmpty) return;

    setState(() => _isTesting = true);
    try {
      final result = await ref
          .read(automationsProvider.notifier)
          .testSmtpConnection(targetEmail: targetEmail);

      if (!mounted) return;
      if (result.success) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: const Icon(Icons.check_circle, color: Colors.green, size: 48),
            title: const Text('Sucesso!'),
            content: Text(result.message),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      } else {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: const Icon(Icons.error_outline, color: Colors.red, size: 48),
            title: const Text('Falha no Teste SMTP'),
            content: Text(result.message),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Fechar'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro no teste: ${friendlyError(e)}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isTesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // O fetch é assíncrono: quando a config chega depois do initState,
    // sincroniza os campos (sem tocar na senha).
    ref.listen<AutomationsState>(automationsProvider, (prev, next) {
      if (next.smtpConfig != null && prev?.smtpConfig != next.smtpConfig) {
        _syncFrom(next.smtpConfig!);
      }
    });
    final state = ref.watch(automationsProvider);
    final canManage = ref.watch(rbacCanProvider((module: 'rh_automacoes', action: 'manage')));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Configuração SMTP Própria',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Configure o servidor de e-mail da sua empresa para enviar mensagens aos candidatos usando o seu próprio domínio.',
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _hostCtrl,
              decoration: const InputDecoration(labelText: 'Host (ex: smtp.gmail.com)', border: OutlineInputBorder()),
              validator: (v) => v!.isEmpty ? 'Obrigatório' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _portCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Porta (ex: 465)', border: OutlineInputBorder()),
              validator: (v) => v!.isEmpty ? 'Obrigatório' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _userCtrl,
              decoration: const InputDecoration(labelText: 'Usuário (E-mail de autenticação)', border: OutlineInputBorder()),
              validator: (v) => v!.isEmpty ? 'Obrigatório' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _passCtrl,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'Senha (ou App Password)',
                border: const OutlineInputBorder(),
                helperText: state.smtpConfig?.hasPassword == true
                  ? 'Já existe senha salva (criptografada, nunca exibida). Digite apenas se quiser alterar.'
                  : 'Sua senha será armazenada de forma criptografada.',
              ),
              validator: (v) {
                if (state.smtpConfig == null && v!.isEmpty) {
                  return 'Obrigatório para nova configuração';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),
            const Text(
              'Remetente (From)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _fromNameCtrl,
              decoration: const InputDecoration(labelText: 'Nome do Remetente (ex: RH ${AppConstants.appName})', border: OutlineInputBorder()),
              validator: (v) => v!.isEmpty ? 'Obrigatório' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _fromEmailCtrl,
              decoration: const InputDecoration(labelText: 'E-mail do Remetente', border: OutlineInputBorder()),
              validator: (v) => v!.isEmpty ? 'Obrigatório' : null,
            ),
            const SizedBox(height: 32),
            Wrap(
              spacing: 16,
              runSpacing: 12,
              children: [
                ElevatedButton.icon(
                  icon: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save),
                  label: const Text('Salvar Configuração'),
                  onPressed: !canManage || _isSaving || _isTesting ? null : _handleSave,
                ),
                OutlinedButton.icon(
                  icon: _isTesting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_outlined),
                  label: const Text('Testar Conexão'),
                  onPressed: !canManage || _isSaving || _isTesting ? null : _handleTestConnection,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TemplatesTab extends ConsumerWidget {
  const _TemplatesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(automationsProvider);
    final canManage = ref.watch(rbacCanProvider((module: 'rh_automacoes', action: 'manage')));
    
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              const Expanded(child: Text('Crie modelos de e-mail que poderão ser enviados automaticamente ou manualmente.')),
              ElevatedButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Novo Template'),
                onPressed: canManage ? () => _showTemplateDialog(context, ref, null) : null,
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: state.templates.length,
            itemBuilder: (context, index) {
              final tpl = state.templates[index];
              return ListTile(
                title: Text(tpl.nome),
                subtitle: Text('Assunto: ${tpl.assunto}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(icon: const Icon(Icons.edit), onPressed: canManage ? () => _showTemplateDialog(context, ref, tpl) : null),
                    IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: canManage ? () => ref.read(automationsProvider.notifier).deleteTemplate(tpl.id!) : null),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _showTemplateDialog(BuildContext context, WidgetRef ref, EmailTemplate? template) {
    final nomeCtrl = TextEditingController(text: template?.nome ?? '');
    final assuntoCtrl = TextEditingController(text: template?.assunto ?? '');
    final bodyCtrl = TextEditingController(text: template?.bodyHtml ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(template == null ? 'Novo Template' : 'Editar Template'),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nomeCtrl, decoration: const InputDecoration(labelText: 'Nome Interno (ex: Reprovação Técnico)')),
                const SizedBox(height: 16),
                TextField(controller: assuntoCtrl, decoration: const InputDecoration(labelText: 'Assunto do E-mail')),
                const SizedBox(height: 16),
                TextField(
                  controller: bodyCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Corpo (Aceita HTML)',
                    alignLabelWithHint: true,
                    helperText: 'Variáveis: {{nome}}, {{candidato_nome}}',
                  ),
                  maxLines: 8,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              final novo = EmailTemplate(
                id: template?.id,
                organizationId: template?.organizationId,
                nome: nomeCtrl.text,
                assunto: assuntoCtrl.text,
                bodyHtml: bodyCtrl.text,
              );
              await ref.read(automationsProvider.notifier).saveTemplate(novo);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }
}

class _RulesTab extends ConsumerWidget {
  const _RulesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(automationsProvider);
    final canManage = ref.watch(rbacCanProvider((module: 'rh_automacoes', action: 'manage')));
    // Etapas reais da org (RH-14) — labels amigáveis nos cards de regra.
    final pipeline =
        ref.watch(pipelineConfigProvider).valueOrNull ?? PipelineConfig.padrao();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              const Expanded(child: Text('Vincule uma mudança de etapa no funil a um disparo de template de e-mail.')),
              ElevatedButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Nova Regra'),
                onPressed: canManage ? () => _showRuleDialog(context, ref, null) : null,
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: state.rules.length,
            itemBuilder: (context, index) {
              final rule = state.rules[index];
              final etapaSlug = rule.condicao['etapa_destino'] as String? ?? '';
              return ListTile(
                leading: Icon(rule.ativo ? Icons.bolt : Icons.bolt_outlined, color: rule.ativo ? Colors.amber : Colors.grey),
                title: Text('Se mover para etapa: ${pipeline.label(etapaSlug)}'),
                subtitle: Text('Enviar template: ${rule.template?.nome ?? 'Sem template'}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Switch(
                      value: rule.ativo,
                      onChanged: (v) {
                        ref.read(automationsProvider.notifier).saveRule(AutomationRule(
                          id: rule.id,
                          organizationId: rule.organizationId,
                          condicao: rule.condicao,
                          templateId: rule.templateId,
                          ativo: v,
                          evento: rule.evento,
                          acao: rule.acao,
                        ));
                      },
                    ),
                    IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: canManage ? () => ref.read(automationsProvider.notifier).deleteRule(rule.id!) : null),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _showRuleDialog(BuildContext context, WidgetRef ref, AutomationRule? rule) {
    // As etapas vêm do pipeline configurável da org (RH-14) — os slugs
    // fixos antigos (triagem/teste/proposta) nem existiam no funil real.
    final pipeline =
        ref.read(pipelineConfigProvider).valueOrNull ?? PipelineConfig.padrao();
    final etapas =
        pipeline.etapas.where((e) => !e.isEntrada).toList(growable: false);
    String etapaDestino = rule?.condicao['etapa_destino'] as String? ??
        pipeline.descartado.slug;
    if (!etapas.any((e) => e.slug == etapaDestino)) {
      etapaDestino = etapas.isNotEmpty ? etapas.first.slug : etapaDestino;
    }
    String? selectedTemplateId = rule?.templateId;
    final state = ref.read(automationsProvider);

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(rule == null ? 'Nova Automação' : 'Editar Automação'),
              content: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Quando o candidato for movido para a etapa:'),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: etapaDestino,
                      decoration: const InputDecoration(border: OutlineInputBorder()),
                      items: [
                        for (final e in etapas)
                          DropdownMenuItem(value: e.slug, child: Text(e.nome)),
                      ],
                      onChanged: (v) => setState(() => etapaDestino = v!),
                    ),
                    const SizedBox(height: 16),
                    const Text('Enviar o e-mail:'),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: selectedTemplateId,
                      decoration: const InputDecoration(border: OutlineInputBorder()),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('Selecione um template...')),
                        ...state.templates.map((t) => DropdownMenuItem(value: t.id, child: Text(t.nome))),
                      ],
                      onChanged: (v) => setState(() => selectedTemplateId = v),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
                ElevatedButton(
                  onPressed: () async {
                    if (selectedTemplateId == null) return;
                    final nova = AutomationRule(
                      id: rule?.id,
                      organizationId: rule?.organizationId,
                      condicao: {'etapa_destino': etapaDestino},
                      templateId: selectedTemplateId,
                      ativo: rule?.ativo ?? true,
                    );
                    await ref.read(automationsProvider.notifier).saveRule(nova);
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: const Text('Salvar'),
                ),
              ],
            );
          }
        );
      },
    );
  }
}
