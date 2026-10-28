import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alinha_ja/core/status_tokens.dart';
import 'package:alinha_ja/features/hr/data/job_catalog.dart';
import 'package:alinha_ja/features/hr/services/candidate_auth_service.dart';
import 'package:alinha_ja/features/hr/services/candidate_portal_service.dart';
import 'package:alinha_ja/features/hr/ui/widgets/preset_field.dart';
import 'package:alinha_ja/core/utils/friendly_error.dart';

final _portalServiceProvider =
    Provider<CandidatePortalService>((_) => const CandidatePortalService());

/// A partir daqui a página deixa de ser uma coluna única e passa a usar
/// duas colunas (apresentação + formulário). Abaixo disso, cabe só uma.
const double _kTwoColumnBreakpoint = 940;

/// Largura máxima do conteúdo em telas grandes. Sem isso, o formulário
/// esticaria por um monitor inteiro e viraria uma linha de campos ilegível.
const double _kMaxContentWidth = 1160;

/// Largura confortável de leitura para o layout de coluna única.
const double _kSingleColumnWidth = 620;

/// RH-2.1 — Página pública de carreiras (/carreiras/:slug).
/// Acessível sem login; toda a comunicação passa pela Edge Function.
class CareersScreen extends ConsumerStatefulWidget {
  const CareersScreen({super.key, required this.orgSlug, this.vagaId});

  final String orgSlug;
  final String? vagaId;

  @override
  ConsumerState<CareersScreen> createState() => _CareersScreenState();
}

class _CareersScreenState extends ConsumerState<CareersScreen> {
  Map<String, dynamic>? _org;
  bool _loadingOrg = true;
  String? _orgError;
  bool _submitted = false;
  ApplyResult? _resultado;

  @override
  void initState() {
    super.initState();
    _loadOrg();
  }

  Future<void> _loadOrg() async {
    try {
      final org =
          await ref.read(_portalServiceProvider).fetchOrg(widget.orgSlug);
      setState(() {
        _org = org;
        _loadingOrg = false;
      });
    } catch (e) {
      setState(() {
        _orgError = friendlyError(e);
        _loadingOrg = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget body;
    if (_loadingOrg) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_orgError != null) {
      body = _NotFound(message: _orgError!);
    } else if (_submitted) {
      body = _Confirmation(
        token: _resultado?.token,
        emailEnviado: _resultado?.emailEnviado ?? false,
        orgSlug: widget.orgSlug,
      );
    } else if (_org!['carreiras_ativo'] == false) {
      // F1.1 — RH pausou as inscrições (a Edge Function também recusa).
      body = _Paused(orgName: (_org!['name'] as String?) ?? '');
    } else {
      final vagas =
          ((_org!['vagas'] as List?) ?? const []).cast<Map<String, dynamic>>();
      return Scaffold(
        backgroundColor: theme.colorScheme.surface,
        body: SafeArea(
          child: _ApplicationForm(
            orgSlug: widget.orgSlug,
            orgName: (_org!['name'] as String?) ?? '',
            logoUrl: _org!['logo_url'] as String?,
            headline: _org!['carreiras_headline'] as String?,
            sobre: _org!['carreiras_sobre'] as String?,
            vagas: vagas,
            // Catálogo da empresa (RH-9). Vem antes dos presets padrão nas
            // sugestões — é a grafia que o RH usa nos próprios filtros.
            areasOrg: _listaDeTextos(_org!['areas']),
            cargosOrg: _listaDeTextos(_org!['cargos']),
            initialVagaId: widget.vagaId,
            onSubmitted: (resultado) {
              setState(() {
                _resultado = resultado;
                _submitted = true;
              });
            },
          ),
        ),
      );
    }

    // Estados curtos (erro, pausado, confirmação) não precisam de layout
    // largo: centralizados numa coluna de leitura em qualquer tela.
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _kSingleColumnWidth),
            child: body,
          ),
        ),
      ),
    );
  }
}

List<String> _listaDeTextos(dynamic v) =>
    (v as List?)?.map((e) => e.toString()).toList() ?? const [];

class _NotFound extends StatelessWidget {
  const _NotFound({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off_rounded,
                size: 64, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

/// RH-2.5 — Confirmação pós-envio.
///
/// O texto muda conforme o e-mail de confirmação saiu ou não: prometer
/// um e-mail que não foi enviado deixa o candidato esperando sem ter
/// como acompanhar nada.
class _Confirmation extends StatelessWidget {
  const _Confirmation({
    this.token,
    required this.orgSlug,
    this.emailEnviado = false,
  });

  final String? token;
  final String orgSlug;
  final bool emailEnviado;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.statusTokens;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_rounded, size: 72, color: tokens.success),
            const SizedBox(height: 20),
            Text('Recebemos sua candidatura!',
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Text(
              emailEnviado
                  ? 'Enviamos um e-mail de confirmação com um link para você '
                      'acompanhar o andamento do processo. Boa sorte! 🍀'
                  : 'Sua candidatura foi registrada. Boa sorte! 🍀',
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.colorScheme.outline),
            ),
            if (token != null) ...[
              const SizedBox(height: 28),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color:
                      theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Text(
                      emailEnviado
                          ? 'Acompanhe seu processo'
                          : 'Guarde este link',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      emailEnviado
                          ? 'Acesse agora sua área do candidato para ver o '
                              'andamento e responder a avaliação, se houver.'
                          : 'Não conseguimos enviar o e-mail de confirmação. '
                              'Este é o seu acesso ao processo — abra agora e '
                              'salve o endereço nos favoritos.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: ElevatedButton(
                        onPressed: () => context.go('/candidato/$token'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.colorScheme.primary,
                          foregroundColor: theme.colorScheme.onPrimary,
                        ),
                        child: const Text('Abrir minha candidatura',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            ] else if (!emailEnviado) ...[
              // Sem token e sem e-mail: o candidato ficaria sem caminho.
              const SizedBox(height: 24),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 18, color: tokens.warning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Não conseguimos enviar o e-mail de confirmação. Sua '
                      'candidatura está registrada — o RH entrará em contato.',
                      style: TextStyle(fontSize: 13, color: tokens.warning),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// F1.1 — Página com inscrições pausadas pelo RH.
class _Paused extends StatelessWidget {
  const _Paused({required this.orgName});

  final String orgName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.pause_circle_outline,
                size: 64, color: theme.colorScheme.outline),
            const SizedBox(height: 20),
            Text('Inscrições pausadas',
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Text(
              '${orgName.isNotEmpty ? '$orgName não' : 'Não'} está recebendo '
              'novas candidaturas no momento. Volte em breve!',
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.colorScheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}

class _ApplicationForm extends ConsumerStatefulWidget {
  const _ApplicationForm({
    required this.orgSlug,
    required this.orgName,
    required this.logoUrl,
    required this.onSubmitted,
    required this.vagas,
    this.headline,
    this.sobre,
    this.initialVagaId,
    this.areasOrg = const [],
    this.cargosOrg = const [],
  });

  final String orgSlug;
  final String orgName;
  final String? logoUrl;
  final String? headline;
  final String? sobre;

  /// Vagas abertas retornadas pela Edge Function (RH-10).
  final List<Map<String, dynamic>> vagas;

  /// Áreas e cargos cadastrados pela empresa (RH-9), quando houver.
  final List<String> areasOrg;
  final List<String> cargosOrg;

  /// Quando aberto via /carreiras/:slug/vaga/:id, a candidatura já
  /// nasce vinculada a esta vaga.
  final String? initialVagaId;
  final void Function(ApplyResult) onSubmitted;

  @override
  ConsumerState<_ApplicationForm> createState() => _ApplicationFormState();
}

class _ApplicationFormState extends ConsumerState<_ApplicationForm> {
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
  String _disponibilidade = 'imediata';
  bool _lgpdOk = false;
  bool _sending = false;
  String? _error;

  /// Vaga escolhida (null = candidatura espontânea / banco de talentos).
  String? _vagaId;

  Uint8List? _cvBytes;
  String? _cvFileName;

  /// Fase 7: reaproveitar o currículo já enviado em outra candidatura,
  /// em vez de anexar de novo. Só vale para candidato logado.
  bool _reusarCv = false;

  static const _maxCvBytes = 5 * 1024 * 1024;

  @override
  void initState() {
    super.initState();
    // Se a vaga do link ainda está aberta, começa vinculada a ela.
    if (widget.initialVagaId != null &&
        widget.vagas.any((v) => v['id'] == widget.initialVagaId)) {
      _vagaId = widget.initialVagaId;
    }
  }

  Map<String, dynamic>? get _vagaSelecionada {
    if (_vagaId == null) return null;
    for (final v in widget.vagas) {
      if (v['id'] == _vagaId) return v;
    }
    return null;
  }

  /// Áreas sugeridas: primeiro o catálogo da empresa, depois os presets
  /// padrão. Empresa nova tem catálogo vazio — sem o fallback, o campo
  /// voltaria a ser texto livre sem nenhuma orientação.
  List<String> get _sugestoesArea =>
      mesclarSugestoes([widget.areasOrg, kDefaultAreas]);

  /// Cargos sugeridos, afunilados pela área escolhida quando ela existe no
  /// catálogo padrão. Área ainda em branco (ou fora do catálogo) mostra a
  /// lista inteira, em vez de nenhuma sugestão.
  List<String> get _sugestoesCargo {
    final daArea = cargosDaArea(_area.text);
    return mesclarSugestoes([
      if (daArea.isNotEmpty) daArea,
      widget.cargosOrg,
      if (daArea.isEmpty) kDefaultCargos,
    ]);
  }

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
      setState(() => _error = 'O currículo deve ter no máximo 5MB.');
      return;
    }
    setState(() {
      _cvBytes = file.bytes;
      _cvFileName = file.name;
      _error = null;
    });
  }

  Future<void> _submit() async {
    if (_sending) return; // double-submit (S051)
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    if (!_reusarCv && _cvBytes == null) {
      setState(() => _error = 'Anexe seu currículo (PDF ou DOCX).');
      return;
    }
    if (!_lgpdOk) {
      setState(() => _error =
          'É necessário aceitar a política de privacidade para continuar.');
      return;
    }

    setState(() => _sending = true);
    try {
      final resultado = await ref.read(_portalServiceProvider).apply(
            slug: widget.orgSlug,
            fields: {
              'nome': _nome.text.trim(),
              'email': _email.text.trim().toLowerCase(),
              'telefone': _telefone.text.trim(),
              'cidade': _cidade.text.trim(),
              'estado': _estado.text.trim(),
              'area_interesse': _area.text.trim(),
              'cargo_pretendido': _cargo.text.trim(),
              'nivel': _nivel,
              'disponibilidade': _disponibilidade,
              'pretensao_salarial': double.tryParse(_pretensao.text
                  .trim()
                  .replaceAll('.', '')
                  .replaceAll(',', '.')),
              if (_vagaId != null) 'vaga_id': _vagaId,
            },
            cvBytes: _reusarCv ? null : _cvBytes,
            reusarCv: _reusarCv,
            sessionToken: ref.read(candidateAuthProvider).token,
          );
      widget.onSubmitted(resultado);
    } on PortalException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(
          () => _error = 'Não foi possível enviar. Verifique sua conexão.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final duasColunas = constraints.maxWidth >= _kTwoColumnBreakpoint;
        return Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth:
                      duasColunas ? _kMaxContentWidth : _kSingleColumnWidth,
                ),
                child: duasColunas
                    ? _layoutLargo(context)
                    : _layoutEstreito(context),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Desktop: apresentação e vagas à esquerda, formulário fixo à direita.
  /// Assim o candidato compara as vagas sem perder de vista o formulário —
  /// e a página deixa de ser uma tira estreita no meio do monitor.
  Widget _layoutLargo(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _HeroHeader(
            logoUrl: widget.logoUrl,
            orgName: widget.orgName,
            headline: widget.headline,
            sobre: widget.sobre,
            horizontal: true,
          ),
          const SizedBox(height: 28),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _HowItWorks(),
                    if (widget.vagas.isNotEmpty) ...[
                      const SizedBox(height: 32),
                      _VagasSection(
                        vagas: widget.vagas,
                        selectedId: _vagaId,
                        onSelect: (id) => setState(() => _vagaId = id),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 40),
              Expanded(
                flex: 6,
                child: Card(
                  margin: EdgeInsets.zero,
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(
                        color: Theme.of(context).colorScheme.outlineVariant),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: _camposDoFormulario(context, largo: true),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Mobile/tablet: tudo empilhado, na ordem em que se lê a página.
  Widget _layoutEstreito(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HeroHeader(
          logoUrl: widget.logoUrl,
          orgName: widget.orgName,
          headline: widget.headline,
          sobre: widget.sobre,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _HowItWorks(),
              const SizedBox(height: 28),
              if (widget.vagas.isNotEmpty) ...[
                _VagasSection(
                  vagas: widget.vagas,
                  selectedId: _vagaId,
                  onSelect: (id) => setState(() => _vagaId = id),
                ),
                const SizedBox(height: 28),
              ],
              _camposDoFormulario(context, largo: false),
            ],
          ),
        ),
      ],
    );
  }

  Widget _camposDoFormulario(BuildContext context, {required bool largo}) {
    final theme = Theme.of(context);
    final auth = ref.watch(candidateAuthProvider);
    final podeReusarCv = auth.isLoggedIn && auth.curriculoReaproveitavel;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
            _vagaSelecionada != null
                ? 'Candidatar-se à vaga'
                : 'Cadastre-se no banco de talentos',
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(
          _vagaSelecionada != null
              ? 'Você está se candidatando para: '
                  '${_vagaSelecionada!['titulo']}.'
              : 'Preencha seus dados abaixo — leva menos de 2 minutos.',
          style: TextStyle(color: theme.colorScheme.outline),
        ),
        const SizedBox(height: 20),
        TextFormField(
          controller: _nome,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Nome completo *'),
          validator: (v) => (v == null || v.trim().length < 3)
              ? 'Informe seu nome completo'
              : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'E-mail *'),
          validator: (v) {
            final ok =
                RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v?.trim() ?? '');
            return ok ? null : 'E-mail inválido';
          },
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _telefone,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'Telefone/WhatsApp *'),
          validator: (v) => (v == null || v.trim().length < 10)
              ? 'Informe um telefone válido com DDD'
              : null,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: TextFormField(
                controller: _cidade,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Cidade *'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Obrigatório' : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _estado,
                maxLength: 2,
                textCapitalization: TextCapitalization.characters,
                decoration:
                    const InputDecoration(labelText: 'UF *', counterText: ''),
                validator: (v) =>
                    (v == null || v.trim().length != 2) ? 'UF' : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Área e cargo com sugestões (catálogo da empresa + presets).
        // Padroniza a grafia sem tirar do candidato a liberdade de
        // digitar um cargo que não está na lista.
        PresetField(
          controller: _area,
          label: 'Área de interesse *',
          hint: 'Ex.: Tecnologia da Informação',
          icon: Icons.category_outlined,
          options: _sugestoesArea,
          emptyOptionsHint: 'Não achou a sua? Digite a área do seu jeito.',
          validator: (v) =>
              (v == null || v.trim().isEmpty) ? 'Obrigatório' : null,
          // Troca de área muda a lista de cargos sugeridos.
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        PresetField(
          controller: _cargo,
          label: 'Cargo pretendido',
          hint: _area.text.trim().isEmpty
              ? 'Escolha a área para ver sugestões'
              : 'Ex.: ${_sugestoesCargo.isNotEmpty ? _sugestoesCargo.first : 'Analista'}',
          icon: Icons.badge_outlined,
          options: _sugestoesCargo,
          emptyOptionsHint: 'Não achou o seu? Digite o cargo do seu jeito.',
        ),
        const SizedBox(height: 12),
        // Nível e disponibilidade são curtos: lado a lado quando o
        // formulário tem largura, empilhados no celular.
        _ParDeCampos(
          lado: largo,
          primeiro: DropdownButtonFormField<String>(
            initialValue: _nivel,
            isExpanded: true,
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
          segundo: DropdownButtonFormField<String>(
            initialValue: _disponibilidade,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Disponibilidade'),
            items: const [
              DropdownMenuItem(value: 'imediata', child: Text('Imediata')),
              DropdownMenuItem(value: '15_dias', child: Text('Em 15 dias')),
              DropdownMenuItem(value: '30_dias', child: Text('Em 30 dias')),
              DropdownMenuItem(value: 'a_combinar', child: Text('A combinar')),
            ],
            onChanged: (v) =>
                setState(() => _disponibilidade = v ?? 'imediata'),
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _pretensao,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
              labelText: 'Pretensão salarial (opcional)', prefixText: 'R\$ '),
        ),
        const SizedBox(height: 16),
        // Fase 7 — quem já se candidatou pela conta não reenvia o
        // arquivo: reaproveita o último currículo enviado.
        if (podeReusarCv)
          CheckboxListTile(
            value: _reusarCv,
            onChanged: (v) => setState(() {
              _reusarCv = v ?? false;
              if (_reusarCv) {
                _cvBytes = null;
                _cvFileName = null;
              }
              _error = null;
            }),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Usar o currículo que já enviei',
              style: TextStyle(fontSize: 13),
            ),
            subtitle: Text(
              'Reaproveita o último currículo da sua conta'
              '${auth.curriculoTipo != null ? ' (${auth.curriculoTipo!.toUpperCase()})' : ''}.',
              style: const TextStyle(fontSize: 12),
            ),
          ),
        if (!_reusarCv)
          OutlinedButton.icon(
            onPressed: _pickCv,
            style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14)),
            icon: Icon(_cvFileName == null
                ? Icons.upload_file_rounded
                : Icons.check_circle_rounded),
            label:
                Text(_cvFileName ?? 'Anexar currículo (PDF/DOCX, máx. 5MB) *'),
          ),
        const SizedBox(height: 8),
        // Aceite LGPD obrigatório (RH-2.3)
        CheckboxListTile(
          value: _lgpdOk,
          onChanged: (v) => setState(() => _lgpdOk = v ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'Autorizo o tratamento dos meus dados pessoais para fins '
            'de recrutamento e seleção, conforme a Lei Geral de '
            'Proteção de Dados (LGPD). *',
            style: TextStyle(fontSize: 13),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child:
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _sending ? null : _submit,
          style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16)),
          child: _sending
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Enviar candidatura'),
        ),
      ],
    );
  }
}

/// Dois campos curtos: lado a lado quando há largura, empilhados quando não.
class _ParDeCampos extends StatelessWidget {
  const _ParDeCampos({
    required this.lado,
    required this.primeiro,
    required this.segundo,
  });

  final bool lado;
  final Widget primeiro;
  final Widget segundo;

  @override
  Widget build(BuildContext context) {
    if (!lado) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [primeiro, const SizedBox(height: 12), segundo],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: primeiro),
        const SizedBox(width: 12),
        Expanded(child: segundo),
      ],
    );
  }
}

/// Cabeçalho-vitrine da página pública: logo do tenant, título e a proposta
/// de valor do banco de talentos. Dá cara de landing page ao formulário.
class _HeroHeader extends StatelessWidget {
  const _HeroHeader({
    required this.logoUrl,
    required this.orgName,
    this.headline,
    this.sobre,
    this.horizontal = false,
  });

  final String? logoUrl;
  final String orgName;

  /// Textos editáveis pelo RH na Central (F1.1) — com fallback aos padrões.
  final String? headline;
  final String? sobre;

  /// No desktop o hero deita: marca à esquerda, texto alinhado à esquerda.
  /// Empilhado e centralizado, ele ocuparia meia tela antes do formulário.
  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final onPrimary = theme.colorScheme.onPrimary;
    final alinhamento = horizontal ? TextAlign.left : TextAlign.center;

    final marca = logoUrl != null
        ? Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Image.network(logoUrl!,
                height: horizontal ? 56 : 48,
                errorBuilder: (_, __, ___) =>
                    Icon(Icons.work, color: primary, size: 40)),
          )
        : CircleAvatar(
            radius: horizontal ? 32 : 28,
            backgroundColor: onPrimary.withValues(alpha: 0.18),
            child: Icon(Icons.work, color: onPrimary, size: 28),
          );

    final textos = <Widget>[
      Text(
          (headline ?? '').trim().isNotEmpty
              ? headline!.trim()
              : 'Trabalhe conosco',
          textAlign: alinhamento,
          style: (horizontal
                  ? theme.textTheme.headlineMedium
                  : theme.textTheme.headlineSmall)
              ?.copyWith(color: onPrimary, fontWeight: FontWeight.w800)),
      const SizedBox(height: 4),
      if (orgName.isNotEmpty)
        Text(orgName,
            textAlign: alinhamento,
            style: TextStyle(
                color: onPrimary.withValues(alpha: 0.85),
                fontWeight: FontWeight.w500)),
      const SizedBox(height: 14),
      Text(
        (sobre ?? '').trim().isNotEmpty
            ? sobre!.trim()
            : 'Mesmo sem uma vaga aberta hoje, seu currículo entra no nosso '
                'banco de talentos e é lembrado nas próximas oportunidades.',
        textAlign: alinhamento,
        style: TextStyle(color: onPrimary.withValues(alpha: 0.9), height: 1.4),
      ),
      const SizedBox(height: 12),
      // RH-16 — Portal do Candidato: acompanhar candidaturas com login.
      Align(
        alignment: horizontal ? Alignment.centerLeft : Alignment.center,
        child: TextButton.icon(
          style: TextButton.styleFrom(
            foregroundColor: onPrimary,
            padding: horizontal
                ? const EdgeInsets.symmetric(horizontal: 12, vertical: 8)
                : null,
          ),
          icon: const Icon(Icons.person_outline, size: 18),
          label: const Text('Já se candidatou? Acompanhe suas candidaturas'),
          onPressed: () => context.go('/candidato/login'),
        ),
      ),
    ];

    return Container(
      width: double.infinity,
      margin: horizontal
          ? EdgeInsets.zero
          : const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: EdgeInsets.symmetric(
          horizontal: horizontal ? 40 : 24, vertical: horizontal ? 44 : 36),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            primary,
            Color.lerp(primary, Colors.black, 0.35)!,
          ],
        ),
      ),
      child: horizontal
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                marca,
                const SizedBox(width: 28),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: textos,
                  ),
                ),
              ],
            )
          : Column(
              children: [marca, const SizedBox(height: 18), ...textos],
            ),
    );
  }
}

/// RH-10 — Lista de vagas abertas no portal. O candidato pode escolher
/// uma vaga (candidatura vinculada) ou seguir sem selecionar (espontânea,
/// banco de talentos).
class _VagasSection extends StatelessWidget {
  const _VagasSection({
    required this.vagas,
    required this.selectedId,
    required this.onSelect,
  });

  final List<Map<String, dynamic>> vagas;
  final String? selectedId;
  final void Function(String? id) onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.work_outline, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text('Vagas abertas',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Selecione uma vaga para se candidatar, ou envie uma candidatura '
          'espontânea para o banco de talentos.',
          style: TextStyle(color: theme.colorScheme.outline, fontSize: 13),
        ),
        const SizedBox(height: 12),
        for (final v in vagas)
          _VagaOption(
            vaga: v,
            selected: v['id'] == selectedId,
            onTap: () =>
                onSelect(v['id'] == selectedId ? null : v['id'] as String),
          ),
      ],
    );
  }
}

class _VagaOption extends StatelessWidget {
  const _VagaOption({
    required this.vaga,
    required this.selected,
    required this.onTap,
  });

  final Map<String, dynamic> vaga;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final titulo = (vaga['titulo'] as String?) ?? 'Vaga';
    final remoto = vaga['remoto'] == true;
    final localidade = (vaga['localidade'] as String?)?.trim() ?? '';
    final tipo = (vaga['tipo_contrato'] as String?)?.trim() ?? '';
    final faixa = (vaga['faixa_salarial'] as String?)?.trim() ?? '';
    final chips = <String>[
      if (remoto) 'Remoto' else if (localidade.isNotEmpty) localidade,
      if (tipo.isNotEmpty) tipo.toUpperCase(),
      if (faixa.isNotEmpty) faixa,
    ];

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      color: selected ? primary.withValues(alpha: 0.08) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? primary : theme.colorScheme.outlineVariant,
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked,
                color: selected ? primary : theme.colorScheme.outline,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titulo,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15)),
                    if (chips.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final c in chips)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainerHighest
                                    .withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(c,
                                  style: TextStyle(
                                      fontSize: 11.5,
                                      color:
                                          theme.colorScheme.onSurfaceVariant)),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Passo-a-passo do processo de candidatura, explicado para o candidato.
class _HowItWorks extends StatelessWidget {
  const _HowItWorks();

  static const List<(IconData, String, String)> _steps = [
    (
      Icons.person,
      'Preencha seus dados',
      'Nome, contato e a sua área de interesse.'
    ),
    (Icons.description, 'Anexe seu currículo', 'PDF ou DOCX, de até 5 MB.'),
    (
      Icons.auto_awesome,
      'Análise inteligente',
      'Nossa IA organiza seu perfil e ajuda a encontrar a vaga certa.'
    ),
    (
      Icons.email,
      'Acompanhe por e-mail',
      'Você recebe um link para ver o andamento quando quiser.'
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Como funciona',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 16),
        for (var i = 0; i < _steps.length; i++) ...[
          _StepTile(
            index: i + 1,
            icon: _steps[i].$1,
            title: _steps[i].$2,
            subtitle: _steps[i].$3,
          ),
          if (i < _steps.length - 1) const SizedBox(height: 14),
        ],
      ],
    );
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({
    required this.index,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final int index;
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: primary, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('$index. ',
                      style: TextStyle(
                          color: primary, fontWeight: FontWeight.w800)),
                  Expanded(
                    child: Text(title,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: TextStyle(
                      color: theme.colorScheme.outline,
                      fontSize: 13,
                      height: 1.3)),
            ],
          ),
        ),
      ],
    );
  }
}
