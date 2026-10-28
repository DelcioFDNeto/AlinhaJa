import 'package:flutter/material.dart';

import 'package:alinha_ja/core/services/backup/backup_models.dart';
import 'package:alinha_ja/features/backup/ui/backup_screen.dart' show formatarData;

/// Explica, antes de qualquer botão, o que o backup protege e o que não
/// protege. Sem isso o titular escolhe uma senha sem saber que ela é a
/// única chave existente.
class BackupCabecalhoSeguranca extends StatelessWidget {
  const BackupCabecalhoSeguranca({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
            color: theme.colorScheme.primary.withValues(alpha: 0.25)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.lock_outline, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Cifrado neste aparelho',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Seus backups são cifrados com AES-256 antes de sair do dispositivo, '
              'com uma chave derivada de uma senha que só você conhece. O servidor '
              'guarda apenas bytes ilegíveis — nem a empresa, nem o administrador, '
              'nem o suporte conseguem abri-los.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// Card de criação: escopo, mídias e as três saídas (nuvem, arquivo,
/// restaurar de arquivo).
class BackupNovoCard extends StatelessWidget {
  final BackupEscopo escopo;
  final bool incluirMidias;
  final bool ocupado;
  final int mensagensLocais;
  final ValueChanged<BackupEscopo> onEscopo;
  final ValueChanged<bool> onMidias;
  final VoidCallback onBackup;
  final VoidCallback onExportar;
  final VoidCallback onRestaurarArquivo;

  const BackupNovoCard({
    super.key,
    required this.escopo,
    required this.incluirMidias,
    required this.ocupado,
    required this.mensagensLocais,
    required this.onEscopo,
    required this.onMidias,
    required this.onBackup,
    required this.onExportar,
    required this.onRestaurarArquivo,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
            Text('Novo backup',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            SegmentedButton<BackupEscopo>(
              segments: const [
                ButtonSegment(
                  value: BackupEscopo.conta,
                  icon: Icon(Icons.cloud_outlined),
                  label: Text('Conta'),
                ),
                ButtonSegment(
                  value: BackupEscopo.dispositivo,
                  icon: Icon(Icons.phone_android),
                  label: Text('Dispositivo'),
                ),
              ],
              selected: {escopo},
              onSelectionChanged:
                  ocupado ? null : (s) => onEscopo(s.first),
            ),
            const SizedBox(height: 10),
            Text(
              escopo == BackupEscopo.conta
                  ? 'Busca no servidor tudo que é seu: mensagens, cadastro, '
                      'consentimentos e histórico. Independe do que está em '
                      'cache aqui.'
                  : 'Empacota apenas o histórico já guardado neste aparelho '
                      '($mensagensLocais mensagens). Rápido e sem consumo de '
                      'rede além do envio.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            SwitchListTile(
              value: incluirMidias,
              onChanged: ocupado ? null : onMidias,
              contentPadding: EdgeInsets.zero,
              title: const Text('Incluir imagens, áudios e vídeos'),
              subtitle: const Text(
                'Aumenta bastante o tamanho. O que passar do limite da '
                'organização fica de fora e é informado ao final.',
                style: TextStyle(fontSize: 12),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: ocupado ? null : onBackup,
                icon: const Icon(Icons.cloud_upload_outlined),
                label: const Text('Fazer backup na nuvem'),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: ocupado ? null : onExportar,
                    icon: const Icon(Icons.save_alt, size: 18),
                    label: const Text('Salvar .fxb'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: ocupado ? null : onRestaurarArquivo,
                    icon: const Icon(Icons.folder_open, size: 18),
                    label: const Text('Abrir .fxb'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Opt-in do backup automático deste aparelho.
class BackupAutomaticoCard extends StatelessWidget {
  final BackupDevice? dispositivo;
  final bool disponivel;
  final bool carregando;
  final void Function(BackupDevice atual, bool ativo)? onAlternar;

  const BackupAutomaticoCard({
    super.key,
    required this.dispositivo,
    required this.disponivel,
    required this.carregando,
    required this.onAlternar,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final d = dispositivo;

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
            Text('Backup automático',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              'Uma vez por dia, apenas em Wi-Fi. Desligado por padrão: nada é '
              'enviado sem que você ative.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            if (carregando)
              const LinearProgressIndicator()
            else if (!disponivel)
              const _Aviso(
                icone: Icons.public_off,
                texto:
                    'Indisponível no navegador: não há cofre seguro para guardar '
                    'a senha. Use o aplicativo instalado ou faça backups manuais.',
              )
            else if (d == null)
              const _Aviso(
                icone: Icons.error_outline,
                texto: 'Não foi possível identificar este dispositivo.',
              )
            else
              SwitchListTile(
                value: d.autoBackup,
                onChanged: onAlternar == null
                    ? null
                    : (v) => onAlternar!(d, v),
                contentPadding: EdgeInsets.zero,
                title: Text(d.nome),
                subtitle: Text(
                  d.ultimoBackup == null
                      ? 'Nenhum backup enviado deste aparelho ainda.'
                      : 'Último backup: ${formatarData(d.ultimoBackup)}',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Aviso extends StatelessWidget {
  final IconData icone;
  final String texto;
  const _Aviso({required this.icone, required this.texto});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icone, size: 18, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(child: Text(texto, style: theme.textTheme.bodySmall)),
      ],
    );
  }
}

/// Uma linha do histórico de backups na nuvem.
class BackupSnapshotTile extends StatelessWidget {
  final BackupSnapshot snapshot;
  final String nomeDispositivo;
  final VoidCallback? onRestaurar;
  final VoidCallback? onExcluir;

  const BackupSnapshotTile({
    super.key,
    required this.snapshot,
    required this.nomeDispositivo,
    required this.onRestaurar,
    required this.onExcluir,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = snapshot;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  s.escopo == BackupEscopo.conta
                      ? Icons.cloud_done_outlined
                      : Icons.phone_android,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    formatarData(s.concluidoEm ?? s.criadoEm),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                if (s.origem == 'automatico')
                  const Chip(
                    label: Text('Automático', style: TextStyle(fontSize: 11)),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${s.escopo.rotulo} • $nomeDispositivo • ${s.tamanhoLegivel}',
              style: theme.textTheme.bodySmall,
            ),
            Text(
              '${s.mensagens} mensagens, ${s.midias} mídias'
              '${s.midiasIgnoradas > 0 ? " (${s.midiasIgnoradas} fora do limite)" : ""}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            Text(
              'Expira em ${s.diasParaExpirar} dias',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: onRestaurar,
                  icon: const Icon(Icons.restore, size: 18),
                  label: const Text('Restaurar'),
                ),
                IconButton(
                  tooltip: 'Excluir',
                  onPressed: onExcluir,
                  icon: Icon(Icons.delete_outline,
                      color: theme.colorScheme.error),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class BackupDispositivoTile extends StatelessWidget {
  final BackupDevice dispositivo;
  final bool ehAtual;
  final VoidCallback? onRevogar;

  const BackupDispositivoTile({
    super.key,
    required this.dispositivo,
    required this.ehAtual,
    required this.onRevogar,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final d = dispositivo;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: ListTile(
        leading: Icon(_icone(d.plataforma)),
        title: Row(
          children: [
            Flexible(child: Text(d.nome, overflow: TextOverflow.ellipsis)),
            if (ehAtual) ...[
              const SizedBox(width: 8),
              Chip(
                label: const Text('Este', style: TextStyle(fontSize: 11)),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                backgroundColor:
                    theme.colorScheme.primaryContainer.withValues(alpha: 0.6),
              ),
            ],
          ],
        ),
        subtitle: Text(
          d.ultimoBackup == null
              ? 'Sem backups'
              : 'Último backup: ${formatarData(d.ultimoBackup)}',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: IconButton(
          tooltip: 'Revogar e apagar backups deste aparelho',
          onPressed: onRevogar,
          icon: Icon(Icons.link_off, color: theme.colorScheme.error),
        ),
      ),
    );
  }

  IconData _icone(String plataforma) => switch (plataforma) {
        'android' || 'ios' => Icons.smartphone,
        'web' => Icons.language,
        'windows' || 'macos' || 'linux' => Icons.desktop_windows_outlined,
        _ => Icons.devices_other,
      };
}

class BackupVazio extends StatelessWidget {
  const BackupVazio({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      child: const Padding(
        padding: EdgeInsets.all(24),
        child: Center(
          child: Text(
            'Nenhum backup na nuvem ainda.',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      ),
    );
  }
}
