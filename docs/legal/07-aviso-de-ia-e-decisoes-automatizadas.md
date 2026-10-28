# Aviso de Uso de Inteligência Artificial e Decisões Automatizadas — AlinhaJá

**Versão 1.0.0 — vigente a partir de `[DATA DE VIGÊNCIA]`**

Este aviso descreve **onde** a plataforma AlinhaJá usa inteligência artificial,
**quais dados** são enviados a serviços externos, **quais salvaguardas** existem
e **quais direitos** você tem sobre isso.

---

## 1. Compromissos

1. **Nenhuma decisão sobre pessoas é tomada exclusivamente por IA.** Contratação,
   promoção, avaliação, disciplina e desligamento são sempre decisões humanas.
2. **Identificadores pessoais são removidos antes do envio** a provedores
   externos, sempre que a função permita.
3. **A IA não é usada para vigilância**, pontuação de comportamento, previsão de
   demissão, análise de sentimento de colaboradores ou perfilamento oculto.
4. **Todo uso é registrado** e auditável, incluindo consumo por funcionalidade.
5. **Você tem direito a revisão** de qualquer decisão apoiada por tratamento
   automatizado (art. 20 da LGPD).

---

## 2. Onde a IA é usada

### 2.1 Assistente de suporte nas conversas

**O que faz.** Responde dúvidas operacionais sobre a plataforma e sobre processos
internos, dentro de conversas e canais em que o assistente foi adicionado. Possui
personas por área (Geral, RH, TI, Administrativo, Comercial, Pós-venda).

**Dados enviados ao provedor.** O trecho recente da conversa em que o assistente
foi acionado, **após remoção automática** de CPF, CNPJ, número de cartão,
e-mail e telefone, que são substituídos por marcadores como `[CPF]` e `[EMAIL]`.

**Provedor.** Groq, modelo Llama 3.3 70B, servidores nos Estados Unidos.

**Limites.** O assistente não acessa conversas de que não participa, não consulta
a ficha funcional de terceiros e não toma decisões. Suas respostas podem conter
erros e não devem ser usadas como única base para decisão relevante.

> **Atenção.** A remoção automática cobre os formatos mais comuns de
> identificador. Ela **não** garante a supressão de todo dado pessoal escrito em
> texto livre — um nome próprio ou uma informação de saúde narrada em frase, por
> exemplo, seguem no texto. Não insira dados pessoais sensíveis, credenciais ou
> segredos comerciais em conversa com o assistente.

### 2.2 Extração de dados de currículo

**O que faz.** Lê o currículo enviado pelo candidato (PDF ou DOCX) e organiza as
informações em campos estruturados: formação, experiência, competências, idiomas.

**Dados enviados ao provedor.** O texto do currículo **após remoção automática**
de e-mails, telefones, CPF e do **nome do candidato** em todas as suas
ocorrências. O modelo recebe o conteúdo profissional sem os identificadores
diretos.

**Provedores.** Configurável por organização, com chave de API própria da
empresa: Anthropic (padrão, Claude Haiku), OpenAI, Google Gemini ou Groq. Todos
com servidores no exterior.

**Limites.** A IA **estrutura** informação; não classifica, não ordena e não
elimina candidatos. A triagem e a decisão são humanas.

### 2.3 Geração de itens de avaliação

**O que faz.** Sugere questões para testes e avaliações a partir de parâmetros
definidos pela equipe de RH.

**Dados enviados.** Descrição da vaga, competências e parâmetros do teste. Em
regra, **não** envolve dados pessoais de candidatos ou colaboradores.

**Limites.** As questões geradas são revisadas por pessoa antes de aplicadas.

### 2.4 Automações de RH

**O que faz.** Dispara alertas e comunicações a partir de regras configuradas —
vencimento de período de experiência, aniversários de admissão, pendências de
documentos.

**Natureza.** São **regras determinísticas** definidas por pessoas, não
aprendizado de máquina. Não produzem decisão sobre o titular; produzem lembrete
para que uma pessoa decida.

### 2.5 Transcrição de reuniões

Quando ativada, a transcrição converte fala em texto, com identificação do
participante. Os participantes são avisados antes do início. O texto fica
disponível apenas aos participantes da reunião.

---

## 3. Resumo dos dados enviados ao exterior

| Função | O que sai | O que **não** sai |
|--------|-----------|-------------------|
| Assistente de suporte | Trecho recente da conversa, com identificadores mascarados | Sua ficha funcional, seus dados sensíveis, conversas de que o assistente não participa |
| Extração de currículo | Texto do currículo sem nome, e-mail, telefone e CPF | O arquivo original, os documentos anexos, o histórico do candidato |
| Geração de questões | Parâmetros da vaga e do teste | Dados de candidatos identificados |
| Automações de RH | Nada — executam no próprio banco de dados | — |

Fundamento da transferência internacional e relação de provedores:
[documento 11](11-suboperadores-e-transferencia-internacional.md).

---

## 4. Uso dos seus dados para treinar modelos

Os provedores são contratados por meio de **API comercial**, cujos termos, em
regra, não autorizam o uso do conteúdo enviado para treinamento de modelos.

A confirmação contratual de cada fornecedor consta do documento 11, com o status
`[CONFIRMAR]` para os que ainda não tiveram a cláusula verificada pelo jurídico.
Enquanto o status não for confirmado, trate a informação como pendente de
verificação, não como garantia.

**A `[RAZÃO SOCIAL]` não treina modelos próprios com dados de colaboradores ou
candidatos.**

---

## 5. Registro e auditoria

Cada chamada aos serviços de IA é registrada com data e hora, funcionalidade,
provedor, modelo, volume de texto processado e custo estimado. O registro permite
demonstrar à ANPD e ao titular o que foi processado e quando.

O conteúdo enviado **não** é armazenado em duplicidade: permanece na conversa ou
no currículo de origem, sujeito aos prazos da
[Política de Retenção](08-politica-de-retencao-e-descarte.md).

---

## 6. Seus direitos (art. 20 da LGPD)

Você pode:

- **Solicitar revisão** de decisão tomada com base em tratamento automatizado que
  afete seus interesses, inclusive de perfil profissional;
- **Pedir informação clara e adequada** sobre os critérios e procedimentos
  utilizados, observados o segredo comercial e industrial;
- **Opor-se** ao tratamento quando fundado em legítimo interesse;
- **Não ser submetido** a decisão exclusivamente automatizada sobre aspectos da
  sua personalidade, perfil profissional ou desempenho — o que, nesta Plataforma,
  já é garantido por desenho.

**Como exercer:** Central de Privacidade no aplicativo (**Configurações →
Privacidade e Dados**) ou `[E-MAIL DO DPO]`. Prazo de resposta: até 15 dias.

A revisão é feita por pessoa da área competente, distinta de quem tomou a decisão
originária sempre que possível, e a resposta é fundamentada.

---

## 7. Riscos conhecidos e limitações

| Risco | Mitigação |
|-------|-----------|
| Resposta incorreta ou inventada pelo assistente | Aviso na interface; proibição de uso como base única de decisão |
| Extração de currículo com erro de leitura | Revisão humana antes de qualquer etapa decisória; candidato pode corrigir seus dados |
| Viés algorítmico na leitura de currículos | O modelo não classifica nem ordena candidatos; identificadores diretos são removidos antes do envio |
| Dado pessoal em texto livre que escapa da máscara | Orientação explícita ao usuário; minimização por regra; revisão do escopo a cada versão |
| Dependência de fornecedor no exterior | Contrato com cláusulas de proteção de dados; possibilidade de troca de provedor |

---

## 8. Governança

- Toda **nova** aplicação de IA na Plataforma passa por avaliação prévia de
  impacto quando envolver dados pessoais em escala ou dados sensíveis;
- Mudança de provedor, de modelo ou de escopo de dados enviados gera **nova
  versão** deste aviso e atualização do documento 11;
- O Encarregado é comunicado de qualquer incidente envolvendo serviços de IA.

---

## 9. Contato

**Encarregado (DPO):** `[NOME DO ENCARREGADO]` — `[E-MAIL DO DPO]`
**ANPD:** [gov.br/anpd](https://www.gov.br/anpd/pt-br)

---

*Base legal: arts. 6º, 9º, 20 e 33 da Lei nº 13.709/2018. Pendente de revisão por
advogado habilitado antes da vigência.*
