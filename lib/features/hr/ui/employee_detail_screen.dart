import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:alinha_ja/core/globals.dart';
import 'package:alinha_ja/core/status_tokens.dart';
import 'package:alinha_ja/core/rbac/providers/rbac_provider.dart';
import 'package:alinha_ja/features/hr/models/employee_model.dart';
import 'package:alinha_ja/features/hr/providers/employee_provider.dart';
import 'package:alinha_ja/features/hr/providers/onboarding_provider.dart';
import 'package:alinha_ja/features/hr/models/onboarding_model.dart';
import 'package:alinha_ja/features/hr/ui/employee_vinculo_sheet.dart';
import 'package:alinha_ja/features/hr/ui/widgets/employee_expansion_sections.dart';
import 'package:alinha_ja/features/hr/ui/widgets/hr_empty_state.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:alinha_ja/core/utils/friendly_error.dart';

/// RH-4.2 — Ficha do funcionário: visão pública + seção sensível
/// carregada sob demanda via RPC (cada leitura é auditada — S008).
class EmployeeDetailScreen extends ConsumerWidget {
  const EmployeeDetailScreen({super.key, required this.funcionarioId});

  final String funcionarioId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(employeeDetailProvider(funcionarioId));

    return Scaffold(
      appBar: AppBar(title: const Text('Ficha do Funcionário')),
      body: detailAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Erro ao carregar a ficha.\n${friendlyError(e)}',
                textAlign: TextAlign.center),
          ),
        ),
        data: (employee) => _DetailBody(employee: employee),
      ),
    );
  }
}

class _DetailBody extends ConsumerWidget {
  const _DetailBody({required this.employee});

  final EmployeeModel employee;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    // Quem só enxerga funcionários (ex.: perfil Gestor) vê a ficha pública;
    // dados sensíveis, salário e dependentes exigem gerir o módulo — a
    // mesma regra das RPCs no banco.
    final canManage = ref.watch(
        rbacCanProvider((module: 'rh_funcionarios', action: 'manage')));
    final canViewOnboarding = ref.watch(
        rbacCanProvider((module: 'rh_onboarding', action: 'view')));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 32,
              backgroundImage: employee.fotoUrl != null
                  ? CachedNetworkImageProvider(employee.fotoUrl!, maxWidth: 320)
                  : null,
              child: employee.fotoUrl == null
                  ? Text(employee.initials,
                      style: const TextStyle(fontSize: 24))
                  : null,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(employee.nome, style: theme.textTheme.titleLarge),
                  if (employee.lotacao.isNotEmpty)
                    Text(employee.lotacao,
                        style: TextStyle(color: theme.colorScheme.outline)),
                  const SizedBox(height: 6),
                  Chip(
                    label: Text(EmployeeStatus.label(employee.status)),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            if (canManage)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded),
              onSelected: (status) => _changeStatus(context, ref, status),
              itemBuilder: (_) => [
                for (final e in EmployeeStatus.labels.entries)
                  if (e.key != employee.status)
                    PopupMenuItem(
                        value: e.key, child: Text('Marcar como ${e.value}')),
              ],
            ),
          ],
        ),
        const Divider(height: 32),

        // ── Vínculo (visão pública) ──────────────────────────
        _VinculoSection(employee: employee),
        const Divider(height: 32),

        // ── Acesso ao app (F1.2 — vínculo com usuário) ───────
        _AppAccessSection(employee: employee),
        const Divider(height: 32),

        if (canViewOnboarding) ...[
          // ── Período de Experiência (RH-5) ──────────────────
          if (employee.vinculoTipo == 'clt' ||
              employee.vinculoTipo == 'aprendiz')
            _ExperienceSection(funcionarioId: employee.id),
          const Divider(height: 32),

          // ── Onboarding (RH-5) ──────────────────────────────
          _OnboardingSection(funcionarioId: employee.id),
          const Divider(height: 32),
        ],

        if (canManage) ...[
          // ── Dados sensíveis (sob demanda, auditado) ────────
          _SensitiveSection(funcionarioId: employee.id),
          const Divider(height: 32),

          // ── Histórico salarial + Dependentes (Fase 8 / rh21)
          SalaryHistorySection(funcionarioId: employee.id),
          const Divider(height: 32),
          DependentesSection(funcionarioId: employee.id),
        ],
        const SizedBox(height: 32),
      ],
    );
  }

  Future<void> _changeStatus(
      BuildContext context, WidgetRef ref, String status) async {
    try {
      await ref.read(employeeServiceProvider).updateStatus(employee.id, status);
      ref.invalidate(employeeDetailProvider(employee.id));
      ref.invalidate(employeeListProvider);
    } catch (e) {
      Globals.showErrorSnackBar('Não foi possível alterar o status: ${friendlyError(e)}');
    }
  }
}

/// RH-4.3 — Vínculo (contrato) da ficha, editável pelo RH admin.
/// A ficha pode chegar aqui sem vínculo: é o caso das importadas em massa
/// a partir das contas do app, que ainda não têm admissão/lotação reais.
class _VinculoSection extends ConsumerWidget {
  const _VinculoSection({required this.employee});

  final EmployeeModel employee;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final dateFmt = DateFormat('dd/MM/yyyy');
    final isRhAdmin = ref.watch(rbacCanProvider((module: 'rh_funcionarios', action: 'manage')));
    final semVinculo = employee.vinculoId == null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Vínculo',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ),
            if (isRhAdmin && !semVinculo)
              TextButton.icon(
                onPressed: () => _openSheet(context, ref),
                icon: const Icon(Icons.edit, size: 18),
                label: const Text('Editar'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (semVinculo) ...[
          Text('Sem vínculo registrado.',
              style: TextStyle(color: theme.colorScheme.outline)),
          if (isRhAdmin) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _openSheet(context, ref),
              icon: const Icon(Icons.badge_outlined, size: 18),
              label: const Text('Registrar vínculo'),
            ),
          ],
        ] else ...[
          _InfoRow(
              icon: Icons.badge_outlined,
              value:
                  '${VinculoTipo.label(employee.vinculoTipo ?? '')} — ${VinculoStatus.label(employee.vinculoStatus ?? '')}'),
          if (employee.dataAdmissao != null)
            _InfoRow(
                icon: Icons.event_rounded,
                value: 'Admissão: ${dateFmt.format(employee.dataAdmissao!)}'),
          if ((employee.matricula ?? '').isNotEmpty)
            _InfoRow(
                icon: Icons.tag_rounded,
                value: 'Matrícula: ${employee.matricula}'),
        ],
      ],
    );
  }

  /// Carrega a linha de `vinculo` na hora de abrir: a view do resumo não
  /// traz os ids de filial/departamento/cargo que os dropdowns precisam.
  Future<void> _openSheet(BuildContext context, WidgetRef ref) async {
    Map<String, dynamic>? vinculo;
    try {
      vinculo =
          await ref.read(employeeServiceProvider).fetchVinculo(employee.id);
    } catch (e) {
      Globals.showErrorSnackBar('Não foi possível carregar o vínculo: ${friendlyError(e)}');
      return;
    }
    if (!context.mounted) return;

    final salvo = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => EmployeeVinculoSheet(
        funcionarioId: employee.id,
        vinculo: vinculo,
      ),
    );

    if (salvo == true) {
      ref.invalidate(employeeDetailProvider(employee.id));
      ref.invalidate(vinculoProvider(employee.id));
      ref.invalidate(employeeListProvider);
    }
  }
}

/// F1.2 — Acesso ao app: vínculo da ficha com um usuário da org.
/// Fecha o ciclo candidato → funcionário → usuário (self-service).
class _AppAccessSection extends ConsumerWidget {
  const _AppAccessSection({required this.employee});

  final EmployeeModel employee;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isRhAdmin = ref.watch(rbacCanProvider((module: 'rh_funcionarios', action: 'manage')));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Acesso ao app',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        if (employee.userId == null) ...[
          Text('Sem usuário vinculado.',
              style: TextStyle(color: theme.colorScheme.outline)),
          if (isRhAdmin) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _openLinkSheet(context, ref),
              icon: const Icon(Icons.person_add_alt, size: 18),
              label: const Text('Vincular usuário'),
            ),
          ],
        ] else
          _LinkedUserTile(
            userId: employee.userId!,
            canUnlink: isRhAdmin,
            onUnlink: () => _unlink(context, ref),
          ),
      ],
    );
  }

  Future<void> _openLinkSheet(BuildContext context, WidgetRef ref) async {
    final linked = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _LinkUserSheet(funcionarioId: employee.id),
    );
    if (linked == true) {
      ref.invalidate(employeeDetailProvider(employee.id));
      ref.invalidate(employeeListProvider);
    }
  }

  Future<void> _unlink(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Desvincular usuário?'),
        content: const Text(
            'O funcionário perde a associação com o usuário do app. '
            'Você pode vincular novamente depois.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Desvincular')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(employeeServiceProvider).desvincularUsuario(employee.id);
      ref.invalidate(employeeDetailProvider(employee.id));
      ref.invalidate(employeeListProvider);
    } catch (e) {
      Globals.showErrorSnackBar('Não foi possível desvincular: ${friendlyError(e)}');
    }
  }
}

class _LinkedUserTile extends ConsumerWidget {
  const _LinkedUserTile({
    required this.userId,
    required this.canUnlink,
    required this.onUnlink,
  });

  final String userId;
  final bool canUnlink;
  final VoidCallback onUnlink;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final userAsync = ref.watch(linkedUserProvider(userId));

    return userAsync.when(
      loading: () => const LinearProgressIndicator(),
      error: (e, _) => Text('Erro ao carregar o usuário: ${friendlyError(e)}'),
      data: (u) {
        final nome = (u?['full_name'] as String?) ?? 'Usuário';
        final email = (u?['email'] as String?) ?? '';
        final avatar = u?['avatar_url'] as String?;
        return Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            leading: CircleAvatar(
              backgroundImage: avatar != null ? CachedNetworkImageProvider(avatar, maxWidth: 320) : null,
              child: avatar == null
                  ? Text(nome.isNotEmpty ? nome[0].toUpperCase() : '?')
                  : null,
            ),
            title: Text('Vinculado a $nome',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: email.isNotEmpty
                ? Text(email,
                    style: TextStyle(color: theme.colorScheme.outline))
                : null,
            trailing: canUnlink
                ? TextButton(
                    onPressed: onUnlink, child: const Text('Desvincular'))
                : null,
          ),
        );
      },
    );
  }
}

/// Bottom sheet de busca e seleção do usuário a vincular.
class _LinkUserSheet extends ConsumerStatefulWidget {
  const _LinkUserSheet({required this.funcionarioId});

  final String funcionarioId;

  @override
  ConsumerState<_LinkUserSheet> createState() => _LinkUserSheetState();
}

class _LinkUserSheetState extends ConsumerState<_LinkUserSheet> {
  final _search = TextEditingController();
  Timer? _debounce;
  String _term = '';
  bool _linking = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _term = v.trim());
    });
  }

  Future<void> _link(String userId, String nome) async {
    setState(() => _linking = true);
    try {
      await ref
          .read(employeeServiceProvider)
          .vincularUsuario(widget.funcionarioId, userId);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      Globals.showErrorSnackBar('Não foi possível vincular $nome: ${friendlyError(e)}');
      if (mounted) setState(() => _linking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final usersAsync = ref.watch(linkableUsersProvider(_term));
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Text('Vincular usuário do app',
                  style: theme.textTheme.titleLarge),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Somente usuários da organização que ainda não estão '
                'vinculados a outro funcionário.',
                style: TextStyle(
                    fontSize: 13, color: theme.colorScheme.outline),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: TextField(
                controller: _search,
                onChanged: _onChanged,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Buscar por nome ou e-mail…',
                  prefixIcon: Icon(Icons.search),
                  filled: true,
                ),
              ),
            ),
            Expanded(
              child: usersAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Erro na busca: ${friendlyError(e)}')),
                data: (users) {
                  if (users.isEmpty) {
                    return const HrEmptyBlock(
                      icone: Icons.person_search,
                      titulo: 'Nenhum usuário disponível',
                      dica:
                          'O vínculo liga a ficha a uma conta do app — é ele '
                          'que faz a pessoa enxergar os próprios holerites e '
                          'documentos. Só aparecem aqui contas ativas ainda '
                          'sem ficha: crie o usuário no Painel '
                          'Administrativo, ou refine a busca.',
                      altura: 180,
                    );
                  }
                  return ListView.builder(
                    itemCount: users.length,
                    itemBuilder: (context, i) {
                      final u = users[i];
                      final nome = (u['full_name'] as String?) ?? 'Usuário';
                      final email = (u['email'] as String?) ?? '';
                      final avatar = u['avatar_url'] as String?;
                      return ListTile(
                        enabled: !_linking,
                        leading: CircleAvatar(
                          backgroundImage:
                              avatar != null ? CachedNetworkImageProvider(avatar, maxWidth: 320) : null,
                          child: avatar == null
                              ? Text(nome.isNotEmpty
                                  ? nome[0].toUpperCase()
                                  : '?')
                              : null,
                        ),
                        title: Text(nome),
                        subtitle: email.isNotEmpty ? Text(email) : null,
                        trailing: const Icon(Icons.link, size: 20),
                        onTap: () => _link(u['id'] as String, nome),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SensitiveSection extends ConsumerStatefulWidget {
  const _SensitiveSection({required this.funcionarioId});

  final String funcionarioId;

  @override
  ConsumerState<_SensitiveSection> createState() => _SensitiveSectionState();
}

class _SensitiveSectionState extends ConsumerState<_SensitiveSection> {
  EmployeeSensitiveData? _data;
  bool _loading = false;

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await ref
          .read(employeeServiceProvider)
          .fetchSensitiveData(widget.funcionarioId);
      setState(() => _data = data);
    } catch (e) {
      Globals.showErrorSnackBar('Acesso negado ou erro: ${friendlyError(e)}');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isRhAdmin = ref.watch(rbacCanProvider((module: 'rh_funcionarios', action: 'manage')));
    final dateFmt = DateFormat('dd/MM/yyyy');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Dados sensíveis',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ),
            if (_data != null && isRhAdmin)
              TextButton.icon(
                onPressed: () => _openEdit(context),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Editar'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (_data == null)
          OutlinedButton.icon(
            onPressed: _loading ? null : _load,
            icon: _loading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.lock_open_rounded, size: 18),
            label: const Text('Visualizar dados sensíveis (acesso auditado)'),
          )
        else if (!_data!.exists)
          const HrEmptyBlock(
            icone: Icons.lock_outline,
            titulo: 'Nenhum dado sensível cadastrado',
            dica:
                'CPF, RG, data de nascimento e dados bancários ficam '
                'cifrados e à parte do resto da ficha. Use "Editar ficha" '
                'para preenchê-los — todo acesso a estes campos é '
                'registrado em log de auditoria (LGPD).',
            altura: 160,
          )
        else ...[
          if ((_data!.cpf ?? '').isNotEmpty)
            _InfoRow(icon: Icons.pin_outlined, value: 'CPF: ${_data!.cpf}'),
          if ((_data!.rg ?? '').isNotEmpty)
            _InfoRow(icon: Icons.pin_outlined, value: 'RG: ${_data!.rg}'),
          if (_data!.dataNascimento != null)
            _InfoRow(
                icon: Icons.cake_outlined,
                value:
                    'Nascimento: ${dateFmt.format(_data!.dataNascimento!)}'),
          if ((_data!.emailPessoal ?? '').isNotEmpty)
            _InfoRow(
                icon: Icons.mail_outline_rounded,
                value: _data!.emailPessoal!),
          if ((_data!.telefone ?? '').isNotEmpty)
            _InfoRow(icon: Icons.phone_outlined, value: _data!.telefone!),
          if ((_data!.estadoCivil ?? '').isNotEmpty)
            _InfoRow(
                icon: Icons.favorite_outline_rounded,
                value: 'Estado civil: ${_data!.estadoCivil}'),
          if (_data!.dependentes != null)
            _InfoRow(
                icon: Icons.family_restroom_rounded,
                value: 'Dependentes: ${_data!.dependentes}'),
          if (_data!.pcd)
            _InfoRow(
                icon: Icons.accessible_rounded,
                value: 'PCD${(_data!.tipoDeficiencia ?? '').isNotEmpty ? ' — ${_data!.tipoDeficiencia}' : ''}'),
          if ((_data!.dadosBancarios ?? '').isNotEmpty)
            _InfoRow(
                icon: Icons.account_balance_outlined,
                value: 'Dados bancários: ${_data!.dadosBancarios}'),
          if ((_data!.salario ?? '').isNotEmpty)
            _InfoRow(
                icon: Icons.payments_outlined,
                value: 'Salário: R\$ ${_data!.salario}'),
        ],
      ],
    );
  }

  Future<void> _openEdit(BuildContext context) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _SensitiveEditSheet(
        funcionarioId: widget.funcionarioId,
        initial: _data!,
      ),
    );
    if (saved == true) _load();
  }
}

class _SensitiveEditSheet extends ConsumerStatefulWidget {
  const _SensitiveEditSheet({required this.funcionarioId, required this.initial});

  final String funcionarioId;
  final EmployeeSensitiveData initial;

  @override
  ConsumerState<_SensitiveEditSheet> createState() =>
      _SensitiveEditSheetState();
}

class _SensitiveEditSheetState extends ConsumerState<_SensitiveEditSheet> {
  late final _cpf = TextEditingController(text: widget.initial.cpf ?? '');
  late final _rg = TextEditingController(text: widget.initial.rg ?? '');
  late final _email =
      TextEditingController(text: widget.initial.emailPessoal ?? '');
  late final _telefone =
      TextEditingController(text: widget.initial.telefone ?? '');
  late final _estadoCivil =
      TextEditingController(text: widget.initial.estadoCivil ?? '');
  late final _dependentes = TextEditingController(
      text: widget.initial.dependentes?.toString() ?? '');
  late final _dadosBancarios =
      TextEditingController(text: widget.initial.dadosBancarios ?? '');
  late final _salario =
      TextEditingController(text: widget.initial.salario ?? '');
  late DateTime? _nascimento = widget.initial.dataNascimento;
  late bool _pcd = widget.initial.pcd;
  late final _tipoDeficiencia =
      TextEditingController(text: widget.initial.tipoDeficiencia ?? '');
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [
      _cpf, _rg, _email, _telefone, _estadoCivil,
      _dependentes, _dadosBancarios, _salario, _tipoDeficiencia,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _saving = true);
    try {
      await ref.read(employeeServiceProvider).saveSensitiveData(
        widget.funcionarioId,
        {
          'cpf': _cpf.text.trim(),
          'rg': _rg.text.trim(),
          'data_nascimento':
              _nascimento?.toIso8601String().split('T').first,
          'email_pessoal': _email.text.trim(),
          'telefone': _telefone.text.trim(),
          'estado_civil': _estadoCivil.text.trim(),
          'dependentes': int.tryParse(_dependentes.text.trim()),
          'pcd': _pcd,
          'tipo_deficiencia': _tipoDeficiencia.text.trim(),
          'dados_bancarios': _dadosBancarios.text.trim(),
          'salario': _salario.text.trim(),
        },
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      final msg = e.toString().contains('CPF inválido')
          ? 'CPF inválido — confira os dígitos.'
          : e.toString().contains('uq_funcionario_org_cpf')
              ? 'Já existe um funcionário com este CPF.'
              : 'Erro ao salvar: ${friendlyError(e)}';
      Globals.showErrorSnackBar(msg);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final dateFmt = DateFormat('dd/MM/yyyy');

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + bottomInset),
      child: ListView(
        shrinkWrap: true,
        children: [
          Text('Editar dados sensíveis', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text('Alterações são registradas no log de auditoria.',
              style: TextStyle(
                  color: theme.colorScheme.outline, fontSize: 13)),
          const SizedBox(height: 16),
          TextField(
              controller: _cpf,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'CPF')),
          const SizedBox(height: 12),
          TextField(
              controller: _rg,
              decoration: const InputDecoration(labelText: 'RG')),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.cake_outlined),
            title: const Text('Data de nascimento'),
            subtitle: Text(_nascimento != null
                ? dateFmt.format(_nascimento!)
                : 'Não informada'),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _nascimento ?? DateTime(1990),
                firstDate: DateTime(1930),
                lastDate: DateTime.now(),
              );
              if (picked != null) setState(() => _nascimento = picked);
            },
          ),
          const SizedBox(height: 12),
          TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration:
                  const InputDecoration(labelText: 'E-mail pessoal')),
          const SizedBox(height: 12),
          TextField(
              controller: _telefone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Telefone')),
          const SizedBox(height: 12),
          TextField(
              controller: _estadoCivil,
              decoration: const InputDecoration(labelText: 'Estado civil')),
          const SizedBox(height: 12),
          TextField(
              controller: _dependentes,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Dependentes')),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Pessoa com deficiência (PCD)'),
            value: _pcd,
            onChanged: (v) => setState(() => _pcd = v),
          ),
          if (_pcd)
            TextField(
                controller: _tipoDeficiencia,
                decoration:
                    const InputDecoration(labelText: 'Tipo de deficiência')),
          const SizedBox(height: 12),
          TextField(
              controller: _dadosBancarios,
              decoration: const InputDecoration(
                  labelText: 'Dados bancários (banco/agência/conta)')),
          const SizedBox(height: 12),
          TextField(
              controller: _salario,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Salário', prefixText: 'R\$ ')),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _saving ? null : _submit,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Salvar'),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.value});

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.outline),
          const SizedBox(width: 10),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _ExperienceSection extends ConsumerWidget {
  const _ExperienceSection({required this.funcionarioId});

  final String funcionarioId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final expAsync = ref.watch(periodoExperienciaProvider(funcionarioId));
    final isRhAdmin = ref.watch(rbacCanProvider((module: 'rh_funcionarios', action: 'manage')));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Período de Experiência',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        expAsync.when(
          loading: () => const CircularProgressIndicator(),
          error: (e, _) => Text('Erro: ${friendlyError(e)}'),
          data: (exp) {
            if (exp == null) {
              return Text('Sem período de experiência registrado.',
                  style: TextStyle(color: theme.colorScheme.outline));
            }

            final isDone = !exp.emAndamento;
            return Card(
              margin: EdgeInsets.zero,
              color: isDone ? theme.colorScheme.surfaceContainerHigh : theme.colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(ExperienciaFase.label(exp.fase),
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        Chip(
                          label: Text(ExperienciaResultado.label(exp.resultado)),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text('Data Limite: ${DateFormat('dd/MM/yyyy').format(exp.limiteAtual)}'),
                    if (exp.emAndamento)
                      Text('Faltam ${exp.diasRestantes} dias',
                          style: TextStyle(
                              color: exp.diasRestantes <= 7 ? context.statusTokens.danger : theme.colorScheme.primary,
                              fontWeight: FontWeight.bold)),
                    if (isRhAdmin && exp.emAndamento) ...[
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        children: [
                          if (exp.fase == 'primeiro_periodo')
                            OutlinedButton(
                              onPressed: () => _decidir(context, ref, exp.id, 'prorrogar'),
                              child: const Text('Prorrogar'),
                            ),
                          OutlinedButton(
                            onPressed: () => _decidir(context, ref, exp.id, 'efetivar'),
                            child: const Text('Efetivar'),
                          ),
                          OutlinedButton(
                            onPressed: () => _decidir(context, ref, exp.id, 'desligar'),
                            style: OutlinedButton.styleFrom(foregroundColor: context.statusTokens.danger),
                            child: const Text('Desligar'),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Future<void> _decidir(BuildContext context, WidgetRef ref, String id, String decisao) async {
    try {
      await ref.read(onboardingServiceProvider).decidirExperiencia(id, decisao);
      ref.invalidate(periodoExperienciaProvider(funcionarioId));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: ${friendlyError(e)}')));
      }
    }
  }
}

class _OnboardingSection extends ConsumerWidget {
  const _OnboardingSection({required this.funcionarioId});

  final String funcionarioId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final execAsync = ref.watch(onboardingExecucaoProvider(funcionarioId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Onboarding',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        execAsync.when(
          loading: () => const CircularProgressIndicator(),
          error: (e, _) => Text('Erro: ${friendlyError(e)}'),
          data: (exec) {
            if (exec == null) {
              return const HrEmptyBlock(
                icone: Icons.checklist,
                titulo: 'Nenhum onboarding em andamento',
                dica:
                    'O onboarding é o roteiro de integração da pessoa '
                    '(documentos, contrato, treinamentos). Cadastre um '
                    'template em RH > Templates de Onboarding e marque-o '
                    'como padrão: ele passa a ser aplicado em toda '
                    'admissão.',
                altura: 170,
              );
            }

            return Card(
              margin: EdgeInsets.zero,
              child: Column(
                children: [
                  ListTile(
                    title: Text('Template: ${exec.templateNome ?? "Manual"}'),
                    subtitle: Text('Status: ${OnboardingStatus.label(exec.status)}'),
                    trailing: CircularProgressIndicator(
                      value: exec.progresso / 100,
                      backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    ),
                  ),
                  _OnboardingItemsList(
                    execucaoId: exec.id,
                    emAndamento: exec.emAndamento,
                    funcionarioId: funcionarioId,
                  ),
                  if (exec.emAndamento)
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: ElevatedButton(
                        onPressed: () async {
                          try {
                            await ref.read(onboardingServiceProvider).concluirOnboarding(exec.id);
                            ref.invalidate(onboardingExecucaoProvider(funcionarioId));
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: ${friendlyError(e)}')));
                            }
                          }
                        },
                        child: const Text('Concluir Onboarding'),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _OnboardingItemsList extends ConsumerWidget {
  const _OnboardingItemsList({
    required this.execucaoId,
    required this.emAndamento,
    required this.funcionarioId,
  });

  final String execucaoId;
  final bool emAndamento;
  final String funcionarioId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(onboardingItemsProvider(execucaoId));

    return itemsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(16.0),
        child: LinearProgressIndicator(),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(16.0),
        child: Text('Erro: ${friendlyError(e)}'),
      ),
      data: (items) {
        if (items.isEmpty) return const SizedBox.shrink();
        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final item = items[index];
            return CheckboxListTile(
              title: Text(item.titulo,
                  style: TextStyle(
                      decoration: item.concluido ? TextDecoration.lineThrough : null)),
              subtitle: Text(
                  '${OnboardingResponsavel.label(item.responsavel)}${item.prazo != null ? ' • Prazo: ${DateFormat('dd/MM/yy').format(item.prazo!)}' : ''}'),
              value: item.concluido,
              onChanged: emAndamento
                  ? (val) async {
                      final status = val == true ? 'concluido' : 'pendente';
                      try {
                        await ref
                            .read(onboardingServiceProvider)
                            .atualizarItem(item.id, status);
                        ref.invalidate(onboardingItemsProvider(execucaoId));
                        ref.invalidate(onboardingExecucaoProvider(funcionarioId));
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context)
                              .showSnackBar(SnackBar(content: Text('Erro: ${friendlyError(e)}')));
                        }
                      }
                    }
                  : null,
            );
          },
        );
      },
    );
  }
}

