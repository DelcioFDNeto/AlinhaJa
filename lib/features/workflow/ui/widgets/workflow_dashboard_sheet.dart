import 'package:flutter/material.dart';
import 'package:alinha_ja/core/supabase_client.dart';
import 'package:alinha_ja/features/workflow/models/workflow_helpers.dart';
import 'package:alinha_ja/features/workflow/models/workflow_supporting_models.dart';

class WorkflowDashboardSheet extends StatefulWidget {
  final String channelId;

  const WorkflowDashboardSheet({super.key, required this.channelId});

  @override
  State<WorkflowDashboardSheet> createState() => _WorkflowDashboardSheetState();
}

class _WorkflowDashboardSheetState extends State<WorkflowDashboardSheet> {
  bool _isLoading = true;
  Map<String, dynamic>? _metrics;
  int _myCards = 0;
  int _slaExceeded = 0;

  @override
  void initState() {
    super.initState();
    _fetchMetrics();
  }

  Future<void> _fetchMetrics() async {
    try {
      final response = await supabase.rpc(
        'get_workflow_metrics',
        params: {'p_channel_id': widget.channelId},
      );
      final cardsResponse = await supabase
          .from('workflow_cards')
          .select('requested_by, assigned_to, priority, status, updated_at')
          .eq('channel_id', widget.channelId)
          .eq('is_archived', false);
      final statusResponse = await supabase
          .from('workflow_status_config')
          .select('status, is_final, is_cancelled')
          .eq('channel_id', widget.channelId);

      final currentUserId = supabase.auth.currentUser?.id;
      final finalStatuses = (statusResponse as List)
          .where((s) => s['is_final'] == true || s['is_final'] == 'true')
          .map((s) => s['status']?.toString())
          .whereType<String>()
          .toSet();
      // Etapa de cancelamento é configurável: sai do SLA por flag, com
      // fallback pelo nome legado para canais anteriores à migration.
      final cancelledStatuses = statusResponse
          .where((s) =>
              s['is_cancelled'] == true ||
              s['is_cancelled'] == 'true' ||
              WorkflowStatusConfig.legacyCancelledNames
                  .contains((s['status']?.toString() ?? '').toLowerCase()))
          .map((s) => s['status']?.toString())
          .whereType<String>()
          .toSet();
      final cards = cardsResponse as List;
      final myCards = currentUserId == null
          ? 0
          : cards
              .where((c) =>
                  c['requested_by']?.toString() == currentUserId ||
                  c['assigned_to']?.toString() == currentUserId)
              .length;
      final slaExceeded = cards.where((c) {
        final status = c['status']?.toString() ?? '';
        if (cancelledStatuses.contains(status) ||
            finalStatuses.contains(status)) {
          return false;
        }
        final updatedAt = DateTime.tryParse(c['updated_at']?.toString() ?? '');
        if (updatedAt == null) return false;
        return isSlaExceeded(updatedAt, c['priority']?.toString() ?? 'medium');
      }).length;

      if (mounted) {
        setState(() {
          _metrics =
              response is Map ? Map<String, dynamic>.from(response) : null;
          _myCards = myCards;
          _slaExceeded = slaExceeded;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao carregar métricas: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              border: Border(
                  bottom: BorderSide(
                      color: theme.colorScheme.outlineVariant
                          .withValues(alpha: 0.2))),
            ),
            child: Row(
              children: [
                Icon(Icons.dashboard_outlined,
                    color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Text('Dashboard de Métricas',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context)),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _metrics == null
                    ? const Center(child: Text('Nenhuma métrica encontrada'))
                    : _buildDashboard(theme),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboard(ThemeData theme) {
    final totalCards = _metrics!['total_cards'] ?? 0;
    final amountValue = _metrics!['total_amount'];
    final totalAmount = amountValue is num
        ? amountValue.toDouble()
        : double.tryParse(amountValue?.toString() ?? '') ?? 0.0;
    final byStatusRaw = _metrics!['by_status'];
    final byStatus = byStatusRaw is Map
        ? Map<String, dynamic>.from(byStatusRaw)
        : <String, dynamic>{};

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            Expanded(
                child: _buildStatCard(
                    theme, 'Total de Cards', '$totalCards', Icons.style)),
            const SizedBox(width: 12),
            Expanded(
                child: _buildStatCard(
                    theme,
                    'Valor Total',
                    'R\$ ${totalAmount.toStringAsFixed(2)}',
                    Icons.attach_money)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
                child: _buildStatCard(theme, 'Meus Cards', '$_myCards',
                    Icons.person_pin_circle_outlined,
                    color: Colors.blue)),
            const SizedBox(width: 12),
            Expanded(
                child: _buildStatCard(theme, 'SLA Estourado', '$_slaExceeded',
                    Icons.timer_off_outlined,
                    color: Colors.red)),
          ],
        ),
        const SizedBox(height: 24),
        Text('Por Status',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        ...byStatus.entries.map((e) {
          return ListTile(
            title: Text(e.key.toUpperCase()),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text('${e.value}',
                  style: TextStyle(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.bold)),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildStatCard(
      ThemeData theme, String title, String value, IconData icon,
      {Color? color}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color ?? theme.colorScheme.primary, size: 24),
          const SizedBox(height: 12),
          Text(title,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline)),
          const SizedBox(height: 4),
          Text(value,
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}
