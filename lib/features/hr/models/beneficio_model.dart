/// Fase 8 — Benefícios (rh_beneficio / rh_funcionario_beneficio).
class BeneficioModel {
  final String id;
  final String organizationId;
  final String nome;
  final String tipo; // Saúde, Odonto, VA, VR, VT, etc
  final String? fornecedor;
  final bool ativo;

  const BeneficioModel({
    required this.id,
    required this.organizationId,
    required this.nome,
    required this.tipo,
    this.fornecedor,
    this.ativo = true,
  });

  factory BeneficioModel.fromMap(Map<String, dynamic> map) => BeneficioModel(
        id: map['id'] as String,
        organizationId: map['organization_id'] as String,
        nome: map['nome'] as String? ?? '',
        tipo: map['tipo'] as String? ?? '',
        fornecedor: map['fornecedor'] as String?,
        ativo: map['ativo'] as bool? ?? true,
      );
}

/// Adesão de funcionário a um benefício. O valor de desconto em folha é
/// cifrado no banco e só chega aqui via RPC `rh_list_adesoes_beneficio`.
class BeneficioAdesao {
  final String id;
  final String funcionarioId;
  final String? funcionarioNome;
  final String beneficioId;
  final String beneficioNome;
  final String beneficioTipo;
  final DateTime dataAdesao;
  final DateTime? dataCancelamento;
  final String? valorDesconto;

  const BeneficioAdesao({
    required this.id,
    required this.funcionarioId,
    this.funcionarioNome,
    required this.beneficioId,
    required this.beneficioNome,
    required this.beneficioTipo,
    required this.dataAdesao,
    this.dataCancelamento,
    this.valorDesconto,
  });

  bool get ativa => dataCancelamento == null;

  factory BeneficioAdesao.fromMap(Map<String, dynamic> map) => BeneficioAdesao(
        id: map['id'] as String,
        funcionarioId: map['funcionario_id'] as String,
        funcionarioNome: map['funcionario_nome'] as String?,
        beneficioId: map['beneficio_id'] as String,
        beneficioNome: map['beneficio_nome'] as String? ?? '',
        beneficioTipo: map['beneficio_tipo'] as String? ?? '',
        dataAdesao: DateTime.parse(map['data_adesao'] as String),
        dataCancelamento: map['data_cancelamento'] != null
            ? DateTime.parse(map['data_cancelamento'] as String)
            : null,
        valorDesconto: map['valor_desconto'] as String?,
      );
}
