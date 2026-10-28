import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alinha_ja/core/status_tokens.dart';
import 'package:alinha_ja/features/hr/services/candidate_portal_service.dart';

/// RH-12 / Fase 3 — Prova objetiva do candidato (portal público).
/// Recebe as questões SEM gabarito; a correção é feita no servidor ao
/// enviar. Empurrada pela área do candidato via Navigator.
///
/// RH-23: quando a org configura um tempo limite, [expiraEm] chega
/// preenchido e a tela mostra a contagem regressiva, enviando sozinha o
/// que estiver respondido ao zerar. A contagem é só conforto visual —
/// quem decide se o prazo estourou é a Edge Function.
class CandidateTestScreen extends ConsumerStatefulWidget {
  const CandidateTestScreen({
    super.key,
    required this.token,
    required this.avaliacaoId,
    required this.questoes,
    this.expiraEm,
  });

  final String token;
  final String avaliacaoId;

  /// Cada questão: `{ id, enunciado, opcoes: [String] }`.
  final List<Map<String, dynamic>> questoes;

  /// Instante-limite devolvido pelo servidor. `null` = prova sem tempo.
  final DateTime? expiraEm;

  @override
  ConsumerState<CandidateTestScreen> createState() =>
      _CandidateTestScreenState();
}

class _CandidateTestScreenState extends ConsumerState<CandidateTestScreen> {
  final Map<String, int> _respostas = {}; // questao_id -> opcao_idx
  bool _enviando = false;
  String? _erro;

  Timer? _ticker;
  Duration _restante = Duration.zero;

  CandidatePortalService get _service => const CandidatePortalService();

  bool get _temPrazo => widget.expiraEm != null;

  @override
  void initState() {
    super.initState();
    if (!_temPrazo) return;
    _restante = _calcRestante();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final restante = _calcRestante();
      if (restante == Duration.zero) {
        _ticker?.cancel();
        // Auto-envio: o candidato não perde o que já respondeu.
        _enviar(porTempo: true);
      }
      if (mounted) setState(() => _restante = restante);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Duration _calcRestante() {
    final falta = widget.expiraEm!.difference(DateTime.now());
    return falta.isNegative ? Duration.zero : falta;
  }

  /// [porTempo] pula a exigência de responder tudo: no estouro do prazo
  /// vale mais enviar parcialmente do que perder a prova inteira.
  Future<void> _enviar({bool porTempo = false}) async {
    if (_enviando) return;
    if (!porTempo && _respostas.length < widget.questoes.length) {
      setState(() => _erro = 'Responda todas as questões antes de enviar.');
      return;
    }
    _ticker?.cancel();
    setState(() {
      _enviando = true;
      _erro = null;
    });
    final navigator = Navigator.of(context);
    try {
      final res = await _service.avaliacaoEnviar(
        token: widget.token,
        avaliacaoId: widget.avaliacaoId,
        respostas: [
          for (final e in _respostas.entries)
            {'questao_id': e.key, 'resposta_idx': e.value},
        ],
      );
      if (!mounted) return;
      navigator.pop(((res['nota'] ?? 0) as num).toInt());
    } on PortalException catch (e) {
      if (!mounted) return;
      // O servidor pode recusar por prazo vencido: aí a prova acabou.
      if (e.status == 409) {
        navigator.pop(0);
        return;
      }
      setState(() {
        _enviando = false;
        _erro = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _enviando = false;
        _erro = 'Falha ao enviar. Verifique sua conexão.';
      });
    }
  }

  Future<bool> _confirmSair() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sair da avaliação?'),
        content: Text(_temPrazo
            ? 'Suas respostas ainda não foram enviadas e serão perdidas. '
                'O cronômetro continua correndo mesmo se você sair.'
            : 'Suas respostas ainda não foram enviadas e serão perdidas.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Continuar prova')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Sair')),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final respondidas = _respostas.length;
    final total = widget.questoes.length;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        final sair = await _confirmSair();
        if (sair && mounted) navigator.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Avaliação técnica'),
          actions: [
            if (_temPrazo)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Center(child: _Cronometro(restante: _restante)),
              ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(4),
            child: LinearProgressIndicator(
              value: total > 0 ? respondidas / total : 0,
              minHeight: 4,
            ),
          ),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text('$respondidas de $total respondidas',
                    style: TextStyle(color: theme.colorScheme.outline)),
                if (_temPrazo && _restante <= _Cronometro.alertaFinal) ...[
                  const SizedBox(height: 8),
                  _AvisoTempo(restante: _restante),
                ],
                const SizedBox(height: 12),
                for (var i = 0; i < widget.questoes.length; i++)
                  _QuestaoTile(
                    numero: i + 1,
                    questao: widget.questoes[i],
                    selecionada:
                        _respostas[widget.questoes[i]['id'] as String],
                    onSelect: (idx) => setState(() =>
                        _respostas[widget.questoes[i]['id'] as String] = idx),
                  ),
                if (_erro != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_erro!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: theme.colorScheme.error)),
                  ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _enviando ? null : _enviar,
                  style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16)),
                  child: _enviando
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Enviar respostas'),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Relógio da AppBar. Fica neutro na maior parte da prova e assume o
/// token de alerta na reta final.
class _Cronometro extends StatelessWidget {
  const _Cronometro({required this.restante});

  /// Abaixo disto o relógio vira alerta visual.
  static const alertaFinal = Duration(minutes: 2);

  final Duration restante;

  static String mmss(Duration d) {
    final min = d.inMinutes.toString().padLeft(2, '0');
    final seg = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$min:$seg';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.statusTokens;
    final urgente = restante <= alertaFinal;
    final cor = urgente ? tokens.danger : theme.colorScheme.onSurfaceVariant;

    return Semantics(
      label: 'Tempo restante ${restante.inMinutes} minutos',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: urgente ? cor.withValues(alpha: 0.12) : null,
          border: Border.all(color: cor.withValues(alpha: urgente ? 0.6 : 0.3)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.timer, size: 16, color: cor),
            const SizedBox(width: 6),
            Text(
              mmss(restante),
              style: TextStyle(
                color: cor,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Faixa de aviso quando o prazo entra na reta final.
class _AvisoTempo extends StatelessWidget {
  const _AvisoTempo({required this.restante});

  final Duration restante;

  @override
  Widget build(BuildContext context) {
    final tokens = context.statusTokens;
    final acabou = restante == Duration.zero;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: tokens.danger.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.warning, size: 18, color: tokens.danger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              acabou
                  ? 'Tempo esgotado — enviando suas respostas…'
                  : 'Menos de ${_Cronometro.mmss(restante)} restantes. '
                      'Ao zerar, o que estiver respondido é enviado automaticamente.',
              style: TextStyle(fontSize: 12.5, color: tokens.danger),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuestaoTile extends StatelessWidget {
  const _QuestaoTile({
    required this.numero,
    required this.questao,
    required this.selecionada,
    required this.onSelect,
  });

  final int numero;
  final Map<String, dynamic> questao;
  final int? selecionada;
  final void Function(int idx) onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.statusTokens;
    final opcoes = ((questao['opcoes'] as List?) ?? const [])
        .map((e) => e.toString())
        .toList();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$numero. ${questao['enunciado']}',
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 12),
            for (var i = 0; i < opcoes.length; i++)
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => onSelect(i),
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 3),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: selecionada == i
                        ? tokens.highlight.withValues(alpha: 0.12)
                        : null,
                    border: Border.all(
                      color: selecionada == i
                          ? tokens.highlight
                          : theme.colorScheme.outlineVariant,
                      width: selecionada == i ? 2 : 1,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        selecionada == i
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        size: 20,
                        color: selecionada == i
                            ? tokens.highlight
                            : theme.colorScheme.outline,
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(opcoes[i])),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
