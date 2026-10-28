import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:alinha_ja/features/hr/models/candidate_model.dart';
import 'package:alinha_ja/features/hr/services/candidate_auth_service.dart';
import 'package:alinha_ja/features/hr/ui/widgets/status_badge.dart';

class CandidateDashboardScreen extends ConsumerWidget {
  const CandidateDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(candidateAuthProvider);

    if (state.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (state.token == null || state.user == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.go('/candidato/login');
      });
      return const Scaffold();
    }

    final user = state.user!;
    final candidaturas = state.candidaturas ?? [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Minhas Candidaturas'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              ref.read(candidateAuthProvider.notifier).logout();
              context.go('/candidato/login');
            },
            tooltip: 'Sair',
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Olá, ${user['nome']}!', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(user['email'],
                style:
                    TextStyle(color: Theme.of(context).colorScheme.outline)),
            const SizedBox(height: 32),
            const Text('Acompanhe seus processos seletivos', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            if (candidaturas.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(48.0),
                  child: Text('Você ainda não tem candidaturas registradas.'),
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: candidaturas.length,
                itemBuilder: (context, index) {
                  final c = candidaturas[index];
                  final orgName = c['organizations']?['name'] ?? 'Empresa';
                  final status = (c['status'] as String?) ?? 'novo';
                  final token = c['portal_token'];
                  final data = c['created_at'] != null
                      ? DateTime.parse(c['created_at']).toLocal()
                      : null;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 16),
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(16),
                      title: Text(orgName, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(data != null
                          ? 'Enviado em ${DateFormat('dd/MM/yyyy').format(data)}'
                          : 'Candidatura registrada'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Labels/cores do funil padrão: fora do login da
                          // org, as etapas customizadas não são expostas.
                          StatusBadge(
                            label: CandidateStatus.label(status),
                            role: CandidateStatus.role(status),
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.arrow_forward_ios, size: 16),
                        ],
                      ),
                      onTap: () {
                        if (token != null) {
                          context.go('/candidato/$token');
                        }
                      },
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
