import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:alinha_ja/core/constants.dart';
import 'package:alinha_ja/core/utils/permissions.dart';
import 'package:alinha_ja/core/supabase_client.dart';
import 'package:alinha_ja/core/providers/org_providers.dart';
import 'package:alinha_ja/features/profile/models/user_model.dart';
import 'package:alinha_ja/features/auth/providers/auth_provider.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  final UserModel targetUser;

  const EditProfileScreen({required this.targetUser, super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;

  String? _selectedBranchId;
  String? _selectedDepartmentId;
  String? _selectedJobPositionId;
  late String _selectedRole;
  bool _isLoading = false;

  final Map<String, String> _roles = AppPermissions.roleLabels;

  @override
  void initState() {
    super.initState();
    _checkSecurity();

    // Pré-preenche os dados
    _nameCtrl = TextEditingController(text: widget.targetUser.fullName);
    _selectedRole = widget.targetUser.roleLevel;
    _selectedDepartmentId = widget.targetUser.departmentId;
    _selectedJobPositionId = widget.targetUser.jobPositionId;
  }

  void _checkSecurity() {
    final user = ref.read(currentUserProvider).value;
    if (user == null || !AppPermissions.canEditOtherUsers(user.roleLevel)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Acesso Negado: Área restrita à TI.'),
              backgroundColor: AppConstants.danger,
            ),
          );
          if (GoRouter.of(context).canPop()) {
            context.pop();
          } else {
            context.go('/chats');
          }
        }
      });
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _updateUser() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedBranchId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, selecione uma filial.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await supabase.rpc('admin_update_user', params: {
        'p_target_user_id': widget.targetUser.id,
        'p_full_name': _nameCtrl.text.trim(),
        'p_branch_id': _selectedBranchId,
        'p_role_level': _selectedRole,
        'p_department_id': _selectedDepartmentId,
        'p_job_position_id': _selectedJobPositionId,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Perfil atualizado com sucesso!'),
            backgroundColor: AppConstants.success,
          ),
        );
        context.pop(); // Volta pra tela anterior
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao atualizar usuário: $e'),
            backgroundColor: AppConstants.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Helper para pré-selecionar a branch baseado no nome
  void _preselectBranch(List<Map<String, dynamic>> branches) {
    // Se não tem branchId no model (porque só trazemos o nome no query original)
    // buscaremos pelo branchName do targetUser
    if (_selectedBranchId == null && widget.targetUser.branchName != null) {
      final found = branches.firstWhere(
        (b) => b['name'] == widget.targetUser.branchName,
        orElse: () => <String, dynamic>{},
      );
      if (found.isNotEmpty) {
        _selectedBranchId = found['id'] as String;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final branchesState = ref.watch(branchesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Editar Colaborador'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: branchesState.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Erro ao carregar filiais:\n$e')),
          data: (branches) {
            if (branches.isEmpty) {
              return const Center(child: Text('Nenhuma filial cadastrada.'));
            }

            _preselectBranch(branches);

            return SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Editar Dados',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Atualizando informações de ${widget.targetUser.fullName}.',
                      style: const TextStyle(
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
                      onChanged: (val) =>
                          setState(() => _selectedBranchId = val),
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
                                labelText: 'Departamento',
                                prefixIcon:
                                    Icon(Icons.business_center_outlined),
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
                            );
                          },
                        );
                      },
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
                                labelText: 'Cargo / Posição',
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
                            );
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 32),

                    // Reset Password
                    OutlinedButton.icon(
                      onPressed: _showResetPasswordDialog,
                      icon: const Icon(Icons.lock_reset),
                      label: const Text('Redefinir Senha do Colaborador'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppConstants.danger,
                        side: const BorderSide(color: AppConstants.danger),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        textStyle: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Submit
                    FilledButton.icon(
                      onPressed: _isLoading ? null : _updateUser,
                      icon: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.save_rounded),
                      label: Text(
                          _isLoading ? 'Salvando...' : 'Salvar Alterações'),
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
      ),
    );
  }

  void _showResetPasswordDialog() {
    final passwordCtrl = TextEditingController();
    bool isResetting = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Redefinir Senha'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                      'Digite a nova senha provisória para este colaborador.'),
                  const SizedBox(height: 16),
                  TextField(
                    controller: passwordCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Nova Senha',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed:
                      isResetting ? null : () => Navigator.of(context).pop(),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: isResetting
                      ? null
                      : () async {
                          final newPassword = passwordCtrl.text;
                          if (newPassword.length < 6) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text(
                                      'A senha deve ter pelo menos 6 caracteres.')),
                            );
                            return;
                          }

                          setDialogState(() => isResetting = true);

                          try {
                            await supabase
                                .rpc('admin_update_user_password', params: {
                              'p_target_user_id': widget.targetUser.id,
                              'p_new_password': newPassword,
                            });

                            if (context.mounted) {
                              Navigator.of(context).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                      'Senha redefinida com sucesso! Compartilhe com o colaborador.'),
                                  backgroundColor: AppConstants.success,
                                ),
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Erro ao redefinir senha: $e'),
                                  backgroundColor: AppConstants.danger,
                                ),
                              );
                            }
                          } finally {
                            if (context.mounted) {
                              setDialogState(() => isResetting = false);
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppConstants.danger,
                      foregroundColor: Colors.white),
                  child: isResetting
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Redefinir'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
