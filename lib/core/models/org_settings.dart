import 'package:flutter/foundation.dart';

/// Faixa válida e padrão de uma configuração inteira da empresa.
@immutable
class FaixaConfig {
  final int min;
  final int max;
  final int padrao;
  const FaixaConfig(this.min, this.max, this.padrao);
}

/// Contrato de `organizations.settings`.
///
/// Espelha `fn_settings_erro` da migration `20261028140100`: as mesmas chaves
/// e faixas valem no banco (para toda escrita) e aqui (para leitura tipada).
/// `test/org_settings_test.dart` compara as duas listas e falha se divergirem.
///
/// Leitura tolerante: valor ausente, nulo, em texto (`"30"`) ou fora da faixa
/// volta ao padrão — o mesmo que as rotinas do banco fazem com
/// `COALESCE(NULLIF(x, '')::int, padrão)`.
@immutable
class OrgSettings {
  final Map<String, dynamic> bruto;

  const OrgSettings(this.bruto);

  static const vazio = OrgSettings({});

  factory OrgSettings.fromJson(Object? json) => json is Map
      ? OrgSettings(Map<String, dynamic>.from(json))
      : OrgSettings.vazio;

  /// Chaves inteiras conhecidas, com faixa e padrão.
  static const faixas = <String, FaixaConfig>{
    'gps_retencao_dias': FaixaConfig(1, 180, 7),
    'candidato_retencao_meses': FaixaConfig(1, 120, 24),
    'msg_retencao_dias': FaixaConfig(0, 3650, 0),
    'backup_retencao_dias': FaixaConfig(7, 365, 90),
    'backup_max_por_dispositivo': FaixaConfig(1, 30, 5),
    'backup_teto_mb': FaixaConfig(10, 256, 200),
    'avaliacao_qtd': FaixaConfig(1, 15, 5),
    'avaliacao_minutos': FaixaConfig(0, 180, 0),
  };

  static const provedoresIa = {'anthropic', 'openai', 'gemini', 'groq'};

  /// Módulos licenciáveis contratados. Ausente ou inválido → nenhum
  /// (gate estrito, como antes).
  Set<String> get modulos {
    final m = bruto['modules'];
    if (m is List) return m.map((e) => e.toString()).toSet();
    return const {};
  }

  String? get provedorIa {
    final v = bruto['ai_provider'];
    return v is String && provedoresIa.contains(v) ? v : null;
  }

  Map<String, dynamic> get legal {
    final v = bruto['legal'];
    return v is Map ? Map<String, dynamic>.from(v) : const {};
  }

  /// Valor inteiro efetivo de uma chave de [faixas].
  int inteiro(String chave) {
    final faixa = faixas[chave];
    if (faixa == null) {
      throw ArgumentError.value(chave, 'chave', 'não é uma configuração inteira');
    }
    final n = _comoInteiro(bruto[chave]);
    if (n == null || n < faixa.min || n > faixa.max) return faixa.padrao;
    return n;
  }

  int get gpsRetencaoDias => inteiro('gps_retencao_dias');
  int get candidatoRetencaoMeses => inteiro('candidato_retencao_meses');
  int get msgRetencaoDias => inteiro('msg_retencao_dias');
  int get backupRetencaoDias => inteiro('backup_retencao_dias');
  int get backupMaxPorDispositivo => inteiro('backup_max_por_dispositivo');
  int get backupTetoMb => inteiro('backup_teto_mb');
  int get avaliacaoQtd => inteiro('avaliacao_qtd');
  int get avaliacaoMinutos => inteiro('avaliacao_minutos');

  static int? _comoInteiro(Object? v) {
    if (v is int) return v;
    if (v is double && v == v.roundToDouble()) return v.toInt();
    if (v is String && RegExp(r'^\d+$').hasMatch(v)) return int.parse(v);
    return null;
  }

  /// Motivo da recusa de um valor, ou nulo se aceito — mesma regra do banco.
  static String? erro(String chave, Object? valor) {
    if (valor == null) return null;
    switch (chave) {
      case 'modules':
        return valor is List && valor.every((e) => e is String)
            ? null
            : 'deve ser uma lista de identificadores de módulo';
      case 'legal':
        return valor is Map ? null : 'deve ser um objeto';
      case 'ai_provider':
        return valor is String && provedoresIa.contains(valor)
            ? null
            : 'provedor não suportado (anthropic, openai, gemini ou groq)';
    }
    final faixa = faixas[chave];
    if (faixa == null) return null; // fora do contrato
    if (valor is String && valor.isEmpty) return null;
    final n = _comoInteiro(valor);
    if (n == null) return 'deve ser um número inteiro';
    if (n < faixa.min || n > faixa.max) {
      return 'deve ficar entre ${faixa.min} e ${faixa.max}';
    }
    return null;
  }
}
