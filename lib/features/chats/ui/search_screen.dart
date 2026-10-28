import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:alinha_ja/core/supabase_client.dart';
import 'package:alinha_ja/core/extensions.dart';
import 'package:alinha_ja/core/ui/widgets/responsive_width_container.dart';

/// Tela de Busca Global.
///
/// Cobre quatro fontes, que moram em tabelas diferentes: `messages` (DMs e
/// grupos, mais os chats legados do tipo 'channel'), `channel_messages`
/// (workspaces atuais) e `workflow_cards` (conteúdo operacional). O comentário
/// antigo aqui afirmava que canal também vivia em `messages` — não vive, e por
/// isso a busca ficou anos sem retornar nada de workspace, silenciosamente.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _ctrl = TextEditingController();
  Timer? _debounce;

  List<Map<String, dynamic>> _chatResults = [];
  List<Map<String, dynamic>> _channelResults = [];

  /// Mensagens de workspace. Vivem em `channel_messages` — tabela distinta de
  /// `messages`, que é o que [_channelResults] cobre (chats do tipo 'channel',
  /// o conceito legado). Enquanto esta lista não existiu, todo o conteúdo dos
  /// canais atuais era invisível para a busca, sem aviso nenhum.
  List<Map<String, dynamic>> _workspaceResults = [];

  /// Cards de workflow: o conteúdo operacional propriamente dito.
  List<Map<String, dynamic>> _cardResults = [];
  bool _isLoading = false;
  String _lastQuery = '';

  // Filtros avançados
  String _contentTypeFilter = 'all'; // all, text, image, file
  String _dateFilter = 'all'; // all, today, week, month
  bool _myMessagesOnly = false;

  @override
  void dispose() {
    _ctrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onQueryChanged(String query) {
    _debounce?.cancel();
    if (query.trim().length < 2) {
      setState(() {
        _chatResults = [];
        _channelResults = [];
        _workspaceResults = [];
        _cardResults = [];
        _lastQuery = '';
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _search(query.trim());
    });
  }

  /// Busca em `channel_messages` e `workflow_cards`.
  ///
  /// Não filtra por membresia: a RLS dessas duas tabelas já exige que o
  /// usuário seja membro do canal. Reimplementar o escopo aqui seria uma
  /// segunda fonte de verdade para a regra de acesso — e a que sai de sincro.
  ///
  /// Falha isolada de propósito: se a busca operacional quebrar, a busca de
  /// conversas continua respondendo em vez de a tela inteira cair no fallback.
  Future<void> _searchWorkspaces(String query) async {
    try {
      final msgs = await supabase
          .from('channel_messages')
          .select(
              'id, content, content_type, created_at, channel_id, sender_id, channels!inner(id, name)')
          .ilike('content', '%$query%')
          .order('created_at', ascending: false)
          .limit(20);

      final rows = (msgs as List).cast<Map<String, dynamic>>();

      // `channel_messages.sender_id` referencia auth.users, então não há
      // embed possível para o perfil. Uma consulta em lote resolve todos os
      // remetentes de uma vez — mesmo padrão do ActiveChannelNotifier.
      final senderIds =
          rows.map((r) => r['sender_id']?.toString()).whereType<String>().toSet();

      var byId = <String, Map<String, dynamic>>{};
      if (senderIds.isNotEmpty) {
        final users = await supabase
            .from('users')
            .select('id, full_name, avatar_url')
            .inFilter('id', senderIds.toList());
        byId = {
          for (final u in (users as List).cast<Map<String, dynamic>>())
            u['id'].toString(): u
        };
      }

      for (final r in rows) {
        r['sender'] = byId[r['sender_id']?.toString()];
        // _ResultTile lê 'user_id' para o filtro "só minhas mensagens".
        r['user_id'] = r['sender_id'];
      }

      if (mounted) setState(() => _workspaceResults = rows);
    } catch (e) {
      if (mounted) setState(() => _workspaceResults = []);
    }

    try {
      final cards = await supabase
          .from('workflow_cards')
          .select(
              'id, title, description, status, channel_id, created_at, due_date, is_archived')
          .or('title.ilike.%$query%,description.ilike.%$query%')
          .eq('is_archived', false)
          .order('created_at', ascending: false)
          .limit(20);

      if (mounted) {
        setState(() =>
            _cardResults = (cards as List).cast<Map<String, dynamic>>());
      }
    } catch (e) {
      if (mounted) setState(() => _cardResults = []);
    }
  }

  Future<void> _search(String query) async {
    if (query == _lastQuery) return;
    _lastQuery = query;
    setState(() => _isLoading = true);

    // Dispara junto com a busca de conversas; cada uma atualiza sua seção
    // quando responde.
    unawaited(_searchWorkspaces(query));

    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      // Busca unificada: mensagens de DMs, Grupos e Canais estão todas na tabela 'messages'
      final chatResults = await supabase
          .from('messages')
          .select(
              'id, content, content_type, created_at, chat_id, user_id, sender:users!messages_user_id_fkey(id, full_name, avatar_url), chats!inner(id, name, type, chat_members!inner(user_id))')
          .ilike('content', '%$query%')
          .eq('chats.chat_members.user_id', userId)
          .isFilter('deleted_at', null)
          .order('created_at', ascending: false)
          .limit(50);

      var allResults = (chatResults as List).cast<Map<String, dynamic>>();

      // Separar em conversas normais e canais
      var normalResults = allResults.where((m) {
        final chat = m['chats'] as Map<String, dynamic>?;
        return chat?['type'] != 'channel';
      }).toList();
      var channelResultsList = allResults.where((m) {
        final chat = m['chats'] as Map<String, dynamic>?;
        return chat?['type'] == 'channel';
      }).toList();

      // Aplicar filtros em memória
      if (_contentTypeFilter != 'all') {
        normalResults = normalResults
            .where((m) => m['content_type'] == _contentTypeFilter)
            .toList();
        channelResultsList = channelResultsList
            .where((m) => m['content_type'] == _contentTypeFilter)
            .toList();
      }

      // Filtrar por data
      final now = DateTime.now();
      DateTime? startDate;
      if (_dateFilter == 'today') {
        startDate = DateTime(now.year, now.month, now.day);
      } else if (_dateFilter == 'week') {
        startDate = now.subtract(const Duration(days: 7));
      } else if (_dateFilter == 'month') {
        startDate = DateTime(now.year, now.month - 1, now.day);
      }

      if (startDate != null) {
        normalResults = normalResults.where((m) {
          final date = DateTime.tryParse(m['created_at'] as String? ?? '');
          return date != null && date.isAfter(startDate!);
        }).toList();
        channelResultsList = channelResultsList.where((m) {
          final date = DateTime.tryParse(m['created_at'] as String? ?? '');
          return date != null && date.isAfter(startDate!);
        }).toList();
      }

      if (_myMessagesOnly) {
        normalResults =
            normalResults.where((m) => m['user_id'] == userId).toList();
        channelResultsList =
            channelResultsList.where((m) => m['user_id'] == userId).toList();
      }

      if (!mounted) return;
      setState(() {
        _chatResults = normalResults.take(20).toList();
        _channelResults = channelResultsList.take(20).toList();
        _isLoading = false;
      });
    } catch (e) {
      // Fallback simplificado
      try {
        final simpleChat = await supabase
            .from('messages')
            .select(
                'id, content, content_type, created_at, chat_id, user_id, sender:users!messages_user_id_fkey(id, full_name, avatar_url)')
            .ilike('content', '%$query%')
            .isFilter('deleted_at', null)
            .order('created_at', ascending: false)
            .limit(20);

        if (!mounted) return;
        setState(() {
          _chatResults = (simpleChat as List).cast<Map<String, dynamic>>();
          _channelResults = [];
          _isLoading = false;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _chatResults = [];
          _channelResults = [];
          _isLoading = false;
        });
      }
    }
  }

  void _showFilterSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Filtros de Busca',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    TextButton(
                      onPressed: () {
                        setModalState(() {
                          _contentTypeFilter = 'all';
                          _dateFilter = 'all';
                          _myMessagesOnly = false;
                        });
                      },
                      child: const Text('Limpar'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text('Tipo de conteúdo',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('Todos'),
                      selected: _contentTypeFilter == 'all',
                      onSelected: (selected) =>
                          setModalState(() => _contentTypeFilter = 'all'),
                    ),
                    ChoiceChip(
                      label: const Text('Texto'),
                      selected: _contentTypeFilter == 'text',
                      onSelected: (selected) =>
                          setModalState(() => _contentTypeFilter = 'text'),
                    ),
                    ChoiceChip(
                      label: const Text('Imagens'),
                      selected: _contentTypeFilter == 'image',
                      onSelected: (selected) =>
                          setModalState(() => _contentTypeFilter = 'image'),
                    ),
                    ChoiceChip(
                      label: const Text('Arquivos'),
                      selected: _contentTypeFilter == 'file',
                      onSelected: (selected) =>
                          setModalState(() => _contentTypeFilter = 'file'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text('Período',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('Todos'),
                      selected: _dateFilter == 'all',
                      onSelected: (selected) =>
                          setModalState(() => _dateFilter = 'all'),
                    ),
                    ChoiceChip(
                      label: const Text('Hoje'),
                      selected: _dateFilter == 'today',
                      onSelected: (selected) =>
                          setModalState(() => _dateFilter = 'today'),
                    ),
                    ChoiceChip(
                      label: const Text('Esta semana'),
                      selected: _dateFilter == 'week',
                      onSelected: (selected) =>
                          setModalState(() => _dateFilter = 'week'),
                    ),
                    ChoiceChip(
                      label: const Text('Este mês'),
                      selected: _dateFilter == 'month',
                      onSelected: (selected) =>
                          setModalState(() => _dateFilter = 'month'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text('Apenas minhas mensagens'),
                  value: _myMessagesOnly,
                  onChanged: (value) =>
                      setModalState(() => _myMessagesOnly = value),
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      setState(() {}); // Rebuild to apply filters
                      if (_lastQuery.isNotEmpty) _search(_lastQuery);
                    },
                    child: const Text('Aplicar Filtros'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasResults = _chatResults.isNotEmpty ||
        _channelResults.isNotEmpty ||
        _workspaceResults.isNotEmpty ||
        _cardResults.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        scrolledUnderElevation: 2,
        title: TextField(
          controller: _ctrl,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Buscar mensagens...',
            hintStyle: TextStyle(color: theme.colorScheme.outline),
            border: InputBorder.none,
            filled: false,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
          ),
          textInputAction: TextInputAction.search,
          onChanged: _onQueryChanged,
          onSubmitted: (v) => _search(v.trim()),
        ),
        actions: [
          if (_ctrl.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                _ctrl.clear();
                setState(() {
                  _chatResults = [];
                  _channelResults = [];
                  _workspaceResults = [];
                  _cardResults = [];
                  _lastQuery = '';
                });
              },
            ),
          IconButton(
            icon: const Icon(Icons.tune),
            onPressed: () => _showFilterSheet(context),
          ),
        ],
      ),
      body: ResponsiveWidthContainer(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : !hasResults
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.search_rounded,
                            size: 64,
                            color: theme.colorScheme.outline
                                .withValues(alpha: 0.4)),
                        const SizedBox(height: 16),
                        Text(
                          _lastQuery.isEmpty
                              ? 'Digite para buscar em todas as conversas e canais'
                              : 'Nenhum resultado para "$_lastQuery"',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: theme.colorScheme.outline, fontSize: 15),
                        ),
                      ],
                    ),
                  )
                : ListView(
                    children: [
                      // ── Seção: Resultados em Conversas ──
                      if (_chatResults.isNotEmpty) ...[
                        _SectionTitle(
                          icon: Icons.chat_bubble_outline_rounded,
                          title:
                              'Resultados em Conversas (${_chatResults.length})',
                          theme: theme,
                        ),
                        ..._chatResults.map((r) => _ResultTile(
                              result: r,
                              source: 'chat',
                              query: _lastQuery,
                              theme: theme,
                              onTap: () {
                                final chatId = r['chat_id'] as String;
                                final chats =
                                    r['chats'] as Map<String, dynamic>?;
                                final chatName =
                                    chats?['name'] as String? ?? 'Chat';
                                context.push('/chat/$chatId',
                                    extra: {'name': chatName});
                              },
                            )),
                      ],

                      // ── Seção: Resultados em Workspaces ──
                      if (_workspaceResults.isNotEmpty) ...[
                        _SectionTitle(
                          icon: Icons.workspaces_rounded,
                          title:
                              'Resultados em Workspaces (${_workspaceResults.length})',
                          theme: theme,
                        ),
                        ..._workspaceResults.map((r) => _ResultTile(
                              result: r,
                              source: 'channel',
                              query: _lastQuery,
                              theme: theme,
                              onTap: () {
                                final channelId = r['channel_id'] as String;
                                final channel =
                                    r['channels'] as Map<String, dynamic>?;
                                final channelName =
                                    channel?['name'] as String? ?? 'Workspace';
                                context.push('/channel/$channelId',
                                    extra: {'channelName': channelName});
                              },
                            )),
                      ],

                      // ── Seção: Cards de workflow ──
                      if (_cardResults.isNotEmpty) ...[
                        _SectionTitle(
                          icon: Icons.assignment_outlined,
                          title: 'Cards (${_cardResults.length})',
                          theme: theme,
                        ),
                        ..._cardResults.map((r) => _CardResultTile(
                              card: r,
                              query: _lastQuery,
                              theme: theme,
                              onTap: () {
                                final channelId = r['channel_id'] as String;
                                context.push('/channel/$channelId',
                                    extra: {'channelName': 'Workspace'});
                              },
                            )),
                      ],

                      // ── Seção: Resultados em Canais ──
                      if (_channelResults.isNotEmpty) ...[
                        _SectionTitle(
                          icon: Icons.campaign_rounded,
                          title:
                              'Resultados em Canais (${_channelResults.length})',
                          theme: theme,
                        ),
                        ..._channelResults.map((r) => _ResultTile(
                              result: r,
                              source: 'channel',
                              query: _lastQuery,
                              theme: theme,
                              onTap: () {
                                final chatId = r['chat_id'] as String;
                                final chats =
                                    r['chats'] as Map<String, dynamic>?;
                                final channelName =
                                    chats?['name'] as String? ?? 'Canal';
                                context.push('/channel/$chatId',
                                    extra: {'channelName': channelName});
                              },
                            )),
                      ],
                    ],
                  ),
      ),
    );
  }
}

// ── Cabeçalho de Seção ──────────────────────────
/// Resultado de card. Tem forma própria em vez de reaproveitar [_ResultTile]:
/// card não tem remetente nem hora de envio — o que identifica é o título, a
/// etapa e o prazo.
class _CardResultTile extends StatelessWidget {
  final Map<String, dynamic> card;
  final String query;
  final ThemeData theme;
  final VoidCallback onTap;

  const _CardResultTile({
    required this.card,
    required this.query,
    required this.theme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final title = card['title']?.toString() ?? 'Card sem título';
    final description = card['description']?.toString() ?? '';
    final status = card['status']?.toString() ?? '';
    final dueRaw = card['due_date']?.toString();
    final due = dueRaw == null ? null : DateTime.tryParse(dueRaw);

    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: theme.colorScheme.secondaryContainer,
        child: Icon(Icons.assignment_outlined,
            size: 18, color: theme.colorScheme.onSecondaryContainer),
      ),
      title: Text(title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      subtitle: Text(
        description.isEmpty ? status : '$status · $description',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
            fontSize: 12.5, color: theme.colorScheme.onSurfaceVariant),
      ),
      trailing: due == null
          ? null
          : Text(
              '${due.day.toString().padLeft(2, '0')}/${due.month.toString().padLeft(2, '0')}',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.outline),
            ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  final ThemeData theme;

  const _SectionTitle(
      {required this.icon, required this.title, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: theme.colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Tile de Resultado ──────────────────────────
class _ResultTile extends StatelessWidget {
  final Map<String, dynamic> result;
  final String source;
  final String query;
  final ThemeData theme;
  final VoidCallback onTap;

  const _ResultTile({
    required this.result,
    required this.source,
    required this.query,
    required this.theme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final sender = result['sender'] as Map<String, dynamic>?;
    final senderName = sender?['full_name'] as String? ?? 'Desconhecido';
    final avatarUrl = sender?['avatar_url'] as String?;
    final content = result['content'] as String? ?? '';
    final createdAt = DateTime.tryParse(result['created_at'] as String? ?? '');

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: CircleAvatar(
        radius: 20,
        backgroundColor: theme.colorScheme.primaryContainer,
        backgroundImage:
            avatarUrl != null ? CachedNetworkImageProvider(avatarUrl, maxWidth: 320) : null,
        child: avatarUrl == null
            ? Text(
                senderName.isNotEmpty ? senderName[0].toUpperCase() : '?',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onPrimaryContainer),
              )
            : null,
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(senderName,
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          ),
          if (createdAt != null)
            Text(
              createdAt.chatListFormatted,
              style: TextStyle(fontSize: 11, color: theme.colorScheme.outline),
            ),
        ],
      ),
      subtitle: _buildHighlightedContent(content, query),
      onTap: onTap,
    );
  }

  /// Destaca o trecho buscado em negrito/primário dentro do conteúdo.
  Widget _buildHighlightedContent(String content, String query) {
    if (query.isEmpty) {
      return Text(content, maxLines: 2, overflow: TextOverflow.ellipsis);
    }

    final lowerContent = content.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final idx = lowerContent.indexOf(lowerQuery);

    if (idx == -1) {
      return Text(content,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              color: theme.colorScheme.onSurfaceVariant, fontSize: 13));
    }

    return RichText(
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style:
            TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 13),
        children: [
          if (idx > 0) TextSpan(text: content.substring(0, idx)),
          TextSpan(
            text: content.substring(idx, idx + query.length),
            style: TextStyle(
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.primary,
                backgroundColor:
                    theme.colorScheme.primary.withValues(alpha: 0.1)),
          ),
          if (idx + query.length < content.length)
            TextSpan(text: content.substring(idx + query.length)),
        ],
      ),
    );
  }
}
