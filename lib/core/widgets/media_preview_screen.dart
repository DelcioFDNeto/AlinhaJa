import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// Resultado da tela de preview: o que efetivamente será enviado.
class MediaPreviewResult {
  final List<XFile> files;
  final String? caption;

  /// Envio em "visualização única": some depois de aberto pelo destinatário.
  final bool isViewOnce;

  const MediaPreviewResult({
    required this.files,
    this.caption,
    this.isViewOnce = false,
  });
}

/// Confirmação antes de enviar mídia.
///
/// Antes o arquivo escolhido subia direto, sem chance de conferir nem de
/// desistir. Aqui o usuário vê o que escolheu, remove o que não quer, escreve
/// uma legenda e só então envia.
class MediaPreviewScreen extends StatefulWidget {
  final List<XFile> files;

  /// Nome do destino, mostrado no topo ("Enviar para Financeiro").
  final String destinationName;

  /// Libera o botão de visualização única (o "1" do WhatsApp). Só faz sentido
  /// para foto e vídeo — documentos continuam sempre em envio normal.
  final bool allowViewOnce;

  const MediaPreviewScreen({
    super.key,
    required this.files,
    required this.destinationName,
    this.allowViewOnce = false,
  });

  /// Abre o preview e devolve o que enviar, ou `null` se o usuário desistir.
  static Future<MediaPreviewResult?> show(
    BuildContext context, {
    required List<XFile> files,
    required String destinationName,
    bool allowViewOnce = false,
  }) {
    if (files.isEmpty) return Future.value(null);
    return Navigator.of(context).push<MediaPreviewResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => MediaPreviewScreen(
          files: files,
          destinationName: destinationName,
          allowViewOnce: allowViewOnce,
        ),
      ),
    );
  }

  @override
  State<MediaPreviewScreen> createState() => _MediaPreviewScreenState();
}

class _MediaPreviewScreenState extends State<MediaPreviewScreen> {
  late final List<XFile> _files = List<XFile>.from(widget.files);
  final _captionController = TextEditingController();
  final _pageController = PageController();
  int _index = 0;
  bool _viewOnce = false;

  @override
  void dispose() {
    _captionController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  bool _isVideo(XFile file) {
    final path = file.path.toLowerCase();
    final name = file.name.toLowerCase();
    return path.endsWith('.mp4') ||
        path.endsWith('.mov') ||
        name.endsWith('.mp4') ||
        name.endsWith('.mov');
  }

  bool _isImage(XFile file) {
    final name = file.name.toLowerCase();
    return name.endsWith('.jpg') ||
        name.endsWith('.jpeg') ||
        name.endsWith('.png') ||
        name.endsWith('.gif') ||
        name.endsWith('.webp') ||
        name.endsWith('.heic');
  }

  void _removeCurrent() {
    setState(() {
      _files.removeAt(_index);
      if (_files.isEmpty) return;
      if (_index >= _files.length) _index = _files.length - 1;
    });

    if (_files.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    _pageController.jumpToPage(_index);
  }

  /// Visualização única só vale para foto e vídeo: com documento no lote o
  /// botão nem aparece.
  bool get _canUseViewOnce =>
      widget.allowViewOnce &&
      _files.isNotEmpty &&
      _files.every((f) => _isImage(f) || _isVideo(f));

  void _send() {
    final caption = _captionController.text.trim();
    Navigator.of(context).pop(
      MediaPreviewResult(
        files: _files,
        caption: caption.isEmpty ? null : caption,
        isViewOnce: _canUseViewOnce && _viewOnce,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          _files.length == 1
              ? 'Enviar para ${widget.destinationName}'
              : '${_index + 1} de ${_files.length} • ${widget.destinationName}',
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Remover este arquivo',
            onPressed: _removeCurrent,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              itemCount: _files.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (context, i) => Center(child: _buildItem(_files[i])),
            ),
          ),

          // Tiras de miniaturas quando há mais de um arquivo.
          if (_files.length > 1)
            SizedBox(
              height: 72,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _files.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final selected = i == _index;
                  return GestureDetector(
                    onTap: () {
                      setState(() => _index = i);
                      _pageController.jumpToPage(i);
                    },
                    child: Container(
                      width: 56,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: selected
                              ? theme.colorScheme.primary
                              : Colors.white24,
                          width: selected ? 2 : 1,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: _buildThumb(_files[i]),
                    ),
                  );
                },
              ),
            ),

          // Aviso do modo temporário — aparece só quando está ligado, sem
          // interromper o envio com uma caixa de diálogo.
          if (_canUseViewOnce)
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              child: _viewOnce
                  ? Container(
                      width: double.infinity,
                      color: Colors.black,
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                      child: Row(
                        children: [
                          Icon(Icons.timer_outlined,
                              size: 14, color: theme.colorScheme.primary),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Visualização única · some depois de ser aberta',
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),

          // Legenda + visualização única + botão de enviar
          Container(
            color: Colors.black,
            padding: EdgeInsets.only(
              left: 12,
              right: 12,
              top: 8,
              bottom: MediaQuery.of(context).viewInsets.bottom + 12,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _captionController,
                    style: const TextStyle(color: Colors.white),
                    maxLines: 4,
                    minLines: 1,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: 'Adicione uma legenda...',
                      hintStyle: const TextStyle(color: Colors.white54),
                      filled: true,
                      fillColor: Colors.white10,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      // Botão "1" dentro do campo, como no WhatsApp.
                      suffixIcon: _canUseViewOnce
                          ? Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: _ViewOnceToggle(
                                active: _viewOnce,
                                onTap: () =>
                                    setState(() => _viewOnce = !_viewOnce),
                              ),
                            )
                          : null,
                      suffixIconConstraints: const BoxConstraints(
                          minWidth: 40, minHeight: 40),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FloatingActionButton(
                  onPressed: _send,
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                  child: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItem(XFile file) {
    if (_isImage(file)) {
      return InteractiveViewer(
        maxScale: 4,
        child: kIsWeb
            ? Image.network(file.path, fit: BoxFit.contain)
            : Image.file(File(file.path), fit: BoxFit.contain),
      );
    }

    // Vídeo e documento não têm preview visual aqui: mostramos a ficha do
    // arquivo, que já responde "é isso mesmo que eu escolhi?".
    return _FileCard(
      icon: _isVideo(file) ? Icons.videocam : Icons.insert_drive_file,
      name: file.name,
    );
  }

  Widget _buildThumb(XFile file) {
    if (_isImage(file)) {
      return kIsWeb
          ? Image.network(file.path, fit: BoxFit.cover)
          : Image.file(File(file.path), fit: BoxFit.cover);
    }
    return Container(
      color: Colors.white12,
      child: Icon(
        _isVideo(file) ? Icons.videocam : Icons.insert_drive_file,
        color: Colors.white70,
      ),
    );
  }
}

/// Botão de visualização única — o "1" dentro do círculo, igual ao WhatsApp.
class _ViewOnceToggle extends StatelessWidget {
  final bool active;
  final VoidCallback onTap;

  const _ViewOnceToggle({required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = active ? theme.colorScheme.onPrimary : Colors.white70;

    return Tooltip(
      message: active
          ? 'Visualização única ativada'
          : 'Enviar em visualização única',
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? theme.colorScheme.primary : Colors.transparent,
            border: Border.all(color: active ? Colors.transparent : fg),
          ),
          alignment: Alignment.center,
          child: Text(
            '1',
            style: TextStyle(
              color: fg,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}

class _FileCard extends StatelessWidget {
  final IconData icon;
  final String name;

  const _FileCard({required this.icon, required this.name});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 88, color: Colors.white70),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
        ),
      ],
    );
  }
}
