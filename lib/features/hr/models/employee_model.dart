/// Models do RH-4 — Ficha do Funcionário.
/// Espelham funcionario_resumo (view) e as RPCs de dados sensíveis.
library;

import 'package:alinha_ja/core/status_role.dart';

class EmployeeStatus {
  EmployeeStatus._();

  static const labels = {
    'ativo': 'Ativo',
    'ferias': 'Férias',
    'afastado': 'Afastado',
    'desligado': 'Desligado',
  };

  static String label(String s) => labels[s] ?? s;

  /// Papel semântico por status — a cor é resolvida no tema (white-label).
  static const roles = {
    'ativo': StatusRole.success,
    'ferias': StatusRole.info,
    'afastado': StatusRole.warning,
    'desligado': StatusRole.neutral,
  };

  static StatusRole role(String s) => roles[s] ?? StatusRole.neutral;
}

class VinculoTipo {
  VinculoTipo._();

  static const labels = {
    'clt': 'CLT',
    'pj': 'PJ',
    'estagio': 'Estágio',
    'temporario': 'Temporário',
    'aprendiz': 'Aprendiz',
  };

  static String label(String s) => labels[s] ?? s;
}

class VinculoStatus {
  VinculoStatus._();

  static const labels = {
    'experiencia': 'Em experiência',
    'efetivo': 'Efetivo',
    'aviso_previo': 'Aviso prévio',
    'desligado': 'Desligado',
  };

  static String label(String s) => labels[s] ?? s;
}

/// Linha da view `funcionario_resumo` — dados públicos (S075).
class EmployeeModel {
  final String id;
  final String nome;
  final String? fotoUrl;
  final String status;
  final String? userId;
  final String? candidatoId;
  final String? vinculoId;
  final String? vinculoTipo;
  final String? vinculoStatus;
  final DateTime? dataAdmissao;
  final String? matricula;
  final String? filial;
  final String? departamento;
  final String? cargo;

  const EmployeeModel({
    required this.id,
    required this.nome,
    this.fotoUrl,
    required this.status,
    this.userId,
    this.candidatoId,
    this.vinculoId,
    this.vinculoTipo,
    this.vinculoStatus,
    this.dataAdmissao,
    this.matricula,
    this.filial,
    this.departamento,
    this.cargo,
  });

  factory EmployeeModel.fromJson(Map<String, dynamic> json) => EmployeeModel(
        id: json['id'] as String,
        nome: (json['nome'] as String?) ?? '',
        fotoUrl: json['foto_url'] as String?,
        status: (json['status'] as String?) ?? 'ativo',
        userId: json['user_id'] as String?,
        candidatoId: json['candidato_id'] as String?,
        vinculoId: json['vinculo_id'] as String?,
        vinculoTipo: json['vinculo_tipo'] as String?,
        vinculoStatus: json['vinculo_status'] as String?,
        dataAdmissao: json['data_admissao'] != null
            ? DateTime.tryParse(json['data_admissao'] as String)
            : null,
        matricula: json['matricula'] as String?,
        filial: json['filial'] as String?,
        departamento: json['departamento'] as String?,
        cargo: json['cargo'] as String?,
      );

  String get initials => nome.isNotEmpty ? nome[0].toUpperCase() : '?';

  String get lotacao => [filial, departamento, cargo]
      .where((e) => e != null && e.isNotEmpty)
      .join(' · ');
}

/// Retorno da RPC `rh_get_dados_sensiveis` — cada leitura é auditada.
class EmployeeSensitiveData {
  final bool exists;
  final String? cpf;
  final String? rg;
  final DateTime? dataNascimento;
  final String? emailPessoal;
  final String? telefone;
  final Map<String, dynamic>? endereco;
  final String? dadosBancarios;
  final String? estadoCivil;
  final int? dependentes;
  final bool pcd;
  final String? tipoDeficiencia;
  final String? salario;

  const EmployeeSensitiveData({
    required this.exists,
    this.cpf,
    this.rg,
    this.dataNascimento,
    this.emailPessoal,
    this.telefone,
    this.endereco,
    this.dadosBancarios,
    this.estadoCivil,
    this.dependentes,
    this.pcd = false,
    this.tipoDeficiencia,
    this.salario,
  });

  factory EmployeeSensitiveData.fromJson(Map<String, dynamic> json) =>
      EmployeeSensitiveData(
        exists: (json['exists'] as bool?) ?? false,
        cpf: json['cpf'] as String?,
        rg: json['rg'] as String?,
        dataNascimento: json['data_nascimento'] != null
            ? DateTime.tryParse(json['data_nascimento'] as String)
            : null,
        emailPessoal: json['email_pessoal'] as String?,
        telefone: json['telefone'] as String?,
        endereco: json['endereco'] as Map<String, dynamic>?,
        dadosBancarios: json['dados_bancarios'] as String?,
        estadoCivil: json['estado_civil'] as String?,
        dependentes: json['dependentes'] as int?,
        pcd: (json['pcd'] as bool?) ?? false,
        tipoDeficiencia: json['tipo_deficiencia'] as String?,
        salario: json['salario'] as String?,
      );
}
