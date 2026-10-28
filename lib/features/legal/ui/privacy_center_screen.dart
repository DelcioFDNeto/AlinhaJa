import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:alinha_ja/core/web_download_helper.dart';
import '../data/legal_documents.dart';
import '../providers/legal_provider.dart';
import 'legal_document_screen.dart';

class PrivacyCenterScreen extends ConsumerStatefulWidget {
  const PrivacyCenterScreen({super.key});

  @override
  ConsumerState<PrivacyCenterScreen> createState() => _PrivacyCenterScreenState();
}

class _PrivacyCenterScreenState extends ConsumerState<PrivacyCenterScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _handleExportData() async {
    setState(() => _exporting = true);
    try {
      final repo = ref.read(legalRepositoryProvider);
      final data = await repo.exportMyData();

      final jsonStr = const JsonEncoder.withIndent('  ').convert(data);

      final dateStr = DateFormat('yyyy-MM-dd_HHmm').format(DateTime.now());
      final fileName = 'meus_dados_lgpd_$dateStr.json';

      final destino = await _saveExport(jsonStr, fileName);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(destino),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao exportar dados: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// Grava a exportação e devolve a mensagem do destino.
  ///
  /// No navegador o download é disparado por data URI; no APK isso é no-op —
  /// e anunciar "exportado com sucesso" sem gerar arquivo seria negar na
  /// prática o direito de acesso (Art. 18, II e V). Em nativo o arquivo vai
  /// para o diretório de documentos do app.
  Future<String> _saveExport(String jsonStr, String fileName) async {
    if (kIsWeb) {
      final dataUri =
          'data:application/json;charset=utf-8,${Uri.encodeComponent(jsonStr)}';
      triggerFileDownload(dataUri, fileName);
      return 'Download iniciado pelo navegador: $fileName';
    }

    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsString(jsonStr);
    return 'Arquivo salvo em ${file.path}';
  }

  void _showNewRequestDialog() {
    final tipoController = ValueNotifier<String>('eliminacao');
    final descController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => ValueListenableBuilder<String>(
        valueListenable: tipoController,
        builder: (context, tipoValue, _) {
          return AlertDialog(
            title: const Text('Novo Pedido do Titular (LGPD)'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Selecione o tipo de pedido que deseja abrir formalmente perante o DPO/RH:',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: tipoValue,
                    decoration: const InputDecoration(
                      labelText: 'Tipo de Solicitação',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'eliminacao',
                        child: Text('Eliminação de Dados (Art. 18, VI)'),
                      ),
                      DropdownMenuItem(
                        value: 'correcao',
                        child: Text('Correção de Dados (Art. 18, III)'),
                      ),
                      DropdownMenuItem(
                        value: 'informacao',
                        child: Text('Informação / Compartilhamento (Art. 18, VIII)'),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) tipoController.value = val;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: descController,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Detalhes ou justificativa do pedido',
                      hintText: 'Descreva quais dados ou situação deseja solicitar...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () async {
                  final desc = descController.text.trim();
                  final messenger = ScaffoldMessenger.of(ctx);
                  if (desc.isEmpty) {
                    messenger.showSnackBar(
                      const SnackBar(content: Text('Descreva o pedido antes de enviar.')),
                    );
                    return;
                  }
                  Navigator.of(ctx).pop();

                  try {
                    final repo = ref.read(legalRepositoryProvider);
                    await repo.createTitularRequest(tipo: tipoValue, descricao: desc);
                    ref.invalidate(myTitularRequestsProvider);

                    if (mounted) {
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text('Pedido aberto com sucesso. Prazo legal de resposta: até 15 dias.'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      messenger.showSnackBar(
                        SnackBar(content: Text('Erro ao abrir pedido: $e'), backgroundColor: Colors.red),
                      );
                    }
                  }
                },
                child: const Text('Enviar Pedido'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _openDocument(LegalDocument doc) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LegalDocumentScreen(documentId: doc.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Central de Privacidade e Dados'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.description_outlined), text: 'Documentos'),
            Tab(icon: Icon(Icons.download_outlined), text: 'Meus Dados'),
            Tab(icon: Icon(Icons.assignment_turned_in_outlined), text: 'Meus Aceites'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildDocumentsTab(theme),
          _buildMyDataTab(theme),
          _buildMyAcceptancesTab(theme),
        ],
      ),
    );
  }

  Widget _buildDocumentsTab(ThemeData theme) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: kLegalDocuments.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final doc = kLegalDocuments[index];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: doc.requiresAcceptance
                ? theme.colorScheme.primaryContainer
                : theme.colorScheme.surfaceContainerHighest,
            child: Icon(
              doc.icon,
              color: doc.requiresAcceptance
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
              size: 20,
            ),
          ),
          title: Text(
            doc.title,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text('Versão ${doc.version} • ${doc.requiresAcceptance ? "Aceite obrigatório" : "Informativo"}'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _openDocument(doc),
        );
      },
    );
  }

  Widget _buildMyDataTab(ThemeData theme) {
    final requestsAsync = ref.watch(myTitularRequestsProvider);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          elevation: 0,
          color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: theme.colorScheme.primary.withValues(alpha: 0.3)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.download_for_offline, color: theme.colorScheme.primary, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Portabilidade e Acesso (LGPD Art. 18)',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Baixe uma cópia completa e estruturada (JSON) de todos os seus dados pessoais, mensagens enviadas, histórico de localização e consentimentos gravados no servidor.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _exporting ? null : _handleExportData,
                    icon: _exporting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.file_download),
                    label: Text(_exporting ? 'Gerando arquivo JSON...' : 'Exportar meus dados agora'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        // A exportação acima atende ao direito de acesso; o backup é outra
        // coisa: cópia cifrada, sob senha do titular, que ele restaura por
        // conta própria. Ficam lado a lado porque quem procura uma costuma
        // estar procurando a outra.
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
          child: ListTile(
            leading: Icon(Icons.cloud_sync_outlined,
                color: theme.colorScheme.primary),
            title: const Text('Backup e Restauração',
                style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text(
              'Cópia cifrada das suas mensagens na nuvem, por conta e por '
              'dispositivo. Só você tem a chave.',
              style: TextStyle(fontSize: 12),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/backup'),
          ),
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Pedidos do Titular (Art. 18)',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            IconButton.filledTonal(
              onPressed: _showNewRequestDialog,
              icon: const Icon(Icons.add),
              tooltip: 'Novo Pedido',
            ),
          ],
        ),
        const SizedBox(height: 8),
        requestsAsync.when(
          data: (requests) {
            if (requests.isEmpty) {
              return Card(
                elevation: 0,
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                child: const Padding(
                  padding: EdgeInsets.all(20.0),
                  child: Center(
                    child: Text(
                      'Você ainda não possui solicitações formais registradas.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                ),
              );
            }
            return Column(
              children: requests.map((req) {
                final dateStr = DateFormat('dd/MM/yyyy HH:mm').format(req.createdAt);
                return Card(
                  elevation: 0,
                  margin: const EdgeInsets.only(bottom: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(color: theme.colorScheme.outlineVariant),
                  ),
                  child: ListTile(
                    title: Text(
                      'Pedido de ${_mapTipo(req.tipo)}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (req.descricao != null && req.descricao!.isNotEmpty)
                          Text('Descrição: ${req.descricao}', maxLines: 2, overflow: TextOverflow.ellipsis),
                        Text('Aberto em: $dateStr • Status: ${req.status.toUpperCase()}',
                            style: const TextStyle(fontSize: 11, color: Colors.grey)),
                        if (req.resposta != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'Resposta DPO: ${req.resposta}',
                              style: TextStyle(fontSize: 12, color: theme.colorScheme.primary, fontWeight: FontWeight.bold),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Text('Erro ao carregar solicitações: $err'),
        ),
      ],
    );
  }

  Widget _buildMyAcceptancesTab(ThemeData theme) {
    final acceptancesAsync = ref.watch(myAcceptancesProvider);

    return acceptancesAsync.when(
      data: (records) {
        if (records.isEmpty) {
          return const Center(
            child: Text('Nenhum registro de aceite de política encontrado para esta conta.'),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: records.length,
          itemBuilder: (context, index) {
            final item = records[index];
            final doc = legalDocumentByPolicyCode(item.policyType);
            final title = doc?.title ?? item.policyType;
            final dateStr = DateFormat('dd/MM/yyyy - HH:mm:ss').format(item.acceptedAt);

            return Card(
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
              child: ListTile(
                leading: const Icon(Icons.verified, color: Colors.green),
                title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('Versão ${item.policyVersion} • Registrado em $dateStr'),
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(child: Text('Erro ao carregar histórico: $err')),
    );
  }

  String _mapTipo(String tipo) {
    switch (tipo) {
      case 'eliminacao':
        return 'Eliminação de Dados';
      case 'correcao':
        return 'Correção de Cadastro';
      case 'informacao':
        return 'Informação / Compartilhamento';
      default:
        return tipo;
    }
  }
}
