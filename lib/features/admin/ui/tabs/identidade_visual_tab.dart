import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'package:alinha_ja/core/brand/brand_theme.dart';
import 'package:alinha_ja/core/brand/identidade_repository.dart';
import 'package:alinha_ja/core/brand/logo_empresa.dart';
import 'package:alinha_ja/core/brand/org_identity.dart';
import 'package:alinha_ja/core/constants.dart';
import 'package:alinha_ja/core/theme_provider.dart';
import 'package:alinha_ja/core/ui/widgets/responsive_width_container.dart';
import 'package:alinha_ja/core/utils/friendly_error.dart';
import 'package:alinha_ja/features/chat/data/image_compress_stub.dart'
    if (dart.library.js_interop) 'package:alinha_ja/features/chat/data/image_compress_web.dart';

/// Identidade visual da empresa em atuação: logo e cores.
///
/// É o white-label por empresa: cada cliente vê o próprio logo e as próprias
/// cores, sem nova build. Grava pela RPC `admin_set_org_identity` (admin da
/// empresa, auditada) e o tema do app muda na hora para todos os usuários
/// dela no próximo carregamento — e imediatamente para quem salvou.
class IdentidadeVisualTab extends ConsumerStatefulWidget {
  const IdentidadeVisualTab({super.key});

  /// Paleta sugerida: tons sóbrios, legíveis com texto branco.
  static const paleta = <Color>[
    Color(0xFFD21A18), Color(0xFFC62828), Color(0xFFAD1457),
    Color(0xFF6A1B9A), Color(0xFF4527A0), Color(0xFF283593),
    Color(0xFF1565C0), Color(0xFF00695C), Color(0xFF2E7D32),
    Color(0xFF558B2F), Color(0xFFEF6C00), Color(0xFF4E342E),
    Color(0xFF37474F), Color(0xFF212121),
  ];

  @override
  ConsumerState<IdentidadeVisualTab> createState() =>
      _IdentidadeVisualTabState();
}

class _IdentidadeVisualTabState extends ConsumerState<IdentidadeVisualTab> {
  String? _orgCarregada;
  String? _logoUrl;
  Uint8List? _logoNovo;
  Color? _primaria;
  Color? _secundaria;
  bool _salvando = false;

  /// Reidrata quando a empresa em atuação muda (dono da plataforma trocando
  /// de empresa): o formulário nunca mostra a identidade de outro cliente.
  void _hidratar(OrgIdentity id) {
    if (_orgCarregada == id.organizationId) return;
    _orgCarregada = id.organizationId;
    _logoUrl = id.logoUrl;
    _logoNovo = null;
    _primaria = id.corPrimaria;
    _secundaria = id.corSecundaria;
  }

  OrgIdentity get _previa => OrgIdentity(
        organizationId: _orgCarregada,
        logoUrl: _logoUrl,
        corPrimaria: _primaria,
        corSecundaria: _secundaria,
      );

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(orgIdentityProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(friendlyError(e))),
      data: (id) {
        _hidratar(id);
        final theme = Theme.of(context);
        return ResponsiveWidthContainer(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              Text(id.nome ?? '—',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                'Logo e cores desta empresa no ${AppConstants.appName}. '
                'Campos vazios usam o padrão do produto.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline, height: 1.4),
              ),
              const SizedBox(height: 24),
              _secaoLogo(theme),
              const SizedBox(height: 28),
              _SeletorCor(
                titulo: 'Cor principal',
                ajuda: 'Barras, botões, ícones e destaques.',
                cor: _primaria,
                rotuloPadrao: 'Padrão do produto',
                corPadrao: AppConstants.primary,
                habilitado: !_salvando,
                aoMudar: (c) => setState(() => _primaria = c),
              ),
              const SizedBox(height: 24),
              _SeletorCor(
                titulo: 'Cor secundária',
                ajuda: 'Detalhes de apoio. Opcional — sem ela, o app usa tons neutros.',
                cor: _secundaria,
                rotuloPadrao: 'Neutra',
                corPadrao: null,
                habilitado: !_salvando,
                aoMudar: (c) => setState(() => _secundaria = c),
              ),
              const SizedBox(height: 28),
              Text('Prévia', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              _Previa(identidade: _previa, logoNovo: _logoNovo),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _salvando ? null : () => _salvar(id),
                  icon: _salvando
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_rounded),
                  label: Text(_salvando ? 'Salvando...' : 'Salvar identidade visual'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Quem escolheu outro esquema de cores em Configurações continua '
                'com a própria escolha; o padrão de todos passa a ser este.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline, height: 1.45),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _secaoLogo(ThemeData theme) {
    final temLogo = _logoNovo != null || (_logoUrl?.isNotEmpty ?? false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Logo', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          'PNG, JPG ou WebP. Prefira fundo transparente e formato horizontal.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.outline),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Container(
              width: 160,
              height: 64,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: _logoNovo != null
                  ? Image.memory(_logoNovo!, fit: BoxFit.contain)
                  : (_logoUrl?.isNotEmpty ?? false)
                      ? Image.network(_logoUrl!,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) =>
                              const Icon(Icons.broken_image_outlined))
                      : Image.asset(LogoEmpresa.logoDoProduto,
                          fit: BoxFit.contain),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _salvando ? null : _escolherLogo,
                    icon: const Icon(Icons.upload_rounded, size: 18),
                    label: Text(temLogo ? 'Trocar logo' : 'Enviar logo'),
                  ),
                  if (temLogo)
                    TextButton.icon(
                      onPressed: _salvando
                          ? null
                          : () => setState(() {
                                _logoNovo = null;
                                _logoUrl = null;
                              }),
                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
                      label: const Text('Remover'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _escolherLogo() async {
    try {
      final imagem = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (imagem == null) return;
      final bytes = await imagem.readAsBytes();
      // WebP preserva a transparência e reduz o peso; o logo continua nítido.
      final comprimido = kIsWeb
          ? await compressImageWeb(bytes, quality: 90, maxWidth: 600)
          : await FlutterImageCompress.compressWithList(
              bytes,
              minWidth: 600,
              minHeight: 150,
              quality: 90,
              format: CompressFormat.webp,
            );
      if (comprimido.lengthInBytes > 2 * 1024 * 1024) {
        _avisar('O logo passou de 2 MB mesmo comprimido. Use uma imagem menor.',
            erro: true);
        return;
      }
      setState(() => _logoNovo = comprimido);
    } catch (e) {
      _avisar('Não foi possível abrir a imagem: ${friendlyError(e)}', erro: true);
    }
  }

  Future<void> _salvar(OrgIdentity atual) async {
    final orgId = atual.organizationId;
    if (orgId == null) {
      _avisar('Empresa não identificada. Recarregue a página.', erro: true);
      return;
    }
    setState(() => _salvando = true);
    final repo = ref.read(identidadeRepositoryProvider);
    try {
      var logo = _logoUrl;
      if (_logoNovo != null) {
        logo = await repo.enviarLogo(orgId: orgId, bytes: _logoNovo!);
      }
      await repo.salvar(
          logoUrl: logo, corPrimaria: _primaria, corSecundaria: _secundaria);
      if (atual.logoUrl != null && atual.logoUrl != logo) {
        await repo.removerLogoAntigo(atual.logoUrl);
      }
      _orgCarregada = null; // reidrata com o que o banco devolveu
      ref.invalidate(orgIdentityProvider);
      _avisar('Identidade visual salva.');
    } catch (e) {
      _avisar('Não foi possível salvar: ${friendlyError(e)}', erro: true);
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  void _avisar(String msg, {bool erro = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor:
          erro ? Theme.of(context).colorScheme.error : Colors.green.shade700,
    ));
  }
}

/// Escolha de cor: padrão, paleta sugerida ou código hexadecimal.
class _SeletorCor extends StatefulWidget {
  final String titulo;
  final String ajuda;
  final Color? cor;
  final String rotuloPadrao;
  final Color? corPadrao;
  final bool habilitado;
  final ValueChanged<Color?> aoMudar;

  const _SeletorCor({
    required this.titulo,
    required this.ajuda,
    required this.cor,
    required this.rotuloPadrao,
    required this.corPadrao,
    required this.habilitado,
    required this.aoMudar,
  });

  @override
  State<_SeletorCor> createState() => _SeletorCorState();
}

class _SeletorCorState extends State<_SeletorCor> {
  late final TextEditingController _hex = TextEditingController(
      text: widget.cor == null ? '' : OrgIdentity.hexDeCor(widget.cor!));

  @override
  void didUpdateWidget(covariant _SeletorCor antigo) {
    super.didUpdateWidget(antigo);
    final texto = widget.cor == null ? '' : OrgIdentity.hexDeCor(widget.cor!);
    if (widget.cor != antigo.cor &&
        OrgIdentity.corDeHex(_hex.text) != widget.cor) {
      _hex.text = texto;
    }
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cor = widget.cor;
    final aviso = cor == null ? null : _avisoContraste(cor);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.titulo, style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(widget.ajuda,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: Text(widget.rotuloPadrao),
              avatar: widget.corPadrao == null
                  ? const Icon(Icons.block_rounded, size: 16)
                  : _Amostra(cor: widget.corPadrao!, tamanho: 16),
              selected: cor == null,
              onSelected:
                  widget.habilitado ? (_) => widget.aoMudar(null) : null,
            ),
            for (final c in IdentidadeVisualTab.paleta)
              Semantics(
                label: OrgIdentity.hexDeCor(c),
                button: true,
                selected: cor == c,
                child: InkWell(
                  onTap: widget.habilitado ? () => widget.aoMudar(c) : null,
                  customBorder: const CircleBorder(),
                  child: _Amostra(cor: c, tamanho: 32, marcada: cor == c),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: 220,
          child: TextField(
            controller: _hex,
            enabled: widget.habilitado,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[#0-9a-fA-F]')),
              LengthLimitingTextInputFormatter(7),
            ],
            decoration: InputDecoration(
              labelText: 'Código da cor',
              hintText: '#1565C0',
              border: const OutlineInputBorder(),
              isDense: true,
              prefixIcon: Padding(
                padding: const EdgeInsets.all(10),
                child: _Amostra(
                    cor: cor ?? widget.corPadrao ?? theme.colorScheme.outline,
                    tamanho: 18),
              ),
              errorText: _hex.text.isNotEmpty &&
                      OrgIdentity.corDeHex(_hex.text) == null
                  ? 'Use o formato #RRGGBB'
                  : null,
            ),
            onChanged: (t) {
              setState(() {});
              if (t.isEmpty) return widget.aoMudar(null);
              final c = OrgIdentity.corDeHex(t);
              if (c != null) widget.aoMudar(c);
            },
          ),
        ),
        if (aviso != null) ...[
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.contrast_rounded,
                  size: 18, color: theme.colorScheme.error),
              const SizedBox(width: 8),
              Expanded(
                child: Text(aviso,
                    style: theme.textTheme.bodySmall?.copyWith(height: 1.4)),
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// Aviso (não bloqueia): cores muito claras somem sobre fundo branco.
  static String? _avisoContraste(Color cor) {
    if (!OrgIdentity.legivelComTexto(cor)) {
      return 'Texto sobre esta cor fica difícil de ler. Escolha um tom mais '
          'escuro ou mais claro.';
    }
    if (OrgIdentity.contraste(cor, Colors.white) < 3) {
      return 'Cor clara: ícones e textos nesta cor ficam pouco visíveis '
          'sobre fundo branco.';
    }
    return null;
  }
}

class _Amostra extends StatelessWidget {
  final Color cor;
  final double tamanho;
  final bool marcada;
  const _Amostra({required this.cor, required this.tamanho, this.marcada = false});

  @override
  Widget build(BuildContext context) {
    final marca = ThemeData.estimateBrightnessForColor(cor) == Brightness.dark
        ? Colors.white
        : Colors.black;
    return Container(
      width: tamanho,
      height: tamanho,
      decoration: BoxDecoration(
        color: cor,
        shape: BoxShape.circle,
        border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant, width: 1),
      ),
      child: marcada
          ? Icon(Icons.check_rounded, size: tamanho * 0.6, color: marca)
          : null,
    );
  }
}

/// Amostra do app com a identidade em edição, usando o mesmo construtor de
/// tema do app — o que aparece aqui é o que os usuários vão ver.
class _Previa extends StatelessWidget {
  final OrgIdentity identidade;
  final Uint8List? logoNovo;
  const _Previa({required this.identidade, this.logoNovo});

  @override
  Widget build(BuildContext context) {
    final escuro = Theme.of(context).brightness == Brightness.dark;
    final tema = escuro
        ? BrandTheme.escuro(AppThemeScheme.alinha, identidade)
        : BrandTheme.claro(AppThemeScheme.alinha, identidade);
    final logo = logoNovo != null
        ? Image.memory(logoNovo!, height: 28, fit: BoxFit.contain)
        : identidade.temLogo
            ? Image.network(identidade.logoUrl!,
                height: 28,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const SizedBox.shrink())
            : Image.asset(LogoEmpresa.logoDoProduto,
                height: 28, fit: BoxFit.contain);
    return Theme(
      data: tema,
      child: Builder(builder: (context) {
        final cs = Theme.of(context).colorScheme;
        return Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                key: const ValueKey('previa-barra'),
                color: cs.primary,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(children: [
                  logo,
                  const SizedBox(width: 10),
                  Text(AppConstants.appName,
                      style: TextStyle(
                          color: cs.onPrimary, fontWeight: FontWeight.w800)),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilledButton(onPressed: () {}, child: const Text('Novo card')),
                    OutlinedButton(onPressed: () {}, child: const Text('Filtrar')),
                    Chip(
                      avatar: Icon(Icons.campaign_rounded, color: cs.primary, size: 18),
                      label: const Text('Canal oficial'),
                    ),
                    Icon(Icons.star_rounded, color: cs.secondary),
                  ],
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}
