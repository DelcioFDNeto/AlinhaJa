import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:alinha_ja/core/brand/org_identity.dart';
import 'package:alinha_ja/core/supabase_client.dart';

/// Acesso a dados da identidade visual da empresa (logo e cores).
///
/// Telas não falam com o Supabase diretamente: passam por aqui. A empresa é
/// sempre a EM ATUAÇÃO (`fn_current_org()` no banco) — o dono da plataforma
/// edita a empresa por onde está atuando, não a própria.
class IdentidadeRepository {
  const IdentidadeRepository();

  static const bucket = 'org-logos';

  /// Envia o logo para `org-logos/{orgId}/logo_{ts}.webp` e devolve a URL
  /// pública. As políticas do bucket só aceitam a pasta da própria empresa.
  Future<String> enviarLogo({
    required String orgId,
    required Uint8List bytes,
    String extensao = 'webp',
    String contentType = 'image/webp',
  }) async {
    final caminho =
        '$orgId/logo_${DateTime.now().millisecondsSinceEpoch}.$extensao';
    final storage = supabase.storage.from(bucket);
    await storage.uploadBinary(
      caminho,
      bytes,
      fileOptions: FileOptions(contentType: contentType, upsert: false),
    );
    return storage.getPublicUrl(caminho);
  }

  /// Remove do bucket um logo antigo desta empresa. Melhor esforço: falha
  /// aqui não desfaz a gravação da identidade nova.
  Future<void> removerLogoAntigo(String? url) async {
    final caminho = caminhoNoBucket(url);
    if (caminho == null) return;
    try {
      await supabase.storage.from(bucket).remove([caminho]);
    } catch (e) {
      debugPrint('IdentidadeRepository: logo antigo não removido ($e)');
    }
  }

  /// Grava logo e cores (estado completo; nulo volta ao padrão da marca).
  Future<OrgIdentity> salvar({
    required String? logoUrl,
    required Color? corPrimaria,
    required Color? corSecundaria,
  }) async {
    final res = await supabase.rpc('admin_set_org_identity', params: {
      'p_logo_url': logoUrl,
      'p_cor_primaria':
          corPrimaria == null ? null : OrgIdentity.hexDeCor(corPrimaria),
      'p_cor_secundaria':
          corSecundaria == null ? null : OrgIdentity.hexDeCor(corSecundaria),
    });
    return res is Map<String, dynamic>
        ? OrgIdentity.fromJson(res)
        : OrgIdentity.vazia;
  }

  /// Caminho dentro do bucket a partir da URL pública, ou nulo se a URL não
  /// for deste bucket (logo externo informado por endereço).
  @visibleForTesting
  static String? caminhoNoBucket(String? url) {
    if (url == null) return null;
    const marcador = '/$bucket/';
    final i = url.indexOf(marcador);
    if (i < 0) return null;
    final caminho = Uri.decodeComponent(url.substring(i + marcador.length))
        .split('?')
        .first;
    return caminho.isEmpty ? null : caminho;
  }
}

final identidadeRepositoryProvider =
    Provider<IdentidadeRepository>((ref) => const IdentidadeRepository());
