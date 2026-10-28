<div align="center">
  <img src="https://img.shields.io/badge/Flutter-3.x-02569B?style=for-the-badge&logo=flutter" alt="Flutter">
  <img src="https://img.shields.io/badge/Supabase-3.x-3FCF8E?style=for-the-badge&logo=supabase" alt="Supabase">
  <img src="https://img.shields.io/badge/State-Riverpod-0F8943?style=for-the-badge" alt="Riverpod">
</div>

<h1 align="center">AlinhaJá 🚀</h1>
<p align="center">
  <strong>Plataforma Corporativa Unificada</strong><br>
  <em>Transforme mensagens soltas em processos operacionais rastreáveis.</em>
</p>

---

## 📌 Sobre o Projeto

O **AlinhaJá** é muito mais do que um mensageiro corporativo. É uma plataforma desenvolvida do zero para resolver a "síndrome de WhatsApp" nas empresas: mensagens dispersas, solicitações esquecidas e falta de controle.

O sistema integra comunicação em tempo real com gestão operacional (Kanban/Helpdesk), exigência de SLA e rastreamento, mantendo toda a operação centralizada em uma única interface cross-platform.

Este projeto foi construído focando em uma arquitetura limpa (*Feature-First*), alto desempenho nativo (Flutter) e backend reativo com **Supabase** (PostgreSQL + Realtime WebSockets).

---

## ✨ Principais Funcionalidades

O sistema é construído sobre 6 módulos principais integrados:

1. 💬 **Mensageria & Broadcast:** Chat em tempo real (1-a-1 e grupos). Canais oficiais com o recurso **"Estou Ciente"** (assinatura digital auditável de leitura), **Quadro Branco Colaborativo** em tempo real traço a traço, e publicação de **Anúncios Oficiais** com permissões RBAC próprias.
2. 📋 **Workflow (Kanban):** Toda mensagem/solicitação pode virar um Card. Visão de Board e Lista com responsáveis claros, acompanhamento de *SLA* (tempo de resolução) e histórico da tarefa.
3. 🎫 **Helpdesk:** Abertura de tickets de suporte interno com conversa dedicada por chamado.
4. 📹 **Videochamadas:** Integração para videochamadas rápidas e salas de reunião corporativas diretamente no aplicativo.
5. 📍 **Rastreamento & Localização (GPS):** Acompanhamento logístico de equipes com *tracking* em background e **seletor interativo de pino no mapa** para envio de pontos de encontro e endereços.
6. 🛡️ **Segurança & Admin (RBAC):** Gestão de usuários provisionada pela TI com papéis específicos (Diretor, Gerente, Base), controle de acesso por módulo, auditoria LGPD (Art. 37) e *Soft Delete*.


---

## 🏗 Arquitetura e Tech Stack

O aplicativo foi projetado adotando a arquitetura orientada a funcionalidades (*Feature-First*), facilitando escalabilidade e manutenção.

### 🛠 Tecnologias Utilizadas
- **Frontend:** Flutter (Dart) com compilação para Mobile (Android/iOS) e Desktop/Web (PWA).
- **Gerenciamento de Estado:** Riverpod.
- **Roteamento:** GoRouter (para proteção nativa de rotas sensíveis).
- **Backend-as-a-Service (BaaS):** Supabase (PostgreSQL, Edge Functions, Auth e Storage).
- **Real-time:** Supabase WebSockets.
- **Push Notifications:** Firebase Cloud Messaging (FCM) + VAPID.

---

## 📂 Estrutura Principal do Código

```text
lib/
 ├── core/             # Configurações globais, Router, Theming, Supabase Client
 ├── features/
 │   ├─ auth/         # Autenticação e bloqueios
 │   ├─ admin/        # Painel Administrativo de TI
 │   ├─ workflow/     # Lógica do Kanban, SLA e Gestão de Cards
 │   ├─ profile/      # Perfil do Usuário e Árvore Sanfonada (Organograma)
 │   └─ chat/         # Fluxo Mensageria Realtime, Anexos, Megalofone
```

---

## 🚀 Como Rodar o Projeto Localmente

Se você deseja explorar o código, siga o guia abaixo:

### Pré-requisitos
- [Flutter SDK](https://flutter.dev/docs/get-started/install) (Versão 3.x+)
- Um projeto configurado no [Supabase](https://supabase.com/) e outro no [Firebase](https://firebase.google.com/) (para Push).

### 1. Clonando o repositório
```bash
git clone https://github.com/DelcioFDNeto/AlinhaJa.git
cd AlinhaJa
```

### 2. Configurando as Variáveis de Ambiente
O projeto depende de variáveis em dois locais (compilação e runtime).
Crie os arquivos baseando-se nos templates disponibilizados:

```bash
# 1. Copie e preencha o ambiente geral
cp .env.example .env

# 2. Copie e preencha as definições de build do Dart
cp dart_defines.example.json dart_defines.json
```

### 3. Instalando dependências e Rodando
```bash
flutter pub get

# Rodar na Web
flutter run -d chrome --dart-define-from-file=dart_defines.json

# Rodar no Emulador Android / Aparelho físico
flutter run -d android --dart-define-from-file=dart_defines.json
```

---

## 🛡️ Medidas de Segurança para o GitHub

1. **Não commitar o arquivo `.env` nem o `dart_defines.json`.** (Eles já estão no `.gitignore` atualizado).
2. **Remover arquivos nativos de assinatura** como o `android/key.properties` ou keystores (também protegidos no `.gitignore`).
3. **Nunca versionar dados de clientes nem senhas:** planilhas de funcionários, CPFs, e-mails pessoais, senhas padrão ou strings de conexão com senha. Esses arquivos ficam em armazenamento seguro, fora do git. O teste `test/sem_contas_fixas_test.dart` falha no CI se algo assim entrar no produto.
4. **Nenhuma conta nasce administradora.** O administrador principal de cada instalação é definido com `supabase/scripts/promover_super_admin.sql` (ver `docs/RUNBOOK-INSTALACAO-DUBAIRRO.md`, etapa 14).

---

## 🔄 Relação com o Fluxy

O **AlinhaJá** é o produto white-label e multiempresa, disponível para distribuição ou aquisição por outras empresas. O **Fluxy** é o produto exclusivo da Shineray by Sabel, com implantação, banco e marca próprios. Desde 28/10/2026 os dois vivem em repositórios independentes; este repositório começou com histórico limpo, sem dados de clientes.

- **Não há paridade automática.** Um recurso só passa de um produto para o outro por decisão explícita.
- **Componentes neutros** (envio de e-mail, helpers de HTML, push, CI e guarda de marca) são mantidos por cópia idêntica nos dois. Para conferir, com os dois repositórios clonados lado a lado: `bash scripts/comparar_componentes_comuns.sh ../Fluxy`.
- **Blindagem de marca:** `scripts/check_brand.sh`, executado no CI, falha se nomes, domínios ou identidade do outro produto aparecerem no código.

---

<p align="center">
  Construído com ❤️ e focado na produtividade corporativa.
</p>
