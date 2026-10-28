# Análise da Estrutura Atual de Canais do AlinhaJá

## 📊 RESUMO EXECUTIVO

Sistema atual de canais (Channels) tem boa base mas precisa evoluir para suportar workflows operacionais completos conforme especificado na skill workflow-skill.md.

---

## ✅ PONTOS FORTES DO SISTEMA ATUAL

### 1. Arquitetura de Banco de Dados
- **Separação lógica**: Canais isolados das tabelas normais de DMs/Grupos
- **RLS bem implementado**: Políticas de segurança por membership
- **Triggers automatizados**: Contagem de replies e last_message_at
- **Suporte a threads**: Estrutura de respostas isolada

### 2. Modelos de Dados Sólidos
- **ChannelModel**: Estrutura limpa com id, name, description, type, postingPermission
- **ChannelMessageModel**: Suporte completo a content, media, threads, reactions, metadata
- **Herança de tipo**: Campo `type` permite diferenciação (comum, avisosp, operacional)

### 3. Providers Bem Estruturados
- **ChannelsListProvider**: Lista canais do usuário com escuta de mudanças
- **ActiveChannelProvider**: Gerencia estado, mensagens, permissões, governança
- **ChannelInfoProvider**: Métricas, mídia compartilhada, ranking de membros
- **Sistema de permissões**: canPost, canGovernChannel, isTI, isAdminOrOwner

### 4. UI/UX Funcional
- **ChannelScreen**: Interface de chat completa
- **ChannelMessageBubble**: Múltiplos tipos (texto, anúncio, enquete)
- **Acknowledge de anúncios**: Sistema de "Estou Ciente"
- **Sistema de polls**: Votação com resultados em tempo real
- **ChannelInfoScreen**: Métricas e mídias do canal

### 5. Recursos Implementados
- Mensagens com threads
- Anúncios com confirmação de leitura
- Enquetes com votação anônima
- Compartilhamento de imagens e documentos
- Fixação de mensagens
- Reações
- Arquivamento e exclusão de canais
- Governança (TI, admin, criador)

---

## ❌ PONTOS FRACOS E LACUNAS

### 1. Falta de Workflow/Card System
- **Não existem workflow_cards**: Sistema operacional inexistente
- **Sem formulários específicos**: Cada canal com campos fixos
- **Sem status pipeline**: Sem kanban ou lista de status
- **Sem atribuição de responsáveis**: Cards não têm responsável definido

### 2. Visual Limitado
- **Design básico**: Sem glassmorphism ou premium visual
- **Falta de identidade visual forte**: Não transmite produto SaaS
- **Sem dashboard operacional**: Métricas isoladas na página de info
- **Animações limitadas**: Pouca microinteração

### 3. Estrutura de Dados Incompleta
- **Sem workspaces**: Tudo no mesmo nível
- **Sem etiquetas (labels)**: Sistema de tags inexistente
- **Sem templates de formulários**: Campos fixos hardcoded
- **Sem histórico de mudanças**: Audit trail de cards inexistente
- **Sem automações**: Triggers e regras de negócio limitadas

### 4. Fluxos Operacionais Ausentes
- **Sem aprovação**: Sistema de approve/reject inexistente
- **Sem notificações por card**: Apenas notificações de mensagem
- **Sem prioridades estruturadas**: Apenas campo metadata genérico
- **Sem filtros avançados**: Busca limitada

### 5. Integrações e Expansão
- **Sem API exposta**: Endpoints não documentados para consumo externo
- **Sem webhooks**: Sistema de eventos para terceiros
- **Sem cache otimizado**: Queries podem ser pesadas

---

## 🏗️ ESTRUTURA ATUAL DO BANCO

### Tabelas Principais
```
channels
├── id (UUID)
├── name (TEXT)
├── description (TEXT)
├── created_by (UUID)
├── type (TEXT) - 'comum', 'avisos', 'operacional'
├── posting_permission (TEXT)
├── pinned_date (TIMESTAMP)
├── last_message_at (TIMESTAMP)
├── created_at (TIMESTAMP)
└── updated_at (TIMESTAMP)

channel_members
├── channel_id (UUID) FK
├── user_id (UUID) FK
├── role (TEXT) - 'admin', 'editor', 'viewer'
└── created_at (TIMESTAMP)

channel_messages
├── id (UUID)
├── channel_id (UUID) FK
├── sender_id (UUID) FK
├── content (TEXT)
├── content_type (TEXT) - 'text', 'image', 'file', 'poll'
├── media_url (TEXT)
├── local_file_path (TEXT)
├── metadata (JSONB)
├── is_bot (BOOLEAN)
├── is_system (BOOLEAN)
├── read_by (UUID[])
├── thread_id (UUID) FK - auto-reply
├── reply_to (UUID) FK - parent message
├── thread_reply_count (INT)
├── deleted_at (TIMESTAMP)
├── updated_at (TIMESTAMP)
└── created_at (TIMESTAMP)

message_actions (tabela auxiliar)
├── id (UUID)
├── message_id (UUID)
├── user_id (UUID)
├── action_type (TEXT) - 'acknowledge', 'poll_vote'
├── action_value (TEXT)
├── created_at (TIMESTAMP)
```

### APIs/RPCs Existentes
- `create_company_channel` - Criação de canal
- `delete_channel` - Exclusão em cascata
- `archive_channel` - Arquivamento

---

## 🎯 ANÁLISE POR CANAL ESPECÍFICO

### Avisos Gerais
**Status atual**: Funcional com sistema de acknowledge
**O que falta**: 
- Fixação visual de avisos importantes
- Destaque para urgentes
- Filtragem por setor/unidade
- Histórico de comunicados

### Liberação Contas a Pagar (Financeiro)
**Status atual**: Apenas canal de chat
**O que falta**:
- Card específico com campos: fornecedor, valor, vencimento, centro de custo
- Pipeline de status: Novo → Em análise → Aguardando → Aprovado → Rejeitado → Pago
- Botões de aprovação rápida
- Timeline de aprovações

### Liberação Fat Moto (Financeiro)
**Status atual**: Apenas canal de chat
**O que falta**:
- Card Fat Financeiro com: Cliente, Pedido, Ficha
- Pipeline: Solicitação → Conferência → Liberação → Pendente → Finalizado
- Destaque visual para números importantes

### Emplacamento (Financeiro)
**Status atual**: Apenas canal de chat
**O que falta**:
- Card com: Cliente, CPF/CNPJ, Chassi, Placa
- Pipeline: Aberto → Análise → Pagamento → Processamento → Emplacado → Pendência
- Checklist documental
- Timeline de processo

### Faturamento OS/Peças (Faturamento)
**Status atual**: Apenas canal de chat
**O que falta**:
- Card com: OS, Orçamento, Cliente, Unidade
- Pipeline: Aberto → Análise → Faturamento → Correção → Faturado → Cancelado
- Visual limpo com progresso

---

## 🔄 RECOMENDAÇÕES PARA REFORMULAÇÃO

### Fase 1: Evolução Natural (Quebra Mínima)
1. Adicionar campo `is_workflow_enabled` na tabela `channels`
2. Criar nova tabela `workflow_cards` com referências ao channel
3. Adicionar sistema de status configurável por canal
4. Implementar dashboard operacional na sidebar

### Fase 2: Workflow Completo
1. Criar `workflow_card_comments` com menções
2. Implementar sistema de aprovações com timeline
3. Adicionar templates de formulário por canal
4. Criar sistema de etiquetas (labels)

### Fase 3: Premium UX
1. Redesenhar UI com tema dark glassmorphism
2. Adicionar animações e microinterações
3. Implementar visual board/kanban
4. Criar painel de métricas

### Fase 4: Expansão
1. Webhooks para automações
2. API REST para integrações
3. Sistema de automações (triggers)
4. Relatórios e analytics

---

## ⚠️ RISCOS E MITIGAÇÃO

| Risco | Mitigação |
|-------|-----------|
| Quebrar canais existentes | Campos opcionais, migração retrocompatível |
| Performance com muitos cards | Paginação, índices, cache |
| Complexidade de UI | Duas visões (conversa/workflow) separadas |
| Migração de dados | Script de migração em fases |
| Aceitação usuários | UX intuitiva, modo conversação preservado |

---

## 📝 PRÓXIMOS PASSOS

1. **Confirmar análise** - Validar pontos fortes/fracos identificados
2. **Definir escopo MVP** - Quais funcionalidades na primeira fase
3. **Mapear estrutura DB** - Criar migration para workflow_cards
4. **Planejar UI** -Wireframes das novas telas
5. **Implementar provider** - Novo provider para workflow cards
6. **Desenvolver tela** - Channel com modo conversa + workflow

---

*Documento gerado para base da reformulação do AlinhaJá conforme workflow-skill.md*
*Data: 2026-03-31*
