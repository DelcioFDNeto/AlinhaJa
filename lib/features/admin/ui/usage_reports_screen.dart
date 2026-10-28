import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:alinha_ja/core/supabase_client.dart';
import 'package:alinha_ja/core/utils/permissions.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Provider para métricas de uso do app
final usageMetricsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final userId = supabase.auth.currentUser?.id;
  if (userId == null) return {};

  final userData = await supabase
      .from('users')
      .select('role_level')
      .eq('id', userId)
      .maybeSingle();

  if (userData == null) {
    return {};
  }

  final roleLevel = userData['role_level'] as String?;
  if (!AppPermissions.canViewReports(roleLevel)) {
    return {};
  }

  // Contagens por HEAD (`count()`): só o número, sem baixar linhas. Antes
  // cada métrica baixava todos os ids e media a lista — lento, e cortado no
  // limite de linhas do PostgREST (1000): o mês nunca passava de 1000
  // mensagens. Fronteiras em horário local, enviadas em UTC.
  final now = DateTime.now();
  final inicioMes = DateTime(now.year, now.month, 1).toUtc().toIso8601String();

  final contagens = await Future.wait<int>([
    supabase.from('users').count().eq('is_active', true),
    supabase.from('messages').count().gte('created_at', inicioMes),
    // Mensagens de canais ficam em outra tabela e não entravam no total.
    supabase.from('channel_messages').count().gte('created_at', inicioMes),
    supabase.from('chats').count(),
    // Canais vivem em `channels` — contar `chats` do tipo canal dava ~0.
    supabase.from('channels').count(),
    supabase.from('calls').count().gte('created_at', inicioMes),
  ]);

  // Usuários online agora
  final onlineUsers = await supabase
      .from('users')
      .select('id, full_name, email, avatar_url')
      .eq('is_online', true) as List<dynamic>;

  return {
    'total_users': contagens[0],
    'messages_this_month': contagens[1] + contagens[2],
    'online_now': onlineUsers.length,
    'online_users_list': onlineUsers,
    'total_chats': contagens[3],
    'total_channels': contagens[4],
    'calls_this_month': contagens[5],
  };
});

/// Provider para atividade por dia (últimos 7 dias)
///
/// Uma contagem por dia (conversas + canais), em paralelo: baixar o
/// `created_at` de cada mensagem da semana era pesado e parava em 1000.
final dailyActivityProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final hoje = DateTime.now();
  final dias = [
    for (var i = 6; i >= 0; i--)
      DateTime(hoje.year, hoje.month, hoje.day).subtract(Duration(days: i)),
  ];

  Future<int> contarDia(DateTime dia) async {
    final de = dia.toUtc().toIso8601String();
    final ate = dia.add(const Duration(days: 1)).toUtc().toIso8601String();
    final porTabela = await Future.wait<int>([
      for (final tabela in ['messages', 'channel_messages'])
        supabase
            .from(tabela)
            .count()
            .gte('created_at', de)
            .lt('created_at', ate),
    ]);
    return porTabela.fold<int>(0, (a, b) => a + b);
  }

  final totais = await Future.wait(dias.map(contarDia));
  return [
    for (var i = 0; i < dias.length; i++)
      {
        'date': '${dias[i].year}-${dias[i].month.toString().padLeft(2, '0')}-'
            '${dias[i].day.toString().padLeft(2, '0')}',
        'messages': totais[i],
      },
  ];
});

/// Tela de relatórios de uso para admins
class UsageReportsScreen extends ConsumerWidget {
  const UsageReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metricsAsync = ref.watch(usageMetricsProvider);
    final dailyAsync = ref.watch(dailyActivityProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Relatórios de Uso'),
        centerTitle: false,
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(usageMetricsProvider);
          ref.invalidate(dailyActivityProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Cards de métricas
            metricsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('Erro: $e'),
              data: (metrics) => _buildMetricsCards(context, metrics, theme),
            ),

            const SizedBox(height: 24),

            // Gráfico de atividade diária
            Text(
              'Mensagens por dia (últimos 7 dias)',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            dailyAsync.when(
              loading: () => const SizedBox(
                height: 200,
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Text('Erro: $e'),
              data: (daily) => _buildActivityChart(context, daily, theme),
            ),
          ],
        ),
      ),
    );
  }

  void _showOnlineUsers(BuildContext context, List<dynamic> users) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Usuários Online',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              if (users.isEmpty)
                const Text('Nenhum usuário online no momento.')
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: users.length,
                    itemBuilder: (context, index) {
                      final user = users[index];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundImage: user['avatar_url'] != null ? CachedNetworkImageProvider(user['avatar_url'], maxWidth: 320) : null,
                          child: user['avatar_url'] == null ? const Icon(Icons.person) : null,
                        ),
                        title: Text(user['full_name'] ?? 'Usuário'),
                        subtitle: Text(user['email'] ?? ''),
                        trailing: const Icon(Icons.circle, color: Colors.green, size: 12),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMetricsCards(
      BuildContext context, Map<String, dynamic> metrics, ThemeData theme) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
                child: _MetricCard(
              title: 'Usuários Ativos',
              value: metrics['total_users']?.toString() ?? '0',
              icon: Icons.people,
              color: Colors.blue,
              theme: theme,
            )),
            const SizedBox(width: 12),
            Expanded(
                child: _MetricCard(
              title: 'Online Agora',
              value: metrics['online_now']?.toString() ?? '0',
              icon: Icons.circle,
              color: Colors.green,
              theme: theme,
              onTap: () => _showOnlineUsers(context, metrics['online_users_list'] as List<dynamic>? ?? []),
            )),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
                child: _MetricCard(
              title: 'Mensagens (Mês)',
              value: metrics['messages_this_month']?.toString() ?? '0',
              icon: Icons.message,
              color: Colors.purple,
              theme: theme,
            )),
            const SizedBox(width: 12),
            Expanded(
                child: _MetricCard(
              title: 'Chamadas (Mês)',
              value: metrics['calls_this_month']?.toString() ?? '0',
              icon: Icons.call,
              color: Colors.orange,
              theme: theme,
            )),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
                child: _MetricCard(
              title: 'Total de Chats',
              value: metrics['total_chats']?.toString() ?? '0',
              icon: Icons.chat,
              color: Colors.teal,
              theme: theme,
            )),
            const SizedBox(width: 12),
            Expanded(
                child: _MetricCard(
              title: 'Canais',
              value: metrics['total_channels']?.toString() ?? '0',
              icon: Icons.campaign,
              color: Colors.indigo,
              theme: theme,
            )),
          ],
        ),
      ],
    );
  }

  Widget _buildActivityChart(
      BuildContext context, List<Map<String, dynamic>> daily, ThemeData theme) {
    final maxMessages = daily.fold<int>(
        1, (max, d) => d['messages'] > max ? d['messages'] as int : max);

    return Container(
      height: 200,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: daily.map((d) {
          final messages = d['messages'] as int;
          final height = (messages / maxMessages) * 120;
          final date = d['date'] as String;
          final day = date.split('-')[2];

          return Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                messages.toString(),
                style:
                    const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Container(
                width: 32,
                height: height.clamp(4.0, 120.0),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                day,
                style:
                    TextStyle(fontSize: 11, color: theme.colorScheme.outline),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final ThemeData theme;
  final VoidCallback? onTap;

  const _MetricCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    required this.theme,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 8),
              Text(
                title,
                style:
                    TextStyle(fontSize: 12, color: theme.colorScheme.outline),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
          ),
            ],
          ),
        ),
      ),
    );
  }
}
