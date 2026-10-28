import 'package:alinha_ja/core/supabase_client.dart';
import 'package:alinha_ja/features/hr/models/employee_model.dart';

/// RH-4 — Ficha do Funcionário.
/// Dados públicos via view `funcionario_resumo`; sensíveis somente
/// pelas RPCs (que validam papel RH e auditam em rh_access_log).
class EmployeeService {
  const EmployeeService();

  static const pageSize = 50;

  Future<List<EmployeeModel>> fetchEmployees({
    String search = '',
    String? status,
    int page = 0,
  }) async {
    var query = supabase.from('funcionario_resumo').select();
    if (status != null) query = query.eq('status', status);
    if (search.isNotEmpty) {
      final s = search.replaceAll('%', r'\%');
      query = query.or('nome.ilike.%$s%,matricula.ilike.%$s%');
    }
    final data = await query
        .order('nome')
        .range(page * pageSize, (page + 1) * pageSize - 1);
    return (data as List)
        .map((e) => EmployeeModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Headcount por status para o cabeçalho da lista (RH-4.1).
  /// Uma única query na view agregada `funcionario_contagem_status`
  /// (espelha `candidato_contagem_status`); statuses sem linhas não
  /// voltam e o cabeçalho já trata ausência como zero.
  Future<Map<String, int>> fetchStatusCounts() async {
    final data = await supabase
        .from('funcionario_contagem_status')
        .select('status, total');
    return {
      for (final row in data as List)
        row['status'] as String: (row['total'] as num).toInt(),
    };
  }

  Future<EmployeeModel> fetchEmployee(String id) async {
    final data = await supabase
        .from('funcionario_resumo')
        .select()
        .eq('id', id)
        .single();
    return EmployeeModel.fromJson(data);
  }

  /// Cada chamada é registrada em rh_access_log (S008) — por isso a
  /// tela só busca quando o usuário pede explicitamente.
  Future<EmployeeSensitiveData> fetchSensitiveData(String funcionarioId) async {
    final data = await supabase.rpc('rh_get_dados_sensiveis',
        params: {'p_funcionario_id': funcionarioId});
    return EmployeeSensitiveData.fromJson(
        (data as Map).cast<String, dynamic>());
  }

  /// Grava dados sensíveis (RPC valida CPF e exige rh_admin — S080).
  Future<void> saveSensitiveData(
      String funcionarioId, Map<String, dynamic> dados) async {
    await supabase.rpc('rh_upsert_dados_sensiveis', params: {
      'p_funcionario_id': funcionarioId,
      'p_dados': dados,
    });
  }

  /// Cadastro direto (sem candidato) — funcionário + vínculo.
  Future<String> createEmployee({
    required String nome,
    required Map<String, dynamic> vinculo,
  }) async {
    final me = await supabase
        .from('users')
        .select('organization_id')
        .eq('id', supabase.auth.currentUser!.id)
        .single();

    final inserted = await supabase
        .from('funcionario')
        .insert({
          'nome': nome,
          'organization_id': me['organization_id'],
          'created_by': supabase.auth.currentUser!.id,
        })
        .select('id')
        .single();
    final id = inserted['id'] as String;

    await supabase.from('vinculo').insert({
      'funcionario_id': id,
      'organization_id': me['organization_id'],
      'created_by': supabase.auth.currentUser!.id,
      ...vinculo,
    });
    return id;
  }

  Future<void> updateStatus(String id, String status) async {
    await supabase.from('funcionario').update({
      'status': status,
      'updated_by': supabase.auth.currentUser!.id,
    }).eq('id', id);
  }

  /// Vínculo vigente da ficha — o mesmo que `funcionario_resumo` resume,
  /// mas com os ids de filial/departamento/cargo (a view só expõe os
  /// nomes) para pré-preencher os dropdowns da edição.
  /// Null = ficha sem vínculo: acontece nas fichas importadas em massa.
  Future<Map<String, dynamic>?> fetchVinculo(String funcionarioId) async {
    return await supabase
        .from('vinculo')
        .select('id, tipo, status, data_admissao, matricula, carga_horaria, '
            'filial_id, departamento_id, cargo_id')
        .eq('funcionario_id', funcionarioId)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
  }

  /// Cria ou corrige o vínculo da ficha (policy "RH acessa vínculos").
  /// `vinculoId` nulo cria a linha — caminho das fichas que vieram da
  /// carga em massa de usuários e das que ficaram sem vínculo.
  Future<void> saveVinculo({
    required String funcionarioId,
    String? vinculoId,
    required Map<String, dynamic> dados,
  }) async {
    if (vinculoId != null) {
      await supabase.from('vinculo').update(dados).eq('id', vinculoId);
      return;
    }

    final me = await supabase
        .from('users')
        .select('organization_id')
        .eq('id', supabase.auth.currentUser!.id)
        .single();

    await supabase.from('vinculo').insert({
      'funcionario_id': funcionarioId,
      'organization_id': me['organization_id'],
      'created_by': supabase.auth.currentUser!.id,
      ...dados,
    });
  }

  /// Conversão candidato aprovado → funcionário (S078/B011).
  Future<String> convertCandidate({
    required String candidatoId,
    String tipo = 'clt',
    DateTime? dataAdmissao,
    String? matricula,
    String? cargaHoraria,
    String? salario,
    String? filialId,
    String? departamentoId,
    String? cargoId,
  }) async {
    final result = await supabase.rpc('rh_converter_candidato', params: {
      'p_candidato_id': candidatoId,
      'p_tipo': tipo,
      'p_data_admissao': (dataAdmissao ?? DateTime.now())
          .toIso8601String()
          .split('T')
          .first,
      'p_matricula': matricula,
      'p_carga_horaria': cargaHoraria,
      'p_salario': salario,
      'p_filial_id': filialId,
      'p_departamento_id': departamentoId,
      'p_cargo_id': cargoId,
    });
    return result as String;
  }

  // ── F1.2 — Vínculo funcionário ↔ usuário do app ─────────────

  /// Dados de exibição do usuário vinculado (nome/e-mail/avatar).
  Future<Map<String, dynamic>?> fetchUserBrief(String userId) async {
    return await supabase
        .from('users')
        .select('id, full_name, email, avatar_url')
        .eq('id', userId)
        .maybeSingle();
  }

  /// Usuários da org disponíveis para vínculo (view org_users_vinculaveis).
  /// Usuários já vinculados a outro funcionário ficam de fora.
  Future<List<Map<String, dynamic>>> fetchLinkableUsers(String search) async {
    var query = supabase
        .from('org_users_vinculaveis')
        .select('id, full_name, email, avatar_url')
        .eq('ja_vinculado', false);
    if (search.isNotEmpty) {
      final s = search.replaceAll('%', r'\%');
      query = query.or('full_name.ilike.%$s%,email.ilike.%$s%');
    }
    final data = await query.order('full_name').limit(30);
    return (data as List).cast<Map<String, dynamic>>();
  }

  /// RPC auditada — exige rh_admin e garante unicidade 1:1.
  Future<void> vincularUsuario(String funcionarioId, String userId) async {
    await supabase.rpc('rh_vincular_usuario', params: {
      'p_funcionario_id': funcionarioId,
      'p_user_id': userId,
    });
  }

  Future<void> desvincularUsuario(String funcionarioId) async {
    await supabase.rpc('rh_desvincular_usuario',
        params: {'p_funcionario_id': funcionarioId});
  }

  /// Estrutura organizacional para os dropdowns do formulário.
  Future<Map<String, List<Map<String, dynamic>>>> fetchOrgStructure() async {
    final results = await Future.wait([
      supabase.from('branches').select('id, name').order('name'),
      supabase
          .from('departments')
          .select('id, name')
          .eq('is_active', true)
          .order('name'),
      supabase
          .from('job_positions')
          .select('id, name')
          .eq('is_active', true)
          .order('name'),
    ]);
    return {
      'branches': (results[0] as List).cast<Map<String, dynamic>>(),
      'departments': (results[1] as List).cast<Map<String, dynamic>>(),
      'positions': (results[2] as List).cast<Map<String, dynamic>>(),
    };
  }
}
