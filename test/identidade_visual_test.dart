import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alinha_ja/core/brand/brand_theme.dart';
import 'package:alinha_ja/core/brand/identidade_repository.dart';
import 'package:alinha_ja/core/brand/org_identity.dart';
import 'package:alinha_ja/core/constants.dart';
import 'package:alinha_ja/core/theme_provider.dart';

/// White-label (Fase 2): identidade da empresa, tema derivado e as guardas
/// que impedem a marca de voltar a ficar presa no código.
void main() {
  group('OrgIdentity', () {
    test('hex ↔ cor, com e sem #, em maiúsculas', () {
      final c = OrgIdentity.corDeHex('#1565c0')!;
      expect(c.toARGB32(), 0xFF1565C0);
      expect(OrgIdentity.corDeHex('1565C0'), c);
      expect(OrgIdentity.hexDeCor(c), '#1565C0');
    });

    test('formatos inválidos viram nulo', () {
      for (final v in [null, '', '#12345', '#1234567', 'azul', '#GG0000', 'rgb(1,2,3)']) {
        expect(OrgIdentity.corDeHex(v), isNull, reason: '$v');
      }
    });

    test('lê a resposta de get_org_identity', () {
      final id = OrgIdentity.fromJson(const {
        'organization_id': 'org-1',
        'nome': 'Empresa Um',
        'logo_url': '  ',
        'cor_primaria': '#2E7D32',
        'cor_secundaria': null,
      });
      expect(id.nome, 'Empresa Um');
      expect(id.temLogo, isFalse, reason: 'texto em branco não é logo');
      expect(id.corPrimaria, const Color(0xFF2E7D32));
      expect(id.corSecundaria, isNull);
      expect(id.primariaEfetiva, const Color(0xFF2E7D32));
    });

    test('sem cor da empresa, vale a cor da marca', () {
      expect(OrgIdentity.vazia.primariaEfetiva, AppConstants.primary);
    });

    test('contraste segue a fórmula WCAG', () {
      expect(OrgIdentity.contraste(Colors.white, Colors.black),
          closeTo(21, 0.01));
      expect(OrgIdentity.contraste(Colors.white, Colors.white),
          closeTo(1, 0.01));
      expect(OrgIdentity.legivelComTexto(AppConstants.primary), isTrue);
    });
  });

  group('BrandTheme', () {
    test('sem identidade, o tema padrão é idêntico ao anterior', () {
      final t = BrandTheme.claro(AppThemeScheme.alinha, OrgIdentity.vazia);
      expect(t.colorScheme.primary, AppConstants.primary);
      expect(t.colorScheme.primaryContainer, const Color(0xFFA51412));
      expect(t.colorScheme.secondary, const Color(0xFF000000));
      final e = BrandTheme.escuro(AppThemeScheme.alinha, OrgIdentity.vazia);
      expect(e.colorScheme.primary, AppConstants.primary);
      expect(e.colorScheme.secondary, const Color(0xFFFFFFFF));
    });

    test('a cor da empresa vira a primária do tema, claro e escuro', () {
      const id = OrgIdentity(
          corPrimaria: Color(0xFF1565C0), corSecundaria: Color(0xFFFFB300));
      final t = BrandTheme.claro(AppThemeScheme.alinha, id);
      expect(t.colorScheme.primary, const Color(0xFF1565C0));
      expect(t.colorScheme.secondary, const Color(0xFFFFB300));
      expect(
          HSLColor.fromColor(t.colorScheme.primaryContainer).lightness,
          lessThan(HSLColor.fromColor(t.colorScheme.primary).lightness),
          reason: 'container é um tom mais escuro da primária');
      expect(BrandTheme.escuro(AppThemeScheme.alinha, id).colorScheme.primary,
          const Color(0xFF1565C0));
    });

    test('cor clara recebe texto escuro por cima', () {
      const id = OrgIdentity(corPrimaria: Color(0xFFFFEB3B));
      final t = BrandTheme.claro(AppThemeScheme.alinha, id);
      expect(ThemeData.estimateBrightnessForColor(t.colorScheme.onPrimary),
          Brightness.dark);
    });

    test('o esquema escolhido pelo usuário prevalece', () {
      const id = OrgIdentity(corPrimaria: Color(0xFF1565C0));
      expect(BrandTheme.claro(AppThemeScheme.whatsapp, id).colorScheme.primary,
          const Color(0xFF075E54));
    });
  });

  test('caminho do logo no bucket a partir da URL pública', () {
    expect(
        IdentidadeRepository.caminhoNoBucket(
            'https://x.supabase.co/storage/v1/object/public/org-logos/org-1/logo_1.webp?t=2'),
        'org-1/logo_1.webp');
    expect(IdentidadeRepository.caminhoNoBucket('https://cdn.cliente.com/logo.png'),
        isNull, reason: 'logo externo não é apagado');
    expect(IdentidadeRepository.caminhoNoBucket(null), isNull);
  });

  test('documentos legais exibem o nome da marca desta build', () {
    final provider = File('lib/features/legal/providers/legal_provider.dart')
        .readAsStringSync();
    expect(provider, contains(
        'replaceAll(AppConstants.nomeOriginalDoProduto, AppConstants.appName)'));
    // O texto aprovado continua escrito com o nome original.
    expect(File('docs/legal/01-termos-de-uso.md').readAsStringSync(),
        contains(AppConstants.nomeOriginalDoProduto));
  });

  group('A marca não volta a ficar presa no código', () {
    final telas = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();

    String semComentarios(File f) => f
        .readAsStringSync()
        .split('\n')
        .where((l) => !RegExp(r'^\s*//').hasMatch(l))
        .join('\n');

    test('telas usam a cor do tema, não a constante da marca', () {
      // A constante continua sendo a cor-base da build; quem desenha usa
      // `context.corMarca`, que reflete a cor da empresa.
      const permitidos = {
        'lib/core/constants.dart',
        'lib/core/brand/org_identity.dart',
        'lib/core/brand/brand_theme.dart',
        'lib/features/admin/ui/tabs/identidade_visual_tab.dart',
      };
      for (final f in telas) {
        if (permitidos.contains(f.path.replaceAll('\\', '/'))) continue;
        expect(semComentarios(f), isNot(contains('AppConstants.primary')),
            reason: f.path);
      }
    });

    test('nome do produto não aparece escrito direto na interface', () {
      // Exceção: o prefixo das salas do MiroTalk é identificador técnico —
      // mudá-lo separaria versões diferentes do app em salas diferentes.
      final literal = RegExp(r"""['"][^'"\n]*AlinhaJá(?!_)[^'"\n]*['"]""");
      for (final f in telas) {
        if (f.path.endsWith('lib/core/constants.dart')) continue;
        expect(literal.hasMatch(semComentarios(f)), isFalse, reason: f.path);
      }
    });
  });
}
