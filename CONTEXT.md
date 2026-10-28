# AlinhaJá - Contexto do Sistema

> **Sobre a marca neste documento:** o AlinhaJá nasceu como fork rebrandado do
> Fluxy e, desde 28/10/2026, vive em repositório próprio (`DelcioFDNeto/AlinhaJa`),
> sem paridade automática com o Fluxy — ver seção 34. As seções históricas que
> citam "Fluxy" descrevem o projeto-base e foram mantidas de propósito. O nome
> visível do app sai de `AppConstants.appName` (`lib/core/constants.dart`).

> Documentação técnica completa. Última atualização: 28/10/2026 (White-label: marca do produto na build e identidade visual por empresa — ver seção 35). Anterior: 28/10/2026 (Repositório próprio, limpeza de segurança e Fase 0 do plano de evolução — ver seção 34). Anterior: 08/09/2026 (Diretriz de Paridade com o Fluxy — NÃO portar migration 20260908150000 — ver seção 31). Anterior: 03/09/2026 (v1.3.8 — Auditoria Geral de Segurança, Hardening LGPD, SMTP e Correções de Enum/Auth — ver seção 30). Anterior: 21/08/2026 (v1.3.7 — ver seção 29). Anterior: 20/08/2026 (v1.3.6 — ver seção 28). Anterior: 29/07/2026 (Assistente IA — persona por conversa e blindagem de marca — ver seção 22).


---

## 1. Visão Geral do Sistema

**AlinhaJá** é um aplicativo corporativo de mensagens instantâneas desenvolvido em Flutter, projetado para comunicação oficial entre equipes e filiais da empresa. Integra mensagens, videoconferências, workflow/service desk, helpdesk e rastreamento GPS.

### Stack Tecnológica

| Categoria                           | Tecnologia                                                                                      |
| ----------------------------------- | ----------------------------------------------------------------------------------------------- |
| Linguagem                           | Dart (Flutter 3.2+)                                                                             |
| State Management                    | Riverpod (StateNotifier, Family Providers)                                                      |
| Navegação                           | GoRouter                                                                                        |
| Backend                             | Supabase (PostgreSQL, Realtime, Auth, Storage, Functions)                                       |
| Mensagens Push                      | Firebase Cloud Messaging + Local Notifications (Triggers assíncronos pós-insert no DB Supabase) |
| Chat UX                             | Mensagens com suporte a markdown, busca local (filtro por termo), empty-states, silenciar chats |
| Video Chamadas 1:1                  | Agora RTC Engine (Tokens dinâmicos seguros via Edge Function)                                   |
| Video Conferências N:N              | MiroTalk SFU                                                                                    |
| Armazenamento Local (Offline Cache) | Hive (runtime cache) + Drift/SQLite (estruturado)                                               |
| Backup Local                        | Drift (espelho SQLite de mensagens) + Export ZIP via `archive`                                  |
| Gerenciamento de Cache de Mídia     | Drift (metadados LRU) + Disco (arquivos físicos) com limites configuráveis                      |
| GPS Tracking                        | Geolocator + Flutter Foreground Task                                                            |

---

## 2. Níveis de Acesso e Permissões (RBAC)

O sistema utiliza 4 níveis hierárquicos de acesso para controle de privilégios (`role_level` na tabela `public.users`). Cada nível superior herda todas as permissões do nível inferior:

1. **super_admin** (TI): Acesso irrestrito a todos os recursos administrativos, painéis de logs avançados e o **único** capaz de conceder/remover o nível `super_admin` de outros usuários.
2. **admin** (Diretores e Gerentes Gerais): Acesso completo ao Painel Administrativo, moderação de conteúdo, criação de usuários, criação/remoção definitiva de canais de comunicação, relatórios de uso e gestão plena do fluxo (Workflow/Helpdesk).
3. **manager** (Supervisores e Gestores Táticos): Podem criar Salas de Reuniões em vídeo dentro de canais e criar Grupos de Chat (DMs com mais de 2 pessoas). Diferem de `member` apenas nestas duas funcionalidades.
4. **member** (Colaboradores, Vendedores, Pós-Venda): Usuários padrão. Utilizam o chat (apenas 1:1, não podem criar grupos), interagem no workflow em cards atribuídos a eles e podem criar solicitações. Não possuem acesso aos painéis administrativos ou de relatórios.

---

## 2.1 Estrutura de Pastas

```
lib/
├── main.dart                          # Entry point
├── app.dart                           # ProviderScope, init services
├── core/
│   ├── constants.dart                  # URLs, versão, config globais
│   ├── supabase_client.dart           # Cliente Supabase
│   ├── router.dart                    # GoRouter (auth guard)
│   ├── globals.dart                   # Variáveis globais (nav keys)
│   ├── theme_provider.dart            # Tema (light/dark)
│   ├── database/
│   │   └── drift_database.dart        # Drift: MediaCache + LocalMessages (+ .g.dart)
│   ├── providers/
│   │   ├── presence_service.dart       # Online/offline tracking
│   │   └── org_providers.dart        # Branches, departments, jobs
│   ├── services/
│   │   ├── push_notification_service.dart  # FCM + Local
│   │   ├── call_service.dart          # Agora + MiroTalk orchestrator
│   │   ├── mirotalk_service.dart      # MiroTalk REST API
│   │   ├── location_service.dart       # GPS tracking
│   │   ├── offline_cache_service.dart  # Hive cache (runtime)
│   │   ├── media_cache_manager.dart    # Drift + Disco (LRU, limites 500MB/1GB)
│   │   ├── backup_service.dart         # Export ZIP + sync Supabase→Drift
│   │   ├── sync_service.dart           # Offline queue sync
│   │   └── realtime_polling_service.dart  # Realtime fallback
│   ├── utils/
│   │   ├── permissions.dart            # RBAC centralizado
│   │   └── icon_registry.dart          # Mapeamento ícones
│   └── ui/
│       ├── responsive_layout.dart     # Layout responsivo
│       └── call_overlay_wrapper.dart   # Call UI overlay
└── features/
    ├── auth/                          # Login, signup, splash
    │   └── providers/auth_provider.dart
    ├── profile/                        # Perfil usuário
    │   ├── models/user_model.dart
    │   ├── providers/users_provider.dart
    │   └── ui/profile_screen.dart
    ├── admin/                          # Painel admin TI
    │   ├── ui/admin_dashboard_screen.dart
    │   └── ui/tabs/
    │       ├── user_management_tab.dart
    │       ├── user_create_tab.dart
    │       ├── audit_management_tab.dart
    │       ├── it_support_management_tab.dart
    │       ├── backup_management_tab.dart
    │       └── moderation_tab.dart
    ├── chats/                          # Lista conversas (DMs+Grupos+Canais)
    │   ├── models/chat_model.dart
    │   ├── providers/
    │   │   ├── call_history_provider.dart
    │   │   └── channels_list_provider.dart
    │   └── ui/
    ├── chat/                           # Mensageria (DMs/Grupos)
    │   ├── models/message_model.dart
    │   ├── providers/chat_provider.dart
    │   ├── data/chat_repository.dart
    │   └── ui/
    ├── channels/                       # Canais broadcast
    │   ├── models/channel_model.dart
    │   ├── models/channel_message_model.dart
    │   ├── models/message_metadata.dart
    │   ├── providers/active_channel_provider.dart
    │   ├── providers/channel_info_provider.dart
    │   └── ui/
    ├── calls/                          # Videochamadas
    │   ├── ui/active_call_screen.dart  # 1:1 (Agora)
    │   ├── ui/web_agora_view.dart      # Web video
    │   ├── ui/widgets/
    │   └── ui/mirotalk/               # N:N (MiroTalk)
    │       ├── mirotalk_screen.dart
    │       ├── mirotalk_mobile.dart
    │       ├── mirotalk_web.dart
    │       └── mirotalk_stub.dart
    ├── workflow/                       # Kanban / Service Desk
    │   ├── models/
    │   │   ├── workflow_card_model.dart
    │   │   ├── workflow_enums.dart
    │   │   ├── workflow_supporting_models.dart
    │   │   └── workflow_helpers.dart
    │   ├── providers/workflow_provider.dart
    │   └── ui/
    │       ├── workflow_main_view.dart     # Scaffold + tabs
    │       ├── workflow_board_view.dart    # Kanban drag-drop
    │       ├── workflow_list_view.dart    # Lista + swipe
    │       ├── workflow_compact_view.dart  # Spreadsheet
    │       ├── create_card_sheet.dart      # Form criação
    │       └── widgets/
    │           ├── card_details_sheet.dart # Detalhe completo
    │           ├── workflow_dashboard_sheet.dart
    │           └── message_input_bar.dart
    ├── support/                        # Helpdesk
    │   ├── models/support_ticket_model.dart
    │   ├── models/ticket_message_model.dart
    │   ├── providers/support_provider.dart
    │   └── ui/
    ├── location/                      # GPS tracking
    │   ├── data/location_repository.dart
    │   ├── providers/location_provider.dart
    │   └── ui/
    └── settings/                      # Configurações
        ├── providers/notification_settings_provider.dart
        └── ui/
```

---

## 3. Modelo de Dados (Banco Supabase)

### Separação de Tabelas: DMs/Grupos vs Workspaces (12/05/2026)

> **Arquitetura dual**: Desde a migration `20260512182000`, workspaces operacionais usam tabelas **dedicadas** (`channels`, `channel_members`, `channel_messages`). DMs e grupos permanecem em `chats`, `chat_members`, `messages`.

### Tabelas de Mensageria (DMs e Grupos)

| Tabela         | Descrição                                                       |
| -------------- | --------------------------------------------------------------- |
| `chats`        | Conversas do tipo `direct` e `group` apenas                     |
| `chat_members` | Participantes de DMs/grupos (roles: `owner`, `admin`, `member`); coluna `muted boolean` (silenciar notificações por conversa — migration `20260709150306`) |
| `messages`     | Mensagens de DMs e grupos                                       |

### Tabelas de Workspaces Operacionais

| Tabela                   | Descrição                                                               |
| ------------------------ | ----------------------------------------------------------------------- |
| `channels`               | Canais/workspaces operacionais (type: `operacional`, `avisos`, `comum`) |
| `channel_members`        | Membros dos workspaces (roles: `admin`, `editor`, `viewer`)             |
| `channel_messages`       | Mensagens nos canais operacionais                                       |
| `workflow_cards`         | Cards do Kanban/Service Desk — FK referencia `channels(id)`             |
| `workflow_card_comments` | Comentários nos cards                                                   |
| `workflow_card_history`  | Histórico de alterações                                                 |
| `workflow_status_config` | Configuração de statuses por canal — FK referencia `channels(id)`       |

### Outras Tabelas Principais

| Tabela                    | Descrição                                                              |
| ------------------------- | ---------------------------------------------------------------------- |
| `users`                   | Perfis dos funcionários (role_level, branch, department, job_position) |
| `branches`                | Filiais                                                                |
| `departments`             | Departamentos                                                          |
| `job_positions`           | Cargos                                                                 |
| `calls`                   | Histórico de chamadas 1:1 (suporta `chat_id` ou `channel_id`)          |
| `meetings`                | Reuniões N:N (suporta `chat_id` ou `channel_id`)                       |
| `support_tickets`         | Tickets de helpdesk                                                    |
| `support_ticket_messages` | Mensagens nos tickets                                                  |
| `user_fcm_tokens`         | Tokens FCM por plataforma                                              |
| `user_locations`          | Histórico de GPS                                                       |
| `user_activity_history`   | Histórico de atividades                                                |

### Tabela `meetings` (Videoconferências)

| Coluna       | Tipo        | Descrição                                      |
| ------------ | ----------- | ---------------------------------------------- |
| id           | uuid        | PK                                             |
| title        | text        | Nome da reunião                                |
| host_id      | uuid        | FK users                                       |
| room_id      | uuid        | ID interno da sala                             |
| chat_id      | uuid        | FK chats (nullable — exclusivo com channel_id) |
| channel_id   | uuid        | FK channels (nullable — exclusivo com chat_id) |
| status       | text        | **default `waiting`** / in_progress / ended    |
| mirotalk_url | text        | URL da sala MiroTalk                           |
| created_at   | timestamptz | Criação                                        |
| started_at   | timestamptz | Início                                         |
| ended_at     | timestamptz | Término                                        |

**Constraint**: `meetings_context_check` garante que exatamente um de `chat_id`/`channel_id` seja preenchido (ou ambos nulos para reunião standalone).

### Tabela `workflow_cards` (Service Desk)

| Coluna       | Tipo               | Descrição                                                             |
| ------------ | ------------------ | --------------------------------------------------------------------- |
| id           | uuid               | PK                                                                    |
| channel_id   | uuid               | **FK channels(id)** (não mais chats)                                  |
| card_type    | workflow_card_type | Tipo (conta_pagar/fat_moto/emplacamento/faturamento_os/aviso/generic) |
| title        | text               | Título                                                                |
| description  | text               | Descrição                                                             |
| observations | text               | Observações gerais                                                    |
| priority     | workflow_priority  | low/medium/high/urgent                                                |
| status       | text               | Status atual                                                          |
| assigned_to  | uuid               | FK users (responsável)                                                |
| requested_by | uuid               | FK users (solicitante)                                                |
| attachments  | jsonb              | Anexos ZIP                                                            |
| is_pinned    | boolean            | Fixado                                                                |
| is_archived  | boolean            | Arquivado                                                             |
| created_at   | timestamptz        | Criação                                                               |
| updated_at   | timestamptz        | Atualização                                                           |

**Campos específicos por tipo** (`conta_pagar`): `supplier`, `expense_description`, `amount`, `due_date`, `cost_center`
**Campos específicos por tipo** (`fat_moto`): `client_name`, `order_number`, `ficha_number`, `consultant`
**Campos específicos por tipo** (`emplacamento`): `client_name`, `client_cpf_cnpj`, `vehicle_model`, `chassis_number`, `plate`, `branch`
**Campos específicos por tipo** (`faturamento_os`): `os_number`, `budget_number`, `billing_type`, `items_details`

**Observação**: colunas antigas de aprovação podem existir em bancos que passaram pelas migrations antigas, mas o app não lê nem envia esses campos em novos cards.

### Banco Drift (SQLite Local — 25/06/2026)

O aplicativo utiliza **Drift** (SQLite no mobile/desktop, IndexedDB na web) como banco estruturado local para cache de mídia e backup de mensagens, complementando o Hive (cache runtime).

| Tabela           | Descrição                                                                                                                                                      | Uso                                                                     |
| ---------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------- |
| `media_cache`    | Metadados de mídia baixada (URL remota, path local, tipo, tamanho, timestamps de download/último acesso)                                                       | Cache LRU de imagens/vídeos, `MediaCacheManager`, `BackupManagementTab` |
| `local_messages` | Espelho local de mensagens do Supabase (DMs + canais) com `chat_id`, `sender_id`, `content`, `content_type`, `media_url`, `metadata` (JSON), flag `is_channel` | Exportação ZIP (`BackupService`), exibição offline                      |

**Schema** (`lib/core/database/drift_database.dart`):

```dart
class MediaCache extends Table {
  TextColumn get id => text()();                  // UUID da mensagem
  TextColumn get remoteUrl => text()();           // URL no Supabase Storage
  TextColumn get localPath => text().nullable()(); // Caminho no disco (null na Web)
  TextColumn get mediaType => text()();           // 'image', 'video', 'audio', 'document'
  IntColumn get sizeBytes => integer()();         // Tamanho em bytes
  TextColumn get chatId => text()();              // ID do chat/canal de origem
  DateTimeColumn get downloadedAt => dateTime()();
  DateTimeColumn get lastAccessedAt => dateTime()();
  @override Set<Column> get primaryKey => {id};
}

class LocalMessages extends Table {
  TextColumn get id => text()();                  // UUID da mensagem
  TextColumn get chatId => text()();              // chat_id ou channel_id
  TextColumn get senderId => text()();
  TextColumn get content => text().nullable()();
  TextColumn get contentType => text().withDefault(const Constant('text'))();
  TextColumn get mediaUrl => text().nullable()();
  TextColumn get metadata => text().nullable()();  // JSON serializado
  BoolColumn get isChannel => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get syncedAt => dateTime().nullable()();
  @override Set<Column> get primaryKey => {id};
}
```

**Limites de Cache de Mídia** (definidos em `AppConstants`):

- Imagens: **500 MB** (LRU — os arquivos menos acessados são removidos primeiro)
- Vídeos: **1 GB** (LRU)
- Total: **2 GB**
- Retenção: **90 dias** sem acesso

### Database Webhook Triggers para Push Notifications (29/05/2026)

Em substituição ao pipeline de chamadas no cliente Flutter (que causava atrasos de rede e risco de perda de push se o app travasse), a sinalização e envio de push notifications para DMs, Grupos e Canais operacionais foi migrada inteiramente para **Triggers reativos diretos no Banco de Dados** pós-inserção (`AFTER INSERT`):

- `trigger_messages_notification` na tabela `messages` (DMs e Grupos)
- `trigger_channel_messages_notification` na tabela `channel_messages` (Canais e Workspaces)

Estes triggers chamam a respectiva Edge Function de notificação de forma totalmente assíncrona através do mecanismo nativo de webhook do Supabase, garantindo entrega confiável de pushes com latência insignificante.

## 4. RBAC (Role-Based Access Control)

### Hierarquia de Roles

```
super_admin (nível 4) > admin (3) > manager (2) > member (1)
```

### Permissões por Role

| Permissão                 | super_admin | admin | manager | member |
| ------------------------- | :---------: | :---: | :-----: | :----: |
| Criar canais              |     ✅      |  ✅   |   ❌    |   ❌   |
| Criar reuniões (MiroTalk) |     ✅      |  ✅   |   ✅    |   ❌   |
| Criar grupos de chat      |     ✅      |  ✅   |   ✅    |   ❌   |
| Operar/Gerenciar Workflow |     ✅      |  ✅   |   ❌    |   ❌   |
| Editar outros usuários    |     ✅      |  ✅   |   ❌    |   ❌   |
| Aprovar cadastros         |     ✅      |  ✅   |   ❌    |   ❌   |
| Painel Admin              |     ✅      |  ✅   |   ❌    |   ❌   |
| Moderação                 |     ✅      |  ✅   |   ❌    |   ❌   |
| Relatórios                |     ✅      |  ✅   |   ❌    |   ❌   |
| Helpdesk Admin            |     ✅      |  ✅   |   ❌    |   ❌   |
| Rastreamento GPS          |     ✅      |  ✅   |   ❌    |   ❌   |

### Workflow RBAC Específico

| Ação                                 | Requisito                                                                                                                                                                    |
| ------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Mover card entre status              | Ser `assigned_to` ou admin+; `requested_by` nao pode operar o proprio card                                                                                                   |
| Arquivar/cancelar/fixar/excluir card | Ser `assigned_to` OU admin+; `requested_by` nao pode operar o proprio card                                                                                                   |
| Criar card                           | Qualquer membro do canal                                                                                                                                                     |
| Assumir card                         | Operador configurado em `operator_ids` ou membro do workspace quando o canal nao restringe operadores; `assigned_to` deve estar vazio e o usuario nao pode ser o solicitante |
| Atribuir card                        | admin+                                                                                                                                                                       |
| Comentar no proprio card             | Solicitante so pode comentar/interagir apos o card chegar em status final (`workflow_status_config.is_final = true`)                                                         |
| Finalizar com anexo                  | Operador responsável (assigned_to) ou admin+                                                                                                                                 |

### Fluxo de Status do Workflow

Fluxo padrão (configurável por canal via `workflow_status_config`):

```
Solicitação aberta → Em análise → Aguardando Solicitante → Finalizado
                                                          ↘ Cancelado (via ação)
```

### Arquivo de Permissões

`lib/core/utils/permissions.dart` - Centraliza todas as verificações de permissão via `AppPermissions`:

- `canAccessAdmin()`, `canApproveUsers()`, `canEditOtherUsers()`
- `canCreateChannel()`, `canManageChannelMembers()`
- `canAccessHelpdesk()`, `canModerate()`, `canViewReports()`
- `canToggleUserStatus()`, `canAssignSuperAdmin()`, `canDeleteChannel()`
- `canManageLocationTracking()`
- `canOperateWorkflowCard()` — mover, assumir, finalizar cards no workflow
- `canManageWorkflow()` — editar campos, excluir anexos, cancelar solicitação

---

## 5. Presença (Online/Offline)

### Fluxo

1. **Login** → `PresenceService.init()` → `is_online: true`
2. **Minimizar/Fechar** → `_goOffline()` sequencial (await em cada etapa) → `is_online: false`
3. **Heartbeat (2min)** → apenas `last_seen_at`
4. **Reconexão** → canais Realtime reconectam

### Smart Presence ("Sem Fantasmas")

```dart
bool get isActuallyOnline {
  if (!isOnline) return false;
  if (lastSeenAt == null) return false;
  return DateTime.now().toUtc().difference(lastSeenAt!).inMinutes <= 5;
}
```

A UI usa `isActuallyOnline` em vez de `isOnline` para exibir bolinha verde.

---

## 6. Mensagens e Chat

### Tipos de Mensagem Suportados

| Tipo         | Chat | Channel | Descrição                                                                                                          |
| ------------ | :--: | :-----: | ------------------------------------------------------------------------------------------------------------------ |
| Text         |  ✅  |   ✅    | Texto com markdown e mentions                                                                                      |
| Image        |  ✅  |   ✅    | Compressão 80%, MediaCacheManager (Drift + disco), CachedNetworkImage (fallback web), Hero, Zoom Viewer com gestos |
| Audio        |  ✅  |   ✅    | Playback nativo (audioplayers), Slider e play/pause inline nos canais                                              |
| Video        |  ✅  |   ✅    | Playback inline nativo (video_player) com aspect-ratio inteligente                                                 |
| File         |  ✅  |   ✅    | Cards semânticos premium para OS (laranja) e Financeiro (recibos/boletos em verde)                                 |
| Meeting      |  ✅  |   ❌    | Card de reunião MiroTalk                                                                                           |
| Announcement |  ❌  |   ✅    | Via MessageMetadata                                                                                                |
| Poll         |  ❌  |   ✅    | Via MessageMetadata                                                                                                |
| Date Event   |  ❌  |   ✅    | Via MessageMetadata                                                                                                |
| System       |  ❌  |   ✅    | Mensagens automáticas                                                                                              |

### Recursos Implementados

- **Optimistic UI** - Mensagem e mídias de canais aparecem instantaneamente antes do upload terminar
- **Swipe to Reply** - Responder mensagens com gesto (Dismissible)
- **Read Receipts** - Três estados em tempo real, na bolha **e** na lista de conversas: ✓ `sent` (no servidor) · ✓✓ `delivered` (chegou ao destinatário) · ✓✓ azul `read`. Entrega confirmada pelo destinatário via `mark_messages_as_delivered`; leitura via `mark_messages_as_read` + `chat_members.last_read_at` (ver seção 20)
- **Typing Indicator** - "X está digitando..." (broadcast channel)
- **Message Expiration** - Mensagens temporárias com timer (texto)
- **View Once** - Mídias de visualização única (Imagens e Vídeos temporários interceptados e deletados após 1 visualização). Ativado pelo botão "1" na tela de preview, junto da legenda — padrão WhatsApp (ver seção 20)
- **Push-to-Talk** - Gravador de áudio integrado no MessageInput
- **Pinned Messages** - Mensagens fixadas no topo
- **Starred Messages** - Favoritar mensagens (tela `/starred`)
- **Fila Offline para Canais** - Cache offline via Hive e fila de sincronização transparente para mensagens e mídias enviadas sem internet
- **Otimização de Streams Realtime** - Merge incremental e inteligente de mensagens em tempo real no cliente, eliminando pulos na tela e recargas massivas
- **Client-Side Sorting** - Ordenação das mensagens em tempo real delegada inteiramente ao Dart para economizar recursos computacionais no Supabase
- **Prevenção de N+1 Queries** - Batch fetching de metadados de remetentes (`getMessagesBatch()`) para lotes de mensagens recebidas de uma só vez
- **Cache de Mídia com LRU** - Imagens e vídeos armazenados localmente via `MediaCacheManager` (Drift + disco) com limites de 500MB/1GB e limpeza automática dos menos acessados
- **Backup Local de Mensagens** - `BackupService` sincroniza mensagens do Supabase para o Drift local e permite exportação em ZIP pelo painel admin
- **Busca na Conversa** - Ícone de lupa no `ChatAppBar` abre campo de busca; filtro local por termo (`ChatState.searchQuery`, `setSearchQuery()`), com empty-state dedicado quando não há resultados
- **Silenciar Conversa (ponta-a-ponta)** - `toggleMute()` grava `chat_members.muted` e a Edge Function `send-chat-notification` filtra destinatários silenciados antes de enviar push (fallback seguro se a coluna não existir; não se aplica a canais, pois `channel_members` não possui `muted`). UI reflete via `ref.invalidate(chatMembersProvider)` — ícone 🔇 no título e rótulo do menu alternam na hora
- **Limpar Janela** - `clearLocalMessages()` remove as mensagens apenas da tela local (não toca no servidor), com diálogo de confirmação
- **Sair do Grupo** - `leaveGroup()` remove a associação em `chat_members`, invalida `chatsListProvider` e navega para `/chats`
- **Scroll-to-Bottom** - FAB flutuante aparece após rolar > 200px e retorna ao fim da conversa; tap na mensagem fixada rola até ela
- **Cabeçalho Rico do Chat** - `ChatAppBar` (agora `ConsumerStatefulWidget`) exibe avatar, indicador online, "digitando...", contagem de membros e ícone de silenciado
- **Scrollbars/Scroll Responsivos** - `dragDevices` (touch/mouse/trackpad) habilitados globalmente em `app.dart`; filtros de categoria em `channels_tab` com `RawScrollbar` + rolagem por wheel e responsividade em telas estreitas

---

## 7. Videochamadas

### Tipos

| Tipo          | Provedor     | Uso                    | Arquivo UI                |
| ------------- | ------------ | ---------------------- | ------------------------- |
| **1:1 Audio** | Agora RTC    | DMs - chamadas de voz  | `active_call_screen.dart` |
| **1:1 Video** | Agora RTC    | DMs - videochamadas    | `active_call_screen.dart` |
| **N:N Video** | MiroTalk SFU | Grupos/Canais/Reuniões | `mirotalk_screen.dart`    |

### Configuração MiroTalk

| Recurso       | Valor                           |
| ------------- | ------------------------------- |
| Servidor      | https://sfu.mirotalk.com        |
| API           | https://sfu.mirotalk.com/api/v1 |
| API Key       | `mirotalksfu_default_secret`    |
| Participantes | Ilimitado                       |
| Tempo         | Ilimitado                       |

### Configuração Agora

| Recurso             | Valor                                                                            |
| ------------------- | -------------------------------------------------------------------------------- |
| App ID              | `50208c981fa6436290b854369d0c136b`                                               |
| Audio Profile       | speechStandard                                                                   |
| Video               | 640x480, 30fps, VP8/H264                                                         |
| Perfil de Canal     | `channelProfileLiveBroadcasting` (com Broadcaster) para cross-platform universal |
| Segurança de Tokens | Tokens dinâmicos seguros válidos por 1h via Edge Function                        |
| Fallback local      | Token vazio automático em ambiente de testes caso secrets não configuradas       |

### Servidor de Tokens Seguros da Agora.io (29/05/2026)

Para viabilizar o uso em produção com segurança criptográfica, as chamadas 1:1 usam tokens dinâmicos gerados no servidor:

1. **Supabase Edge Function (`get-agora-token`)**: Desenvolvida em TypeScript e implantada sob Deno. Ela recebe requisições GET/POST do cliente, decodifica o JWT no cabeçalho `Authorization` para comprovar que o remetente é um usuário autenticado do Supabase, e gera um token RTC oficial contendo privilégios de entrada no canal Agora solicitado.
2. **Biblioteca Utilizada**: `@agora-token` (npm version `2.0.3`) com suporte para Agora RTC Privilege.
3. **Resiliência e Fallback**: O Flutter detecta automaticamente se a Edge Function está ausente ou se as variáveis secretas `AGORA_APP_ID` e `AGORA_APP_CERTIFICATE` não estão configuradas no painel do Supabase. Nesses casos, o app realiza um fallback automático silencioso para token vazio (modo de testes local da Agora), garantindo que desenvolvedores possam rodar e testar as chamadas localmente sem atritos.

### Fluxo de Reunião (MiroTalk)

1. Host (manager+) cria reunião → `CallService.createMeetingRoom()`
2. App chama MiroTalk API (`POST /api/v1/meeting`) → cria sala
3. App salva URL em `meetings.mirotalk_url`
4. Host entra **primeiro** para validar a sala
5. Card com descrição enviado ao chat
6. Membros clicam no card → buscam URL → abrem no navegador

### Rotas

- `/calls/:chatId` - Chamada 1:1 (Agora)
- `/mirotalk/:roomId` - Videoconferência N:N (MiroTalk)

---

## 8. Workflow / Service Desk

### Arquitetura de Fluxo

O workflow funciona como um **sistema de solicitação e atendimento por canal**, onde:

- **Solicitante** (qualquer membro do canal) cria cards via formulário
- **Operador/Atendente** (atribuído ao card ou admin+) trata, move status e responde
- **Gestor** (admin+) supervisiona, redistribui e arquiva

### Fluxo Operacional Solicitante -> Operador

**Atualizacao 12/05/2026 - atribuicao configuravel por canal**

- `assignment_mode = single_operator`: canal com 1 operador fixo; cards novos ja nascem atribuidos ao `default_operator_id`.
- `assignment_mode = operator_pool`: canal com equipe; cards novos nascem sem responsavel e entram em fila para **Assumir atendimento**.
- `operator_ids`: quando preenchido, restringe quem pode assumir cards naquele workflow.
- `super_admin` ou o criador do canal podem abrir as informacoes do canal e marcar/desmarcar quem e operador.
- Canais antigos sem esses metadados continuam no modo compativel: qualquer membro do workspace pode assumir cards sem responsavel.

1. Solicitante cria o card no workspace/canal de workflow.
2. Card nasce no status inicial configurado em `workflow_status_config`; a atribuição depende do `assignment_mode` do canal.
3. Operador abre o detalhe do card e usa **Assumir atendimento**.
4. Backend registra a posse via RPC `claim_workflow_card`, valida que o operador é membro do workspace e grava histórico.
5. Operador move o card no board/lista/compacto ou usa ações do detalhe.
6. Se precisar de informação, move para `Aguardando Solicitante`.
7. Ao concluir, usa `Finalizar com Anexo`, que move para o status `is_final` configurado do canal.

Esse fluxo evita atribuição aleatória e deixa a decisão maleável: um canal pode ter operador único com autoatribuição ou uma equipe que assume cards em fila.

### Tipos de Card (6 tipos)

| Type             | Label                    | Uso                      |
| ---------------- | ------------------------ | ------------------------ |
| `conta_pagar`    | Liberação Contas a Pagar | Solicitação de pagamento |
| `fat_moto`       | Liberação Fat Moto       | Faturamento motorcycles  |
| `emplacamento`   | Emplacamento             | Processo de emplacamento |
| `faturamento_os` | Faturamento OS/Peças     | Faturamento de OS        |
| `aviso`          | Avisos Gerais            | Comunicados              |
| `generic`        | Genérico                 | Uso geral                |

### Prioridades

| Priority | Label  | Cor     |
| -------- | ------ | ------- |
| Baixa    | low    | #6B7280 |
| Média    | medium | #F59E0B |
| Alta     | high   | #F97316 |
| Urgente  | urgent | #EF4444 |

### Status (Configurável por Canal)

Via `workflow_status_config` com fallback nativo:

1. `Solicitação aberta` (ordem 1, #3B82F6)
2. `Em análise` (ordem 2, #F59E0B)
3. `Aguardando Solicitante` (ordem 3, #8B5CF6) — quando operador precisa de resposta do cliente
4. `Finalizado` (ordem 4, isFinal: true, #10B981)
5. `Cancelado` (via ação do card)

### UI Views

| View     | Arquivo                      | Descrição                               |
| -------- | ---------------------------- | --------------------------------------- |
| Board    | `workflow_board_view.dart`   | Kanban colunas por status com drag-drop |
| Lista    | `workflow_list_view.dart`    | Lista vertical com swipe-to-advance     |
| Compacto | `workflow_compact_view.dart` | Linhas densas (spreadsheet)             |

### Recursos Implementados

- **Filtros** - Status, Prioridade, Responsável, "Meus Cards"
- **Bulk Actions** - Selecionar múltiplos, mover status, arquivar
- **Pinning** - Fixar cards no topo
- **Comentários** - Thread de conversa no card
- **Histórico** - Timeline de alterações (até 5 visíveis, "ver todos")
- **Anexos** - Upload PDF/imagem compactado em ZIP
- **Finalizar com Anexo** - Operador envia documento final e move para o status final configurado (`is_final`)
- **SLA Tracking** - Indicador visual de SLA excedido por prioridade
- **Dashboard operacional** - Total, valor, meus cards, SLA estourado e cards por status
- **Atribuição configurável** - Canal pode usar operador único com autoatribuição ou equipe com fila
- **Gestão de operadores** - `super_admin` ou criador do canal define quem é operador pela tela de informações do canal
- **Assumir atendimento** - Operador autorizado assume cards sem responsável via RPC segura
- **Status intermediário** - "Aguardando Solicitante" para pauses por espera
- **Notifications** - Toast ao ser atribuído, toast para cards urgentes
- **Real-time** - Cards e status via Supabase Realtime; detalhe do card escuta comentarios/historico sem precisar reabrir ou dar F5
- **Regra do solicitante** - Quem cria o card acompanha o fluxo, mas nao opera status/atribuicao/cancelamento/finalizacao do proprio card; comentarios do solicitante ficam liberados apenas apos conclusao

### Formulário de Criação (`create_card_sheet.dart`)

Cada tipo de card tem campos específicos:

- **Conta Pagar**: Fornecedor, Descrição, Valor, Vencimento, Centro Custo
- **Fat Moto**: Cliente, Nº Pedido, Nº Ficha, Consultor
- **Emplacamento**: Cliente, CPF/CNPJ, Modelo Veículo, Placa, Chassi, Filial, Vendedor
- **Faturamento OS**: Nº OS, Nº Orçamento, Tipo, Detalhes dos Itens
- **Aviso**: Sem campos específicos (apenas info na aba Conversa)

---

## 9. Admin / Helpdesk

### Painel Admin (8 abas)

| Aba                | Função                                                            |
| ------------------ | ----------------------------------------------------------------- |
| Gestão de Usuários | Lista, buscar, filtrar, ativar/desativar, promover                |
| Novo Cadastro      | Criar funcionários (nome, email, branch, role, dept, cargo)       |
| Auditoria          | Listar todos canais/grupos para acesso                            |
| Moderação          | Excluir mensagens (24h), listar canais                            |
| Relatórios         | Métricas (usuários ativos, mensagens, chamadas) + gráfico 7 dias  |
| Helpdesk (TI)      | Gerenciar tickets de suporte                                      |
| Localização        | Ver tracking GPS                                                  |
| Backup             | Exportar mensagens em ZIP, gerenciar cache de mídia local (Drift) |

### Helpdesk (Suporte T.I.)

**Para usuários:**

- Criar ticket (título, categoria, prioridade, descrição)
- Listar meus tickets
- Chat no ticket
- Ver status

**Categorias de Ticket:**

- Software / Systems
- Hardware / Equipment
- Network / Internet
- External Access / Credentials
- General Question
- Other

**Prioridades:**

- Low (pode esperar)
- Medium (uso diário)
- High (atrapalha trabalho)
- Urgent (sistema fora)

**Admin TI:**

- Estatísticas (novos, andamento, pendentes, resolvidos)
- Assumir ticket
- Marcar como resolvido
- Cancelar ticket
- Chat com usuário

---

## 10. Localização / GPS

### Serviço

`LocationService` - Rastreamento GPS com otimização de bateria:

- Detecção de movimento via acelerômetro
- 5 min timeout → "Low Battery Mode"
- Foreground service (Android/iOS)
- Fallback Timer (Web)

### Dados Gravados

Tabela `user_locations`:

- user_id, lat, lng
- battery_level
- device_info (OS, versão)
- timestamp

### Screens

- `/settings/location` - Tracking on/off
- `/admin` tab Localização - Dashboard admin

---

## 11. Serviços Core

### PushNotificationService

- Firebase Cloud Messaging (FCM)
- Local Notifications com agrupamento (Android)
- Canais: DMs, Grupos, Channels, Workflow, Calls
- Suprime notificações do chat atual
- **Ícone Nativo Monocromático**: Logotipo oficial monocromático da Shineray (`ic_notification.png`) configurado nas pastas `drawable` de densidade nativas Android, eliminando blocos brancos genéricos.
- **Sincronização em Background (Sem Wake Engine)**: Modificado o `NotificationSettingsProvider` para gravar preferências físicas no `SharedPreferences`. O isolate em segundo plano do Firebase (`firebaseMessagingBackgroundHandler`) consome diretamente essas preferências, honrando Não Perturbe (DND), silenciamentos de chats e filtros de tipo de conversa sem carregar o engine pesado do Flutter na memória, economizando bateria.
- **Database Webhook Triggers**: Os disparos de push não são mais solicitados pelo Flutter! Agora são feitos reativamente de forma assíncrona por triggers direto no PostgreSQL do Supabase pós-insert de mensagens (`trigger_messages_notification` e `trigger_channel_messages_notification`), eliminando tráfego extra do dispositivo do usuário e garantindo entrega sob qualquer condição de rede.
- **Filtro de Silenciamento no Backend**: A Edge Function `send-chat-notification` remove da lista de destinatários os usuários que silenciaram a conversa (`chat_members.muted = true`) antes de buscar tokens FCM e enviar o push. Aplica-se apenas a DMs/grupos (a tabela `channel_members` não possui `muted`) e cobre também o roteamento de threads; em caso de falha na consulta, faz fallback seguro mantendo os destinatários. É este o ponto que efetiva o "Silenciar Conversa" — o cliente apenas grava a flag.

### OfflineCacheService

- Hive para cache local
- Boxes: messages, chats, users, settings, queue, **channel_messages_cache** (Fase 5)
- Mantém fila de operações offline
- Registra adaptadores Hive do tipo `ChannelMessageModel` (`ChannelMessageModelAdapter`) para permitir cache de canais
- Cleanup automático (7 dias)

### MediaCacheManager

- Banco Drift (`MediaCache`) para metadados de cache de mídia
- Download automático de imagens/vídeos para disco local com fallback na Web
- Limites configuráveis: 500MB imagens, 1GB vídeos, 2GB total
- LRU (Least Recently Used): quando o limite é atingido, apaga arquivos não acessados há mais tempo
- `getOrDownloadMedia()`: verifica cache → retorna local ou baixa e registra
- `cacheLocalFile()`: registra arquivos enviados no cache (sem re-download)
- `runStorageCleanup()`: limpeza programada de todos os tipos de mídia
- `getCacheUsageMB()`: consulta de uso atual por tipo (para tela de admin)

### BackupService

- `exportMessagesAsZip()`: exporta mensagens locais (Drift `LocalMessages`) em JSON compactado ZIP
  - Web: download direto via navegador (Data URI)
  - Mobile/Desktop: salva em `{documents}/backups/`
- `syncRecentMessages()`: sincroniza mensagens dos últimos 30 dias do Supabase (tabelas `messages` + `channel_messages`) para o Drift local
- `getLocalMessageCount()`: total de mensagens armazenadas localmente

### SyncService

- Monitora conectividade (connectivity_plus)
- Processa fila offline quando reconecta
- Dispara re-envios offline de mensagens e mídias de canais operacionais via fila do Hive
- Limite de 5 retries por operação para evitar loop infinito
- Ao reconectar, chama `BackupService.syncRecentMessages()` e `MediaCacheManager.runStorageCleanup()`

### RealtimePollingService

- Fallback quando Supabase Realtime falha
- Poll interval padrão: 30s
- Ativa automaticamente em falhas

---

## 12. Autenticação

- Provedor: **Supabase Auth**
- Fluxo: Login → verifica `is_active` → **avalia 2FA (AAL)** → redireciona
- Sessão: via `onAuthStateChange`
- Logout: remove FCM token, marca offline, signOut, reseta `Globals.is2faVerified`

### Splash Screen

1. Verifica sessão existente
2. Consulta `is_active` no banco
3. Se inativo → signOut + mensagem
4. Se ativo → avalia o AAL da sessão (`MfaService.evaluate()`) → `/chats` ou `/verify-2fa`

### 2FA — MFA nativo TOTP (AAL2) — 04/07/2026

> **Substitui** o antigo 2FA por e-mail (OTP + `user_trusted_devices`/`user_email_otp` + Edge Function `send-2fa-code`), que era apenas navegação no cliente e podia ser burlado (ex.: voltar aba no navegador, digitar a URL, recarregar). O código legado permanece no repo mas está **fora do fluxo ativo**.

**Enforcement real no servidor (RLS):** migration `20260704120000_enforce_mfa_aal2.sql` cria a policy **restritiva** `require_aal2` em 17 tabelas de conteúdo sensível (`messages`, `channel_messages`, `chats`, `chat_members`, `channels`, `channel_members`, `workflow_cards`, `workflow_card_comments`, `workflow_card_history`, `support_tickets`, `support_ticket_messages`, `user_locations`, `user_activity_history`, `starred_messages`, `calls`, `meetings`, `message_actions`). Um JWT que só passou pela senha (`aal1`) **não lê nem escreve** nessas tabelas — nem via API REST direta. Só sessões `aal2` (senha + código TOTP) têm acesso.

- **Anti-lockout (rollout):** a policy exige `aal2` **apenas** de quem já tem fator TOTP verificado (helper SECURITY DEFINER `public.user_has_verified_mfa()`). Quem ainda não configurou 2FA continua acessando — evita trancar a base durante a adoção. Para tornar obrigatório: remover a cláusula `OR NOT public.user_has_verified_mfa()` das policies **e** trocar o caso `notEnrolled` no login/splash por `context.go('/mfa-setup', extra: {'onboarding': true})`.
- **Tabelas fora do gate** (de propósito): `users`, `user_fcm_tokens` e organização — o login/splash lê `is_active` **antes** do 2FA (sessão ainda `aal1`); gateá-las travaria o próprio login.
- **Pré-requisito:** TOTP habilitado em Authentication → Multi-Factor Authentication no projeto Supabase (senão `enroll()` falha em runtime).

**Camada de cliente:**

| Arquivo | Papel |
| ------- | ----- |
| `lib/features/auth/services/mfa_service.dart` | Wrapper de `supabase.auth.mfa`: `evaluate()` (verified/challengeRequired/notEnrolled), enroll TOTP, `verifyCode` (challengeAndVerify), listar/remover fatores |
| `lib/features/auth/ui/mfa_enrollment_screen.dart` | Rota `/mfa-setup`. Enrollment: QR code (`qr_flutter`) + chave manual + confirmação. `isOnboarding` decide `/chats` vs `pop`. Acessível por Configurações → Segurança e 2FA |
| `lib/features/auth/ui/verify_2fa_screen.dart` | Rota `/verify-2fa`. Desafio TOTP no login: 6 dígitos → `challengeAndVerify` → sobe sessão a `aal2` |
| `lib/core/globals.dart` | `is2faVerified` (flag síncrona, em memória) — gate de UX no router; a proteção real é a RLS |
| `lib/core/router.dart` | `redirect` bloqueia rotas protegidas se `!is2faVerified`; logado-sem-2FA só acessa `/`, `/verify-2fa`, `/mfa-setup`. Fecha o bypass do "voltar aba" |

**Fluxo de login:** `signInWithPassword` → checa `is_active` → `MfaService.evaluate()`:
- `verified` (sessão já `aal2`) → `/chats`
- `challengeRequired` (tem fator, sessão `aal1`) → `/verify-2fa`
- `notEnrolled` (sem fator) → `/chats` (rollout; RLS não bloqueia)

---

## 13. Configuração

### Versão

```dart
static const appVersion = '1.0.9';
static const appBuild = 1062026;
```

### URLs

| Serviço  | URL                                                      |
| -------- | -------------------------------------------------------- |
| App Web  | https://fluxy.web.app                                    |
| Supabase | https://gpeemngsxvqjflasdody.supabase.co (projeto AlinhaJá; ref antigo `hzvmqsgpopgfkvdxyain` descontinuado) |
| Firebase | https://console.firebase.google.com/project/chat-bysabel |
| MiroTalk | https://sfu.mirotalk.com                                 |

### Variáveis de Ambiente (`dart_defines.json`)

Produção deve usar `--dart-define-from-file=dart_defines.json`. O `.env` fica apenas como fallback local/debug e não deve ser publicado no Firebase Hosting.

```json
{
  "SUPABASE_URL": "https://gpeemngsxvqjflasdody.supabase.co",
  "SUPABASE_ANON_KEY": "sb_publishable_...",
  "AGORA_APP_ID": "50208c981fa6436290b854369d0c136b",
  "FIREBASE_WEB_API_KEY": "AIzaSyApoDs...",
  "FIREBASE_WEB_APP_ID": "1:1054159540269:web:c4cd631a793a5c789868a4",
  "FIREBASE_WEB_MESSAGING_SENDER_ID": "1054159540269",
  "FIREBASE_WEB_PROJECT_ID": "fluxy-app",
  "FIREBASE_VAPID_KEY": "BDoqzF68..."
}
```

---

## 14. Comandos

### Pré-check local

Antes de buildar, confirmar que o Flutter/Dart não está travado. Se `dart --version` ou `flutter --version` não responderem, reiniciar a IDE/terminal ou encerrar processos antigos `dart.exe`/`java.exe`.

```powershell
Get-Process dart,flutter,java -ErrorAction SilentlyContinue
dart --version
flutter --version
flutter doctor -v
```

### Dependências e análise

```powershell
flutter pub get
dart format lib test
flutter analyze
flutter test
```

Se o analyzer/testes voltarem a travar, não fazer deploy sem investigar o processo preso.

### Supabase

Aplicar migrations antes do deploy do app, pois o workflow atual depende das RPCs `create_workspace`, `claim_workflow_card`, `update_workflow_operators`, `seed_base_workflow_channels` e `reset_operational_data`.

```powershell
npx supabase migration list
npx supabase db push
npx supabase migration list
```

#### Provisionamento de Secrets (Agora.io) & Edge Functions (29/05/2026)

Para habilitar a geração de tokens seguros no servidor de produção, é obrigatório provisionar o App ID e App Certificate gerados no console da Agora.io nas secrets do Supabase:

```powershell
# Defina as Secrets de producao no painel remoto do Supabase
npx supabase secrets set AGORA_APP_ID="50208c981fa6436290b854369d0c136b" AGORA_APP_CERTIFICATE="SEU_CERTIFICADO_AGORA_AQUI"
```

> **Status atual (20/08/2026)**: **as 12 Edge Functions estão no ar** — verificado por sondagem `POST /functions/v1/<nome>` nos bancos das duas marcas (resposta != `404 not found` = deployada). Isso inclui `send-workflow-notification` e `webhook-receiver`, que esta nota listava como não deployadas desde 01/06/2026.

Migrations obrigatórias mais recentes:

- `20260512153000_harden_workspace_security.sql`
- `20260512170000_workflow_assignment_config.sql`
- `20260512173000_manage_workflow_operators.sql`
- `20260512180000_unified_workflow_channel_seed.sql`
- `20260512181000_fix_unified_seed_conflict_target.sql`
- `20260512182000_isolate_workspaces_in_channels.sql`
- `20260512183000_fix_channel_seed_member_conflict.sql`
- `20260512184000_fix_get_chats_with_preview_job_position.sql`
- `20260512185000_fix_workspace_membership_visibility.sql`
- `20260513120000_optimize_workspace_channels_and_notifications.sql`
- `20260513150000_fix_meetings_default_status.sql`
- `20260513160000_enable_meetings_in_channels.sql`
- `20260513170000_enable_realtime_for_dedicated_workspaces.sql`
- `20260513183000_enable_realtime_for_app_surface.sql`
- `20260513190000_block_workflow_requester_operations.sql`

Seed/reseed operacional atual:

```powershell
# Reaplicar canais base sem apagar operadores configurados
# Executar o SQL em supabase/scripts/create_base_channels.sql

# Reset operacional destrutivo + reseed dos canais base
# Executar o SQL em supabase/scripts/reset_and_seed_operational_data.sql
```

### Build Web

```powershell
flutter build web --release --dart-define-from-file=dart_defines.json
firebase deploy --only hosting:app
```

Para publicar também a landing page:

```powershell
firebase deploy --only hosting:landing
```

### Build Android

Build APK oficial do projeto: usar sempre `--split-per-abi`.

```powershell
flutter build apk --release --split-per-abi --dart-define-from-file=dart_defines.json
```

Antes de publicar Android externamente em lojas/distribuição formal, configurar keystore real em `android/key.properties`; o `android/app/build.gradle.kts` utiliza `signingConfigs.getByName("debug")` como fallback de assinatura quando `key.properties` não existe.

---

## 15. Problemas Conhecidos e Correções

### Ícones Material sumindo na Web — codepoint alto `0xf___` (09/07/2026)

- **Problema**: ícones não aparecem no build Web (renderizam em branco) enquanto o texto ao lado aparece normal. Ocorreu na aba **Chave de IA** do painel admin: `Icons.vpn_key_outlined` (tab), `Icons.vpn_key_rounded` (avatar), `Icons.password_rounded`, `Icons.save_rounded`, `Icons.check_circle_rounded` e `Icons.warning_rounded` ficaram invisíveis.
- **Causa raiz**: as variantes `_rounded`/`_outlined` adicionadas recentemente ao Material caem na faixa de codepoint **`0xf____`** (private use area alta). Esses glyphs **não estão na fonte `MaterialIcons` subsetada/em cache** do build web e renderizam como `notdef` (invisível). Os ícones antigos na faixa **`0xe___`** (ex.: `vpn_key`=`0xe6c7`, `visibility`=`0xe6bd`, `save`=`0xe550`, `check_circle`=`0xe159`) renderizam sempre.
- **Correção**: usar as **variantes base** (sem sufixo `_rounded`/`_outlined`) sempre que o codepoint da variante for `0xf____`. Não depende de rebuild da fonte. Ao publicar no `alinhajadev.web.app`, fazer hard-refresh (Ctrl+Shift+R) para descartar a `MaterialIcons` antiga em cache.
- **Como conferir o codepoint** (SDK): `<flutter>/packages/flutter/lib/src/material/icons.dart` → procurar `IconData <nome>`; se for `IconData(0xf...)`, trocar pela variante base `0xe___`. `flutter analyze` **não** detecta isso — o const existe, só o glyph falta na fonte.

### Workflow - Campos Emplacamento Faltando (11/05/2026)

- **Problema**: Form de emplacamento não capturava CPF/CNPJ, Modelo, Chassi e Placa
- **Correção**: Adicionados CPF/CNPJ, Modelo, Chassi, Placa e Filial ao fluxo de criação/detalhe. A coluna `workflow_cards.branch` foi adicionada pela migration `20260511001000_workflow_branch_and_operational_statuses.sql`

### Workflow - Status Final Configurado (11/05/2026)

- **Problema**: A ação "Finalizar com Anexo" forçava `Concluído`, mesmo em fluxos cujo final é `Pago`, `Emplacado`, `Faturado` ou `Finalizado`
- **Correção**: `WorkflowNotifier.completeCard()` usa o status marcado como `is_final`; se não houver, usa o último status ativo não cancelado. `updateCardStatus()` bloqueia status inexistente, exceto `Cancelado`

### Workflow - Dashboard Operacional (11/05/2026)

- **Problema**: Dashboard ainda exibia métricas de aprovação
- **Correção**: Dashboard mostra Total de Cards, Valor Total, Meus Cards, SLA Estourado e contagem por status

### Workflow - Status Intermediário (11/05/2026)

- **Problema**: Falta estado para quando operador aguarda resposta do solicitante
- **Correção**: Adicionado status "Aguardando Solicitante" ao fallback de statuses

### RBAC Workflow - Checagem Dupla (11/05/2026)

- **Problema**: Código usava `userMetadata['role']` e `roleLevel` em lugares diferentes
- **Correção**: Unificado para usar `currentUser?.roleLevel` via `currentUserProvider`

### Workflow - UI de Status (11/05/2026)

- **Problema**: `workflow_list_view.dart` mostrava string crua do status em vez do nome localized
- **Correção**: Agora usa `statusConfig.status` com cor do `statusConfig.colorValue`

- **Problema**: Campo de busca abria com espaço em branco como query
- **Correção**: Inicializado com string vazia

### Workspace - Segurança e Fluxo Operacional (12/05/2026)

- **Problema**: criação/arquivamento/exclusão de workspaces dependiam demais de bloqueios no cliente, e RPCs `SECURITY DEFINER` não validavam permissão internamente
- **Correção**: migration `20260512153000_harden_workspace_security.sql` adiciona helpers `current_user_can_create_workspace()` e `can_manage_workspace()`, restringe policies de `chats`/`chat_members`, endurece `delete_channel`, `archive_channel`, `add_channel_member` e `remove_channel_member`, e cria `create_workspace()` transacional
- **Problema**: workspace arquivado podia continuar aparecendo na listagem ou receber novos usuários via trigger
- **Correção**: `get_chats_with_preview()`, `channelsListProvider`, descoberta de canais e triggers de novos usuários ignoram `metadata.archived = true`
- **Problema**: novos cards eram atribuídos automaticamente ao primeiro admin/manager ativo, o que quebrava a fila operacional real
- **Correção**: atribuição virou configuração do canal. Em `single_operator`, o card nasce com o operador padrão; em `operator_pool`, nasce sem responsável e entra na fila de **Assumir atendimento**
- **Correção backend**: `claim_workflow_card()` passa a respeitar `operator_ids` quando o canal restringe operadores
- **Gestão**: `update_workflow_operators()` permite que `super_admin` ou criador do canal defina operador único/equipe e marque quem pode assumir cards
- **Observação**: a migration precisa estar aplicada no Supabase real para a proteção de backend valer fora do app

### Seeds de Canais - Fluxo Atual (12/05/2026)

- **Fonte única atual**: `supabase/migrations/20260512180000_unified_workflow_channel_seed.sql`
- **Correção aplicada**: `supabase/migrations/20260512181000_fix_unified_seed_conflict_target.sql` troca o `ON CONFLICT` do seed para usar a constraint explícita `workflow_status_config_channel_id_status_key`, evitando ambiguidade de `channel_id` em PL/pgSQL
- **Isolamento aplicado**: `supabase/migrations/20260512182000_isolate_workspaces_in_channels.sql` move workspaces/canais operacionais para `channels`, `channel_members` e `channel_messages`, deixando `chats`, `chat_members` e `messages` para DMs/grupos
- **Correção de seed dedicado**: `supabase/migrations/20260512183000_fix_channel_seed_member_conflict.sql` recria o seed usando `channel_members_pkey` explicitamente, evitando ambiguidade no `ON CONFLICT`
- **Função de seed**: `public.seed_base_workflow_channels(reset_statuses, preserve_operator_config)` cria/atualiza os 5 canais base, membros e status atuais
- **Função de reset**: `public.reset_operational_data(reseed_channels)` limpa dados transacionais e opcionalmente chama o seed dos canais
- **Scripts atualizados**: `supabase/scripts/create_base_channels.sql` chama a função de seed preservando operadores; `supabase/scripts/reset_and_seed_operational_data.sql` chama o reset destrutivo com reseed; `supabase/seed.sql` chama o seed após criar usuários locais
- **Metadata atual**: canais base usam `workflow_enabled`, `posting_permission`, `card_type`, `category`, `color`, `icon`, `assignment_mode`, `operator_ids`, `default_operator_id`, `operator_count` e `archived`
- **Atribuição padrão**: canais nascem em `operator_pool` com `operator_ids: []`; o `super_admin` ou criador define depois quem é operador pela tela de informações do canal
- **Reexecução segura**: `create_base_channels.sql` atualiza metadata e etapas, mas preserva operadores já configurados em `assignment_mode`, `operator_ids`, `default_operator_id` e `operator_count`
- **Reset com cuidado**: `reset_and_seed_operational_data.sql` apaga mensagens, canais, cards, reuniões, chamadas, notificações, tickets e históricos operacionais; preserva usuários e estrutura organizacional
- **Estado remoto após reset de 12/05/2026**: `channels = 5`, `channel_members = 30`, `workflow_status_config = 26`, `workflow_cards = 0`, `channel_messages = 0`; `chats` e `chat_members` ficaram zeradas para não misturar workspaces com DMs/grupos
- **FKs atuais**: `workflow_cards.channel_id` e `workflow_status_config.channel_id` referenciam `public.channels(id)`, não `public.chats(id)`
- **Fluxo operacional**: etapas usam `Aguardando Solicitante` e status finais reais (`Pago`, `Finalizado`, `Emplacado`, `Faturado`, `Arquivado`)
- **Sem aprovação**: seeds não criam mais `Aguardando aprovação`, `Aprovado` ou `Rejeitado`
- **Cancelamento**: `Cancelado` segue como ação/desvio do card, não como coluna seedada

### Pré-Build/Deploy - Ambiente e Versionamento (12/05/2026)

- **Problema**: `pubspec.yaml` estava em `1.0.0+1`, enquanto `AppConstants` indicava `1.0.2/11052026`
- **Correção**: `pubspec.yaml` atualizado para `1.0.2+11052026`
- **Problema**: Firebase Hosting permitia publicar `assets/.env`, expondo variáveis do app no web deploy
- **Correção**: removida exceção `!**/assets/.env` do `firebase.json`; produção web deve usar `flutter build web --dart-define-from-file=dart_defines.json`
- **Correção**: criado `AppEnv`, centralizando `String.fromEnvironment` com fallback local para `.env`; `main.dart`, push notifications e chamadas Agora/Supabase usam essa fonte
- **Pendência Android release**: `android/app/build.gradle.kts` utiliza chave debug como fallback na ausência de `key.properties`; antes de publicar APK/AAB externo formal, configurar keystore de produção

### Workflow - Checks Dart/Flutter Travando (11/05/2026)

- **Problema**: `dart format`, `dart --version`, `flutter --version`, `flutter analyze` e `flutter test test/workflow_provider_test.dart` ficaram presos até timeout na sessão de implementação
- **Status**: Alterações validadas por varredura textual (`rg`) e revisão dos pontos editados; próxima rodada deve investigar processos Dart/Flutter travados antes de confiar nos checks automatizados

### Web Release e PWA - Crash de Inicialização e Conflito de Service Workers (09/06/2026)

- **Problema 1 (Crash de Inicialização)**: Tela preta com erro `Null check operator used on a null value` em Web Release devido a um `Stack` em `_PushNotificationInitializer` sem um ancestral `Directionality`.
- **Correção 1**: Retornou-se diretamente o `MaterialApp.router` (removendo o `Stack` desnecessário na inicialização).
- **Problema 2 (Cache-poisoning no Chrome)**: Stale PWA service workers caching fallback pages interceptavam arquivos compilados (como `main.dart.js`) e retornavam o HTML de fallback, gerando erros `SyntaxError: Unexpected token '<'` no console do Chrome.
- **Correção 2**: Inicialização customizada do Flutter via `web/flutter_bootstrap.js` sem registrar o service worker embutido padrão. Adição de um script inline de auto-limpeza em `web/index.html` que detecta e desinscreve (unregister) qualquer service worker que não seja o `firebase-messaging-sw.js` do Firebase e limpa todos os caches antigos do navegador na primeira visita.

### Migrations Recentes

| Migration                                                          | Data       | Descrição                                                                                                                                                                                                                                                                                                              |
| ------------------------------------------------------------------ | ---------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `20260704120000_enforce_mfa_aal2.sql`                              | 04/07/2026 | **2FA real**: policy restritiva `require_aal2` em 17 tabelas de conteúdo + helper `user_has_verified_mfa()`. Exige sessão `aal2` (MFA nativo TOTP) para acessar dados; anti-lockout preserva usuários sem fator. Aplicada no projeto `gpeemngsxvqjflasdody` via MCP                                                     |
| `20260703184600_create_2fa_schema.sql`                             | 03/07/2026 | (Legado) Schema do 2FA por e-mail: `user_trusted_devices`, `user_email_otp`, RPCs `check_device_trusted`/`verify_2fa_code`. **Substituído pelo MFA nativo AAL2** — fora do fluxo ativo                                                                                                                                 |
| `20260703120000_webhook_secret_for_notification_triggers.sql`      | 03/07/2026 | Segredo de webhook para os triggers de notificação; atualizado para a URL do projeto `gpeemngsxvqjflasdody`                                                                                                                                                                                                            |
| `20260609161300_enable_notification_tables_rls.sql`                | 09/06/2026 | Habilita RLS nas tabelas `user_notification_preferences` e `user_notification_settings` e adiciona políticas de acesso próprias                                                                                                                                                                                        |
| `20260609153000_create_channel_join_requests.sql`                  | 09/06/2026 | Tabela de solicitações de entrada em canais, RLS, Realtime e trigger `handle_channel_join_request_update`                                                                                                                                                                                                              |
| `20260608131500_channel_settings_and_leave.sql`                    | 08/06/2026 | RPC `update_channel_info` e RLS para desfiliação voluntária                                                                                                                                                                                                                                                            |
| `20260602010000_simplify_user_roles.sql`                           | 02/06/2026 | Simplificação das roles de usuários e regras de privilégios                                                                                                                                                                                                                                                            |
| `20260602000000_split_matriz_and_cd.sql`                           | 02/06/2026 | Divisão física de filiais entre Matriz e Centro de Distribuição (CD)                                                                                                                                                                                                                                                   |
| `20260601010000_add_workflow_notification_trigger.sql`             | 01/06/2026 | Adiciona trigger e função de webhook assíncrono para notificação de novos cards e atribuições no Kanban (`send-workflow-notification`)                                                                                                                                                                                 |
| `20260601000000_add_callee_and_answered_by_to_calls.sql`           | 01/06/2026 | Adiciona `callee_id` (quem recebeu a chamada) e `answered_by` (quem atendeu) na tabela `calls`                                                                                                                                                                                                                         |
| `20260513190000_block_workflow_requester_operations.sql`           | 13/05/2026 | Bloqueia solicitante de operar o proprio card; recria policy de update de `workflow_cards`, endurece `update_workflow_card_status` e limita comentarios do solicitante ate status final                                                                                                                                |
| `20260513183000_enable_realtime_for_app_surface.sql`               | 13/05/2026 | Garante Supabase Realtime para mensagens, canais/workspaces, workflow, helpdesk, chamadas, usuarios, organizacao e localizacao                                                                                                                                                                                         |
| `20260513170000_enable_realtime_for_dedicated_workspaces.sql`      | 13/05/2026 | Adiciona `channel_messages`, `channel_members`, `channels` e `workflow_status_config` ao Realtime dos workspaces dedicados                                                                                                                                                                                             |
| `20260513160000_enable_meetings_in_channels.sql`                   | 13/05/2026 | Adiciona `channel_id` em `meetings` e `calls`; relaxa `chat_id` nullable em calls; atualiza RLS para aceitar `channel_members`                                                                                                                                                                                         |
| `20260513150000_fix_meetings_default_status.sql`                   | 13/05/2026 | Corrige default de `meetings.status` de `ringing` para `waiting`; corrige reuniões presas em `ringing`                                                                                                                                                                                                                 |
| `20260513120000_optimize_workspace_channels_and_notifications.sql` | 13/05/2026 | Índices de performance: `channel_members`, `channels`, `channel_messages`, `user_fcm_tokens`                                                                                                                                                                                                                           |
| `20260512185000_fix_workspace_membership_visibility.sql`           | 12/05/2026 | Insere todos usuários ativos em `channel_members` para workspaces `shineray_operations`; atualiza trigger `handle_new_user` para fazer o mesmo                                                                                                                                                                         |
| `20260512184000_fix_get_chats_with_preview_job_position.sql`       | 12/05/2026 | Corrige RPC `get_chats_with_preview` removendo coluna `job_function` que não existe mais                                                                                                                                                                                                                               |
| `20260512183000_fix_channel_seed_member_conflict.sql`              | 12/05/2026 | Corrige `ON CONFLICT` do seed dedicado de `channel_members` usando `channel_members_pkey`                                                                                                                                                                                                                              |
| `20260512182000_isolate_workspaces_in_channels.sql`                | 12/05/2026 | **Mudança arquitetural**: isola workspaces operacionais em `channels`/`channel_members`/`channel_messages`; cria RPCs `is_channel_member`, `can_manage_workspace`, `create_workspace`, `delete_channel`, `archive_channel`, `add_channel_member`, `remove_channel_member`; workflow passa a referenciar `channels(id)` |
| `20260512181000_fix_unified_seed_conflict_target.sql`              | 12/05/2026 | Corrige ambiguidade no `ON CONFLICT` do seed unificado                                                                                                                                                                                                                                                                 |
| `20260512180000_unified_workflow_channel_seed.sql`                 | 12/05/2026 | Centraliza seed/reset em `seed_base_workflow_channels` e `reset_operational_data`                                                                                                                                                                                                                                      |
| `20260512173000_manage_workflow_operators.sql`                     | 12/05/2026 | RPC `update_workflow_operators` para super_admin/criador configurar operador por canal                                                                                                                                                                                                                                 |
| `20260512170000_workflow_assignment_config.sql`                    | 12/05/2026 | `claim_workflow_card` respeita `operator_ids` e modo de atribuição por canal                                                                                                                                                                                                                                           |
| `20260512153000_harden_workspace_security.sql`                     | 12/05/2026 | Endurece segurança de workspace, `create_workspace` transacional, filtro de arquivados                                                                                                                                                                                                                                 |
| `20260512140000_fix_legacy_role_rls_policies.sql`                  | 12/05/2026 | Remove referências a roles legados `director` e `ti_admin` das políticas RLS                                                                                                                                                                                                                                           |
| `20260511001000_workflow_branch_and_operational_statuses.sql`      | 11/05/2026 | Adiciona `workflow_cards.branch`, saneia status antigos de approval                                                                                                                                                                                                                                                    |
| `20260511000000_remove_workflow_approval.sql`                      | 11/05/2026 | Remove approval_threshold, RPC approve_workflow_card                                                                                                                                                                                                                                                                   |
| `20260507000000_fase2_workflow_approval.sql`                       | 07/05/2026 | Adiciona approval_threshold + RPC approve_workflow_card + metrics (substituído)                                                                                                                                                                                                                                        |
| `20260504100001_workflow_rbac.sql`                                 | 04/05/2026 | RBAC workflow (update_workflow_card_status, approve_workflow_card)                                                                                                                                                                                                                                                     |
| `20260504100000_fix_meetings_rls.sql`                              | 04/05/2026 | RLS meetings - só manager+ cria                                                                                                                                                                                                                                                                                        |
| `20260429100000_auto_join_channels.sql`                            | 29/04/2026 | Auto-inscrever usuários em canais                                                                                                                                                                                                                                                                                      |
| `20260428100000_add_mirotalk_url_to_meetings.sql`                  | 28/04/2026 | Adiciona mirotalk_url                                                                                                                                                                                                                                                                                                  |
| `20260427162100_rpc_reset_and_reseed_data.sql`                     | 27/04/2026 | Reset + seed completo                                                                                                                                                                                                                                                                                                  |
| `004_init_fluxy_workflow_schema.sql`                               | -          | Schema inicial workflow                                                                                                                                                                                                                                                                                                |

### Fixes do Banco - 13/05/2026

#### Realtime/PWA - Superficie Principal (13/05/2026)

- **Problema**: algumas telas ainda dependiam de refresh manual ou de snapshots pesados do Realtime.
- **Correção banco**: migration `20260513183000_enable_realtime_for_app_surface.sql` garante publicacao Realtime para mensagens, workspaces, workflow, helpdesk, chamadas, usuarios, organizacao e localizacao.
- **Correção app**: `chat_provider.dart` ignora snapshot inicial e processa apenas mensagens novas/alteradas; `channels_list_provider.dart` escuta `channels`/`channel_members`; `active_channel_provider.dart` usa debounce em `channel_messages`; `card_details_sheet.dart` escuta comentarios/historico.
- **Responsividade PWA**: `message_bubble.dart` calcula largura de balao pelo espaco real do painel, evitando overflow no desktop/master-detail.

#### Workflow - Solicitante nao opera proprio card (13/05/2026)

- **Regra**: quem cria o card acompanha o fluxo, mas nao pode mover status, assumir, atribuir, fixar, arquivar, cancelar, excluir ou finalizar o proprio card.
- **Interacao final**: comentarios do solicitante no proprio card ficam bloqueados ate o card chegar em status final (`workflow_status_config.is_final = true`).
- **Correção banco**: migration `20260513190000_block_workflow_requester_operations.sql` recria policy de update de `workflow_cards`, endurece `update_workflow_card_status` e ajusta insert em `workflow_card_comments`.
- **Correção app**: `workflow_provider.dart`, `card_details_sheet.dart`, `workflow_board_view.dart`, `workflow_list_view.dart` e `workflow_compact_view.dart` removem/impedem acoes operacionais do solicitante.

#### Chamadas Web x Android - Encerramento sem congelar (13/05/2026)

- **Problema**: quando a Web encerrava uma chamada com Android, o Android podia ficar preso na tela de chamada com timer congelado.
- **Causa provavel**: o estado local aguardava `Agora.leaveChannel()` terminar antes de liberar a UI; em alguns encerramentos cross-platform esse await podia demorar/travar.
- **Correção**: `CallService.leaveChannel()` reseta o estado local antes do teardown do Agora e usa timeout em `disableAudio`, `disableVideo` e `leaveChannel`; `ActiveCallScreen` cancela timer/animação e libera `PopScope` quando `isInCall=false`.

#### MiroTalk - Percent encoding em nomes (13/05/2026)

- **Problema**: contas com `%` ou nomes/filiais com caracteres especiais podiam quebrar a rota da reuniao com `Illegal percent encoding in URI`.
- **Correção**: `router.dart` nao decodifica novamente `queryParameters` ja decodificados; `mirotalk_web.dart` e `mirotalk_mobile.dart` normalizam URLs antigas e escapam percentuais invalidos antes de abrir a reuniao.

#### Meetings - Default Status e channel_id (13/05/2026)

- **Problema**: `meetings.status` tinha default `ringing`; app esperava `waiting` ao criar reuniões
- **Correção**: migration `20260513150000` altera default para `waiting` e corrige reuniões presas
- **Novo campo**: `meetings.channel_id` (FK → `channels`) permite reuniões em workspaces operacionais; `calls.channel_id` idem
- **Constraint**: `meetings_context_check` e `calls_context_check` garantem que `chat_id` e `channel_id` sejam mutuamente exclusivos

#### Performance - Índices (13/05/2026)

- Adicionados índices em `channel_members(user_id, channel_id)`, `channels(last_message_at DESC)`, `channel_messages(channel_id, created_at DESC)`, `channel_messages(thread_id, sender_id)` e `user_fcm_tokens(user_id)`

#### Visibilidade de Workspaces - Membership (12/05/2026)

- **Problema**: após isolamento para `channels`, usuários não apareciam em `channel_members` e não viam workspaces
- **Correção**: migration `20260512185000` faz bulk-insert de todos usuários ativos em `channel_members` para workspaces `shineray_operations`; trigger `handle_new_user` atualizado para fazer o mesmo em novos cadastros

---

## 16. Segunda Auditoria de Bugs — 32 Issues Corrigidas (28/05/2026)

Após segunda análise criteriosa do código-fonte, **32 bugs** foram identificados e **29 corrigidos** em 13 arquivos. Abaixo, o resumo por gravidade.

### Críticos (4/4 corrigidos)

| #   | Arquivo                        | Problema                                                                 | Correção                                     |
| --- | ------------------------------ | ------------------------------------------------------------------------ | -------------------------------------------- |
| 1   | `chat_provider.dart`           | `Uint8List` sem import — quebra runtime em Web ao enviar mídia           | Adicionado `import 'dart:typed_data'`        |
| 2   | `call_service.dart`            | `endMeetingRoom()` sem filtro de `room_id` — encerrava TODAS as reuniões | Filtro por `metadata->>room_id` na query     |
| 3   | `active_channel_provider.dart` | `ChannelArgs.hashCode` não sobrescrito — colisão em cache                | `Object.hash()` implementado                 |
| 4   | `call_service.dart`            | Estado setado após `await` sem `mounted` — UI fantasma                   | Guarda com `mounted` antes de `_updateState` |

### Altos (8/8 corrigidos)

| #   | Arquivo                       | Problema                                                                | Correção                                 |
| --- | ----------------------------- | ----------------------------------------------------------------------- | ---------------------------------------- |
| 5   | `auth_provider.dart`          | `signIn()` sem try/catch — exceção vazava                               | try/catch com `state = AsyncValue.error` |
| 6   | `auth_provider.dart`          | `signOut()` sem `finally` — estado inconsistente em falha               | `finally` garante atualizações de estado |
| 7   | `channels_list_provider.dart` | SELECT sem `unread_count` — badge zerado                                | `unread_count` adicionado ao SELECT      |
| 8   | `channels_list_provider.dart` | Ordenação com `nullsFirst` — conversas sem última msg no topo           | Switches para `nullsFirst: false`        |
| 9   | `workflow_provider.dart`      | `createCard` match otimista por `title` — colisão com mesmo título      | Match por `id` único                     |
| 10  | `workflow_provider.dart`      | `_throwIfRequesterOperation` retornava sem lançar — operação prosseguia | Lança `Exception` real                   |
| 11  | `workflow_provider.dart`      | `addComment` sem validação de solicitante                               | Valida com `_throwIfRequesterOperation`  |
| 12  | `card_details_sheet.dart`     | `_handleCancelCard` tipado como `dynamic` — perda de tipo               | Tipado como `WorkflowNotifier`           |

### Médios (12/12 corrigidos)

| #   | Arquivo                        | Problema                                                         | Correção                    |
| --- | ------------------------------ | ---------------------------------------------------------------- | --------------------------- |
| 13  | `workflow_provider.dart`       | `cardsByStatus` incluía cancelados/arquivados                    | Exclui ambos                |
| 14  | `workflow_provider.dart`       | `getFilteredCards` inconsistente com `cardsByStatus`             | Sincronizado                |
| 15  | `workflow_provider.dart`       | `togglePin` sem `orElse` — crash se card inexistente             | `orElse: () {}`             |
| 16  | `workflow_provider.dart`       | `_isFetching` ausente em `loadCards` — race condition            | Guard com `_isFetching`     |
| 17  | `workflow_provider.dart`       | `_updateOptimisticProgress` sobrescrevia metadata                | Preserva metadata existente |
| 18  | `chat_provider.dart`           | `_membersSub` sem `onError` — subscription morta silenciosamente | `onError` com log           |
| 19  | `active_channel_provider.dart` | Primeiro evento Realtime descartado                              | Processa evento normalmente |
| 20  | `active_channel_provider.dart` | Cache de usuários podado a cada subscribe                        | Mantém cache                |
| 21  | `presence_service.dart`        | `_goOffline()` disparado sem await — corrida de lifecycle        | Sequencial com await        |
| 22  | `presence_service.dart`        | `_isTracking` setado após subscribe — race                       | Setado antes do subscribe   |
| 23  | `card_details_sheet.dart`      | `_completeWithAttachment` validava permissão após upload         | Permissão checada antes     |
| 24  | `card_details_sheet.dart`      | Null role (`roleLevel == null`) elevava privilégios              | Bloqueia se null            |

### Baixos (5/8 corrigidos)

| #   | Arquivo                  | Problema                                                        | Correção                  |
| --- | ------------------------ | --------------------------------------------------------------- | ------------------------- |
| 25  | `workflow_provider.dart` | `_isAllowedStatus` case-sensitive                               | Case-insensitive          |
| 26  | `mirotalk_service.dart`  | `joinMeetingRoomDirect` sem `mounted`                           | Seta estado só se mounted |
| 27  | `sync_service.dart`      | Tipos desconhecidos travavam o processador                      | `else` ignora sem erro    |
| 28  | `mirotalk_service.dart`  | URLs de fallback sem encoding                                   | `Uri.encodeComponent`     |
| 29  | `permissions.dart`       | Faltavam helpers `canOperateWorkflowCard` e `canManageWorkflow` | Adicionados               |

### Não corrigidos (3/32) — aceitos como risco

| #   | Arquivo                                                 | Motivo                                                                                               |
| --- | ------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| 3   | `lib/core/globals.dart` (Web `onBeforeUnload`)          | Mitigado por smart presence (5-min threshold) — `sendBeacon` complexidade injustificada              |
| 22  | `channels_list_provider.dart` (subscription sem filtro) | Filtro de usuário existente em `channel_members` — subscription ampla intencional para novos membros |
| 28  | `login_screen.dart` (`Future.delayed(500ms)`)           | Aguarda `addPostFrameCallback` resolver — risco baixo de frame perdido                               |

---

## 17. Rebranding Completo e Transição de Infraestrutura (22/05/2026)

Para consolidar o projeto como portfólio profissional e apresentação oficial para clientes, toda a plataforma foi migrada da identidade legada **"Chat BySabel"** para a nova marca **"Fluxy"**, saneando e otimizando a infraestrutura de hospedagem.

### 1. Refatoração e Rebranding no App (Flutter)

- **Nome do Pacote**: Atualizado no `pubspec.yaml` de `chat_bysabel` para `fluxy` (versão `1.0.4+13052026`).
- **Imports e Classes**: Todos os arquivos `.dart` foram atualizados para importar `package:fluxy/...` em vez de `package:chat_bysabel/...`. Todas as classes e variáveis foram atualizadas com o novo nome (ex: `FluxyApp`).
- **Arquivos IntelliJ/IDE**: Renomeados arquivos de módulos nativos (`chat_bysabel.iml` -> `fluxy.iml` e `android/chat_bysabel_android.iml` -> `fluxy_android.iml`) e atualizado `.idea/modules.xml` para garantir compatibilidade da IDE com a nova estrutura de pastas.
- **Identidade Android**: Namespace e `applicationId` atualizados de `com.bysabel.chat` para `com.fluxy.app` em `build.gradle.kts` e sincronizados em `MainActivity.kt`.
- **Validação Estática**: Executado `flutter clean`, `flutter pub get` e `flutter analyze` retornando **0 erros e 0 warnings**, atestando compilação 100% íntegra.

### 2. Configurações de Banco de Dados (Supabase)

- **Contas Administrativas e Triggers**: E-mails corporativos ajustados de `@shineraybysabel.com.br` para `@shinerayfluxy.com.br`.
- **Bot do Sistema**: Nome alterado de `BySabel Bot` para `Fluxy Bot` (e-mail `bot@fluxy.com.br`).
- **Seed de Testes (`seed.sql`)**: Saneado por completo com novos e-mails da marca para permitir reseed local limpo.

### 3. Infraestrutura de Hospedagem (Firebase Hosting Multisite)

- **Domínios e Múltiplos Sites**: Configurado o Firebase Spark Multisite para hospedar sub-sites independentes sob o mesmo ID técnico do console do Google (`chat-bysabel`):
  - **Landing Page**: Hospedada em `https://fluxy-landing.web.app` (mapeada no target `landing`).
  - **App Web**: Hospedada em `https://fluxy-app.web.app` (mapeada no target `app`).
- **Redirecionamento Automático 301**: Adicionado o target `legacy` em `.firebaserc` (apontando ao domínio original `chat-bysabel`). Configurado no `firebase.json` uma regra que intercepta todo o tráfego das URLs antigas (`chat-bysabel.web.app` e `chat-bysabel.firebaseapp.com`) e o redireciona permanentemente (HTTP 301) para a nova Landing Page oficial em `https://fluxy-landing.web.app`.
- **Ligação de URL**: Atualizado `App.jsx` na Landing Page para apontar o link "Acessar Web" diretamente para `https://fluxy-app.web.app` e recompilado o bundle em `landing-page/dist/`.

---

## 18. Auditoria Final — Estabilidade Fase 3 (28/05/2026)

Após varredura completa de 103 arquivos .dart, schema Supabase (35 migrations), build/config e integrações, **~300 issues** foram identificadas e corrigidas em 43+ arquivos. Abaixo os blocos de correção:

### Tratamento de Crashes (Grupo A)

- **Correção de Bang Operators**: 7 operadores `!` substituídos por `?? ''` em `router.dart`.
- **Rotas Seguras**: Adição de redirecionamentos para `/chats` e `NewDmRedirectScreen`.
- **Singleton Callbacks**: Migração para `_onRemoteUserJoinedListeners` no `call_service.dart`.
- **Segurança Async**: Checagem dupla de `mounted` em todas as rotas e estados após await.

### Performance UI e Consultas (Grupo B)

- **Otimização de Query**: `active_channel_provider.dart` passou de `.select('*')` para lista explícita de colunas.
- **Merge Inteligente**: Realtime de conversas processa incrementais em vez de recarga total.
- **Client-Side Sorting**: Ordenação de mensagens em tempo real via Dart, poupando CPU do Postgres.

### Configurações Android e Build (Grupo C)

- **Build**: Downgrade de Kotlin `2.2.20` para `1.9.24` por instabilidade e ajustes em `AndroidManifest.xml` para ícone único.
- **Config**: Remoção de `.env` dos assets para segurança.

### Schema e Segurança (Grupo D)

- **Migrations**: Adição de `starred_messages`, RPCs de gestão de usuários e coluna `unread_count`.
- **Autenticação**: Ajuste de senhas default para criação de usuários com exibição de dialog.

---

## 19. Refinamentos Técnicos de Infraestrutura, Notificações e Canais (29/05/2026)

### 1. Suporte e Renderização de Mídias

- **UI Imersiva**: Fotos com `InteractiveViewer`, vídeos inline nativos e players de áudio deslizantes.
- **Semântica Corporativa**: Selos automáticos para "ORDEM DE SERVIÇO" (Laranja) e "FINANCEIRO" (Verde Esmeralda).

### 2. Notificações Push via Database Triggers

- **Reatividade**: Fim do envio via Flutter; triggers `AFTER INSERT` no PostgreSQL garantem disparos instáveis.
- **Economia de Recursos**: Isolate de background lê cache local (`SharedPreferences`) para regras de DND.

### 3. Chamadas Agora.io 1:1

- **Edge Function**: Tokenização JWT no `get-agora-token` para maior segurança.
- **Confiabilidade**: Teardown robusto com flag `_hasPopped` e isolamento de erros via `try/catch`.

### 4. Performance Estática

- **Hive Cache**: Suporte a mensagens offline e upload progressivo.
- **Prevenção de N+1**: Carregamento em lote de metadados de remetente.
- **Cache Híbrido Hive + Drift**: Hive para runtime de mensagens offline; Drift (`LocalMessages`) para backup sincronizado com Supabase; Drift (`MediaCache`) para metadados de cache de mídia com LRU.
- **Validação Final**: `flutter analyze` retornando 0 erros e 0 warnings.

---

## 20. Refinamento Técnico e Otimização da Landing Page PWA (29/05/2026)

Focando no refinamento estético, performance móvel, segurança e acessibilidade da porta de entrada do ecossistema Fluxy (em `landing-page/`), implementamos melhorias robustas de ponta a ponta:

### 1. Migração e Tipagem Estrita TypeScript (Vite + React)

- **Migração Completa**: Renomeação de todos os arquivos principais de JavaScript para TypeScript (`App.tsx`, `main.tsx`, `vite.config.ts`), eliminando tipagens dinâmicas e vulnerabilidades ocultas.
- **Configuração de Compilação**: Provisionado `tsconfig.json` e `tsconfig.node.json` estruturados, com regras estritas (`strict: true`, `noUnusedLocals: true`, etc.).
- **Compatibilidade Global de Assets**: Criado `vite-env.d.ts` garantindo suporte de compilação automática para side-effect de imports CSS e extensões de imagem (`.png`), obtendo **0 erros de compilação estática** (`npx tsc --noEmit`).

### 2. Otimização de GPU e Performance Mobile (Save GPU)

- **Detecção de Hardware Reativa**: Hook responsivo (`checkPerformanceMode`) combinando largura de tela (`innerWidth < 768`) e suporte de toque físico (`pointer: coarse`).
- **Desativação Inteligente**: Acoplada a classe CSS `.reduce-effects` à raiz do background animado, desativando transições de transform/filter pesadas, partículas flutuantes e feixes de luz dinâmicos (rays), substituídos por um degradê estático leve.

### 3. Acessibilidade e Transição de Temas (Light/Dark Mode)

- **Alternador de Tema Intuitivo**: Botão de toggle interativo (Sun/Moon) integrado ao cabeçalho (Navbar).
- **Persistência Local**: Tema salvo no `localStorage` do navegador para respeito imediato à preferência do usuário em visitas recorrentes.
- **Mapeamento HSL Adaptativo**: Cores semânticas e painéis em vidro adaptados no `index.css` via `:root.light`, mantendo o contraste legível em ambos os modos.

### 4. Captação de Leads e Prova Social (Geração de Demanda)

- **Seção de Depoimentos Premium**: Grade interativa e refinada com casos reais de equipe de logística, operações e TI (prova social).
- **Formulário de Leads Corporativo**: Componente com validação reativa e estrita de e-mails corporativos (rejeitando Gmail, Hotmail, etc.), validação de telefones DDD e seleção de tamanho da equipe.
- **Animações de Sucesso**: Feedback imersivo via `AnimatePresence` do Framer Motion exibindo selos animados pós-envio.

### 5. Distribuição Confiável do APK e Analytics

- **Redirecionamento Inteligente de APK**: Mantivemos o link relativo `/fluxy.apk` na Landing Page para manter a URL limpa sob o domínio corporativo. No entanto, como o **Firebase Spark Plan** bloqueia uploads diretos de executáveis `.apk`, configuramos uma regra de redirecionamento 302 no `firebase.json` do target `landing`. Esta regra intercepta requisições para `/fluxy.apk` e as redireciona de forma transparente e instantânea para o arquivo hospedado de forma segura no **Google Drive**, garantindo 100% de disponibilidade, economizando espaço de armazenamento no Supabase e contornando o bloqueio sem alterar uma única linha de código da landing page.
- **CTA Analytics**: Helper `trackEvent` acoplado a todos os cliques em botões de ação e CTAs importantes (acesso Web, download APK e formulários), permitindo acompanhamento unificado das taxas de conversão de leads.

---

## 21. Gestão de Grupos Estilo WhatsApp, Gravador de Áudio, Moderação e Notificações de Chamadas (29/05/2026)

Implementamos um pacote técnico focado na experiência de usuário móvel, estabilidade de banco de dados e roteamento de rede, entregando quatro melhorias fundamentais:

### 1. Gestão de Grupos Estilo WhatsApp (admingroup Desacoplado)

- **Desacoplamento de Roles**: Adicionada a coluna `admingroup BOOLEAN NOT NULL DEFAULT false` na tabela `chat_members` do Supabase. Os privilégios administrativos dos grupos de conversas foram 100% isolados das permissões globais de sistema (`role_level` de TI/Administradores de filiais).
- **Camada de Banco (RPCs Seguros)**: Desenvolvemos e executamos uma migração SQL transacional (`20260529194000_group_management_rpcs.sql`), implementando os procedimentos de segurança de criação (`create_group_chat`), adição de membros (`add_group_member`), expulsão (`remove_group_member`), atualização de metadados (`update_group_info`) e gestão de privilégios (`set_group_member_role`).
- **Interface Dinâmica & Edição**: Admins do grupo agora veem botões de edição ao lado do nome e da descrição no painel de informações do grupo. Alterações salvam via RPC seguro e disparam notificações de sistema em tempo real na conversa.
- **Upload de Imagem Comprimida**: Integrado overlay de câmera e seleção de novas fotos de perfil de grupo para admins, utilizando o `MediaService` para aplicar compressão WebP client-side nativa (Mobile) ou Canvas API (Web) antes do upload ao bucket `chat-media`.
- **Adição de Participantes**: Desenvolvida lista de contatos que filtra de forma reativa usuários do sistema que ainda não participam daquele grupo específico, permitindo pesquisa textual e adição rápida.
- **Ações de Membros (Promover/Remover)**: Criado painel inferior (Bottom Sheet) contextual ativado ao tocar em qualquer participante do grupo, permitindo promover a admin, demover, expulsar ou iniciar DMs diretas de forma instantânea.

### 2. Gravador de Áudio Reconstruído (Hold & Tap Triggers)

- **Suporte a Gestos**: MessageInput agora aceita gravação dupla: com um toque simples (clicar para iniciar, clicar para parar e enviar) ou por pressão contínua (segurar para gravar, soltar para enviar).
- **Feedback Pulsante**: A barra de escrita é substituída durante o gravação por um cronômetro digital vermelho (`0:00`) e um ícone de microfone vermelho que oscila continuamente de escala e opacidade.
- **Lixeira de Descarte**: O botão de anexo (+) à esquerda do campo de texto transforma-se em um ícone de lixeira vermelha durante a gravação, possibilitando descartar o áudio gravado e excluir fisicamente o arquivo temporário de cache local sem enviar nada.

### 3. Moderação de Canais sem Travamentos e Responsivo

- **Correção de Relacionamento (PGRST200)**: Trocada a query interna no `moderationChannelsProvider` de `member_count:chat_members(count)` para `member_count:channel_members(count)` na tabela `channels`. Isso solucionou o erro de banco de dados Postgrest join relation que causava crash total na listagem de canais administrativos.
- **Cartões de Mensagens Modificados**: Nova interface baseada em blocos limpos, com balões internos sombreados para leitura confortável, badges indicando a sala de origem, metadados do remetente e botões de ações diretos ("Excluir" e "Advertir").
- **Responsividade Widescreen**: As abas administrativas foram envolvidas na diretiva `ResponsiveWidthContainer` para centralizar a grade e limitar a largura máxima em resoluções widescreen/web, evitando esticamentos desagradáveis da interface.

### 4. Correção de Chamadas em Segundo Plano no Android (FCM "HIGH" Priority)

- **FCM v1 Android Priority**: Corrigida a prioridade de envio de `'high'` para `"HIGH"` (em letras maiúsculas) sob `messagePayload.message.android.priority` em conformidade estrita com o protocolo do Firebase Cloud Messaging v1, garantindo o bypass do Doze Mode do Android em chamadas em segundo plano.
- **caller_id nos Metadados**: Injetada a chave `caller_id` dentro do payload de dados das Edge Functions de sinalização para garantir o recebimento e mapeamento instantâneo do CallKit local.
- **Bypass de Silenciamento**: Reprogramada a inicialização isolada de background (`firebaseMessagingBackgroundHandler`) no `PushNotificationService` para interceptar os eventos de ligação e forçar o som nativo, contornando qualquer filtro de silenciamento ou DND ativo para mensagens textuais tradicionais.

---

## 22. Otimização e Correção de Reatividade no Kanban de Canais (01/06/2026)

- **Causa do Problema**: Ao abrir um canal de workflow, a interface inicia na aba "Conversa" (index 0). Quando o usuário alternava para a aba "Workflow" (index 1), o botão flutuante "Novo Card" (FAB) não aparecia até que alguma ação forçasse uma reconstrução da tela (como entrar na tela de informações do canal e retornar). Isso ocorria porque o `TabController` em `WorkflowMainView` mudava seu índice internamente, mas por não possuir um listener registrado chamando `setState()`, o widget pai não rebuildava e não avaliava a mudança de aba para exibir o FAB.
- **Resolução**:
  - Adicionado `_tabController.addListener(_handleTabSelection)` no método `initState()` de `WorkflowMainView`.
  - Desenvolvida a função `_handleTabSelection()` executando `setState(() {})` de forma segura sempre que a aba do canal mudar.
  - Realizada a remoção preventiva do listener em `dispose()` (`_tabController.removeListener(_handleTabSelection)`).
- **Resultado**: Ao trocar de aba, o botão de criar novos cards e todas as ações no AppBar (como filtros e visualizações) agora atualizam-se de forma **instantânea** e 100% reativa.

---

## 23. Resolução da Vulnerabilidade de Acesso com Tela Bloqueada no Android (01/06/2026)

- **Problema de Segurança**: Quando um usuário recebia e atendia uma ligação de voz/vídeo com a tela do celular bloqueada, o app ativava a flag de janela `showWhenLocked` na `MainActivity` para desenhar a tela de chamada ativa (`ActiveCallScreen`) por cima do lockscreen do sistema. No entanto, se o usuário utilizasse o recurso de minimizar a chamada para o modo miniatura/PiP dentro do app, o layout de fundo da aplicação (com todos os chats, canais operacionais e dados administrativos) tornava-se visível e plenamente interativo, permitindo acesso total e não autorizado ao sistema sem qualquer inserção de credenciais de desbloqueio.
- **Resolução Implementada**:
  - **Mapeamento de Estado do Keyguard**: Criamos a funcionalidade `isDeviceLocked` na `MainActivity.kt` nativa através do MethodChannel (`com.fluxy.app/lockscreen`), expondo o estado real do bloqueio de tela do dispositivo através da API `KeyguardManager.isKeyguardLocked`.
  - **Serviço de Comunicação**: Mapeamos a função correspondente `LockscreenService.isDeviceLocked()` no ecossistema Dart/Flutter.
  - **Intercepção e Validação de Minimização**: No componente centralizador de chamadas `CallOverlayWrapper`, adicionamos validações assíncronas tanto para a ação de clique no ícone "Minimizar" quanto para o acionamento do botão físico de retorno (voltar) do Android. Se o dispositivo estiver bloqueado, o app executa `LockscreenService.requestUnlock()`, invocando o diálogo de segurança nativo do Android (PIN/Padrão/Biometria). A minimização e a revelação do app em segundo plano só prosseguem após o sucesso desta autenticação.
  - **Revogação Reativa das Window Flags**: Ajustamos o `ActiveCallScreen`. Caso a chamada seja instanciada ou movida para o modo miniatura (`widget.isMiniature == true`), o app revoga imediatamente o privilégio de sobreposição de lockscreen executando `LockscreenService.setCallScreenVisible(false)`. Isso faz com que, caso o celular seja bloqueado com a chamada em miniatura, a aplicação inteira seja instantaneamente blindada atrás da tela de bloqueio padrão do SO.
- **Resultado**: A segurança do sistema foi plenamente restabelecida. O aplicativo agora opera de forma blindada e 100% em conformidade com as diretrizes de segurança móvel corporativa, garantindo que conversas e dados corporativos sensíveis permaneçam inacessíveis sem autenticação prévia.

---

## 24. Lista de Contatos Agrupada por Filial/Departamento e Indicador de Presença no Canto Direito (01/06/2026)

- **Melhoria de UI/UX de Contatos**:
  - **Agrupamento Duplo Premium**: A tela de seleção de contatos (`new_chat_screen.dart`) foi totalmente reconstruída estruturando a exibição em **Filial (Branch) -> Departamento (Department) -> Colaborador**. O design utiliza cards expandíveis arredondados e elegantes com sombras suaves e contadores integrados nos cabeçalhos, resolvendo o problema de sobrecarga de informações visuais.
  - **Indicador de Presença no Canto Direito**: Adicionado um indicador visual discreto, posicionado na extremidade direita do card de contato (à esquerda do checkbox). Se o usuário estiver **Online**, exibe um ponto verde brilhante com um efeito pulsante/glowing shadow (`AppConstants.success` com opacity); caso contrário, mostra um ponto neutro discreto. Adicionado tooltip informando o status textual ("Online" / "Offline").
  - **Reaproveitamento de Presença**: O sistema de presença foi acoplado à sinalização reativa e em tempo real em background que observa `onlineUsersProvider` e `isActuallyOnline` via Supabase Realtime (a mesma engine altamente precisa já estabelecida no feed de DMs).
  - **Comunicação Aberta**: Removemos restrições de visibilidade no `users_provider.dart`, permitindo rede aberta com liberdade de comunicação entre todas as filiais e cargos do ecossistema corporativo.
  - **Análise de Estabilidade**: Validado estaticamente via `flutter analyze` com **0 erros** no projeto.

---

## 25. Correções de Auditoria, Registro de Chamadas, Build e Deploy Final v1.0.9 (01/06/2026)

### 1. Auditoria de Código — 6 Bugs Confirmados e Corrigidos

Após varredura de 140+ arquivos .dart, 113 issues candidatas foram identificadas. Re-auditoria manual confirmou **6 bugs reais**, todos corrigidos:

|  Gravidade  | Arquivo                                            | Problema                                                                                        | Correção                                                        |
| :---------: | -------------------------------------------------- | ----------------------------------------------------------------------------------------------- | --------------------------------------------------------------- |
| **Crítico** | `employee_management_screen.dart`                  | Tela de cadastro/edição de funcionários sem guarda RBAC — qualquer usuário logado podia acessar | Adicionado `AppPermissions.canAccessAdmin()` no build           |
| **Crítico** | `user_management_tab.dart`                         | Promoção de `super_admin` para `admin` sem validação — `canAssignSuperAdmin()` retornava false  | Adicionado `canAssignSuperAdmin()` nas ações de role            |
|  **Alto**   | `router.dart` + `globals.dart`                     | Rotas de admin sem guards — `_adminRouteGuard` e `_supportAdminRouteGuard` inexistentes         | Adicionados guards com cache síncrono de role em `globals.dart` |
|  **Médio**  | `active_call_screen.dart`                          | Timeout de 30s do lockscreen era ignorado — app ficava preso na tela de chamada                 | Timeout retorna `false` e libera `PopScope`                     |
|  **Médio**  | `channels_list_provider.dart`                      | `channelsSub` sem filtro de usuário logado — vazamento de dados                                 | Removido `channelsSub`, filtrado apenas `membersSub`            |
|  **Médio**  | `sync_service.dart` + `offline_cache_service.dart` | Fila offline sem limite de retry — loop infinito                                                | Máximo de 5 retries + `updateOperation()` para status           |

### 2. Correção do Registro de Chamadas (Call History)

Quadro de 4 bugs no fluxo de chamadas 1:1 — **3 corrigidos imediatamente**, 1 via migration + Edge Function:

|  #  | Arquivo                            | Problema                                                                                                     | Correção                                                                                                                           |
| :-: | ---------------------------------- | ------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------- |
|  1  | `call_service.dart`                | `endCall` usava `missed` como fallback genérico — chamadas atendidas eram registradas como perdidas          | `endCall` aceita `CallEndReason`; só usa `missed` se duração < 3s                                                                  |
|  2  | `call_service.dart`                | `startCall` não registrava `callee_id` — impossível saber quem recebeu                                       | Adicionado `callee_id` no insert                                                                                                   |
|  3  | `call_service.dart`                | `endCall` não setava `answered_by` — impossível saber quem atendeu                                           | Setado `answered_by` quando `callEndReason == answered`                                                                            |
| 3b  | `chat_app_bar.dart`                | `calleeId` não era passado nas chamadas de áudio/vídeo                                                       | Passado `calleeId` nas chamadas de DM                                                                                              |
|  4  | Supabase migration + Edge Function | `send-call-notification` não suportava canais (apenas DMs) — notificações de chamada em workspaces quebradas | Migration `20260601000000` adiciona `callee_id` e `answered_by`; Edge Function atualizada para buscar membros em `channel_members` |

### 3. Verificação da Seção 24 (Contatos + Presença)

- `new_chat_screen.dart`: agrupamento Filial → Departamento → Colaborador confirmado funcional
- Indicador de presença pulsante no canto direito com `AppConstants.success` — funcional
- `users_provider.dart`: rede aberta sem restrições de filial/cargo — funcional
- `flutter analyze`: **0 erros**

### 4. Build e Deploy Final v1.0.9

| Etapa                             | Status | Detalhes                                                         |
| :-------------------------------- | :----: | :--------------------------------------------------------------- |
| `pubspec.yaml`                    |   ✅   | Versão `1.0.9+01062026`                                          |
| `constants.dart`                  |   ✅   | `appVersion = '1.0.9'`, `appBuild = 1062026`                     |
| `flutter pub get`                 |   ✅   | Dependências resolvidas                                          |
| `flutter analyze`                 |   ✅   | **0 erros**, 26 warnings/info preexistentes                      |
| Build Web                         |   ✅   | Compilado sem erros                                              |
| Firebase Deploy (hosting:app)     |   ✅   | **https://fluxy.web.app** 🚀                                     |
| Build Android (split-per-abi)     |   ✅   | 3 APKs (armeabi-v7a: 80,8MB, arm64-v8a: 100,7MB, x86_64: 88,1MB) |
| Firebase Deploy (hosting:landing) |   ✅   | **https://fluxy-landing.web.app** 🚀                             |
| Landing Page URL                  |   ✅   | Botão "Acessar Web" corrigido para `https://fluxy.web.app`       |

### 5. Status das Edge Functions no Supabase

| Função                       |        Status        | Notas                                          |
| ---------------------------- | :------------------: | ---------------------------------------------- |
| `get-agora-token`            |       ✅ Ativa       | Retorna 401 (exige JWT) — tokens seguros Agora |
| `send-chat-notification`     |       ✅ Ativa       | Push de mensagens DMs/grupos via trigger DB    |
| `send-call-notification`     |    ✅ Ativa (v13)    | Push de chamadas 1:1, suporta `channel_id`     |
| `send-workflow-notification` | ❌ **Não deployada** | Envia push de cards atribuídos/urgentes        |
| `webhook-receiver`           | ❌ **Não deployada** | Endpoint para bots externos (opcional)         |

### 6. Pendências

- **`send-workflow-notification`**: deployada (confirmado em 20/08/2026)
- **`webhook-receiver`**: deployada (confirmado em 20/08/2026)
- **Agora Certificate**: verificar `AGORA_APP_CERTIFICATE` no painel Supabase (não verificado remotamente)
- **Migrations**: executar `npx supabase db push` para garantir sync completo com remoto (CLI local não está autenticada)

---

## 26. Controle de Entrada em Canais, Inicialização PWA e Responsividade (09/06/2026)

### 1. Fluxo de Entrada em Canais (Join Requests)

- **Objetivo**: Garantir que canais operacionais e restritos não possam ser acessados livremente. Qualquer usuário pode visualizar a existência de canais, mas deve solicitar acesso para poder ler e postar.
- **Modelo de Banco (Supabase/Postgres)**:
  - Tabela `channel_join_requests` registra solicitações com chave estrangeira para `channels` e `users`.
  - Status possíveis: `pending` (aguardando revisão) e `approved` (aprovado).
  - Política RLS: Usuários autenticados podem submeter (`INSERT`) e consultar (`SELECT`) suas próprias solicitações. Administradores do canal e administradores globais possuem controle total (`ALL`) para visualizar, aprovar ou remover solicitações.
  - Trigger do Banco (`handle_channel_join_request_update`): Quando o status de uma solicitação é atualizado para `'approved'`, o trigger cria automaticamente uma entrada na tabela `channel_members` para o solicitante com papel (`role`) `viewer`, concedendo-lhe acesso imediato ao canal.
  - A rejeição de solicitações é tratada removendo o registro da tabela (via `DELETE`), o que permite que o colaborador solicite entrada novamente no futuro caso precise.
  - Habilitada reatividade completa via Supabase Realtime na tabela `channel_join_requests`.
- **Fluxo no Cliente (Dart/Flutter)**:
  - **Pesquisa de Canais (`ChannelDiscoveryScreen`)**: Usuários comuns visualizam todos os canais e o status da solicitação. Botões mudam contextualmente entre:
    - _Solicitar Entrada_: Cria uma solicitação pendente no banco.
    - _Pendente_ (desabilitado com ícone de ampulheta): Aguardando aprovação.
    - _Participando_ (desabilitado): Se já for membro do canal.
    - _Refazer Solicitação_: Se foi recusado anteriormente (deletado do banco), o botão volta a ficar ativo para permitir nova submissão.
  - **Moderação de Entrada (`ChannelInfoScreen`)**: Admins do canal/workspace e administradores globais visualizam uma aba ou seção de "Solicitações de Entrada" com a listagem em tempo real e botões rápidos de "Aprovar" (atualiza para `'approved'`) e "Recusar" (deleta o registro).

### 2. Responsividade Completa no Dashboard de Canais

- **Dashboard (`ChannelsTab`)**: Totalmente redesenhado para suportar qualquer tamanho de tela sem overflows ou distorções visuais:
  - **Layout Mobile (largura < 600px)**: Exibição em lista de cartões horizontais densos (`_WorkspaceCardMobile`). O layout horizontal otimiza telas estreitas ao dispor o ícone temático à esquerda, o título e badge de categoria no meio, e badges de mensagens não-lidas/data à direita.
  - **Layout Tablet (600px <= largura < 800px)**: Grade responsiva de 2 colunas com limites de largura definidos (`maxCrossAxisExtent: 300`, `mainAxisExtent: 170`).
  - **Layout Desktop/Widescreen (largura >= 800px)**: Grade fluida de 3 a 4 colunas (`maxCrossAxisExtent: 360`, `mainAxisExtent: 180`) para preenchimento harmônico de grandes monitores.
  - **Estilo Visual**: Cores HSL premium, gradientes baseados nas cores dos workspaces, feedback tátil e bordas brilhantes dinâmicas quando há novas mensagens não-lidas no canal.

### 3. Ajustes de Inicialização do Web Release & Resolução de Caching PWA (Chrome)

- **Crash de Inicialização**: Removido widget `Stack` na raiz de `_PushNotificationInitializer` (em `lib/app.dart`), que gerava exceções de direcionalidade no motor Web do Flutter em release.
- **Resolução do Cache-Poisoning no Chrome**:
  - Substituição do carregador padrão do Flutter pelo script otimizado `web/flutter_bootstrap.js`, desabilitando o registro do Service Worker nativo embutido do Flutter para evitar conflitos de cache e warnings de timeout.
  - Inclusão de um script de auto-limpeza em `web/index.html` que detecta dinamicamente qualquer Service Worker ativo que não pertença ao Firebase Cloud Messaging (`firebase-messaging-sw.js`). O script desinstala (unregister) workers conflitantes obsoletos e limpa todo o cache local de arquivos do navegador, forçando um recarregamento limpo das rotas e scripts JS na primeira visita.

---

## 27. Popup de Solicitação de Acesso, Diálogo de Adição Avançado e Controle de Versão Forçado (09/06/2026)

### 1. Popup de Notificação para Solicitação de Entrada

- **Requisito**: Notificação instantânea em tempo real diferenciada de mensagens de chat comuns.
- **Implementação (`push_notification_service.dart`)**:
  - Registro de um canal `public:channel_join_requests` escutando eventos de `INSERT` com status `'pending'`.
  - Ao detectar a inserção, busca dinamicamente o nome do solicitante, avatar e o nome do canal.
  - Renderização de um **OverlayEntry** animado na interface (estilo Amber/Orange Amber gradient) exibindo os dados e dois botões rápidos:
    - **Aprovar**: Atualiza o status para `'approved'` no Supabase (o que dispara o trigger Postgres de inclusão automática em `channel_members`).
    - **Recusar**: Deleta o registro de solicitação no banco, permitindo reenvio futuro pelo usuário.
    - Ao tocar na notificação, redireciona o usuário para `/channel/:id/info`.
  - Liberação do listener no método `dispose()` do serviço de push.

### 2. Painel de Adição de Membros Avançado para Admins

- **Requisito**: Substituir a inclusão direta simples por uma lista com filtros, pesquisa e seleção múltipla.
- **Implementação (`channel_info_screen.dart`)**:
  - Utilização de um diálogo reativo com `StatefulBuilder`.
  - **Barra de Pesquisa**: Campo de texto que filtra localmente por nome ou email dos contatos do sistema.
  - **Filtros Organizacionais**: Seletores suspensos (`DropdownButtonFormField`) de Filial (Matriz/CDs) e Departamento (Setor) para filtragem granular rápida.
  - **Seleção Múltipla**: Caixa "Selecionar todos" que seleciona/desmarca em lote todos os contatos filtrados visíveis na tela.
  - **Inclusão em Lote**: Ao confirmar, o app executa em paralelo (`Future.wait`) as inserções de membros no banco através da RPC `add_channel_member`, oferecendo feedback único de sucesso.

### 3. Controle de Versão Forçado e Invalidação de Cache

- **Requisito**: Clientes em versões desatualizadas não devem operar e devem atualizar imediatamente para evitar inconsistências.
- **Implementação (`app.dart`)**:
  - Um timer periódico (a cada 10 minutos) e no início consulta `version.json` (no web de forma relativa, no mobile via link absoluto `https://fluxy.web.app/version.json`).
  - Se a versão diferir da constante local `AppConstants.appVersion`, a variável `_forceUpgradeRequired` é ativada.
  - O `build` principal do `MaterialApp` é interceptado, exibindo uma tela bloqueante em tela cheia informando sobre a atualização obrigatória.
  - Botões de ação com comportamento específico:
    - **Web**: Invoca via `dart:js` a função global `clearFlutterCaches` e recarrega a página (`location.reload`), limpando o cache persistente.
    - **Mobile (Android/iOS)**: Redireciona o usuário para a Landing Page (`https://fluxy-landing.web.app`) via `url_launcher` para que possa baixar o APK atualizado.

---

## 28. Correções de Layout, Sincronismo de Canal e Crash ao Excluir (09/06/2026)

### 1. Correção de Layout e Responsividade na Aba de Canais (`channels_tab.dart`)

- **Problema**: Sobreposição visual do botão central de "Descobrir Canais" e do Floating Action Button (FAB) "Novo Fluxo" em telas estreitas (como a barra lateral em desktops).
- **Ajuste**:
  - O Floating Action Button (FAB) passa a ser ocultado dinamicamente caso a lista filtrada de canais esteja vazia.
  - Quando a lista estiver vazia e a busca sem filtros, ambos os botões ("Descobrir Canais" e "Novo Fluxo") são renderizados juntos e centralizados dentro de um widget `Wrap`, adaptando-se de forma limpa a qualquer tamanho de painel lateral sem sobreposições.

### 2. Sincronismo de Canais em Tempo Real (`channel_create_screen.dart`)

- **Problema**: Ao retornar à lista principal após criar um canal, a listagem não exibia o novo workspace imediatamente, forçando o usuário a reiniciar/recarregar a página manualmente.
- **Ajuste**: Inclusão de `ref.invalidate(channelsListProvider)` logo após o retorno de sucesso do RPC `create_workspace`, atualizando reativamente a listagem local em cache de imediato.

### 3. Prevenção de Crash (Tela Preta) ao Excluir/Arquivar Canal (`channel_info_screen.dart` e `workflow_main_view.dart`)

- **Problema**: A exclusão/arquivamento físico do canal no Supabase removia as tabelas associadas. Por conta da reatividade das assinaturas de stream em segundo plano, as telas ainda empilhadas (`ChannelInfoScreen` e `WorkflowMainView`) tentavam se reconstruir com dados vazios/nulos antes de desempilhar, gerando exceções de ponteiro nulo e tela preta. Além disso, no desktop, o painel lateral de chat continuava selecionado.
- **Ajuste**:
  - Adicionado um loader com `showDialog` impedindo interações extras durante a chamada assíncrona.
  - Limpeza explícita do estado de seleção global no desktop (`desktopSelectionProvider = null`) caso o canal a ser removido seja o selecionado ativo.
  - Substituição do fluxo de `Navigator.pop(context)` simples por `context.go('/chats')` na conclusão, forçando o GoRouter a limpar e reconstruir a pilha de rotas na página principal e evitando rebuilds com referências obsoletas.

### 4. Compilação e Deploy de Produção

- **Release Build**: Gerado pacote de produção Web via `flutter build web --release --dart-define-from-file=dart_defines.json` sem lints ou erros de compilação.
- **Firebase Deploy**: Publicado e atualizado no Firebase Hosting de produção em **https://fluxy.web.app** 🚀.

---

## 29. Correção de Travamento no WebRTC e Implementação de Ringtone/Notificações em Segundo Plano na Web (11/06/2026)

### 1. Tratamento Anti-Travamento (Web)

- **Problema**: Ao finalizar uma chamada (áudio ou vídeo) na versão Web, o aplicativo congelava totalmente exibindo o diálogo do navegador "Página sem resposta". Isso ocorria devido a um timer de timeout forçado que gerava promessas não capturadas (Uncaught Promises) ao tentar invocar `disableAudio()` e `disableVideo()` na thread principal do Javascript.
- **Ajuste**:
  - A classe `CallService` agora usa a limpeza nativa de canais da SDK e bloqueia exceções lançadas nos "desligamentos" forçados de Áudio/Vídeo, removendo um "Timer de Timeout" destrutivo que estava derrubando a thread principal do Javascript em segundo plano. O navegador não irá mais congelar durante o `leaveChannel()`.

### 2. Toque de Chamada (Ringtone) na Web

- **Problema**: A notificação visual de chamada no Web não reproduzia nenhum som, sendo totalmente silenciosa e fazendo com que o usuário perdesse ligações caso não estivesse olhando para o monitor.
- **Ajuste**:
  - Utilização do pacote `audioplayers` para tocar um som clássico de chamada (`phone_ringing.ogg`) em loop contínuo enquanto o diálogo `showWebIncomingCallDialog` estiver visível na tela.
  - O loop do reprodutor de áudio (`_webRingtonePlayer`) é interrompido imediatamente e seus recursos liberados quando a ligação é atendida, recusada, cancelada ou perdida.

### 3. Notificações Nativas no Computador (Em Segundo Plano)

- **Problema**: Se o navegador estivesse minimizado ou o usuário estivesse em outra aba ativa, o aplicativo não conseguia notificar a chegada da chamada fora de tela.
- **Ajuste**:
  - Implementação da classe `WebNotificationService` com uso de importação condicional (`web_notification_service_stub.dart` e `web_notification_service_web.dart` via `dart.library.js_interop`) para não quebrar a compilação nativa (Android/iOS).
  - O serviço interage com a API HTML5 de Notificações do Navegador (`package:web` / `web.Notification`), solicitando permissão e disparando notificações nativas do sistema operacional (Windows/MacOS/Linux) ao receber uma chamada.
  - O banner de notificação exibe o remetente, a mensagem contextual e é fechado automaticamente via código (usando `tag` única) quando a chamada é encerrada no backend.

### 4. Correção da Exibição de Versão do App

- **Problema**: A tela de configurações do aplicativo (`settings_screen.dart`) exibia uma versão estática e incorreta ("Fluxy v1.0.5"), em vez de refletir dinamicamente a versão real configurada na constante do sistema (`AppConstants.appVersion`).
- **Ajuste**:
  - Substituída a String estática pelo valor dinâmico `'Fluxy v${AppConstants.appVersion}'` após a devida importação de `package:fluxy/core/constants.dart`.

### 5. Correção do Botão "Estou Ciente" em Canais (RLS e FK da Tabela `message_actions`)

- **Problema**: Ao clicar no botão "Estou Ciente" nos anúncios de canais (workspaces operacionais), o aplicativo exibia erros. Inicialmente, a política RLS (Row-Level Security) de `SELECT` falhava com código `42501` (Forbidden) pois checava somente a tabela `messages` (DMs). Após a correção da RLS, um segundo erro impedia a gravação: `PostgrestException: insert or update on table "message_actions" violates foreign key constraint "message_actions_message_id_fkey" (code 23503)`. Isso ocorria porque `message_actions.message_id` possuía uma chave estrangeira estrita para a tabela `messages(id)`, bloqueando qualquer referência a IDs da tabela `channel_messages(id)`.
- **Ajuste**:
  - Atualizada a política RLS `SELECT` no Supabase para validar tanto o acesso a mensagens de chats (`messages`) quanto mensagens de canais (`channel_messages`), usando a respectiva função `is_channel_member(channel_id)` para este último caso.
  - Removida a chave estrangeira limitante `message_actions_message_id_fkey` da tabela `message_actions`.
  - Adicionados triggers de exclusão (`on_message_deleted` e `on_channel_message_deleted`) baseados em uma nova função `public.handle_delete_message_actions()` para garantir que ações/respostas associadas a mensagens de ambas as tabelas sejam excluídas em cascata (`ON DELETE CASCADE` lógico) sempre que uma mensagem for deletada.
  - O botão "Estou Ciente" e as enquetes nos canais agora funcionam de forma fluida e sem erros no Supabase.

### 6. Limpeza e Reset Operacional Preventivo da Base de Dados

- **Ajuste**:
  - Executada a RPC administrativa `public.reset_operational_data(TRUE)` no Supabase, que realiza a limpeza total (Truncate Cascade) de mensagens, chats, cartões de workflow, comentários, históricos, chamadas, reuniões, tickets de helpdesk, tracking GPS e logs de atividades.
  - Executado também o Truncate Cascade das tabelas adicionadas em migrations recentes (`channel_join_requests` e `starred_messages`).
  - O banco foi reconfigurado de forma limpa, mantendo intactos todos os usuários cadastrados e filiais, e recriando apenas os 5 canais base com seus respectivos status padrão (`seed_base_workflow_channels`).

### 7. Invalidação de Cache e Atualizações Web Robustas (Firebase CDN)

- **Problema**: O navegador ou CDNs intermediárias cacheavam agressivamente arquivos críticos como `index.html`, `version.json` e `flutter_bootstrap.js`. Como resultado, mesmo após um deploy de nova versão, o usuário continuava executando a versão em cache local, a menos que fizesse uma limpeza manual profunda ou reiniciasse o sistema operacional para forçar a renovação do cache do Chrome/Edge.
- **Ajuste**:
  - Configurados cabeçalhos de controle de cache (`Cache-Control: no-cache, no-store, must-revalidate`) no arquivo de infraestrutura `firebase.json` para arquivos chaves de inicialização e controle de versão: `/index.html`, `/version.json`, `/flutter_bootstrap.js` e `/manifest.json`.
  - Isso garante que toda e qualquer verificação periódica de atualizações (`checkForUpdates` que consome `version.json`) ou carregamento inicial da página buscará os dados diretamente do servidor, forçando a atualização instantânea do app nos navegadores dos usuários logo na primeira atualização ou recarga da página.

### 8. Correção de Corrida de Corrida Assíncrona no PresenceService (Travamento do App)

- **Problema**: Ocorria um erro intermitente não-bloqueante no carregamento do Web (exibindo `Uncaught Error` no console e travando o loop de eventos na inicialização). Esse erro acontecia na função `_stopPresence()` do `PresenceService`. Quando o canal de tempo real sofria uma perda de conexão ou desconexão imediata (ex: logout seguido de login rápido), a trigger de fechamento de canal do Supabase Realtime marcava a instância `_presenceChannel = null`. No entanto, como `_stopPresence()` é assíncrona, a execução que já havia passado pela checagem de nulo e estava aguardando (`await`) o método `untrack()` tentava invocar o método `removeChannel(_presenceChannel!)` logo em seguida, gerando uma exceção de null-pointer (`Null check operator used on a null value`) por conta do atraso da promessa.
- **Ajuste**:
  - Refatorada a função `_stopPresence()` em `presence_service.dart` para capturar a referência do canal em uma variável local (`final channel = _presenceChannel;`).
  - A variável de instância `_presenceChannel` é anulada de forma imediata (antes de qualquer chamada assíncrona), blindando o fluxo contra chamadas reentrantes ou eventos concorrentes.
  - Todas as operações assíncronas subsequentes (`untrack()` e `removeChannel()`) operam na variável local isolada e foram envolvidas em blocos `try/catch` para mitigar qualquer instabilidade de rede ou fechamento de canal redundante.


### 9. Módulo de Controle Dinâmico de Permissões (RBAC)

- **Implementação**: Foi desenvolvida uma infraestrutura completa de Role-Based Access Control (RBAC) para suportar múltiplos perfis customizados e isolamento multi-tenant seguro.
- **Ajuste**:
  - **Supabase**: Criação da migration `20260709200000_rbac_permissions.sql` com as tabelas `rbac_roles`, `rbac_permissions`, `rbac_role_permissions` e `rbac_user_roles`. Políticas de Row-Level Security (RLS) habilitadas em todas elas restringindo leitura de perfis por `organization_id` e usando helper `fn_is_admin()`. Inseridos seeds padrões (Módulos de Sistema, Perfil Colaborador, Gestor, e Super Admin).
  - **Flutter Core**: Criação de `RbacRole` e `RbacPermission` models. Criação do `RbacRepository` e `myPermissionsProvider` (FutureProvider) para leitura e escrita das permissões.
  - **Integração na CRM Sidebar**: A `CrmSidebar` passou a observar ativamente os acessos do `myPermissionsProvider`. Itens do menu (como RH, Helpdesk, Configurações e o novo Painel Admin) só são renderizados se o perfil logado possuir as devidas permissões registradas na matriz.
  - **Painel Administrativo**: Criação de uma tela completa `AdminRbacScreen` que permite a visualização e edição em tempo real das permissões atribuídas a cada perfil de acesso através de checkboxes intuitivas, sincronizando o estado instantaneamente no banco de dados.


### 10. Módulos Adicionais de RH (LGPD, Alertas, Rejeições e Autoprovisionamento RBAC)

- **Implementação**: Finalizada a esteira completa do RH integrado à LGPD e melhorias no fluxo do RBAC.
- **Ajustes**:
  - **LGPD (Retenção e Esquecimento)**:
    - Criada a migration `20260710100000_rh_lgpd_retencao_esquecimento.sql`.
    - Adicionado suporte a tempo de retenção customizável por empresa (`fn_org_retencao_meses` e `rh_set_retencao_candidatos` salvando em `organizations.settings`).
    - Motor de anonimização e esquecimento (`fn_anonimizar_candidato` / `rh_anonimizar_candidato`) limpando dados PII, currículos e arquivos no Storage, mantendo o ID para logs de auditoria no histórico do candidato.
    - Job diário automatizado `rh-lgpd-diario` às 03:00 para expiração automática por retenção.
  - **Alertas, Integração e Rejeição**:
    - Criada a migration `20260710110000_rh6_alertas_integracao_rejeicao.sql`.
    - Vinculado `rh_atualizar_status_documentos` para lançar alertas automáticos na tabela `rh_alerta` + job diário `rh-documentos-diario`.
    - RPC `rh_rejeitar_documento(id, motivo)` para registrar o motivo de recusa de documentos do funcionário.
    - RPC `rh_anexar_documento_onboarding` vinculando documentos criados ao checklist de onboarding automaticamente.
  - **Autoprovisionamento do RBAC**:
    - Criada a migration `20260710120000_rbac_autoprovision.sql`.
    - Garantido setup idempotente das roles padrão (`Super Admin`, `RH`, `Gestor`, `Colaborador`) por empresa.
    - Trigger automático para associar novos usuários/empresas aos perfis corretos.
    - Safeguard no `rbac_repository.dart` para garantir que o Super Admin tenha sempre acesso irrestrito ao painel admin, independente das configurações no banco.
  - **Atualizações no Dart**:
    - `rh_documento_model.dart` adaptado para o novo campo `motivoRejeicao`.
    - `rh_documento_repository.dart` e `hr_documentos_screen.dart` integrando o fluxo completo de rejeição com pop-up solicitando motivo.
    - `onboarding_service.dart` com fluxo de upload e link de documentos.
    - `talent_bank_service.dart` adicionado o suporte para as funções de anonimização e retenção de candidatos.
  - **Documentação de Secrets**:
    - Criado `docs/SECRETS-RH.md` detalhando segredos de Extensions, Vault, e Edge Functions necessárias.


### 11. Unificação do Painel Admin e Nova UI de Acessos

- **Unificação**: 
  - O antigo `AdminDashboardScreen` e o `AdminRbacScreen` foram unificados.
  - O item "Painel Admin" da barra lateral agora abre diretamente o `AdminDashboardScreen` centralizado, com "Gerenciamento de Acessos" tornando-se a terceira aba do dashboard.
  - O antigo `AdminRbacScreen` foi mantido apenas como wrapper de compatibilidade para links legados.
- **Nova UI de Gerenciamento de Acessos (`access_management_screen.dart`)**:
  - Implementado alternador via `SegmentedButton` entre "Perfis & Permissões" e "Usuários".
  - **Aba Perfis & Permissões**: 
    - Exibição de painel lateral (desktop) ou chips (mobile) dos perfis.
    - Permissões agora agrupadas por módulo (em cards) usando Switches por ação (Visualizar/Gerenciar).
    - Estado de "Alterações não salvas" que só habilita salvamento quando há mudanças.
    - Estado vazio adicionado que inclui o botão "Criar perfis padrão" que auto-provisiona as 4 roles principais.
    - Diálogo de criação e exclusão de perfis não-sistema funcionalizado.
  - **Aba Usuários**:
    - Listagem de colaboradores com busca, avatar, e chips de perfis atribuídos.
    - Ação em bottom sheet para manipular as atribuições de papéis por usuário.
- **Backend**:
  - Criada a migration `20260710130000_rbac_admin_rpcs.sql`.
  - Contém RPCs `SECURITY DEFINER` protegidas pela função `fn_is_admin`:
    - `rbac_setup_default_roles()`
    - `rbac_create_role(nome, desc)` e `rbac_delete_role(id)`
    - `rbac_set_user_roles(user, uuid[])`
- **Camada Dart**:
  - `user_role_assignment.dart` (novo modelo).
  - Fluxos totalmente ligados a `rbac_repository.dart`.


### 12. Chave de IA por Organização — BYOK (aba "Chave de IA" do Painel Admin)

Módulo multi-tenant **multi-provedor** onde cada empresa fornece a **própria** chave de API — **Anthropic (Claude)**, **OpenAI (GPT)**, **Google (Gemini)** ou **Groq (Llama)** — habilitando a extração automatizada de currículos/documentos do RH (`rh-extract-cv`). As chaves vivem **exclusivamente no Supabase Vault (criptografadas)**, uma por provedor (`ai_key_<provider>_<org>`), nunca em `organizations/settings` nem expostas ao cliente. O **provedor ativo** por org fica em `organizations.settings->>'ai_provider'` (default `anthropic`).

- **UI**: `lib/features/admin/ui/tabs/ai_keys_management_tab.dart` (8ª aba, restrita a `admin`+ via `canAccessAdmin`). `SegmentedButton` alterna entre os 4 provedores; para cada um mostra status (`configurada + ••••last4`), instruções passo a passo (botão abre o console do provedor via `url_launcher`), campo mascarado (`autocorrect`/`enableSuggestions` off), botão salvar, botão **"Usar … na extração"** (define o ativo) e **"Remover chave do sistema"**. Um banner no topo indica o provedor ativo e se ele tem chave.
- **RPCs** (migrations `20260708220000` + `20260709190000` + `20260709200000_rh4_multiprovider_ai.sql` + `20260710150000_rh_groq_support.sql`), todas `SECURITY DEFINER` / `search_path=''`, org derivada de `auth.uid()`, guard `super_admin`/`admin`:
  - `set_org_ai_key(p_provider, p_key)` — upsert no Vault; valida provedor (`anthropic`/`openai`/`gemini`/`groq`) e formato da chave (`sk-ant-` / `sk-` / `AIza` / `gsk_`, tamanho mínimo). GRANT `authenticated`.
  - `has_org_ai_key(p_provider)` — status para a UI (`{configured, last4}`); nunca retorna a chave.
  - `delete_org_ai_key(p_provider)` — **remoção definitiva**: `DELETE FROM vault.secrets` (secret apagado por completo — não sobra material criptografado, evitando vazamento/roubo). Retorna `boolean`.
  - `set_org_ai_provider(p_provider)` / `get_org_ai_provider()` — grava/lê o provedor ativo em `organizations.settings.ai_provider`.
  - `get_org_ai_key(p_org_id, p_provider)` — leitura da chave **exclusiva de `service_role`** (Edge Functions); REVOKE de `anon`/`authenticated`. Nenhuma sessão de usuário — nem admin — lê a chave.
- **Consumo**: `supabase/functions/rh-extract-cv/index.ts` lê o provedor ativo de `organizations.settings`, a chave via `get_org_ai_key`, e despacha por provedor (`runExtraction`): Anthropic `claude-haiku-4-5` (`output_config.format`), OpenAI `gpt-4o-mini` (`response_format json_schema strict`), Gemini `gemini-2.0-flash` (`responseMimeType application/json` + prompt), Groq `llama-3.3-70b-versatile` (SDK OpenAI com `baseURL` da Groq + JSON mode). Todas as saídas são validadas com o mesmo Zod (`ExtractionSchema`, S061) e o custo é logado em `ia_usage_log` com preço por modelo. Empresa sem chave do provedor ativo → `extracao='falhou'` com `missing_api_key` e **sem retry** (nada trava o RH — S064).
- **Atenção**: as migrations precisam estar **aplicadas no Supabase real** (dev → prod) e a Edge Function `rh-extract-cv` **redeployada** (SDKs `npm:openai` e `npm:@google/generative-ai`) para o multi-provedor funcionar.

### 13. Assistente IA — Chatbot Interno (Groq/Llama)

Contato de sistema **"Assistente IA"** na lista de chats. Colaboradores conversam com ele em DMs ou o adicionam a grupos para tirar dúvidas de RH/TI/processos. Responde via **Groq (Llama)** com chave **GLOBAL da plataforma** (Supabase Secret `GROQ_API_KEY`) — **não é BYOK**, aproveitando o tier gratuito generoso da Groq.

- **Usuário-bot** (migration `20260710160000_ai_chatbot_agent.sql`): UUID fixo `00000000-0000-4000-a000-000000000001`. Como `public.users.id` é FK de `auth.users(id)`, o bot é inserido em `auth.users` (senha `DISABLED-BOT-ACCOUNT-NO-LOGIN`, nunca autentica); o trigger `handle_new_user` cria `public.users`, que é ativado (`is_active/is_online = true`) e desbanido. Insert idempotente.
- **Disparo**: trigger `trg_ai_chatbot` `AFTER INSERT ON messages` chama a Edge Function `ai-chatbot` (via `net.http_post` + `get_webhook_secret()`), **apenas** quando o remetente não é o bot e o bot é membro do `chat_id` (filtro no SQL evita acordar a function à toa e previne loop).
- **Edge Function** `supabase/functions/ai-chatbot/index.ts`: valida `x-webhook-secret`; **DM** (`chat.type='direct'`) → sempre responde; **grupo** → só se **mencionado** (`@assistente`/`@ia` ou `metadata.mentions`) ou for **resposta** (`reply_to`) a uma mensagem do bot. Lê as últimas ~16 mensagens do chat como contexto, chama a Groq (`llama-3.3-70b-versatile`) e **insere a resposta em `messages` como o bot** → Realtime + push atualizam o app automaticamente.
- **Especialização (persona)**: `chats.metadata.ai_specialization` seleciona o system prompt (`geral` | `rh` | `ti` | `administrativo` | `comercial` | `pos_venda`); default `geral`. Ponto de extensão para Function Calling futuro (banco de horas, abrir chamados, etc.).
- **Atenção**: aplicar a migration, **deployar** a Edge Function `ai-chatbot`, e definir os secrets `GROQ_API_KEY` e `WEBHOOK_SECRET` (`npx supabase secrets set ...`). Sem `GROQ_API_KEY` o bot silenciosamente não responde.

### 14. Performance de Headcount e Design System de Status Multi-tenant (10/07/2026)

Duas frentes no módulo RH: cortar round-trips na contagem por status e extrair as cores de status para tokens de tema (base do white-label por tenant).

**A) Headcount de funcionários em 1 query.** `EmployeeService.fetchStatusCounts()` fazia **N** `count()` (uma por status) via `Future.wait`. Agora lê a view agregada **`funcionario_contagem_status`** (migration `20260710170000_rh4_funcionario_contagem_status.sql` — `security_invoker`, `GROUP BY organization_id, status`, `deleted_at IS NULL`), espelho fiel de `candidato_contagem_status`. Statuses sem linhas não voltam do `GROUP BY`; o cabeçalho já trata ausência como `0`. Aplicada em **dev** (`ffsspqscpdxlmxuaiytj`) via MCP.

**B) Tokens de status como `ThemeExtension` (white-label).** Antes cada tela hardcodava `Colors.green/orange/...` por status (dois `_StatusBadge` gêmeos, paletas duplicadas, switches de documento repetidos). Agora a cor **nunca** é escolhida na UI: mapeia-se o status para um papel semântico e resolve-se a cor no tema.

- `lib/core/status_role.dart` — enum **`StatusRole`** com 8 papéis (`success`/`info`/`warning`/`danger`/`neutral`/`highlight`/`progress`/`pending`). Dart puro de propósito, para manter os models livres de `material.dart`.
- `lib/core/status_tokens.dart` — **`AlinhaStatusTokens extends ThemeExtension`** mapeia cada papel → `Color`; paleta `standard` equivale **1:1** às cores Material antigas. Açúcar `context.statusTokens`.
- **Anexado nos 4 `ThemeData`** (alinha/whatsapp × light/dark) em `app.dart` via `extensions:`. **Ativar white-label para um novo tenant = adicionar uma variante de `AlinhaStatusTokens` + um `AppThemeScheme`; zero mudança nas telas.**
- **Mapa status→papel** ao lado das labels nos models: `EmployeeStatus.role()`, `CandidateStatus.role()` e `extension DocumentoStatusX` (com `role` **e** `label` — de quebra unificou a label divergente do documento: era "Aprovação Pendente" em uma tela e "Pendente de Aprovação" na outra).
- **Widget compartilhado** `lib/features/hr/ui/widgets/status_badge.dart` (**`StatusBadge`**) substituiu os dois `_StatusBadge` duplicados (funcionários + candidatos).
- **Telas migradas**: `employees_screen` (headcount + badge), `talent_bank_screen` (badge, cor da coluna do board, pills do funil, `_ScorePill`), `hr_documentos_screen`/`meus_documentos_screen` (cor+label do enum), `hr_alerts_screen` (warning/info), `careers_screen` (success), `onboarding_template_form_sheet` (danger), `employee_detail_screen` (danger). **Exceção intencional**: o ícone cinza de `candidate_area_screen` é *chrome* mudo, não status — mantido fora dos tokens.
- `flutter analyze`: **0 issues**. Aparência **inalterada** (mapeamento 1:1); o ganho é fonte única + troca de paleta por tenant.

### 15. Injeção de RAG / Contexto de Negócios e Regras Estritas no Assistente IA (10/07/2026)

**A) Arquivo de Contexto de Negócios (`app_context.ts`)**:
Criado para fornecer à Edge Function `ai-chatbot` o escopo funcional completo do aplicativo (módulos RH, Service Desk, Comunicação, RBAC), omitindo intencionalmente os detalhes técnicos e de banco de dados. Isso garante que a IA responda embasada estritamente nas capacidades do sistema, sem alucinar features de infraestrutura.

**B) Diretrizes Operacionais (5 Regras de Ouro)**:
O *system prompt* base do robô recebeu 5 regras restritivas absolutas:
1. **Não inventar nada**: Admitir desconhecimento e não alucinar leis, datas ou links.
2. **Sem bajulação**: Respostas secas, diretas, sem elogios ou entusiasmos artificiais ("Ótima pergunta!").
3. **Direto ao ponto**: Listas e objetividade. Sem repetir o prompt.
4. **Uso de ferramentas**: Orientar o colaborador a usar o sistema/ferramenta, em vez de refazer processos.
5. **Dúvida = Pergunta**: Na ausência de certeza, a IA é programada para perguntar a intenção.

**C) Identificação Dinâmica de Usuários**:
A Edge Function agora faz uma query em `public.users(full_name)` a partir do `sender_id` (remetente da mensagem) antes de chamar a Groq. O nome é embutido dinamicamente no system prompt (`IMPORTANTE: A pessoa falando com você agora se chama...`), forçando o bot a ser responsivo ao nome do usuário logado e garantindo aderência na plataforma.

**D) Correção de Deploy e Webhook do Gatilho**:
- O gatilho `trg_ai_chatbot` foi migrado da URL chumbada de Produção para consumir dinamicamente `public.get_edge_base_url()`, ativando o gatilho perfeitamente em `dev`.
- O secret da function foi emparelhado ao `webhook_secret` do Vault da Supabase para reverter `401 Unauthorized` de chamadas do banco.

### 16. Multitenancy, Hub de Suporte e Tour de Onboarding (13/07/2026)

**A) Entitlements de Módulo por Organização (Multitenancy)**:
- Implementado o RLS e gates client-side para garantir o acesso a módulos sob o modelo SaaS multitenant. Apenas organizações que possuem a permissão e licença (`settings.modules`) podem visualizar os módulos (ex: `helpdesk_central`, `rh_banco_talentos`).
- **Edge Function Gating**: As funções do Supabase (ex: `rh-candidatura`) validam o módulo no banco (bypassando RLS) e retornam 404 nativo no endpoint público se a organização não tiver ativado o módulo contratado.

**B) Novo Hub Central de Suporte e Ajuda (`HelpCenterScreen`)**:
- Central unificada contendo navegação com 4 Abas principais (TabBar rolável):
  1. **Central de Ajuda**: FAQ + Faixa de ações rápidas (Rever tutorial, Guias, Manual, Abrir chamado).
  2. **Guias**: Tutoriais passo a passo portados do antigo `tutorialsData` (`help_guides.dart`).
  3. **Manual**: Documentação completa e pesquisável (renderizada com `flutter_markdown` em `help_manual.dart`). Imagens de ajuda servidas localmente em `assets/images/help/`.
  4. **Meus Chamados**: Painel de visualização e abertura de tickets.
- O botão "Rever tutorial" foi centralizado nas ações rápidas desta tela (suportando tanto desktop quanto mobile via `tourReplayProvider`).

**C) Tour Guiado de Onboarding Interativo (Primeiro Acesso)**:
- Pacote `tutorial_coach_mark` implementado na Web e Mobile para mostrar a plataforma na primeira vez que o usuário loga. Apresenta um fluxo unificado: Carrossel inicial explicativo (`WelcomeIntroScreen`) -> Tour UI em destaques reais na tela (`home_tour.dart`).
- **Adaptado para CrmSidebar (Desktop)**: A barra lateral é expandida inteligentemente antes do tour; o estado original (expandida/recolhida) é restaurado fielmente ao final.
- **Scroll Inteligente**: O tour rola a sidebar para o topo no início (`scrollToTop()`) e utiliza o hook `beforeFocus` para garantir a visibilidade (`ensureKeyVisible()`) de itens abaixo da dobra da tela, tornando-o totalmente responsivo.
- **Detalhamento RBAC-aware**: Cada item da sidebar é chaveado (`HomeTourKeys.moduleKey(id)`), permitindo que o tour seja gerado dinamicamente APENAS para os módulos que o usuário logado tem acesso. Descrições ricas foram configuradas em `ModuleDescriptor.tourHint`.
- **Interatividade**: Ao avançar os passos, o tour **ativa o módulo em tempo real** (via ProviderContainer e `desktopSelectionProvider`), garantindo que o conteúdo de fundo sincronize com o passo atual exibido no balão. O balão permite avanço clicando em qualquer parte da tela (`enableOverlayTab`).

### 17. RH — Central de Recrutamento: Divulgação, Vínculo, Catálogo, Vagas, Dashboard, Avaliação Técnica e Pipeline avançado (Ondas 1–5 — 14–15/07/2026)

Evolução do módulo RH seguindo o `docs/PLANO-RH-COMPLETO.md`, entregue em **5 ondas** (migrations aditivas `rh7`–`rh13`), todas com `organization_id` + `trg_force_org` + RLS `tenant_isolation` RESTRICTIVE + `module_entitlement` (`rh_banco_talentos`). Nenhum acesso anônimo direto: o portal público segue passando **só** pela Edge Function `rh-candidatura` (service_role). Mapa Onda→conteúdo: 1 = A+C, 2 = D+E, 3 = F, 4 = G, 5 = H.

**A) Central de Recrutamento — hub com abas (F1.1 / `talent_bank_screen.dart`).**
`TalentBankScreen` deixou de ser "lista + funil" e virou hub. Após as Ondas 3–5 são **6 abas** (na ordem): **Visão Geral** (dashboard), **Pipeline** (lista + funil Kanban), **Divulgação**, **Vagas**, **Avaliações** e **Ajustes**. FAB contextual: "Novo candidato" no Pipeline, "Nova vaga" em Vagas. (Onda 1 nasceu com 4 abas; Visão Geral e Avaliações chegaram nas Ondas 3 e 4.)

**B) Painel de Divulgação (`ui/widgets/careers_link_panel.dart`).**
- Link público `<host>/carreiras/<slug>` (host: `Uri.base.origin` na Web, constante `AppEnv` no mobile — exposto em `CareersLinkPanel.publicHost` para reuso por vaga). Ações: copiar, WhatsApp (`wa.me?text=`), e-mail (`mailto:`), abrir. **QR code** (`qr_flutter`) expansível.
- Toggle **Página ativa/pausada** + edição da mini-landing (headline/sobre) por admin RH. Métricas: inscrições 30d, total pelo portal, avançaram no funil, contratados.
- Migration `20260714100000_rh7_central_divulgacao.sql`: colunas `organizations.carreiras_ativo/headline/sobre`; RPC `rh_set_carreiras_config(p_ativo,p_headline,p_sobre)` (null preserva, string vazia limpa; guard `fn_is_rh_admin`; auditoria em `rh_access_log`); view `rh_metricas_divulgacao`. A Edge Function `rh-candidatura` (`org`) devolve `carreiras_*` e (`apply`) recusa candidatura com 403 quando a página está pausada.

**C) Vínculo Funcionário ↔ Usuário do app (F1.2).**
- Migration `20260714110000_rh8_vinculo_usuario.sql`: índice único parcial `uq_funcionario_user` (1:1 em `funcionario.user_id` vivo); view `org_users_vinculaveis` (usuários da org + flag `ja_vinculado`); RPCs `rh_vincular_usuario(p_funcionario_id,p_user_id)` / `rh_desvincular_usuario(p_funcionario_id)` (guard `fn_is_rh_admin`, mesma org, unicidade 1:1, auditoria). UI na ficha do funcionário (`employee_detail_screen.dart`) + badge "tem app" na lista.

**C.1) Edição de vínculo na ficha + carga em massa (23/07/2026 — paridade com o Fluxy).** Sem migration nova.
- **Edição de vínculo (RH-4.3):** a seção "Vínculo" da ficha (`employee_detail_screen.dart` → `_VinculoSection`) ganhou **Editar** (quando há vínculo) / **Registrar vínculo** (quando a ficha está sem vínculo), gated por `isHrAdmin`. Novo sheet `employee_vinculo_sheet.dart`: tipo, **situação** (`vinculo_status` — o form de criação não expunha), data de admissão, matrícula, carga e filial/depto/cargo. Escreve direto em `public.vinculo` pela policy `RH acessa vínculos` (`FOR ALL` a `fn_is_rh` na própria org) — `EmployeeService.saveVinculo()` faz UPDATE se existe e INSERT se não; `fetchVinculo()` traz os *ids* de lotação que a view `funcionario_resumo` não expõe. Provider `vinculoProvider`. Fecha o buraco de que a admissão (base do saldo de férias — rh26) só era editável recriando a ficha.
- **Carga em massa (`supabase/scripts/importar_usuarios_como_funcionarios.sql`, slug `dubairro`):** cria uma ficha `funcionario` (com `user_id`) + `vinculo` para cada usuário **ativo** da org, puxando lotação de `users.branch_id/department_id/job_position_id` e contato de `users.phone/data_nascimento`; ignora bot/sistema (ids fixos), inativos e nomes < 3 letras; **idempotente**. `data_admissao` = data de corte única (não é dado real — o RH corrige depois pela edição de vínculo acima). Não copia CPF (colisão de `cpf_hash` único por org). ⚠️ **DuBairro já tem ~178 fichas de planilha:** se estiverem sem `user_id`, a carga cria uma 2ª ficha para a mesma pessoa — o script traz a **"Conferência 0"** (fichas sem vínculo) para rodar isolada antes e vinculá-las primeiro.

**D) Catálogo Áreas / Cargos / Competências (Fase 4 / `20260715100000_rh9_catalogo_areas_cargos.sql`).**
- Tabelas `rh_area`, `rh_cargo` (FK `area_id`, `nivel_sugerido`), `rh_competencia`, `cargo_competencia` (N:N — já no schema para a Fase 3). FKs opcionais `candidato.area_id/cargo_id` + **seed best-effort** dos textos livres já digitados. RLS: org inteira lê (dropdowns), só RH escreve.
- **UI de CRUD** em Ajustes → Catálogo (`ui/catalog_management_sheet.dart`, abas Áreas/Cargos com criar/editar/ativar-inativar). Service/provider: `vacancy_service.dart` (`fetchAreas/Cargos`, `createArea/updateArea`, `createCargo/updateCargo`), `vacancy_provider.dart` (`areasProvider`/`cargosProvider` family por `somenteAtivas`).

**E) Vagas publicáveis (Fase 2 / `20260715110000_rh10_vagas.sql`).**
- Enum `vaga_status` (`rascunho|aberta|pausada|fechada`), tabela `vaga` (título, `area_id`/`cargo_id`, nível, contrato, localidade, remoto, faixa, descrição, requisitos, `vagas_qtd`, `expira_em`, soft-delete). Trigger `fn_tg_vaga_publicada` carimba `publicada_em` na 1ª abertura. `candidato.vaga_id` opcional (espontânea = null). View `vaga_resumo` com nomes do catálogo + contadores de candidatos.
- **Central → aba Vagas** (`ui/vacancies_tab.dart`): CRUD via `VacancyFormSheet`, transições de status, contadores, **compartilhar vaga** (link/QR `<host>/carreiras/<slug>/vaga/<id>`), "ver candidatos no pipeline" (aplica `TalentFilters.vagaId` e volta ao Pipeline com chip removível).
- **Portal público** (`careers_screen.dart`, rotas `/carreiras/:slug` e `/carreiras/:slug/vaga/:id`): lista as vagas abertas (retornadas pela `rh-candidatura`/`org`, filtradas por status `aberta` e não expiradas), permite escolher uma vaga (candidatura vinculada, envia `vaga_id`) ou seguir espontânea. A Edge Function (`apply`) valida a vaga (org, aberta, não expirada) antes de gravar.

**Correções de integração aplicadas nesta auditoria (14/07/2026):** a `VacanciesTab`, o CRUD de Catálogo e a exibição de vagas no portal haviam sido construídos mas **não ligados** (a aba Vagas ainda exibia um placeholder; o portal ignorava `vagaId`/lista de vagas; Ajustes não tinha Catálogo). Tudo foi conectado end-to-end; `flutter analyze` do módulo RH sem erros.

**F) Dashboard & Analytics de RH (Onda 3 / Fase 6).**
- Nova aba **Visão Geral** (primeira aba da Central / `ui/hr_dashboard_tab.dart`), landing para gestores. KPIs (total, em processo, contratados, conversão), **funil** por etapa (barras horizontais proporcionais), **candidatos por fonte** (pizza `fl_chart`), **por nível** (barras), **movimentação de pessoal** dos últimos 12 meses (admissões x desligamentos — barras agrupadas `fl_chart`) e **top talentos** por score (abre a ficha).
- Nova dependência **`fl_chart: ^0.69.0`** (a "única nova dependência" prevista no plano). Charts usam os tokens de status (`context.statusTokens`) — white-label consistente; datas com array fixo de meses (sem depender de `initializeDateFormatting`).
- Migration `20260716100000_rh11_dashboard_analytics.sql`: views `security_invoker` (RLS por org filtra) `rh_dash_candidato_fonte`, `rh_dash_candidato_nivel` e `rh_dash_movimentacao_mes` (admissões/desligamentos por mês, derivadas de `vinculo`). Funil e headcount reusam `candidato_contagem_status` / `funcionario_contagem_status`. Service/provider: `hr_analytics_service.dart` + `hr_analytics_provider.dart`.

**G) Avaliação Técnica + IA generativa de questões (Onda 4 / Fase 3).**
O maior diferencial do plano: banco de questões por cargo (manuais ou geradas por IA) e prova objetiva do candidato com **correção 100% server-side** (o gabarito `correta_idx` nunca vai ao cliente).
- Migration `20260717100000_rh12_avaliacao_tecnica.sql`: `questao` (org, cargo_id/area_id, nível, enunciado, `opcoes jsonb`, `correta_idx`, origem `manual|ia`, soft-delete; CHECK valida array de 2–6 opções e idx dentro do intervalo), `avaliacao` (candidato, vaga?, total, acertos, nota 0–100, status `iniciada|finalizada|expirada`) e `avaliacao_resposta`. RLS: `questao` — org lê / RH escreve (`trg_force_org`); `avaliacao`/respostas — RH **lê** a própria org, escrita exclusiva do `service_role` (Edge Function). Views `avaliacao_resumo` (resultados p/ RH) e `questao_contagem_cargo`.
- **Edge Function `rh-gerar-questoes`** (RH autenticado): valida JWT + `fn_is_rh_admin`, lê provedor+chave BYOK do Vault (reuso do dispatch multi-provedor Anthropic/OpenAI/Gemini/Groq do `rh-extract-cv`), gera N questões (teto **15**), valida com Zod, persiste como o usuário (RLS + `trg_force_org`) e loga custo em `ia_usage_log` (`funcao='rh-gerar-questoes'`).
- **`rh-candidatura`** ganhou `avaliacao_iniciar` (sorteia N questões ativas priorizando cargo→nível, cria `avaliacao`, devolve **sem** gabarito; impede refazer se já finalizada) e `avaliacao_enviar` (lê gabarito no servidor, calcula nota, grava respostas + histórico). Config `organizations.settings.avaliacao_qtd` (default 5, teto 15).
- **Central → aba Avaliações** (`ui/avaliacoes_tab.dart`, 5ª aba): banco filtrável por cargo, **Gerar com IA** (sheet cargo/nível/quantidade) e **Nova questão** manual (enunciado + 2–6 alternativas com rádio da correta). Service/model/provider: `avaliacao_service.dart`, `avaliacao_model.dart`, `avaliacao_provider.dart`.
- **Portal do candidato**: `candidate_test_screen.dart` (prova com barra de progresso, exige responder tudo, `PopScope` confirma saída) acessível pelo card "Avaliação técnica" da área do candidato; resultado (nota) exibido lá. A ficha do candidato (RH) mostra a seção **Avaliação técnica** com acertos/nota por prova.

**H) Pipeline avançado — responsável, SLA e ações em massa (Onda 5 / Fase 5, parte 1).**
Camada aditiva e de baixo risco sobre o funil atual (o funil segue em `CandidateStatus`; as **etapas customizáveis por org** data-driven ficaram fora deste corte por serem um refactor profundo e arriscado).
- Migration `20260718100000_rh13_pipeline_avancado.sql`: `candidato.responsavel_id` (FK users, índice por org) e `candidato.status_changed_at` (carimbo de tempo na etapa, backfill do histórico). A guarda `fn_candidato_status_guard` foi recriada para **reiniciar `status_changed_at`** a cada mudança de etapa (base do SLA). RPC `rh_atribuir_responsavel(p_ids[], p_responsavel)` (guard RH + mesma org; NULL desatribui; ações em massa).
- **Pipeline** (`talent_bank_screen.dart`): chip **"Meus candidatos"** (filtra por `responsavel_id = auth.uid()`), **badge de SLA** "Parado há X d" nos cards em processo (limite `_slaDias = 7`), **seleção múltipla** (long-press → checkboxes → barra de ações: **Atribuir** responsável / **Mover** etapa / **Descartar** em lote). Filtro `TalentFilters.responsavelId`.
- **Ficha do candidato**: seção **Responsável** (atribuir/alterar/remover). Seletor reutilizável `ui/widgets/responsavel_picker.dart` (busca nos usuários da org via view `org_users_vinculaveis`). Service: `atribuirResponsavel`, `bulkUpdateStatus`, `fetchOrgUsers`; model ganhou `responsavelId/Nome`, `statusChangedAt` e getter `diasNaEtapa`.
**I) Etapas customizáveis do pipeline por org (Onda 5 / Fase 5, parte 2 — RH-14, 15/07/2026).**
Fecha a Fase 5: o funil deixa de ser fixo em `CandidateStatus` e passa a ler as etapas da org na tabela **`pipeline_etapa`** (seed = etapas atuais; comportamento inalterado para orgs existentes).
- **Modelo:** `pipeline_etapa` (org, `slug` imutável, `nome`, `ordem`, `role_cor` = nome de `StatusRole` — white-label, nunca cor crua, `tipo`). Três etapas **reservadas** por org (únicas, indeléveis, slug fixo): `entrada` ('novo'), `contratado` e `descartado`. As `normal` podem ser criadas/renomeadas/recoloridas/reordenadas/excluídas (exclusão bloqueada se houver candidatos na etapa — trigger `fn_tg_pipeline_etapa_protege`).
- Migration `20260719100000_rh14_pipeline_etapas.sql`: tabela + RLS padrão (org lê; `fn_is_rh_admin` escreve; `trg_force_org` + `tenant_isolation` + `module_entitlement`), **seed idempotente das orgs existentes**, RPC `rh_pipeline_seed_padrao()` (orgs novas semeiam ao clicar "Personalizar etapas"), e **`candidato.status` convertido de enum para TEXT** (as views dependentes `candidato_contagem_status`, `rh_metricas_divulgacao` e `vaga_resumo` foram dropadas e recriadas idênticas). O enum `candidato_status` permanece no banco, sem uso.
- **Guard data-driven:** `fn_candidato_status_guard` recriada lendo `pipeline_etapa` (contratado imutável; descartado só reativa para a entrada; sem retroativas por `ordem`, exceto rumo a descartado/contratado; etapa destino precisa existir). Fallback estático para org sem etapas. O trigger passou a rodar **também no INSERT** (valida o slug — o TEXT perdeu a proteção do enum — e carimba `status_changed_at`).
- **Flutter:** model `pipeline_etapa_model.dart` (`PipelineEtapa` + `PipelineConfig` com `label/role/funil/transicoesDe/prontoParaContratar` e fallback `PipelineConfig.padrao()`), provider `pipelineConfigProvider` (sem autoDispose). Consomem o config: chips/kanban/bulk da `talent_bank_screen`, ficha (`candidate_detail_screen` — o botão "Contratar" agora aparece na **última etapa antes de contratado**), dashboard (`hr_dashboard_tab`) e **portal do candidato** (`candidate_area_screen` lê o novo campo `pipeline` devolvido pela action `status` da `rh-candidatura`). Gestão na aba **Ajustes → Etapas do pipeline** (`ui/pipeline_stages_sheet.dart`: personalizar/seed, criar, renomear, recolorir via picker de `StatusRole`, subir/descer, excluir).
### 18. RH — Consolidação das Fases 7/8/9 (rh22 — 15/07/2026)

Fecha o `docs/PLANO-RH-COMPLETO.md`: as fases finais saíram de scaffold para implementação completa, com hardening de segurança/multi-tenant na migration **`20260727100000_rh22_consolidacao_fases789.sql`** e reescrita da Edge Function `rh-automations`.

**A) Hardening multi-tenant (rh22).** As 12 tabelas das fases 8/9 (`rh_ausencia`, `rh_email_template`, `rh_automacao`, `rh_comunicacao_log`, `org_smtp_config`, `rh_historico_cargo_salario`, `rh_dependente`, `rh_beneficio`, `rh_funcionario_beneficio`, `rh_avaliacao_desempenho`, `rh_holerite`, `rh_ponto_registro`) ganharam o padrão do projeto que faltava no scaffold: `trg_force_org` + policies RESTRICTIVE `tenant_isolation` e `module_entitlement` (mapeadas por módulo: `rh_ausencias`, `rh_automacoes`, `rh_funcionarios`, `rh_beneficios`, `rh_desempenho`, `rh_holerites`, `rh_ponto`).

**B) Fase 9 — Comunicação & Automações (CONCLUÍDA).**
- **Vulnerabilidade corrigida:** `rh_get_smtp_server(p_org_id)` era SECURITY DEFINER com EXECUTE default — qualquer usuário autenticado lia a senha SMTP descriptografada de **qualquer** org. Agora é exclusiva de `service_role`. A senha também **nunca mais volta ao cliente**: `rh_get_smtp_config()` retorna `has_password` em vez de `password_decrypted`, e a cifra passou da chave derivável (salt estático) para a **chave Vault por org** (`fn_rh_data_key`, mesma dos dados sensíveis). Senha vazia no save preserva a cifra atual.
- **Bug corrigido (automação nunca disparava):** a Edge Function esperava `organization_id`/`status_id` no record de `candidato_historico` — colunas que **não existem**. Novo trigger `trg_rh_automacao_notify` (AFTER INSERT, `acao='mudanca_status'`) resolve a org via `candidato`, só acorda a function se a org tiver automação ativa e envia `x-webhook-secret` (padrão do `trg_ai_chatbot`). A function valida o secret (antes qualquer um com anon key disparava e-mails), lê a etapa de `detalhes.para`, resolve o nome da etapa em `pipeline_etapa` e suporta as variáveis `{{nome}}`, `{{empresa}}` e `{{etapa}}` nos templates. `config.toml`: `verify_jwt = false` (webhook autentica por secret).
- **UI:** o dropdown de etapas da regra deixou de usar slugs fixos inexistentes (`triagem`/`teste`/`proposta`) e passou a ler o **pipeline real da org** (`pipelineConfigProvider` / RH-14); labels amigáveis nos cards de regra; formulário SMTP sincroniza após o fetch e nunca exibe a senha.

**C) Fase 8 — Gestão de Pessoas (CONCLUÍDA).** Os 4 stubs viraram módulos funcionais sobre o schema `rh21`, com service/providers dedicados (`people_management_service.dart` + `people_management_provider.dart`):
- **Controle de Ponto** (`hr_ponto_screen.dart`): espelho por período/funcionário agrupado por dia, lançamento manual do RH (origem `importacao`) e aprovação/ajuste/rejeição de batidas (tokens de status). **Meu Ponto** (`my_time_clock_screen.dart`, rota `/meu-ponto`, botão no perfil): batida do colaborador com o próximo tipo sugerido (entrada → saída almoço → retorno → saída) + espelho de 7 dias.
- **Holerites** (`hr_holerites_screen.dart`): emissão por competência com upload de PDF para `rh-documentos/holerites/{funcionario_id}/…` (policy nova na rh22 libera o SELECT do **próprio** colaborador nesse prefixo), recibo de leitura ("Visualizado em"), signed URL e exclusão. **Meus Holerites** (`my_payslips_screen.dart`, rota `/meus-holerites`): abre o PDF e carimba `data_visualizacao`.
- **Benefícios** (`hr_beneficios_screen.dart`): abas Catálogo (CRUD + ativo/inativo) e Adesões. Desconto em folha **cifrado** via RPCs `rh_add_adesao_beneficio` / `rh_list_adesoes_beneficio` (o cliente nunca cifra/decifra).
- **Desempenho** (`hr_desempenho_screen.dart`): avaliações por ciclo (1:1, experiência, anual, 360) com pontuação 0–100 (cor por faixa via tokens) e feedback.
- **Ficha do funcionário** (`employee_expansion_sections.dart`): seções **Histórico de cargos e salários** (RPC nova `rh_add_historico_cargo_salario` — cifra + auditoria em `rh_access_log`; sem ela a UI não tinha como gravar, pois `fn_rh_encrypt` é revogada do cliente) e **Dependentes** (CPF cifrado via `rh_add_dependente`/`rh_list_dependentes`).
- **Ausências (correções):** o insert falhava sempre (`.eq('deleted', false)` — a coluna é `deleted_at`); "Minhas Ausências" mostrava a org inteira para usuários RH (agora filtra pelo próprio `funcionario` via `myFuncionarioIdProvider`); invalidações de providers completadas.
- **RBAC/entitlements (rh22):** permissões view/manage para `rh_automacoes`, `rh_holerites`, `rh_ponto`, `rh_beneficios`, `rh_desempenho`; backfill nos perfis Super Admin e RH existentes; `fn_setup_default_roles` atualizada; entitlements semeados nas orgs que já têm `rh_funcionarios` (novos módulos) e `rh_banco_talentos` (automações).

**D) Fase 7 — Portal do Candidato com login (CONCLUÍDA).** Backend rh16 + actions `auth_*`/`api_me` da `rh-candidatura` já eram sólidos (RPCs só via service_role, bcrypt, sessão 30d). Polimento no Flutter: validação client-side no cadastro (nome/e-mail/senha ≥ 6), erros/ícones via tema e `AlinhaStatusTokens` (sem `Colors.X`), datas com `DateFormat`, status da candidatura com `StatusBadge` + labels do funil padrão, e link "Já se candidatou? Acompanhe suas candidaturas" no cabeçalho do portal público de carreiras. Secrets da verificação por e-mail: `GMAIL_USER`/`GMAIL_APP_PASSWORD`/`APP_BASE_URL` (link `/candidato/verify?token=`).

**E) Fase 10 (Financeiro ERP):** permanece scaffold intencional (telas placeholder sem RBAC/entitlement seeds → invisíveis na sidebar). Fora do escopo do plano de RH.

**Status de Deploy no Supabase (15/07/2026):**
O repositório e o app estão à frente do Supabase:
- **DEV (Pendente):** aplicar migrations da `rh14` até a **`rh22`** (inclui `fase10`), redeployar `rh-candidatura`, deployar `rh-automations` (com `--no-verify-jwt`) e conferir secrets (`WEBHOOK_SECRET`, `GMAIL_USER`, `GMAIL_APP_PASSWORD`, `SENDER_NAME`, `APP_BASE_URL`, opcional `DEV_EMAIL_OVERRIDE`).
- **PROD (Pendente):** aplicar migrations da `rh7` até a `rh22` + deploy/redeploy das Edge Functions (`rh-gerar-questoes`, `rh-candidatura`, `rh-automations`). A geração por IA continua dependendo da chave BYOK (Admin → Chave de IA).
- **Validação:** fluxo completo em `alinhajadev.web.app` antes de produção (regra do projeto).

---

## 19. Console de Plataforma e Multi-Tenant (White-Label)

### Arquitetura de Build
O sistema possui suporte a múltiplos tenants (empresas) através de uma arquitetura centralizada. Para gerenciar essas empresas sem misturar acessos operacionais, foi implementado um **Console de Plataforma** segregado por build:
- **Build de Tenant (Padrão):** O aplicativo carrega normalmente. O usuário só interage com o contexto de sua própria organização (RLS).
- **Build de Admin (Console):** Compilado com a flag --dart-define=PLATFORM_ADMIN=true. Acesso exclusivo aos Platform Owners (configurado via n_is_platform_owner() no Supabase).

### Org Switcher (Empresa Efetiva)
No Console de Plataforma (integrado via ResponsiveLayout na web de admin), o Super Administrador tem acesso ao **PlatformOrgSwitcher** no topo da CrmSidebar.
Este seletor altera o ctingOrganizationId no user_model.dart, permitindo que o dono da plataforma:
- **Simule** o login dentro de qualquer tenant sem precisar de senhas extras.
- Visualize e opere módulos (Chats, Vagas, Workflow) restritos àquele tenant.
- Volte instantaneamente para a empresa matriz.

### Roteamento Seguro
O GoRouter isola as rotas:
- Um usuário validado na *Build de Admin* acessa os chats, mas tem renderizado no lado direito a PlatformConsoleScreen ao clicar no botão exclusivo.
- Componentes alheios ao Admin (notificações push/tracking passivo) são desativados para evitar poluição.

---

## 20. Chat — Recibos de Entrega/Leitura, Visualização Única no Preview e Correções do Modo Foco (27/07/2026)

Quatro ajustes de UX/bug reportados no uso diário do Desktop. Uma migration:
**`20260802100000_chat_list_read_receipts.sql`**. Feature portada do Fluxy —
código de chat/layout é compartilhado entre as marcas, então o conteúdo é o
mesmo dos dois lados (paridade).

### A) Checks de entrega/leitura na lista de conversas

**Problema:** a lista mostrava sempre **um único check**, independente do estado
real — só dava para saber se a mensagem foi lida entrando na conversa.

Duas causas somadas:

1. A RPC `get_chats_with_preview` montava o `last_message` **sem a coluna
   `status`**, então `MessageModel.fromJson` caía no default (`sent`) e desenhava
   sempre `Icons.check`.
2. **Não existia o estado "entregue".** O `status` só saía de `sent` quando o
   destinatário abria a conversa (`mark_messages_as_read`) — sem o estado
   intermediário, "1 check x 2 checks" não tinha o que distinguir.

**Banco (migration acima):**

- **`mark_messages_as_delivered(p_user_id)`** — SECURITY DEFINER com guard
  `p_user_id = auth.uid()` (o usuário só confirma as **próprias** entregas).
  Move `sent → delivered` nas mensagens dos chats em que ele é membro e que não
  foram enviadas por ele. Índice parcial `idx_messages_pending_delivery`
  (`WHERE status = 'sent'`) sustenta o UPDATE.
- **`get_chats_with_preview`** recriada (mantém a definição de
  `20260512184000`) devolvendo `last_message.status` e um novo
  **`other_read_at`** = `MAX(chat_members.last_read_at)` entre os **demais**
  membros — a mesma fonte que a bolha usa para o check azul.

**Flutter:**

- `ChatModel` ganhou `otherReadAt`; `chatsListProvider` parseia `other_read_at`
  e chama `_markIncomingAsDelivered()` na carga inicial e a cada lote de
  mensagens novas (dentro do debounce de 500 ms que já existia). O UPDATE só
  atinge linhas `sent`, então repetir é inofensivo: nenhuma linha alterada ⇒
  nenhum evento de realtime ⇒ sem loop.
- `_ChatTile._buildStatusTick()` substituiu o antigo `_getStatusIcon`: relógio =
  enviando · ✓ = enviado · ✓✓ = entregue · ✓✓ **azul** (`0xFF00B4D8`) = lido ·
  ⚠ = erro.
- `message_bubble.dart` estava **inconsistente** com isso: tratava como
  "entregue" qualquer mensagem que não fosse `sending`/`error`, ou seja, exibia
  ✓✓ cinza até para `sent`. Passou a olhar `status == delivered` de fato, então
  bolha e lista agora contam a mesma história.

**Simplificação assumida (herdada do `mark_messages_as_read`):** em grupos e
canais, **um** membro recebendo/lendo já carimba `delivered`/`read` para todos —
não há recibo por membro.

**Degradação sem a migration:** a chamada da RPC inexistente é capturada
(`debugPrint`), `other_read_at` vem nulo e o `status` ausente cai em `sent` — a
lista volta ao comportamento antigo (1 check), sem crash.

### B) Visualização única saiu do AlertDialog e virou o botão "1" (padrão WhatsApp)

O `MessageInput` abria um `AlertDialog` "Modo de Envio" **antes** de escolher a
mídia — perguntava sobre um arquivo que o usuário ainda nem tinha selecionado.

A escolha migrou para a `MediaPreviewScreen` (que já era o preview estilo
WhatsApp, com legenda e lote): botão **"1"** circular como `suffixIcon` do campo
de legenda + faixa de aviso "Visualização única · some depois de ser aberta"
quando ligado. Só aparece para foto/vídeo (`_canUseViewOnce`) — documento segue
sempre em envio normal.

- `MediaPreviewScreen.allowViewOnce` (default `false`; `true` no chat) e
  `MediaPreviewResult.isViewOnce`.
- `_handleMediaSelection()` agora só abre câmera/galeria. De quebra, corrigiu um
  efeito colateral: o botão de câmera da barra chamava `_toggleAttach()`
  incondicionalmente e **abria** o menu de anexos ao ser usado com o menu
  fechado.
- `thread_screen.dart` usa `onPickImage` sem passar pelo preview, então lá a
  mídia sai sempre em envio normal (threads são de canal; o botão em DMs/grupos
  já havia sido removido).

### C) Modo Foco: botão cobria os anexos e virou provider

O FAB do Modo Foco ficava em `left: 24, bottom: 24` do painel direito —
exatamente sobre o botão **"+"** de anexos da barra de mensagem.

- Virou **puxador de 16 px colado na borda esquerda do painel**, centralizado na
  vertical (`_FocusModeHandle`): opacidade 0.35 em repouso, 1.0 no hover, chevron
  apontando para o lado do movimento. Não disputa espaço nem com a barra de
  mensagem nem com as ações da AppBar.
- O estado saiu do `setState` local do `_DesktopMainScreenState` para o provider
  **`desktopFocusModeProvider`** (em `core/providers/desktop_selection_provider.dart`),
  porque as telas do painel direito precisam conseguir sair do modo foco.
- `Esc` agora devolve os menus **antes** de largar a conversa aberta (se está em
  foco, sai do foco; senão, limpa a seleção).

### D) Bug — tela preta ao usar a seta de voltar no Desktop

`ChatAppBar` chamava `Navigator.of(context).pop()` direto. No Desktop a conversa
não é uma rota: é um painel do master-detail (`DesktopSelection`). O `pop()`
desempilhava a **própria home**, deixando o Navigator vazio — tela preta sem
saída a não ser recarregar a página. Ficava evidente no Modo Foco, onde a seta é
o caminho natural para "voltar".

`_handleBack()` passou a checar `Navigator.canPop()`:

- **Mobile / rota empilhada** (`/chat/:id`, busca): desempilha normalmente.
- **Desktop master-detail:** desliga `desktopFocusModeProvider` e limpa
  `desktopSelectionProvider` — volta para a lista com os menus de volta.

Varredura confirmou que `ChatAppBar` era o **único** back button explícito entre
as telas do painel direito (incluindo a `PlatformConsoleScreen`); as demais usam
`automaticallyImplyLeading`, que não renderiza a seta quando `ModalRoute.canPop`
é falso.

### Pendência de deploy

A migration `20260802100000_chat_list_read_receipts.sql` **ainda não foi
aplicada** (`npx supabase db push`) — vale para os projetos Supabase das duas
marcas, cada um com o seu push. Até lá, item A opera em modo degradado (ver
acima); B, C e D são puro Flutter e já valem no próximo build.

---

## 21. Logout Automático por Inatividade — descartado (29/07/2026)

O `SessionTimeoutService` (encerrar a sessão após 30 min sem interação) existiu
só no repo da outra marca, na v1.3.0, e **nunca chegou aqui** — ficou no backlog
do sync. Foi **removido de lá** por decisão de produto: o ganho de privacidade
não compensava o atrito de deslogar quem acompanha o chat sem tocar na tela
(reunião, ligação, atendimento no balcão) e obrigá-lo a refazer senha + TOTP.

**Não portar em sincronizações futuras.** Se o arquivo
`lib/core/services/session_timeout_service.dart`, o `SessionActivityDetector` no
`builder` do `MaterialApp` ou as chamadas `.start()`/`.stop()` no
`onAuthStateChange` de `lib/app.dart` aparecerem num patch, descartar.

**Risco aceito (igual nas duas marcas):** a sessão do Supabase se renova
indefinidamente, então em desktop compartilhado quem sentar depois continua
logado como a pessoa anterior; 2FA e RLS não cobrem sessão abandonada (o JWT já
está `aal2`).

---

## 22. Persona do Assistente IA, Papéis de Canal e Blindagem de Marca (29/07/2026)

Sync vindo da outra marca (3 conjuntos de mudanças) + correção de um bug que
veio junto + eliminação da causa raiz dos vazamentos de marca entre os forks.

### A) Persona do Assistente IA por conversa

`lib/core/constants.dart` ganhou a classe **`AiAssistant`**, que espelha o
contrato da Edge Function `ai-chatbot`:

- `AiAssistant.botId` — UUID fixo do usuário-bot (`00000000-0000-4000-a000-000000000001`,
  criado na migration `20260710160000_ai_chatbot_agent.sql`).
- `AiAssistant.specializations` — as 6 personas (`geral`, `rh`, `ti`,
  `administrativo`, `comercial`, `pos_venda`). **As chaves têm de bater com o
  mapa `SPECIALIZATIONS` de `supabase/functions/ai-chatbot/index.ts`** — chave
  desconhecida cai no `geral` nos dois lados.
- `AiAssistant.normalizeSpecialization()` — replica o fallback do backend.

Um dropdown **"Especialidade do Assistente IA"** foi adicionado às configurações
de grupo (`chat_info_screen.dart`) e de canal (`channel_info_screen.dart`).
Grava em `chats.metadata` / `channels.metadata` na chave `ai_specialization`.
**Só aparece se o bot for membro da conversa** — fora disso a persona não teria
efeito. `_updateGroupMetadataKey` passou de `bool` para `dynamic` por causa do
valor string.

### B) Gestão de papéis de membro em canais

`ChannelInfoState` ganhou **`memberRoles`** (`userId -> 'admin' | 'editor' |
'viewer'`), alimentado por `channel_members.role`. Na lista de membros:

- Badge do papel (verde para admin, `tertiary` para editor; `viewer` não exibe).
- Toque abre um bottom sheet com troca de papel e remoção, **só para quem
  gerencia o workspace**. Usa `add_channel_member` (upsert com
  `ON CONFLICT DO UPDATE SET role`, serve para promover e rebaixar) e
  `remove_channel_member`. O RPC revalida no banco via `can_manage_workspace`;
  a checagem na UI só evita oferecer o que iria falhar.

### C) Mensagens de contingência do bot + correção de escopo

A `ai-chatbot` passou a postar aviso na conversa em vez de falhar em silêncio:
quando falta `GROQ_API_KEY` e quando estoura erro em runtime.

**Bug corrigido junto:** no `catch`, `record` e `conversationId` eram `const`
declarados **dentro** do `try`. O handler referenciava nomes fora de escopo, o
`ReferenceError` era engolido pelo `catch (_) {}` interno e **a contingência de
erro nunca era postada**. Agora são `let` declarados antes do `try`. O bug
existia nas duas marcas e foi corrigido nas duas.

### D) Blindagem de marca — fim dos literais

Os dois repos são o mesmo código sincronizado por overlay/patch, e o rebrand por
tokens cobria o nome do app mas **não o nome da empresa**. Resultado: o prompt do
Assistente IA daqui dizia ao colaborador do DuBairro que ele trabalhava na
**"Shineray by Sabel"**. Na auditoria apareceu um segundo vazamento, no sentido
oposto: o fallback de filiais de `user_create_tab.dart` trazia as **lojas do
DuBairro** (Guamá, Júlio César, Terra Firme) para dentro do app da outra marca.

Correções estruturais, aplicadas nas duas marcas:

| Camada | Mecanismo |
|---|---|
| Dart | `AppConstants.appName` + **`AppConstants.companyName`** (novo) |
| Edge Functions | **`supabase/functions/_shared/brand.ts`** — exporta `APP_NAME`, `COMPANY_NAME`, `LANDING_URL`, `APP_TAGLINE`, `EMAIL_LOGO_URL` |
| Guard | **`scripts/check_brand.sh`** |

`brand.ts` lê os valores de **Secrets do projeto Supabase** (cada marca tem o
seu projeto, então o valor nunca cruza), com default = marca deste repo.
Consomem: `ai-chatbot`, `app_context.ts`, `send-2fa-code`, `rh-candidatura`,
`rh-automations`. **Não existe mais nenhuma string de marca em
`supabase/functions/` fora do `brand.ts`** — `app_context.ts` e
`send-2fa-code/index.ts` ficaram idênticos entre os dois repos.

`scripts/check_brand.sh` lê `AppConstants.appName`, deduz a marca oposta e falha
(exit 1) se achar tokens dela em `lib/`, `supabase/functions/` e `web/`.
Isenções: `brand-guard:allow` (linha) e `brand-guard:allow-file` (arquivo — só
`brand.ts` e `constants.dart`, que tratam de marca por definição). `alinha`
isolado ficou fora dos tokens de propósito (raiz do português: alinhar,
alinhamento). **Rodar antes de commitar qualquer sync.**

**Mudança de comportamento:** o fallback estático de filiais em
`user_create_tab.dart` foi reduzido a `Corporativo` nas duas marcas. Nome de
filial é dado do tenant e não pode morar em código compartilhado; as filiais
reais devem sair da tabela `branches`. O fallback só dispara se essa leitura
falhar (tabela ausente ou RLS bloqueando).

### Pendência de configuração

Os Secrets **já foram configurados no projeto Supabase da outra marca**
(`APP_NAME="Fluxy"`, `COMPANY_NAME="Shineray by Sabel"`,
`LANDING_URL="https://fluxy-landing.web.app"`). **Falta fazer o mesmo aqui:**

```bash
npx supabase secrets set APP_NAME="AlinhaJá" \
                         COMPANY_NAME="DuBairro" \
                         LANDING_URL="https://alinha-ja-landing.web.app"
```

Sem isso vale o default de `brand.ts`, que já está correto para esta marca —
nada quebra, mas a identidade fica presa ao código em vez de vir do ambiente.

### Ainda não portado da outra marca

`redactPii()` na `ai-chatbot` (LGPD — o histórico de chat ainda vai cru para a
Groq, nos EUA), `SignedNetworkImage` no lugar de `CachedNetworkImage` (mídia
privada), remoção do card "Informações Pessoais" (CPF/nascimento de terceiro na
tela de conversa), `avatarBucket`, `UserModel.selectColumns` e
`_shared/cors.ts`.

---

## 23. Pacote Legal/LGPD, Composer Unificado e Cards Estruturados (v1.3.1 e v1.3.2 — 07/08/2026)

Sync da outra marca trazendo as versões **1.3.1** e **1.3.2**. Versão do app foi
de `1.3.0+30072026` para **`1.3.2+07082026`** (`pubspec.yaml`,
`AppConstants.appVersion`/`appBuild`, `web/version.json` e a tela de Novidades).

### A) v1.3.1 — Pacote legal e Central de Privacidade

Os 13 documentos ficam em `docs/legal/*.md` e essa pasta é a **fonte da verdade
única**: o app a declara como asset no `pubspec.yaml` e a landing importa os
mesmos `.md` com `?raw`. Nunca duplicar o texto em Dart ou TSX — na primeira
revisão jurídica as cópias divergem em silêncio.

- `lib/features/legal/` — repositório, providers, Central de Privacidade
  (`/privacidade`), leitor de documento (`/legal/:id`) e o `PolicyGate`.
- `PolicyGate` entra **por dentro** do `CallOverlayWrapper` no `ShellRoute`: com
  documento pendente ele substitui o app inteiro, mas a chamada em curso
  continua visível.
- `kLegalDocuments` em `legal_documents.dart` é o catálogo **único** no Dart.
  Subir a versão MAIOR de um documento com `policyType` faz a tela de aceite
  reaparecer para todos — é o mecanismo de reinformar mudança material.
  `test/legal_catalog_test.dart` guarda essa unicidade; não recriar um segundo
  catálogo em paralelo.
- `pendingPoliciesProvider` deriva de `myAcceptancesProvider` — é o que faz o
  portão sair depois do aceite. Coberto por `test/pending_policies_test.dart`.
- Direitos do Art. 18 pela própria tela: exportação em JSON (`export_my_data`) e
  abertura/acompanhamento de pedidos (`create_titular_request`,
  `titular_request`). O backend já existia aqui — a migration
  `20260803210000_titular_rights_and_policy.sql` veio no port de 30/07 **na
  variante multi-tenant** (carimbo `fn_current_org()`, `trg_force_org` e RLS de
  admin por org). Só o Dart faltava.
- Landing: rotas legais por `pathname` em `legal-routes.ts` + `legal.tsx` com
  import dinâmico (o renderizador de Markdown não pesa no bundle da home). O
  rodapé passou a gerar os links a partir do índice — documento novo aparece
  sozinho. Dependências novas: `react-markdown` e `remark-gfm`.

**Marca nos documentos legais:** os `.md` carregam os literais **AlinhaJá** e
**DuBairro**, e o `check_brand.sh` **não varre `docs/`**. Ao sincronizar com a
outra marca, trocar os tokens à mão — junto com razão social, CNPJ, DPO e
endereço, que são de outra pessoa jurídica. `docs/legal/README.md` lista os
`[CAMPOS ENTRE COLCHETES]` que ainda faltam o advogado preencher.

### B) v1.3.2 — Composer unificado e cards estruturados

Quatro composers separados (chat, canal, thread, workflow) viraram um só:
`lib/core/ui/composer/conversation_composer.dart` com um `ComposerDelegate` por
superfície (`ChatComposerDelegate`, `ChannelComposerDelegate`). Foram removidos
`message_input.dart`, `message_input_bar.dart`, `channel_attachment_sheet.dart`
e o `create_poll_sheet.dart` antigo do canal.

- Cards estruturados (enquete, evento, localização, contato) saem de
  `lib/core/ui/message_cards/` e são compartilhados entre chat e canal.
  `MessageRef` abstrai a origem da mensagem.
- Botão **"Mensagem"** no `ContactCard` abre DM 1:1 direto com o usuário.
- `workflow_main_view.dart` delega enquete/evento/localização/contato ao
  `ChannelMessageBubble` — antes esses cards não renderizavam na aba Conversa.
- **Mensagens temporárias/efêmeras foram removidas** por completo.

**Migration `20260807100000_message_actions_channel_support.sql`** — enquete de
canal não gravava: `message_actions.message_id` referenciava `messages`, e
mensagem de canal vive em `channel_messages`. Agora há uma coluna por origem com
`CHECK (num_nonnulls(...) = 1)`, dois índices únicos parciais e a policy de
SELECT enxergando os dois lados. Índice parcial não pode ser alvo de
`on_conflict` no PostgREST — por isso `setMessageAction` apaga antes de inserir
em vez de usar UPSERT. O arquivo é idempotente e espelha o que já foi aplicado
via MCP nos projetos deste repo.

### C) Correção de segurança que veio junto

A rota `/admin/edit` só validava o **tipo** de `state.extra`: bastava navegar com
um `UserModel` qualquer para abrir a edição de perfil de terceiro sem ser admin.
Passou a usar `moduleGuard('admin_panel')`, igual às demais telas
administrativas.

### D) O que ficou de fora deste sync

- `README.md` — estrutura própria desta marca, sem seção de changelog nem
  versão. Nada a portar.
- `supabase/migrations/20260709200002_fix_support_tickets_rls.sql` — existe só na
  outra marca e é anterior a esta faixa. Continua no backlog.

**Validação:** `flutter analyze lib test` sem issues, `flutter test` 73/73,
`scripts/check_brand.sh` sem vazamento e `npm run build` da landing OK.


---

## 24. Perfil Legal por Tenant — Documentos LGPD Preenchidos por Empresa (10/08/2026)

Os documentos em `docs/legal/` são um **modelo**. Num produto white label isso
não basta: cada empresa que usa a plataforma precisa do documento com a sua
razão social, o seu CNPJ e o seu Encarregado. Antes, só `[NOME_DA_EMPRESA]` era
substituído — e por uma constante de build, que aqui é o **operador da
plataforma**, não o cliente. Ou seja: o documento de um cliente sairia com o
nome de outra pessoa jurídica.

É o mesmo erro que o `check_brand.sh` existe para impedir, e que já custou meses
de bot dizendo a colaborador de uma empresa que ele trabalhava na outra. Só que
em documento de aceite, com valor probatório.

### A) O tenant já era resolvido no banco

`fn_current_org()` (de `20260728100000_platform_acting_org.sql`) devolve
`COALESCE(acting_organization_id, organization_id)` para o dono da plataforma e
a org natal para os demais. Todo o perfil legal foi construído em cima dele —
então **trocar de empresa troca o titular dos documentos**, sem código
específico. O fork de marca própria usa o mesmo código com o resolvedor simples.

### B) Migration `20260810170000_org_legal_profile.sql`

- **`get_org_legal_profile()`** — `STABLE`/`SECURITY DEFINER`, escopo na org
  corrente. Razão social, CNPJ, endereço, Encarregado (nome/e-mail/telefone),
  comarca, vigência, região de hospedagem, telefone de plantão, **mais os prazos
  de retenção efetivos** (`gps_retencao_dias`, `candidato_retencao_meses`,
  `msg_retencao_dias`).
  Os prazos entram no texto porque cada empresa configura o seu: o documento tem
  de afirmar o que o sistema faz para *aquele* tenant. Política declarada e não
  cumprida é agravante em fiscalização (Art. 15 e 16).
- **`admin_set_org_legal_profile(jsonb)`** — só `admin`/`super_admin`, e da
  **própria** org: como usa `fn_current_org()`, o dono da plataforma edita a
  empresa em que está atuando, não a natal. Faz merge em `settings.legal`
  preservando módulos e prazos, e audita **quais campos** mudaram, nunca o
  conteúdo — senão o log vira segunda cópia dos dados do cliente.
- Permissão RBAC `admin_legal` (`view`), só para **Super Admin**.

**Onde mora:** `organizations.legal_name` / `organizations.cnpj` (colunas
existentes) + `organizations.settings.legal` (JSONB), documentado no
`COMMENT ON COLUMN organizations.settings`.

### C) App Flutter

- **`lib/features/legal/models/org_legal_profile.dart`** — `OrgLegalProfile` e
  `kLegalFields`, a **lista canônica** dos 10 tokens substituíveis.
- **Substituição por token exato, nunca regex de colchetes.** Os documentos usam
  colchetes também para links Markdown, marcadores `[CONFIRMAR]`/`[VALIDAR: …]`
  e, no documento 07, os exemplos de mascaramento de PII (`[CPF]`, `[EMAIL]`,
  `[NOME]`) — regex genérico corromperia a seção que explica a anonimização.
- **Campo vazio permanece entre colchetes**, com faixa de "documento ainda não
  personalizado" listando o que falta. Empresa recém-cadastrada mostra
  claramente que o documento não está em vigor, em vez de exibir dado de
  ninguém.
- **Nova aba `Painel Administrativo → Dados Legais`**
  (`lib/features/admin/ui/tabs/legal_profile_tab.dart`) — formulário, indicador
  de completude e painel dos prazos vigentes daquele tenant.

### D) `AppConstants.isSingleTenant = false` — e por que importa

| | Este produto | Fork de marca própria |
|---|---|---|
| `isSingleTenant` | `false` | `true` |
| Razão social ausente | permanece `[RAZÃO SOCIAL]` | exibe `companyName` |

`companyName` (`DuBairro`) é o **tenant natal / operador**, não o cliente.
Nenhum caminho de código pode injetá-lo num documento — está declarado assim na
constante e o `_replacePlaceholders` do repositório é curto-circuitado quando
`isSingleTenant` é falso.

### E) Bug corrigido — troca de empresa no celular

`platform_org_switcher.dart` recarrega o app na **web** (o que reseta tudo), mas
no **celular** apenas invalida `currentUserProvider` e navega para `/chats`. O
perfil legal ficaria em cache: o dono trocaria para a Empresa B e leria a razão
social e o Encarregado da **Empresa A** nos documentos dela.

Corrigido na origem: `orgLegalProfileProvider` dá `watch` em
`currentUserProvider`, e a cascata refaz o perfil. **Não** foi resolvido com um
`invalidate` manual no switcher — quem adicionasse um provider org-scoped novo
esqueceria, e o vazamento voltaria.

### F) Landing Page

`landing-page/src/legal-routes.ts` ganhou `legalProfile`, `applyLegalProfile()` e
`missingLegalFields()` com **os mesmos tokens** do app. O site é estático e da
marca da plataforma; os documentos públicos dele não são os de nenhum cliente.
Enquanto houver campo vazio, exibe o aviso `.legal-pending`.

### G) Testes — `test/org_legal_profile_test.dart` (14 casos)

Dois deles rodam **contra os documentos reais**: nenhum placeholder sobra quando
o perfil está completo, e todo campo essencial exigido do administrador aparece
em algum documento de aceite. Os demais fixam a substituição, a completude, a
serialização da RPC e o que **não** pode ser substituído.

### H) Pendente para produção

1. ~~Aplicar a migration no projeto Supabase.~~ **Feito** — auditoria de
   20/08/2026 confirmou `policy_acceptance` e `titular_request` existentes em
   DEV (`ffsspqscpdxlmxuaiytj`) e PROD (`gpeemngsxvqjflasdody`), e o
   `PolicyGate` presente nos bundles de `alinhajadev` e `alinha-ja-app`. Se a
   tela de aceite não aparece para alguém, é porque a conta já tem as três
   linhas de aceite — conferir com `SELECT policy_type, policy_version FROM
   public.policy_acceptance WHERE user_id = auth.uid()`, não reaplicar nada.
2. Cada empresa preencher os seus **Dados Legais** — razão social, CNPJ,
   endereço, Encarregado, e-mail do DPO e vigência são essenciais.
3. No onboarding de cliente novo, incluir o preenchimento desses campos: sem
   eles a empresa opera com documentos que não estão em vigor.

**Validação:** `flutter analyze lib test` sem issues, `flutter test` 160/160,
`scripts/check_brand.sh` sem vazamento, landing com `tsc`/`eslint`/`vite build`
limpos.

### I) Captura no cadastro do tenant e release v1.3.3 (10/08/2026)

**Migration `20260810180000_platform_create_org_legal.sql`** — o perfil legal
entra no MESMO ato da criação da empresa:

- `platform_create_organization` ganhou `p_legal jsonb` e grava
  `settings.legal` na mesma transação, no formato que
  `admin_set_org_legal_profile` escreve e `get_org_legal_profile()` lê.
- A assinatura de 4 argumentos foi **derrubada** em vez de mantida: com a de 5
  tendo default, uma chamada nomeada com os 4 primeiros casaria com as duas e o
  PostgREST devolveria erro de função ambígua.
- Não dava para reaproveitar `admin_set_org_legal_profile` depois de criar: ela
  opera sobre `fn_current_org()`, e o dono da plataforma não está atuando na
  empresa recém-criada — gravaria o perfil na empresa errada.

**Console de Plataforma** — o diálogo *Nova empresa* ganhou a seção
**Dados legais (LGPD)** com razão social, CNPJ, endereço, Encarregado, e-mail do
DPO e data de vigência **obrigatórios**, mais comarca opcional. A data usa
`showDatePicker` e é gravada em ISO (`YYYY-MM-DD`), que é o formato que
`OrgLegalProfile` converte para dd/MM/yyyy na leitura.

Por que obrigatórios no cadastro e não depois: o primeiro colaborador da empresa
nova aceita os Termos no primeiro acesso. Se o perfil estiver vazio nesse
momento, o aceite recai sobre um texto que não identifica o controlador nem o
canal de exercício de direitos — como prova, vale pouco.

Ajustes posteriores continuam em `Painel Administrativo → Dados Legais`, que
também expõe região de hospedagem e telefone de plantão.

**Release:** `1.3.2+07082026` → **`1.3.3+10082026`** em `pubspec.yaml`,
`AppConstants.appVersion`/`appBuild`, `web/version.json` e a tela de Novidades.

---

## 25. Quadro Branco Colaborativo e Correções de Mídia no Web (13/08/2026)

Portada a correção de quatro defeitos de conversa e o recurso que faltava por
trás do primeiro deles. O Quadro Branco existia como texto no changelog mas
**não existia como código neste repositório** — a bolha caía no fallback de
texto simples (`🎨 Quadro branco`) porque não havia card nem tela para abrir.

**A) Quadro Branco — recurso portado por inteiro.** `lib/features/whiteboard/`
(modelo de traço, provider com replicação por Realtime, tela e widgets) e a
migration `20260810110000_whiteboards.sql`. O desenho é guardado **traço a
traço** em `whiteboard_strokes`, não como imagem: assim dá para desfazer por
autor, reabrir dias depois e continuar de onde parou. `MessageExtras` ganhou
`typeWhiteboard`/`whiteboardId`/`whiteboardTitle`, `MessageMetadata.isStructuredCard`
passou a reconhecer `isWhiteboard`, e `StructuredMessageCard` despacha para
`WhiteboardCard`. A ação `Quadro` entrou no painel de anexos dos dois composers.

*Adaptação multi-tenant:* as duas tabelas recebem `organization_id`, índice,
`trg_force_org` e policy RESTRICTIVE `tenant_isolation`, no mesmo padrão do
retrofit legado (`20260713110000_retrofit_org_chat.sql`). Sem isso, um quadro
criado com `chat_id` de outra empresa passaria pela policy permissiva de membro.

**B) Ícone do card de evento.** `Icons.schedule_rounded` tinha o mesmo formato
de relógio do indicador de "enviando"; trocado por `Icons.event_note_rounded`.

**C) Envio de documentos.** `ComposerMedia.toXFiles` checava `file.path` antes
de `file.bytes`. No Web o `path` vem vazio, então `readAsBytes()` abortava o
envio **em silêncio**. Agora `file.bytes` tem prioridade via `XFile.fromData`.

**D) Expandir imagem (lightbox).** O `onTap` exigia `!message.isOptimistic`,
bloqueando o toque em imagem recém-enviada. Agora abre com arquivo local ou
remoto; a URL remota passa por `SignedNetworkImage`.

> **Atenção (20/08/2026):** este trecho afirmava "o bucket é privado". Ele
> **não era**: sondagem em DEV e PROD mostrou `chat-media` ainda público, ou
> seja, `/object/public/{path}` servindo mídia sem passar por RLS. A
> `20260820110000_chat_media_private.sql` (ETAPA B) faz o flip e só depois
> de aplicada a frase volta a ser verdadeira. O código do app já estava
> pronto — o que faltava era o banco.

**E) Abrir e baixar documento no Web.** `launchUrl` chamado **depois** de um
`await` perde o vínculo com o clique do usuário e o navegador trata como popup,
bloqueando em silêncio. Agora há `webOnlyWindowName: '_blank'` com fallback em
`LaunchMode.platformDefault`. `SignedNetworkImage` usa `Image.network` sob
`kIsWeb` — o `CachedNetworkImage` busca pelo cliente HTTP do Flutter e esbarra
em CORS.

**F) Rejeitar cadastro (FK 23503).** `funcionario.user_id` e as colunas de
auditoria não tinham `ON DELETE SET NULL`, e `admin_reject_user` apagava de
`auth.users` antes de desvincular. Migration
`20260813130000_fix_admin_reject_user_fk_cascade.sql`.

**G) Redefinir senha por administrador (42703).** `edit_profile_screen.dart`
**já chamava** `admin_update_user_password`, uma RPC que não existia no banco
deste projeto. Migration `20260813140000_add_admin_update_user_password_rpc.sql`.

**H) RBAC de anúncio oficial — permissão própria, travada no banco.** Publicar
comunicado deixou de ser sinônimo de administrar o canal: o módulo RBAC
`comunicacao_anuncios` (`create` / `manage` / `view_stats`) separa RH e
Comunicação de quem gere a lista de membros. O composer passou a receber
`canAnnounce` (de `canPublishAnnouncementProvider`) no lugar do toggle antigo
`isAnnouncement`/`onToggleAnnouncement`, que liberava o anúncio para qualquer
admin do canal.

*Por que travar no banco:* esconder o botão não impede nada — `metadata` é campo
livre e qualquer cliente autenticado insere `type = 'announcement'` chamando a
API direto. A migration `20260810100000_announcement_rbac.sql` cria
`has_rbac_permission()` e policies **RESTRICTIVE** em `messages` e
`channel_messages`, que fazem AND com as permissivas existentes (inclusive com o
`tenant_isolation` deste repositório) sem reescrever nenhuma delas.

O anúncio ganhou prioridade, prazo (`valid_until`), público-alvo, anexo e botão
de ação, todos em `metadata` via `AnnouncementSpec`; a bolha inline antiga deu
lugar ao `AnnouncementCard`, compartilhado por canal e grupo — antes grupo não
tinha o recurso. `20260810160000_fix_get_announcement_stats_hybrid.sql` faz o
painel de confirmações funcionar nas duas origens: a versão anterior só olhava
`ma.message_id`, então em canal (`channel_message_id`) o ack vinha sempre nulo e
todo mundo caía em "Pendentes".

*Nota:* as permissões nascem sem perfil vinculado — até alguém atribuir
`comunicacao_anuncios:create` na tela de Gestão de Acessos, só `admin` e
`super_admin` publicam.

**I) Localização com pino em mapa.** `_shareLocation` mandava a posição atual e
pronto (`LocationShareService.capture()`). Agora abre `LocationPickerScreen`
centrado no GPS, mas quem manda é o pino: dá para enviar o endereço do cliente,
a obra, o ponto de encontro — e nomear (`label`). `flutter_map` e `latlong2` já
estavam no `pubspec.yaml`.

**Movimentação estrutural:** `branchesProvider` saiu de
`features/admin/ui/tabs/user_create_tab.dart` para `core/providers/org_providers.dart`.
Quatro telas o importavam atravessando features só para alcançá-lo, e agora o
composer de anúncio (que vive em `core`) também precisa dele — `core` não pode
depender da UI de um módulo.

---

## 26. Sincronização de Migrações Portadas do Fluxy, Vault `edge_anon_key` e Vínculo DuBairro (13-14/08/2026)

**A) Provedor de Segredo no Vault (`edge_anon_key`):**
- As chaves anon/publishables de DEV (`ffsspqscpdxlmxuaiytj`) e PROD (`gpeemngsxvqjflasdody`) foram provisionadas remotamente no Vault do Supabase via `SELECT vault.create_secret('<anon_key>', 'edge_anon_key')`.
- Alimenta a RPC `get_edge_anon_key()`, permitindo aos triggers de webhook enviar o cabeçalho `Authorization: Bearer <edge_anon_key>` exigido pelo Gateway de Edge Functions do Supabase para o AI Chatbot sem expor segredos nem gerar hardcodes no controle de versão.

**B) Migrações Portadas (20260813150000 até 20260813153000):**
- `20260813150000_fix_ai_chatbot_auth_header.sql`: Header `Authorization: Bearer` lido do Vault no `trg_ai_chatbot()`.
- `20260813151000_fix_admin_create_user_phone_null.sql`: Normaliza `phone` para `NULL` (evita conflito de chave duplicada na constraint `users_phone_key`).
- `20260813152000_fix_admin_list_users_pii_volatile.sql`: `admin_list_users_pii` alterado para `VOLATILE` autorizando o `INSERT INTO public.rh_access_log` da auditoria LGPD.
- `20260813153000_reassert_handle_new_user.sql`: Reafirma o trigger de criação de usuário com `COALESCE(full_name, email)`.
- *Omissão defensiva*: A 5ª migration de RLS de FCM foi omitida por ser comprovadamente redundante em relação ao `trg_force_org` já ativo em `user_fcm_tokens`.

**C) Vínculo Massivo de Funcionários DuBairro:**
- Script de vínculo executado via MCP nos bancos DEV e PROD.
- Todos os colaboradores da organização `DuBairro Supermercados` (`a0000000-0000-4000-8000-000000000001`) foram vinculados a registros com `status = 'ativo'` em `public.funcionario` (6 em DEV, 186 em PROD; 0 pendentes).


## 27. Guarda de Administrador que Falhava Aberta e `chat-media` Privado (20/08/2026)

Auditoria de paridade entre os dois forks. As duas correções abaixo nasceram
juntas e foram aplicadas **nos dois repositórios**, com o mesmo corpo SQL.

### A) Escalonamento de privilégio com a chave `anon` (crítico)

Cinco RPCs administrativas (`admin_toggle_user_status`, `admin_update_user_role`,
`admin_update_user`, `admin_reject_user`, `admin_update_user_password`) checavam
o papel do chamador assim:

```sql
SELECT role_level INTO v_caller_role FROM public.users WHERE id = auth.uid();
IF v_caller_role NOT IN ('super_admin', 'admin') THEN RAISE ...
```

Sem linha em `public.users` — papel `anon`, conta removida, pendente ou inativa —
`v_caller_role` fica NULL, e **`NULL NOT IN (...)` é NULL, não TRUE**. O `IF` não
dispara e a execução segue para o `UPDATE`. Sendo `SECURITY DEFINER`, o UPDATE
roda como dono e ignora RLS. Some-se a isso o `EXECUTE` que o Postgres concede a
`PUBLIC` por padrão: as funções eram alcançáveis com a chave `anon`, que é
pública e vai embarcada no bundle web.

Em `admin_update_user_role` a trava de promoção tinha o mesmo vício
(`TRUE AND NULL` = NULL), então nem promover a `super_admin` barrava.

**Medido em 20/08/2026 com a chave anon:** em DEV e em PROD, `admin_toggle_user_status`, `admin_update_user_role` e
`admin_update_user` retornaram **200 com corpo vazio** — execução bem-sucedida.
`admin_reject_user` passou da guarda e só abortou por um erro de coluna.

Correção em `20260820100000_fix_admin_rpc_null_role_bypass.sql`, em duas camadas
porque nenhuma sozinha cobre todos os chamadores:

1. **`fn_assert_admin(p_acao)`** — guarda única, NULL-safe (`IS NULL` **antes** do
   `NOT IN`), que também exige `is_active`. Existir uma só guarda é o ponto: o
   vício se espalhou por cópia.
2. **`REVOKE EXECUTE ... FROM PUBLIC, anon`** — corta o anônimo antes de a função
   rodar. A camada 1 continua necessária para o usuário **autenticado** cuja
   linha em `users` sumiu ou está inativa.

As funções são derrubadas por OID antes de recriadas (`DROP FUNCTION` sem
CASCADE, varrendo todas as sobrecargas). Um `DROP` com assinatura fixa viraria
no-op onde a assinatura viva divergisse — e o `CREATE` seguinte criaria uma
**sobrecarga**, deixando a versão vulnerável no ar e tornando a chamada ambígua
para o PostgREST.

De quebra, `admin_reject_user` referenciava `candidato.usuario_id`, coluna que
não existe em nenhum dos bancos (a tabela tem `created_by`, `updated_by`,
`deleted_by` e `responsavel_id`). A função abortava com 42703 **sempre** — rejeitar um cadastro nunca funcionou
aqui. Era só esse erro que impedia o bypass acima de causar dano por essa porta;
corrigir a coluna sem corrigir a guarda tornaria a função explorável, por isso as
duas coisas vão na mesma migration.

### B) `chat-media` privado — a ETAPA B que faltava

`20260803130000` (ETAPA A) instalou autorização por membership no bucket e
anunciava no cabeçalho uma ETAPA B `20260803140000`, que nunca foi escrita: virar
o bucket antes de o app publicar URLs assinadas quebraria toda a mídia. O app tem
`MediaUrlResolver` e `SignedNetworkImage` desde a v1.3.5 (13/08/2026), então o
pré-requisito está cumprido.

A ETAPA B saiu como **`20260820110000_chat_media_private.sql`** — timestamp de
hoje, porque aplicar uma migration com data anterior às já aplicadas as coloca
fora de ordem. Ela aborta se as três policies da ETAPA A não existirem (virar o
bucket sem elas tiraria a mídia do ar para todo mundo) e confere o resultado em
vez de confiar no `UPDATE`.

**Estado medido em 20/08/2026:** `chat-media` estava **público** em DEV e em
PROD — `/object/public/{path}` servindo foto de DM privada, áudio, PDF e anexo
de workflow com CPF/CNPJ sem passar por RLS. No Fluxy o bucket já estava
privado, o que serve de prova de que o app funciona nesse modo.

`avatars` continua público de propósito nos dois forks: a foto de perfil aparece
em listas e menções por toda a aplicação.

### C) Método de verificação

O token do Supabase CLI não alcança os projetos do AlinhaJá, então a auditoria
sondou por REST com a chave anon. Vale registrar as armadilhas:

- **RPC:** `POST /rest/v1/rpc/<nome>` **com os nomes de argumento corretos**.
  Payload incompleto devolve `PGRST202`, que é indistinguível de "função não
  existe" — três falsos negativos nesta auditoria vieram daí.
- **Tabela:** `42501` = existe (RLS barrou); `PGRST205` = não existe.
- **Edge Function:** `404 not found` = não deployada; qualquer outra = no ar.
- **Bucket:** `GET /storage/v1/object/public/<bucket>/<inexistente>` →
  `Bucket not found` = privado; `Object not found` = público.

### D) Tour guiado perdido no primeiro acesso

O `PolicyGate` devolve `child` enquanto a consulta de aceites está **carregando**
(`maybeWhen(..., orElse: () => child)`, fail-open deliberado). Isso faz o
`MainScaffold` montar antes de se saber se há documento pendente — e o
`initState` dele disparava `launchOnboarding` num `addPostFrameCallback`, sem
checar nada.

No primeiro acesso real (aceite pendente) a sequência era:

1. `MainScaffold` monta durante o `loading` e empurra o `WelcomeIntroScreen` no
   **rootNavigator**, acima de tudo;
2. a consulta resolve, o portão troca o app pela tela de consentimento;
3. o carrossel fica por cima do aceite;
4. `markSeen` é gravado assim que o carrossel é fechado;
5. `showHomeTour` é pulado, porque o `context` do scaffold já foi desmontado.

Resultado: **quem entrava pela primeira vez — exatamente o público do tour —
perdia o tour para sempre**, e ainda via o carrossel na frente do consentimento.

Correção em `main_scaffold.dart`: `_talvezAbrirOnboarding()` só dispara quando
`pendingPoliciesProvider` já resolveu **e** não há documento pendente. Com
aceite pendente não faz nada — o scaffold vai ser desmontado e, depois do
aceite, remontado, e aí o `initState` roda de novo com o caminho livre. Um
`ref.listen` no mesmo provider cobre o caso de quem já aceitou tudo e permanece
montado na transição `loading → data`. Erro na consulta segue em frente, para
acompanhar o mesmo fail-open do portão.

O flag `_onboardingDisparado` evita o carrossel abrir duas vezes, já que a
tentativa acontece em dois momentos. "Rever tutorial" não passa por aí — chama
`launchOnboarding(reset: true)` direto — e ficou intacto.

### E) Estado do preenchimento automático dos documentos

O mecanismo está correto: `LegalDocumentView` lê `legalDocumentTextProvider`,
que aplica `OrgLegalProfile.apply()` sobre o markdown, e um aviso lista
nominalmente os campos que faltam quando o perfil está incompleto.

O que **não** existe é semeadura: nenhuma migration preenche `settings.legal`
das empresas já criadas. `20260810180000` só tornou os dados obrigatórios no
cadastro de empresa NOVA, pelo Console de Plataforma. Toda organização anterior
a 10/08/2026 opera com o perfil vazio até um admin preencher em
**Painel Administrativo → Dados Legais** — e, até lá, os documentos aparecem com
os `[CAMPOS ENTRE COLCHETES]` e o aviso de "documento ainda não personalizado".

Para conferir por empresa:

```sql
SELECT id, name, legal_name, cnpj, settings->'legal' AS legal
  FROM public.organizations;
```

---

## 28. Release v1.3.6 — Anexos no Quadro Branco, Recibos de Mensagem e RH Guiado (20/08/2026)

**A) Anexos no Quadro Branco (`20260820120000_whiteboard_attachments.sql`):**
- Criação da tabela `public.whiteboard_items` para abrigar imagens e arquivos posicionados no espaço lógico `0..1000`.
- Anexos vivem sob o bucket privado `chat-media` (`chats/{id}/`), sob as políticas de membership da ETAPA A.
- Introdução da ferramenta **Mover** para arrastar e redimensionar elementos com replicação Realtime.
- Decisão de renderização: itens ficam sob os traços (folha branca separada) e borracha utiliza `BlendMode.clear` para não criar artefatos brancos sobre imagens.
- Trigger `trg_wb_items_geometry_only` garante que apenas coordenadas/geometria possam ser atualizadas por membros (impedindo substituição arbitrária de arquivos alheios).

**B) Recibos e Informações da Mensagem (`20260820130000_message_receipts.sql`):**
- Adição da coluna `last_delivered_at` em `chat_members` e `channel_members`.
- Menu de contexto (long press) ganhou a ação **Informações**, detalhando nominalmente:
  1. *Lidas*: membros com `last_read_at >= created_at`.
  2. *Entregues*: membros com `last_delivered_at >= created_at` mas sem leitura.
  3. *Pendentes*: aparelhos que ainda não sincronizaram.
- Otimização com throttle de 30s para evitar tempestade de escritas Realtime em grupos movimentados.

**C) Estados Vazios Educativos no Módulo de RH:**
- Componentes `HrEmptyState`, `HrEmptyBlock`, `HrGhostList` e `HrGhostBoard` aplicados em 28 telas.
- Separação clara entre "Sem registros" (orientação para primeiro cadastro) e "Filtro sem resultados" (ação para limpar busca).

**D) Versionamento Monotônico:**
- Release: `1.3.5+30081300` → **`1.3.6+30082000`** em `pubspec.yaml`, `AppConstants`, `web/version.json` e `changelog_screen.dart`.

---

## 29. Otimizações de Mídia, Perímetro de Workspaces, Auditoria e Busca Global (21/08/2026)

**A) Otimizações de Desempenho e Cache de Mídia:**
- `MediaCacheManager` e `MediaUrlResolver`: introduzido cache síncrono em memória (`peek()`, `cachedFileFor()`), evitando repetição de queries SQLite e criação de `FutureBuilder` contínuos nos balões de mensagem (`message_bubble.dart`, `channel_message_bubble.dart`).
- Deduplicação de downloads e assinaturas concorrentes em voo.
- Capeamento de decodificação de imagem para 48 avatares com `CachedNetworkImageProvider(..., maxWidth: 320)`, reduzindo significativamente o consumo de memória RAM.
- Debounce de 2s no `_markAsRead` do `active_channel_provider`.

**B) Perímetro de Segurança de Canais e Workspaces (F-01 a F-05):**
- `20260821100000_channel_membership_perimeter.sql`: remoção da policy de auto-inscrição aberta em `channel_members`, coluna `visibility` (`public`/`private`) e RPC segura `set_channel_visibility`.
- `20260821110000_channel_posting_permission_rls.sql`: policy RESTRICTIVE travando no banco que apenas usuários com permissão (`can_post_in_channel`) publiquem em canais restritos/murais.
- `20260821120000_workflow_audit_trail.sql`: trigger de auditoria de alterações em cards (`fn_tg_workflow_card_history`), registro de entrada/saída de membros em `audit_log`, e revogação de UPDATE direto na coluna `status` de `workflow_cards` (forçando o uso da RPC `update_workflow_card_status`).

**C) Busca Global Acelerada e Painel Minha Operação (U-01 a U-03):**
- `20260821130000_search_indexes.sql`: índices GIN trigram (`pg_trgm`) em mensagens, mensagens de canal e cards de workflow.
- Busca global agora abrange `channel_messages` e `workflow_cards`.
- Nova tela de visão operacional agregada `/minha-operacao` (`my_operation_screen.dart`).

**D) Versionamento Monotônico (v1.3.7):**
- Release: `1.3.6+30082000` → **`1.3.7+30082100`** em `pubspec.yaml`, `AppConstants` (`appVersion` e `appBuild`), `web/version.json` e `changelog_screen.dart`.

---

## 30. Auditoria Geral de Segurança, Hardening LGPD e Estabilidade (03/09/2026 — v1.3.8)

### A) Segurança e Privacidade (LGPD)
1. **Revogação de Privilégio `SELECT (phone)` em `users` (`20260903140000_revoke_phone_column_privilege.sql`)**:
   - `phone` revogado para `authenticated`; acesso restrito ao titular via `get_my_sensitive_profile()` ou auditoria via `admin_list_users_pii()`.
2. **Troca Obrigatória de Senha Inicial (`20260903140100_must_change_password.sql`)**:
   - Coluna `must_change_password` em `users`; interceptação no login para definir senha própria no primeiro acesso.
3. **Remediação Geral de Segurança (`20260903170000_security_audit_remediation_12_findings.sql`)**:
   - Eliminação de policies residuais em `branches`.
   - `SET search_path = ''` e qualificação explícita `public.` em funções `SECURITY DEFINER`.
   - Expurgos de fotos de perfil no storage em desativação/exclusão de usuários (LGPD Art. 18).
4. **Correções de Enums Qualificados e Permissões (`20260904100000` e `20260904123000`)**:
   - Qualificação explícita `public.workflow_action_type` na RPC `approve_workflow_card`.
   - Concessão de `SELECT (must_change_password)` para `authenticated` na tabela `users`.

---

## 31. Diretriz de Paridade com o Fluxy e Exclusões de Migração (08/09/2026)

> ⚠️ **REGRA DE PARIDADE E EXCEÇÃO CRÍTICA — NÃO PORTAR MIGRATION 20260908150000**:
> No dia 08/09/2026, foi executada no projeto-base Fluxy a migration:
> `20260908150000_sync_and_clean_employees_mapping.sql`.
> 
> **Esta migration NÃO DEVE SER PORTADA, COPIADA OU REPLICADA NO ALINHAJÁ SOB HIPÓTESE ALGUMA.**
> 
> **Motivos Fundamentais**:
> 1. **Isolamento de Tenant**: O Fluxy é uma implantação single-tenant exclusiva para a **Shineray By Sabel**. A referida migration sincroniza 87 colaboradores reais da Shineray e realiza expurgos na organização fixa `a0000000-0000-4000-8000-000000000001`.
> 2. **Arquitetura Multi-Tenant do AlinhaJá**: O AlinhaJá atende a múltiplos clientes (Rede DuBairro, etc.). Inserir e-mails `@shineraybysabel.com.br` ou dados nominais da Shineray violaria gravemente a LGPD, o compliance e o isolamento de tenants da plataforma.
> 3. **Auditoria de Migrações**: Qualquer agente de IA ou desenvolvedor que for auditar a paridade entre os repositórios Fluxy e AlinhaJá deve considerar que **todas as migrations até `20260904123000_grant_select_must_change_password.sql` estão em 100% de paridade**, e que a `20260908150000` é uma exceção de dados exclusiva do Fluxy a ser **expressamente ignorada e excluída de checklists de paridade**.

---

## 32. Notificações estilo WhatsApp, Auditoria de Segurança/LGPD e Review de Canais e Workspaces (16/09/2026 — v1.3.9)

*(Equivalente à Seção 41 do repositório irmão Fluxy, adaptado para a arquitetura multi-tenant e marca AlinhaJá / DuBairro).*

### A) Notificações
- **Android**: renderização nativa em `lib/core/services/notifications/` — `NotificationStore` (cache persistente em SharedPreferences com `reload()`, compartilhado entre isolates com lock e deduplicação), `ChatNotificationRenderer` (MessagingStyle, avatar circular em 128 px, resumo agrupado, badges e sons), `NotificationActionBridge` (ações de resposta rápida e marcação de leitura executadas pelo isolate principal quando ativo) e `RestSessionGateway` (comunicação REST direta com o Supabase com tokens persistidos quando o app está em background ou fechado).
- **Ids de notificação**: identificadores estáveis derivados via FNV-1a (`stableNotificationId`), garantindo consistência entre isolates e versões do app.
- **Web/PWA**: arquitetura push orientada a dados (data-only). `web/notification-format.js` unifica o contrato de formatação para o Service Worker (`firebase-messaging-sw.js`) e para o runtime da aplicação (`window.alinhajaShowPushNotification`).
- **Servidor**: biblioteca compartilhada `supabase/functions/_shared/fcm.ts` (prévia de conteúdo adaptada por tipo de mídia, limite seguro de 300 caracteres, tratamento fail-safe de erro com deleção de token apenas em falhas `UNREGISTERED`). Notificações de chamada com TTL restrito a 60s. Canal específico no Android: `alinhaja_workflow_alerts`.
- **Trigger de push de mensagens**: migração `20260916130000_version_chat_push_triggers.sql`, criando a automação no banco de dados apenas quando nenhum trigger concorrente estiver chamando a função `send-chat-notification`.

### B) Auditoria de Segurança e LGPD
- **Migration `20260916120000_security_audit_2026_09_16.sql`**:
  - RPCs que recebem `p_user_id` passam a validar a identidade da sessão autenticada (`auth.uid()`).
  - Funções obsoletas com falhas de isolamento (`update_workflow_status`, `get_workflow_cards`) formalmente revogadas.
  - `get_workflow_metrics` convertida para `SECURITY INVOKER` respeitando as regras RLS do chamador.
  - Política de segurança restritiva em `meeting_transcriptions`.
  - Guarda `fn_assert_same_org` acoplada às 5 RPCs administrativas para blindagem contra mutações cross-tenant.
- **Edge Functions**:
  - Sanitização e escape estrito de HTML em templates de e-mail (`_shared/html.ts`).
  - Geração de OTP para autenticação 2FA utilizando gerador seguro de números pseudoaleatórios criptográficos (CSPRNG via `crypto.getRandomValues`).
  - Guardas de autorização JWT em `send-call-notification` e `rh-automations`.
  - Comportamento fail-closed implementado nas funções de push notification.

### C) Review de Canais e Workspaces (Migration `20260916140000`)
- **Pedidos de Entrada**: função auxiliar `can_review_channel_join_request()` criada para substituir subconsultas com identificadores ambíguos nas policies de SELECT, UPDATE e DELETE.
- **`update_channel_info`**: sanitização de metadata com merge raso e descarte forçado de campos reservados (`assignment_mode`, `operator_ids`, `default_operator_id`, `operator_count`, `archived`, `archived_at`); validação das permissões de publicação (`posting_permission`).
- **`get_channel_message_counts()`**: convertida para `SECURITY INVOKER`, desconsiderando mensagens deletadas e remetentes nulos.
- **Aplicativo Flutter**:
  - Stream de mensagens com ordenação estrita e limitação inicial (`limit(200)`).
  - Exclusão atômica de canais executando a RPC no banco antes de expurgos no Supabase Storage.
  - Verificação de erro silencioso de RLS na aprovação de solicitações de entrada.
  - Liberação de comentários do solicitante em cards de workflow independentemente de status final.
  - Carregamento concorrente na descoberta de canais.
  - Acesso direto ao painel "Minha Operação".

### D) Governança, Sucessão de Administrador e Notificações de Conta
- **Governança Multi-Tenant e Canais Privados (`20260916170000` e `20260916180000`)**:
  - `can_manage_workspace`: isolamento estrito de tenant validando `c.organization_id IS DISTINCT FROM public.fn_current_org() AND NOT public.fn_is_platform_owner()`.
  - Gestores globais não possuem acesso a workspaces privados (`visibility = 'private'`) dos quais não participem formalmente; apenas super administradores globais ou participantes do canal possuem controle.
  - Membros com permissão `editor` não possuem permissão para promover a si mesmos ou a terceiros para `admin`, nem para rebaixar ou remover administradores existentes.
- **Sucessão Obrigatória do Último Administrador (`20260916150000`)**:
  - Ao tentar sair de um canal (`leave_channel`) onde seja o único administrador remanescente e existam outros membros, o usuário é bloqueado pela política RLS e deve selecionar obrigatoriamente um sucessor via diálogo `ChannelSuccessorPicker`. O sucessor é promovido atomicamente a administrador e recebe notificação push.
- **Notificações de Rejeição de Entrada e Desativação de Conta**:
  - Ao ter uma solicitação de entrada rejeitada em um canal fechado, o usuário recebe notificação push através da trigger `trg_notify_channel_join_rejected`.
  - Candidatos rejeitados pelo painel administrativo recebem e-mail formal via Edge Function `send-account-notification` com o motivo da decisão.

### E) Correção na URL Base das Automações de RH (`20260916160000`)
- A trigger `fn_tg_rh_automacao_notify` concatenava a URL base das Edge Functions sem o prefixo padrão `/functions/v1`. O disparo HTTP resultava em erro 404 e os e-mails de notificação automática de candidatura e movimentação de fases não eram entregues. Corrigido com a normalização canônica da URL da API de Edge Functions.

---

## 33. RBAC Unificado por Módulo no RH, Friendly Errors, View-Once Tolerante e Otimizações Web (22/09/2026 — v1.3.10)

*(Equivalente à Seção 42 do repositório irmão Fluxy, adaptado com rigor para a arquitetura multi-tenant e identidade visual AlinhaJá / DuBairro).*

### A) RBAC Unificado por Módulo no RH e Auditoria de Segurança
- **Desacoplamento de `role_level` / `hr_role`**: Anteriormente, a interface exibia os menus conforme a matriz RBAC, mas as policies RLS e RPCs no banco de dados ainda validavam `users.role_level` ou `hr_role` (`fn_is_rh()`), fazendo com que qualquer administrador comum tivesse acesso irrestrito a salários e dados de RH mesmo sem o papel correspondente.
- **Helper Central `fn_rh_pode(p_module, p_action)` (`20260918110000`)**:
  - Nova função `SECURITY DEFINER` que verifica a posse da permissão RBAC específica para o módulo em questão (`rh_banco_talentos`, `rh_funcionarios`, `rh_onboarding`, `rh_documentos`, `rh_ausencias`, `rh_ponto`, `rh_holerites`, `rh_beneficios`, `rh_desempenho`, `rh_automacoes`, `rh_alertas`).
  - A permissão `manage` herda e implica automaticamente a leitura (`view`).
  - Usuários com `role_level = 'super_admin'` mantêm bypass administrativo seguro em todas as checagens.
  - As funções legadas `fn_is_rh()` e `fn_is_rh_admin()` foram refatoradas para consultar `fn_rh_pode_algum('view')` e `fn_rh_pode_algum('manage')`.
- **Blindagem Hierárquica em `fn_assert_same_org` (`20260918100000`)**:
  - Administradores comuns não podem mais alterar, redefinir senha, rebaixar ou desativar usuários com nível `super_admin`.
- **Integridade Temporal do Ponto e Visualização de Holerites (`20260918100000`)**:
  - `fn_tg_rh_ponto_hora_servidor`: Registros de ponto do próprio colaborador sempre assumem `now()` do servidor, prevenindo adulteração de relógio no cliente.
  - `fn_tg_rh_holerite_somente_visualizacao`: Colaboradores comuns só têm autorização para atualizar o campo `data_visualizacao` do próprio holerite (com carimbo do servidor), protegendo os dados de proventos, descontos e anexos PDF contra mutação.
- **RPC `rh_soft_delete_candidato` (`20260918100000`)**:
  - Criação da RPC oficial de exclusão lógica com verificação estrita de tenant e permissão `rh_banco_talentos:manage`.
- **Transação Atômica de Perfis (`rbac_set_role_permissions`)**:
  - Substituiu a deleção e inserção de permissões de perfil em requisições separadas por uma única RPC atômica, eliminando o risco de perfis ficarem desprovidos de acessos em falhas intermediárias de rede.
- **Políticas e RPCs Unificadas (`20260918110100` a `20260918110600`)**:
  - Atualização sistemática de todas as políticas RLS em tabelas satélites de candidatos, onboarding, catálogo de cargos/áreas e Storage de RH (`rh-curriculos`, `rh-fotos`, `rh-documentos`).
  - Refatoração de mais de 25 RPCs em talentos, funcionários, onboarding, documentos, ausências e gestão para consumo exclusivo via `fn_rh_pode`.

### B) Friendly Errors (Tratamento Humanizado de Exceções)
- **Centralizador `friendly_error.dart`**: Mapeamento centralizado de códigos de erro do PostgreSQL e PostgREST (`42501`, `P0001`, `23502`, `23503`, `23505`, `23514`, `22P02`, `PGRST116`, `PGRST301`) e exceções de rede, autenticação e Storage em mensagens amigáveis em português brasileiro, eliminando alertas técnicos crípticos na interface do usuário.

### C) Visualização Única Tolerante (View-Once)
- **Correção no Supabase Storage (`20260919100000`)**:
  - Como o Supabase passou a recusar deleções diretas via SQL na tabela `storage.objects`, a exclusão da mensagem na RPC `mark_view_once_opened` foi isolada de uma tentativa em subtransação segura. Se a deleção SQL falhar, a mensagem ainda é consumida e o client do chat realiza a limpeza do arquivo via Storage API utilizando o path devolvido.
- **Componente `ViewOnceBubble`**:
  - Novo widget de renderização para mídias efêmeras com controle visual de visualizado, carregamento e animações de destruição.

### D) Otimizações do Banco e Plataforma Web
- **`fn_is_admin()` Estabilizada (`20260919110000`)**:
  - A função voltou a ter o marcador `STABLE`, permitindo que o planejador de consultas do PostgreSQL armazene em cache e otimize avaliações em batch de RLS em dezenas de tabelas simultaneamente.
- **Resiliência no Carregamento de Configurações**:
  - `main_admin.dart`: Carregamento do arquivo `.env` protegido com flag `isOptional: true`, prevenindo crashes na inicialização da aplicação web administrativa em ambientes onde variáveis são injetadas via runtime flags.
- **WebRTC e Timeouts**:
  - Aprimoramentos de estabilidade na finalização e limpeza de sessões no `CallService` e `SessionTimeoutService`.

---

## 34. Repositório Próprio, Limpeza de Segurança e Fase 0 da Arquitetura (26–28/10/2026)

Plano completo em `docs/PLANO-EVOLUCAO-ARQUITETURA.md`.

### A) Separação dos produtos
- **AlinhaJá** (white-label, multiempresa, disponível para distribuição ou aquisição) passa a viver em `DelcioFDNeto/AlinhaJa`, branch `main`, iniciado com histórico limpo. **Fluxy** (exclusivo da Shineray, empresa única) continua em `DelcioFDNeto/Fluxy`.
- **Fim da paridade automática.** As diretrizes de porte das seções 26 e 31 deixam de valer: um recurso só passa de um produto ao outro por decisão explícita.
- **Componentes neutros por cópia idêntica:** `_shared/mailer.ts`, `_shared/mailer_test.ts`, `_shared/html.ts`, `_shared/fcm.ts`, `.github/workflows/ci.yml`, `scripts/check_brand.sh` e `scripts/comparar_componentes_comuns.sh`. Conferência: `bash scripts/comparar_componentes_comuns.sh ../Fluxy`.

### B) Limpeza de segurança
- **Conta mestre removida:** `handle_new_user()` promovia a super_admin ativo quem se cadastrasse com um e-mail fixo. Nova versão em `20261028120000_remove_conta_mestre_handle_new_user.sql`: todo cadastro nasce `member`, inativo e bloqueado. As regras de e-mail fixo também saíram das versões antigas da função (inertes). Contas existentes não mudam.
- **Primeiro administrador:** `supabase/scripts/promover_super_admin.sql`, executado como postgres na instalação (`-v email=...`, opcional `-v dono_plataforma=sim`). Exige conta existente e registra `user.promoted_super_admin` em `audit_log`.
- **Conta de sistema** (`00000000-0000-0000-0000-111111111111`): o seed usa senha aleatória; `20261028120100_senha_conta_sistema.sql` troca a senha original só se a conta ainda estiver bloqueada e avisa se ela estiver liberada.
- **Fora do repositório:** seeds com dados de funcionários da Shineray, scripts com dados pessoais de funcionários do DuBairro e `recover_user_data.sql` (obsoleto: usava papéis inexistentes e derrubaria todo cadastro).
- `run_seed.js` lê `DATABASE_URL`; a senha do banco DEV estava no código.
- `test/sem_contas_fixas_test.dart` prende os invariantes: nenhuma promoção por e-mail fixo, nenhuma senha ou conexão com senha em código, nenhum dado da Shineray no produto.
- **Instalação nova:** migrations antigas semeiam a estrutura da concessionária. O runbook (`docs/RUNBOOK-INSTALACAO-DUBAIRRO.md`, etapa 10) remove esses registros com os scripts `01_` e `02_` logo após as migrations, antes de qualquer dado do cliente.

### C) Fase 0 do plano de evolução
- **Assistente IA por empresa:** o prompt do `ai-chatbot` usa `organizations.name` da conversa, não o `COMPANY_NAME` do deployment.
- **Configuração em tempo de execução:** o app Web lê `config.json` ao lado do `index.html` antes de iniciar o Supabase (`lib/core/config/runtime_config*.dart`). Prioridade: `config.json` → `--dart-define` → `.env`. Arquivo ausente, inválido ou HTML do rewrite do Firebase Hosting mantém os valores do build.
- **`AppEnv.appBaseUrl`** substitui os domínios fixos na redefinição de senha e na página de carreiras.
- **E-mail independente de provedor:** `_shared/mailer.ts` com `SMTP_HOST/PORT/USER/PASSWORD/FROM_EMAIL`; `GMAIL_*` continua aceito. SMTP próprio da empresa (RH) tem prioridade, e um cadastrado incompleto não cai no servidor global.
- **`rh-gerar-questoes`:** corrigido o `ReferenceError` (`corsHeaders` fora de escopo) que derrubava toda resposta desde 30/07/2026.
- **CI** (`.github/workflows/ci.yml`): `flutter analyze` e `flutter test` com Flutter **3.41.9** (versão compatível com o `pubspec.lock`), `deno check` e `deno test` das Edge Functions, guarda de marca.

---

## 35. White-label: Marca do Produto e Identidade Visual por Empresa (28/10/2026)

Fase 2 do `docs/PLANO-EVOLUCAO-ARQUITETURA.md`. Guia de uso para distribuidores e administradores: `docs/GUIA-MARCA-DISTRIBUIDOR.md`.

### A) Marca do produto (build)
- `AppConstants.appName = String.fromEnvironment('BRAND_NAME', defaultValue: 'AlinhaJá')` e `AppConstants.primary = Color(int.fromEnvironment('BRAND_PRIMARY_COLOR', defaultValue: 0xFFD21A18))`. Continuam `const`. O formato da cor é `0xFFRRGGBB`; outro formato cai no padrão sem aviso.
- `AppConstants.nomeOriginalDoProduto`: nome com que os textos-fonte foram escritos. `legalDocumentTextProvider` troca esse nome por `appName` antes de aplicar o perfil legal.
- `scripts/aplicar_marca.sh --nome --cor [--descricao]`: edita `web/index.html`, `web/manifest.json` e o `android:label`, e imprime o restante da lista.
- `scripts/check_brand.sh` passou a ler o `defaultValue` da declaração de `appName` (as duas formas são aceitas; cópia idêntica no Fluxy).

### B) Identidade da empresa (tempo de execução)
- **Banco** (`20261028140000_identidade_visual_empresa.sql`): `organizations.cor_primaria/cor_secundaria` (`#RRGGBB`, CHECK), `fn_pode_editar_identidade()` (admin ativo, empresa em atuação), `get_org_identity()`, `admin_set_org_identity(p_logo_url, p_cor_primaria, p_cor_secundaria)` (estado completo; nulo volta ao padrão; audita `org.identity_changed`), bucket público `org-logos` (PNG/JPEG/WebP, 2 MB, escrita só em `{org_id}/`), permissão RBAC `admin_identidade` (Super Admin).
- **App** (`lib/core/brand/`): `OrgIdentity` + `orgIdentityProvider` (nunca falha; sem sessão devolve `vazia`), `BrandTheme.claro/escuro` (sem cor da empresa, tema idêntico ao anterior; o esquema "WhatsApp" escolhido pelo usuário prevalece), `LogoEmpresa` (logo da empresa com reserva no logo do produto), `IdentidadeRepository` (upload, gravação, limpeza do logo antigo).
- **Regra:** telas usam `context.corMarca` (primária do tema), nunca `AppConstants.primary`. Notificações do Android, sem `BuildContext`, usam `OrgIdentity.corAtual`. `test/identidade_visual_test.dart` falha se a constante ou o nome escrito direto voltarem à interface.
- **Painel Administrativo → Identidade Visual** (`identidade_visual_tab.dart`): logo (convertido para WebP), cores por paleta ou hex, aviso de contraste WCAG (não bloqueia), prévia com o mesmo `BrandTheme`.

### C) Contrato de `organizations.settings`
- `20261028140100_contrato_settings_empresa.sql`: `fn_settings_erro(chave, valor)` e o trigger `trg_validar_settings` (BEFORE INSERT/UPDATE OF settings). Valida só as chaves que mudaram; chaves desconhecidas passam; `null` e `''` voltam ao padrão.
- `lib/core/models/org_settings.dart`: leitura tipada (`modulos`, `provedorIa`, `gpsRetencaoDias`…). `test/org_settings_test.dart` compara as faixas com as da migration.

### D) Pendências conhecidas
- Redefinição de senha pelo app no celular: `redirectTo: 'alinhaja://update-password'` sem *intent filter* no `AndroidManifest.xml` — o link não abre o app.
- Identificador do pacote Android por distribuição é manual (sem *flavors*).

