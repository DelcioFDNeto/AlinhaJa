import 'package:flutter/material.dart';

import 'package:alinha_ja/core/models/message_extras.dart';
import 'package:alinha_ja/core/models/message_ref.dart';
import 'package:alinha_ja/core/ui/message_cards/contact_card.dart';
import 'package:alinha_ja/core/ui/message_cards/event_card.dart';
import 'package:alinha_ja/core/ui/message_cards/location_card.dart';
import 'package:alinha_ja/core/ui/message_cards/poll_card.dart';
import 'package:alinha_ja/features/whiteboard/ui/widgets/whiteboard_card.dart';

/// Escolhe o card certo para uma mensagem estruturada.
///
/// É o ponto único onde `metadata.type` vira widget — as bolhas de chat e de
/// canal só perguntam [handles] e delegam para cá.
class StructuredMessageCard extends StatelessWidget {
  /// Origem da mensagem (chat ou canal) — a enquete grava o voto na coluna
  /// correspondente de `message_actions`.
  final MessageRef message;

  final Map<String, dynamic> metadata;

  /// Conteúdo textual da mensagem (pergunta da enquete, título do evento…).
  final String? content;

  final double maxWidth;

  const StructuredMessageCard({
    super.key,
    required this.message,
    required this.metadata,
    this.content,
    this.maxWidth = 320,
  });

  /// Se este metadata é renderizável como card.
  static bool handles(Map<String, dynamic> metadata) => metadata.isStructured;

  @override
  Widget build(BuildContext context) {
    if (metadata.isPoll) {
      return PollCard(
        message: message,
        question: content?.trim().isNotEmpty == true
            ? content!.trim()
            : 'Enquete',
        options: metadata.pollOptions,
        allowsMultiple: metadata.pollAllowsMultiple,
        maxWidth: maxWidth,
      );
    }

    if (metadata.isEvent) {
      final date = metadata.eventDate;
      if (date != null) {
        return EventCard(
          // Mensagens antigas só têm o título no content, com o 📅 na frente.
          title: metadata.eventTitle ??
              (content ?? 'Evento').replaceFirst('📅 ', '').trim(),
          date: date,
          maxWidth: maxWidth,
        );
      }
    }

    if (metadata.isLocation) {
      final lat = metadata.latitude;
      final lng = metadata.longitude;
      if (lat != null && lng != null) {
        return LocationCard(
          latitude: lat,
          longitude: lng,
          accuracy: metadata.locationAccuracy,
          label: metadata.locationLabel,
          maxWidth: maxWidth < 260 ? maxWidth : 260,
        );
      }
    }

    if (metadata.isWhiteboard) {
      final boardId = metadata.whiteboardId;
      if (boardId != null && boardId.isNotEmpty) {
        return WhiteboardCard(
          boardId: boardId,
          title: metadata.whiteboardTitle ??
              (content ?? 'Quadro branco').replaceFirst('🎨 ', '').trim(),
          maxWidth: maxWidth < 280 ? maxWidth : 280,
        );
      }
    }

    if (metadata.isContact) {
      return ContactCard(
        name: metadata.contactName ?? content ?? 'Contato',
        subtitle: metadata.contactSubtitle,
        phone: metadata.contactPhone,
        email: metadata.contactEmail,
        avatarUrl: metadata.contactAvatar,
        userId: metadata.contactId,
        maxWidth: maxWidth,
      );
    }

    // Metadata estruturado porém incompleto: cai no texto puro da mensagem.
    return Text(content ?? '');
  }
}
