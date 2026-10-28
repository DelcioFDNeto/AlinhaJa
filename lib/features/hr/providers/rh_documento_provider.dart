import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:alinha_ja/core/supabase_client.dart';
import 'package:alinha_ja/features/hr/models/rh_documento_model.dart';
import 'package:alinha_ja/features/hr/services/rh_documento_repository.dart';

final rhDocumentoRepositoryProvider = Provider<RhDocumentoRepository>((ref) {
  return RhDocumentoRepository(supabase);
});

/// Provider para buscar alertas de vencimento (Visão RH)
final rhDocumentosAlertaProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final repo = ref.watch(rhDocumentoRepositoryProvider);
  return await repo.getDocumentosAlertaVencimento();
});

/// Provider para os documentos de um funcionário específico
final rhDocumentosPorFuncionarioProvider = 
  StateNotifierProvider.family<RhDocumentosNotifier, AsyncValue<List<RhDocumento>>, String>((ref, funcionarioId) {
    return RhDocumentosNotifier(ref.watch(rhDocumentoRepositoryProvider), funcionarioId);
});

class RhDocumentosNotifier extends StateNotifier<AsyncValue<List<RhDocumento>>> {
  final RhDocumentoRepository _repository;
  final String _funcionarioId;

  RhDocumentosNotifier(this._repository, this._funcionarioId) : super(const AsyncValue.loading()) {
    loadDocumentos();
  }

  Future<void> loadDocumentos() async {
    state = const AsyncValue.loading();
    try {
      final docs = await _repository.getDocumentosByFuncionario(_funcionarioId);
      state = AsyncValue.data(docs);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> upload({
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
    try {
      final novoDoc = await _repository.uploadDocumento(
        funcionarioId: _funcionarioId,
        orgId: orgId,
        titulo: titulo,
        categoria: categoria,
        fileBytes: fileBytes,
        fileName: fileName,
        mimeType: mimeType,
        descricao: descricao,
        dataEmissao: dataEmissao,
        dataVencimento: dataVencimento,
        status: status,
      );

      if (state.hasValue) {
        state = AsyncValue.data([novoDoc, ...state.value!]);
      } else {
        state = AsyncValue.data([novoDoc]);
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> updateStatus(String docId, DocumentoStatus status) async {
    try {
      final updated = await _repository.updateStatus(docId, status);
      if (state.hasValue) {
        final current = state.value!;
        final index = current.indexWhere((d) => d.id == docId);
        if (index != -1) {
          final newList = List<RhDocumento>.from(current);
          newList[index] = updated;
          state = AsyncValue.data(newList);
        }
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> delete(String docId) async {
    try {
      await _repository.deleteDocumento(docId);
      if (state.hasValue) {
        final current = state.value!;
        final newList = current.where((d) => d.id != docId).toList();
        state = AsyncValue.data(newList);
      }
    } catch (e) {
      rethrow;
    }
  }
}
