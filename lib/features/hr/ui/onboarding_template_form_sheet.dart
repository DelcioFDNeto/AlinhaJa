import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:alinha_ja/core/status_tokens.dart';
import 'package:alinha_ja/features/hr/models/onboarding_model.dart';
import 'package:alinha_ja/features/hr/providers/onboarding_provider.dart';
import 'package:alinha_ja/features/hr/ui/widgets/hr_empty_state.dart';
import 'package:alinha_ja/core/utils/friendly_error.dart';

class OnboardingTemplateFormSheet extends ConsumerStatefulWidget {
  final String? templateId;

  const OnboardingTemplateFormSheet({super.key, this.templateId});

  @override
  ConsumerState<OnboardingTemplateFormSheet> createState() =>
      _OnboardingTemplateFormSheetState();
}

class _OnboardingTemplateFormSheetState
    extends ConsumerState<OnboardingTemplateFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nomeCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  bool _ativo = true;
  bool _padrao = false;
  List<OnboardingTemplateItem> _itens = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    if (widget.templateId != null) {
      _loadData();
    }
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final templates = await ref.read(onboardingTemplatesProvider.future);
      final tpl = templates.firstWhere((t) => t.id == widget.templateId);
      final items = await ref.read(
          onboardingTemplateItemsProvider(widget.templateId!).future);
      setState(() {
        _nomeCtrl.text = tpl.nome;
        _descCtrl.text = tpl.descricao ?? '';
        _ativo = tpl.ativo;
        _padrao = tpl.padrao;
        _itens = List.from(items);
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  void _addItem() {
    setState(() {
      _itens.add(OnboardingTemplateItem(
        ordem: _itens.length,
        titulo: 'Novo Item',
      ));
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await ref.read(onboardingServiceProvider).saveTemplate(
            id: widget.templateId,
            nome: _nomeCtrl.text,
            descricao: _descCtrl.text.isEmpty ? null : _descCtrl.text,
            ativo: _ativo,
            padrao: _padrao,
            itens: _itens,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro ao salvar: ${friendlyError(e)}')));
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _nomeCtrl.text.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.templateId == null
                  ? 'Novo Template'
                  : 'Editar Template',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nomeCtrl,
              decoration: const InputDecoration(labelText: 'Nome do Template'),
              validator: (v) =>
                  v == null || v.isEmpty ? 'Campo obrigatório' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _descCtrl,
              decoration: const InputDecoration(labelText: 'Descrição'),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              title: const Text('Template Padrão (Auto-iniciado)'),
              value: _padrao,
              onChanged: (v) => setState(() => _padrao = v),
            ),
            SwitchListTile(
              title: const Text('Ativo'),
              value: _ativo,
              onChanged: (v) => setState(() => _ativo = v),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Itens do Checklist',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                TextButton.icon(
                  onPressed: _addItem,
                  icon: const Icon(Icons.add),
                  label: const Text('Adicionar Item'),
                ),
              ],
            ),
            if (_itens.isEmpty)
              const HrEmptyBlock(
                icone: Icons.playlist_add,
                titulo: 'Nenhuma etapa neste template',
                dica:
                    'Adicione as etapas na ordem em que devem acontecer '
                    '(entregar documentos, assinar contrato, treinamento de '
                    'segurança). Cada uma pode ter responsável e prazo, e a '
                    'ordem é ajustável arrastando.',
                altura: 160,
              )
            else
              Flexible(
                child: ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _itens.length,
                  onReorder: (oldIndex, newIndex) {
                    setState(() {
                      if (newIndex > oldIndex) newIndex -= 1;
                      final item = _itens.removeAt(oldIndex);
                      _itens.insert(newIndex, item);
                      for (int i = 0; i < _itens.length; i++) {
                        _itens[i] = OnboardingTemplateItem(
                          id: _itens[i].id,
                          ordem: i,
                          titulo: _itens[i].titulo,
                          descricao: _itens[i].descricao,
                          categoria: _itens[i].categoria,
                          obrigatorio: _itens[i].obrigatorio,
                          prazoDias: _itens[i].prazoDias,
                          responsavel: _itens[i].responsavel,
                        );
                      }
                    });
                  },
                  itemBuilder: (context, index) {
                    final item = _itens[index];
                    return Card(
                      key: ValueKey(item.id ?? 'item_$index'),
                      child: ListTile(
                        title: Text(item.titulo),
                        subtitle: Text(
                            'Responsável: ${OnboardingResponsavel.label(item.responsavel)}\nPrazo: ${item.prazoDias ?? '-'} dias'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit, size: 20),
                              onPressed: () {
                                // Em um app real, abriria form de edição do item
                              },
                            ),
                            IconButton(
                              icon: Icon(Icons.delete,
                                  size: 20, color: context.statusTokens.danger),
                              onPressed: () {
                                setState(() {
                                  _itens.removeAt(index);
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loading ? null : _save,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _loading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Salvar Template'),
            ),
          ],
        ),
      ),
    );
  }
}
