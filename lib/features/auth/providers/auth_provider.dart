import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:alinha_ja/core/config/app_env.dart';
import 'package:alinha_ja/core/services/backup_service.dart';
import 'package:alinha_ja/core/services/media_cache_manager.dart';
import 'package:alinha_ja/core/services/media_url_resolver.dart';
import 'package:alinha_ja/core/services/offline_cache_service.dart';
import 'package:alinha_ja/core/supabase_client.dart';
import 'package:alinha_ja/features/profile/models/user_model.dart';
import 'package:alinha_ja/core/globals.dart';

/// Estado de autenticação global.
final authStateProvider = StreamProvider<AuthState>((ref) {
  return supabase.auth.onAuthStateChange;
});

/// Perfil do usuário logado.
final currentUserProvider = FutureProvider<UserModel?>((ref) async {
  // Observa o estado de autenticação para recarregar o provider
  // caso o usuário faça login ou logout
  ref.watch(authStateProvider);

  final auth = supabase.auth.currentUser;
  if (auth == null) {
    Globals.currentUserIsPlatformOwner = null;
    return null;
  }

  final data = await supabase
      .from('users')
      .select(UserModel.selectWithOrg)
      .eq('id', auth.id)
      .maybeSingle();

  if (data == null) {
    debugPrint(
        'Aviso: Usuário não encontrado na tabela users - provavelmente tabela vazia após reset');
    await supabase.auth.signOut();
    return null;
  }

  final user = UserModel.fromJson(data);

  if (!user.isActive) {
    try {
      await supabase.auth.signOut();
    } catch (e) {
      debugPrint('Aviso: Erro ao fazer signOut de usuario inativo -> $e');
    }
    return null;
  }

  // Espelho síncrono para a guarda de rota do Console de Plataforma.
  Globals.currentUserIsPlatformOwner = user.isPlatformOwner;

  return user;
});

/// Indica se o usuário logado é dono da aplicação (acesso ao Console de
/// Plataforma). Deriva de [currentUserProvider]; `false` enquanto carrega.
final isPlatformOwnerProvider = Provider<bool>((ref) {
  return ref.watch(currentUserProvider).valueOrNull?.isPlatformOwner ?? false;
});

/// Repositório de autenticação.
class AuthRepository {
  const AuthRepository();

  Future<void> signIn({required String email, required String password}) async {
    await supabase.auth.signInWithPassword(email: email, password: password);
  }

  Future<void> signOut() async {
    try {
      final userId = supabase.auth.currentUser?.id;

      // -- 1. Deletar o token FCM ANTES do signOut (enquanto currentUser ainda existe) --
      if (userId != null) {
        try {
          final messaging = FirebaseMessaging.instance;
          final token = kIsWeb
              ? await messaging.getToken(
                  vapidKey: AppEnv.firebaseVapidKey.isNotEmpty
                      ? AppEnv.firebaseVapidKey
                      : dotenv.env['FIREBASE_VAPID_KEY'],
                )
              : await messaging.getToken();
          if (token != null) {
            await supabase
                .from('user_fcm_tokens')
                .delete()
                .match({'user_id': userId, 'token': token});
            await messaging.deleteToken();
            debugPrint('FCM: Token removido do banco antes do signOut.');
          }
        } catch (e) {
          debugPrint('FCM: Erro ao deletar token no signOut: $e');
        }

        // -- 2. Marcar como offline --
        // Best-effort, como o passo 1: sem rede o update lança, e antes a
        // exceção pulava a limpeza do aparelho e o próprio signOut — a
        // pessoa não conseguia sair da conta offline e as mensagens ficavam
        // no dispositivo.
        try {
          await supabase.from('users').update({
            'is_online': false,
            'last_seen_at': DateTime.now().toUtc().toIso8601String(),
          }).eq('id', userId);
        } catch (e) {
          debugPrint('Auth: Falha ao marcar offline no signOut: $e');
        }
      }

      // -- 3. Apagar o que a conta deixou neste aparelho --
      // Espelho de mensagens e cache de mídia. Sem isto o dado sobrevive ao
      // logout e fica ao alcance da próxima conta que usar o dispositivo —
      // exatamente o vazamento que o backup antigo exportava. A Política de
      // Retenção (seção 1.7) promete "até sair da conta": é aqui que cumpre.
      await BackupService.limparDadosDoDispositivo();
      // Cache offline (Hive) de mensagens, canais, usuários e fila de envio.
      await OfflineCacheService.clearAll();

      // -- 4. Só agora encerra a sessão (currentUser vira null) --
      Globals.is2faVerified = false;
      // URLs assinadas foram emitidas para a sessão que está terminando:
      // descartá-las evita que sobrevivam ao logout na memória do processo.
      MediaUrlResolver.clear();
      MediaCacheManager.clearResolvedCache();
      await supabase.auth.signOut();
    } catch (e) {
      Globals.showErrorSnackBar(
          'Erro ao encerrar a sessão. Verifique sua conexão.');
    }
  }

  Future<void> markOnline() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId != null) {
      await supabase.from('users').update({'is_online': true}).eq('id', userId);
    }
  }
}

final authRepositoryProvider = Provider((_) => const AuthRepository());

