import 'package:flutter/material.dart';

import 'package:alinha_ja/core/services/backup/backup_crypto.dart';

/// Pede a senha do backup.
///
/// Em [confirmar] a senha é digitada duas vezes e vem acompanhada do aviso
/// de irrecuperabilidade. Não é formalidade: como a chave nunca sai do
/// aparelho, ninguém — nem o suporte, nem o administrador — consegue abrir
/// o arquivo depois. O titular precisa saber disso antes de escolher, não
/// no dia em que tentar restaurar.
class BackupPasswordDialog extends StatefulWidget {
  final String titulo;
  final String descricao;
  final bool confirmar;

  const BackupPasswordDialog({
    super.key,
    required this.titulo,
    required this.descricao,
    this.confirmar = false,
  });

  /// Devolve a senha digitada, ou `null` se o titular cancelar.
  static Future<String?> mostrar(
    BuildContext context, {
    required String titulo,
    required String descricao,
    bool confirmar = false,
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) => BackupPasswordDialog(
        titulo: titulo,
        descricao: descricao,
        confirmar: confirmar,
      ),
    );
  }

  @override
  State<BackupPasswordDialog> createState() => _BackupPasswordDialogState();
}

class _BackupPasswordDialogState extends State<BackupPasswordDialog> {
  final _senha = TextEditingController();
  final _repetir = TextEditingController();
  bool _oculta = true;
  bool _cienteDoRisco = false;
  String? _erro;

  @override
  void dispose() {
    _senha.dispose();
    _repetir.dispose();
    super.dispose();
  }

  void _confirmar() {
    final senha = _senha.text;

    if (widget.confirmar) {
      final problema = BackupCrypto.validarSenha(senha);
      if (problema != null) {
        setState(() => _erro = problema);
        return;
      }
      if (senha != _repetir.text) {
        setState(() => _erro = 'As senhas não conferem.');
        return;
      }
      if (!_cienteDoRisco) {
        setState(() => _erro = 'Confirme que entendeu o aviso acima.');
        return;
      }
    } else if (senha.isEmpty) {
      setState(() => _erro = 'Digite a senha do backup.');
      return;
    }

    Navigator.of(context).pop(senha);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(widget.titulo),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.descricao, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 16),
            TextField(
              controller: _senha,
              obscureText: _oculta,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Senha do backup',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_oculta ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _oculta = !_oculta),
                ),
              ),
            ),
            if (widget.confirmar) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _repetir,
                obscureText: _oculta,
                decoration: const InputDecoration(
                  labelText: 'Repita a senha',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Mínimo de 12 caracteres, com letras, números e ao menos um símbolo.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: theme.colorScheme.error.withValues(alpha: 0.4)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.key_off_outlined,
                        color: theme.colorScheme.error, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'O backup é cifrado neste aparelho. A senha não é enviada '
                        'ao servidor e não pode ser redefinida: se você esquecê-la, '
                        'nem a empresa nem o suporte conseguem abrir o arquivo.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
              CheckboxListTile(
                value: _cienteDoRisco,
                onChanged: (v) => setState(() => _cienteDoRisco = v ?? false),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text(
                  'Entendi que, sem a senha, o backup é irrecuperável.',
                  style: TextStyle(fontSize: 13),
                ),
              ),
            ],
            if (_erro != null) ...[
              const SizedBox(height: 8),
              Text(_erro!, style: TextStyle(color: theme.colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _confirmar,
          child: Text(widget.confirmar ? 'Definir e continuar' : 'Confirmar'),
        ),
      ],
    );
  }
}
