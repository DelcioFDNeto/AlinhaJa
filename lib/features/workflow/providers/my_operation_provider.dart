import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alinha_ja/core/supabase_client.dart';
import 'package:alinha_ja/features/workflow/models/workflow_card_model.dart';
import 'package:alinha_ja/features/workflow/models/workflow_helpers.dart';

/// Um card atribuído ao usuário, com o workspace de origem junto.
///
/// O board carrega cards de um canal só. Aqui o eixo é a pessoa, então o nome
/// do workspace vira parte do resultado — sem ele a lista não diz de onde veio
/// cada item.
class MyCard {
  final WorkflowCard card;
  final String channelId;
  final String channelName;

  /// Etapa que encerra o card, resolvida no banco pela flag `is_final` ou
  /// `is_cancelled` da configuração daquele workspace.
  ///
  /// Precisa vir pronto: cada workspace tem a própria configuração de etapas,
  /// e carregar todas para decidir aqui seria uma consulta por canal.
  final bool isClosed;

  const MyCard({
    required this.card,
    required this.channelId,
    required this.channelName,
    required this.isClosed,
  });

  bool get isOverdueNow => !isClosed && isOverdue(card.dueDate);
}

/// Cards atribuídos ao usuário em TODOS os workspaces.
///
/// Existe porque o `workflowProvider` é indexado por canal: ele responde
/// "meus cards neste workspace", nunca "meus cards". Quem atua em cinco
/// workspaces precisava abrir cinco quadros para saber o que tinha na mão.
///
/// O escopo de acesso é da RLS: `workflow_cards` só devolve linha de canal em
/// que o usuário é membro. Não há filtro de membresia aqui de propósito —
/// duplicá-lo criaria uma segunda fonte de verdade para a regra de acesso.
final myOperationProvider = FutureProvider<List<MyCard>>((ref) async {
  final userId = supabase.auth.currentUser?.id;
  if (userId == null) return const [];

  final rows = await supabase
      .from('workflow_cards')
      .select(
          '*, channels!inner(id, name), assigned_user:users!assigned_to(full_name)')
      .eq('assigned_to', userId)
      .eq('is_archived', false)
      .order('due_date', ascending: true, nullsFirst: false);

  final list = (rows as List).cast<Map<String, dynamic>>();
  if (list.isEmpty) return const [];

  // Uma consulta resolve as etapas de encerramento de todos os workspaces
  // envolvidos, em vez de uma por canal.
  final channelIds = list
      .map((r) => r['channel_id']?.toString())
      .whereType<String>()
      .toSet()
      .toList();

  final closedByChannel = <String, Set<String>>{};
  if (channelIds.isNotEmpty) {
    final configs = await supabase
        .from('workflow_status_config')
        .select('channel_id, status, is_final, is_cancelled')
        .inFilter('channel_id', channelIds);

    for (final c in (configs as List).cast<Map<String, dynamic>>()) {
      final isClosing = c['is_final'] == true || c['is_cancelled'] == true;
      if (!isClosing) continue;
      final chId = c['channel_id'].toString();
      closedByChannel
          .putIfAbsent(chId, () => <String>{})
          .add(c['status'].toString().toLowerCase().trim());
    }
  }

  return list.map((row) {
    final channel = row['channels'] as Map<String, dynamic>?;
    final channelId = row['channel_id']?.toString() ?? '';
    final status = row['status']?.toString().toLowerCase().trim() ?? '';

    return MyCard(
      card: WorkflowCard.fromJson(row),
      channelId: channelId,
      channelName: channel?['name']?.toString() ?? 'Workspace',
      isClosed: closedByChannel[channelId]?.contains(status) ?? false,
    );
  }).toList();
});

/// Agrupamento por urgência, na ordem em que a lista deve aparecer.
enum OperationBucket { atrasados, hoje, proximos, semPrazo, concluidos }

extension OperationBucketLabel on OperationBucket {
  String get label => switch (this) {
        OperationBucket.atrasados => 'Em atraso',
        OperationBucket.hoje => 'Para hoje',
        OperationBucket.proximos => 'Próximos',
        OperationBucket.semPrazo => 'Sem prazo',
        OperationBucket.concluidos => 'Concluídos',
      };
}

/// Distribui os cards nos grupos da tela.
///
/// Função separada — e pura — para ser testável sem Supabase.
Map<OperationBucket, List<MyCard>> groupMyCards(List<MyCard> cards) {
  final out = <OperationBucket, List<MyCard>>{};

  for (final c in cards) {
    final OperationBucket bucket;
    if (c.isClosed) {
      bucket = OperationBucket.concluidos;
    } else if (c.card.dueDate == null) {
      bucket = OperationBucket.semPrazo;
    } else {
      final days = daysUntilDue(c.card.dueDate);
      bucket = days < 0
          ? OperationBucket.atrasados
          : (days == 0 ? OperationBucket.hoje : OperationBucket.proximos);
    }
    out.putIfAbsent(bucket, () => []).add(c);
  }

  return out;
}
