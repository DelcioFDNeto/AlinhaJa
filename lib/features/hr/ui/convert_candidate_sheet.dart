import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alinha_ja/core/globals.dart';
import 'package:alinha_ja/features/hr/models/candidate_model.dart';
import 'package:alinha_ja/features/hr/models/employee_model.dart';
import 'package:alinha_ja/features/hr/providers/employee_provider.dart';
import 'package:alinha_ja/core/utils/friendly_error.dart';

/// RH-4.6/S078 — Converte candidato aprovado em funcionário
/// (RPC transacional: funcionário + vínculo + status contratado).
/// Retorna o id do funcionário criado via Navigator.pop.
class ConvertCandidateSheet extends ConsumerStatefulWidget {
  const ConvertCandidateSheet({super.key, required this.candidato});

  final CandidateModel candidato;

  @override
  ConsumerState<ConvertCandidateSheet> createState() =>
      _ConvertCandidateSheetState();
}

class _ConvertCandidateSheetState extends ConsumerState<ConvertCandidateSheet> {
  final _matricula = TextEditingController();
  final _cargaHoraria = TextEditingController();
  final _salario = TextEditingController();

  String _tipo = 'clt';
  DateTime _dataAdmissao = DateTime.now();
  String? _filialId;
  String? _departamentoId;
  String? _cargoId;
  bool _saving = false;

  @override
  void dispose() {
    _matricula.dispose();
    _cargaHoraria.dispose();
    _salario.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _saving = true);
    try {
      final funcionarioId =
          await ref.read(employeeServiceProvider).convertCandidate(
                candidatoId: widget.candidato.id,
                tipo: _tipo,
                dataAdmissao: _dataAdmissao,
                matricula: _matricula.text.trim().isEmpty
                    ? null
                    : _matricula.text.trim(),
                cargaHoraria: _cargaHoraria.text.trim().isEmpty
                    ? null
                    : _cargaHoraria.text.trim(),
                salario: _salario.text.trim().isEmpty
                    ? null
                    : _salario.text.trim(),
                filialId: _filialId,
                departamentoId: _departamentoId,
                cargoId: _cargoId,
              );
      if (mounted) Navigator.of(context).pop(funcionarioId);
    } catch (e) {
      Globals.showErrorSnackBar('Erro na conversão: ${friendlyError(e)}');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final org = ref.watch(orgStructureProvider).valueOrNull;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + bottomInset),
      child: ListView(
        shrinkWrap: true,
        children: [
          Text('Contratar ${widget.candidato.nome}',
              style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Cria a ficha de funcionário, o vínculo e marca o candidato '
            'como contratado — tudo em uma única transação.',
            style: TextStyle(color: theme.colorScheme.outline, fontSize: 13),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _tipo,
            decoration: const InputDecoration(labelText: 'Tipo de vínculo'),
            items: [
              for (final e in VinculoTipo.labels.entries)
                DropdownMenuItem(value: e.key, child: Text(e.value)),
            ],
            onChanged: (v) => setState(() => _tipo = v ?? 'clt'),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_rounded),
            title: const Text('Data de admissão'),
            subtitle: Text(
                '${_dataAdmissao.day.toString().padLeft(2, '0')}/'
                '${_dataAdmissao.month.toString().padLeft(2, '0')}/'
                '${_dataAdmissao.year}'),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _dataAdmissao,
                firstDate: DateTime.now().subtract(const Duration(days: 30)),
                lastDate: DateTime.now().add(const Duration(days: 90)),
              );
              if (picked != null) setState(() => _dataAdmissao = picked);
            },
          ),
          const SizedBox(height: 12),
          TextField(
              controller: _matricula,
              decoration: const InputDecoration(labelText: 'Matrícula')),
          const SizedBox(height: 12),
          TextField(
              controller: _cargaHoraria,
              decoration: const InputDecoration(
                  labelText: 'Carga horária (ex: 44h semanais)')),
          const SizedBox(height: 12),
          TextField(
              controller: _salario,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Salário', prefixText: 'R\$ ')),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _filialId,
            decoration: const InputDecoration(labelText: 'Filial'),
            items: [
              for (final b in org?['branches'] ?? [])
                DropdownMenuItem(
                    value: b['id'] as String, child: Text(b['name'] as String)),
            ],
            onChanged: (v) => setState(() => _filialId = v),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _departamentoId,
            decoration: const InputDecoration(labelText: 'Departamento'),
            items: [
              for (final d in org?['departments'] ?? [])
                DropdownMenuItem(
                    value: d['id'] as String, child: Text(d['name'] as String)),
            ],
            onChanged: (v) => setState(() => _departamentoId = v),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _cargoId,
            decoration: const InputDecoration(labelText: 'Cargo'),
            items: [
              for (final p in org?['positions'] ?? [])
                DropdownMenuItem(
                    value: p['id'] as String, child: Text(p['name'] as String)),
            ],
            onChanged: (v) => setState(() => _cargoId = v),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _saving ? null : _submit,
            icon: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.how_to_reg_rounded),
            label: const Text('Confirmar contratação'),
          ),
        ],
      ),
    );
  }
}
