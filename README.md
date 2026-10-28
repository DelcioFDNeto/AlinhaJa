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
git clone https://github.com/SEU-USUARIO/AlinhaJá.git
cd AlinhaJá
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

Ao colocar este projeto no seu GitHub, certifique-se de:
1. **Não commitar o arquivo `.env` nem o `dart_defines.json`.** (Eles já estão no `.gitignore` atualizado).
2. **Remover arquivos nativos de assinatura** como o `android/key.properties` ou keystores (também protegidos no `.gitignore`).

---

## 🔄 Diretrizes de Paridade com o Repositório Base (Fluxy)

O **AlinhaJá** é o fork corporativo do Fluxy voltado para operações multi-tenant. Mantém paridade com o projeto-base em infraestrutura, bibliotecas Flutter, segurança do banco de dados (RLS, auditoria LGPD) e funcionalidades de mensageria.

### ⚠️ Regras e Exceções Estritas de Paridade:
- **Colaboradores e Seeds de Dados**: O AlinhaJá é uma plataforma **multi-tenant** (Rede DuBairro, etc.). Migrations e rotinas que manipulam base de colaboradores específicos de um cliente (como a migration `20260908150000_sync_and_clean_employees_mapping.sql` da Shineray By Sabel) são **estritamente exclusivas do Fluxy e NÃO devem ser portadas ou replicadas no AlinhaJá**.
- **Blindagem de Marca**: Nomes, domínios, URLs de landing page e variáveis corporativas respeitam os assets e a identidade visual própria do AlinhaJá, validada pelo guard automatizado `scripts/check_brand.sh`.

---

<p align="center">
  Construído com ❤️ e focado na produtividade corporativa.
</p>