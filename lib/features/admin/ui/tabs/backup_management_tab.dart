import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:alinha_ja/core/database/drift_database.dart';
import 'package:alinha_ja/core/services/backup/backup_repository.dart';
import 'package:alinha_ja/core/services/media_cache_manager.dart';
import 'package:alinha_ja/features/backup/providers/backup_providers.dart';

/// Governança de backup — visão do administrador.
///
/// Esta aba **não dá acesso a conteúdo de backup**, e isso é desenho, não
/// limitação técnica: os arquivos são cifrados no aparelho do titular com
/// uma chave que o servidor nunca recebe. O acesso corporativo legítimo a
/// conversas existe e continua sendo a moderação auditada
/// (`admin_search_messages`), que exige justificativa por escrito e registra
/// cada consulta. Abrir uma segunda via silenciosa pelo backup esvaziaria
/// essa garantia.
///
/// O que o administrador faz aqui: define a política de retenção, acompanha
/// a cobertura (quem tem backup, de quantos aparelhos, há quanto tempo) e
/// gerencia o armazenamento local deste dispositivo.
class BackupManagementTab extends ConsumerStatefulWidget {
  const BackupManagementTab({super.key});

  @override
  ConsumerState<BackupManagementTab> createState() =>
      _BackupManagementTabState();
}

class _BackupManagementTabState extends ConsumerState<BackupManagementTab> {
  bool _isLoadingCache = true;
  bool _salvandoPolitica = false;
  Map<String, double> _cacheUsage = {};

  @override
  void initState() {
    super.initState();
    _loadCacheUsage();
  }

  Future<void> _loadCacheUsage() async {
    setState(() => _isLoadingCache = true);
    final usage = await MediaCacheManager.getCacheUsageMB();
    if (mounted) {
      setState(() {
        _cacheUsage = usage;
        _isLoadingCache = false;
      });
    }
  }

  void _aviso(String msg, {bool erro = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor:
            erro ? Theme.of(context).colorScheme.error : Colors.green,
      ),
    );
  }

  Future<void> _editarPolitica(Map<String, dynamic> politica) async {
    final dias = TextEditingController(
        text: '${(politica['retencao_dias'] as num?)?.toInt() ?? 90}');
    final maxDisp = TextEditingController(
        text: '${(politica['max_dispositivo'] as num?)?.toInt() ?? 5}');
    final teto = TextEditingController(
        text: '${(politica['teto_mb'] as num?)?.toInt() ?? 200}');

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Política de retenção de backup'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Prazo declarado precisa de rotina que o cumpra. O expurgo roda '
                'diariamente às 03:40 e o volume removido fica registrado na '
                'auditoria como evidência (LGPD, arts. 15 e 16).',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: dias,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Retenção (dias)',
                  helperText: 'De 7 a 365',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: maxDisp,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Backups mantidos por dispositivo',
                  helperText: 'De 1 a 30. Os mais antigos são podados.',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: teto,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Tamanho máximo por backup (MB)',
                  helperText: 'De 10 a 256. Limita o volume de mídias.',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    setState(() => _salvandoPolitica = true);
    try {
      await const BackupRepository().definirPolitica(
        dias: int.tryParse(dias.text) ?? 90,
        maxPorDispositivo: int.tryParse(maxDisp.text),
        tetoMb: int.tryParse(teto.text),
      );
      ref.invalidate(visaoAdminBackupProvider);
      _aviso('Política de backup atualizada.');
    } catch (e) {
      _aviso('$e', erro: true);
    } finally {
      if (mounted) setState(() => _salvandoPolitica = false);
    }
  }

  Future<void> _clearCache() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Limpar cache de mídia?'),
        content: const Text(
          'Isso apagará as imagens e vídeos salvos localmente neste '
          'dispositivo. Eles voltam a ser baixados quando acessados.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Limpar'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _isLoadingCache = true);
    try {
      final items = await driftDb.select(driftDb.mediaCache).get();
      if (!kIsWeb) {
        for (final item in items) {
          final path = item.localPath;
          if (path == null) continue;
          final file = File(path);
          if (await file.exists()) await file.delete();
        }
      }
      await driftDb.delete(driftDb.mediaCache).go();
      await _loadCacheUsage();
      _aviso('Cache limpo com sucesso.');
    } catch (e) {
      _aviso('Erro ao limpar cache: $e', erro: true);
    } finally {
      if (mounted) setState(() => _isLoadingCache = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visao = ref.watch(visaoAdminBackupProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(visaoAdminBackupProvider);
        await _loadCacheUsage();
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _cabecalho(theme),
          const SizedBox(height: 24),
          visao.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (e, _) => Text('Não foi possível carregar a visão: $e'),
            data: (dados) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _politica(theme,
                    Map<String, dynamic>.from(dados['politica'] as Map)),
                const SizedBox(height: 24),
                _totais(
                    theme, Map<String, dynamic>.from(dados['totais'] as Map)),
                const SizedBox(height: 24),
                _porTitular(theme, (dados['por_titular'] as List?) ?? const []),
              ],
            ),
          ),
          const Divider(height: 48),
          _armazenamentoLocal(theme),
        ],
      ),
    );
  }

  Widget _cabecalho(ThemeData theme) => Card(
        elevation: 0,
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.shield_outlined, color: theme.colorScheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('Governança de backup',
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Os backups são cifrados no aparelho de cada titular com uma chave '
                'que o servidor não recebe. Por isso esta aba mostra cobertura e '
                'volume, mas não permite abrir nenhum arquivo — nem por esta conta, '
                'nem por qualquer outra. Acesso a conteúdo de conversa continua '
                'sendo feito pela Moderação, com justificativa e registro.',
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      );

  Widget _politica(ThemeData theme, Map<String, dynamic> p) => Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Política de retenção',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                  ),
                  TextButton.icon(
                    onPressed:
                        _salvandoPolitica ? null : () => _editarPolitica(p),
                    icon: const Icon(Icons.edit, size: 18),
                    label: const Text('Alterar'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _linha('Backups expiram em',
                  '${(p['retencao_dias'] as num?)?.toInt() ?? 90} dias'),
              _linha('Mantidos por dispositivo',
                  '${(p['max_dispositivo'] as num?)?.toInt() ?? 5}'),
              _linha('Tamanho máximo por backup',
                  '${(p['teto_mb'] as num?)?.toInt() ?? 200} MB'),
              const SizedBox(height: 8),
              Text(
                'Expurgo automático diário às 03:40, com volume registrado na '
                'auditoria.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );

  Widget _totais(ThemeData theme, Map<String, dynamic> t) {
    final bytes = (t['bytes'] as num?)?.toDouble() ?? 0;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Cobertura da organização',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _linha('Titulares com backup', '${t['titulares'] ?? 0}'),
            _linha('Backups armazenados', '${t['snapshots'] ?? 0}'),
            _linha('Volume total',
                '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB'),
            _linha('Dispositivos com automático ativo', '${t['auto_ativo'] ?? 0}'),
          ],
        ),
      ),
    );
  }

  Widget _porTitular(ThemeData theme, List<dynamic> linhas) {
    if (linhas.isEmpty) {
      return Card(
        elevation: 0,
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        child: const Padding(
          padding: EdgeInsets.all(24),
          child: Center(
            child: Text('Nenhum titular fez backup ainda.',
                style: TextStyle(color: Colors.grey)),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Por titular',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        for (final raw in linhas)
          Builder(builder: (_) {
            final l = Map<String, dynamic>.from(raw as Map);
            final ultimo = DateTime.tryParse('${l['ultimo_backup']}');
            final mb =
                ((l['bytes'] as num?)?.toDouble() ?? 0) / (1024 * 1024);
            return Card(
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
              child: ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text('${l['usuario'] ?? 'Sem nome'}'),
                subtitle: Text(
                  '${l['snapshots'] ?? 0} backups • ${l['dispositivos'] ?? 0} '
                  'dispositivos • ${mb.toStringAsFixed(1)} MB',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: Text(
                  ultimo == null
                      ? '—'
                      : DateFormat('dd/MM/yy').format(ultimo.toLocal()),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _armazenamentoLocal(ThemeData theme) {
    final imagens = _cacheUsage['image'] ?? 0.0;
    final videos = _cacheUsage['video'] ?? 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Armazenamento local deste dispositivo',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(
          'Mídias baixadas são apagadas automaticamente após 90 dias sem acesso '
          'ou ao atingir os limites (imagens 500 MB, vídeos 1 GB). O histórico '
          'local de conversas é apagado ao sair da conta.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        if (_isLoadingCache)
          const Center(child: CircularProgressIndicator())
        else
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _linha('Imagens em cache', '${imagens.toStringAsFixed(2)} MB'),
                  _linha('Vídeos em cache', '${videos.toStringAsFixed(2)} MB'),
                  const Divider(height: 24),
                  _linha('Total utilizado',
                      '${(imagens + videos).toStringAsFixed(2)} MB',
                      destaque: true),
                ],
              ),
            ),
          ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _isLoadingCache ? null : _clearCache,
            icon: const Icon(Icons.delete_sweep_outlined, size: 18),
            label: const Text('Limpar cache manualmente'),
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
              side: BorderSide(color: theme.colorScheme.error),
            ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _linha(String rotulo, String valor, {bool destaque = false}) {
    final estilo = TextStyle(
      fontSize: destaque ? 16 : 14,
      fontWeight: destaque ? FontWeight.bold : FontWeight.w500,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(child: Text(rotulo, style: estilo)),
          Text(valor, style: estilo),
        ],
      ),
    );
  }
}
