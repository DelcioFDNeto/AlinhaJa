import { StrictMode, Suspense, lazy } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import App from './App'
import { matchLegalRoute } from './legal-routes'

// Roteamento mínimo por pathname: o Firebase Hosting já reescreve tudo para
// index.html, então basta olhar a URL na entrada. Não vale trazer um router
// inteiro para um punhado de rotas estáticas.
//
// A página legal entra por import dinâmico para que o renderizador de Markdown
// e o texto dos documentos não pesem no bundle de quem só abre a home.
const legalSlug = matchLegalRoute(window.location.pathname)
const LegalPage = lazy(() => import('./legal'))

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    {legalSlug ? (
      <Suspense fallback={null}>
        <LegalPage initialSlug={legalSlug} />
      </Suspense>
    ) : (
      <App />
    )}
  </StrictMode>,
)
