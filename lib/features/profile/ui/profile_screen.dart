import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:alinha_ja/core/constants.dart';
import 'package:alinha_ja/core/supabase_client.dart';
import 'package:alinha_ja/core/utils/permissions.dart';
import 'package:alinha_ja/core/providers/org_providers.dart';
import 'package:go_router/go_router.dart';
import 'package:alinha_ja/features/auth/providers/auth_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:alinha_ja/features/chat/data/image_compress_stub.dart'
    if (dart.library.js_interop) 'package:alinha_ja/features/chat/data/image_compress_web.dart';
import 'package:alinha_ja/core/ui/widgets/responsive_width_container.dart';
import 'package:alinha_ja/core/brand/org_identity.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isSaving = false;
  bool _isInitialized = false;
  bool _sensitiveDataLoaded = false;

  late TextEditingController _nameCtrl;
  late TextEditingController _cpfCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController
      _dataNascimentoCtrl; // Fix: proper controller for date field
  DateTime? _dataNascimento;
  String? _selectedSexo;
  String? _selectedDepartmentId;
  String? _selectedJobPositionId;
  String? _selectedBranchId;
  String? _selectedRole;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _cpfCtrl = TextEditingController();
    _phoneCtrl = TextEditingController();
    _dataNascimentoCtrl = TextEditingController();
    _loadOwnSensitiveData();
  }

  /// Busca CPF, nascimento, sexo e telefone do PRÓPRIO usuário.
  ///
  /// Esses campos não vêm mais no SELECT de `users` — o privilégio de coluna
  /// foi revogado para `authenticated` (migrations 20260803170000 e
  /// 20260903140000) porque a
  /// RLS libera a leitura de todas as linhas da org, o que expunha o CPF de
  /// todo mundo para todo mundo. A RPC devolve apenas os do dono da sessão.
  Future<void> _loadOwnSensitiveData() async {
    try {
      final rows = await supabase.rpc('get_my_sensitive_profile');
      if (!mounted) return;
      final list = rows as List;
      if (list.isEmpty) {
        _sensitiveDataLoaded = true;
        return;
      }

      final data = Map<String, dynamic>.from(list.first as Map);
      setState(() {
        _sensitiveDataLoaded = true;
        _cpfCtrl.text = (data['cpf'] as String?) ?? '';
        _phoneCtrl.text = (data['phone'] as String?) ?? '';
        _selectedSexo = data['sexo'] as String?;
        final nascimento = data['data_nascimento'] as String?;
        if (nascimento != null) {
          _dataNascimento = DateTime.tryParse(nascimento);
          if (_dataNascimento != null) {
            _dataNascimentoCtrl.text =
                '${_dataNascimento!.day.toString().padLeft(2, '0')}/'
                '${_dataNascimento!.month.toString().padLeft(2, '0')}/'
                '${_dataNascimento!.year}';
          }
        }
      });
    } catch (e) {
      _sensitiveDataLoaded = false;
      debugPrint('Não foi possível carregar os dados pessoais: $e');
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _cpfCtrl.dispose();
    _phoneCtrl.dispose();
    _dataNascimentoCtrl.dispose();
    super.dispose();
  }

  Future<void> _updateAvatar(String userId) async {
    try {
      final picker = ImagePicker();
      final image =
          await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
      if (image == null) return;

      setState(() => _isSaving = true);

      final bytes = await image.readAsBytes();
      final compressedBytes = kIsWeb
          ? await compressImageWeb(bytes, quality: 60, maxWidth: 400)
          : await FlutterImageCompress.compressWithList(
              bytes,
              minWidth: 400,
              minHeight: 400,
              quality: 60,
              format: CompressFormat.webp,
            );

      final fileName =
          '${userId}_${DateTime.now().millisecondsSinceEpoch}.webp';

      // Bucket dedicado e público: mantém o avatar renderizável por URL
      // direta enquanto chat-media (mídia de conversa) é privado.
      final storage = supabase.storage.from(AppConstants.avatarBucket);
      await storage.uploadBinary(
        fileName,
        compressedBytes,
        fileOptions: const FileOptions(contentType: 'image/webp', upsert: true),
      );

      final avatarUrl = storage.getPublicUrl(fileName);
      await supabase
          .from('users')
          .update({'avatar_url': avatarUrl}).eq('id', userId);
      ref.invalidate(currentUserProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Foto atualizada!'),
            backgroundColor: AppConstants.success));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Erro: $e'), backgroundColor: AppConstants.danger));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// Verifica se uma string é um UUID válido
  bool _isValidUuid(String? value) {
    if (value == null) return false;
    final uuidRegex = RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
    return uuidRegex.hasMatch(value);
  }

  Future<void> _saveProfile(String userId) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      final updates = <String, dynamic>{
        'full_name': _nameCtrl.text.trim(),
        'department_id': _selectedDepartmentId,
        'job_position_id': _selectedJobPositionId,
      };

      // SEGURANÇA (Achado 11): Só inclui dados sensíveis no update se a carga
      // inicial teve sucesso. Se ela falhou, os controllers estão vazios e
      // enviar estes campos sobrescreveria CPF, telefone, sexo e nascimento com vazio/nulo.
      if (_sensitiveDataLoaded) {
        updates['cpf'] = _cpfCtrl.text.replaceAll(RegExp(r'\D'), '');
        updates['phone'] = _phoneCtrl.text.replaceAll(RegExp(r'\D'), '');
        updates['sexo'] = _selectedSexo;
        if (_dataNascimento != null) {
          updates['data_nascimento'] =
              _dataNascimento!.toIso8601String().split('T')[0];
        }
      }

      // Atualiza filial e nível de acesso (apenas ti_admin consegue editar)
      // Só salva branch_id se for um UUID válido do banco
      if (_selectedBranchId != null && _isValidUuid(_selectedBranchId)) {
        updates['branch_id'] = _selectedBranchId!;
      }
      if (_selectedRole != null) updates['role_level'] = _selectedRole!;

      await supabase.from('users').update(updates).eq('id', userId);
      ref.invalidate(currentUserProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Perfil atualizado com sucesso!'),
            backgroundColor: AppConstants.success));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Erro ao salvar: $e'),
            backgroundColor: AppConstants.danger));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(currentUserProvider);
    final theme = Theme.of(context);

    return userAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, __) => Center(child: Text('Erro: $err')),
      data: (user) {
        if (user == null) {
          return const Center(child: Text('Sua conta não foi encontrada.'));
        }

        // Initialize form data once
        if (!_isInitialized) {
          _nameCtrl.text = user.fullName;
          // CPF, nascimento, sexo e telefone são preenchidos por
          // _loadOwnSensitiveData() via RPC — não vêm mais em `user`.
          // Reatribuí-los aqui apagaria o que a RPC carregou.
          _selectedDepartmentId = user.departmentId;
          _selectedJobPositionId = user.jobPositionId;
          _selectedBranchId = user.branchId;
          _selectedRole = user.roleLevel;
          _isInitialized = true;
        }

        final isTiAdmin = AppPermissions.canEditOtherUsers(user.roleLevel);
        final branchesState = ref.watch(branchesProvider);
        final branches = branchesState.value ?? [];

        // Garante que se o usuário tiver uma filial que não está na lista atual,
        // ela seja injetada para que o Dropdown não quebre e não resete a conta.
        if (_selectedBranchId != null && branches.isNotEmpty) {
          final exists = branches.any((b) => b['id'] == _selectedBranchId);
          if (!exists) {
            branches.add({
              'id': _selectedBranchId,
              'name': 'Filial Retida ($_selectedBranchId)'
            });
          }
        }

        // Garante que o Role exista
        final validRoles = AppPermissions.assignableRoles.toList();
        if (_selectedRole != null && !validRoles.contains(_selectedRole)) {
          validRoles.add(_selectedRole!);
        }

        // Garante que Sexo não limpe à toa
        final validSexos = ['M', 'F', 'O'];
        if (_selectedSexo != null && !validSexos.contains(_selectedSexo)) {
          validSexos.add(_selectedSexo!);
        }

        // Usa as mesmas listas do cadastro (kDepartamentos e kCargos) - REMOVIDO PARA USAR DO BANCO

        return Scaffold(
          appBar: AppBar(
            title: const Text('Meu Perfil',
                style: TextStyle(fontWeight: FontWeight.w700)),
            centerTitle: false,
            backgroundColor: theme.colorScheme.surface,
            elevation: 0,
            scrolledUnderElevation: 2,
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _isSaving ? null : () => _saveProfile(user.id),
            icon: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.save_rounded),
            label: Text(_isSaving ? 'Salvando...' : 'Salvar Perfil'),
            backgroundColor: context.corMarca,
            foregroundColor: Colors.white,
          ),
          body: ResponsiveWidthContainer(
            child: Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(
                    left: 24, right: 24, top: 24, bottom: 100),
                child: Column(
                  children: [
                    // AVATAR
                    GestureDetector(
                      onTap: _isSaving ? null : () => _updateAvatar(user.id),
                      child: Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          CircleAvatar(
                            radius: 56,
                            backgroundColor: theme.colorScheme.primary
                                .withValues(alpha: 0.1),
                            backgroundImage: user.avatarUrl != null
                                ? CachedNetworkImageProvider(user.avatarUrl!, maxWidth: 320)
                                : null,
                            child: user.avatarUrl == null
                                ? Text(user.initials,
                                    style: TextStyle(
                                        fontSize: 40,
                                        fontWeight: FontWeight.bold,
                                        color: theme.colorScheme.primary))
                                : null,
                          ),
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                                color: theme.colorScheme.primary,
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: theme.colorScheme.surface,
                                    width: 3)),
                            child: const Icon(Icons.camera_alt_rounded,
                                color: Colors.white, size: 18),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),
                    Text(supabase.auth.currentUser?.email ?? 'Sem e-mail',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: theme.colorScheme.outline)),

                    const SizedBox(height: 32),

                    // DADOS PESSOAIS
                    Card(
                      elevation: 0,
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.3),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.person_outline,
                                    size: 20, color: theme.colorScheme.primary),
                                const SizedBox(width: 8),
                                Text('Dados Pessoais',
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(
                                            fontWeight: FontWeight.bold)),
                              ],
                            ),
                            const SizedBox(height: 20),
                            TextFormField(
                              controller: _nameCtrl,
                              decoration: const InputDecoration(
                                  labelText: 'Nome Completo',
                                  prefixIcon: Icon(Icons.badge_outlined)),
                              validator: (v) => v!.trim().isEmpty
                                  ? 'Preencha seu nome'
                                  : null,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _cpfCtrl,
                              decoration: const InputDecoration(
                                  labelText: 'CPF',
                                  prefixIcon: Icon(Icons.credit_card_outlined)),
                              keyboardType: TextInputType.number,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _phoneCtrl,
                              decoration: const InputDecoration(
                                  labelText: 'Telefone Corporativo',
                                  prefixIcon: Icon(Icons.phone_outlined)),
                              keyboardType: TextInputType.phone,
                            ),
                            const SizedBox(height: 16),
                            GestureDetector(
                              onTap: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate:
                                      _dataNascimento ?? DateTime(2000, 1, 1),
                                  firstDate: DateTime(1950),
                                  lastDate: DateTime.now(),
                                  locale: const Locale('pt', 'BR'),
                                );
                                if (picked != null) {
                                  setState(() {
                                    _dataNascimento = picked;
                                    _dataNascimentoCtrl.text =
                                        '${picked.day.toString().padLeft(2, '0')}/${picked.month.toString().padLeft(2, '0')}/${picked.year}';
                                  });
                                }
                              },
                              child: AbsorbPointer(
                                child: TextFormField(
                                  decoration: const InputDecoration(
                                      labelText: 'Data de Nascimento',
                                      prefixIcon: Icon(Icons.cake_outlined)),
                                  controller: _dataNascimentoCtrl,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            DropdownButtonFormField<String>(
                              initialValue: _selectedSexo,
                              decoration: const InputDecoration(
                                  labelText: 'Sexo',
                                  prefixIcon: Icon(Icons.wc_outlined)),
                              items: validSexos.map((s) {
                                String label = s == 'M'
                                    ? 'Masculino'
                                    : s == 'F'
                                        ? 'Feminino'
                                        : s == 'O'
                                            ? 'Outro'
                                            : s;
                                return DropdownMenuItem(
                                    value: s, child: Text(label));
                              }).toList(),
                              onChanged: (val) =>
                                  setState(() => _selectedSexo = val),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Bloco de Suporte de TI
                    Card(
                      elevation: 0,
                      margin: const EdgeInsets.only(bottom: 24),
                      color: theme.colorScheme.tertiaryContainer
                          .withValues(alpha: 0.3),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                            color: theme.colorScheme.tertiary
                                .withValues(alpha: 0.2)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.headset_mic_rounded,
                                    color: theme.colorScheme.tertiary),
                                const SizedBox(width: 8),
                                Text('Suporte T.I.',
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                            color: theme.colorScheme.tertiary)),
                              ],
                            ),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: () => context.push('/support/help'),
                              icon: const Icon(Icons.help_center_rounded),
                              label: const Text('Central de Ajuda & Suporte'),
                              style: FilledButton.styleFrom(
                                  backgroundColor: theme.colorScheme.tertiary,
                                  foregroundColor:
                                      theme.colorScheme.onTertiary),
                            ),
                            if (isTiAdmin) ...[
                              const SizedBox(height: 8),
                              FilledButton.icon(
                                onPressed: () => context.push('/support/admin'),
                                icon: const Icon(
                                    Icons.admin_panel_settings_rounded),
                                label:
                                    const Text('Acessar Painel Helpdesk (TI)'),
                                style: FilledButton.styleFrom(
                                    backgroundColor: theme.colorScheme.error,
                                    foregroundColor: theme.colorScheme.onError),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),

                    // EMPRESA
                    Card(
                      elevation: 0,
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.3),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.corporate_fare_outlined,
                                    size: 20, color: theme.colorScheme.primary),
                                const SizedBox(width: 8),
                                Text('Informações Organizacionais',
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(
                                            fontWeight: FontWeight.bold)),
                                const Spacer(),
                                if (!isTiAdmin)
                                  Tooltip(
                                    message:
                                        'Apenas a TI pode alterar estes dados.',
                                    child: Icon(Icons.lock_outline,
                                        size: 16,
                                        color: theme.colorScheme.outline),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            DropdownButtonFormField<String>(
                              initialValue: _selectedBranchId,
                              decoration: InputDecoration(
                                labelText: 'Filial de Lotação',
                                prefixIcon:
                                    const Icon(Icons.location_city_outlined),
                                filled: !isTiAdmin,
                              ),
                              items: branches
                                  .map((b) => DropdownMenuItem<String>(
                                      value: b['id'], child: Text(b['name'])))
                                  .toList(),
                              onChanged: isTiAdmin
                                  ? (val) =>
                                      setState(() => _selectedBranchId = val)
                                  : null,
                            ),
                            const SizedBox(height: 16),
                            Consumer(
                              builder: (context, ref, _) {
                                final deptsAsync =
                                    ref.watch(departmentsProvider);
                                return deptsAsync.when(
                                  loading: () =>
                                      const LinearProgressIndicator(),
                                  error: (e, _) => Text('Erro: $e'),
                                  data: (depts) {
                                    final validDeptIds = depts
                                        .map((d) => d['id'] as String)
                                        .toSet();
                                    final effectiveDeptId = validDeptIds
                                            .contains(_selectedDepartmentId)
                                        ? _selectedDepartmentId
                                        : null;
                                    return DropdownButtonFormField<String>(
                                      initialValue: effectiveDeptId,
                                      decoration: InputDecoration(
                                        labelText: 'Departamento / Setor',
                                        prefixIcon: const Icon(
                                            Icons.business_center_outlined),
                                        filled: !isTiAdmin,
                                      ),
                                      items: depts
                                          .map((d) => DropdownMenuItem(
                                                value: d['id'] as String,
                                                child:
                                                    Text(d['name'] as String),
                                              ))
                                          .toList(),
                                      onChanged: isTiAdmin
                                          ? (val) => setState(() {
                                                _selectedDepartmentId = val;
                                                _selectedJobPositionId = null;
                                              })
                                          : null,
                                    );
                                  },
                                );
                              },
                            ),
                            const SizedBox(height: 16),
                            Consumer(
                              builder: (context, ref, _) {
                                final jobsAsync = ref.watch(
                                    jobPositionsProvider(
                                        _selectedDepartmentId));
                                return jobsAsync.when(
                                  loading: () =>
                                      const LinearProgressIndicator(),
                                  error: (e, _) => Text('Erro: $e'),
                                  data: (jobs) {
                                    final validJobIds = jobs
                                        .map((j) => j['id'] as String)
                                        .toSet();
                                    final effectiveJobId = validJobIds
                                            .contains(_selectedJobPositionId)
                                        ? _selectedJobPositionId
                                        : null;
                                    return DropdownButtonFormField<String>(
                                      initialValue: effectiveJobId,
                                      decoration: InputDecoration(
                                        labelText: 'Cargo / Função',
                                        prefixIcon:
                                            const Icon(Icons.work_outline),
                                        filled: !isTiAdmin,
                                      ),
                                      items: jobs
                                          .map((j) => DropdownMenuItem(
                                                value: j['id'] as String,
                                                child:
                                                    Text(j['name'] as String),
                                              ))
                                          .toList(),
                                      onChanged: isTiAdmin
                                          ? (val) => setState(() =>
                                              _selectedJobPositionId = val)
                                          : null,
                                    );
                                  },
                                );
                              },
                            ),
                            const SizedBox(height: 16),
                            DropdownButtonFormField<String>(
                              initialValue: _selectedRole,
                              decoration: InputDecoration(
                                labelText: 'Nível de Acesso',
                                prefixIcon: const Icon(
                                    Icons.admin_panel_settings_outlined),
                                filled: !isTiAdmin,
                              ),
                              items: validRoles.map((r) {
                                return DropdownMenuItem(
                                    value: r,
                                    child: Text(AppPermissions.getLabel(r)));
                              }).toList(),
                              onChanged: isTiAdmin
                                  ? (val) => setState(() => _selectedRole = val)
                                  : null,
                            ),
                            if (!isTiAdmin)
                              Padding(
                                padding: const EdgeInsets.only(top: 16),
                                child: Row(
                                  children: [
                                    Icon(Icons.info_outline,
                                        size: 14,
                                        color: theme.colorScheme.outline),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                          'Contate o administrador para alterar lotação corporativa.',
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                  color: theme
                                                      .colorScheme.outline)),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // DOCUMENTOS (RH-6)
                    Card(
                      elevation: 0,
                      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(color: theme.colorScheme.primary.withValues(alpha: 0.2))),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.folder_shared_outlined, color: theme.colorScheme.primary),
                                const SizedBox(width: 8),
                                Text('Recursos Humanos',
                                    style: theme.textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.bold, color: theme.colorScheme.primary)),
                              ],
                            ),
                            const SizedBox(height: 16),
                            // Atalhos self-service. Empilhados no celular;
                            // em duas colunas quando há largura (web/desktop),
                            // em vez de uma coluna de botões esticados.
                            LayoutBuilder(
                              builder: (context, constraints) {
                                const atalhos = <(String, IconData, String)>[
                                  ('/meus-documentos', Icons.description_outlined, 'Meus Documentos'),
                                  ('/meu-onboarding', Icons.checklist_outlined, 'Meu Onboarding'),
                                  ('/meus-afastamentos', Icons.event_busy_outlined, 'Minhas Ausências e Férias'),
                                  ('/meu-ponto', Icons.access_time_outlined, 'Meu Ponto'),
                                  ('/meus-holerites', Icons.request_quote_outlined, 'Meus Holerites'),
                                  ('/meu-desempenho', Icons.insights_outlined, 'Meu Desempenho'),
                                ];
                                final duasColunas = constraints.maxWidth >= 520;
                                final largura = duasColunas
                                    ? (constraints.maxWidth - 8) / 2
                                    : constraints.maxWidth;
                                return Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    for (final (rota, icone, rotulo) in atalhos)
                                      SizedBox(
                                        width: largura,
                                        child: FilledButton.tonalIcon(
                                          onPressed: () => context.push(rota),
                                          icon: Icon(icone),
                                          label: Text(rotulo,
                                              overflow: TextOverflow.ellipsis),
                                        ),
                                      ),
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 32),

                    // Botão de Logout Rápido Estiloso
                    TextButton.icon(
                      onPressed: () => _showLogoutDialog(context, ref),
                      icon: Icon(Icons.exit_to_app_rounded,
                          color: theme.colorScheme.error),
                      label: Text('Sair da Conta (Logout)',
                          style: TextStyle(color: theme.colorScheme.error)),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showLogoutDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar Saída'),
        content: const Text('Deseja realmente sair da sua conta ${AppConstants.appName}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () async {
              Navigator.pop(ctx);
              await ref.read(authRepositoryProvider).signOut();
              if (context.mounted) {
                context.go('/login');
              }
            },
            child: const Text('Sair'),
          ),
        ],
      ),
    );
  }
}
