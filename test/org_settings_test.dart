import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:alinha_ja/core/models/org_settings.dart';

/// Contrato de `organizations.settings`: leitura tipada no app e a mesma
/// regra do trigger do banco.
void main() {
  test('lê valores, aceita número em texto e volta ao padrão quando inválido', () {
    final s = OrgSettings.fromJson(const {
      'gps_retencao_dias': 30,
      'backup_retencao_dias': '120',
      'backup_teto_mb': 9999, // fora da faixa
      'avaliacao_qtd': 'cinco', // não numérico
      'modules': ['rh_ponto', 'helpdesk'],
      'ai_provider': 'gemini',
    });
    expect(s.gpsRetencaoDias, 30);
    expect(s.backupRetencaoDias, 120);
    expect(s.backupTetoMb, 200);
    expect(s.avaliacaoQtd, 5);
    expect(s.candidatoRetencaoMeses, 24, reason: 'ausente → padrão');
    expect(s.modulos, {'rh_ponto', 'helpdesk'});
    expect(s.provedorIa, 'gemini');
  });

  test('settings ausente ou malformado não quebra a leitura', () {
    expect(OrgSettings.fromJson(null).modulos, isEmpty);
    expect(OrgSettings.fromJson('lixo').gpsRetencaoDias, 7);
    expect(OrgSettings.fromJson(const {'modules': 'rh'}).modulos, isEmpty);
    expect(OrgSettings.fromJson(const {'ai_provider': 'chatgpt'}).provedorIa, isNull);
  });

  test('erro() aceita e recusa como o banco', () {
    expect(OrgSettings.erro('gps_retencao_dias', 30), isNull);
    expect(OrgSettings.erro('gps_retencao_dias', '30'), isNull);
    expect(OrgSettings.erro('gps_retencao_dias', ''), isNull);
    expect(OrgSettings.erro('gps_retencao_dias', null), isNull);
    expect(OrgSettings.erro('gps_retencao_dias', 365), 'deve ficar entre 1 e 180');
    expect(OrgSettings.erro('backup_teto_mb', 'muito'), 'deve ser um número inteiro');
    expect(OrgSettings.erro('modules', ['a', 1]), isNotNull);
    expect(OrgSettings.erro('ai_provider', 'chatgpt'), isNotNull);
    expect(OrgSettings.erro('chave_nova', {'x': 1}), isNull);
  });

  test('faixas e provedores do app batem com o trigger do banco', () {
    final sql = File(
            'supabase/migrations/20261028140100_contrato_settings_empresa.sql')
        .readAsStringSync();
    final faixasSql = {
      for (final m in RegExp(r"WHEN '([a-z_]+)'\s+THEN ARRAY\[(\d+), (\d+)\]")
          .allMatches(sql))
        m.group(1)!: [int.parse(m.group(2)!), int.parse(m.group(3)!)],
    };
    expect(faixasSql.keys.toSet(), OrgSettings.faixas.keys.toSet());
    OrgSettings.faixas.forEach((chave, f) {
      expect(faixasSql[chave], [f.min, f.max], reason: chave);
    });

    final provedores = RegExp(r"NOT IN \(([^)]+)\)")
        .firstMatch(sql.substring(sql.indexOf("WHEN 'ai_provider'")))!
        .group(1)!
        .split(',')
        .map((p) => p.trim().replaceAll("'", ''))
        .toSet();
    expect(provedores, OrgSettings.provedoresIa);
  });
}
