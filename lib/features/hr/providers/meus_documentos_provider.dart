import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:alinha_ja/core/supabase_client.dart';

final meuFuncionarioIdProvider = FutureProvider.autoDispose<String?>((ref) async {
  final userId = supabase.auth.currentUser?.id;
  if (userId == null) return null;

  // Ficha excluída (soft delete) não dá acesso às telas self-service.
  final response = await supabase
      .from('funcionario')
      .select('id')
      .eq('user_id', userId)
      .isFilter('deleted_at', null)
      .maybeSingle();

  if (response == null) return null;
  return response['id'] as String;
});

final meuOrgIdProvider = FutureProvider.autoDispose<String?>((ref) async {
  final userId = supabase.auth.currentUser?.id;
  if (userId == null) return null;

  final response = await supabase
      .from('users')
      .select('organization_id')
      .eq('id', userId)
      .maybeSingle();

  if (response == null) return null;
  return response['organization_id'] as String;
});
