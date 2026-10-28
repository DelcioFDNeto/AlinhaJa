import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alinha_ja/core/globals.dart';
import 'package:alinha_ja/features/hr/providers/talent_bank_provider.dart';
import 'package:alinha_ja/core/utils/friendly_error.dart';

/// RH-1.3 — Cadastro manual de candidato pelo RH (indicações, e-mail, etc.).
class CandidateFormSheet extends ConsumerStatefulWidget {
  const CandidateFormSheet({super.key});

  @override
  ConsumerState<CandidateFormSheet> createState() => _CandidateFormSheetState();
}

class _CandidateFormSheetState extends ConsumerState<CandidateFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nome = TextEditingController();
  final _email = TextEditingController();
  final _telefone = TextEditingController();
  final _cidade = TextEditingController();
  final _estado = TextEditingController();
  final _area = TextEditingController();
  final _cargo = TextEditingController();
  final _pretensao = TextEditingController();

  String _nivel = 'pleno';
  String _fonte = 'upload_manual';
  bool _lgpdOk = false;
  bool _saving = false;

  Uint8List? _cvBytes;
  String? _cvFileName;

  static const _maxCvBytes = 5 * 1024 * 1024;

  @override
  void dispose() {
    for (final c in [
      _nome,
      _email,
      _telefone,
      _cidade,
      _estado,
      _area,
      _cargo,
      _pretensao
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickCv() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'docx'],
      withData: true,
    );
    final file = result?.files.firstOrNull;
    if (file == null || file.bytes == null) return;
    if (file.size > _maxCvBytes) {
      Globals.showErrorSnackBar('O currículo deve ter no máximo 5MB.');
      return;
    }
    setState(() {
      _cvBytes = file.bytes;
      _cvFileName = file.name;
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_lgpdOk) {
      Globals.showErrorSnackBar(
          'Confirme que o candidato consentiu com o uso dos dados (LGPD).');
      return;
    }

    setState(() => _saving = true);
    try {
      await ref.read(talentBankServiceProvider).createCandidate(
        fields: {
          'nome': _nome.text.trim(),
          'email': _email.text.trim().toLowerCase(),
          'telefone':
              _telefone.text.trim().isEmpty ? null : _telefone.text.trim(),
          'cidade': _cidade.text.trim().isEmpty ? null : _cidade.text.trim(),
          'estado': _estado.text.trim().isEmpty
              ? null
              : _estado.text.trim().toUpperCase(),
          'area_interesse':
              _area.text.trim().isEmpty ? null : _area.text.trim(),
          'cargo_pretendido':
              _cargo.text.trim().isEmpty ? null : _cargo.text.trim(),
          'nivel': _nivel,
          'fonte': _fonte,
          'pretensao_salarial': double.tryParse(
              _pretensao.text.trim().replaceAll('.', '').replaceAll(',', '.')),
        },
        cvBytes: _cvBytes,
        cvFileName: _cvFileName,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      final msg = e.toString().contains('uq_candidato_org_email') ||
              e.toString().contains('duplicate key')
          ? 'Já existe um candidato com este e-mail.'
          : 'Erro ao cadastrar candidato: ${friendlyError(e)}';
      Globals.showErrorSnackBar(msg);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

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
            Text('Novo candidato', style: theme.textTheme.titleLarge),
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
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'E-mail *'),
              validator: (v) {
                final email = v?.trim() ?? '';
                final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
                return ok ? null : 'E-mail inválido';
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _telefone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Telefone'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: _cidade,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Cidade'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _estado,
                    maxLength: 2,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                        labelText: 'UF', counterText: ''),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _area,
              decoration:
                  const InputDecoration(labelText: 'Área de interesse'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _cargo,
              decoration:
                  const InputDecoration(labelText: 'Cargo pretendido'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _nivel,
              decoration: const InputDecoration(labelText: 'Nível'),
              items: const [
                DropdownMenuItem(value: 'estagio', child: Text('Estágio')),
                DropdownMenuItem(value: 'junior', child: Text('Júnior')),
                DropdownMenuItem(value: 'pleno', child: Text('Pleno')),
                DropdownMenuItem(value: 'senior', child: Text('Sênior')),
                DropdownMenuItem(
                    value: 'lideranca', child: Text('Liderança/Gestão')),
              ],
              onChanged: (v) => setState(() => _nivel = v ?? 'pleno'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _fonte,
              decoration: const InputDecoration(labelText: 'Fonte'),
              items: const [
                DropdownMenuItem(
                    value: 'upload_manual', child: Text('Upload manual')),
                DropdownMenuItem(value: 'indicacao', child: Text('Indicação')),
              ],
              onChanged: (v) => setState(() => _fonte = v ?? 'upload_manual'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _pretensao,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Pretensão salarial (opcional)',
                  prefixText: 'R\$ '),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _pickCv,
              icon: Icon(_cvFileName == null
                  ? Icons.upload_file_rounded
                  : Icons.check_circle_rounded),
              label: Text(_cvFileName ?? 'Anexar currículo (PDF/DOCX, 5MB)'),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              value: _lgpdOk,
              onChanged: (v) => setState(() => _lgpdOk = v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'O candidato consentiu com o tratamento dos seus dados '
                'pessoais para fins de recrutamento (LGPD). *',
                style: TextStyle(fontSize: 13),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _saving ? null : _submit,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Cadastrar candidato'),
            ),
          ],
        ),
      ),
    );
  }
}
