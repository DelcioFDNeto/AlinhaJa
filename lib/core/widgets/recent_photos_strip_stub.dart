import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// Implementação usada onde não há biblioteca de fotos para ler — a Web, já
/// que navegador nenhum expõe a galeria do usuário.
///
/// O menu de anexo simplesmente não mostra a tira e o botão "Galeria" segue
/// sendo o caminho.
bool get recentPhotosSupported => false;

Widget buildRecentPhotosStrip({
  required ValueChanged<XFile> onPicked,
  required VoidCallback onOpenGallery,
}) =>
    const SizedBox.shrink();
