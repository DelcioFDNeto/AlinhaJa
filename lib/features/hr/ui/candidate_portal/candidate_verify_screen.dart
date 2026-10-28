import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:alinha_ja/core/status_role.dart';
import 'package:alinha_ja/core/status_tokens.dart';
import 'package:alinha_ja/features/hr/services/candidate_auth_service.dart';

class CandidateVerifyScreen extends ConsumerStatefulWidget {
  final String? token;
  const CandidateVerifyScreen({super.key, this.token});

  @override
  ConsumerState<CandidateVerifyScreen> createState() => _CandidateVerifyScreenState();
}

class _CandidateVerifyScreenState extends ConsumerState<CandidateVerifyScreen> {
  bool _verified = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.token != null) {
      _verifyToken(widget.token!);
    }
  }

  Future<void> _verifyToken(String t) async {
    final success = await ref.read(candidateAuthProvider.notifier).verify(t);
    if (mounted) {
      setState(() {
        _verified = success;
        _error = ref.read(candidateAuthProvider).error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.token == null) {
      // Tela mostrando "E-mail enviado"
      return Scaffold(
        appBar: AppBar(title: const Text('Verificação de E-mail')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.mark_email_read,
                    size: 64,
                    color: context.statusTokens.color(StatusRole.success)),
                const SizedBox(height: 24),
                const Text(
                  'E-mail de verificação enviado!',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Acesse sua caixa de entrada e clique no link para ativar sua conta.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => context.go('/candidato/login'),
                  child: const Text('Ir para Login'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Verificação de Conta')),
      body: Center(
        child: _error != null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline,
                      size: 64, color: Theme.of(context).colorScheme.error),
                  const SizedBox(height: 16),
                  Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 18)),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () => context.go('/candidato/login'),
                    child: const Text('Voltar para Login'),
                  )
                ],
              )
            : _verified
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle,
                          size: 64,
                          color: context.statusTokens
                              .color(StatusRole.success)),
                      const SizedBox(height: 16),
                      const Text('Conta verificada com sucesso!', style: TextStyle(fontSize: 18)),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: () => context.go('/candidato/login'),
                        child: const Text('Fazer Login'),
                      )
                    ],
                  )
                : const CircularProgressIndicator(),
      ),
    );
  }
}
