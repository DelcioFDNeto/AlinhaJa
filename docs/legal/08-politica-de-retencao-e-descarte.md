# Política de Retenção e Descarte de Dados — AlinhaJá

**Versão 1.0.0 — vigente a partir de `[DATA DE VIGÊNCIA]`**

Documento de governança interna, disponível aos titulares. Define **por quanto
tempo** cada categoria de dado é mantida, **com que fundamento** e **como** o
descarte é executado.

> Princípio orientador (art. 15 e 16 da LGPD): dado pessoal é mantido **apenas
> enquanto necessário** à finalidade que justificou sua coleta. Prazo declarado e
> não cumprido é agravante em fiscalização — por isso cada prazo desta política
> corresponde a uma rotina automática ou a um procedimento com responsável
> nomeado.

---

## 1. Tabela de retenção

### 1.1 Comunicação

| Dado | Prazo | Fundamento | Execução |
|------|-------|------------|----------|
| Mensagens diretas e de canais | Configurável por organização. **Valor atual: [RETENÇÃO DE MENSAGENS]** | Art. 7º, VI (exercício de direitos) e art. 16, I | Rotina diária automática, quando o prazo for definido |
| Arquivos, imagens, áudios e vídeos | Acompanha a mensagem de origem | Idem | Manual, junto com o expurgo de mensagens |
| Reações, confirmações de leitura e de ciência | Acompanha a mensagem | Idem | Cascata |
| Registro de chamadas e reuniões | `[VALIDAR: sugerido 5 anos]` | Art. 7º, VI | A definir |
| Transcrições de reunião | `[VALIDAR: sugerido 2 anos]` | Art. 7º, V e VI | A definir |

> ⚠️ **Pendência crítica.** O sistema suporta expurgo automático de mensagens, mas
> o valor configurado é **zero**, o que significa retenção indefinida. Enquanto
> um prazo não for definido pela Diretoria, a Política de Privacidade não pode
> afirmar prazo determinado para mensagens. **Sugestão para deliberação: 5 anos**,
> alinhado ao prazo prescricional trabalhista.

### 1.2 Localização

| Dado | Prazo | Fundamento | Execução |
|------|-------|------------|----------|
| Histórico de posições (`user_locations`) | `[7]` dias, configurável por organização | Art. 15, I — fim da necessidade | **Rotina automática diária às 03:20**, com registro do volume expurgado |
| Registro de consentimento e revogação | Enquanto durar o vínculo + 5 anos | Art. 7º, VI — prova do consentimento | Manual |
| Posição da marcação de ponto | Acompanha o registro de ponto | Art. 7º, II | Cascata |

### 1.3 Recursos Humanos

| Dado | Prazo sugerido | Fundamento |
|------|----------------|------------|
| Registro de ponto | 5 anos após o fato | Art. 7º, XXIX, CF; art. 11 da CLT |
| Folha de pagamento, holerites e encargos | 10 anos | Art. 32, § 11, da Lei nº 8.212/1991 |
| Ficha funcional e histórico de cargo e salário | 5 anos após a rescisão `[VALIDAR]` | Prescrição trabalhista |
| Documentos de FGTS | 5 anos `[VALIDAR]` | STF, ARE 709212 — prescrição quinquenal |
| Atestados e licenças médicas | `[VALIDAR: 5 anos; 20 anos se compuserem prontuário de saúde ocupacional]` | Art. 11, II, "a"; NR-07 |
| Documentos de saúde ocupacional (ASO, PCMSO, PPP) | 20 anos após o desligamento | NR-07 e legislação previdenciária |
| Dados de dependentes | Enquanto durar a dependência declarada + prazos fiscais | Art. 7º, II |
| Avaliações de desempenho e metas | 5 anos `[VALIDAR]` | Art. 7º, V e VI |
| Execuções de onboarding | 5 anos | Art. 7º, V |
| Benefícios concedidos | Enquanto vigente + 5 anos | Art. 7º, II e V |

> Os prazos marcados `[VALIDAR]` são sugestões técnicas alinhadas às práticas
> correntes e devem ser confirmados pelo jurídico antes da vigência. Prazo legal
> superior sempre prevalece sobre prazo desta tabela.

### 1.4 Recrutamento e seleção

| Dado | Prazo | Fundamento | Execução |
|------|-------|------------|----------|
| Candidatura em processo aberto | Enquanto durar o processo | Art. 7º, V | Manual |
| Cadastro em banco de talentos | **[24] meses**, configurável por organização | Art. 7º, I — consentimento | **Anonimização automática** por rotina diária |
| Currículos e documentos anexos | Acompanha o cadastro; **removidos do armazenamento** na anonimização | Art. 15, I | Automática |
| Testes e respostas | Acompanha a candidatura | Art. 7º, V | Cascata |
| Candidato contratado | Migra para a ficha funcional | Art. 7º, V | Manual, na conversão |

**Como funciona a anonimização.** A linha do candidato é preservada para não
quebrar vínculos históricos, mas **todo dado identificador é removido** e os
arquivos são apagados do armazenamento. O registro anonimizado sai das listagens
e não permite reidentificação — deixando de ser dado pessoal (art. 12).

### 1.5 Acesso, segurança e auditoria

| Dado | Prazo | Fundamento |
|------|-------|------------|
| Registros de auditoria (`audit_log`) | `[VALIDAR: sugerido 5 anos]` — **atualmente sem expurgo automático** | Art. 7º, VI e IX; art. 37 |
| Registros de acesso a dados de RH | `[VALIDAR: sugerido 5 anos]` | Art. 7º, IX |
| Registros de uso de IA | `[VALIDAR: sugerido 2 anos]` | Prestação de contas |
| Registros de conexão e aplicação | 6 meses (mínimo legal) a `[VALIDAR: 5 anos]` | Arts. 13 e 15 da Lei nº 12.965/2014 |
| Dispositivos confiáveis | **30 dias**, com expiração automática | Art. 7º, IX |
| Códigos de verificação por e-mail | Minutos, expiração automática | Art. 7º, IX |
| Tokens de notificação push | Enquanto a sessão do dispositivo existir | Art. 7º, V |

### 1.5.1 Backup pessoal em nuvem

| Dado | Prazo | Fundamento | Execução |
|------|-------|------------|----------|
| Arquivo de backup cifrado | **90 dias**, configurável por organização (7 a 365) | Art. 15, I — fim da necessidade | **Rotina automática diária às 03:40**, com registro do volume expurgado |
| Backups por dispositivo | Os **5 mais recentes**, configurável (1 a 30) | Art. 16 — não guardar além do necessário | Poda automática a cada novo backup |
| Upload interrompido (`pendente`) | **24 horas** | Art. 15, I | Automática, na mesma rotina |
| Registro do dispositivo de backup | Enquanto não for revogado pelo titular | Art. 7º, IX | Manual, pelo titular |

O backup pessoal é **cifrado no dispositivo do titular** com chave derivada de
senha que não trafega nem é armazenada no servidor. Consequências relevantes
para esta política:

- A Controladora **não consegue ler** o conteúdo dos backups. O que é possível
  demonstrar em fiscalização é o metadado: quem gerou, quando, de qual aparelho,
  qual volume — e o expurgo cumprido no prazo.
- O expurgo é **eliminação real**: o objeto sai do repositório e o registro sai
  da base. Não há cópia decifrável em outro lugar.
- Revogar um dispositivo apaga, no mesmo ato, todos os backups originados dele —
  procedimento indicado em caso de perda ou furto do aparelho.
- Criação, restauração, exclusão e revogação ficam registradas em `audit_log`
  (art. 37).

> ⚠️ **Pendência.** O registro de auditoria cresce indefinidamente. Definir prazo
> e agendar expurgo, preservando o que for necessário à defesa em processo.

### 1.6 Aceites e exercício de direitos

| Dado | Prazo | Fundamento |
|------|-------|------------|
| Aceites de política | Enquanto durar o vínculo + 5 anos | Art. 7º, VI — prova de consentimento e de informação |
| Pedidos de titular e respostas | 5 anos após o encerramento | Art. 7º, VI; prestação de contas |

O registro de aceite é **prova de conformidade** e não deve ser eliminado junto
com os demais dados do titular: sua eliminação inviabilizaria demonstrar que a
informação foi prestada.

### 1.7 Dados no dispositivo do usuário

| Dado | Prazo | Execução |
|------|-------|----------|
| Cache de mídias | 90 dias sem acesso, com tetos de 500 MB (imagens), 1 GB (vídeos) e 2 GB (total) | Automática, no aplicativo |
| Banco local de conversas | 30 dias, e **sempre até sair da conta** | Automática, no logout e a cada sincronização |
| Senha do backup automático (cofre da plataforma) | Até desligar o automático ou sair da conta | Automática |
| Sessão e preferências | Até sair da conta | Automática |

O banco local é **atribuído ao titular que o sincronizou**. Ao sair da conta,
tanto o histórico quanto o cache de mídia são apagados; ao entrar outra conta no
mesmo aparelho, o que restou da anterior é descartado antes de qualquer leitura.
A senha do backup automático, quando o titular opta por ele, fica no cofre da
plataforma (Keychain no iOS, Keystore no Android) — nunca em arquivo de
preferências — e é apagada no logout.

---

## 2. Critérios de descarte

Ao fim do prazo, o dado é submetido a um destes tratamentos:

| Tratamento | Quando se aplica |
|------------|------------------|
| **Eliminação** | Dado sem valor histórico, legal ou probatório |
| **Anonimização** | Quando o registro tem valor estatístico ou de integridade referencial — caso do banco de talentos |
| **Bloqueio** | Suspensão temporária do tratamento durante litígio ou apuração |
| **Retenção estendida** | Ordem judicial, requisição de autoridade ou processo em curso — mediante registro do motivo e do prazo |

---

## 3. Hipóteses de suspensão do descarte

O expurgo é **suspenso**, com registro formal, quando houver:

- ordem judicial ou requisição de autoridade;
- processo judicial, administrativo ou arbitral em curso ou iminente que envolva
  o titular ou os fatos registrados;
- apuração interna de conduta em andamento;
- incidente de segurança sob investigação.

A suspensão é levantada assim que cessar o motivo, e o descarte é executado no
ciclo seguinte.

---

## 4. Eliminação antecipada a pedido do titular

O titular pode requerer eliminação antes do prazo (art. 18, VI). O pedido é
recebido pela Central de Privacidade e analisado pelo Encarregado em até 15 dias.

**Será negado, com justificativa por escrito**, quando a manutenção for
necessária para (art. 16 da LGPD):

- cumprimento de obrigação legal ou regulatória;
- exercício regular de direitos;
- estudo por órgão de pesquisa, com anonimização;
- transferência a terceiro com observância da lei;
- uso exclusivo do controlador, vedado o acesso por terceiro e com anonimização.

**Limite adicional em comunicações.** Mensagem trocada envolve outros titulares.
A eliminação a pedido de um participante não pode suprimir o registro que
constitui direito de outro. Nesses casos, aplica-se anonimização do autor ou
bloqueio, conforme o caso concreto.

---

## 5. Responsabilidades

| Papel | Responsabilidade |
|-------|------------------|
| **Diretoria** | Aprovar prazos, especialmente o de mensagens e o de auditoria |
| **Encarregado (DPO)** | Manter esta política atualizada; decidir pedidos de eliminação; registrar suspensões |
| **TI** | Implementar e monitorar as rotinas automáticas; comprovar execução |
| **RH** | Executar descarte de documentos funcionais; validar prazos trabalhistas |
| **Jurídico** | Confirmar os itens marcados `[VALIDAR]`; comunicar litígios que suspendam descarte |

---

## 6. Comprovação de cumprimento

As rotinas automáticas registram o volume expurgado a cada execução. Esses
registros constituem **evidência de cumprimento** perante a ANPD e devem ser
preservados ainda que os dados de origem tenham sido eliminados.

Revisão desta política: **anual**, ou a qualquer momento por mudança legal ou de
funcionalidade.

---

## 7. Resumo das pendências

| # | Pendência | Responsável |
|---|-----------|-------------|
| 1 | Definir prazo de retenção de mensagens (hoje: indefinido) | Diretoria + Jurídico |
| 2 | Definir prazo e agendar expurgo de registros de auditoria | Diretoria + TI |
| 3 | Confirmar todos os prazos marcados `[VALIDAR]` | Jurídico |
| 4 | Definir prazo para registros de chamadas e transcrições | Diretoria |
| 5 | Alinhar a Política de Privacidade aos prazos aprovados | Encarregado |

Enquanto as pendências 1 e 4 não forem resolvidas, a Política de Privacidade
informa retenção indefinida para mensagens — o que é transparente, porém
desfavorável em avaliação de conformidade.

---

*Base legal: arts. 15, 16, 18 e 37 da Lei nº 13.709/2018; art. 11 da CLT; art. 7º,
XXIX, da Constituição Federal; art. 32 da Lei nº 8.212/1991; arts. 13 e 15 da Lei
nº 12.965/2014. Pendente de revisão por advogado habilitado.*
