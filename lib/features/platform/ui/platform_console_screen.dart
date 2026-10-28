import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:alinha_ja/core/config/app_env.dart';
import 'package:alinha_ja/core/constants.dart';
import 'package:alinha_ja/core/modules/module_descriptor.dart';
import 'package:alinha_ja/core/modules/module_registry.dart';
import 'package:alinha_ja/features/auth/providers/auth_provider.dart';
import 'package:alinha_ja/features/platform/providers/platform_provider.dart';
import 'package:alinha_ja/core/brand/org_identity.dart';

/// Console do Dono da Aplicação: gestão de empresas (tenants).
///
/// Acesso restrito a `is_platform_owner`. Permite cadastrar novas empresas
/// (org + primeiro admin) e ativar/desativar tenants. É o único ponto do app
/// que atravessa organizações — todas as operações são guardadas no banco por
/// `fn_is_platform_owner()`.
class PlatformConsoleScreen extends ConsumerWidget {
  const PlatformConsoleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOwner = ref.watch(isPlatformOwnerProvider);
    if (!isOwner) {
      // Na build de admin (host separado) não há para onde redirecionar — o
      // usuário logado simplesmente não é dono da plataforma. Mostra acesso
      // negado com opção de trocar de conta, sem loop de redirect.
      if (AppEnv.isPlatformAdminBuild) {
        return const _AccessDeniedScreen();
      }
      // Fora da build de admin: defesa em profundidade (a rota já bloqueia).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go('/chats');
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final orgsAsync = ref.watch(platformOrganizationsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Console de Plataforma')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showDialog(
          context: context,
          builder: (_) => const _CreateOrgDialog(),
        ),
        icon: const Icon(Icons.add_business_outlined),
        label: const Text('Nova empresa'),
        backgroundColor: context.corMarca,
        foregroundColor: Colors.white,
      ),
      body: orgsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Não foi possível carregar as empresas.\n$e',
                textAlign: TextAlign.center),
          ),
        ),
        data: (orgs) {
          if (orgs.isEmpty) {
            return const Center(child: Text('Nenhuma empresa cadastrada.'));
          }
          return RefreshIndicator(
            onRefresh: () => ref.refresh(platformOrganizationsProvider.future),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: orgs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) => _OrgCard(org: orgs[i]),
            ),
          );
        },
      ),
    );
  }
}

/// Exibida na build de admin quando o usuário logado não é dono da plataforma.
/// Evita o loop de redirect (o app inteiro aponta para `/plataforma`) e oferece
/// trocar de conta.
class _AccessDeniedScreen extends ConsumerWidget {
  const _AccessDeniedScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_outline, size: 64, color: AppConstants.secondaryText),
              const SizedBox(height: 16),
              Text('Acesso restrito', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              const Text(
                'Esta conta não tem permissão para o Console de Plataforma.\n'
                'Entre com uma conta de dono da plataforma.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () async {
                  await ref.read(authRepositoryProvider).signOut();
                  if (context.mounted) context.go('/login');
                },
                icon: const Icon(Icons.logout),
                label: const Text('Trocar de conta'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Cartão de uma empresa na lista do console.
class _OrgCard extends ConsumerWidget {
  const _OrgCard({required this.org});

  final PlatformOrganization org;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: context.corMarca.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.apartment_rounded,
                  color: context.corMarca),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(org.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text('/${org.slug} · ${org.userCount} usuário(s)',
                      style: const TextStyle(
                          color: AppConstants.secondaryText, fontSize: 12)),
                  if (org.cnpj != null && org.cnpj!.isNotEmpty)
                    Text('CNPJ ${org.cnpj}',
                        style: const TextStyle(
                            color: AppConstants.secondaryText, fontSize: 12)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(org.isActive ? 'Ativa' : 'Inativa',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: org.isActive
                            ? AppConstants.success
                            : AppConstants.secondaryText)),
                Switch(
                  value: org.isActive,
                  activeThumbColor: AppConstants.success,
                  onChanged: (v) async {
                    if (!v) {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Desativar empresa'),
                          content: Text(
                              'Tem certeza que deseja desativar "${org.name}"? '
                              'Todos os usuários desta organização perderão acesso.'),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Cancelar')),
                            FilledButton(
                                style: FilledButton.styleFrom(
                                    backgroundColor: AppConstants.danger),
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Desativar')),
                          ],
                        ),
                      );
                      if (confirmed != true) return;
                    }
                    try {
                      await ref
                          .read(platformRepositoryProvider)
                          .setOrgActive(org.id, v);
                      ref.invalidate(platformOrganizationsProvider);
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text('Erro ao atualizar status: $e'),
                              backgroundColor: AppConstants.danger),
                        );
                      }
                    }
                  },
                ),
              ],
            ),
              ],
            ),
            const Divider(height: 24),
            _OrgModulesFooter(org: org),
          ],
        ),
      ),
    );
  }
}

/// Rodapé do cartão: resumo dos módulos contratados + acesso à gestão.
class _OrgModulesFooter extends StatelessWidget {
  const _OrgModulesFooter({required this.org});

  final PlatformOrganization org;

  @override
  Widget build(BuildContext context) {
    final total = licensableModuleIds.length;
    final active = org.enabledModuleIds
        .where((id) => licensableModuleIds.contains(id))
        .length;
    return Row(
      children: [
        const Icon(Icons.widgets_outlined,
            size: 18, color: AppConstants.secondaryText),
        const SizedBox(width: 8),
        Expanded(
          child: Text('$active de $total módulos contratados',
              style: const TextStyle(
                  fontSize: 12, color: AppConstants.secondaryText)),
        ),
        TextButton.icon(
          icon: const Icon(Icons.tune_rounded, size: 18),
          label: const Text('Gerenciar'),
          onPressed: () => showDialog(
            context: context,
            builder: (_) => _OrgModulesDialog(org: org),
          ),
        ),
      ],
    );
  }
}

/// Diálogo de liberação de módulos licenciáveis por empresa.
///
/// Lista os módulos de [licensableModules] agrupados por seção, com um switch
/// por módulo. Salva em `organizations.settings.modules` via
/// `platform_set_org_modules` (guardado por `fn_is_platform_owner()`).
class _OrgModulesDialog extends ConsumerStatefulWidget {
  const _OrgModulesDialog({required this.org});

  final PlatformOrganization org;

  @override
  ConsumerState<_OrgModulesDialog> createState() => _OrgModulesDialogState();
}

class _OrgModulesDialogState extends ConsumerState<_OrgModulesDialog> {
  late final Set<String> _selected;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    // Só considera ids que ainda existem no registro (ignora módulos removidos).
    _selected = widget.org.enabledModuleIds
        .where((id) => licensableModuleIds.contains(id))
        .toSet();
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      await ref
          .read(platformRepositoryProvider)
          .setOrgModules(widget.org.id, _selected.toList());
      ref.invalidate(platformOrganizationsProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Módulos atualizados.')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Erro ao salvar módulos: $e'),
              backgroundColor: AppConstants.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Agrupa por seção preservando a ordem de declaração do registro.
    final sections = <ModuleSection, List<ModuleDescriptor>>{};
    for (final m in licensableModules) {
      sections.putIfAbsent(m.section, () => []).add(m);
    }

    return AlertDialog(
      title: Text('Módulos · ${widget.org.name}'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Ative apenas os módulos que a empresa contratou. '
                'Comunicação e Painel Admin acompanham o plano.',
                style:
                    TextStyle(fontSize: 12, color: AppConstants.secondaryText),
              ),
              const SizedBox(height: 8),
              for (final entry in sections.entries) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 4, left: 4),
                  child: Text(
                    entry.key.title ?? entry.key.name.toUpperCase(),
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                        color: AppConstants.secondaryText),
                  ),
                ),
                for (final m in entry.value)
                  SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    secondary: Icon(m.icon, color: context.corMarca),
                    title: Text(m.title),
                    value: _selected.contains(m.id),
                    activeThumbColor: AppConstants.success,
                    onChanged: _isSaving
                        ? null
                        : (v) => setState(() {
                              if (v) {
                                _selected.add(m.id);
                              } else {
                                _selected.remove(m.id);
                              }
                            }),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Salvar'),
        ),
      ],
    );
  }
}

/// Diálogo de cadastro de uma nova empresa + seu primeiro admin.
class _CreateOrgDialog extends ConsumerStatefulWidget {
  const _CreateOrgDialog();

  @override
  ConsumerState<_CreateOrgDialog> createState() => _CreateOrgDialogState();
}

class _CreateOrgDialogState extends ConsumerState<_CreateOrgDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _slugCtrl = TextEditingController();
  final _cnpjCtrl = TextEditingController();
  final _adminNameCtrl = TextEditingController();
  final _adminEmailCtrl = TextEditingController();
  final _adminPassCtrl = TextEditingController();

  // Perfil legal — capturado no cadastro porque o primeiro colaborador da
  // empresa aceita os documentos antes de alguém lembrar de preenchê-los.
  final _legalNameCtrl = TextEditingController();
  final _enderecoCtrl = TextEditingController();
  final _dpoNomeCtrl = TextEditingController();
  final _dpoEmailCtrl = TextEditingController();
  final _vigenciaCtrl = TextEditingController();
  final _comarcaCtrl = TextEditingController();

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _adminPassCtrl.text = _randomPassword();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _slugCtrl.dispose();
    _cnpjCtrl.dispose();
    _adminNameCtrl.dispose();
    _adminEmailCtrl.dispose();
    _adminPassCtrl.dispose();
    _legalNameCtrl.dispose();
    _enderecoCtrl.dispose();
    _dpoNomeCtrl.dispose();
    _dpoEmailCtrl.dispose();
    _vigenciaCtrl.dispose();
    _comarcaCtrl.dispose();
    super.dispose();
  }

  String _randomPassword() {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#%&*';
    final rnd = Random.secure();
    return String.fromCharCodes(
        Iterable.generate(10, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))));
  }

  /// Data de vigência dos documentos. Gravada em ISO (`YYYY-MM-DD`), que é o
  /// formato que `OrgLegalProfile` converte para dd/MM/yyyy na leitura.
  Future<void> _pickVigencia() async {
    final hoje = DateTime.now();
    final escolhida = await showDatePicker(
      context: context,
      initialDate: hoje,
      firstDate: DateTime(hoje.year - 1),
      lastDate: DateTime(hoje.year + 5),
      helpText: 'A partir de quando os documentos valem',
    );
    if (escolhida == null) return;
    final m = escolhida.month.toString().padLeft(2, '0');
    final d = escolhida.day.toString().padLeft(2, '0');
    _vigenciaCtrl.text = '${escolhida.year}-$m-$d';
  }

  /// Deriva um slug a partir do nome (minúsculas, hífens, sem acento simples).
  void _syncSlug(String name) {
    if (_slugCtrl.text.isNotEmpty) return; // não sobrescreve edição manual
    final slug = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    _slugCtrl.text = slug;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    final repo = ref.read(platformRepositoryProvider);
    try {
      String? opcional(TextEditingController c) {
        final t = c.text.trim();
        return t.isEmpty ? null : t;
      }

      final orgId = await repo.createOrganization(
        name: _nameCtrl.text.trim(),
        slug: _slugCtrl.text.trim(),
        legalName: opcional(_legalNameCtrl),
        cnpj: opcional(_cnpjCtrl),
        legal: {
          'endereco': opcional(_enderecoCtrl),
          'dpo_nome': opcional(_dpoNomeCtrl),
          'dpo_email': opcional(_dpoEmailCtrl),
          'vigencia': opcional(_vigenciaCtrl),
          'comarca': opcional(_comarcaCtrl),
        },
      );
      await repo.createOrgAdmin(
        orgId: orgId,
        email: _adminEmailCtrl.text.trim(),
        password: _adminPassCtrl.text,
        fullName: _adminNameCtrl.text.trim(),
      );
      // Empresa nova nasce com todos os módulos licenciáveis ligados; o dono
      // desliga depois o que não foi contratado.
      await repo.setOrgModules(orgId, licensableModuleIds);
      ref.invalidate(platformOrganizationsProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
      _showCredentials();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Erro ao cadastrar empresa: $e'),
              backgroundColor: AppConstants.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showCredentials() {
    final email = _adminEmailCtrl.text.trim();
    final pass = _adminPassCtrl.text;
    final name = _nameCtrl.text.trim();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Empresa cadastrada'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('A empresa "$name" foi criada com o primeiro administrador.'),
            const SizedBox(height: 12),
            Text('Admin: $email'),
            Text('Senha provisória: $pass',
                style: const TextStyle(fontFamily: 'monospace')),
            const SizedBox(height: 8),
            const Text(
              'Copie as credenciais e envie ao administrador da empresa.',
              style: TextStyle(fontSize: 12, color: AppConstants.secondaryText),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('Copiar'),
            onPressed: () {
              Clipboard.setData(ClipboardData(
                  text: 'Acesso ${AppConstants.appName}\nEmpresa: $name\n'
                      'E-mail: $email\nSenha provisória: $pass'));
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(
                    content: Text('Credenciais copiadas!'),
                    duration: Duration(seconds: 2)),
              );
            },
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Concluído'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nova empresa'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Nome da empresa',
                      prefixIcon: Icon(Icons.business_outlined)),
                  onChanged: _syncSlug,
                  validator: (v) =>
                      v!.trim().isEmpty ? 'Informe o nome' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _slugCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Slug (usado em /carreiras/:slug)',
                      prefixIcon: Icon(Icons.link_outlined)),
                  validator: (v) {
                    final s = v!.trim();
                    if (s.isEmpty) return 'Informe o slug';
                    if (!RegExp(r'^[a-z0-9]([a-z0-9-]*[a-z0-9])?$').hasMatch(s)) {
                      return 'Use minúsculas, números e hífen';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                const Divider(height: 28),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Dados legais (LGPD)',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 4),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Preenchem os Termos de Uso e a Política de Privacidade '
                    'desta empresa. Sem eles, o primeiro colaborador aceita um '
                    'documento com os campos em branco.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _legalNameCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Razão social',
                      prefixIcon: Icon(Icons.corporate_fare_outlined)),
                  validator: (v) =>
                      v!.trim().isEmpty ? 'Informe a razão social' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _cnpjCtrl,
                  decoration: const InputDecoration(
                      labelText: 'CNPJ',
                      prefixIcon: Icon(Icons.badge_outlined)),
                  validator: (v) =>
                      v!.trim().isEmpty ? 'Informe o CNPJ' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _enderecoCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Endereço da sede',
                      prefixIcon: Icon(Icons.location_city_outlined)),
                  validator: (v) =>
                      v!.trim().isEmpty ? 'Informe o endereço' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _dpoNomeCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Encarregado (DPO)',
                      prefixIcon: Icon(Icons.shield_outlined)),
                  validator: (v) =>
                      v!.trim().isEmpty ? 'Informe o Encarregado' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _dpoEmailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                      labelText: 'E-mail do Encarregado',
                      helperText: 'Canal público do titular (Art. 41)',
                      prefixIcon: Icon(Icons.alternate_email_outlined)),
                  validator: (v) => v!.trim().isEmpty || !v.contains('@')
                      ? 'Informe um e-mail válido'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _vigenciaCtrl,
                  readOnly: true,
                  decoration: const InputDecoration(
                      labelText: 'Data de vigência dos documentos',
                      prefixIcon: Icon(Icons.event_outlined)),
                  onTap: _pickVigencia,
                  validator: (v) =>
                      v!.trim().isEmpty ? 'Informe a data de vigência' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _comarcaCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Comarca do foro (opcional)',
                      prefixIcon: Icon(Icons.gavel_outlined)),
                ),
                const Divider(height: 28),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Primeiro administrador',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _adminNameCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Nome do admin',
                      prefixIcon: Icon(Icons.person_outline)),
                  validator: (v) =>
                      v!.trim().isEmpty ? 'Informe o nome do admin' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _adminEmailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                      labelText: 'E-mail do admin',
                      prefixIcon: Icon(Icons.email_outlined)),
                  validator: (v) => v!.trim().isEmpty || !v.contains('@')
                      ? 'Informe um e-mail válido'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _adminPassCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Senha provisória',
                      prefixIcon: Icon(Icons.lock_outline)),
                  validator: (v) =>
                      v!.length < 8 ? 'Mínimo de 8 caracteres' : null,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _isLoading ? null : _submit,
          child: _isLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Cadastrar'),
        ),
      ],
    );
  }
}
