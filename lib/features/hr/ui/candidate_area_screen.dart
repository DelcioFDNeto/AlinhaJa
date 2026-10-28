import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:alinha_ja/features/hr/models/pipeline_etapa_model.dart';
import 'package:alinha_ja/features/hr/services/candidate_portal_service.dart';
import 'package:alinha_ja/features/hr/ui/candidate_test_screen.dart';
import 'package:alinha_ja/core/utils/friendly_error.dart';

final _portalServiceProvider =
    Provider<CandidatePortalService>((_) => const CandidatePortalService());

final _statusProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, token) {
  return ref.watch(_portalServiceProvider).fetchStatus(token);
});

/// Acima desta largura a área do candidato usa duas colunas.
const double _kTwoColumnBreakpoint = 900;
const double _kMaxContentWidth = 1080;
const double _kSingleColumnWidth = 640;

/// RH-2.7/2.8/2.9 — Área pública do candidato (/candidato/:token).
class CandidateAreaScreen extends ConsumerWidget {
  const CandidateAreaScreen({super.key, required this.token});

  final String token;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(_statusProvider(token));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Minha candidatura'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(_statusProvider(token)),
          ),
        ],
      ),
      body: statusAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _LinkInvalido(mensagem: friendlyError(e)),
        data: (data) => _AreaBody(token: token, data: data),
      ),
    );
  }
}

class _LinkInvalido extends StatelessWidget {
  const _LinkInvalido({required this.mensagem});

  final String mensagem;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.link_off_rounded,
                  size: 56, color: theme.colorScheme.outline),
              const SizedBox(height: 16),
              Text('Não conseguimos abrir sua candidatura',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                  textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(mensagem,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: theme.colorScheme.outline)),
              const SizedBox(height: 8),
              Text(
                'O link de acompanhamento é pessoal e vale por 90 dias. '
                'Se o seu expirou, fale com o RH da empresa.',
                textAlign: TextAlign.center,
                style:
                    TextStyle(fontSize: 13, color: theme.colorScheme.outline),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AreaBody extends ConsumerStatefulWidget {
  const _AreaBody({required this.token, required this.data});

  final String token;
  final Map<String, dynamic> data;

  @override
  ConsumerState<_AreaBody> createState() => _AreaBodyState();
}

class _AreaBodyState extends ConsumerState<_AreaBody> {
  final _msgController = TextEditingController();
  bool _busy = false;

  /// Estado da avaliação depois de uma ação local (fez a prova agora).
  /// Enquanto for null, vale o que veio do servidor — que já sabe se a
  /// empresa tem questões, se a prova está em andamento ou encerrada.
  Map<String, dynamic>? _avaliacaoLocal;

  @override
  void dispose() {
    _msgController.dispose();
    super.dispose();
  }

  Map<String, dynamic> get _avaliacao =>
      _avaliacaoLocal ??
      ((widget.data['avaliacao'] as Map?)?.cast<String, dynamic>() ??
          const {'estado': 'indisponivel'});

  void _aviso(String texto, {bool erro = false}) {
    if (!mounted) return;
    final theme = Theme.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texto),
        behavior: SnackBarBehavior.floating,
        backgroundColor: erro ? theme.colorScheme.errorContainer : null,
      ),
    );
  }

  Future<void> _fazerAvaliacao() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final res =
          await ref.read(_portalServiceProvider).avaliacaoIniciar(widget.token);
      if (res['ja_feita'] == true) {
        setState(() => _avaliacaoLocal = {
              'estado': res['expirada'] == true ? 'expirada' : 'concluida',
              'nota': res['nota'],
            });
      } else if (res['disponivel'] == false) {
        setState(() => _avaliacaoLocal = {'estado': 'indisponivel'});
      } else if (res['avaliacao_id'] != null) {
        final questoes = ((res['questoes'] as List?) ?? const [])
            .map((e) => (e as Map).cast<String, dynamic>())
            .toList();
        final expiraEm = res['expira_em'] != null
            ? DateTime.tryParse(res['expira_em'] as String)?.toLocal()
            : null;
        if (!mounted) return;
        final nota = await Navigator.of(context).push<int>(
          MaterialPageRoute(
            builder: (_) => CandidateTestScreen(
              token: widget.token,
              avaliacaoId: res['avaliacao_id'] as String,
              questoes: questoes,
              expiraEm: expiraEm,
            ),
          ),
        );
        if (nota != null) {
          setState(
              () => _avaliacaoLocal = {'estado': 'concluida', 'nota': nota});
        }
      }
    } on PortalException catch (e) {
      _aviso(e.message, erro: true);
    } catch (_) {
      _aviso('Falha de conexão. Tente novamente.', erro: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _run(Future<void> Function() action, String ok) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      _aviso(ok);
      ref.invalidate(_statusProvider(widget.token));
    } on PortalException catch (e) {
      _aviso(e.message, erro: true);
    } catch (_) {
      _aviso('Falha de conexão. Tente novamente.', erro: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendMessage() async {
    final texto = _msgController.text.trim();
    if (texto.isEmpty) return;
    await _run(() async {
      await ref.read(_portalServiceProvider).sendMessage(widget.token, texto);
      _msgController.clear();
    }, 'Mensagem enviada ao RH.');
  }

  Future<void> _uploadDoc() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'docx', 'jpg', 'jpeg', 'png'],
      withData: true,
    );
    final file = result?.files.firstOrNull;
    if (file == null || file.bytes == null) return;
    if (file.size > 10 * 1024 * 1024) {
      _aviso('O arquivo deve ter no máximo 10MB.', erro: true);
      return;
    }
    final bytes = Uint8List.fromList(file.bytes!);
    await _run(() async {
      await ref.read(_portalServiceProvider).uploadDocument(
          token: widget.token, bytes: bytes, fileName: file.name);
    }, 'Documento enviado ao RH.');
  }

  @override
  Widget build(BuildContext context) {
    final nome = (widget.data['nome'] as String?) ?? '';
    final status = (widget.data['status'] as String?) ?? 'novo';
    final pipe = PipelineConfig.fromRows(
        ((widget.data['pipeline'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .toList());
    final descartado = status == pipe.descartado.slug;

    return LayoutBuilder(
      builder: (context, constraints) {
        final duasColunas = constraints.maxWidth >= _kTwoColumnBreakpoint;
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(_statusProvider(widget.token)),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth:
                      duasColunas ? _kMaxContentWidth : _kSingleColumnWidth,
                ),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                      duasColunas ? 24 : 16, 20, duasColunas ? 24 : 16, 40),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Cabecalho(nome: nome, data: widget.data),
                      const SizedBox(height: 24),
                      if (duasColunas)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 5,
                              child: _ColunaStatus(
                                pipe: pipe,
                                status: status,
                                descartado: descartado,
                              ),
                            ),
                            const SizedBox(width: 24),
                            Expanded(
                              flex: 6,
                              child: _ColunaAcoes(
                                estado: this,
                                descartado: descartado,
                              ),
                            ),
                          ],
                        )
                      else ...[
                        _ColunaStatus(
                          pipe: pipe,
                          status: status,
                          descartado: descartado,
                        ),
                        const SizedBox(height: 16),
                        _ColunaAcoes(estado: this, descartado: descartado),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Cabeçalho: para quem, em que empresa, para qual vaga e desde quando.
///
/// Quem se candidata em várias empresas recebe vários links iguais; sem
/// esse contexto o candidato abre um deles e não sabe qual processo está
/// vendo.
class _Cabecalho extends StatelessWidget {
  const _Cabecalho({required this.nome, required this.data});

  final String nome;
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final empresa = (data['empresa'] as String?)?.trim() ?? '';
    final logo = data['empresa_logo'] as String?;
    final vaga = (data['vaga_titulo'] as String?)?.trim() ?? '';
    final criadoEm = data['criado_em'] as String?;
    final desde =
        criadoEm == null ? null : _dataPorExtenso(DateTime.parse(criadoEm));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (logo != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(logo,
                    height: 40,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink()),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Text(
                // Só o primeiro nome: o cabeçalho cumprimenta, não identifica.
                nome.trim().isEmpty
                    ? 'Olá!'
                    : 'Olá, ${nome.trim().split(' ').first}!',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          [
            if (vaga.isNotEmpty)
              'Sua candidatura para $vaga'
            else
              'Sua candidatura ao banco de talentos',
            if (empresa.isNotEmpty) 'na $empresa',
          ].join(' '),
          style: TextStyle(color: theme.colorScheme.outline, height: 1.4),
        ),
        if (desde != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text('Enviada em $desde.',
                style:
                    TextStyle(color: theme.colorScheme.outline, fontSize: 13)),
          ),
      ],
    );
  }
}

/// Nomes fixos: o app não inicializa o locale pt_BR do intl, então
/// `DateFormat(..., 'pt_BR')` estouraria em runtime (mesma decisão de
/// absence_calendar.dart).
const _meses = [
  'janeiro',
  'fevereiro',
  'março',
  'abril',
  'maio',
  'junho',
  'julho',
  'agosto',
  'setembro',
  'outubro',
  'novembro',
  'dezembro',
];

String _dataPorExtenso(DateTime utc) {
  final d = utc.toLocal();
  return '${d.day} de ${_meses[d.month - 1]} de ${d.year}';
}

/// Coluna da esquerda: onde a candidatura está e o que acontece depois.
class _ColunaStatus extends StatelessWidget {
  const _ColunaStatus({
    required this.pipe,
    required this.status,
    required this.descartado,
  });

  final PipelineConfig pipe;
  final String status;
  final bool descartado;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final indiceAtual = pipe.funilSlugs.indexOf(status);
    final atual = pipe.bySlug(status);
    final proxima = indiceAtual >= 0 && indiceAtual < pipe.funil.length - 1
        ? pipe.funil[indiceAtual + 1]
        : null;

    return _Bloco(
      titulo: 'Andamento',
      icone: Icons.timeline,
      // O contador dá noção de progresso que uma lista de bolinhas sozinha
      // não dá — "estou no 1 de 5" é diferente de "estou em Novo".
      trailing: descartado || indiceAtual < 0
          ? null
          : Text('Etapa ${indiceAtual + 1} de ${pipe.funil.length}',
              style:
                  TextStyle(fontSize: 12.5, color: theme.colorScheme.outline)),
      child: descartado
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.inventory_2_outlined,
                    color: theme.colorScheme.outline),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Este processo foi encerrado, mas seu perfil continua no '
                    'banco de talentos da empresa e pode ser retomado em '
                    'futuras oportunidades.',
                    style: TextStyle(
                        color: theme.colorScheme.outline, height: 1.4),
                  ),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final e in pipe.funil)
                  _TimelineStep(
                    label: e.nome,
                    done: pipe.funilSlugs.indexOf(e.slug) < indiceAtual,
                    current: e.slug == status,
                    last: e.slug == pipe.funil.last.slug,
                  ),
                const SizedBox(height: 4),
                // Dizer em que etapa está resolve metade da dúvida; a outra
                // metade é "e agora, o que acontece / o que eu faço?".
                _Callout(
                  icone: Icons.hourglass_bottom_rounded,
                  texto: proxima != null
                      ? 'Você está em "${atual?.nome ?? status}". '
                          'O RH analisa as candidaturas desta etapa e avisa '
                          'por e-mail quando ela avançar para '
                          '"${proxima.nome}". Não é preciso fazer nada agora.'
                      : 'Você chegou à última etapa do processo. '
                          'O RH entrará em contato com os próximos passos.',
                ),
              ],
            ),
    );
  }
}

/// Coluna da direita: o que o candidato pode fazer.
class _ColunaAcoes extends StatelessWidget {
  const _ColunaAcoes({required this.estado, required this.descartado});

  final _AreaBodyState estado;
  final bool descartado;

  @override
  Widget build(BuildContext context) {
    final data = estado.widget.data;
    final mensagens = (data['mensagens'] as List?) ?? const [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!descartado) ...[
          _AvaliacaoCard(
            avaliacao: estado._avaliacao,
            busy: estado._busy,
            onIniciar: estado._fazerAvaliacao,
          ),
          const SizedBox(height: 16),
        ],
        _MensagensCard(
          mensagens: mensagens,
          controller: estado._msgController,
          busy: estado._busy,
          onEnviar: estado._sendMessage,
        ),
        const SizedBox(height: 16),
        _DocumentosCard(busy: estado._busy, onEnviar: estado._uploadDoc),
      ],
    );
  }
}

/// Card da avaliação técnica.
///
/// Todos os estados vêm resolvidos do servidor (S061/RH-12): a tela nunca
/// oferece um botão que leva a "nenhuma avaliação disponível".
class _AvaliacaoCard extends StatelessWidget {
  const _AvaliacaoCard({
    required this.avaliacao,
    required this.busy,
    required this.onIniciar,
  });

  final Map<String, dynamic> avaliacao;
  final bool busy;
  final VoidCallback onIniciar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final estado = (avaliacao['estado'] as String?) ?? 'indisponivel';
    final nota = (avaliacao['nota'] as num?)?.toInt();
    final total = (avaliacao['total_questoes'] as num?)?.toInt();
    final minutos = (avaliacao['limite_minutos'] as num?)?.toInt();

    Widget corpo;
    switch (estado) {
      case 'concluida':
        corpo = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Avaliação concluída. Nada mais é necessário da sua parte.',
                style: TextStyle(color: theme.colorScheme.outline)),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text('${nota ?? 0}',
                    style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.primary)),
                Text(' / 100',
                    style: TextStyle(color: theme.colorScheme.outline)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'A nota é um dos fatores que o RH considera — não decide '
              'sozinha o resultado do processo.',
              style:
                  TextStyle(fontSize: 12.5, color: theme.colorScheme.outline),
            ),
          ],
        );
        break;

      case 'expirada':
        corpo = const _Callout(
          icone: Icons.timer_off_outlined,
          texto: 'O tempo da avaliação terminou antes do envio, então ela foi '
              'encerrada. Se precisar de uma nova chance, peça ao RH pelas '
              'mensagens.',
        );
        break;

      case 'em_andamento':
        corpo = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                'Você tem uma avaliação em andamento. Continue de onde parou '
                '— as questões são as mesmas.',
                style: TextStyle(color: theme.colorScheme.outline)),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: busy ? null : onIniciar,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Continuar avaliação'),
            ),
          ],
        );
        break;

      case 'disponivel':
        corpo = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Responda algumas questões objetivas para complementar sua '
              'candidatura.',
              style: TextStyle(color: theme.colorScheme.outline, height: 1.4),
            ),
            const SizedBox(height: 12),
            // Regras antes do clique, não depois: quantas questões, quanto
            // tempo e que não dá para refazer. Começar uma prova cronometrada
            // sem saber disso é o tipo de surpresa que faz o candidato perder
            // a chance.
            _Regra(
                icone: Icons.help_outline,
                texto: total != null
                    ? '$total questões de múltipla escolha'
                    : 'Poucas questões de múltipla escolha'),
            _Regra(
              icone: Icons.schedule_rounded,
              texto: minutos != null
                  ? 'Tempo limite de $minutos minutos, contado a partir do '
                      'início'
                  : 'Sem tempo limite',
            ),
            const _Regra(
                icone: Icons.lock_clock,
                texto: 'Só pode ser feita uma vez — não dá para refazer'),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: busy ? null : onIniciar,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Iniciar avaliação'),
            ),
          ],
        );
        break;

      default: // indisponivel
        // Estado neutro e explicado. Antes, este texto só aparecia DEPOIS de
        // clicar em "Iniciar avaliação" — o candidato levava um beco sem saída.
        corpo = const _Callout(
          icone: Icons.info_outline_rounded,
          texto: 'Esta empresa não pediu avaliação técnica para a sua '
              'candidatura. Se isso mudar, o aviso aparece aqui e você recebe '
              'um e-mail.',
        );
    }

    return _Bloco(
      titulo: 'Avaliação técnica',
      icone: Icons.quiz_outlined,
      child: corpo,
    );
  }
}

class _MensagensCard extends StatelessWidget {
  const _MensagensCard({
    required this.mensagens,
    required this.controller,
    required this.busy,
    required this.onEnviar,
  });

  final List<dynamic> mensagens;
  final TextEditingController controller;
  final bool busy;
  final VoidCallback onEnviar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFmt = DateFormat('dd/MM/yyyy HH:mm');

    return _Bloco(
      titulo: 'Conversa com o RH',
      icone: Icons.forum_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (mensagens.isEmpty)
            const _Callout(
              icone: Icons.chat_bubble_outline_rounded,
              texto: 'Nenhuma mensagem ainda. Use o campo abaixo para tirar '
                  'dúvidas sobre o processo — o RH responde por aqui e você '
                  'recebe um aviso por e-mail.',
            )
          else
            for (final m in mensagens)
              _MessageBubble(
                autor: (m['autor'] as String?) ?? 'rh',
                texto: (m['texto'] as String?) ?? '',
                anexoLink: m['anexo_link'] as String?,
                anexoNome: m['anexo_nome'] as String?,
                quando: dateFmt.format(
                    DateTime.parse(m['created_at'] as String).toLocal()),
              ),
          const SizedBox(height: 14),
          TextField(
            controller: controller,
            textInputAction: TextInputAction.send,
            minLines: 1,
            maxLines: 4,
            onSubmitted: (_) => onEnviar(),
            decoration: InputDecoration(
              labelText: 'Escrever para o RH',
              hintText: 'Ex.: tenho disponibilidade para entrevista à tarde.',
              alignLabelWithHint: true,
              suffixIcon: IconButton(
                tooltip: 'Enviar',
                icon: const Icon(Icons.send_rounded),
                onPressed: busy ? null : onEnviar,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Não envie senhas nem dados bancários por aqui.',
            style: TextStyle(fontSize: 12, color: theme.colorScheme.outline),
          ),
        ],
      ),
    );
  }
}

class _DocumentosCard extends StatelessWidget {
  const _DocumentosCard({required this.busy, required this.onEnviar});

  final bool busy;
  final VoidCallback onEnviar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Bloco(
      titulo: 'Documentos',
      icone: Icons.folder_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Envie apenas o que o RH pedir pelas mensagens — como RG, CPF ou '
            'comprovante de escolaridade. Nada aqui é obrigatório.',
            style: TextStyle(color: theme.colorScheme.outline, height: 1.4),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: busy ? null : onEnviar,
            style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14)),
            icon: const Icon(Icons.attach_file_rounded),
            label: const Text('Escolher arquivo'),
          ),
          const SizedBox(height: 6),
          Text('PDF, DOCX, JPG ou PNG, de até 10 MB.',
              style: TextStyle(fontSize: 12, color: theme.colorScheme.outline)),
        ],
      ),
    );
  }
}

/// Card padrão da tela: título com ícone, conteúdo e um trailing opcional.
/// Uniformiza espaçamento e hierarquia — antes cada seção tinha o seu.
class _Bloco extends StatelessWidget {
  const _Bloco({
    required this.titulo,
    required this.icone,
    required this.child,
    this.trailing,
  });

  final String titulo;
  final IconData icone;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icone, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(titulo,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

/// Aviso destacado do fluxo normal do card (explicação, estado vazio).
class _Callout extends StatelessWidget {
  const _Callout({required this.icone, required this.texto});

  final IconData icone;
  final String texto;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, size: 18, color: theme.colorScheme.outline),
          const SizedBox(width: 10),
          Expanded(
            child: Text(texto,
                style: TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: theme.colorScheme.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }
}

/// Linha de regra da avaliação (quantidade, tempo, tentativa única).
class _Regra extends StatelessWidget {
  const _Regra({required this.icone, required this.texto});

  final IconData icone;
  final String texto;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, size: 16, color: theme.colorScheme.outline),
          const SizedBox(width: 8),
          Expanded(
            child:
                Text(texto, style: const TextStyle(fontSize: 13, height: 1.35)),
          ),
        ],
      ),
    );
  }
}

class _TimelineStep extends StatelessWidget {
  const _TimelineStep({
    required this.label,
    required this.done,
    required this.current,
    required this.last,
  });

  final String label;
  final bool done;
  final bool current;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = done || current
        ? theme.colorScheme.primary
        : theme.colorScheme.outlineVariant;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Icon(
                done
                    ? Icons.check_circle
                    : current
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                color: color,
                size: 22,
              ),
              if (!last) Expanded(child: Container(width: 2, color: color)),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 16, top: 1),
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontWeight: current ? FontWeight.w700 : FontWeight.w400,
                        color:
                            done || current ? null : theme.colorScheme.outline,
                      ),
                    ),
                  ),
                  // Marca explícita de "você está aqui": negrito sozinho é
                  // fraco demais para carregar a informação principal da tela.
                  if (current) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text('Você está aqui',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.onPrimary)),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.autor,
    required this.texto,
    required this.quando,
    this.anexoLink,
    this.anexoNome,
  });

  final String autor;
  final String texto;
  final String quando;
  final String? anexoLink;
  final String? anexoNome;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCandidato = autor == 'candidato';

    return Align(
      alignment: isCandidato ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 380),
        decoration: BoxDecoration(
          color: isCandidato
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Sem isto, mensagem do RH e do candidato só se distinguem pelo
            // lado da bolha — que some quando as duas são curtas.
            Text(isCandidato ? 'Você' : 'RH',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.primary)),
            const SizedBox(height: 2),
            if (texto.isNotEmpty) Text(texto),
            if (anexoLink != null)
              InkWell(
                onTap: () => launchUrl(Uri.parse(anexoLink!),
                    mode: LaunchMode.externalApplication),
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.attach_file_rounded, size: 16),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          anexoNome ?? 'Anexo',
                          style: const TextStyle(
                              decoration: TextDecoration.underline),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 2),
            Text(quando,
                style:
                    TextStyle(fontSize: 11, color: theme.colorScheme.outline)),
          ],
        ),
      ),
    );
  }
}
