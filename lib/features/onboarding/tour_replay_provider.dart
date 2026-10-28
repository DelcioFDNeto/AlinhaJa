import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Sinaliza que o usuário pediu para **rever o tutorial** a partir de uma tela
/// que não é a home (ex.: Central de Ajuda no mobile, empilhada sobre o
/// scaffold principal).
///
/// A Central de Ajuda seta este flag e navega de volta para `/`; o
/// [MainScaffold] o observa e dispara o `launchOnboarding(reset: true)` com o
/// contexto da home — onde os alvos do tour (bottom nav) estão montados. No
/// desktop o tour é disparado direto (a CrmSidebar já está montada), sem passar
/// por aqui.
final tourReplayProvider = StateProvider<bool>((ref) => false);
