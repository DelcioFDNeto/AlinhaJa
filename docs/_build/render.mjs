import path from 'path';

// Renderiza capa.html e corpo.html (gerados pelo build_pdf.py) em PDF.
// Uso: node render.mjs <diretorio> "<texto do rodapé>"
const pw = process.env.PLAYWRIGHT_PATH || 'playwright';
const { chromium } = await import(pw);

const [dir, rodape] = process.argv.slice(2);

// Templates de cabeçalho/rodapé do Chromium não herdam o charset da página:
// caracteres acentuados vão como entidades numéricas.
const entidades = (s) => s.replace(/[^\x00-\x7F]/g, (c) => `&#${c.codePointAt(0)};`)
  .replace(/</g, '&lt;');
const marca = entidades(rodape).replace(
  'AlinhaJ&#225;',
  'Alinha<span style="color:#D21A18;font-weight:bold;">J&#225;</span>');

const footerTemplate = `
<div style="width:100%; font-size:7.5px; color:#9AA2AF; padding:0 16mm;
            display:flex; justify-content:space-between; font-family:Arial, sans-serif;">
  <span style="letter-spacing:.4px;">${marca}</span>
  <span>P&#225;gina <span class="pageNumber"></span> de <span class="totalPages"></span></span>
</div>`;

const browser = await chromium.launch();
const page = await browser.newPage();

await page.goto('file://' + path.join(dir, 'capa.html'), { waitUntil: 'networkidle' });
await page.pdf({
  path: path.join(dir, 'capa.pdf'),
  format: 'A4', printBackground: true,
  margin: { top: '0', bottom: '0', left: '0', right: '0' },
});

await page.goto('file://' + path.join(dir, 'corpo.html'), { waitUntil: 'networkidle' });
await page.pdf({
  path: path.join(dir, 'corpo.pdf'),
  format: 'A4', printBackground: true,
  displayHeaderFooter: true,
  headerTemplate: '<span></span>',
  footerTemplate,
  margin: { top: '14mm', bottom: '16mm', left: '15mm', right: '15mm' },
});

await browser.close();
