# PLATAFORMA ALINHAJÁ

**Questionário Técnico de Hospedagem**

---

# ORIENTAÇÕES

Objetivo do levantamento e configuração de referência para a máquina virtual.

## Objetivo

Este questionário reúne as informações técnicas necessárias para instalar a plataforma AlinhaJá em uma máquina virtual (VM) da empresa contratante. Nesse modelo, o **núcleo da plataforma** — banco de dados, autenticação, armazenamento de arquivos e funções de servidor — fica hospedado na infraestrutura da empresa, e o aplicativo é distribuído pela nuvem.

Cada resposta evita um retrabalho conhecido. Ao lado das perguntas, explicamos por que cada informação é necessária. Respostas como "não sei" são aceitas: elas apenas indicam pontos que trataremos juntos antes da instalação.

**Prazo de devolução:** antes da reunião de início do projeto.

## Configuração de Referência

| Usuários | Mínimo | Recomendado |
| --- | --- | --- |
| **Até 100** | 4 vCPU · 8 GB RAM · 100 GB SSD | 4 vCPU · 12 GB RAM · 150 GB SSD |
| **100 a 300** | 4 vCPU · 12 GB RAM · 250 GB SSD | 8 vCPU · 16 GB RAM · 250 GB SSD |
| **300 a 800** | 8 vCPU · 24 GB RAM · 500 GB SSD | 12 vCPU · 32 GB RAM · 500 GB NVMe |
| **Acima de 800** | Avaliação conjunta: banco de dados e serviços em servidores separados | |

**Sistema operacional:** Ubuntu Server 24.04 LTS, 64 bits.

> Com 8 GB de RAM a plataforma opera, mas com serviços de diagnóstico desativados e sem margem para crescimento. A RAM é o recurso mais sensível; o processador raramente é o limite.

---

# QUESTIONÁRIO

Identificação, porte, máquina, acesso, rede, certificado, energia, backup, e-mail e conformidade.

## 1. Identificação e Contatos

| # | Pergunta | Resposta |
| --- | --- | --- |
| 1.1 | Razão social da empresa | |
| 1.2 | Responsável técnico pela infraestrutura (nome, cargo, telefone e e-mail) | |
| 1.3 | Contato para incidentes fora do horário comercial | |
| 1.4 | Canal seguro para envio de credenciais | ( ) Cofre de senhas ( ) E-mail criptografado ( ) Outro: {campo} |

> **Por que perguntamos:** senhas e arquivos de configuração de VPN contêm chaves privadas que dão acesso à rede interna da empresa. Enviados por grupos de mensagens, ficam replicados nos aparelhos e nos backups de todos os participantes — e precisam ser trocados depois.

## 2. Porte e Perfil de Uso

| # | Pergunta | Resposta |
| --- | --- | --- |
| 2.1 | Número total de usuários | |
| 2.2 | Usuários simultâneos no horário de pico (estimativa) | |
| 2.3 | Quantidade de filiais ou unidades | |
| 2.4 | Haverá colaboradores acessando fora da rede da empresa (equipes externas, dados móveis, home office)? | ( ) Sim ( ) Não |
| 2.5 | Haverá usuários de iPhone? | ( ) Sim ( ) Não |
| 2.6 | Módulos previstos | ( ) Comunicação ( ) Kanban ( ) Helpdesk ( ) RH ( ) GPS |
| 2.7 | Volume esperado de anexos (fotos, documentos, holerites) | ( ) Baixo ( ) Médio ( ) Alto |

> **Por que perguntamos:** o número de usuários define o dimensionamento da máquina. Colaboradores fora da rede e usuários de iPhone só conseguem usar o sistema se o servidor for publicado na internet (Seção 5). O módulo de RH e o volume de anexos determinam o crescimento do disco.

## 3. Máquina Virtual

| # | Pergunta | Resposta |
| --- | --- | --- |
| 3.1 | Hipervisor | ( ) VMware ( ) Proxmox ( ) Hyper-V ( ) Outro: {campo} |
| 3.2 | Processadores, memória e disco disponibilizados | vCPU: {campo} RAM: {campo} Disco: {campo} |
| 3.3 | Tipo de disco | ( ) SSD ( ) NVMe ( ) HDD |
| 3.4 | O disco pode ser ampliado sem recriar a máquina? | ( ) Sim ( ) Não |
| 3.5 | A memória pode ser ampliada mediante solicitação? Em quanto tempo? | ( ) Sim, em: {campo} ( ) Não |
| 3.6 | Sistema operacional instalado | ( ) Ubuntu Server 24.04 LTS ( ) Outro: {campo} |
| 3.7 | Se a instalação usar LVM, o volume ocupará todo o disco disponibilizado? | ( ) Sim ( ) Não ( ) Não sei |
| 3.8 | A VM tem snapshots? Com que frequência e retenção? | |
| 3.9 | Teremos acesso ao console do hipervisor em caso de emergência? | ( ) Sim ( ) Não |

> **Por que perguntamos:** o instalador do Ubuntu, por padrão, aloca cerca de 100 GB do disco ao volume do sistema, mesmo quando o disco entregue é maior — o espaço existe, mas fica sem uso até ser estendido. O acesso ao console é a rede de segurança para a configuração do firewall: um erro feito por acesso remoto pode deixar a máquina inalcançável.

## 4. Acesso Administrativo

| # | Pergunta | Resposta |
| --- | --- | --- |
| 4.1 | Forma de acesso remoto para a nossa equipe | ( ) VPN, tipo: {campo} ( ) Acesso restrito por IP ( ) Outro: {campo} |
| 4.2 | O acesso SSH aceita autenticação por chave pública? | ( ) Sim ( ) Apenas senha |
| 4.3 | O usuário fornecido terá privilégios de administrador (sudo)? | ( ) Sim ( ) Não |
| 4.4 | Autorização para instalar Docker e ferramentas de suporte | ( ) Autorizado ( ) Requer aprovação de: {campo} |
| 4.5 | Há políticas que restrinjam contêineres, exijam antivírus ou EDR em Linux, ou imponham padrões de hardening? | |

> **Por que perguntamos:** a plataforma roda em contêineres Docker. Políticas corporativas de segurança precisam ser conhecidas antes da instalação para não haver conflito com os controles da empresa.

## 5. Rede e Publicação

| # | Pergunta | Resposta |
| --- | --- | --- |
| 5.1 | O endereço IP público da empresa é | ( ) Fixo ( ) Dinâmico |
| 5.2 | Endereço que o aplicativo usará para acessar o servidor | ( ) Subdomínio próprio: {campo} ( ) DDNS: {campo} |
| 5.3 | É possível redirecionar as portas 443 e 80 do IP público para a VM? | ( ) Sim ( ) Não |
| 5.4 | A porta 443 desse IP público já está em uso por outro serviço? | ( ) Sim, qual: {campo} ( ) Não |
| 5.5 | O firewall permite conexões WebSocket (wss)? | ( ) Sim ( ) Não sei |
| 5.6 | A VM terá saída para a internet por HTTPS? | ( ) Livre ( ) Restrita a lista ( ) Não |
| 5.7 | Há proxy de saída ou inspeção de tráfego criptografado? | ( ) Sim ( ) Não |
| 5.8 | Velocidade do link de internet | Download: {campo} Upload: {campo} |
| 5.9 | Há link de internet redundante? | ( ) Sim ( ) Não |

> **Por que perguntamos — esta é a seção mais importante.** O aplicativo é executado no aparelho de cada colaborador, e é o aparelho que conversa diretamente com o servidor; a nuvem entrega apenas a interface. Um servidor acessível somente pela rede interna ou por VPN não atende quem está fora dela.
>
> O endereço do servidor é **gravado dentro do aplicativo**. Trocá-lo depois exige gerar e redistribuir o aplicativo para todos os usuários — por isso o endereço definitivo precisa ser escolhido antes da instalação. Recomendamos subdomínio do domínio próprio da empresa; serviços gratuitos de DDNS funcionam, mas tornam a disponibilidade do sistema dependente de um terceiro.
>
> A velocidade de **upload** é a que mais pesa: cada foto ou documento aberto por um colaborador é enviado pelo link da empresa. A saída para a internet é necessária para atualizações, notificações, e-mail e Inteligência Artificial.

## 6. Certificado de Segurança (TLS)

| # | Pergunta | Resposta |
| --- | --- | --- |
| 6.1 | Forma de emissão do certificado | ( ) Let's Encrypt automático ( ) Certificado da empresa |
| 6.2 | Se for certificado da empresa: validade e responsável pela renovação | |

> **Por que perguntamos:** o certificado é validado pelo navegador e pelo aplicativo no aparelho de cada colaborador, inclusive em aparelhos pessoais. Por isso precisa ser emitido por autoridade pública — certificados de autoridade interna não são reconhecidos por esses aparelhos. O Let's Encrypt exige a porta 80 aberta, também para a renovação automática a cada 90 dias.

## 7. Energia e Disponibilidade

| # | Pergunta | Resposta |
| --- | --- | --- |
| 7.1 | O servidor é protegido por nobreak ou gerador? | ( ) Sim ( ) Não |
| 7.2 | Horário de operação da empresa | ( ) Comercial ( ) Estendido ( ) 24 horas |
| 7.3 | Janela autorizada para manutenção (dia e horário) | |
| 7.4 | Após queda de energia, a VM é religada automaticamente? | ( ) Sim ( ) Não |

> **Por que perguntamos:** com o servidor na rede da empresa, o link de internet e a energia do local passam a ser ponto único de falha para todos os usuários — inclusive para quem está fora da empresa. A plataforma é configurada para subir sozinha após um reinício, mas depende de a máquina virtual também ser religada.

## 8. Backup e Continuidade

| # | Pergunta | Resposta |
| --- | --- | --- |
| 8.1 | Destino das cópias de segurança fora da VM | ( ) Segundo disco ( ) Storage de rede ( ) Nuvem corporativa ( ) Não há |
| 8.2 | Retenção desejada para as cópias | {campo} dias |
| 8.3 | Responsável pelo teste periódico de restauração | |
| 8.4 | Ferramenta de monitoramento em uso | ( ) Zabbix ( ) PRTG ( ) Outra: {campo} ( ) Não há |

> **Por que perguntamos:** snapshot da máquina virtual não substitui a cópia do banco de dados, e cópias guardadas no mesmo disco não protegem contra falha de hardware. A plataforma gera cópias diárias verificadas; o destino externo e o teste de restauração definem se elas servem quando forem necessárias.

## 9. E-mail Corporativo (SMTP)

| # | Pergunta | Resposta |
| --- | --- | --- |
| 9.1 | Provedor de e-mail | ( ) Microsoft 365 ( ) Google Workspace ( ) Servidor próprio ( ) Outro: {campo} |
| 9.2 | Servidor e porta de envio (ex.: smtp.office365.com, porta 587) | |
| 9.3 | Conta remetente (ex.: nao-responda@empresa.com.br) | |
| 9.4 | Os colaboradores possuem e-mail corporativo individual? | ( ) Todos ( ) Parte ( ) Nenhum |

> **Por que perguntamos:** o servidor de e-mail envia a recuperação de senha e as comunicações do recrutamento. Colaboradores sem e-mail individual recebem senha temporária, trocada obrigatoriamente no primeiro acesso — e esse caminho precisa ser definido antes do cadastro dos usuários.

## 10. Localização e Conformidade

| # | Pergunta | Resposta |
| --- | --- | --- |
| 10.1 | Fuso horário da operação | |
| 10.2 | Há exigência de que nenhum dado trafegue para fora da rede da empresa? | ( ) Sim ( ) Não |
| 10.3 | A empresa já indicou Encarregado de Proteção de Dados (DPO)? | ( ) Sim, nome: {campo} ( ) Não |

> **Por que perguntamos:** o fuso horário afeta o registro de ponto e o horário das rotinas automáticas. Se nenhum dado puder sair da rede, as notificações e a Inteligência Artificial precisam de solução específica, descrita no documento de requisitos de implantação. O Encarregado é exigido pela LGPD e consta dos documentos legais da plataforma.

## 11. Responsável pelo Preenchimento

| # | Pergunta | Resposta |
| --- | --- | --- |
| 11.1 | Nome | |
| 11.2 | Cargo | |
| 11.3 | E-mail e telefone | |
| 11.4 | Data | |
| 11.5 | Assinatura | |

## Próximos Passos

Com o questionário devolvido, a equipe da AlinhaJá:

- Confere as respostas com a configuração de referência e aponta eventuais ajustes;
- Registra como pendência cada item marcado "Não" ou "Não sei", com o responsável e o prazo para resolução;
- Confirma a data da reunião de início e o cronograma de implantação.

---

*AlinhaJá — Questionário Técnico de Hospedagem. As configurações de referência correspondem à versão atual da plataforma e podem ser revisadas em novas versões.*
