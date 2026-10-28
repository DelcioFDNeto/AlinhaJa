import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:alinha_ja/features/hr/services/candidate_auth_service.dart';

class CandidateSignupScreen extends ConsumerStatefulWidget {
  const CandidateSignupScreen({super.key});

  @override
  ConsumerState<CandidateSignupScreen> createState() => _CandidateSignupScreenState();
}

class _CandidateSignupScreenState extends ConsumerState<CandidateSignupScreen> {
  final _nomeCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  String? _localError;

  void _signup() async {
    final nome = _nomeCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text;
    setState(() => _localError = null);
    if (nome.length < 3) {
      setState(() => _localError = 'Informe seu nome completo.');
      return;
    }
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      setState(() => _localError = 'Informe um e-mail válido.');
      return;
    }
    if (pass.length < 6) {
      setState(() => _localError = 'A senha deve ter pelo menos 6 caracteres.');
      return;
    }

    final success = await ref.read(candidateAuthProvider.notifier).signup(nome, email, pass);
    if (success && mounted) {
      context.go('/candidato/verify-sent');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(candidateAuthProvider);
    final theme = Theme.of(context);
    final error = _localError ?? state.error;

    return Scaffold(
      appBar: AppBar(title: const Text('Cadastro de Candidato')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Criar Conta', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                  const SizedBox(height: 24),
                  if (error != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(error,
                          style: TextStyle(color: theme.colorScheme.error)),
                    ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _nomeCtrl,
                    decoration: const InputDecoration(labelText: 'Nome Completo', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _emailCtrl,
                    decoration: const InputDecoration(labelText: 'E-mail', border: OutlineInputBorder()),
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _passCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Senha',
                      border: OutlineInputBorder(),
                      helperText: 'Mínimo de 6 caracteres.',
                    ),
                    obscureText: true,
                    onSubmitted: (_) => _signup(),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: state.isLoading ? null : _signup,
                    child: state.isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Cadastrar'),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => context.go('/candidato/login'),
                    child: const Text('Já tem conta? Entre aqui'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
