import 'dart:ui';

/// Paleta e constantes globais do AlinhaJá.
/// brand-guard:allow-file — este arquivo define a marca; citar as duas aqui
/// é intencional.
class AppConstants {
  AppConstants._();

  /// Nome da marca desta build. Fonte única para título da aba, rótulo da
  /// sidebar e qualquer texto de identidade — ao portar para o Fluxy, é aqui
  /// que o nome muda (ver regras de sync entre os forks).
  ///
  /// NUNCA escreva o nome da marca literalmente na UI: use esta constante.
  /// `scripts/check_brand.sh` falha se a marca do outro fork aparecer no
  /// código — foi um literal esquecido que fez o bot do AlinhaJá dizer a
  /// colaborador do DuBairro que ele trabalhava na Shineray.
  ///
  /// White-label: quem distribui o produto com marca própria troca o nome
  /// na build, sem editar código — `--dart-define=BRAND_NAME=MarcaX`
  /// (ver `docs/GUIA-MARCA-DISTRIBUIDOR.md`).
  static const appName =
      String.fromEnvironment('BRAND_NAME', defaultValue: 'AlinhaJá');

  /// Nome com que os textos-fonte foram escritos (documentos legais em
  /// `docs/legal/`, aprovados como estão). Na exibição, ele é trocado por
  /// [appName] — numa distribuição com outra marca, o documento mostra a
  /// marca dela sem que o texto aprovado seja editado.
  static const nomeOriginalDoProduto = 'AlinhaJá';

  /// Empresa dona deste deployment. Separada de [appName] de propósito: o
  /// app é o produto, a empresa é o cliente, e os dois divergem entre forks.
  ///
  /// Aqui é o tenant NATAL / operador da plataforma — **não** serve como nome
  /// da empresa nos documentos LGPD, porque este produto atende várias. Ver
  /// [isSingleTenant].
  static const companyName = 'DuBairro';

  /// Este deployment atende UMA empresa (marca própria) ou várias (white
  /// label)? Muda o comportamento do módulo LGPD:
  ///
  ///   • `true`  → há uma empresa só, e [companyName] é ela. Documento sem
  ///     razão social cadastrada pode exibir esse nome como último recurso.
  ///   • `false` → cada tenant é uma empresa distinta. **Nada** de identidade
  ///     pode vir de constante de build: preencher o documento de um cliente
  ///     com o nome que está no código é exatamente o erro que fez o bot dizer
  ///     a colaborador de uma empresa que ele trabalhava na outra — e aqui
  ///     sairia em documento assinado.
  ///
  /// Este produto é white label e multiempresa: `false`.
  static const isSingleTenant = false;

  // Cores institucionais
  /// Cor-base da marca. Distribuidor troca na build com
  /// `--dart-define=BRAND_PRIMARY_COLOR=0xFFRRGGBB`. Cada empresa ainda pode
  /// ter a própria cor (OrgIdentity), que prevalece em tempo de execução —
  /// por isso as telas usam a cor do tema (`context.corMarca`), não esta.
  static const primary =
      Color(int.fromEnvironment('BRAND_PRIMARY_COLOR', defaultValue: 0xFFD21A18));
  static const success = Color(0xFF34C759);
  static const danger = Color(0xFFFF3B30);

  static const secondaryText = Color(0xFF8E8E93);

  // Armazenamento de versão para cache clearing
  static const appVersion = '1.3.10';
  static const appBuild = 30092200;

  // Storage
  static const storageBucket = 'chat-media';

  /// Fotos de perfil. Bucket público separado de propósito — avatar é
  /// renderizado em toda a UI e não tem a sensibilidade de uma mídia de DM.
  static const avatarBucket = 'avatars';
  static const maxUploadSizeBytes = 25 * 1024 * 1024; // 25 MB
  static const compressionThresholdBytes = 500 * 1024; // 500 KB

  // Paginação
  static const messagesPerPage = 50;
  static const chatsPerPage = 30;

  // Compressão de imagem
  static const imageMaxWidth = 1200;
  static const imageQuality = 80; // 0-100 (WebP é ~30% mais eficiente que JPEG)

  // Videochamadas - MiroTalk (alternativa gratuita ao Jitsi)
  static const mirotalkServerUrl = 'https://sfu.mirotalk.com';
  static const mirotalkApiUrl = 'https://sfu.mirotalk.com/api/v1';
  static const mirotalkApiKey = String.fromEnvironment('MIROTALK_API_KEY');

  // Cache de Mídia Local (Drift + Disco)
  static const int mediaCacheMaxImageBytes = 500 * 1024 * 1024; // 500 MB
  static const int mediaCacheMaxVideoBytes = 1024 * 1024 * 1024; // 1 GB
  static const int mediaCacheMaxTotalBytes =
      2 * 1024 * 1024 * 1024; // 2 GB total
  static const int mediaCacheRetentionDays =
      90; // Mídias não acessadas há 90 dias são limpas
}

/// Assistente IA interno — espelha o contrato da Edge Function `ai-chatbot`.
class AiAssistant {
  AiAssistant._();

  /// UUID fixo do usuário-bot, criado na migration `..._ai_chatbot_agent.sql`.
  /// A tela de info só oferece a persona quando ele é membro da conversa.
  static const botId = '00000000-0000-4000-a000-000000000001';

  /// Personas gravadas em `chats.metadata` / `channels.metadata` sob a chave
  /// `ai_specialization`. As chaves PRECISAM bater com o mapa
  /// `SPECIALIZATIONS` de `supabase/functions/ai-chatbot/index.ts` — chave
  /// desconhecida cai no `geral` lá também.
  static const specializations = <String, String>{
    'geral': 'Geral',
    'rh': 'RH',
    'ti': 'TI / Helpdesk',
    'administrativo': 'Administrativo',
    'comercial': 'Comercial',
    'pos_venda': 'Pós-venda',
  };

  static const defaultSpecialization = 'geral';

  /// Normaliza o valor vindo do metadata, replicando o fallback do backend.
  static String normalizeSpecialization(Object? raw) {
    final key = raw?.toString();
    return specializations.containsKey(key) ? key! : defaultSpecialization;
  }
}
