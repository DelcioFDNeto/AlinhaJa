import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:alinha_ja/core/constants.dart';
import 'package:alinha_ja/core/supabase_client.dart';
import 'package:alinha_ja/core/utils/permissions.dart';
import 'package:alinha_ja/core/providers/org_providers.dart';
import 'package:alinha_ja/features/admin/ui/org_structure_management_sheet.dart';
import 'package:flutter/services.dart';
import 'dart:math';


class UserCreateTab extends ConsumerStatefulWidget {
  const UserCreateTab({super.key});

  @override
  ConsumerState<UserCreateTab> createState() => _UserCreateTabState();
}

class _UserCreateTabState extends ConsumerState<UserCreateTab> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  String? _selectedDepartmentId;
  String? _selectedJobPositionId;

  String? _selectedBranchId;
  String _selectedRole = 'member';
  String? _selectedSexo;
  DateTime? _dataNascimento;
  bool _isLoading = false;

  /// Níveis hierárquicos de acesso.
  /// TI Admin: acesso total (cadastro, manutenção, técnico).
  /// Diretor/Gerente: acesso administrativo completo, sem funções técnicas.
  /// Supervisor: pode criar grupos, não cria canais.
  /// Colaborador: acesso básico de leitura/envio.
  final Map<String, String> _roles = AppPermissions.roleLabels;

  @override
  void initState() {
    super.initState();
    _passwordCtrl.text = _generateRandomPassword();
  }

  String _generateRandomPassword() {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#%&*';
    final rnd = Random();
    return String.fromCharCodes(Iterable.generate(
        8, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))));
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _createUser() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedBranchId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, selecione uma filial.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await supabase.rpc('admin_create_user', params: {
        'p_email': _emailCtrl.text.trim(),
        'p_password': _passwordCtrl.text,
        'p_full_name': _nameCtrl.text.trim(),
        'p_branch_id': _selectedBranchId,
        'p_role_level': _selectedRole,
        'p_department_id': _selectedDepartmentId,
        'p_job_position_id': _selectedJobPositionId,
        'p_sexo': _selectedSexo,
        'p_data_nascimento':
            _dataNascimento?.toIso8601String().split('T').first,
      });

      if (mounted) {
        final createdName = _nameCtrl.text.trim();
        final createdEmail = _emailCtrl.text.trim();
        final createdPassword = _passwordCtrl.text;

        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.check_circle_rounded,
                    color: AppConstants.success, size: 28),
                SizedBox(width: 10),
                Text('Colaborador Cadastrado',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                    'O usuário foi criado com sucesso no banco de dados corporativo.'),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .primaryContainer
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.1)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Nome: $createdName',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text('E-mail: $createdEmail'),
                      const SizedBox(height: 4),
                      Text('Senha Provisória: $createdPassword',
                          style: const TextStyle(
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Copie as credenciais abaixo para enviar ao colaborador antes de fechar esta tela.',
                  style: TextStyle(
                      fontSize: 12, color: AppConstants.secondaryText),
                ),
              ],
            ),
            actions: [
              TextButton.icon(
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('Copiar Credenciais'),
                onPressed: () {
                  Clipboard.setData(ClipboardData(
                    text:
                        'Acesso ao ${AppConstants.appName}:\n\nNome: $createdName\nE-mail: $createdEmail\nSenha Provisória: $createdPassword',
                  ));
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(
                        content: Text(
                            'Credenciais copiadas para a área de transferência!')),
                  );
                },
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Concluído'),
              ),
            ],
          ),
        );
        // Limpa o formulário após criar
        _nameCtrl.clear();
        _emailCtrl.clear();
        _passwordCtrl.text = _generateRandomPassword();
        setState(() {
          _selectedDepartmentId = null;
          _selectedJobPositionId = null;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao criar usuário: $e'),
            backgroundColor: AppConstants.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final branchesState = ref.watch(branchesProvider);

    return SafeArea(
      child: branchesState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erro ao carregar filiais:\n$e')),
        data: (branches) {
          if (branches.isEmpty) {
            return const Center(child: Text('Nenhuma filial cadastrada.'));
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Cadastrar Colaborador',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Este usuário será criado instantaneamente e adicionado ao quadro corporativo.',
                    style: TextStyle(
                        color: AppConstants.secondaryText, fontSize: 13),
                  ),
                  const SizedBox(height: 24),

                  // Nome
                  TextFormField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nome Completo',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    validator: (v) =>
                        v!.trim().isEmpty ? 'Preencha o nome' : null,
                  ),
                  const SizedBox(height: 16),

                  // Email
                  TextFormField(
                    controller: _emailCtrl,
                    decoration: const InputDecoration(
                      labelText: 'E-mail Corporativo',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) => v!.trim().isEmpty || !v.contains('@')
                        ? 'Informe um e-mail válido'
                        : null,
                  ),
                  const SizedBox(height: 16),

                  // Senha Padrão
                  TextFormField(
                    controller: _passwordCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Senha Inicial (O colaborador usa para logar)',
                      prefixIcon: Icon(Icons.lock_outline),
                    ),
                    validator: (v) =>
                        v!.length < 6 ? 'Mínimo de 6 caracteres' : null,
                  ),
                  const SizedBox(height: 24),

                  // Filial Dropdown
                  DropdownButtonFormField<String>(
                    initialValue: _selectedBranchId,
                    decoration: const InputDecoration(
                      labelText: 'Filial de Lotação',
                      prefixIcon: Icon(Icons.location_city_outlined),
                    ),
                    items: branches.map((b) {
                      return DropdownMenuItem<String>(
                        value: b['id'],
                        child: Text(b['name']),
                      );
                    }).toList(),
                    onChanged: (val) => setState(() => _selectedBranchId = val),
                  ),
                  const SizedBox(height: 16),

                  // Cargo Hierárquico
                  DropdownButtonFormField<String>(
                    initialValue: _selectedRole,
                    decoration: const InputDecoration(
                      labelText: 'Nível de Acesso (Cargo Hierárquico)',
                      prefixIcon: Icon(Icons.admin_panel_settings_outlined),
                    ),
                    items: _roles.entries.map((entry) {
                      return DropdownMenuItem<String>(
                        value: entry.key,
                        child: Text(entry.value),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _selectedRole = val);
                    },
                  ),
                  const SizedBox(height: 16),

                  // Sexo (Dropdown)
                  DropdownButtonFormField<String>(
                    initialValue: _selectedSexo,
                    decoration: const InputDecoration(
                      labelText: 'Sexo',
                      prefixIcon: Icon(Icons.wc_rounded),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'M', child: Text('Masculino')),
                      DropdownMenuItem(value: 'F', child: Text('Feminino')),
                      DropdownMenuItem(value: 'O', child: Text('Outro')),
                    ],
                    onChanged: (val) => setState(() => _selectedSexo = val),
                  ),
                  const SizedBox(height: 16),

                  // Data de Nascimento
                  GestureDetector(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _dataNascimento ?? DateTime(2000, 1, 1),
                        firstDate: DateTime(1950),
                        lastDate: DateTime.now(),
                        locale: const Locale('pt', 'BR'),
                      );
                      if (picked != null) {
                        setState(() => _dataNascimento = picked);
                      }
                    },
                    child: AbsorbPointer(
                      child: TextFormField(
                        decoration: InputDecoration(
                          labelText: 'Data de Nascimento',
                          prefixIcon: const Icon(Icons.cake_rounded),
                          hintText: _dataNascimento != null
                              ? '${_dataNascimento!.day.toString().padLeft(2, '0')}/${_dataNascimento!.month.toString().padLeft(2, '0')}/${_dataNascimento!.year}'
                              : 'dd/mm/aaaa',
                        ),
                        controller: TextEditingController(
                          text: _dataNascimento != null
                              ? '${_dataNascimento!.day.toString().padLeft(2, '0')}/${_dataNascimento!.month.toString().padLeft(2, '0')}/${_dataNascimento!.year}'
                              : '',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Departamento (dinâmico do banco)
                  Consumer(
                    builder: (context, ref, _) {
                      final deptsAsync = ref.watch(departmentsProvider);
                      return deptsAsync.when(
                        loading: () => const LinearProgressIndicator(),
                        error: (e, _) => Text('Erro: $e'),
                        data: (depts) {
                          // Garante que o valor atual exista na lista
                          final validDeptIds =
                              depts.map((d) => d['id'] as String).toSet();
                          final effectiveDeptId =
                              validDeptIds.contains(_selectedDepartmentId)
                                  ? _selectedDepartmentId
                                  : null;
                          return DropdownButtonFormField<String>(
                            initialValue: effectiveDeptId,
                            decoration: const InputDecoration(
                              labelText: 'Departamento / Setor',
                              prefixIcon: Icon(Icons.business_center_outlined),
                            ),
                            items: depts
                                .map((d) => DropdownMenuItem<String>(
                                      value: d['id'] as String,
                                      child: Text(d['name'] as String),
                                    ))
                                .toList(),
                            onChanged: (val) => setState(() {
                              _selectedDepartmentId = val;
                              _selectedJobPositionId = null;
                            }),
                            validator: (v) =>
                                v == null ? 'Selecione um departamento' : null,
                          );
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () {
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          useSafeArea: true,
                          builder: (context) => const OrgStructureManagementSheet(),
                        );
                      },
                      icon: const Icon(Icons.settings_outlined, size: 18),
                      label: const Text('Gerenciar Departamentos e Cargos'),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Cargo / Posição (dinâmico, filtrado pelo departamento)
                  Consumer(
                    builder: (context, ref, _) {
                      final jobsAsync = ref
                          .watch(jobPositionsProvider(_selectedDepartmentId));
                      return jobsAsync.when(
                        loading: () => const LinearProgressIndicator(),
                        error: (e, _) => Text('Erro: $e'),
                        data: (jobs) {
                          final validJobIds =
                              jobs.map((j) => j['id'] as String).toSet();
                          final effectiveJobId =
                              validJobIds.contains(_selectedJobPositionId)
                                  ? _selectedJobPositionId
                                  : null;
                          return DropdownButtonFormField<String>(
                            initialValue: effectiveJobId,
                            decoration: const InputDecoration(
                              labelText: 'Cargo / Função',
                              prefixIcon: Icon(Icons.badge_outlined),
                            ),
                            items: jobs
                                .map((j) => DropdownMenuItem<String>(
                                      value: j['id'] as String,
                                      child: Text(j['name'] as String),
                                    ))
                                .toList(),
                            onChanged: (val) =>
                                setState(() => _selectedJobPositionId = val),
                            validator: (v) =>
                                v == null ? 'Selecione um cargo' : null,
                          );
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 32),

                  // Submit
                  FilledButton.icon(
                    onPressed: _isLoading ? null : _createUser,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.person_add_alt_1_rounded),
                    label: Text(_isLoading
                        ? 'Cadastrando...'
                        : 'Registrar Funcionário'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      textStyle: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
