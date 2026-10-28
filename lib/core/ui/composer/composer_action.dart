import 'package:flutter/material.dart';

/// Ações que podem aparecer no painel de anexos do composer.
///
/// A ordem das entradas aqui é a ordem em que os botões são desenhados; cada
/// conversa declara apenas o subconjunto que sabe executar
/// (`ComposerDelegate.actions`).
enum ComposerActionId {
  camera,
  gallery,
  document,
  poll,
  event,
  location,
  contact,
  whiteboard,
  announcement,
}

/// Aparência de uma ação — ícone, rótulo e cor de destaque.
@immutable
class ComposerActionSpec {
  final IconData icon;
  final String label;
  final Color color;

  const ComposerActionSpec({
    required this.icon,
    required this.label,
    required this.color,
  });
}

/// Catálogo único de aparência. Antes cada barra escolhia seu próprio ícone e
/// rótulo para a mesma ação ("Galeria" x "Imagem", "Documento" x "Arquivo"),
/// então a mesma função tinha nomes diferentes dependendo da tela.
const Map<ComposerActionId, ComposerActionSpec> composerActionSpecs = {
  ComposerActionId.camera: ComposerActionSpec(
    icon: Icons.camera_alt_rounded,
    label: 'Câmera',
    color: Color(0xFFE040FB),
  ),
  ComposerActionId.gallery: ComposerActionSpec(
    icon: Icons.photo_library_rounded,
    label: 'Galeria',
    color: Color(0xFF5856D6),
  ),
  ComposerActionId.document: ComposerActionSpec(
    icon: Icons.insert_drive_file_rounded,
    label: 'Documento',
    color: Color(0xFFFF9500),
  ),
  ComposerActionId.poll: ComposerActionSpec(
    icon: Icons.poll_rounded,
    label: 'Enquete',
    color: Color(0xFF00A79D),
  ),
  ComposerActionId.event: ComposerActionSpec(
    icon: Icons.event_rounded,
    label: 'Evento',
    color: Color(0xFF0A84FF),
  ),
  ComposerActionId.location: ComposerActionSpec(
    icon: Icons.location_on_rounded,
    label: 'Localização',
    color: Color(0xFF34C759),
  ),
  ComposerActionId.contact: ComposerActionSpec(
    icon: Icons.person_rounded,
    label: 'Contato',
    color: Color(0xFF5E5CE6),
  ),
  ComposerActionId.whiteboard: ComposerActionSpec(
    icon: Icons.draw_rounded,
    label: 'Quadro',
    color: Color(0xFF00A79D),
  ),
  ComposerActionId.announcement: ComposerActionSpec(
    icon: Icons.campaign_rounded,
    label: 'Anúncio',
    color: Color(0xFFFF9500),
  ),
};

/// Anexos de arquivo — o mínimo que qualquer conversa entende.
const Set<ComposerActionId> kMediaComposerActions = {
  ComposerActionId.camera,
  ComposerActionId.gallery,
  ComposerActionId.document,
};

/// Conteúdo estruturado (enquete, evento, localização, contato).
const Set<ComposerActionId> kRichComposerActions = {
  ComposerActionId.poll,
  ComposerActionId.event,
  ComposerActionId.location,
  ComposerActionId.contact,
};

/// Ordena um conjunto de ações pela ordem canônica do enum.
List<ComposerActionId> orderedComposerActions(Set<ComposerActionId> actions) =>
    ComposerActionId.values.where(actions.contains).toList(growable: false);
