import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:alinha_ja/core/services/backup/backup_models.dart';
import 'package:alinha_ja/core/services/backup_service.dart';
import 'package:alinha_ja/features/backup/providers/backup_providers.dart';
import 'package:alinha_ja/features/backup/ui/widgets/backup_password_dialog.dart';
import 'package:alinha_ja/features/backup/ui/widgets/backup_sections.dart';

/// Tela de backup do titular.
///
/// Backup é direito e responsabilidade da pessoa, não função administrativa:
/// por isso vive aqui, junto da Central de Privacidade, e não no painel de
/// administração. O administrador acompanha cobertura e política na aba
/// "Backup" do painel — sem nunca alcançar o conteúdo.
class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  BackupEscopo _escopo = BackupEscopo.conta;
  bool _incluirMidias = true;
  String? _etapa;

  bool get _ocupado => _etapa != null;

  void _progresso(String? etapa) {
    if (mounted) setState(() => _etapa = etapa);
  }

  void _aviso(String msg, {bool erro = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: erro ? Theme.of(context).colorScheme.error : Colors.green,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  // ── Ações ────────────────────────────────────────────────

  Future<void> _fazerBackup() async {
    final senha = await BackupPasswordDialog.mostrar(
      context,
      titulo: 'Senha do backup',
      descricao:
          'Escolha a senha que protegerá este backup. Ela é usada para cifrar '
          'o arquivo aqui no aparelho, antes do envio.',
      confirmar: true,
    );
    if (senha == null) return;

    _progresso('Preparando...');
    try {
      final r = await BackupService.criarBackupNaNuvem(
        senha: senha,
        escopo: _escopo,
        incluirMidias: _incluirMidias,
        onProgresso: _progresso,
      );
      final ignoradas = r.midiasIgnoradas > 0
          ? ' (${r.midiasIgnoradas} mídias não couberam no limite)'
          : '';
      _aviso('Backup concluído: ${r.mensagens} mensagens, '
          '${r.midias} mídias$ignoradas.');
      recarregarBackup(ref);
    } catch (e) {
      _aviso('$e', erro: true);
    } finally {
      _progresso(null);
    }
  }

  Future<void> _restaurar(BackupSnapshot snap) async {
    final senha = await BackupPasswordDialog.mostrar(
      context,
      titulo: 'Restaurar backup',
      descricao:
          'Digite a senha usada quando este backup foi criado. As mensagens '
          'voltam para o histórico local deste aparelho.',
    );
    if (senha == null) return;

    _progresso('Preparando...');
    try {
      final total = await BackupService.restaurarDaNuvem(
        snapshot: snap,
        senha: senha,
        onProgresso: _progresso,
      );
      _aviso('$total mensagens restauradas neste dispositivo.');
      recarregarBackup(ref);
    } catch (e) {
      _aviso('$e', erro: true);
    } finally {
      _progresso(null);
    }
  }

  Future<void> _excluir(BackupSnapshot snap) async {
    final ok = await _confirmar(
      titulo: 'Excluir este backup?',
      mensagem:
          'O arquivo é apagado da nuvem imediatamente e não há como desfazer. '
          'A exclusão fica registrada na auditoria.',
      acao: 'Excluir',
    );
    if (!ok) return;

    try {
      await BackupService.excluirBackup(snap.id);
      _aviso('Backup excluído.');
      recarregarBackup(ref);
    } catch (e) {
      _aviso('$e', erro: true);
    }
  }

  Future<void> _revogarDispositivo(BackupDevice d) async {
    final ok = await _confirmar(
      titulo: 'Revogar "${d.nome}"?',
      mensagem:
          'Todos os backups gerados por esse aparelho serão apagados da nuvem. '
          'Use isto se o dispositivo foi perdido, roubado ou não é mais seu.',
      acao: 'Revogar e apagar',
    );
    if (!ok) return;

    try {
      await BackupService.revogarDispositivo(d.id);
      _aviso('Dispositivo revogado e backups apagados.');
      recarregarBackup(ref);
    } catch (e) {
      _aviso('$e', erro: true);
    }
  }

  Future<void> _alternarAutomatico(BackupDevice atual, bool ativo) async {
    String? senha;
    if (ativo) {
      senha = await BackupPasswordDialog.mostrar(
        context,
        titulo: 'Ativar backup automático',
        descricao:
            'Para rodar sozinho, o aplicativo precisa guardar a senha no cofre '
            'seguro deste aparelho (Keychain no iOS, Keystore no Android). Ela '
            'continua sem sair do dispositivo e é apagada ao sair da conta ou '
            'ao desligar o automático.',
        confirmar: true,
      );
      if (senha == null) return;
    }

    try {
      await BackupService.definirBackupAutomatico(atual.id, ativo, senha: senha);
      _aviso(ativo
          ? 'Backup automático ativado: diário, apenas em Wi-Fi.'
          : 'Backup automático desativado e senha removida do cofre.');
      recarregarBackup(ref);
    } catch (e) {
      _aviso('$e', erro: true);
    }
  }

  Future<void> _exportarArquivo() async {
    final senha = await BackupPasswordDialog.mostrar(
      context,
      titulo: 'Exportar para arquivo',
      descricao:
          'O arquivo .fxb sai daqui já cifrado. Guarde-o com o mesmo cuidado '
          'que daria a um documento com dados pessoais.',
      confirmar: true,
    );
    if (senha == null) return;

    _progresso('Preparando...');
    try {
      final destino = await BackupService.exportarParaArquivo(
        senha: senha,
        escopo: _escopo,
        incluirMidias: _incluirMidias,
        onProgresso: _progresso,
      );
      _aviso('Arquivo gerado: $destino');
    } catch (e) {
      _aviso('$e', erro: true);
    } finally {
      _progresso(null);
    }
  }

  Future<void> _restaurarDeArquivo() async {
    final escolha = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );
    final bytes = escolha?.files.singleOrNull?.bytes;
    if (bytes == null) return;

    if (!mounted) return;
    final senha = await BackupPasswordDialog.mostrar(
      context,
      titulo: 'Restaurar de arquivo',
      descricao: 'Digite a senha usada na criação deste arquivo .fxb.',
    );
    if (senha == null) return;

    _progresso('Preparando...');
    try {
      final total = await BackupService.restaurarDeArquivo(
        arquivo: bytes,
        senha: senha,
        onProgresso: _progresso,
      );
      _aviso('$total mensagens restauradas neste dispositivo.');
      recarregarBackup(ref);
    } catch (e) {
      _aviso('$e', erro: true);
    } finally {
      _progresso(null);
    }
  }

  Future<bool> _confirmar({
    required String titulo,
    required String mensagem,
    required String acao,
  }) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titulo),
        content: Text(mensagem),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(acao),
          ),
        ],
      ),
    );
    return res ?? false;
  }

  // ── UI ───────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final backups = ref.watch(meusBackupsProvider);
    final dispositivos = ref.watch(meusDispositivosProvider);
    final atual = ref.watch(dispositivoAtualProvider);
    final espelho = ref.watch(espelhoLocalProvider);
    final autoDisponivel = ref.watch(backupAutomaticoDisponivelProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Backup e Restauração'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _ocupado ? null : () => recarregarBackup(ref),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const BackupCabecalhoSeguranca(),
          const SizedBox(height: 20),
          if (_etapa != null) ...[
            Card(
              color: theme.colorScheme.primaryContainer,
              child: ListTile(
                leading: const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                title: Text(_etapa!),
                subtitle: const Text('Não feche o aplicativo.'),
              ),
            ),
            const SizedBox(height: 20),
          ],
          BackupNovoCard(
            escopo: _escopo,
            incluirMidias: _incluirMidias,
            ocupado: _ocupado,
            mensagensLocais: espelho.valueOrNull ?? 0,
            onEscopo: (v) => setState(() => _escopo = v),
            onMidias: (v) => setState(() => _incluirMidias = v),
            onBackup: _fazerBackup,
            onExportar: _exportarArquivo,
            onRestaurarArquivo: _restaurarDeArquivo,
          ),
          const SizedBox(height: 24),
          BackupAutomaticoCard(
            dispositivo: atual.valueOrNull,
            disponivel: autoDisponivel,
            carregando: atual.isLoading,
            onAlternar: _ocupado ? null : _alternarAutomatico,
          ),
          const SizedBox(height: 24),
          Text('Backups na nuvem',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          backups.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Text('Não foi possível carregar: $e'),
            data: (lista) => lista.isEmpty
                ? const BackupVazio()
                : Column(
                    children: [
                      for (final s in lista)
                        BackupSnapshotTile(
                          snapshot: s,
                          nomeDispositivo: _nomeDoDispositivo(
                              dispositivos.valueOrNull, s.deviceId),
                          onRestaurar: _ocupado ? null : () => _restaurar(s),
                          onExcluir: _ocupado ? null : () => _excluir(s),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 24),
          Text('Meus dispositivos',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          dispositivos.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text('Não foi possível carregar: $e'),
            data: (lista) => Column(
              children: [
                for (final d in lista.where((d) => d.ativo))
                  BackupDispositivoTile(
                    dispositivo: d,
                    ehAtual: d.id == atual.valueOrNull?.id,
                    onRevogar: _ocupado ? null : () => _revogarDispositivo(d),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          Text(
            'Backups expiram conforme a Política de Retenção e Descarte da sua '
            'organização e são apagados automaticamente. Criação, restauração e '
            'exclusão ficam registradas na auditoria (LGPD, art. 37).',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  String _nomeDoDispositivo(List<BackupDevice>? lista, String? id) {
    if (lista == null || id == null) return 'Dispositivo removido';
    for (final d in lista) {
      if (d.id == id) return d.nome;
    }
    return 'Dispositivo removido';
  }
}

/// Formatação compartilhada entre a tela e os cartões.
String formatarData(DateTime? d) =>
    d == null ? '—' : DateFormat('dd/MM/yyyy HH:mm').format(d);
