import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alinha_ja/features/legal/data/legal_documents.dart';
import 'package:alinha_ja/features/legal/models/legal_document_model.dart';
import 'package:alinha_ja/features/legal/providers/legal_provider.dart';

/// O portão de aceite observa `pendingPoliciesProvider`. Se esse provider não
/// derivar de `myAcceptancesProvider`, aceitar registra tudo no servidor e a
/// tela de consentimento não sai da frente — falha que a análise estática não
/// pega, porque os dois lados compilam perfeitamente.
void main() {
  PolicyAcceptanceRecord aceite(LegalDocument doc, {String? versao}) {
    return PolicyAcceptanceRecord(
      policyType: doc.policyType!.code,
      policyVersion: versao ?? doc.version,
      acceptedAt: DateTime(2026, 8, 4),
    );
  }

  Future<List<LegalDocument>> pendentes(
    List<PolicyAcceptanceRecord> aceites,
  ) async {
    final container = ProviderContainer(
      overrides: [
        myAcceptancesProvider.overrideWith((ref) async => aceites),
      ],
    );
    addTearDown(container.dispose);
    return container.read(pendingPoliciesProvider.future);
  }

  test('sem nenhum aceite, todos os documentos obrigatórios pendem', () async {
    final result = await pendentes([]);
    expect(result.map((d) => d.id), kAcceptanceDocuments.map((d) => d.id));
  });

  test('aceitar tudo na versão vigente esvazia a lista — o portão sai',
      () async {
    final result = await pendentes(
      kAcceptanceDocuments.map(aceite).toList(),
    );
    expect(result, isEmpty);
  });

  test('aceite de versão antiga não conta: o documento volta a pender',
      () async {
    final result = await pendentes(
      kAcceptanceDocuments.map((d) => aceite(d, versao: '0.9.0')).toList(),
    );
    expect(result.length, kAcceptanceDocuments.length);
  });

  test('aceite parcial deixa pendente só o que falta', () async {
    final primeiro = kAcceptanceDocuments.first;
    final result = await pendentes([aceite(primeiro)]);

    expect(result.map((d) => d.id), isNot(contains(primeiro.id)));
    expect(result.length, kAcceptanceDocuments.length - 1);
  });
}
