import 'dart:async';
import 'dart:ui' as ui show Color, Offset, Size, instantiateImageCodec;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:alinha_ja/core/constants.dart';
import 'package:alinha_ja/core/supabase_client.dart';
import 'package:alinha_ja/features/chat/data/media_service.dart';
import 'package:alinha_ja/features/whiteboard/models/whiteboard_item.dart';
import 'package:alinha_ja/features/whiteboard/models/whiteboard_stroke.dart';

/// Estado de um quadro aberto.
@immutable
class WhiteboardState {
  final List<WhiteboardStroke> strokes;

  /// Imagens e arquivos anexados, na ordem em que chegaram (o último fica
  /// por cima).
  final List<WhiteboardItem> items;

  final bool isLoading;
  final bool isLocked;
  final String title;

  /// Conversa dona do quadro. É de onde sai o prefixo do Storage, e por
  /// tabela só um dos dois é preenchido.
  final String? chatId;
  final String? channelId;

  /// Anexo em upload, para a tela mostrar progresso em vez de parecer travada.
  final bool isUploading;

  final String? error;

  const WhiteboardState({
    this.strokes = const [],
    this.items = const [],
    this.isLoading = true,
    this.isLocked = false,
    this.title = 'Quadro branco',
    this.chatId,
    this.channelId,
    this.isUploading = false,
    this.error,
  });

  /// Id da conversa usado como pasta no bucket `chat-media`. `MediaService`
  /// recebe chat e canal no mesmo parâmetro — o prefixo é `chats/` nos dois
  /// casos (ver 20260803130000_chat_media_membership_policies.sql).
  String? get storageOwnerId => chatId ?? channelId;

  /// O quadro aceita anexo: existe conversa dona e ele não está congelado.
  bool get canAttach => !isLocked && storageOwnerId != null;

  WhiteboardState copyWith({
    List<WhiteboardStroke>? strokes,
    List<WhiteboardItem>? items,
    bool? isLoading,
    bool? isLocked,
    String? title,
    String? chatId,
    String? channelId,
    bool? isUploading,
    String? error,
    bool clearError = false,
  }) =>
      WhiteboardState(
        strokes: strokes ?? this.strokes,
        items: items ?? this.items,
        isLoading: isLoading ?? this.isLoading,
        isLocked: isLocked ?? this.isLocked,
        title: title ?? this.title,
        chatId: chatId ?? this.chatId,
        channelId: channelId ?? this.channelId,
        isUploading: isUploading ?? this.isUploading,
        error: clearError ? null : (error ?? this.error),
      );
}

/// Traços e anexos de um quadro, com replicação ao vivo.
///
/// O traço aparece na tela assim que a mão levanta (otimista) e só depois é
/// gravado; se o insert falhar ele some e o erro aparece — desenhar não pode
/// depender de ida e volta ao servidor. O mesmo vale para arrastar um anexo.
class WhiteboardNotifier extends FamilyNotifier<WhiteboardState, String> {
  final _uuid = const Uuid();
  final _media = MediaService();
  RealtimeChannel? _channel;

  String get _boardId => arg;

  @override
  WhiteboardState build(String arg) {
    ref.onDispose(() {
      final channel = _channel;
      _channel = null;
      if (channel != null) supabase.removeChannel(channel);
    });

    _load();
    return const WhiteboardState();
  }

  Future<void> _load() async {
    try {
      final board = await supabase
          .from('whiteboards')
          .select('title, is_locked, chat_id, channel_id')
          .eq('id', _boardId)
          .maybeSingle();

      final rows = await supabase
          .from('whiteboard_strokes')
          .select()
          .eq('whiteboard_id', _boardId)
          .order('created_at', ascending: true);

      final itemRows = await supabase
          .from('whiteboard_items')
          .select()
          .eq('whiteboard_id', _boardId)
          .order('created_at', ascending: true);

      state = state.copyWith(
        strokes: [
          for (final row in rows as List)
            WhiteboardStroke.fromJson(Map<String, dynamic>.from(row))
        ],
        items: [
          for (final row in itemRows as List)
            WhiteboardItem.fromJson(Map<String, dynamic>.from(row))
        ],
        title: board?['title']?.toString() ?? 'Quadro branco',
        isLocked: board?['is_locked'] == true,
        chatId: board?['chat_id']?.toString(),
        channelId: board?['channel_id']?.toString(),
        isLoading: false,
        clearError: true,
      );

      _subscribe();
    } catch (e) {
      debugPrint('Erro ao carregar quadro: $e');
      state = state.copyWith(
        isLoading: false,
        error: 'Não foi possível abrir o quadro.',
      );
    }
  }

  void _subscribe() {
    _channel?.unsubscribe();

    final boardFilter = PostgresChangeFilter(
      type: PostgresChangeFilterType.eq,
      column: 'whiteboard_id',
      value: _boardId,
    );

    _channel = supabase
        .channel('whiteboard:$_boardId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'whiteboard_strokes',
          filter: boardFilter,
          callback: (payload) => _onRemoteInsert(payload.newRecord),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'whiteboard_strokes',
          callback: (payload) => _onRemoteDelete(payload.oldRecord),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'whiteboard_items',
          filter: boardFilter,
          callback: (payload) => _onRemoteItemUpsert(payload.newRecord),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'whiteboard_items',
          filter: boardFilter,
          callback: (payload) => _onRemoteItemUpsert(payload.newRecord),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'whiteboard_items',
          callback: (payload) => _onRemoteItemDelete(payload.oldRecord),
        )
        .subscribe();
  }

  void _onRemoteInsert(Map<String, dynamic> record) {
    final incoming = WhiteboardStroke.fromJson(record);
    if (incoming.id.isEmpty) return;

    // Traço próprio já está na tela desde o gesto: o eco do Realtime é
    // ignorado pelo id, senão a linha seria desenhada duas vezes.
    if (state.strokes.any((s) => s.id == incoming.id)) return;

    state = state.copyWith(strokes: [...state.strokes, incoming]);
  }

  void _onRemoteDelete(Map<String, dynamic> record) {
    // O DELETE do Postgres só traz a chave primária.
    final id = record['id']?.toString();
    if (id == null) return;

    state = state.copyWith(
      strokes: state.strokes.where((s) => s.id != id).toList(),
    );
  }

  /// INSERT e UPDATE de anexo caem aqui: o efeito é o mesmo — a linha do
  /// banco passa a ser a verdade sobre aquele item.
  ///
  /// Vale inclusive para o eco do próprio arrasto. Diferente do traço (que é
  /// imutável e só precisa não duplicar), aceitar o eco aqui é o que faz
  /// duas pessoas arrastando o mesmo anexo convergirem para a mesma posição
  /// em vez de cada tela ficar com a sua.
  void _onRemoteItemUpsert(Map<String, dynamic> record) {
    final incoming = WhiteboardItem.fromJson(record);
    if (incoming.id.isEmpty) return;

    final index = state.items.indexWhere((i) => i.id == incoming.id);
    if (index == -1) {
      state = state.copyWith(items: [...state.items, incoming]);
      return;
    }

    // Enquanto o dedo está no anexo, a posição autoritativa é a local: aceitar
    // o eco do servidor no meio do gesto faria o item pular para trás.
    if (_draggingItemId == incoming.id) return;

    final updated = [...state.items];
    updated[index] = incoming;
    state = state.copyWith(items: updated);
  }

  void _onRemoteItemDelete(Map<String, dynamic> record) {
    final id = record['id']?.toString();
    if (id == null) return;

    state = state.copyWith(
      items: state.items.where((i) => i.id != id).toList(),
    );
  }

  /// Registra um traço recém-desenhado.
  Future<void> addStroke({
    required List<ui.Offset> points,
    required ui.Color color,
    required double width,
    required WhiteboardTool tool,
  }) async {
    final myId = supabase.auth.currentUser?.id;
    if (myId == null || points.length < 2 || state.isLocked) return;

    // A ferramenta de mover não pinta: sem esta guarda um arrasto de anexo
    // gravaria um traço fantasma com `tool = 'move'`.
    if (!tool.isDrawing) return;

    final stroke = WhiteboardStroke(
      id: _uuid.v4(),
      whiteboardId: _boardId,
      authorId: myId,
      points: points,
      color: color,
      width: width,
      tool: tool,
      createdAt: DateTime.now().toUtc(),
    );

    state = state.copyWith(strokes: [...state.strokes, stroke]);

    try {
      await supabase.from('whiteboard_strokes').insert(stroke.toInsert());
    } catch (e) {
      debugPrint('Erro ao gravar traço: $e');
      state = state.copyWith(
        strokes: state.strokes.where((s) => s.id != stroke.id).toList(),
        error: 'O traço não foi salvo.',
      );
    }
  }

  /// Desfaz o último traço do usuário atual.
  Future<void> undoMine() async {
    final myId = supabase.auth.currentUser?.id;
    if (myId == null || state.isLocked) return;

    final mine = state.strokes.where((s) => s.authorId == myId).toList();
    if (mine.isEmpty) return;

    final last = mine.last;
    final backup = state.strokes;
    state = state.copyWith(
      strokes: state.strokes.where((s) => s.id != last.id).toList(),
    );

    try {
      await supabase.from('whiteboard_strokes').delete().eq('id', last.id);
    } catch (e) {
      debugPrint('Erro ao desfazer traço: $e');
      state = state.copyWith(strokes: backup, error: 'Não foi possível desfazer.');
    }
  }

  /// Limpa o quadro inteiro — a policy só deixa passar para o autor do quadro
  /// (e cada um sempre pode apagar os próprios traços).
  ///
  /// Os anexos ficam: apagá-los junto destruiria arquivo enviado por outra
  /// pessoa sem que a confirmação tenha avisado disso. Limpar o quadro é
  /// sobre o desenho.
  Future<void> clearAll() async {
    final backup = state.strokes;
    state = state.copyWith(strokes: const []);

    try {
      await supabase
          .from('whiteboard_strokes')
          .delete()
          .eq('whiteboard_id', _boardId);
    } catch (e) {
      debugPrint('Erro ao limpar quadro: $e');
      state = state.copyWith(
        strokes: backup,
        error: 'Só o autor do quadro pode limpar tudo.',
      );
    }
  }

  // ── Anexos ─────────────────────────────────────────────────

  /// Id do anexo sob o dedo. Ver [_onRemoteItemUpsert].
  String? _draggingItemId;

  /// Sobe um arquivo e o posiciona no centro do quadro.
  ///
  /// Imagem passa pela mesma compressão do chat (WebP, 1200px); qualquer
  /// outro tipo sobe como está e vira cartão. O arquivo vai para a pasta da
  /// conversa dona do quadro, então a autorização de leitura é a mesma da
  /// mídia trocada ali — não há caminho novo de Storage.
  Future<void> attachFile(XFile file, {bool asImage = true}) async {
    final myId = supabase.auth.currentUser?.id;
    final ownerId = state.storageOwnerId;

    if (myId == null || ownerId == null || state.isLocked) {
      state = state.copyWith(
        error: state.isLocked
            ? 'O quadro está trancado.'
            : 'Não foi possível identificar a conversa do quadro.',
      );
      return;
    }

    state = state.copyWith(isUploading: true, clearError: true);

    try {
      // A proporção sai do arquivo ORIGINAL, antes de qualquer compressão:
      // é ela que decide a forma do anexo no quadro.
      final source = asImage
          ? await _imageSize(file)
          : const ui.Size(4, 3);
      final placement = WhiteboardItem.fitToBoard(source);

      final upload = asImage
          ? await _media.compressAndUploadImage(chatId: ownerId, file: file)
          : await _media.uploadFile(
              chatId: ownerId,
              file: file,
              originalFileName: file.name,
            );

      final item = WhiteboardItem(
        id: _uuid.v4(),
        whiteboardId: _boardId,
        authorId: myId,
        kind: asImage ? WhiteboardItemKind.image : WhiteboardItemKind.file,
        mediaUrl: upload.publicUrl,
        storagePath: upload.filePath,
        fileName: file.name.isEmpty ? null : file.name,
        mimeType: upload.mimeType,
        sizeBytes: upload.sizeBytes,
        position: placement.position,
        size: placement.size,
        createdAt: DateTime.now().toUtc(),
      );

      await supabase.from('whiteboard_items').insert(item.toInsert());

      // O item entra pelo insert local; o eco do Realtime é reconhecido pelo
      // id em [_onRemoteItemUpsert] e não duplica.
      state = state.copyWith(
        items: [...state.items, item],
        isUploading: false,
      );
    } catch (e) {
      debugPrint('Erro ao anexar no quadro: $e');
      state = state.copyWith(
        isUploading: false,
        error: 'Não foi possível anexar o arquivo.',
      );
    }
  }

  /// Move/redimensiona um anexo enquanto o dedo está nele — só local.
  ///
  /// Gravar a cada frame do arrasto inundaria o Realtime de todo mundo com
  /// dezenas de UPDATEs por segundo. A gravação acontece uma vez, em
  /// [commitItemGeometry], quando o gesto termina.
  void previewItemGeometry(String itemId,
      {ui.Offset? position, ui.Size? size}) {
    final index = state.items.indexWhere((i) => i.id == itemId);
    if (index == -1 || state.isLocked) return;

    _draggingItemId = itemId;

    final updated = [...state.items];
    updated[index] = updated[index].copyWith(position: position, size: size);
    state = state.copyWith(items: updated);
  }

  /// Posição atual de um anexo, como o provider a conhece agora.
  ///
  /// O arrasto precisa somar o delta sobre o estado **corrente**, não sobre o
  /// que a tela capturou quando montou o widget: dois eventos de ponteiro no
  /// mesmo frame usariam a mesma base antiga e o segundo delta se perderia —
  /// o anexo "escorrega" atrás do dedo em movimento rápido.
  WhiteboardItem? itemById(String itemId) {
    final index = state.items.indexWhere((i) => i.id == itemId);
    return index == -1 ? null : state.items[index];
  }

  /// Grava a posição final do anexo.
  Future<void> commitItemGeometry(String itemId) async {
    _draggingItemId = null;

    // O anexo pode ter sido removido por outra pessoa no meio do arrasto: o
    // gesto termina no vazio e não há geometria para gravar.
    final item = itemById(itemId);
    if (item == null) return;

    try {
      await supabase
          .from('whiteboard_items')
          .update(item.toGeometryUpdate())
          .eq('id', itemId);
    } catch (e) {
      debugPrint('Erro ao mover anexo: $e');
      state = state.copyWith(error: 'A nova posição do anexo não foi salva.');
      // Recarrega a posição autoritativa: deixar a tela local divergente do
      // banco é pior do que o anexo dar um pulo de volta.
      await _reloadItem(itemId);
    }
  }

  Future<void> _reloadItem(String itemId) async {
    try {
      final row = await supabase
          .from('whiteboard_items')
          .select()
          .eq('id', itemId)
          .maybeSingle();
      if (row == null) {
        _onRemoteItemDelete({'id': itemId});
        return;
      }
      _onRemoteItemUpsert(Map<String, dynamic>.from(row));
    } catch (e) {
      debugPrint('Erro ao recarregar anexo: $e');
    }
  }

  /// Tira um anexo do quadro. A policy só deixa passar para quem anexou ou
  /// para o autor do quadro.
  Future<void> removeItem(String itemId) async {
    final index = state.items.indexWhere((i) => i.id == itemId);
    if (index == -1) return;

    final removed = state.items[index];
    final backup = state.items;
    state = state.copyWith(
      items: state.items.where((i) => i.id != itemId).toList(),
    );

    try {
      await supabase.from('whiteboard_items').delete().eq('id', itemId);
    } catch (e) {
      debugPrint('Erro ao remover anexo: $e');
      state = state.copyWith(
        items: backup,
        error: 'Só quem anexou (ou o autor do quadro) pode remover.',
      );
      return;
    }

    // O objeto no Storage só sai depois que a linha sumiu de verdade. Falha
    // aqui deixa um arquivo órfão no bucket — chato, mas invisível para o
    // usuário e melhor do que anexo sem imagem.
    final path = removed.storagePath;
    if (path == null || path.isEmpty) return;
    try {
      await supabase.storage.from(AppConstants.storageBucket).remove([path]);
    } catch (e) {
      debugPrint('Anexo removido do quadro, mas o arquivo ficou no bucket: $e');
    }
  }

  /// Largura e altura reais da imagem, para o anexo entrar no quadro com a
  /// proporção certa.
  ///
  /// Um arquivo que o decoder não reconhece cai em 4:3 em vez de propagar o
  /// erro: anexo com proporção errada ainda é utilizável; anexo que não
  /// entrou, não.
  Future<ui.Size> _imageSize(XFile file) async {
    try {
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final size = ui.Size(
        frame.image.width.toDouble(),
        frame.image.height.toDouble(),
      );
      frame.image.dispose();
      codec.dispose();
      return size;
    } catch (e) {
      debugPrint('Não foi possível medir a imagem anexada: $e');
      return const ui.Size(4, 3);
    }
  }

  void dismissError() => state = state.copyWith(clearError: true);
}

final whiteboardProvider =
    NotifierProvider.family<WhiteboardNotifier, WhiteboardState, String>(
  WhiteboardNotifier.new,
);

/// Cria um quadro na conversa e devolve o id.
///
/// [chatId] e [channelId] são exclusivos — o CHECK da tabela recusa os dois
/// preenchidos ou nenhum.
Future<String?> createWhiteboard({
  required String title,
  String? chatId,
  String? channelId,
}) async {
  final myId = supabase.auth.currentUser?.id;
  if (myId == null) return null;

  try {
    final result = await supabase
        .from('whiteboards')
        .insert({
          'title': title,
          'created_by': myId,
          if (chatId != null) 'chat_id': chatId,
          if (channelId != null) 'channel_id': channelId,
        })
        .select('id')
        .single();

    return result['id']?.toString();
  } catch (e) {
    debugPrint('Erro ao criar quadro: $e');
    return null;
  }
}
