import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:alinha_ja/features/hr/models/rh_documento_model.dart';

class RhDocumentoRepository {
  final SupabaseClient _supabase;

  RhDocumentoRepository(this._supabase);

  /// Retorna os documentos de um funcionário específico (Visão do Funcionário ou Visão Detalhe RH)
  Future<List<RhDocumento>> getDocumentosByFuncionario(String funcionarioId) async {
    final response = await _supabase
        .from('rh_documento')
        .select()
        .eq('funcionario_id', funcionarioId)
        .isFilter('deleted_at', null)
        .order('created_at', ascending: false);

    return (response as List).map((json) => RhDocumento.fromJson(json)).toList();
  }

  /// Retorna todos os documentos da empresa (Visão Gerencial do RH)
  Future<List<RhDocumento>> getTodosDocumentos() async {
    final response = await _supabase
        .from('rh_documento')
        .select('*, funcionario(id, nome)')
        .isFilter('deleted_at', null)
        .order('data_vencimento', ascending: true, nullsFirst: false);
    
    // Na visão gerencial, podemos querer parsear os dados do funcionário anexados.
    // O modelo base RhDocumento não tem as infos aninhadas, mas podemos retornar a lista
    // e o Provider cuida de estruturar, ou podemos mapear.
    return (response as List).map((json) => RhDocumento.fromJson(json)).toList();
  }
  
  /// Retorna apenas os documentos próximos do vencimento ou vencidos
  Future<List<Map<String, dynamic>>> getDocumentosAlertaVencimento() async {
    final response = await _supabase
        .from('rh_documento')
        .select('*, funcionario(id, nome)')
        .isFilter('deleted_at', null)
        .inFilter('status', ['proximo_vencimento', 'vencido'])
        .order('data_vencimento', ascending: true);
        
    return List<Map<String, dynamic>>.from(response);
  }

  /// Faz upload do arquivo para o Storage e salva o registro na tabela
  Future<RhDocumento> uploadDocumento({
    required String funcionarioId,
    required String orgId,
    required String titulo,
    required DocumentoCategoria categoria,
    required Uint8List fileBytes,
    required String fileName,
    required String mimeType,
    String? descricao,
    DateTime? dataEmissao,
    DateTime? dataVencimento,
    DocumentoStatus status = DocumentoStatus.pendenteAprovacao,
  }) async {
    // 1. Upload no Storage
    final uniqueName = '${DateTime.now().millisecondsSinceEpoch}_$fileName';
    final storagePath = '$funcionarioId/$uniqueName';

    await _supabase.storage.from('rh-documentos').uploadBinary(
          storagePath,
          fileBytes,
          fileOptions: FileOptions(
            contentType: mimeType,
            upsert: true,
          ),
        );

    // 2. Insert na Tabela
    final insertData = {
      'organization_id': orgId,
      'funcionario_id': funcionarioId,
      'titulo': titulo,
      'descricao': descricao,
      'categoria': categoria.toString().split('.').last, // json value
      'storage_path': storagePath,
      'data_emissao': dataEmissao?.toIso8601String(),
      'data_vencimento': dataVencimento?.toIso8601String(),
      'status': status.toString().split('.').last, // json value
    };

    final response = await _supabase
        .from('rh_documento')
        .insert(insertData)
        .select()
        .single();

    return RhDocumento.fromJson(response);
  }

  /// Atualiza o status do documento (ex.: aprovar → 'valido')
  Future<RhDocumento> updateStatus(String id, DocumentoStatus status) async {
    final response = await _supabase
        .from('rh_documento')
        .update({'status': status.toString().split('.').last})
        .eq('id', id)
        .select()
        .single();

    return RhDocumento.fromJson(response);
  }

  /// Rejeita um documento registrando o motivo (S098).
  /// Vai pela RPC rh_rejeitar_documento (valida papel RH + motivo).
  Future<void> rejeitarDocumento(String id, String motivo) async {
    await _supabase.rpc('rh_rejeitar_documento', params: {
      'p_documento_id': id,
      'p_motivo': motivo,
    });
  }
  
  // ── Aceite eletrônico (RH-24) ──────────────────────────────

  /// RH liga/desliga a exigência de aceite do funcionário.
  Future<void> setExigeAceite(String id, bool exige) async {
    await _supabase.rpc('rh_set_exige_aceite', params: {
      'p_documento_id': id,
      'p_exige': exige,
    });
  }

  /// Funcionário registra o aceite. Quem, quando e de onde é carimbado
  /// no servidor — daí passar por RPC em vez de update direto.
  /// Retorna o instante do aceite.
  Future<DateTime> aceitarDocumento(String id) async {
    final res = await _supabase.rpc('rh_aceitar_documento', params: {
      'p_documento_id': id,
    });
    return DateTime.parse(res as String).toLocal();
  }

  /// Documentos da org aguardando aceite (visão do RH).
  Future<List<Map<String, dynamic>>> getAceitesPendentes() async {
    final response = await _supabase
        .from('rh_documento_aceite_pendente')
        .select()
        .order('created_at', ascending: true);
    return List<Map<String, dynamic>>.from(response);
  }

  /// Soft delete de um documento
  Future<void> deleteDocumento(String id) async {
    await _supabase
        .from('rh_documento')
        .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', id);
  }

  /// Gera uma Signed URL de 15 minutos para visualizar/baixar o arquivo
  Future<String> getSignedUrl(String storagePath) async {
    final url = await _supabase.storage
        .from('rh-documentos')
        .createSignedUrl(storagePath, 60 * 15); // 15 minutos
    return url;
  }
}
