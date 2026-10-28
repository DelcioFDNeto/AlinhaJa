import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:alinha_ja/core/models/announcement_spec.dart';
import 'package:alinha_ja/core/models/message_extras.dart';
import 'package:alinha_ja/core/ui/composer/composer_action.dart';
import 'package:alinha_ja/core/ui/composer/composer_delegate.dart';
import 'package:alinha_ja/core/ui/composer/composer_media.dart';
import 'package:alinha_ja/core/ui/composer/sheets/compose_announcement_sheet.dart';
import 'package:alinha_ja/core/ui/composer/sheets/contact_picker_sheet.dart';
import 'package:alinha_ja/core/ui/composer/sheets/create_poll_sheet.dart';
import 'package:alinha_ja/core/ui/composer/sheets/location_picker_screen.dart';
import 'package:alinha_ja/core/ui/composer/sheets/schedule_event_sheet.dart';

/// Executa as ações do painel de anexos.
///
/// Fica fora do widget porque é fluxo, não estado: cada ação abre um seletor,
/// monta a mensagem e entrega ao [ComposerDelegate]. O composer só informa o
/// que foi tocado e recebe de volta o que precisa guardar (o prazo da mensagem
/// temporária).
class ComposerActionRunner {
  final ComposerDelegate delegate;

  /// Mostra um aviso curto ao usuário (SnackBar).
  final void Function(String message) notify;

  const ComposerActionRunner({
    required this.delegate,
    required this.notify,
  });

  Future<void> run(BuildContext context, ComposerActionId id) async {
    switch (id) {
      case ComposerActionId.camera:
        await _pickMedia(context, ImageSource.camera);
      case ComposerActionId.gallery:
        await _pickMedia(context, ImageSource.gallery);
      case ComposerActionId.document:
        await _pickDocuments(context);
      case ComposerActionId.poll:
        await _createPoll(context);
      case ComposerActionId.event:
        await _scheduleEvent(context);
      case ComposerActionId.location:
        await _shareLocation(context);
      case ComposerActionId.contact:
        await _shareContact(context);
      case ComposerActionId.whiteboard:
        await _createWhiteboard(context);
      case ComposerActionId.announcement:
        await _publishAnnouncement(context);
    }
  }

  Future<void> _createWhiteboard(BuildContext context) async {
    final title = await _askWhiteboardTitle(context);
    if (title == null) return;

    // O quadro nasce antes da mensagem: sem id não há o que o card abrir.
    final boardId = await delegate.createWhiteboard(title);
    if (boardId == null) {
      notify('Não foi possível criar o quadro.');
      return;
    }

    await _guard(() => delegate.sendStructured(
          '🎨 $title',
          MessageExtras.whiteboard(boardId: boardId, title: title),
        ));
  }

  Future<String?> _askWhiteboardTitle(BuildContext context) async {
    final controller = TextEditingController(text: 'Quadro branco');

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.draw_rounded, size: 32, color: Color(0xFF00A79D)),
        title: const Text('Novo quadro branco'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
          decoration: InputDecoration(
            labelText: 'Assunto do quadro',
            hintText: 'Ex: Layout da nova loja',
            filled: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Criar'),
          ),
        ],
      ),
    );

    controller.dispose();
    if (result == null || result.isEmpty) return null;
    return result;
  }

  Future<void> _publishAnnouncement(BuildContext context) async {
    final draft = await ComposeAnnouncementSheet.show(
      context,
      destinationName: delegate.destinationName,
    );
    if (draft == null) return;

    var spec = draft.spec;

    // O anexo sobe antes da mensagem: se o upload falhar, o anúncio ainda é
    // publicado, mas sem prometer um documento que não existe.
    final pending = draft.pendingAttachment;
    if (pending != null) {
      notify('Enviando anexo do anúncio...');
      try {
        final url = await delegate.uploadAttachment(pending);
        if (url == null) {
          notify('Não foi possível anexar o arquivo; publicando sem ele.');
        } else {
          spec = AnnouncementSpec(
            priority: spec.priority,
            validUntil: spec.validUntil,
            pinned: spec.pinned,
            requiresAck: spec.requiresAck,
            audience: spec.audience,
            action: spec.action,
            attachment: AnnouncementAttachment(
              url: url,
              name: pending.name,
              sizeBytes: await pending.length(),
            ),
          );
        }
      } catch (e) {
        notify('Falha ao anexar o arquivo; publicando sem ele.');
        debugPrint('Erro ao subir anexo do anúncio: $e');
      }
    }

    await _guard(
      () => delegate.sendStructured(draft.content, spec.toMetadata()),
    );
  }

  /// Arquivos escolhidos fora do seletor do sistema (tira de recentes,
  /// arrastar e soltar): ainda passam pelo preview antes de subir.
  Future<void> sendPickedFiles(
    BuildContext context,
    List<XFile> files,
  ) async {
    final result = await ComposerMedia.previewFiles(
      context,
      files: files,
      destinationName: delegate.destinationName,
      allowViewOnce: delegate.allowViewOnce,
    );
    if (result == null || result.files.isEmpty) return;

    await _guard(() => delegate.sendFromPreview(result));
  }

  Future<void> _pickMedia(BuildContext context, ImageSource source) async {
    final result = await ComposerMedia.pickAndPreviewMedia(
      context,
      source: source,
      destinationName: delegate.destinationName,
      allowViewOnce: delegate.allowViewOnce,
    );
    if (result == null || result.files.isEmpty) return;

    await _guard(() => delegate.sendMedia(
          result.files,
          caption: result.caption,
          isViewOnce: result.isViewOnce,
        ));
  }

  Future<void> _pickDocuments(BuildContext context) async {
    final result = await ComposerMedia.pickAndPreviewDocuments(
      context,
      destinationName: delegate.destinationName,
    );
    if (result == null || result.files.isEmpty) return;

    await _guard(
      () => delegate.sendDocuments(result.files, caption: result.caption),
    );
  }

  Future<void> _createPoll(BuildContext context) async {
    final draft = await CreatePollSheet.show(context);
    if (draft == null) return;

    await _guard(() => delegate.sendStructured(draft.question, draft.metadata));
  }

  Future<void> _scheduleEvent(BuildContext context) async {
    final draft = await ScheduleEventSheet.show(context);
    if (draft == null) return;

    await _guard(() => delegate.sendStructured(draft.content, draft.metadata));
  }

  Future<void> _shareLocation(BuildContext context) async {
    // O mapa abre já centrado na posição atual, mas quem manda é o pino: dá
    // para enviar o endereço do cliente, a obra, o ponto de encontro.
    final picked = await LocationPickerScreen.show(context);
    if (picked == null) return;

    final label = picked.label;

    await _guard(() => delegate.sendStructured(
          label != null && label.isNotEmpty ? '📍 $label' : '📍 Localização',
          MessageExtras.location(
            latitude: picked.latitude,
            longitude: picked.longitude,
            accuracy: picked.accuracy,
            label: label,
          ),
        ));
  }

  Future<void> _shareContact(BuildContext context) async {
    final members = delegate.mentionableMembers;
    if (members.isEmpty) {
      notify('Nenhum contato disponível nesta conversa.');
      return;
    }

    final member = await ContactPickerSheet.show(context, members: members);
    if (member == null) return;

    await _guard(() => delegate.sendStructured(
          '👤 ${member.fullName}',
          MessageExtras.contact(
            userId: member.id,
            name: member.fullName,
            subtitle: member.displaySubtitle,
            phone: member.phone,
            email: member.email,
            avatarUrl: member.avatarUrl,
          ),
        ));
  }

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      notify('Erro ao enviar: $e');
    }
  }
}
