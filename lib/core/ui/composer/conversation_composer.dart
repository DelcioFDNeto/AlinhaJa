import 'dart:async';

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:alinha_ja/core/ui/composer/composer_action.dart';
import 'package:alinha_ja/core/ui/composer/composer_action_runner.dart';
import 'package:alinha_ja/core/ui/composer/composer_delegate.dart';
import 'package:alinha_ja/core/ui/composer/composer_recorder.dart';
import 'package:alinha_ja/core/ui/composer/widgets/composer_attach_panel.dart';
import 'package:alinha_ja/core/ui/composer/widgets/composer_banners.dart';
import 'package:alinha_ja/core/ui/composer/widgets/composer_buttons.dart';
import 'package:alinha_ja/core/ui/composer/widgets/composer_mention_overlay.dart';
import 'package:alinha_ja/core/widgets/recent_photos_strip.dart';
import 'package:alinha_ja/features/profile/models/user_model.dart';

/// Barra de composição única de todas as conversas do app.
///
/// Chat 1:1, grupos, canais e threads compartilham este widget; o que muda
/// entre eles vem do [ComposerDelegate] — quais ações o painel oferece e para
/// onde a mensagem vai.
class ConversationComposer extends StatefulWidget {
  final ComposerDelegate delegate;

  const ConversationComposer({super.key, required this.delegate});

  @override
  State<ConversationComposer> createState() => _ConversationComposerState();
}

class _ConversationComposerState extends State<ConversationComposer>
    with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _keyboardFocusNode = FocusNode();

  // Criado no initState, não como `late` preguiçoso: em conversa somente
  // leitura o build sai antes de tocar no controller, e aí o dispose tentaria
  // construí-lo com a árvore já desmontada.
  late final AnimationController _attachAnim;

  bool _showAttach = false;
  bool _showEmoji = false;
  bool _hasText = false;

  late final ComposerRecorder _recorder;
  bool get _isRecording => _recorder.isRecording;

  List<UserModel> _mentionSuggestions = const [];
  List<ComposerBroadcastMention> _broadcastSuggestions = const [];

  ComposerDelegate get _delegate => widget.delegate;

  @override
  void initState() {
    super.initState();
    _attachAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _recorder = ComposerRecorder(
      onChanged: () {
        if (mounted) setState(() {});
      },
    );
    _controller.addListener(_onTextChange);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _keyboardFocusNode.dispose();
    _attachAnim.dispose();
    _recorder.dispose();
    super.dispose();
  }

  // ── Texto e menções ─────────────────────────────────────────

  void _onTextChange() {
    final text = _controller.text;
    final has = text.trim().isNotEmpty;
    if (has != _hasText) setState(() => _hasText = has);

    _delegate.onTyping(text);
    _refreshMentions(text);
  }

  /// Sugere membros e menções coletivas quando o cursor está logo depois de
  /// um `@`.
  void _refreshMentions(String text) {
    final members = _delegate.mentionableMembers;
    final broadcasts = _delegate.broadcastMentions;
    if (members.isEmpty && broadcasts.isEmpty) return;

    final cursor = _controller.selection.baseOffset;
    List<UserModel> matches = const [];
    List<ComposerBroadcastMention> broadcastMatches = const [];

    if (cursor > 0 && cursor <= text.length) {
      final beforeCursor = text.substring(0, cursor);
      final lastAt = beforeCursor.lastIndexOf('@');
      if (lastAt != -1) {
        final query = beforeCursor.substring(lastAt + 1);
        if (!query.contains(' ')) {
          final lower = query.toLowerCase();
          matches = members
              .where((m) =>
                  query.isEmpty || m.fullName.toLowerCase().contains(lower))
              .take(5)
              .toList();
          broadcastMatches = broadcasts
              .where((b) =>
                  query.isEmpty ||
                  b.token.toLowerCase().startsWith(lower) ||
                  b.label.toLowerCase().startsWith(lower))
              .toList();
        }
      }
    }

    if (!listEquals(matches, _mentionSuggestions) ||
        !listEquals(broadcastMatches, _broadcastSuggestions)) {
      setState(() {
        _mentionSuggestions = matches;
        _broadcastSuggestions = broadcastMatches;
      });
    }
  }

  void _applyMention(UserModel member) => _insertMention(member.fullName);

  void _applyBroadcastMention(ComposerBroadcastMention broadcast) =>
      _insertMention(broadcast.token);

  /// Troca o `@parcial` sob o cursor pela menção escolhida.
  void _insertMention(String name) {
    final cursor = _controller.selection.baseOffset;
    final text = _controller.text;
    if (cursor < 0 || cursor > text.length) return;

    final lastAt = text.substring(0, cursor).lastIndexOf('@');
    if (lastAt == -1) return;

    final mention = '@$name ';
    final newText = text.substring(0, lastAt) + mention + text.substring(cursor);
    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: lastAt + mention.length),
    );
    setState(() {
      _mentionSuggestions = const [];
      _broadcastSuggestions = const [];
    });
  }

  void _insertEmoji(String emoji) {
    final selection = _controller.selection;
    final text = _controller.text;
    final start = selection.start < 0 ? text.length : selection.start;
    final end = selection.end < 0 ? text.length : selection.end;

    final newText = text.replaceRange(start, end, emoji);
    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + emoji.length),
    );
  }

  Future<void> _sendText() async {
    if (!_hasText) return;
    final text = _controller.text;

    HapticFeedback.lightImpact();
    _controller.clear();

    try {
      await _delegate.sendText(text);
    } catch (e) {
      // O texto volta para o campo: perder o que foi escrito por causa de uma
      // falha de rede é pior do que ver o erro.
      if (!mounted) return;
      _controller.text = text;
      _notify('Erro ao enviar: $e');
      return;
    }

    if (!mounted) return;
    FocusScope.of(context).requestFocus(_focusNode);
  }

  // ── Painéis ─────────────────────────────────────────────────

  void _toggleAttach() {
    setState(() {
      _showAttach = !_showAttach;
      if (_showAttach) _showEmoji = false;
    });
    _showAttach ? _attachAnim.forward() : _attachAnim.reverse();
    if (_showAttach) FocusScope.of(context).unfocus();
  }

  void _closeAttach() {
    if (!_showAttach) return;
    setState(() => _showAttach = false);
    _attachAnim.reverse();
  }

  void _toggleEmoji() {
    setState(() {
      _showEmoji = !_showEmoji;
      if (_showEmoji) {
        _showAttach = false;
        _attachAnim.reverse();
      }
    });
    if (_showEmoji) {
      FocusScope.of(context).unfocus();
    } else {
      FocusScope.of(context).requestFocus(_focusNode);
    }
  }

  // ── Gravação de áudio ───────────────────────────────────────

  Future<void> _stopRecording({required bool shouldSend}) async {
    final path = await _recorder.stop(discard: !shouldSend);
    if (path == null) return;

    await _delegate.sendAudio(path);
  }

  // ── Ações do painel ─────────────────────────────────────────

  ComposerActionRunner get _runner => ComposerActionRunner(
        delegate: _delegate,
        notify: _notify,
      );

  Future<void> _runAction(ComposerActionId id) async {
    _closeAttach();
    await _runner.run(context, id);
  }

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // ── Build ───────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_delegate.canSend) {
      return ComposerLockedBanner(message: _delegate.lockedMessage);
    }

    final actions = orderedComposerActions(_delegate.actions);
    final reply = _delegate.reply;

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_mentionSuggestions.isNotEmpty ||
              _broadcastSuggestions.isNotEmpty)
            ComposerMentionOverlay(
              members: _mentionSuggestions,
              onSelected: _applyMention,
              broadcasts: _broadcastSuggestions,
              onBroadcastSelected: _applyBroadcastMention,
            ),

          SizeTransition(
            sizeFactor: _attachAnim,
            axisAlignment: -1,
            child: _showAttach
                ? ComposerAttachPanel(
                    actions: actions,
                    onAction: _runAction,
                    highlighted: const {},
                    recentPhotos: actions.contains(ComposerActionId.gallery) &&
                            RecentPhotosStrip.isSupported
                        ? RecentPhotosStrip(
                            onPicked: (file) {
                              _closeAttach();
                              _runner.sendPickedFiles(context, [file]);
                            },
                            onOpenGallery: () =>
                                _runAction(ComposerActionId.gallery),
                          )
                        : null,
                  )
                : const SizedBox.shrink(),
          ),

          if (reply != null) ComposerReplyPreview(reply: reply),

          _buildInputRow(context, actions),

          if (_showEmoji)
            SizedBox(
              height: (MediaQuery.sizeOf(context).height * 0.35).clamp(220, 320),
              child: EmojiPicker(
                onEmojiSelected: (category, emoji) => _insertEmoji(emoji.emoji),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInputRow(BuildContext context, List<ComposerActionId> actions) {
    final theme = Theme.of(context);
    final accent = _delegate.accentColor;

    // Em tela estreita a câmera some da barra: ela continua no painel de
    // anexos, e o campo de texto ganha o espaço.
    final showCameraShortcut = actions.contains(ComposerActionId.camera) &&
        MediaQuery.sizeOf(context).width > 360;

    return Container(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 6),
      constraints: const BoxConstraints(maxHeight: 148),
      decoration: BoxDecoration(
        color: accent?.withValues(alpha: 0.12) ??
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(24),
        border: accent != null ? Border.all(color: accent) : null,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (_isRecording)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              tooltip: 'Descartar',
              onPressed: () => _stopRecording(shouldSend: false),
            )
          else if (actions.isNotEmpty)
            IconButton(
              icon: Icon(
                _showAttach ? Icons.close : Icons.add_circle_rounded,
                color: theme.colorScheme.primary,
              ),
              tooltip: _showAttach ? 'Fechar' : 'Anexar',
              onPressed: _toggleAttach,
            ),

          if (!_isRecording)
            for (final toggle in _delegate.toggles)
              IconButton(
                icon: Icon(
                  toggle.active ? toggle.activeIcon : toggle.icon,
                  color: toggle.active
                      ? toggle.activeColor
                      : theme.colorScheme.onSurfaceVariant,
                ),
                tooltip: toggle.tooltip,
                onPressed: toggle.onPressed,
              ),

          Expanded(
            child: _isRecording
                ? ComposerRecordingIndicator(duration: _recorder.duration)
                : _buildTextField(theme),
          ),

          if (!_isRecording && showCameraShortcut)
            IconButton(
              icon: Icon(Icons.camera_alt_outlined,
                  color: theme.colorScheme.primary, size: 24),
              tooltip: 'Câmera',
              onPressed: () => _runAction(ComposerActionId.camera),
            ),

          if (!_isRecording)
            IconButton(
              icon: Icon(
                _showEmoji
                    ? Icons.keyboard_rounded
                    : Icons.emoji_emotions_outlined,
                color: theme.colorScheme.primary,
                size: 24,
              ),
              tooltip: 'Emojis',
              onPressed: _toggleEmoji,
            ),

          _buildSendButton(theme),
        ],
      ),
    );
  }

  Widget _buildTextField(ThemeData theme) {
    return KeyboardListener(
      focusNode: _keyboardFocusNode,
      onKeyEvent: (event) {
        // Enter envia; Shift+Enter quebra linha.
        if (event is! KeyDownEvent) return;
        if (event.logicalKey != LogicalKeyboardKey.enter) return;

        final pressed = HardwareKeyboard.instance.logicalKeysPressed;
        final shift = pressed.contains(LogicalKeyboardKey.shiftLeft) ||
            pressed.contains(LogicalKeyboardKey.shiftRight);
        if (!shift) _sendText();
      },
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        maxLines: null,
        keyboardType: TextInputType.multiline,
        textInputAction: TextInputAction.send,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          hintText: _delegate.hintText,
          border: InputBorder.none,
          filled: false,
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        ),
        onTap: () {
          if (_showEmoji) setState(() => _showEmoji = false);
        },
        onSubmitted: (_) => _sendText(),
      ),
    );
  }

  Widget _buildSendButton(ThemeData theme) {
    final canRecord = _delegate.supportsAudio;
    final isSendMode = _hasText || !canRecord;

    if (isSendMode && !_isRecording) {
      return ComposerCircleButton(
        icon: Icons.send_rounded,
        background: theme.colorScheme.primary,
        foreground: theme.colorScheme.onPrimary,
        onTap: _hasText ? _sendText : null,
      );
    }

    return GestureDetector(
      onTap: () => _isRecording
          ? _stopRecording(shouldSend: true)
          : _recorder.start(),
      onLongPress: _recorder.start,
      onLongPressUp: () => _stopRecording(shouldSend: true),
      child: ComposerCircleButton(
        icon: _isRecording ? Icons.send_rounded : Icons.mic_rounded,
        background: _isRecording ? Colors.green : theme.colorScheme.primary,
        foreground: theme.colorScheme.onPrimary,
      ),
    );
  }
}
