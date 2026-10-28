import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'package:alinha_ja/core/ui/composer/composer_media.dart';
import 'package:alinha_ja/features/whiteboard/models/whiteboard_item.dart';
import 'package:alinha_ja/features/whiteboard/models/whiteboard_stroke.dart';
import 'package:alinha_ja/features/whiteboard/providers/whiteboard_provider.dart';
import 'package:alinha_ja/features/whiteboard/ui/widgets/whiteboard_item_view.dart';
import 'package:alinha_ja/features/whiteboard/ui/widgets/whiteboard_painter.dart';
import 'package:alinha_ja/features/whiteboard/ui/widgets/whiteboard_toolbar.dart';

/// Quadro branco colaborativo: todo mundo da conversa desenha junto, sobre
/// as imagens e arquivos que qualquer um tenha anexado.
class WhiteboardScreen extends ConsumerStatefulWidget {
  final String boardId;
  final String title;

  const WhiteboardScreen({
    super.key,
    required this.boardId,
    this.title = 'Quadro branco',
  });

  static Future<void> open(
    BuildContext context, {
    required String boardId,
    String title = 'Quadro branco',
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WhiteboardScreen(boardId: boardId, title: title),
      ),
    );
  }

  @override
  ConsumerState<WhiteboardScreen> createState() => _WhiteboardScreenState();
}

class _WhiteboardScreenState extends ConsumerState<WhiteboardScreen> {
  /// Traço em andamento, ainda no dedo do usuário.
  final List<Offset> _current = [];

  Color _color = const Color(0xFF1A1A1A);
  double _width = 3;
  WhiteboardTool _tool = WhiteboardTool.pen;

  /// Menor lado que um anexo pode ter depois de redimensionado, em unidades
  /// do quadro. Abaixo disso o CHECK do banco recusaria a linha e a alça de
  /// arrastar ficaria maior que o próprio anexo.
  static const double _minItemSide = 40;

  /// Quanto de um anexo precisa continuar dentro do quadro, em unidades do
  /// quadro. Ver [_dentroDoQuadro].
  static const double _margemVisivel = 60;

  WhiteboardNotifier get _notifier =>
      ref.read(whiteboardProvider(widget.boardId).notifier);

  /// Área quadrada onde o quadro é desenhado.
  ///
  /// O espaço lógico é um quadrado; encaixá-lo com sobra em vez de esticar
  /// garante que o desenho tenha a mesma forma no celular e no monitor de quem
  /// abriu junto — esticar deformaria círculos e texto à mão.
  Rect _boardRect(Size size) {
    final side = size.shortestSide;
    return Rect.fromLTWH(
      (size.width - side) / 2,
      (size.height - side) / 2,
      side,
      side,
    );
  }

  Offset? _toBoard(Offset local, Size size) {
    final rect = _boardRect(size);
    if (!rect.contains(local)) return null;

    return Offset(
      (local.dx - rect.left) / rect.width * WhiteboardStroke.canvasSize,
      (local.dy - rect.top) / rect.height * WhiteboardStroke.canvasSize,
    );
  }

  void _onPanStart(Offset local, Size size) {
    final point = _toBoard(local, size);
    if (point == null) return;
    setState(() => _current
      ..clear()
      ..add(point));
  }

  void _onPanUpdate(Offset local, Size size) {
    final point = _toBoard(local, size);
    if (point == null || _current.isEmpty) return;

    // Descarta micro-movimentos: menos pontos, menos JSON no banco e traço
    // igualmente suave.
    if ((point - _current.last).distance < 1.5) return;
    setState(() => _current.add(point));
  }

  Future<void> _onPanEnd() async {
    if (_current.length < 2) {
      setState(_current.clear);
      return;
    }

    final points = List<Offset>.from(_current);
    setState(_current.clear);

    await _notifier.addStroke(
      points: points,
      color: _color,
      width: _width,
      tool: _tool,
    );
  }

  // ── Anexos ───────────────────────────────────────────────

  Future<void> _attachFromGallery() async {
    final picker = ImagePicker();
    final picked = await picker.pickMultiImage(imageQuality: 90);
    for (final file in picked) {
      await _notifier.attachFile(file, asImage: true);
    }
    // Anexo recém-solto quase sempre precisa ser posicionado; entrar já no
    // modo mover evita que o primeiro gesto vire um risco por cima da imagem.
    if (picked.isNotEmpty && mounted) {
      setState(() => _tool = WhiteboardTool.move);
    }
  }

  Future<void> _attachFromCamera() async {
    final picker = ImagePicker();
    final shot =
        await picker.pickImage(source: ImageSource.camera, imageQuality: 90);
    if (shot == null) return;

    await _notifier.attachFile(shot, asImage: true);
    if (mounted) setState(() => _tool = WhiteboardTool.move);
  }

  Future<void> _attachDocument() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.any,
      withData: true,
    );
    final files = result == null
        ? const <XFile>[]
        : ComposerMedia.toXFiles(result.files);
    if (files.isEmpty) return;

    final file = files.first;

    // O picker de documentos também devolve foto: quem escolhe um .png ali
    // espera desenhar em cima, não ganhar um cartão de arquivo.
    await _notifier.attachFile(
      file,
      asImage: ComposerMedia.isVisualMedia(file),
    );
    if (mounted) setState(() => _tool = WhiteboardTool.move);
  }

  void _dragItem(String itemId, Offset boardDelta) {
    // A base do delta vem do provider, não do `item` capturado no build: dois
    // eventos de ponteiro no mesmo frame partiriam da mesma posição antiga e
    // o anexo ficaria para trás do dedo.
    final item = _notifier.itemById(itemId);
    if (item == null) return;

    _notifier.previewItemGeometry(
      itemId,
      position: _dentroDoQuadro(item.position + boardDelta, item.size),
    );
  }

  /// Impede que o anexo seja arrastado para longe da folha.
  ///
  /// A camada de anexos é recortada no quadrado do quadro: sem o limite, um
  /// arrasto largo levaria a imagem para fora do recorte e ela sumiria — sem
  /// nada visível para arrastar de volta. Sempre fica uma alça de
  /// [_margemVisivel] dentro do quadro.
  Offset _dentroDoQuadro(Offset position, Size size) {
    const canvas = WhiteboardStroke.canvasSize;
    return Offset(
      position.dx.clamp(_margemVisivel - size.width, canvas - _margemVisivel),
      position.dy.clamp(_margemVisivel - size.height, canvas - _margemVisivel),
    );
  }

  void _resizeItem(String itemId, Offset boardDelta) {
    final item = _notifier.itemById(itemId);
    if (item == null) return;

    // A proporção é travada: redimensionar livre distorceria a foto anexada,
    // que é justamente a referência sobre a qual se está desenhando.
    final ratio = item.size.height / item.size.width;
    final newWidth =
        (item.size.width + boardDelta.dx).clamp(_minItemSide, 3000).toDouble();

    _notifier.previewItemGeometry(
      itemId,
      size: Size(newWidth, (newWidth * ratio).clamp(_minItemSide, 3000)),
    );
  }

  Future<void> _confirmRemoveItem(WhiteboardItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover anexo?'),
        content: Text(
          item.isImage
              ? 'A imagem sai do quadro para todo mundo. Os traços feitos em '
                  'cima dela continuam.'
              : '"${item.fileName ?? 'O arquivo'}" sai do quadro para todo '
                  'mundo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );

    if (confirmed == true) await _notifier.removeItem(item.id);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(whiteboardProvider(widget.boardId));
    final theme = Theme.of(context);

    ref.listen(whiteboardProvider(widget.boardId), (previous, next) {
      final error = next.error;
      if (error != null && error != previous?.error) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error)));
        _notifier.dismissError();
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(state.title.isEmpty ? widget.title : state.title,
                style: const TextStyle(fontSize: 17)),
            Text(
              _subtitle(state),
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.undo),
            tooltip: 'Desfazer meu último traço',
            onPressed: state.isLocked ? null : _notifier.undoMine,
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: 'Limpar traços',
            onPressed: state.isLocked ? null : _confirmClear,
          ),
        ],
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final size =
                          Size(constraints.maxWidth, constraints.maxHeight);
                      return _buildBoard(context, state, size);
                    },
                  ),
                ),
                if (!state.isLocked)
                  WhiteboardToolbar(
                    color: _color,
                    width: _width,
                    tool: _tool,
                    isUploading: state.isUploading,
                    onAttachImage: state.canAttach ? _attachFromGallery : null,
                    onAttachCamera: state.canAttach ? _attachFromCamera : null,
                    onAttachFile: state.canAttach ? _attachDocument : null,
                    onColorChanged: (c) => setState(() => _color = c),
                    onWidthChanged: (w) => setState(() => _width = w),
                    onToolChanged: (t) => setState(() => _tool = t),
                  ),
              ],
            ),
    );
  }

  String _subtitle(WhiteboardState state) {
    if (state.isLocked) return 'Somente leitura';

    final parts = <String>['${state.strokes.length} traço(s)'];
    if (state.items.isNotEmpty) parts.add('${state.items.length} anexo(s)');

    if (_tool == WhiteboardTool.move) {
      parts.add('arraste os anexos');
    } else {
      parts.add('todos podem desenhar');
    }

    return parts.join(' · ');
  }

  /// Empilha, de baixo para cima: folha branca → anexos → traços.
  ///
  /// A ordem é o recurso: o anexo é a base sobre a qual se desenha, então ele
  /// nunca pode cobrir a tinta.
  Widget _buildBoard(
      BuildContext context, WhiteboardState state, Size size) {
    final board = _boardRect(size);
    final scale = board.width / WhiteboardStroke.canvasSize;
    final moving = _tool == WhiteboardTool.move && !state.isLocked;

    final strokeLayer = CustomPaint(
      size: size,
      painter: WhiteboardPainter(
        strokes: state.strokes,
        board: board,
        // O fundo é um widget à parte para os anexos ficarem entre ele e a
        // tinta.
        paintBackground: false,
        liveStroke: _current,
        liveColor: _color,
        liveWidth: _width,
        liveTool: _tool,
      ),
    );

    final canDraw = !state.isLocked && _tool.isDrawing;

    return Stack(
      children: [
        // Folha do quadro.
        Positioned.fromRect(
          rect: board,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: const Color(0xFFE5E5EA)),
            ),
          ),
        ),

        // Instruções — só enquanto o quadro está totalmente vazio.
        if (state.strokes.isEmpty && state.items.isEmpty)
          Positioned.fromRect(
            rect: board,
            child: _EmptyBoardHint(canAttach: state.canAttach),
          ),

        // Anexos, na ordem de chegada e presos ao quadrado do quadro.
        //
        // O recorte importa: a área da tela é maior que o quadro (o quadrado
        // é encaixado com sobra), e sem ele um anexo arrastado para fora
        // ficaria boiando na margem, fora da folha — enquanto os traços,
        // esses sim, param na borda.
        Positioned.fromRect(
          rect: board,
          child: ClipRect(
            child: Stack(
              children: [
                for (final item in state.items)
                  Positioned(
                    left: item.position.dx * scale,
                    top: item.position.dy * scale,
                    width: item.size.width * scale,
                    height: item.size.height * scale,
                    child: WhiteboardItemView(
                      item: item,
                      scale: scale,
                      interactive: moving,
                      onDrag: (delta) => _dragItem(item.id, delta),
                      onResize: (delta) => _resizeItem(item.id, delta),
                      onGestureEnd: () =>
                          _notifier.commitItemGeometry(item.id),
                      onRemove: () => _confirmRemoveItem(item),
                    ),
                  ),
              ],
            ),
          ),
        ),

        // Tinta. No modo mover a camada deixa o toque passar para os anexos
        // logo abaixo; nas demais ferramentas é ela quem captura o gesto.
        Positioned.fill(
          child: IgnorePointer(
            ignoring: moving,
            child: GestureDetector(
              onPanStart:
                  canDraw ? (d) => _onPanStart(d.localPosition, size) : null,
              onPanUpdate:
                  canDraw ? (d) => _onPanUpdate(d.localPosition, size) : null,
              onPanEnd: canDraw ? (_) => _onPanEnd() : null,
              child: strokeLayer,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmClear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Limpar os traços?'),
        content: const Text(
          'Todos os traços somem para todo mundo. Só o autor do quadro pode '
          'fazer isso. Os anexos continuam no lugar — remova cada um pelo modo '
          'mover, se quiser.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Limpar'),
          ),
        ],
      ),
    );

    if (confirmed == true) await _notifier.clearAll();
  }
}

/// O que fazer num quadro em branco.
///
/// Quadro vazio é literalmente uma folha branca: sem uma palavra, ninguém
/// descobre que dá para anexar uma foto e desenhar em cima dela.
class _EmptyBoardHint extends StatelessWidget {
  const _EmptyBoardHint({required this.canAttach});

  final bool canAttach;

  @override
  Widget build(BuildContext context) {
    const muted = Color(0xFF8A8A8E);

    return IgnorePointer(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.draw, size: 44, color: muted),
              const SizedBox(height: 12),
              const Text(
                'Quadro em branco',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF5A5A5E),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                canAttach
                    ? 'Desenhe com o dedo ou o mouse. Para partir de algo que '
                        'já existe, use o botão de anexo na barra abaixo: a '
                        'imagem entra no quadro e o traço vai por cima dela.'
                    : 'Desenhe com o dedo ou o mouse. Tudo aparece ao vivo '
                        'para quem está na conversa.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12.5, color: muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
