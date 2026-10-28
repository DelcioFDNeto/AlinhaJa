import 'package:flutter/material.dart';

import 'package:alinha_ja/core/models/message_extras.dart';

/// Peso do anúncio. Define cor, ícone e o quanto ele grita na conversa.
enum AnnouncementPriority { info, important, urgent, critical }

@immutable
class AnnouncementPrioritySpec {
  final String label;
  final IconData icon;
  final Color color;
  final String hint;

  const AnnouncementPrioritySpec({
    required this.label,
    required this.icon,
    required this.color,
    required this.hint,
  });
}

const Map<AnnouncementPriority, AnnouncementPrioritySpec> announcementPriorities =
    {
  AnnouncementPriority.info: AnnouncementPrioritySpec(
    label: 'Informativo',
    icon: Icons.info_outline_rounded,
    color: Color(0xFF0A84FF),
    hint: 'Comunicado geral, sem urgência',
  ),
  AnnouncementPriority.important: AnnouncementPrioritySpec(
    label: 'Importante',
    icon: Icons.campaign_rounded,
    color: Color(0xFFFF9500),
    hint: 'Merece atenção de todos',
  ),
  AnnouncementPriority.urgent: AnnouncementPrioritySpec(
    label: 'Urgente',
    icon: Icons.priority_high_rounded,
    color: Color(0xFFFF3B30),
    hint: 'Precisa de ação rápida',
  ),
  AnnouncementPriority.critical: AnnouncementPrioritySpec(
    label: 'Crítico',
    icon: Icons.warning_amber_rounded,
    color: Color(0xFFAF0038),
    hint: 'Parada de operação, segurança, emergência',
  ),
};

/// Tipo do botão de ação que acompanha o anúncio.
///
/// Não há `workflowCard` porque card do workflow ainda não tem rota própria —
/// abre por sheet dentro da view. Um botão que não navega para lugar nenhum
/// seria pior do que não ter botão; quando existir deep link para o card, entra
/// aqui.
enum AnnouncementActionKind { none, link, document, confirmPresence }

/// Botão configurável exibido no rodapé do card.
@immutable
class AnnouncementAction {
  final AnnouncementActionKind kind;
  final String label;

  /// URL, id do card do workflow — depende de [kind].
  final String? value;

  const AnnouncementAction({
    required this.kind,
    required this.label,
    this.value,
  });

  bool get isEmpty => kind == AnnouncementActionKind.none || label.trim().isEmpty;

  Map<String, dynamic> toMap() => {
        'kind': kind.name,
        'label': label,
        if (value != null && value!.isNotEmpty) 'value': value,
      };

  static AnnouncementAction? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final kind = AnnouncementActionKind.values.firstWhere(
      (k) => k.name == map['kind']?.toString(),
      orElse: () => AnnouncementActionKind.none,
    );
    final label = map['label']?.toString() ?? '';
    if (kind == AnnouncementActionKind.none || label.isEmpty) return null;
    return AnnouncementAction(
      kind: kind,
      label: label,
      value: map['value']?.toString(),
    );
  }
}

/// Arquivo anexado ao anúncio (política, comunicado em PDF).
@immutable
class AnnouncementAttachment {
  final String url;
  final String name;
  final int? sizeBytes;

  const AnnouncementAttachment({
    required this.url,
    required this.name,
    this.sizeBytes,
  });

  Map<String, dynamic> toMap() => {
        'url': url,
        'name': name,
        if (sizeBytes != null) 'size_bytes': sizeBytes,
      };

  static AnnouncementAttachment? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final url = map['url']?.toString();
    if (url == null || url.isEmpty) return null;
    return AnnouncementAttachment(
      url: url,
      name: map['name']?.toString() ?? 'Anexo',
      sizeBytes: map['size_bytes'] is int
          ? map['size_bytes'] as int
          : int.tryParse(map['size_bytes']?.toString() ?? ''),
    );
  }

  String get readableSize {
    final size = sizeBytes;
    if (size == null) return '';
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// Um grupo do público-alvo (setor, cargo ou filial).
@immutable
class AudienceTarget {
  final String id;
  final String name;

  const AudienceTarget({required this.id, required this.name});

  Map<String, dynamic> toMap() => {'id': id, 'name': name};

  static AudienceTarget? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final id = map['id']?.toString();
    if (id == null || id.isEmpty) return null;
    return AudienceTarget(id: id, name: map['name']?.toString() ?? id);
  }

  @override
  bool operator ==(Object other) =>
      other is AudienceTarget && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Para quem o anúncio vale.
///
/// Vazio significa "todo mundo da conversa". Isto direciona **de quem se espera
/// confirmação** e o que o card mostra — não esconde a mensagem de ninguém:
/// filtrar visibilidade exigiria RLS por linha em `messages`, com risco de
/// alguém deixar de ver um comunicado por engano de configuração.
@immutable
class AnnouncementAudience {
  final List<AudienceTarget> departments;
  final List<AudienceTarget> jobPositions;
  final List<AudienceTarget> branches;

  const AnnouncementAudience({
    this.departments = const [],
    this.jobPositions = const [],
    this.branches = const [],
  });

  bool get isEveryone =>
      departments.isEmpty && jobPositions.isEmpty && branches.isEmpty;

  /// Nomes na ordem em que aparecem no card.
  List<String> get labels => [
        for (final d in departments) d.name,
        for (final j in jobPositions) j.name,
        for (final b in branches) b.name,
      ];

  Map<String, dynamic> toMap() => {
        if (departments.isNotEmpty)
          'departments': departments.map((e) => e.toMap()).toList(),
        if (jobPositions.isNotEmpty)
          'job_positions': jobPositions.map((e) => e.toMap()).toList(),
        if (branches.isNotEmpty)
          'branches': branches.map((e) => e.toMap()).toList(),
      };

  static AnnouncementAudience fromMap(Object? raw) {
    if (raw is! Map) return const AnnouncementAudience();
    final map = Map<String, dynamic>.from(raw);

    List<AudienceTarget> read(String key) => (map[key] is List)
        ? (map[key] as List)
            .map(AudienceTarget.fromMap)
            .whereType<AudienceTarget>()
            .toList()
        : const [];

    return AnnouncementAudience(
      departments: read('departments'),
      jobPositions: read('job_positions'),
      branches: read('branches'),
    );
  }
}

/// Tudo que define um anúncio oficial.
///
/// Vira o `metadata` da mensagem — o `content` continua sendo o texto. Assim o
/// anúncio funciona igual em canal (`channel_messages`) e em grupo
/// (`messages`), sem coluna nova em nenhuma das duas.
@immutable
class AnnouncementSpec {
  final AnnouncementPriority priority;

  /// Depois desta data o card aparece esmaecido e marcado como encerrado.
  final DateTime? validUntil;

  /// Fixa no topo da conversa enquanto estiver válido.
  final bool pinned;

  /// Exige o "li e confirmo" de quem recebe.
  final bool requiresAck;

  final AnnouncementAudience audience;
  final AnnouncementAttachment? attachment;
  final AnnouncementAction? action;

  const AnnouncementSpec({
    this.priority = AnnouncementPriority.important,
    this.validUntil,
    this.pinned = false,
    this.requiresAck = false,
    this.audience = const AnnouncementAudience(),
    this.attachment,
    this.action,
  });

  AnnouncementPrioritySpec get style => announcementPriorities[priority]!;

  bool get isExpired =>
      validUntil != null && DateTime.now().isAfter(validUntil!);

  Map<String, dynamic> toMetadata() => {
        'type': MessageExtras.typeAnnouncement,
        'priority': priority.name,
        // `valid_until` e não `expires_at`: aquela chave já significou "apague
        // esta mensagem" no recurso de mensagem temporária, e um anúncio
        // vencido deve continuar no histórico.
        if (validUntil != null) 'valid_until': validUntil!.toIso8601String(),
        if (pinned) 'pinned': true,
        if (requiresAck) 'requires_ack': true,
        if (!audience.isEveryone) 'audience': audience.toMap(),
        if (attachment != null) 'attachment': attachment!.toMap(),
        if (action != null && !action!.isEmpty) 'action': action!.toMap(),
      };

  static AnnouncementSpec fromMetadata(Map<String, dynamic> metadata) {
    final rawValidUntil = metadata['valid_until']?.toString();

    return AnnouncementSpec(
      priority: AnnouncementPriority.values.firstWhere(
        (p) => p.name == metadata['priority']?.toString(),
        // Anúncios criados antes deste recurso não têm prioridade gravada.
        orElse: () => AnnouncementPriority.important,
      ),
      validUntil:
          rawValidUntil == null ? null : DateTime.tryParse(rawValidUntil),
      pinned: metadata['pinned'] == true,
      requiresAck: metadata['requires_ack'] == true,
      audience: AnnouncementAudience.fromMap(metadata['audience']),
      attachment: AnnouncementAttachment.fromMap(metadata['attachment']),
      action: AnnouncementAction.fromMap(metadata['action']),
    );
  }
}
