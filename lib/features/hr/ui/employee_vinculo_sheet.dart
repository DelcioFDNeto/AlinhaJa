import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alinha_ja/core/globals.dart';
import 'package:alinha_ja/features/hr/models/employee_model.dart';
import 'package:alinha_ja/features/hr/providers/employee_provider.dart';
import 'package:alinha_ja/core/utils/friendly_error.dart';

/// RH-4.3 — Edição do vínculo de uma ficha já existente.
/// Complementa o EmployeeFormSheet (que só cria vínculo junto com a ficha):
/// aqui o RH corrige admissão, tipo, situação e lotação depois — inclusive
/// nas fichas importadas em massa a partir das contas do app, que nascem
/// com a data de corte da carga.
class EmployeeVinculoSheet extends ConsumerStatefulWidget {
  const EmployeeVinculoSheet({
    super.key,
    required this.funcionarioId,
    this.vinculo,
  });

  final String funcionarioId;

  /// Linha atual de `vinculo` (null = ficha ainda sem vínculo).
  final Map<String, dynamic>? vinculo;

  @override
  ConsumerState<EmployeeVinculoSheet> createState() =>
      _EmployeeVinculoSheetState();
}

class _EmployeeVinculoSheetState extends ConsumerState<EmployeeVinculoSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _matricula;
  late final TextEditingController _cargaHoraria;

  late String _tipo;
  late String _status;
  late DateTime _dataAdmissao;
  String? _filialId;
  String? _departamentoId;
  String? _cargoId;
  bool _saving = false;

  bool get _novo => widget.vinculo == null;

  @override
  void initState() {
    super.initState();
    final v = widget.vinculo;
    _matricula = TextEditingController(text: v?['matricula'] as String? ?? '');
    _cargaHoraria =
        TextEditingController(text: v?['carga_horaria'] as String? ?? '');
    _tipo = v?['tipo'] as String? ?? 'clt';
    _status = v?['status'] as String? ?? 'efetivo';
    _dataAdmissao = v?['data_admissao'] != null
        ? DateTime.parse(v!['data_admissao'] as String)
        : DateTime.now();
    _filialId = v?['filial_id'] as String?;
    _departamentoId = v?['departamento_id'] as String?;
    _cargoId = v?['cargo_id'] as String?;
  }

  @override
  void dispose() {
    _matricula.dispose();
    _cargaHoraria.dispose();
    super.dispose();
  }

  String? _trimOrNull(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref.read(employeeServiceProvider).saveVinculo(
        funcionarioId: widget.funcionarioId,
        vinculoId: widget.vinculo?['id'] as String?,
        dados: {
          'tipo': _tipo,
          'status': _status,
          'data_admissao': _dataAdmissao.toIso8601String().split('T').first,
          'matricula': _trimOrNull(_matricula),
          'carga_horaria': _trimOrNull(_cargaHoraria),
          'filial_id': _filialId,
          'departamento_id': _departamentoId,
          'cargo_id': _cargoId,
        },
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      Globals.showErrorSnackBar('Erro ao salvar o vínculo: ${friendlyError(e)}');
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
      child: Form(
        key: _formKey,
        child: ListView(
          shrinkWrap: true,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(_novo ? 'Registrar vínculo' : 'Editar vínculo',
                style: theme.textTheme.titleLarge),
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
            DropdownButtonFormField<String>(
              initialValue: _status,
              decoration: const InputDecoration(labelText: 'Situação'),
              items: [
                for (final e in VinculoStatus.labels.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) => setState(() => _status = v ?? 'efetivo'),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_rounded),
              title: const Text('Data de admissão'),
              subtitle: Text('${_dataAdmissao.day.toString().padLeft(2, '0')}/'
                  '${_dataAdmissao.month.toString().padLeft(2, '0')}/'
                  '${_dataAdmissao.year}'),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _dataAdmissao,
                  firstDate: DateTime(1980),
                  lastDate: DateTime.now().add(const Duration(days: 90)),
                );
                if (picked != null) setState(() => _dataAdmissao = picked);
              },
            ),
            // O saldo de férias é calculado a partir desta data (rh26).
            Text(
              'A data de admissão define o período aquisitivo de férias.',
              style:
                  TextStyle(fontSize: 12, color: theme.colorScheme.outline),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _matricula,
              decoration: const InputDecoration(labelText: 'Matrícula'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _cargaHoraria,
              decoration: const InputDecoration(
                  labelText: 'Carga horária (ex: 44h semanais)'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _filialId,
              decoration: const InputDecoration(labelText: 'Filial'),
              items: [
                for (final b in org?['branches'] ?? [])
                  DropdownMenuItem(
                      value: b['id'] as String,
                      child: Text(b['name'] as String)),
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
                      value: d['id'] as String,
                      child: Text(d['name'] as String)),
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
                      value: p['id'] as String,
                      child: Text(p['name'] as String)),
              ],
              onChanged: (v) => setState(() => _cargoId = v),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _saving ? null : _submit,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(_novo ? 'Registrar vínculo' : 'Salvar alterações'),
            ),
          ],
        ),
      ),
    );
  }
}
