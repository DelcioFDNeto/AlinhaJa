import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alinha_ja/core/globals.dart';
import 'package:alinha_ja/features/hr/models/employee_model.dart';
import 'package:alinha_ja/features/hr/providers/employee_provider.dart';
import 'package:alinha_ja/core/utils/friendly_error.dart';

/// RH-4.3 — Cadastro de funcionário (dados públicos + vínculo).
/// Dados sensíveis são preenchidos depois, na ficha (RPC própria).
class EmployeeFormSheet extends ConsumerStatefulWidget {
  const EmployeeFormSheet({super.key});

  @override
  ConsumerState<EmployeeFormSheet> createState() => _EmployeeFormSheetState();
}

class _EmployeeFormSheetState extends ConsumerState<EmployeeFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nome = TextEditingController();
  final _matricula = TextEditingController();
  final _cargaHoraria = TextEditingController();

  String _tipo = 'clt';
  DateTime _dataAdmissao = DateTime.now();
  String? _filialId;
  String? _departamentoId;
  String? _cargoId;
  bool _saving = false;

  @override
  void dispose() {
    _nome.dispose();
    _matricula.dispose();
    _cargaHoraria.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref.read(employeeServiceProvider).createEmployee(
        nome: _nome.text.trim(),
        vinculo: {
          'tipo': _tipo,
          'data_admissao':
              _dataAdmissao.toIso8601String().split('T').first,
          'matricula':
              _matricula.text.trim().isEmpty ? null : _matricula.text.trim(),
          'carga_horaria': _cargaHoraria.text.trim().isEmpty
              ? null
              : _cargaHoraria.text.trim(),
          'filial_id': _filialId,
          'departamento_id': _departamentoId,
          'cargo_id': _cargoId,
        },
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      Globals.showErrorSnackBar('Erro ao cadastrar funcionário: ${friendlyError(e)}');
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
            Text('Novo funcionário', style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nome,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nome completo *'),
              validator: (v) => (v == null || v.trim().length < 3)
                  ? 'Informe o nome (mínimo 3 letras)'
                  : null,
            ),
            const SizedBox(height: 12),
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
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now().add(const Duration(days: 90)),
                );
                if (picked != null) setState(() => _dataAdmissao = picked);
              },
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
                  : const Text('Cadastrar funcionário'),
            ),
          ],
        ),
      ),
    );
  }
}
