import 'package:alinha_ja/core/supabase_client.dart';
import 'package:alinha_ja/features/hr/models/vacancy_model.dart';

/// Onda 2 — Vagas (RH-10) e Catálogo Áreas/Cargos (RH-9).
/// Leitura via `vaga_resumo`/tabelas do catálogo; escrita direta nas
/// tabelas (RLS exige papel RH e a org é carimbada por trigger).
class VacancyService {
  const VacancyService();

  // ── Vagas ───────────────────────────────────────────────────

  Future<List<VagaModel>> fetchVagas() async {
    final data = await supabase
        .from('vaga_resumo')
        .select()
        .order('created_at', ascending: false);
    return (data as List)
        .map((e) => VagaModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<String> createVaga(Map<String, dynamic> fields) async {
    final inserted = await supabase
        .from('vaga')
        .insert({
          ...fields,
          'created_by': supabase.auth.currentUser!.id,
        })
        .select('id')
        .single();
    return inserted['id'] as String;
  }

  Future<void> updateVaga(String id, Map<String, dynamic> fields) async {
    await supabase.from('vaga').update({
      ...fields,
      'updated_by': supabase.auth.currentUser!.id,
    }).eq('id', id);
  }

  Future<void> setStatus(String id, String status) =>
      updateVaga(id, {'status': status});

  /// Soft delete (padrão S006 do módulo).
  Future<void> softDelete(String id) async {
    await supabase.from('vaga').update({
      'deleted_at': DateTime.now().toUtc().toIso8601String(),
      'deleted_by': supabase.auth.currentUser!.id,
    }).eq('id', id);
  }

  // ── Catálogo (RH-9) ─────────────────────────────────────────

  Future<List<CatalogItem>> fetchAreas({bool somenteAtivas = false}) async {
    var query = supabase.from('rh_area').select('id, nome, ativo');
    if (somenteAtivas) query = query.eq('ativo', true);
    final data = await query.order('nome');
    return (data as List)
        .map((e) => CatalogItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<CatalogItem>> fetchCargos({bool somenteAtivos = false}) async {
    var query = supabase
        .from('rh_cargo')
        .select('id, nome, ativo, area_id, nivel_sugerido');
    if (somenteAtivos) query = query.eq('ativo', true);
    final data = await query.order('nome');
    return (data as List)
        .map((e) => CatalogItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> createArea(String nome) async {
    await supabase.from('rh_area').insert({
      'nome': nome.trim(),
      'created_by': supabase.auth.currentUser!.id,
    });
  }

  Future<void> updateArea(String id,
      {String? nome, bool? ativo}) async {
    await supabase.from('rh_area').update({
      if (nome != null) 'nome': nome.trim(),
      if (ativo != null) 'ativo': ativo,
    }).eq('id', id);
  }

  Future<void> createCargo(String nome,
      {String? areaId, String? nivelSugerido}) async {
    await supabase.from('rh_cargo').insert({
      'nome': nome.trim(),
      'area_id': areaId,
      'nivel_sugerido': nivelSugerido,
      'created_by': supabase.auth.currentUser!.id,
    });
  }

  Future<void> updateCargo(String id,
      {String? nome, Object? areaId = _sentinel, String? nivelSugerido,
      bool? ativo}) async {
    await supabase.from('rh_cargo').update({
      if (nome != null) 'nome': nome.trim(),
      if (!identical(areaId, _sentinel)) 'area_id': areaId,
      if (nivelSugerido != null) 'nivel_sugerido': nivelSugerido,
      if (ativo != null) 'ativo': ativo,
    }).eq('id', id);
  }

  static const _sentinel = Object();
}
