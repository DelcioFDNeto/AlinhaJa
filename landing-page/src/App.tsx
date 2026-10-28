import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { AnimatePresence, LazyMotion, domAnimation, m as Motion } from 'framer-motion';
import {
  ArrowRight,
  Check,
  ChevronLeft,
  ChevronRight,
  Download,
  ExternalLink,
  Globe,
  Maximize2,
  Menu,
  Smartphone,
  Sparkles,
  X,
} from 'lucide-react';
import { brand } from './brand';
import { legalDocsMeta } from './legal-routes';
import {
  areas,
  comparisonRows,
  features,
  flowSteps,
  heroStats,
  pillars,
  type Shot,
} from './content';
import './index.css';

const navItems = [
  { href: '#plataforma', label: 'Plataforma' },
  { href: '#areas', label: 'Áreas' },
  { href: '#recursos', label: 'Recursos' },
  { href: '#galeria', label: 'Galeria' },
  { href: '#baixar', label: 'Baixar' },
];

const allShots: Shot[] = areas.flatMap((area) => area.shots);

const reveal = {
  initial: { opacity: 0, y: 20 },
  whileInView: { opacity: 1, y: 0 },
  viewport: { once: true, margin: '-40px', amount: 0.1 },
  transition: { duration: 0.4, ease: 'easeOut' as const },
};

/* ------------------------------------------------------------------ */
/* Chrome                                                              */
/* ------------------------------------------------------------------ */

const Aurora = React.memo(() => (
  <div className="aurora" aria-hidden="true">
    <span className="aurora-blob blob-a" />
    <span className="aurora-blob blob-b" />
    <span className="aurora-blob blob-c" />
    <span className="aurora-grid" />
  </div>
));

const Navbar = () => {
  const [scrolled, setScrolled] = useState(false);
  const [open, setOpen] = useState(false);

  useEffect(() => {
    let lastScrolled = window.scrollY > 24;
    setScrolled(lastScrolled);
    const onScroll = () => {
      const isScrolled = window.scrollY > 24;
      if (isScrolled !== lastScrolled) {
        lastScrolled = isScrolled;
        setScrolled(isScrolled);
      }
    };
    window.addEventListener('scroll', onScroll, { passive: true });
    return () => window.removeEventListener('scroll', onScroll);
  }, []);

  return (
    <nav className={`nav ${scrolled ? 'nav-solid' : ''}`}>
      <div className="nav-inner">
        <a href="#topo" className="nav-brand" aria-label={`${brand.name} — início`}>
          <img src={brand.logoHeader} alt="" />
          <span>{brand.name}</span>
        </a>

        <div className="nav-links">
          {navItems.map((item) => (
            <a key={item.href} href={item.href}>
              {item.label}
            </a>
          ))}
        </div>

        <div className="nav-actions">
          <a
            className="btn btn-ghost nav-cta"
            href={brand.appUrl}
            target="_blank"
            rel="noopener noreferrer"
          >
            Acessar web <ArrowRight size={14} />
          </a>
          <button
            type="button"
            className="nav-burger"
            aria-label={open ? 'Fechar menu' : 'Abrir menu'}
            aria-expanded={open}
            onClick={() => setOpen((v) => !v)}
          >
            {open ? <X size={20} /> : <Menu size={20} />}
          </button>
        </div>
      </div>

      <AnimatePresence>
        {open && (
          <Motion.div
            className="nav-mobile"
            initial={{ opacity: 0, height: 0 }}
            animate={{ opacity: 1, height: 'auto' }}
            exit={{ opacity: 0, height: 0 }}
          >
            {navItems.map((item) => (
              <a key={item.href} href={item.href} onClick={() => setOpen(false)}>
                {item.label}
              </a>
            ))}
            <a href={brand.appUrl} target="_blank" rel="noopener noreferrer">
              Acessar web
            </a>
          </Motion.div>
        )}
      </AnimatePresence>
    </nav>
  );
};

/** Moldura de navegador usada em toda captura de tela. */
const Frame = ({
  shot,
  onOpen,
  eager = false,
}: {
  shot: Shot;
  onOpen?: () => void;
  eager?: boolean;
}) => (
  <figure className="frame">
    <div className="frame-bar">
      <span />
      <span />
      <span />
      <p>{shot.title}</p>
      {onOpen && (
        <button type="button" onClick={onOpen} aria-label={`Ampliar: ${shot.title}`}>
          <Maximize2 size={13} />
        </button>
      )}
    </div>
    <img
      src={shot.src}
      alt={shot.title}
      width="1200"
      height="750"
      loading={eager ? 'eager' : 'lazy'}
      decoding="async"
      fetchPriority={eager ? 'high' : 'auto'}
      onClick={onOpen}
      style={onOpen ? { cursor: 'zoom-in' } : undefined}
    />
  </figure>
);

const SectionHead = ({
  eyebrow,
  title,
  desc,
  color = 'var(--primary)',
}: {
  eyebrow: string;
  title: React.ReactNode;
  desc?: string;
  color?: string;
}) => (
  <Motion.header className="sec-head" {...reveal}>
    <span className="eyebrow" style={{ color, borderColor: `${color}33` }}>
      {eyebrow}
    </span>
    <h2>{title}</h2>
    {desc && <p>{desc}</p>}
  </Motion.header>
);

/* ------------------------------------------------------------------ */
/* Seções                                                              */
/* ------------------------------------------------------------------ */

const Hero = () => (
  <section id="topo" className="hero">
    <div className="hero-copy">
      <Motion.span
        className="hero-badge"
        initial={{ opacity: 0, y: 12 }}
        animate={{ opacity: 1, y: 0 }}
      >
        <Sparkles size={13} /> {brand.tagline}
      </Motion.span>

      <Motion.h1
        initial={{ opacity: 0, y: 20 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ delay: 0.05 }}
      >
        Comunicação, operação e <span className="grad">RH completo</span> em um
        só sistema
      </Motion.h1>

      <Motion.p
        initial={{ opacity: 0, y: 20 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ delay: 0.12 }}
      >
        O {brand.name} transforma conversa solta em processo rastreável — e ainda
        cuida de funcionários, documentos, férias, ponto, holerites, benefícios,
        desempenho e recrutamento. Tudo com permissão por módulo e histórico
        auditável.
      </Motion.p>

      <Motion.div
        className="hero-cta"
        initial={{ opacity: 0, y: 20 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ delay: 0.18 }}
      >
        <a
          className="btn btn-primary"
          href={brand.appUrl}
          target="_blank"
          rel="noopener noreferrer"
        >
          <Globe size={15} /> Acessar pela web
        </a>
        <a className="btn btn-ghost" href="#baixar">
          <Download size={15} /> Baixar o app
        </a>
      </Motion.div>

      <Motion.dl
        className="hero-stats"
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        transition={{ delay: 0.25 }}
      >
        {heroStats.map((stat) => (
          <div key={stat.label}>
            <dt>{stat.value}</dt>
            <dd>{stat.label}</dd>
          </div>
        ))}
      </Motion.dl>
    </div>

    <Motion.div
      className="hero-visual"
      initial={{ opacity: 0, scale: 0.96, y: 30 }}
      animate={{ opacity: 1, scale: 1, y: 0 }}
      transition={{ delay: 0.2, duration: 0.7, ease: 'easeOut' }}
    >
      <Frame
        eager
        shot={{
          src: '/shots/nav-modulos.webp',
          title: `${brand.name} — navegação completa`,
          desc: '',
        }}
      />
      <div className="float-card float-a">
        <strong>Estou Ciente</strong>
        <span>leitura confirmada</span>
      </div>
      <div className="float-card float-b">
        <strong>ASO vence em 30d</strong>
        <span>alerta automático de RH</span>
      </div>
    </Motion.div>
  </section>
);

const Marquee = () => {
  const items = useMemo(() => features.map((f) => f.title), []);
  return (
    <div className="marquee" aria-hidden="true">
      <div className="marquee-track">
        {[...items, ...items].map((label, i) => (
          <span key={`${label}-${i}`}>{label}</span>
        ))}
      </div>
    </div>
  );
};

const Pillars = () => (
  <section id="plataforma" className="sec">
    <SectionHead
      eyebrow="Por que existe"
      title={<>Uma plataforma, não cinco assinaturas</>}
      desc="O que hoje se espalha entre grupo de mensagem, planilha de férias, pasta de documentos e sistema de vagas cabe em um login só."
      color="#10b981"
    />
    <div className="pillar-grid">
      {pillars.map((item, i) => (
        <Motion.article
          key={item.title}
          className="card pillar"
          {...reveal}
          transition={{ ...reveal.transition, delay: i * 0.07 }}
          style={{ '--tint': item.color } as React.CSSProperties}
        >
          <div className="pillar-icon">{item.icon}</div>
          <h3>{item.title}</h3>
          <p>{item.desc}</p>
        </Motion.article>
      ))}
    </div>
  </section>
);

const Showcase = ({ onOpen }: { onOpen: (shot: Shot) => void }) => {
  const [active, setActive] = useState(0);
  const [index, setIndex] = useState(0);
  const area = areas[active];
  const shot = area.shots[index];

  const pick = (next: number) => {
    setActive(next);
    setIndex(0);
  };

  return (
    <section id="areas" className="sec sec-alt">
      <SectionHead
        eyebrow="O sistema por dentro"
        title={<>Capturas reais, não ilustração</>}
        desc="Navegue pelas cinco áreas da plataforma e veja exatamente como cada tela funciona."
        color="#3b82f6"
      />

      <div className="tabs" role="tablist">
        {areas.map((item, i) => (
          <button
            key={item.id}
            type="button"
            role="tab"
            aria-selected={i === active}
            className={`tab ${i === active ? 'tab-on' : ''}`}
            style={{ '--tint': item.color } as React.CSSProperties}
            onClick={() => pick(i)}
          >
            {item.icon}
            {item.label}
          </button>
        ))}
      </div>

      <AnimatePresence mode="wait">
        <Motion.div
          key={area.id}
          className="showcase"
          initial={{ opacity: 0, y: 16 }}
          animate={{ opacity: 1, y: 0 }}
          exit={{ opacity: 0, y: -12 }}
          transition={{ duration: 0.3 }}
          style={{ '--tint': area.color } as React.CSSProperties}
        >
          <div className="showcase-copy">
            <h3>{area.headline}</h3>
            <p>{area.summary}</p>
            <ul>
              {area.bullets.map((bullet) => (
                <li key={bullet}>
                  <Check size={13} /> {bullet}
                </li>
              ))}
            </ul>

            <div className="thumbs">
              {area.shots.map((item, i) => (
                <button
                  key={item.src}
                  type="button"
                  className={`thumb ${i === index ? 'thumb-on' : ''}`}
                  onClick={() => setIndex(i)}
                  aria-label={item.title}
                >
                  <img src={item.src} alt="" loading="lazy" decoding="async" />
                </button>
              ))}
            </div>
          </div>

          <div className="showcase-stage">
            <Frame shot={shot} onOpen={() => onOpen(shot)} />
            <p className="stage-caption">
              <strong>{shot.title}</strong> {shot.desc}
            </p>
          </div>
        </Motion.div>
      </AnimatePresence>
    </section>
  );
};

const Features = () => (
  <section id="recursos" className="sec">
    <SectionHead
      eyebrow="Recursos"
      title={<>Tudo que já está pronto</>}
      desc="Cada item abaixo é um módulo em produção, acessível conforme o perfil de acesso do usuário."
      color="#a855f7"
    />
    <div className="feat-grid">
      {features.map((item, i) => (
        <Motion.div
          key={item.title}
          className="card feat"
          initial={{ opacity: 0, scale: 0.96 }}
          whileInView={{ opacity: 1, scale: 1 }}
          viewport={{ once: true, amount: 0.1 }}
          transition={{ delay: (i % 6) * 0.02, duration: 0.25 }}
          style={{ '--tint': item.color } as React.CSSProperties}
        >
          <span className="feat-icon">{item.icon}</span>
          <div>
            <h4>{item.title}</h4>
            <p>{item.desc}</p>
          </div>
        </Motion.div>
      ))}
    </div>
  </section>
);

const Flow = () => (
  <section className="sec sec-alt">
    <SectionHead
      eyebrow="Como funciona"
      title={<>Da solicitação ao registro final</>}
      desc="O mesmo motor de funil atende contas a pagar, faturamento, emplacamento, chamados de TI e processo seletivo."
      color="#f59e0b"
    />
    <div className="flow">
      {flowSteps.map((step, i) => (
        <React.Fragment key={step.title}>
          <Motion.div
            className="card flow-step"
            {...reveal}
            transition={{ ...reveal.transition, delay: i * 0.08 }}
            style={{ '--tint': step.color } as React.CSSProperties}
          >
            <span className="flow-icon">{step.icon}</span>
            <span className="flow-num">Etapa {i + 1}</span>
            <h4>{step.title}</h4>
            <p>{step.desc}</p>
          </Motion.div>
          {i < flowSteps.length - 1 && (
            <span className="flow-arrow" aria-hidden="true">
              <ChevronRight size={14} />
            </span>
          )}
        </React.Fragment>
      ))}
    </div>
  </section>
);

const Gallery = ({ onOpen }: { onOpen: (shot: Shot) => void }) => {
  const [limit, setLimit] = useState(12);
  const visible = allShots.slice(0, limit);

  return (
    <section id="galeria" className="sec">
      <SectionHead
        eyebrow="Galeria"
        title={<>As {allShots.length} telas em um lugar</>}
        desc="Clique em qualquer captura para ver em tamanho real."
        color="#06b6d4"
      />
      <div className="gallery">
        {visible.map((shot, i) => (
          <Motion.button
            key={shot.src}
            type="button"
            className="gallery-item"
            onClick={() => onOpen(shot)}
            initial={{ opacity: 0, y: 16 }}
            whileInView={{ opacity: 1, y: 0 }}
            viewport={{ once: true, amount: 0.1 }}
            transition={{ delay: (i % 4) * 0.03, duration: 0.25 }}
          >
            <img src={shot.src} alt={shot.title} loading="lazy" decoding="async" />
            <span className="gallery-meta">
              <strong>{shot.title}</strong>
              <em>{shot.desc}</em>
            </span>
          </Motion.button>
        ))}
      </div>
      {limit < allShots.length && (
        <div className="gallery-more">
          <button
            type="button"
            className="btn btn-ghost"
            onClick={() => setLimit(allShots.length)}
          >
            Ver as {allShots.length - limit} telas restantes
          </button>
        </div>
      )}
    </section>
  );
};

const Comparison = () => (
  <section className="sec sec-alt">
    <SectionHead
      eyebrow="Além do grupo de mensagem"
      title={<>Conversa rápida não sustenta operação</>}
      desc="Quando a demanda precisa virar entrega — e ficar registrada — o chat comum não dá conta."
      color="#f59e0b"
    />
    <div className="compare">
      <Motion.div className="card compare-side muted" {...reveal}>
        <h3>Grupo de mensagem</h3>
        <div className="bubbles">
          <span>“Quem ficou com isso?”</span>
          <span>“Já mandei o ASO dele?”</span>
          <span>“Isso foi aprovado ou não?”</span>
        </div>
      </Motion.div>

      <Motion.div
        className="card compare-side strong"
        {...reveal}
        transition={{ ...reveal.transition, delay: 0.1 }}
      >
        <h3>{brand.name}</h3>
        <ul>
          {comparisonRows.map(([label]) => (
            <li key={label}>
              <Check size={13} /> {label}
            </li>
          ))}
        </ul>
      </Motion.div>
    </div>
  </section>
);

const Download_ = () => (
  <section id="baixar" className="sec">
    <SectionHead
      eyebrow="Comece agora"
      title={<>Web no desktop, app no bolso</>}
      desc="A mesma conta funciona nos dois. O app Android adiciona notificações push e GPS em segundo plano."
    />
    <div className="download">
      <Motion.article className="card dl-card" {...reveal} style={{ '--tint': 'var(--primary)' } as React.CSSProperties}>
        <span className="dl-icon">
          <Smartphone size={18} />
        </span>
        <h3>App Android</h3>
        <p>APK nativo</p>
        <ul>
          {['Notificações push', 'GPS em segundo plano', 'Chamadas integradas', 'Leitura offline'].map(
            (item) => (
              <li key={item}>
                <Check size={12} /> {item}
              </li>
            ),
          )}
        </ul>
        <a className="btn btn-primary" href={brand.apkUrl} target="_blank" rel="noopener noreferrer">
          <Download size={14} /> Baixar APK
        </a>
      </Motion.article>

      <Motion.article
        className="card dl-card"
        {...reveal}
        transition={{ ...reveal.transition, delay: 0.1 }}
        style={{ '--tint': '#8b5cf6' } as React.CSSProperties}
      >
        <span className="dl-icon">
          <Globe size={18} />
        </span>
        <h3>Web / PWA</h3>
        <p>Direto no navegador</p>
        <ul>
          {['Sem instalar nada', 'Painéis administrativos', 'Instale na área de trabalho', 'Qualquer navegador'].map(
            (item) => (
              <li key={item}>
                <Check size={12} /> {item}
              </li>
            ),
          )}
        </ul>
        <a className="btn btn-ghost" href={brand.appUrl} target="_blank" rel="noopener noreferrer">
          <ExternalLink size={14} /> Acessar agora
        </a>
      </Motion.article>
    </div>
  </section>
);

const Footer = () => (
  <footer className="foot">
    <div className="foot-grid">
      <div className="foot-col foot-col-brand">
        <div className="foot-brand">
          <img src={brand.logoHeader} alt="" />
          <span>{brand.name}</span>
        </div>
        <p>{brand.tagline}</p>
        <a className="foot-cta" href={brand.appUrl} target="_blank" rel="noopener noreferrer">
          Acessar a plataforma <ExternalLink size={13} />
        </a>
      </div>

      <nav className="foot-col" aria-labelledby="foot-produto">
        <h4 id="foot-produto">Plataforma</h4>
        {navItems.map((item) => (
          <a key={item.href} href={item.href}>
            {item.label}
          </a>
        ))}
      </nav>

      {/* Gerado a partir do índice em legal-routes.ts: documento novo no
          registro aparece aqui sozinho, sem link esquecido para trás. */}
      <nav className="foot-col" aria-labelledby="foot-legal">
        <h4 id="foot-legal">Legal e privacidade</h4>
        {legalDocsMeta.map((doc) => (
          <a key={doc.slug} href={`/${doc.slug}`}>
            {doc.title}
          </a>
        ))}
      </nav>
    </div>

    <div className="foot-bottom">
      <p className="foot-fine">
        © {new Date().getFullYear()} {brand.name} · Desenvolvido por{' '}
        <strong>{brand.author}</strong>
      </p>
      <p className="foot-fine">
        Tratamento de dados conforme a Lei nº 13.709/2018 (LGPD).
      </p>
    </div>
  </footer>
);

/* ------------------------------------------------------------------ */
/* Lightbox                                                            */
/* ------------------------------------------------------------------ */

const Lightbox = ({
  shot,
  onClose,
  onStep,
}: {
  shot: Shot;
  onClose: () => void;
  onStep: (delta: number) => void;
}) => {
  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      if (event.key === 'Escape') onClose();
      if (event.key === 'ArrowRight') onStep(1);
      if (event.key === 'ArrowLeft') onStep(-1);
    };
    window.addEventListener('keydown', onKey);
    document.body.style.overflow = 'hidden';
    return () => {
      window.removeEventListener('keydown', onKey);
      document.body.style.overflow = '';
    };
  }, [onClose, onStep]);

  return (
    <Motion.div
      className="lightbox"
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      exit={{ opacity: 0 }}
      onClick={onClose}
      role="dialog"
      aria-modal="true"
      aria-label={shot.title}
    >
      <button type="button" className="lb-close" onClick={onClose} aria-label="Fechar">
        <X size={20} />
      </button>
      <button
        type="button"
        className="lb-nav lb-prev"
        onClick={(e) => {
          e.stopPropagation();
          onStep(-1);
        }}
        aria-label="Anterior"
      >
        <ChevronLeft size={22} />
      </button>
      <Motion.figure
        className="lb-body"
        initial={{ scale: 0.95, opacity: 0 }}
        animate={{ scale: 1, opacity: 1 }}
        onClick={(e) => e.stopPropagation()}
      >
        <img src={shot.src} alt={shot.title} />
        <figcaption>
          <strong>{shot.title}</strong>
          <span>{shot.desc}</span>
        </figcaption>
      </Motion.figure>
      <button
        type="button"
        className="lb-nav lb-next"
        onClick={(e) => {
          e.stopPropagation();
          onStep(1);
        }}
        aria-label="Próxima"
      >
        <ChevronRight size={22} />
      </button>
    </Motion.div>
  );
};

/* ------------------------------------------------------------------ */

export default function App() {
  const [openIndex, setOpenIndex] = useState<number | null>(null);

  const open = useCallback((shot: Shot) => {
    const i = allShots.findIndex((item) => item.src === shot.src);
    setOpenIndex(i >= 0 ? i : 0);
  }, []);

  const step = useCallback((delta: number) => {
    setOpenIndex((current) => {
      if (current === null) return current;
      return (current + delta + allShots.length) % allShots.length;
    });
  }, []);

  return (
    <LazyMotion features={domAnimation}>
      <Aurora />
      <Navbar />

      <main>
        <Hero />
        <Marquee />
        <Pillars />
        <Showcase onOpen={open} />
        <Features />
        <Flow />
        <Gallery onOpen={open} />
        <Comparison />
        <Download_ />
      </main>

      <Footer />

      <AnimatePresence>
        {openIndex !== null && (
          <Lightbox
            shot={allShots[openIndex]}
            onClose={() => setOpenIndex(null)}
            onStep={step}
          />
        )}
      </AnimatePresence>
    </LazyMotion>
  );
}
