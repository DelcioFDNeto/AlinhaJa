import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants.dart';
import 'legal_documents.dart';
import '../models/legal_document_model.dart';
import '../models/org_legal_profile.dart';

class LegalRepository {
  final SupabaseClient _supabase;

  LegalRepository(this._supabase);

  /// Carrega o texto em Markdown do documento a partir do seu id ou asset.
  Future<String> loadDocumentText(String docId) async {
    final doc = legalDocumentById(docId);
    final assetPath = doc?.asset ?? 'docs/legal/$docId';
    try {
      final raw = await rootBundle.loadString(assetPath);
      return _replacePlaceholders(raw);
    } catch (e) {
      debugPrint('❌ Erro ao carregar documento legal $assetPath: $e');
      return '# Documento Indisponível\n\nNão foi possível carregar o documento. Tente novamente mais tarde.';
    }
  }

  /// Registra o aceite de um documento legal.
  ///
  /// Tipado de propósito: a versão anterior recebia `dynamic` e devolvia em
  /// silêncio quando não reconhecia o argumento — na operação mais sensível do
  /// módulo, um erro de chamada virava aceite não registrado, sem exceção
  /// alguma. Documento informativo lança, em vez de fingir que aceitou.
  Future<void> acceptPolicy(LegalDocument doc) async {
    final policyType = doc.policyType;
    if (policyType == null) {
      throw ArgumentError(
        'Documento informativo não gera aceite: ${doc.id}',
      );
    }

    final typeKey = policyType.code;
    final version = doc.version;

    try {
      await _supabase.rpc('accept_policy', params: {
        'p_policy_type': typeKey,
        'p_version': version,
      });
      debugPrint('✅ Aceite de política registrado: $typeKey v$version');
    } catch (e) {
      debugPrint('❌ Erro ao registrar aceite de política ($typeKey): $e');
      rethrow;
    }
  }

  /// Registra o aceite de um lote de documentos.
  Future<void> acceptAllRequiredPolicies() async {
    for (final doc in kAcceptanceDocuments) {
      await acceptPolicy(doc);
    }
  }

  /// Busca os aceites do usuário logado na tabela policy_acceptance.
  Future<List<PolicyAcceptanceRecord>> fetchMyAcceptances() async {
    try {
      final response = await _supabase
          .from('policy_acceptance')
          .select()
          .order('accepted_at', ascending: false);

      final list = response as List<dynamic>? ?? [];
      return list
          .map((item) => PolicyAcceptanceRecord.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      // Propaga em vez de devolver lista vazia: "não consegui consultar" e
      // "não aceitou nada" levam a decisões opostas no portão de aceite —
      // engolir o erro faria uma falha de rede prender no consentimento quem
      // já aceitou, sem conseguir aceitar de novo.
      debugPrint('❌ Erro ao buscar aceites do usuário: $e');
      rethrow;
    }
  }

  /// Retorna quais documentos obrigatórios ainda pendem de aceite.
  Future<List<LegalDocument>> pendingPolicies() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return [];

      final acceptances = await fetchMyAcceptances();
      final pending = <LegalDocument>[];

      for (final doc in kAcceptanceDocuments) {
        final hasAcceptedCurrentVersion = acceptances.any(
          (a) => a.policyType == doc.policyType?.code && a.policyVersion == doc.version,
        );
        if (!hasAcceptedCurrentVersion) {
          pending.add(doc);
        }
      }
      return pending;
    } catch (e) {
      debugPrint('❌ Erro ao verificar políticas pendentes: $e');
      return [];
    }
  }

  /// Exporta todos os dados do titular em JSON via RPC `export_my_data`.
  Future<Map<String, dynamic>> exportMyData() async {
    try {
      final response = await _supabase.rpc('export_my_data');
      if (response is Map<String, dynamic>) {
        return response;
      } else if (response is String) {
        return jsonDecode(response) as Map<String, dynamic>;
      }
      return {'data': response};
    } catch (e) {
      debugPrint('❌ Erro ao exportar dados do titular: $e');
      rethrow;
    }
  }

  /// Cria um pedido formal de titular via RPC `create_titular_request`.
  Future<String> createTitularRequest({
    required String tipo,
    required String descricao,
  }) async {
    try {
      final response = await _supabase.rpc('create_titular_request', params: {
        'p_tipo': tipo,
        'p_descricao': descricao,
      });
      return response.toString();
    } catch (e) {
      debugPrint('❌ Erro ao criar pedido de titular: $e');
      rethrow;
    }
  }

  /// Busca o histórico de pedidos de titular efetuados pelo usuário logado.
  Future<List<TitularRequestRecord>> fetchMyTitularRequests() async {
    try {
      final response = await _supabase
          .from('titular_request')
          .select()
          .order('created_at', ascending: false);

      final list = response as List<dynamic>? ?? [];
      return list
          .map((item) => TitularRequestRecord.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('❌ Erro ao buscar pedidos de titular: $e');
      return [];
    }
  }

  /// Perfil legal do tenant corrente, para preencher os documentos.
  ///
  /// A RPC resolve a organização por `fn_current_org()`, então o mesmo código
  /// serve ao produto de empresa única e ao white label — inclusive quando o
  /// dono da plataforma alterna a empresa em atuação.
  ///
  /// **Propaga a falha de propósito.** Devolver o perfil vazio aqui seria
  /// destrutivo: o formulário de Dados Legais hidrata desta MESMA fonte, então
  /// uma consulta que não respondeu abriria a tela em branco e o primeiro
  /// "Salvar" gravaria vazio por cima do endereço e do Encarregado já
  /// cadastrados. Quem trata a falha é cada chamador — o leitor de documento
  /// cai para o texto cru com colchetes, e o formulário mostra erro em vez de
  /// campos vazios.
  Future<OrgLegalProfile> fetchLegalProfile() async {
    try {
      final res = await _supabase.rpc('get_org_legal_profile');
      if (res == null) return OrgLegalProfile.empty;
      return OrgLegalProfile.fromJson(Map<String, dynamic>.from(res as Map));
    } catch (e) {
      debugPrint('❌ Erro ao buscar o perfil legal da organização: $e');
      rethrow;
    }
  }

  /// Grava o perfil legal do tenant corrente. Só admin, auditado no banco.
  Future<void> saveLegalProfile(OrgLegalProfile profile) async {
    await _supabase.rpc('admin_set_org_legal_profile', params: {
      'p_profile': profile.toJson(),
    });
  }

  /// Substitui o nome da empresa herdado da build.
  ///
  /// Só vale em deployment de empresa única. No white label a identidade tem de
  /// vir do cadastro do tenant — ver [AppConstants.isSingleTenant].
  String _replacePlaceholders(String text) {
    if (!AppConstants.isSingleTenant) return text;
    return text.replaceAll('[NOME_DA_EMPRESA]', AppConstants.companyName);
  }
}
