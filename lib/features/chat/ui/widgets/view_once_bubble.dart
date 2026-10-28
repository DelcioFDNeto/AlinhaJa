import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'package:alinha_ja/core/services/media_url_resolver.dart';
import 'package:alinha_ja/features/chat/models/message_model.dart';
import 'package:alinha_ja/features/chat/providers/chat_provider.dart';

/// Mídia de visualização única, do lado de quem recebe.
///
/// Foto: os bytes são baixados em segundo plano assim que a bolha aparece —
/// sem exibir nada na conversa e sem cache em disco — e ao tocar ela abre na
/// hora. O consumo no servidor acontece ao ABRIR: fechar o app no meio da
/// visualização não deixa a mídia disponível para uma segunda vez.
///
/// Vídeo: toca em streaming a partir do Storage, então só pode ser consumido
/// depois que o visualizador fecha.
class ViewOnceBubble extends ConsumerStatefulWidget {
  const ViewOnceBubble({
    super.key,
    required this.message,
    required this.videoBuilder,
  });

  final MessageModel message;

  /// Player de vídeo da bolha (privado em message_bubble.dart).
  final WidgetBuilder videoBuilder;

  @override
  ConsumerState<ViewOnceBubble> createState() => _ViewOnceBubbleState();
}

class _ViewOnceBubbleState extends ConsumerState<ViewOnceBubble> {
  Future<Uint8List?>? _foto;
  bool _abrindo = false;

  bool get _isVideo => widget.message.contentType == ContentType.video;

  @override
  void initState() {
    super.initState();
    if (!_isVideo) _foto = _baixar();
  }

  Future<Uint8List?> _baixar() async {
    final stored = widget.message.mediaUrl;
    if (stored == null || stored.isEmpty) return null;
    try {
      final url = await MediaUrlResolver.resolve(stored);
      final resp =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
      return resp.statusCode == 200 ? resp.bodyBytes : null;
    } catch (e) {
      debugPrint('Visualização única: pré-carga falhou: $e');
      return null;
    }
  }

  Future<void> _abrir() async {
    if (_abrindo) return;
    setState(() => _abrindo = true);

    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final notifier = ref.read(chatProvider(ChatArgs(
      chatId: widget.message.chatId,
      threadId: widget.message.threadId,
    )).notifier);
    final messageId = widget.message.id;

    if (_isVideo) {
      final player = widget.videoBuilder(context);
      await _comTelaProtegida(() => navigator.push(_visualizador(player)));
      await notifier.openViewOnceMessage(messageId);
      return;
    }

    var bytes = await _foto;
    // A pré-carga pode ter falhado sem rede: uma nova tentativa no toque.
    bytes ??= await (_foto = _baixar());
    if (bytes == null) {
      if (mounted) setState(() => _abrindo = false);
      messenger.showSnackBar(const SnackBar(
        content: Text('Não foi possível abrir a mídia. Verifique a conexão '
            'e tente de novo.'),
      ));
      return;
    }

    // Os bytes já estão na memória: a mensagem sai do servidor antes mesmo
    // de a foto aparecer.
    unawaited(notifier.openViewOnceMessage(messageId));
    final foto = Image.memory(bytes, fit: BoxFit.contain);
    await _comTelaProtegida(() => navigator.push(_visualizador(foto)));
  }

  /// Bloqueia print e gravação de tela no Android enquanto a mídia aparece.
  Future<void> _comTelaProtegida(Future<void> Function() acao) async {
    const canal = MethodChannel('com.alinha_ja.app/lockscreen');
    if (!kIsWeb) {
      try {
        await canal.invokeMethod('enableSecureScreen');
      } catch (e) {
        debugPrint('Erro ao ativar proteção contra print: $e');
      }
    }
    try {
      await acao();
    } finally {
      if (!kIsWeb) {
        try {
          await canal.invokeMethod('disableSecureScreen');
        } catch (e) {
          debugPrint('Erro ao desativar proteção contra print: $e');
        }
      }
    }
  }

  Route<void> _visualizador(Widget conteudo) => MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            iconTheme: const IconThemeData(color: Colors.white),
            elevation: 0,
          ),
          extendBodyBehindAppBar: true,
          body: Center(child: conteudo),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: ElevatedButton.icon(
        icon: _abrindo
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                _isVideo ? Icons.videocam_rounded : Icons.photo_rounded,
                size: 18,
              ),
        label: Text(_isVideo ? 'Ver vídeo temporário' : 'Ver foto temporária'),
        onPressed: _abrindo ? null : _abrir,
      ),
    );
  }
}
