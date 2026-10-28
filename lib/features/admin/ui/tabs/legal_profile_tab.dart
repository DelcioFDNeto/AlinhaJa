import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alinha_ja/core/constants.dart';
import 'package:alinha_ja/core/ui/widgets/responsive_width_container.dart';
import 'package:alinha_ja/features/legal/models/org_legal_profile.dart';
import 'package:alinha_ja/features/legal/providers/legal_provider.dart';

/// Dados legais da empresa — o que preenche os documentos LGPD.
///
/// Os documentos em `docs/legal/` são o mesmo texto para todo tenant; o que os
/// individualiza é este cadastro. Enquanto ele estiver vazio, o titular lê
/// `[RAZÃO SOCIAL]` na tela e o documento não pode entrar em vigor.
///
/// Salva pela RPC `admin_set_org_legal_profile`, que resolve a empresa por
/// `fn_current_org()` — no produto white label, isso significa que o dono da
/// plataforma edita a empresa em que está atuando, não a própria.
class LegalProfileTab extends ConsumerStatefulWidget {
  const LegalProfileTab({super.key});

  @override
  ConsumerState<LegalProfileTab> createState() => _LegalProfileTabState();
}

class _LegalProfileTabState extends ConsumerState<LegalProfileTab> {
  final _controllers = <String, TextEditingController>{};
  bool _saving = false;

  /// Qual empresa está carregada no formulário.
  ///
  /// Era um booleano `_carregou`, e isso segurava os dados da empresa anterior
  /// depois que o dono da plataforma trocava de empresa em atuação: o formulário
  /// seguia exibindo — e pronto para salvar — o endereço e o Encarregado de
  /// outro cliente. Comparar o id força a reidratação na troca.
  String? _orgCarregada;

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _hydrate(OrgLegalProfile perfil) {
    if (_orgCarregada == perfil.organizationId) return;
    _orgCarregada = perfil.organizationId;

    for (final c in _controllers.values) {
      c.dispose();
    }
    _controllers.clear();

    for (final field in kLegalFields) {
      _controllers[field.key] =
          TextEditingController(text: perfil.valueOf(field.key) ?? '');
    }
    _controllers['dpo_telefone'] =
        TextEditingController(text: perfil.dpoTelefone ?? '');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final perfilAsync = ref.watch(orgLegalProfileProvider);

    return perfilAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Não foi possível carregar os dados legais.\n$e',
              textAlign: TextAlign.center),
        ),
      ),
      data: (perfil) {
        _hydrate(perfil);

        return ResponsiveWidthContainer(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              _Cabecalho(perfil: perfil),
              const SizedBox(height: 20),
              for (final field in kLegalFields) ...[
                TextField(
                  controller: _controllers[field.key],
                  enabled: !_saving,
                  decoration: InputDecoration(
                    labelText:
                        field.essential ? '${field.label} *' : field.label,
                    helperText: field.hint,
                    helperMaxLines: 2,
                    border: const OutlineInputBorder(),
                    suffixIcon: Tooltip(
                      message: 'Substitui ${field.placeholder} nos documentos',
                      child: Icon(Icons.info_outline,
                          size: 18, color: theme.colorScheme.outline),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              TextField(
                controller: _controllers['dpo_telefone'],
                enabled: !_saving,
                decoration: const InputDecoration(
                  labelText: 'Telefone do Encarregado',
                  helperText: 'Opcional — não aparece nos documentos públicos',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),
              _PrazosVigentes(perfil: perfil),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _salvar,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_rounded),
                  label: Text(_saving ? 'Salvando...' : 'Salvar dados legais'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'A alteração vale para os documentos já aceitos: o texto é '
                'renderizado na leitura, não congelado no aceite. Corrigir um '
                'dado cadastral não exige novo aceite; mudar uma regra de '
                'tratamento exige — e isso se faz subindo a versão do '
                'documento, não editando este cadastro.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                  height: 1.45,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _salvar() async {
    setState(() => _saving = true);

    String? v(String key) {
      final t = _controllers[key]?.text.trim() ?? '';
      return t.isEmpty ? null : t;
    }

    final perfil = OrgLegalProfile(
      razaoSocial: v('razao_social'),
      cnpj: v('cnpj'),
      endereco: v('endereco'),
      dpoNome: v('dpo_nome'),
      dpoEmail: v('dpo_email'),
      dpoTelefone: v('dpo_telefone'),
      comarca: v('comarca'),
      vigencia: v('vigencia'),
      regiaoHospedagem: v('regiao_hospedagem'),
      telefonePlantao: v('telefone_plantao'),
    );

    try {
      await ref.read(legalRepositoryProvider).saveLegalProfile(perfil);
      ref.invalidate(orgLegalProfileProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Dados legais salvos. Os documentos já refletem.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Não foi possível salvar: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _Cabecalho extends StatelessWidget {
  const _Cabecalho({required this.perfil});

  final OrgLegalProfile perfil;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final faltando = perfil.missingEssentials;
    final ok = faltando.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          // White label mostra o nome vindo do banco — é a empresa em atuação.
          // Empresa única cai na constante de build, nunca no nome do banco:
          // a linha semeada é a mesma nos dois forks e traz o nome do outro.
          AppConstants.isSingleTenant
              ? AppConstants.companyName
              : (perfil.nomeFantasia ?? '—'),
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          'Estes dados substituem os campos entre colchetes nos documentos '
          'LGPD desta empresa.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.outline, height: 1.4),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: (ok ? Colors.green : theme.colorScheme.error)
                .withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                ok ? Icons.verified_rounded : Icons.warning_amber_rounded,
                size: 18,
                color: ok ? Colors.green.shade700 : theme.colorScheme.error,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  ok
                      ? 'Todos os campos essenciais estão preenchidos.'
                      : 'Faltam ${faltando.length} campo(s) essencial(is): '
                          '${faltando.map((f) => f.label).join(', ')}.',
                  style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Prazos que o documento cita e que vêm da configuração do tenant, não deste
/// formulário — mostrados para o administrador conferir se o texto bate com a
/// operação real.
class _PrazosVigentes extends StatelessWidget {
  const _PrazosVigentes({required this.perfil});

  final OrgLegalProfile perfil;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Prazos citados nos documentos',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          _linha(theme, 'Histórico de localização',
              '${perfil.gpsRetencaoDias} dias'),
          _linha(theme, 'Candidatos no banco de talentos',
              '${perfil.candidatoRetencaoMeses} meses'),
          _linha(
            theme,
            'Mensagens',
            perfil.msgRetencaoDias > 0
                ? '${perfil.msgRetencaoDias} dias'
                : 'sem expiração automática',
            alerta: perfil.msgRetencaoDias <= 0,
          ),
          const SizedBox(height: 8),
          Text(
            'Vêm da configuração da empresa e entram no texto automaticamente. '
            'Retenção indefinida é transparente, mas desfavorável em '
            'fiscalização.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _linha(ThemeData theme, String rotulo, String valor,
      {bool alerta = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(rotulo, style: theme.textTheme.bodySmall)),
          Text(
            valor,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: alerta ? theme.colorScheme.error : null,
            ),
          ),
        ],
      ),
    );
  }
}
