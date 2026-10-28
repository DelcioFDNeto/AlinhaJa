import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:alinha_ja/core/constants.dart';
import 'package:alinha_ja/features/legal/data/legal_documents.dart';

/// Peças visuais da tela de consentimento, sem acoplamento ao estado dela.
///
/// Ficam num arquivo próprio porque os dois layouts — painel duplo no desktop e
/// leitura em tela cheia no celular — montam as mesmas peças em ordens
/// diferentes. Duplicá-las seria a forma mais rápida de o texto do aceite
/// divergir entre plataformas.

class PolicyIntroHeader extends StatelessWidget {
  const PolicyIntroHeader({super.key, required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(Icons.privacy_tip_rounded,
              color: theme.colorScheme.primary, size: 28),
        ),
        const SizedBox(height: 16),
        Text(
          'Antes de continuar',
          style: GoogleFonts.outfit(
            fontSize: compact ? 24 : 22,
            fontWeight: FontWeight.w800,
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Para usar o ${AppConstants.appName} você precisa ler e aceitar os '
          'documentos abaixo. Eles explicam o que a plataforma faz com os seus '
          'dados e o que a empresa pode acessar.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}

class PolicyConsentNote extends StatelessWidget {
  const PolicyConsentNote({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded,
              size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Seu aceite é registrado com data, hora e a versão de cada '
              'documento. Consentimentos opcionais — como localização e foto '
              'de perfil — são pedidos à parte e podem ser recusados sem '
              'prejuízo.',
              style: theme.textTheme.bodySmall?.copyWith(height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

class PolicyAcceptanceFooter extends StatelessWidget {
  const PolicyAcceptanceFooter({
    super.key,
    required this.faltam,
    required this.canAccept,
    required this.saving,
    required this.onSubmit,
    required this.onSignOut,
  });

  final int faltam;
  final bool canAccept;
  final bool saving;
  final VoidCallback onSubmit;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (faltam > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                faltam == 1
                    ? 'Falta confirmar 1 documento.'
                    : 'Faltam confirmar $faltam documentos.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: theme.colorScheme.outline,
                ),
              ),
            ),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: (canAccept && !saving) ? onSubmit : null,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Aceitar e continuar',
                      style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: saving ? null : onSignOut,
            child: Text(
              'Não concordo — sair da conta',
              style: TextStyle(color: theme.colorScheme.outline),
            ),
          ),
        ],
      ),
    );
  }
}

/// Cartão de um documento na lista de aceite.
///
/// A caixa só habilita quando [opened] é verdadeiro: aceite às cegas não é
/// consentimento informado (Art. 8º, § 1º, da LGPD).
class PolicyDocumentTile extends StatelessWidget {
  const PolicyDocumentTile({
    super.key,
    required this.doc,
    required this.selected,
    required this.opened,
    required this.read,
    required this.checked,
    required this.onTap,
    required this.onChanged,
    this.showReadButton = false,
  });

  final LegalDocument doc;

  /// Exibido no painel direito (desktop).
  final bool selected;

  /// O texto já foi apresentado ao titular.
  final bool opened;

  /// A leitura chegou ao fim do documento — indicador, não trava.
  final bool read;

  final bool checked;
  final VoidCallback onTap;
  final ValueChanged<bool?> onChanged;

  /// No celular o cartão ganha botão "Ler"; no desktop o toque só seleciona.
  final bool showReadButton;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      key: ValueKey('policy-tile-${doc.id}'),
      decoration: BoxDecoration(
        color: selected
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.18)
            : null,
        border: Border.all(
          color: checked
              ? theme.colorScheme.primary.withValues(alpha: 0.5)
              : selected
                  ? theme.colorScheme.primary.withValues(alpha: 0.35)
                  : theme.colorScheme.outlineVariant,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          ListTile(
            onTap: onTap,
            leading: Icon(doc.icon, color: theme.colorScheme.primary),
            title: Text(doc.title,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(
              doc.summary,
              style:
                  TextStyle(color: theme.colorScheme.outline, fontSize: 12.5),
            ),
            trailing: showReadButton
                ? TextButton(
                    onPressed: onTap,
                    child: Text(opened ? 'Reler' : 'Ler'),
                  )
                : read
                    ? Icon(Icons.done_all_rounded,
                        size: 18, color: Colors.green.shade600)
                    : const Icon(Icons.chevron_right_rounded, size: 20),
          ),
          Divider(height: 1, color: theme.colorScheme.outlineVariant),
          CheckboxListTile(
            key: ValueKey('policy-check-${doc.id}'),
            value: checked,
            onChanged: opened ? onChanged : null,
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
            title: Text(
              opened
                  ? 'Li e concordo com este documento (v${doc.version})'
                  : showReadButton
                      ? 'Toque em "Ler" para habilitar'
                      : 'Abra o documento para habilitar',
              style: TextStyle(
                fontSize: 13,
                color: opened
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.outline,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
