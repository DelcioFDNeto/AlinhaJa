import 'package:flutter/material.dart';

import 'package:alinha_ja/core/models/message_extras.dart';

/// Enquete pronta para virar mensagem.
class PollDraft {
  final String question;
  final List<String> options;
  final bool multipleChoice;

  const PollDraft({
    required this.question,
    required this.options,
    this.multipleChoice = false,
  });

  Map<String, dynamic> get metadata => MessageExtras.poll(
        options: options,
        multipleChoice: multipleChoice,
      );
}

/// Criação de enquete — usada por qualquer conversa que aceite a ação.
class CreatePollSheet extends StatefulWidget {
  const CreatePollSheet({super.key});

  static Future<PollDraft?> show(BuildContext context) {
    return showModalBottomSheet<PollDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const CreatePollSheet(),
    );
  }

  @override
  State<CreatePollSheet> createState() => _CreatePollSheetState();
}

class _CreatePollSheetState extends State<CreatePollSheet> {
  static const int _maxOptions = 10;

  final _questionCtrl = TextEditingController();
  final List<TextEditingController> _optionsCtrls = [
    TextEditingController(),
    TextEditingController(),
  ];
  bool _multipleChoice = false;

  @override
  void dispose() {
    _questionCtrl.dispose();
    for (final c in _optionsCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  void _addOption() {
    if (_optionsCtrls.length >= _maxOptions) return;
    setState(() => _optionsCtrls.add(TextEditingController()));
  }

  void _removeOption(int index) {
    if (_optionsCtrls.length <= 2) return;
    setState(() {
      _optionsCtrls[index].dispose();
      _optionsCtrls.removeAt(index);
    });
  }

  void _submit() {
    final question = _questionCtrl.text.trim();
    if (question.isEmpty) {
      _warn('Por favor, insira a pergunta da enquete.', Colors.red);
      return;
    }

    final options = _optionsCtrls
        .map((c) => c.text.trim())
        .where((text) => text.isNotEmpty)
        .toList();

    if (options.length < 2) {
      _warn('Uma enquete precisa de pelo menos 2 opções válidas.',
          Colors.orange);
      return;
    }
    if (options.toSet().length != options.length) {
      _warn('Há opções repetidas na enquete.', Colors.orange);
      return;
    }

    Navigator.of(context).pop(PollDraft(
      question: question,
      options: options,
      multipleChoice: _multipleChoice,
    ));
  }

  void _warn(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.poll_rounded,
                      color: theme.colorScheme.primary, size: 26),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Criar enquete',
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _questionCtrl,
                textCapitalization: TextCapitalization.sentences,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Pergunta da enquete',
                  hintText: 'Ex: Qual será o tema da próxima reunião?',
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Opções',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              for (var index = 0; index < _optionsCtrls.length; index++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _optionsCtrls[index],
                          textCapitalization: TextCapitalization.sentences,
                          decoration: InputDecoration(
                            hintText: 'Opção ${index + 1}',
                            filled: true,
                            fillColor: theme.colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.3),
                            isDense: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      if (_optionsCtrls.length > 2)
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline,
                              color: Colors.red),
                          tooltip: 'Remover opção',
                          onPressed: () => _removeOption(index),
                        ),
                    ],
                  ),
                ),
              if (_optionsCtrls.length < _maxOptions)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _addOption,
                    icon: const Icon(Icons.add),
                    label: const Text('Adicionar outra opção'),
                  ),
                ),
              SwitchListTile(
                value: _multipleChoice,
                onChanged: (v) => setState(() => _multipleChoice = v),
                contentPadding: EdgeInsets.zero,
                title: const Text('Permitir múltiplas respostas'),
                subtitle: const Text('Cada pessoa pode marcar mais de uma opção',
                    style: TextStyle(fontSize: 12)),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _submit,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Publicar enquete',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
