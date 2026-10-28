import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:alinha_ja/features/hr/models/vacancy_model.dart';
import 'package:alinha_ja/features/hr/providers/vacancy_provider.dart';
import 'package:alinha_ja/core/utils/friendly_error.dart';

/// RH-10 / Fase 2 — Formulário de criação / edição de vaga.
/// Abre como BottomSheet a partir da aba Vagas (VacanciesTab).
class VacancyFormSheet extends ConsumerStatefulWidget {
  const VacancyFormSheet({super.key, this.vaga});

  /// Quando `null` é criação; quando preenchido, edição.
  final VagaModel? vaga;

  @override
  ConsumerState<VacancyFormSheet> createState() => _VacancyFormSheetState();
}

class _VacancyFormSheetState extends ConsumerState<VacancyFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titulo;
  late final TextEditingController _localidade;
  late final TextEditingController _faixaSalarial;
  late final TextEditingController _descricao;
  late final TextEditingController _requisitos;
  late final TextEditingController _vagasQtd;

  String? _areaId;
  String? _cargoId;
  String _nivel = 'pleno';
  String _tipoContrato = 'clt';
  bool _remoto = false;
  DateTime? _expiraEm;
  bool _saving = false;

  bool get _isEdit => widget.vaga != null;

  static final _dateFmt = DateFormat('dd/MM/yyyy');

  static const _niveis = {
    'estagio': 'Estágio',
    'junior': 'Júnior',
    'pleno': 'Pleno',
    'senior': 'Sênior',
    'lideranca': 'Liderança/Gestão',
  };

  static const _contratos = {
    'clt': 'CLT',
    'pj': 'PJ',
    'estagio': 'Estágio',
    'temporario': 'Temporário',
    'freelancer': 'Freelancer',
  };

  @override
  void initState() {
    super.initState();
    final v = widget.vaga;
    _titulo = TextEditingController(text: v?.titulo ?? '');
    _localidade = TextEditingController(text: v?.localidade ?? '');
    _faixaSalarial = TextEditingController(text: v?.faixaSalarial ?? '');
    _descricao = TextEditingController(text: v?.descricao ?? '');
    _requisitos = TextEditingController(text: v?.requisitos ?? '');
    _vagasQtd = TextEditingController(
        text: v?.vagasQtd != null ? v!.vagasQtd.toString() : '');

    _areaId = v?.areaId;
    _cargoId = v?.cargoId;
    _nivel = v?.nivel ?? 'pleno';
    _tipoContrato = v?.tipoContrato ?? 'clt';
    _remoto = v?.remoto ?? false;
    _expiraEm = v?.expiraEm;
  }

  @override
  void dispose() {
    _titulo.dispose();
    _localidade.dispose();
    _faixaSalarial.dispose();
    _descricao.dispose();
    _requisitos.dispose();
    _vagasQtd.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiraEm ?? DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _expiraEm = picked);
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    try {
      final fields = <String, dynamic>{
        'titulo': _titulo.text.trim(),
        'area_id': _areaId,
        'cargo_id': _cargoId,
        'nivel': _nivel,
        'tipo_contrato': _tipoContrato,
        'localidade': _localidade.text.trim().isEmpty
            ? null
            : _localidade.text.trim(),
        'remoto': _remoto,
        'faixa_salarial': _faixaSalarial.text.trim().isEmpty
            ? null
            : _faixaSalarial.text.trim(),
        'descricao': _descricao.text.trim().isEmpty
            ? null
            : _descricao.text.trim(),
        'requisitos': _requisitos.text.trim().isEmpty
            ? null
            : _requisitos.text.trim(),
        'vagas_qtd': int.tryParse(_vagasQtd.text.trim()),
        'expira_em': _expiraEm?.toIso8601String().split('T').first,
      };

      final svc = ref.read(vacancyServiceProvider);
      if (_isEdit) {
        await svc.updateVaga(widget.vaga!.id, fields);
      } else {
        await svc.createVaga(fields);
      }

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro ao salvar: ${friendlyError(e)}')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final areasAsync = ref.watch(areasProvider(true));
    final cargosAsync = ref.watch(cargosProvider(true));

    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Scaffold(
        appBar: AppBar(
          title: Text(_isEdit ? 'Editar Vaga' : 'Nova Vaga'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
          actions: [
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Salvar'),
            ),
            const SizedBox(width: 12),
          ],
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(16),
            children: [
              // ── Título ──
              TextFormField(
                controller: _titulo,
                textCapitalization: TextCapitalization.sentences,
                decoration:
                    const InputDecoration(labelText: 'Título da vaga *'),
                validator: (v) => (v == null || v.trim().length < 3)
                    ? 'Mínimo 3 caracteres'
                    : null,
              ),
              const SizedBox(height: 12),

              // ── Área (catálogo) ──
              areasAsync.when(
                data: (areas) => DropdownButtonFormField<String>(
                  initialValue: _areaId,
                  decoration: const InputDecoration(labelText: 'Área'),
                  items: [
                    const DropdownMenuItem<String>(
                        value: null, child: Text('Nenhuma')),
                    for (final a in areas)
                      DropdownMenuItem(value: a.id, child: Text(a.nome)),
                  ],
                  onChanged: (v) => setState(() => _areaId = v),
                ),
                loading: () => const LinearProgressIndicator(),
                error: (_, __) => const Text('Erro ao carregar áreas'),
              ),
              const SizedBox(height: 12),

              // ── Cargo (catálogo) ──
              cargosAsync.when(
                data: (cargos) => DropdownButtonFormField<String>(
                  initialValue: _cargoId,
                  decoration: const InputDecoration(labelText: 'Cargo'),
                  items: [
                    const DropdownMenuItem<String>(
                        value: null, child: Text('Nenhum')),
                    for (final c in cargos)
                      DropdownMenuItem(value: c.id, child: Text(c.nome)),
                  ],
                  onChanged: (v) => setState(() => _cargoId = v),
                ),
                loading: () => const LinearProgressIndicator(),
                error: (_, __) => const Text('Erro ao carregar cargos'),
              ),
              const SizedBox(height: 12),

              // ── Nível + Tipo de Contrato ──
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _nivel,
                      decoration: const InputDecoration(labelText: 'Nível'),
                      items: _niveis.entries
                          .map((e) => DropdownMenuItem(
                              value: e.key, child: Text(e.value)))
                          .toList(),
                      onChanged: (v) =>
                          setState(() => _nivel = v ?? 'pleno'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _tipoContrato,
                      decoration:
                          const InputDecoration(labelText: 'Contrato'),
                      items: _contratos.entries
                          .map((e) => DropdownMenuItem(
                              value: e.key, child: Text(e.value)))
                          .toList(),
                      onChanged: (v) =>
                          setState(() => _tipoContrato = v ?? 'clt'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // ── Localidade + Remoto ──
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _localidade,
                      decoration:
                          const InputDecoration(labelText: 'Localidade'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilterChip(
                    label: const Text('Remoto'),
                    selected: _remoto,
                    onSelected: (v) => setState(() => _remoto = v),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // ── Faixa salarial + Posições ──
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _faixaSalarial,
                      decoration:
                          const InputDecoration(labelText: 'Faixa salarial'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 100,
                    child: TextFormField(
                      controller: _vagasQtd,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: 'Posições'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // ── Data de expiração ──
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event),
                title: Text(_expiraEm != null
                    ? 'Expira em: ${_dateFmt.format(_expiraEm!)}'
                    : 'Sem data de expiração'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_calendar),
                      onPressed: _pickDate,
                    ),
                    if (_expiraEm != null)
                      IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () =>
                            setState(() => _expiraEm = null),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // ── Descrição ──
              TextFormField(
                controller: _descricao,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Descrição da vaga',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 12),

              // ── Requisitos ──
              TextFormField(
                controller: _requisitos,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Requisitos',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
