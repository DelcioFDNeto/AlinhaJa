import 'package:flutter/material.dart';

/// Campo de texto com sugestões (área de interesse, cargo pretendido).
///
/// Combina preset e texto livre de propósito: a lista guia o candidato para
/// as grafias que o RH usa nos filtros, mas nenhum catálogo cobre todo cargo
/// que existe — quem não se encontrar na lista digita o próprio.
///
/// A lista abre ao focar o campo (mesmo vazio) e vai filtrando conforme se
/// digita, ignorando acento e caixa: "tecnologia" acha "Tecnologia da
/// Informação" e "grafico" acha "Designer Gráfico".
class PresetField extends StatefulWidget {
  const PresetField({
    super.key,
    required this.controller,
    required this.label,
    required this.options,
    this.hint,
    this.icon,
    this.validator,
    this.onChanged,
    this.emptyOptionsHint,
  });

  final TextEditingController controller;
  final String label;
  final List<String> options;
  final String? hint;
  final IconData? icon;
  final String? Function(String?)? validator;

  /// Chamado a cada alteração — digitada ou escolhida na lista.
  final ValueChanged<String>? onChanged;

  /// Texto do rodapé da lista, lembrando que dá para digitar outro valor.
  final String? emptyOptionsHint;

  @override
  State<PresetField> createState() => _PresetFieldState();
}

class _PresetFieldState extends State<PresetField> {
  final _focusNode = FocusNode();
  final _layerLink = LayerLink();
  OverlayEntry? _overlay;
  List<String> _filtradas = const [];

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_aoMudarFoco);
    widget.controller.addListener(_aoDigitar);
    _filtradas = widget.options;
  }

  @override
  void didUpdateWidget(covariant PresetField old) {
    super.didUpdateWidget(old);
    // A lista de cargos muda quando o candidato troca a área.
    if (old.options != widget.options) {
      _filtrar();
      _overlay?.markNeedsBuild();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_aoDigitar);
    _focusNode.removeListener(_aoMudarFoco);
    _removerOverlay();
    _focusNode.dispose();
    super.dispose();
  }

  void _aoMudarFoco() {
    if (_focusNode.hasFocus) {
      _filtrar();
      _mostrarOverlay();
    } else {
      _removerOverlay();
    }
  }

  void _aoDigitar() {
    if (!_focusNode.hasFocus) return;
    _filtrar();
    if (_filtradas.isEmpty) {
      _removerOverlay();
    } else {
      _mostrarOverlay();
      _overlay?.markNeedsBuild();
    }
  }

  void _filtrar() {
    final termo = _chave(widget.controller.text);
    if (termo.isEmpty) {
      _filtradas = widget.options;
      return;
    }
    final comeca = <String>[];
    final contem = <String>[];
    for (final o in widget.options) {
      final k = _chave(o);
      if (k.startsWith(termo)) {
        comeca.add(o);
      } else if (k.contains(termo)) {
        contem.add(o);
      }
    }
    // Já digitou exatamente uma opção: não faz sentido manter a lista
    // aberta cobrindo o resto do formulário.
    if (comeca.length == 1 && contem.isEmpty && _chave(comeca.first) == termo) {
      _filtradas = const [];
      return;
    }
    _filtradas = [...comeca, ...contem];
  }

  void _escolher(String valor) {
    widget.controller.value = TextEditingValue(
      text: valor,
      selection: TextSelection.collapsed(offset: valor.length),
    );
    widget.onChanged?.call(valor);
    _removerOverlay();
    _focusNode.unfocus();
  }

  void _mostrarOverlay() {
    if (_overlay != null || _filtradas.isEmpty) return;
    _overlay = OverlayEntry(builder: _construirLista);
    Overlay.of(context).insert(_overlay!);
  }

  void _removerOverlay() {
    _overlay?.remove();
    _overlay = null;
  }

  Widget _construirLista(BuildContext context) {
    // A lista pode esvaziar entre a inserção e o rebuild (troca de área,
    // texto que casou exato). Painel vazio flutuando é pior que nada.
    if (_filtradas.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final box = this.context.findRenderObject() as RenderBox?;
    final largura = box?.size.width ?? 320;
    // Espaço real abaixo do campo: perto do rodapé (ou com o teclado
    // aberto), a lista sobe em vez de ficar fora da tela.
    final origem = box?.localToGlobal(Offset.zero);
    final alturaTela = MediaQuery.of(context).size.height;
    final abaixo = origem == null
        ? alturaTela
        : alturaTela - origem.dy - (box?.size.height ?? 0) - 24;
    final acima = origem?.dy ?? 0;
    final paraCima = abaixo < 180 && acima > abaixo;
    final altura = (paraCima ? acima : abaixo).clamp(120.0, 280.0);

    return Positioned(
      width: largura,
      child: CompositedTransformFollower(
        link: _layerLink,
        showWhenUnlinked: false,
        targetAnchor: paraCima ? Alignment.topLeft : Alignment.bottomLeft,
        followerAnchor: paraCima ? Alignment.bottomLeft : Alignment.topLeft,
        offset: Offset(0, paraCima ? -6 : 6),
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          color: theme.colorScheme.surfaceContainerHigh,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: altura),
            child: ListView(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              children: [
                for (final o in _filtradas)
                  InkWell(
                    onTap: () => _escolher(o),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 11),
                      child: Text(o, style: const TextStyle(fontSize: 14)),
                    ),
                  ),
                if (widget.emptyOptionsHint != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
                    child: Text(
                      widget.emptyOptionsHint!,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: TextFormField(
        controller: widget.controller,
        focusNode: _focusNode,
        validator: widget.validator,
        onChanged: widget.onChanged,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: widget.hint,
          prefixIcon: widget.icon == null ? null : Icon(widget.icon, size: 20),
          suffixIcon: IconButton(
            tooltip: 'Ver sugestões',
            icon: const Icon(Icons.arrow_drop_down),
            onPressed: () {
              if (_overlay != null) {
                _removerOverlay();
                _focusNode.unfocus();
              } else {
                // Abrir a lista completa é mais útil do que filtrar pelo que
                // já está escrito quando o candidato quer trocar de opção.
                widget.controller.clear();
                _focusNode.requestFocus();
              }
            },
          ),
        ),
      ),
    );
  }
}

/// Comparação tolerante a acento, caixa e pontuação.
String _chave(String s) {
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    b.write(const {
          'á': 'a',
          'à': 'a',
          'ã': 'a',
          'â': 'a',
          'ä': 'a',
          'é': 'e',
          'è': 'e',
          'ê': 'e',
          'ë': 'e',
          'í': 'i',
          'ì': 'i',
          'î': 'i',
          'ï': 'i',
          'ó': 'o',
          'ò': 'o',
          'õ': 'o',
          'ô': 'o',
          'ö': 'o',
          'ú': 'u',
          'ù': 'u',
          'û': 'u',
          'ü': 'u',
          'ç': 'c',
          'ñ': 'n',
        }[ch] ??
        ch);
  }
  return b.toString().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
}
