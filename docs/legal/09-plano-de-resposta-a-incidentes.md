# Plano de Resposta a Incidentes de Segurança com Dados Pessoais — AlinhaJá

**Versão 1.0.0 — vigente a partir de `[DATA DE VIGÊNCIA]`**

Procedimento interno da `[RAZÃO SOCIAL]` para detectar, conter, avaliar,
comunicar e documentar incidentes de segurança envolvendo dados pessoais, em
conformidade com o art. 48 da LGPD e a **Resolução CD/ANPD nº 15/2024**.

---

## 1. O que é incidente de segurança

Qualquer evento, confirmado ou sob suspeita fundada, que comprometa
**confidencialidade, integridade ou disponibilidade** de dados pessoais tratados
na Plataforma. Exemplos:

- acesso não autorizado a conta, base de dados ou arquivo;
- vazamento ou exposição indevida de dados;
- envio de dado pessoal ao destinatário errado;
- perda ou roubo de dispositivo com acesso à Plataforma;
- ataque de ransomware, malware ou negação de serviço;
- exclusão ou alteração indevida de dados, acidental ou intencional;
- falha de controle de acesso que exponha dados a quem não deveria vê-los;
- incidente em fornecedor que trate dados em nome da empresa.

**Não** é incidente: tentativa de acesso bloqueada com sucesso pelos controles,
sem qualquer exposição. Ainda assim, deve ser registrada para análise de
tendência.

---

## 2. Papéis

| Papel | Quem | Responsabilidade |
|-------|------|------------------|
| **Encarregado (DPO)** | `[NOME DO ENCARREGADO]` — `[E-MAIL DO DPO]` | Coordena a resposta, decide sobre comunicação à ANPD e aos titulares, mantém o registro |
| **Responsável técnico (TI)** | `[NOME]` | Contém, investiga, preserva evidências, restaura |
| **Diretoria** | `[NOME]` | Decide sobre acionamento jurídico, comunicação externa e recursos |
| **Jurídico** | `[NOME OU ESCRITÓRIO]` | Avalia riscos legais, revisa comunicações |
| **RH** | `[NOME]` | Comunica colaboradores afetados; conduz apuração quando houver conduta interna |
| **Qualquer colaborador** | Todos | **Comunicar imediatamente** ao detectar ou suspeitar |

**Canal de comunicação de incidente:** `[E-MAIL DO DPO]` — disponível a
colaboradores, candidatos e terceiros. Comunicação de boa-fé **não** gera
retaliação.

---

## 3. Fluxo de resposta

### Fase 1 — Detecção e registro (imediato)

1. Quem detectar comunica ao Encarregado pelo canal acima, com o que souber:
   o que aconteceu, quando, quais sistemas e dados, como percebeu.
2. O Encarregado abre registro no **Livro de Incidentes** (Seção 6) e marca o
   **momento da ciência** — é dele que corre o prazo de comunicação.
3. Não aguarde certeza para comunicar internamente. Suspeita basta.

### Fase 2 — Contenção (até 24 horas)

Ações típicas, conforme o caso:

- revogar sessões e credenciais comprometidas;
- desativar contas envolvidas;
- rotacionar chaves de API e segredos expostos;
- bloquear o vetor de acesso;
- isolar o sistema afetado;
- acionar o fornecedor, quando o incidente for de origem externa.

**Preserve as evidências**: logs, registros de auditoria, capturas e cópias. Não
apague nem sobrescreva antes da coleta.

### Fase 3 — Avaliação de risco (até 3 dias úteis da ciência)

O Encarregado avalia, com apoio de TI e Jurídico:

| Critério | Perguntas |
|----------|-----------|
| **Natureza dos dados** | Há dados sensíveis? De crianças ou adolescentes? Financeiros? Credenciais? |
| **Volume** | Quantos titulares? Quantos registros? |
| **Facilidade de identificação** | Os dados estavam criptografados, pseudonimizados ou em claro? |
| **Consequências prováveis** | Discriminação, fraude, dano patrimonial, dano moral, exposição de intimidade, risco físico |
| **Reversibilidade** | Os dados foram recuperados? A exposição foi contida? |
| **Boa-fé do destinatário** | Terceiro identificado e confiável, ou exposição aberta? |

**Conclusão:** o incidente **pode acarretar risco ou dano relevante** aos
titulares? Se sim, comunicação obrigatória. A dúvida resolve-se **pela
comunicação**.

### Fase 4 — Comunicação (até 3 dias úteis da ciência)

#### 4.1 À ANPD

Pelo canal eletrônico oficial da ANPD, contendo, conforme a Resolução nº 15/2024:

1. identificação e contato do controlador e do Encarregado;
2. descrição da natureza e categoria dos dados afetados;
3. número de titulares afetados, com destaque para dados sensíveis e de crianças
   e adolescentes;
4. data do incidente e data da ciência;
5. descrição das prováveis consequências;
6. medidas de segurança já adotadas, antes e depois;
7. medidas de mitigação de efeitos e de comunicação aos titulares;
8. se a comunicação foi parcial, prazo para completá-la.

**Comunicação preliminar** é admitida quando não houver informação completa,
seguida de complementação. Informação incompleta não justifica atraso.

#### 4.2 Aos titulares afetados

Comunicação individual — pela Plataforma, por e-mail corporativo e, para
candidatos, pelo e-mail de cadastro —, em linguagem simples, contendo:

- o que aconteceu e quando;
- quais dados **dele** foram afetados;
- consequências possíveis;
- o que a empresa já fez;
- **o que o titular deve fazer** (trocar senha, revisar acessos, atenção a golpes
  de phishing);
- canal de contato do Encarregado.

Quando a comunicação individual for impossível ou desproporcional, comunicação
pública em canal de fácil acesso, na forma admitida pela Resolução nº 15/2024.

### Fase 5 — Erradicação e recuperação

Corrigir a causa raiz, restaurar sistemas e dados a partir de backups íntegros,
validar que a vulnerabilidade foi efetivamente eliminada e monitorar reincidência
por período definido.

### Fase 6 — Lições aprendidas (até 30 dias)

Relatório final com: linha do tempo, causa raiz, dados afetados, decisões
tomadas, comunicações realizadas, custo estimado e **plano de ação** com
responsáveis e prazos. Revisão de controles e, se necessário, atualização das
políticas deste pacote.

---

## 4. Prazos

| Marco | Prazo |
|-------|-------|
| Comunicação interna ao Encarregado | Imediata |
| Contenção inicial | 24 horas |
| Comunicação à ANPD e aos titulares | **3 dias úteis** da ciência |
| Comunicação de incidente pelo fornecedor à empresa | 24 horas da detecção, por contrato |
| Relatório final interno | 30 dias |

---

## 5. Incidentes em fornecedores

Os fornecedores listados no
[documento 11](11-suboperadores-e-transferencia-internacional.md) devem comunicar
incidentes em até 24 horas da detecção. Recebida a comunicação, **o prazo de 3
dias úteis para a ANPD corre a partir da ciência da empresa**, que permanece
responsável perante os titulares na qualidade de controladora.

Verificar, a cada incidente de fornecedor: escopo dos dados da empresa afetados,
medidas do fornecedor, necessidade de troca de credenciais e de comunicação
própria aos titulares.

---

## 6. Livro de Incidentes

Registro obrigatório de **todos** os incidentes, inclusive os que não geraram
comunicação — a ANPD pode requisitá-lo a qualquer momento.

Campos mínimos:

```
ID | Data do incidente | Data da ciência | Descrição | Sistemas afetados
Categorias de dados | Nº de titulares | Havia dado sensível?
Avaliação de risco | Comunicou ANPD? (data) | Comunicou titulares? (data)
Medidas de contenção | Causa raiz | Plano de ação | Encerramento
```

Guarda: `[VALIDAR: sugerido 5 anos]` após o encerramento.

---

## 7. Comunicação e mídia

Nenhum colaborador está autorizado a se manifestar publicamente sobre incidente.
Contatos de imprensa, clientes ou parceiros são encaminhados à Diretoria.
Comunicação externa é revisada previamente pelo Jurídico e pelo Encarregado.

---

## 8. Treinamento e teste

- Treinamento anual de todos os colaboradores sobre identificação e comunicação
  de incidentes;
- Simulação anual do fluxo com a equipe de resposta;
- Revisão deste plano após cada incidente relevante e, no mínimo, anualmente.

---

## 9. Contatos rápidos

| Situação | Contato |
|----------|---------|
| Suspeita de incidente | `[E-MAIL DO DPO]` |
| Emergência fora do horário | `[TELEFONE DE PLANTÃO]` |
| ANPD | [gov.br/anpd](https://www.gov.br/anpd/pt-br) |

---

*Base legal: art. 48 da Lei nº 13.709/2018 e Resolução CD/ANPD nº 15/2024.
Pendente de revisão por advogado habilitado antes da vigência.*
