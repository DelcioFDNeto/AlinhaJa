/**
 * Índice das páginas legais — só metadados.
 *
 * Fica separado de `legal.tsx` de propósito: o `main.tsx` precisa decidir a
 * rota na entrada, e importar o componente aqui arrastaria o renderizador de
 * Markdown e o texto inteiro dos documentos para o bundle da home.
 */
export type LegalDocMeta = {
  /** Caminho público: `/termos`, `/privacidade`, … */
  slug: string;
  title: string;
  /** Nome do arquivo em `docs/legal/`, usado para resolver links entre docs. */
  file: string;
};

export const legalDocsMeta: LegalDocMeta[] = [
  { slug: 'termos', title: 'Termos de Uso', file: '01-termos-de-uso.md' },
  {
    slug: 'privacidade',
    title: 'Política de Privacidade',
    file: '02-politica-de-privacidade.md',
  },
  {
    slug: 'monitoramento',
    title: 'Monitoramento e Uso Aceitável',
    file: '03-politica-de-monitoramento-e-uso-aceitavel.md',
  },
  {
    slug: 'geolocalizacao',
    title: 'Consentimento — Geolocalização',
    file: '04-termo-de-consentimento-geolocalizacao.md',
  },
  {
    slug: 'candidatos',
    title: 'Privacidade — Candidatos',
    file: '05-aviso-de-privacidade-candidatos.md',
  },
  { slug: 'cookies', title: 'Cookies', file: '06-politica-de-cookies.md' },
  { slug: 'ia', title: 'Uso de IA', file: '07-aviso-de-ia-e-decisoes-automatizadas.md' },
  {
    slug: 'retencao',
    title: 'Retenção e Descarte',
    file: '08-politica-de-retencao-e-descarte.md',
  },
  {
    slug: 'fornecedores',
    title: 'Fornecedores e Transferência Internacional',
    file: '11-suboperadores-e-transferencia-internacional.md',
  },
];

/** Rota legal correspondente ao pathname, ou `null` para o site normal. */
export function matchLegalRoute(pathname: string): string | null {
  const clean = pathname.replace(/\/+$/, '').toLowerCase();
  if (clean === '/legal') return 'termos';

  const direct = legalDocsMeta.find((d) => clean === `/${d.slug}`);
  if (direct) return direct.slug;

  const nested = legalDocsMeta.find((d) => clean === `/legal/${d.slug}`);
  return nested ? nested.slug : null;
}

/** Resolve um link relativo entre documentos (`02-….md`) para o item do índice. */
export function metaByFile(href: string): LegalDocMeta | undefined {
  const name = href.split('/').pop()?.split('#')[0] ?? '';
  return legalDocsMeta.find((d) => d.file === name);
}

/**
 * Dados da empresa que preenchem os documentos publicados no site.
 *
 * O app lê isso do banco (`get_org_legal_profile`), porque lá o tenant varia. O
 * site é estático e de uma marca só, então os valores são de build — mas a
 * lista de campos é a MESMA do app (`kLegalFields` em
 * `lib/features/legal/models/org_legal_profile.dart`). Divergir daria um site
 * publicando dados diferentes do aplicativo.
 *
 * Campo vazio permanece entre colchetes de propósito: lacuna visível é honesta.
 */
export const legalProfile: Record<string, string> = {
  '[RAZÃO SOCIAL]': '',
  '[CNPJ]': '',
  '[ENDEREÇO COMPLETO]': '',
  '[NOME DO ENCARREGADO]': '',
  '[E-MAIL DO DPO]': '',
  '[DATA DE VIGÊNCIA]': '',
  '[COMARCA]': '',
  '[REGIÃO DE HOSPEDAGEM]': '',
  '[TELEFONE DE PLANTÃO]': '',
};

/**
 * Prazos de retenção que os documentos citam.
 *
 * No app eles vêm do tenant; aqui não há tenant, então valem os padrões das
 * rotinas de expurgo. Precisam estar preenchidos: sem isso o site publica
 * literalmente "`[7]` dias" na Política de Privacidade. Se a empresa alterar a
 * configuração, ajuste aqui também — site e app afirmando prazos diferentes é
 * contradição em documento público.
 */
export const legalRetencao: Record<string, string> = {
  '[7]': '7',
  '[24]': '24',
  '[RETENÇÃO DE MENSAGENS]': 'sem expiração automática',
};

/**
 * Aplica o perfil ao Markdown.
 *
 * Substituição por token exato, nunca por regex de colchetes: os documentos
 * usam colchetes também para links Markdown, marcadores de pendência
 * (`[CONFIRMAR]`) e exemplos de mascaramento de PII (`[CPF]`, `[NOME]`) — um
 * regex genérico corromperia justamente a seção que explica a anonimização.
 */
export function applyLegalProfile(markdown: string): string {
  let out = markdown;
  for (const [placeholder, value] of Object.entries(legalProfile)) {
    if (!value) continue;
    out = out.split(placeholder).join(value);
  }
  // Prazos entram sempre: deixar `[7]` visível não é "lacuna honesta", é um
  // número que o leitor não consegue interpretar.
  for (const [placeholder, value] of Object.entries(legalRetencao)) {
    out = out.split(placeholder).join(value);
  }
  return out;
}

/** Campos ainda não preenchidos — o site avisa em vez de fingir completude. */
export function missingLegalFields(): string[] {
  return Object.entries(legalProfile)
    .filter(([, value]) => !value)
    .map(([placeholder]) => placeholder);
}
