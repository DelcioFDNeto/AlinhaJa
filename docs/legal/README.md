# Pacote Legal e LGPD — AlinhaJá

Documentos de uso, privacidade e conformidade com a Lei nº 13.709/2018 (LGPD)
da plataforma AlinhaJá. Esta pasta é a **fonte da verdade**: os textos exibidos no
aplicativo e no site público são lidos daqui, não reescritos em outro lugar.

> ⚠️ **Status jurídico.** Documentos elaborados internamente com base na LGPD,
> nas resoluções da ANPD vigentes e no inventário técnico real da aplicação.
> **Não substituem parecer de advogado.** Estão pendentes de revisão por
> profissional habilitado (OAB) antes da vigência.

---

## Índice

| # | Documento | Público | Aceite |
|---|-----------|---------|--------|
| 01 | [Termos de Uso](01-termos-de-uso.md) | Colaboradores | ✅ `uso` |
| 02 | [Política de Privacidade](02-politica-de-privacidade.md) | Colaboradores | ✅ `privacidade` |
| 03 | [Política de Monitoramento e Uso Aceitável](03-politica-de-monitoramento-e-uso-aceitavel.md) | Colaboradores | ✅ `monitoramento` |
| 04 | [Termo de Consentimento — Geolocalização](04-termo-de-consentimento-geolocalizacao.md) | Colaboradores rastreados | ✅ granular (GPS) |
| 05 | [Aviso de Privacidade — Candidatos](05-aviso-de-privacidade-candidatos.md) | Candidatos externos | ✅ no cadastro |
| 06 | [Política de Cookies e Armazenamento Local](06-politica-de-cookies.md) | Todos (web) | Informativo |
| 07 | [Aviso de Uso de IA e Decisões Automatizadas](07-aviso-de-ia-e-decisoes-automatizadas.md) | Todos | Informativo |
| 08 | [Política de Retenção e Descarte](08-politica-de-retencao-e-descarte.md) | Interno + titulares | Informativo |
| 09 | [Plano de Resposta a Incidentes](09-plano-de-resposta-a-incidentes.md) | Interno | Informativo |
| 10 | [Registro de Operações de Tratamento (ROPA)](10-registro-de-operacoes-ropa.md) | Interno / ANPD | Art. 37 |
| 11 | [Suboperadores e Transferência Internacional](11-suboperadores-e-transferencia-internacional.md) | Todos | Informativo |
| 12 | [Termo de Ciência e Aceite](12-termo-de-ciencia-e-aceite.md) | Colaboradores | Tela de aceite |

---

## Como o aceite é registrado

O aceite dos documentos 01, 02 e 03 é gravado em `public.policy_acceptance`
pela RPC `accept_policy(p_policy_type, p_version)`:

```
policy_type   →  'uso' | 'privacidade' | 'monitoramento'
policy_version→  versão semântica do documento (ex.: '1.0.0')
```

A escrita direta na tabela é revogada para `authenticated` e `anon` — o aceite
não pode ser forjado nem apagado pelo cliente. Cada aceite gera evento
`policy.accepted` em `audit_log`.

O consentimento de geolocalização (documento 04) é **separado e granular**,
gravado em `location_tracking_settings` pelas RPCs `gps_grant_consent` /
`gps_revoke_consent`, com `consent_version` própria. Recusá-lo não bloqueia o
acesso à plataforma.

### Versionamento

- Versão **maior** (`2.0.0`): mudança material — novo tratamento, nova
  finalidade, novo destinatário, prazo de retenção maior. **Exige novo aceite**.
- Versão **menor** (`1.1.0`): esclarecimento de redação, correção, contato novo.
  Notificar, sem exigir novo aceite.

Ao subir a versão de um documento, atualize também a constante correspondente em
`lib/features/legal/data/legal_documents.dart` — é ela que o app envia ao
`accept_policy` e que decide se a tela de aceite reaparece.

---

## Campos preenchidos automaticamente

Os documentos são um **modelo**: o que os individualiza é o cadastro da empresa.
O app substitui os campos abaixo em tempo de leitura, pelos dados do **tenant
corrente** — resolvido no banco por `fn_current_org()`, que num produto de
empresa única devolve a org do usuário e num white label acompanha a empresa em
atuação.

Onde preencher: **Painel Administrativo → Dados Legais**.

| Campo no texto | Origem | Essencial |
|----------------|--------|-----------|
| `[RAZÃO SOCIAL]` | `organizations.legal_name` | ✅ |
| `[CNPJ]` | `organizations.cnpj` | ✅ |
| `[ENDEREÇO COMPLETO]` | `settings.legal.endereco` | ✅ |
| `[NOME DO ENCARREGADO]` | `settings.legal.dpo_nome` | ✅ |
| `[E-MAIL DO DPO]` | `settings.legal.dpo_email` | ✅ |
| `[DATA DE VIGÊNCIA]` | `settings.legal.vigencia` | ✅ |
| `[COMARCA]` | `settings.legal.comarca` | — |
| `[REGIÃO DE HOSPEDAGEM]` | `settings.legal.regiao_hospedagem` | — |
| `[TELEFONE DE PLANTÃO]` | `settings.legal.telefone_plantao` | — |
| `[7]` (retenção de GPS) | `settings.gps_retencao_dias` | — |

A lista canônica vive em `kLegalFields`
(`lib/features/legal/models/org_legal_profile.dart`); o site replica os mesmos
tokens em `landing-page/src/legal-routes.ts`.

**Campo vazio permanece entre colchetes**, e o leitor exibe um aviso de
documento não personalizado. Lacuna visível é honesta; lacuna apagada esconderia
que o documento está incompleto.

### O que NÃO é substituído

Os documentos usam colchetes para outras três coisas, e a substituição é por
token exato justamente para não tocar nelas:

- links Markdown — `[Política de Privacidade](02-….md)`;
- marcadores de pendência — `[CONFIRMAR]`, `[VALIDAR: sugerido 5 anos]`, que
  dependem de decisão do jurídico e de TI, não de cadastro;
- exemplos de mascaramento de PII no documento 07 — `[CPF]`, `[EMAIL]`,
  `[NOME]`. Substituí-los corromperia a seção que explica a anonimização.

Busca rápida pelas pendências que sobram para pessoas:

```bash
grep -rn "\[CONFIRMAR\|\[VALIDAR\|\[AVALIAR" docs/legal/*.md
```

---

## Onde os textos são consumidos

| Consumidor | Caminho |
|------------|---------|
| App Flutter | `docs/legal/` declarado como asset em `pubspec.yaml`, renderizado por `LegalDocumentScreen` |
| Site público | `landing-page/src/legal.tsx` importa os `.md` com `?raw` |
| Central de Privacidade | `lib/features/legal/ui/privacy_center_screen.dart` |

Não duplique o texto em código Dart ou TSX. Editar aqui basta.

---

## Nota de sincronização entre forks

Estes arquivos contêm os literais **AlinhaJá** e **DuBairro**. O
`scripts/check_brand.sh` **não** varre `docs/` — ao portar para o outro fork,
os tokens de marca destes documentos precisam ser trocados manualmente, junto
com razão social, CNPJ, DPO e endereço, que são de outra pessoa jurídica.

---

**Versão do pacote:** 1.0.0 — `[DATA DE VIGÊNCIA]`
