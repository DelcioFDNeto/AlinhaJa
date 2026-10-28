import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:alinha_ja/features/support/providers/support_provider.dart';
import 'package:alinha_ja/core/constants.dart';
import 'package:alinha_ja/features/auth/providers/auth_provider.dart';

class CreateTicketScreen extends ConsumerStatefulWidget {
  const CreateTicketScreen({super.key});

  @override
  ConsumerState<CreateTicketScreen> createState() => _CreateTicketScreenState();
}

class _CreateTicketScreenState extends ConsumerState<CreateTicketScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _deviceCtrl = TextEditingController();

  String _selectedCategory = 'software';
  String _selectedPriority = 'medium';
  bool _isLoading = false;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      await SupportService.createTicket(
        title: _titleCtrl.text.trim(),
        description: _descCtrl.text.trim(),
        category: _selectedCategory,
        priority: _selectedPriority,
        deviceInfo:
            _deviceCtrl.text.trim().isEmpty ? null : _deviceCtrl.text.trim(),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('✅ Chamado enviado com sucesso!'),
              backgroundColor: AppConstants.success),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Erro ao criar chamado: $e'),
              backgroundColor: AppConstants.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _deviceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final userAsync = ref.watch(currentUserProvider);

    return userAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, __) =>
          const Scaffold(body: Center(child: Text('Erro ao carregar perfil'))),
      data: (user) {
        // Qualquer usuário autenticado pode abrir um chamado para a T.I.
        // A visibilidade da Central de Ajuda (e deste fluxo) já é gated por
        // licença + RBAC (`helpdesk:view`) no Module Registry.
        if (user == null) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Abrir Novo Chamado'),
              centerTitle: false,
            ),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_rounded,
                        size: 64, color: AppConstants.danger),
                    const SizedBox(height: 16),
                    Text(
                      'Sessão expirada',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Faça login novamente para abrir um chamado.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.outline),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Abrir Novo Chamado'),
            centerTitle: false,
          ),
          body: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // Ícone de destaque
                Icon(Icons.support_agent_rounded,
                    size: 48, color: theme.colorScheme.tertiary),
                const SizedBox(height: 8),
                Text(
                  'Descreva seu problema abaixo.\nA equipe de TI receberá e responderá.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
                const SizedBox(height: 24),

                // Assunto
                TextFormField(
                  controller: _titleCtrl,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: 'Assunto do Problema *',
                    hintText: 'Ex: Sistema travando ao gerar nota',
                    prefixIcon: const Icon(Icons.short_text_rounded),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  validator: (v) =>
                      v!.trim().isEmpty ? 'Digite o assunto do chamado' : null,
                ),
                const SizedBox(height: 16),

                // Categoria
                DropdownButtonFormField<String>(
                  initialValue: _selectedCategory,
                  decoration: InputDecoration(
                    labelText: 'Categoria',
                    prefixIcon: const Icon(Icons.category_rounded),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  items: categoryLabels.entries
                      .map((e) =>
                          DropdownMenuItem(value: e.key, child: Text(e.value)))
                      .toList(),
                  onChanged: (v) => setState(() => _selectedCategory = v!),
                ),
                const SizedBox(height: 16),

                // Prioridade
                DropdownButtonFormField<String>(
                  initialValue: _selectedPriority,
                  decoration: InputDecoration(
                    labelText: 'Impacto no Trabalho',
                    prefixIcon: const Icon(Icons.priority_high_rounded),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  items: const [
                    DropdownMenuItem(
                        value: 'low', child: Text('🟢  Baixo — Pode aguardar')),
                    DropdownMenuItem(
                        value: 'medium',
                        child: Text('🔵  Normal — Uso diário')),
                    DropdownMenuItem(
                        value: 'high',
                        child: Text('🟠  Alto — Atrapalha o trabalho')),
                    DropdownMenuItem(
                        value: 'urgent',
                        child: Text('🔴  Urgente — Sistema parado')),
                  ],
                  onChanged: (v) => setState(() => _selectedPriority = v!),
                ),
                const SizedBox(height: 16),

                // Descrição detalhada
                TextFormField(
                  controller: _descCtrl,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: 'Descrição Detalhada *',
                    hintText: 'Explique passo a passo o que aconteceu...',
                    alignLabelWithHint: true,
                    prefixIcon: const Padding(
                        padding: EdgeInsets.only(bottom: 80),
                        child: Icon(Icons.description_rounded)),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  validator: (v) => v!.trim().isEmpty
                      ? 'Descreva o que está acontecendo'
                      : null,
                ),
                const SizedBox(height: 16),

                // Equipamento (opcional)
                TextFormField(
                  controller: _deviceCtrl,
                  decoration: InputDecoration(
                    labelText: 'Equipamento ou Local (Opcional)',
                    hintText: 'Ex: Computador da Recepção 02',
                    prefixIcon: const Icon(Icons.devices_rounded),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),

                const SizedBox(height: 32),

                // Botão de envio
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: _isLoading ? null : _submit,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.send_rounded),
                    label: Text(_isLoading ? 'Enviando...' : 'ENVIAR CHAMADO'),
                    style: FilledButton.styleFrom(
                      backgroundColor: theme.colorScheme.tertiary,
                      foregroundColor: theme.colorScheme.onTertiary,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      textStyle: const TextStyle(
                          fontWeight: FontWeight.w700, letterSpacing: 0.5),
                    ),
                  ),
                ),

                const SizedBox(height: 16),
                Text(
                  'Após enviar, acompanhe o status do chamado em "Meus Chamados".',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline, fontSize: 11),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
