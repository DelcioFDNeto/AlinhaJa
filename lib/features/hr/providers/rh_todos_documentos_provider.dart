import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:alinha_ja/features/hr/models/rh_documento_model.dart';
import 'package:alinha_ja/features/hr/providers/rh_documento_provider.dart';

final rhTodosDocumentosProvider = FutureProvider.autoDispose<List<RhDocumento>>((ref) async {
  final repo = ref.watch(rhDocumentoRepositoryProvider);
  return repo.getTodosDocumentos();
});
