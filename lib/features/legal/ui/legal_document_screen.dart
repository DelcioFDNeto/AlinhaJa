import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../data/legal_documents.dart';
import '../models/legal_document_model.dart';
import '../providers/legal_provider.dart';
import 'widgets/legal_document_view.dart';

/// Leitor de um documento legal.
///
/// O texto vem de `docs/legal/*.md` via assets — a mesma fonte usada pelo site
/// público, para que app e site nunca divirjam. A renderização é a compartilhada
/// com o fluxo de aceite: é ela que sabe navegar os links entre documentos, que
/// numa cópia própria da folha de estilo viravam links mortos.
class LegalDocumentScreen extends ConsumerWidget {
  const LegalDocumentScreen({super.key, required this.documentId});

  /// Id do catálogo (`termos`, `privacidade`, …).
  final String documentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final doc = legalDocumentById(documentId);

    if (doc == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Documento')),
        body: const Center(child: Text('Documento não encontrado.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          doc.title,
          style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
        ),
        centerTitle: false,
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        scrolledUnderElevation: 2,
      ),
      body: LegalDocumentReadingPane(
        doc: doc,
        header: _AcceptanceBadge(doc: doc),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        onOpenDocument: (target) => context.push('/legal/${target.id}'),
      ),
    );
  }
}

/// Faixa com a versão do documento e, quando ele exige aceite, a data em que
/// este usuário o aceitou.
class _AcceptanceBadge extends ConsumerWidget {
  const _AcceptanceBadge({required this.doc});

  final LegalDocument doc;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    if (!doc.requiresAcceptance) {
      return _Chip(
        icon: Icons.description_outlined,
        label: 'Versão ${doc.version} · documento informativo',
        color: theme.colorScheme.outline,
      );
    }

    final acceptances = ref.watch(myAcceptancesProvider);

    return acceptances.when(
      loading: () => _Chip(
        icon: Icons.hourglass_empty_rounded,
        label: 'Versão ${doc.version}',
        color: theme.colorScheme.outline,
      ),
      error: (_, __) => _Chip(
        icon: Icons.description_outlined,
        label: 'Versão ${doc.version}',
        color: theme.colorScheme.outline,
      ),
      data: (list) {
        PolicyAcceptanceRecord? match;
        for (final a in list) {
          if (a.policyType == doc.policyType?.code &&
              a.policyVersion == doc.version) {
            match = a;
            break;
          }
        }

        if (match == null) {
          return _Chip(
            icon: Icons.info_outline_rounded,
            label: 'Versão ${doc.version} · aceite pendente',
            color: theme.colorScheme.error,
          );
        }

        final quando =
            DateFormat("dd/MM/yyyy 'às' HH:mm").format(match.acceptedAt);
        return _Chip(
          icon: Icons.verified_rounded,
          label: 'Versão ${doc.version} · aceito em $quando',
          color: Colors.green.shade700,
        );
      },
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
