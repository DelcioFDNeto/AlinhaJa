import { useEffect, useState } from 'react';
import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';
import { ArrowLeft, FileText } from 'lucide-react';

import { brand } from './brand';
import {
  applyLegalProfile,
  legalDocsMeta,
  matchLegalRoute,
  metaByFile,
  missingLegalFields,
} from './legal-routes';
import './legal.css';

/* Os textos vêm de docs/legal/ — a MESMA fonte lida pelo app Flutter. Nada de
   copiar o conteúdo para cá: divergência entre o que o site publica e o que o
   app exibe é problema jurídico, não de conteúdo. */
import termos from '../../docs/legal/01-termos-de-uso.md?raw';
import privacidade from '../../docs/legal/02-politica-de-privacidade.md?raw';
import monitoramento from '../../docs/legal/03-politica-de-monitoramento-e-uso-aceitavel.md?raw';
import geolocalizacao from '../../docs/legal/04-termo-de-consentimento-geolocalizacao.md?raw';
import candidatos from '../../docs/legal/05-aviso-de-privacidade-candidatos.md?raw';
import cookies from '../../docs/legal/06-politica-de-cookies.md?raw';
import ia from '../../docs/legal/07-aviso-de-ia-e-decisoes-automatizadas.md?raw';
import retencao from '../../docs/legal/08-politica-de-retencao-e-descarte.md?raw';
import fornecedores from '../../docs/legal/11-suboperadores-e-transferencia-internacional.md?raw';

const bodies: Record<string, string> = {
  termos,
  privacidade,
  monitoramento,
  geolocalizacao,
  candidatos,
  cookies,
  ia,
  retencao,
  fornecedores,
};

export default function LegalPage({ initialSlug }: { initialSlug: string }) {
  const [slug, setSlug] = useState(initialSlug);

  const doc = legalDocsMeta.find((d) => d.slug === slug) ?? legalDocsMeta[0];

  /* Botão "voltar" do navegador troca o documento em vez de sair da SPA. */
  useEffect(() => {
    const onPop = () => {
      const next = matchLegalRoute(window.location.pathname);
      if (next) setSlug(next);
    };
    window.addEventListener('popstate', onPop);
    return () => window.removeEventListener('popstate', onPop);
  }, []);

  useEffect(() => {
    document.title = `${doc.title} · ${brand.name}`;
    window.scrollTo({ top: 0 });
  }, [doc]);

  const goTo = (next: string) => {
    window.history.pushState({}, '', `/${next}`);
    setSlug(next);
  };

  return (
    <div className="legal">
      <header className="legal-top">
        <a className="legal-back" href="/">
          <ArrowLeft size={16} /> Voltar ao site
        </a>
        <div className="legal-brand">
          <img src={brand.logoHeader} alt="" />
          <span>{brand.name}</span>
        </div>
      </header>

      <div className="legal-shell">
        <nav className="legal-nav" aria-label="Documentos legais">
          <p className="legal-nav-title">
            <FileText size={14} /> Documentos
          </p>
          {legalDocsMeta.map((d) => (
            <button
              key={d.slug}
              className={
                d.slug === doc.slug ? 'legal-nav-item is-active' : 'legal-nav-item'
              }
              onClick={() => goTo(d.slug)}
            >
              {d.title}
            </button>
          ))}
        </nav>

        <article className="legal-body">
          {missingLegalFields().length > 0 && (
            <p className="legal-pending">
              <strong>Documento pendente de personalização.</strong> Os campos
              entre colchetes ainda não foram preenchidos com os dados da
              empresa e este texto não está em vigor.
            </p>
          )}
          <ReactMarkdown
            remarkPlugins={[remarkGfm]}
            components={{
              a: ({ href, children, ...props }) => {
                const target = href ? metaByFile(href) : undefined;
                if (target) {
                  return (
                    <a
                      href={`/${target.slug}`}
                      onClick={(e) => {
                        e.preventDefault();
                        goTo(target.slug);
                      }}
                      {...props}
                    >
                      {children}
                    </a>
                  );
                }
                // Documento interno que o site não publica (ROPA, plano de
                // incidentes): mostra o texto sem link morto.
                if (href?.endsWith('.md')) return <span>{children}</span>;
                return (
                  <a href={href} target="_blank" rel="noopener noreferrer" {...props}>
                    {children}
                  </a>
                );
              },
              table: ({ children, ...props }) => (
                <div className="legal-table-wrap">
                  <table {...props}>{children}</table>
                </div>
              ),
            }}
          >
            {applyLegalProfile(bodies[doc.slug] ?? '')}
          </ReactMarkdown>
        </article>
      </div>

      <footer className="legal-foot">
        © {new Date().getFullYear()} {brand.name} · Documentos sujeitos a revisão
        jurídica antes da vigência.
      </footer>
    </div>
  );
}
