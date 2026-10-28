import 'package:alinha_ja/core/status_role.dart';

/// Tipos de batida do ponto (slugs gravados em rh_ponto_registro.tipo).
class PontoTipo {
  static const entrada = 'entrada';
  static const saidaAlmoco = 'saida_almoco';
  static const retornoAlmoco = 'retorno_almoco';
  static const saida = 'saida';

  static const ordem = [entrada, saidaAlmoco, retornoAlmoco, saida];

  static String label(String tipo) => switch (tipo) {
        entrada => 'Entrada',
        saidaAlmoco => 'Saída almoço',
        retornoAlmoco => 'Retorno almoço',
        saida => 'Saída',
        _ => tipo,
      };
}

/// Status do registro de ponto → papel semântico (tokens white-label).
class PontoStatus {
  static String label(String status) => switch (status) {
        'aprovado' => 'Aprovado',
        'aguardando_ajuste' => 'Aguardando ajuste',
        'rejeitado' => 'Rejeitado',
        _ => status,
      };

  static StatusRole role(String status) => switch (status) {
        'aprovado' => StatusRole.success,
        'aguardando_ajuste' => StatusRole.warning,
        'rejeitado' => StatusRole.danger,
        _ => StatusRole.neutral,
      };
}

class PontoRegistroModel {
  final String id;
  final String organizationId;
  final String funcionarioId;
  final String? funcionarioNome;
  final DateTime dataHora;
  final String tipo; // PontoTipo.*
  final double? latitude;
  final double? longitude;
  final String? dispositivoInfo;
  final String origem; // 'app' ou 'importacao'
  final String status; // aprovado, aguardando_ajuste, rejeitado
  final DateTime createdAt;

  const PontoRegistroModel({
    required this.id,
    required this.organizationId,
    required this.funcionarioId,
    this.funcionarioNome,
    required this.dataHora,
    required this.tipo,
    this.latitude,
    this.longitude,
    this.dispositivoInfo,
    required this.origem,
    required this.status,
    required this.createdAt,
  });

  factory PontoRegistroModel.fromMap(Map<String, dynamic> map) {
    return PontoRegistroModel(
      id: map['id'] as String,
      organizationId: map['organization_id'] as String,
      funcionarioId: map['funcionario_id'] as String,
      funcionarioNome: map['funcionario']?['nome'] as String?,
      dataHora: DateTime.parse(map['data_hora']),
      tipo: map['tipo'] as String,
      latitude: map['latitude'] != null ? double.tryParse(map['latitude'].toString()) : null,
      longitude: map['longitude'] != null ? double.tryParse(map['longitude'].toString()) : null,
      dispositivoInfo: map['dispositivo_info'] as String?,
      origem: map['origem'] as String,
      status: map['status'] as String,
      createdAt: DateTime.parse(map['created_at']),
    );
  }
}
