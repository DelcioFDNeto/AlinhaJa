#!/usr/bin/env python3
"""Gera PDF com a identidade visual AlinhaJá a partir de um markdown de docs/.

O markdown é a fonte única: capa, sumário, faixas de seção, listas, tabelas,
formulários e perguntas frequentes são derivados dele. Não editar o PDF à mão.

Uso:
    python build_pdf.py ENTRADA.md SAIDA.pdf --title "..." --subtitle "..." \
        --chips "A,B,C" --edition "..." --footer "..." [--no-toc]

Convenções do markdown:
    # TÍTULO DO DOCUMENTO          primeira linha — substituída pela capa
    **subtítulo**                  linha seguinte — substituída pela capa
    # PARTE N — NOME               faixa de seção com "Parte N" e quebra de página
    # NOME                         faixa de seção sem numeração
    (parágrafo após a faixa)       vira o subtítulo da faixa e a descrição no sumário
    ## Seção / ### Subseção        títulos internos
    > texto                        caixa de observação
    **Pergunta?**\\nResposta       caixa de pergunta frequente
    | # | Pergunta | Resposta |    tabela de formulário (coluna "Resposta" vira campo)
    ( )                            caixa de marcação

Dependências: markdown, beautifulsoup4, pypdf (pip) e playwright (node).
O caminho do playwright pode ser informado em PLAYWRIGHT_PATH.
"""
import argparse
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

import markdown
from bs4 import BeautifulSoup
from pypdf import PdfReader, PdfWriter

AQUI = Path(__file__).resolve().parent
RAIZ = AQUI.parent.parent
LOGO = RAIZ / "assets" / "images" / "logo.png"

PEQUENAS = {"a", "o", "as", "os", "e", "da", "de", "do", "das", "dos", "em",
            "na", "no", "nas", "nos", "para", "com", "por", "à", "ao"}
SIGLAS = {"RH", "TI", "LGPD", "GPS", "SLA", "IA", "VM", "TLS", "SMTP", "DPO",
          "RBAC", "SSH", "API"}


def titulo_pt(texto: str) -> str:
    """Converte CAIXA ALTA em título, mantendo siglas e preposições."""
    saida = []
    for i, palavra in enumerate(texto.split()):
        nucleo = palavra.strip("—-:,.()")
        if nucleo.upper() in SIGLAS:
            saida.append(palavra.upper())
        elif i > 0 and palavra.lower() in PEQUENAS:
            saida.append(palavra.lower())
        else:
            minus = palavra.lower()
            saida.append(minus[:1].upper() + minus[1:])
    return " ".join(saida)


def remover_cabecalho(md: str) -> str:
    """Remove título, subtítulo e o primeiro separador — a capa os substitui."""
    linhas = md.splitlines()
    i = 0
    while i < len(linhas) and not linhas[i].startswith("# "):
        i += 1
    i += 1  # título

    def eh_cabecalho(linha: str) -> bool:
        s = linha.strip()
        return s in ("", "---") or (s.startswith("**") and s.endswith("**"))

    while i < len(linhas) and eh_cabecalho(linhas[i]):
        i += 1
    return "\n".join(linhas[i:])


def agrupar_opcoes(sopa, celula):
    """Prende cada caixa de marcação ao seu rótulo, para não quebrar entre eles."""
    novos, atual = [], None
    for no in list(celula.contents):
        eh_caixa = getattr(no, "name", None) == "span" and "sq" in (no.get("class") or [])
        if eh_caixa:
            atual = sopa.new_tag("span", attrs={"class": "opt"})
            novos.append(atual)
            atual.append(no.extract())
        elif atual is not None:
            atual.append(no.extract())
        else:
            novos.append(no.extract())
    celula.clear()
    for no in novos:
        celula.append(no)


def classe_celula(texto: str):
    return {"Sim": "yes", "Não": "no", "Config.": "cfg"}.get(texto.strip())


def converter(md: str, com_sumario: bool, titulo_doc: str) -> str:
    md = remover_cabecalho(md)
    html = markdown.markdown(md, extensions=["tables", "sane_lists"])
    html = html.replace("( )", '<span class="sq"></span>')
    # "Rótulo: {campo}" fica junto na mesma linha; {campo} solto vira só a linha
    html = re.sub(r"([^\s<>]+:)\s*\{campo\}",
                  r'<span class="pair">\1 <span class="fill"></span></span>', html)
    html = html.replace("{campo}", '<span class="fill"></span>')
    sopa = BeautifulSoup(html, "html.parser")

    for hr in sopa.find_all("hr"):
        hr.decompose()

    # Faixas de seção (h1) e sumário
    partes = []
    for h1 in sopa.find_all("h1"):
        texto = h1.get_text(strip=True)
        m = re.match(r"^PARTE\s+(\d+)\s*[—-]\s*(.+)$", texto)
        kicker, nome = (f"Parte {m.group(1)}", titulo_pt(m.group(2))) if m \
            else (None, titulo_pt(texto))
        sub = h1.find_next_sibling()
        sub_txt = ""
        if sub is not None and sub.name == "p":
            sub_txt = sub.decode_contents()
            sub.decompose()
        faixa = sopa.new_tag("div", attrs={"class": "part-banner"})
        if kicker:
            k = sopa.new_tag("div", attrs={"class": "kicker"})
            k.string = kicker
            faixa.append(k)
        t = sopa.new_tag("h2")
        t.string = nome
        faixa.append(t)
        if sub_txt:
            s = sopa.new_tag("p", attrs={"class": "sub"})
            s.append(BeautifulSoup(sub_txt, "html.parser"))
            faixa.append(s)
        h1.replace_with(faixa)
        partes.append((nome, sub_txt))

    for h2 in sopa.find_all("h2"):
        if h2.find_parent(class_="part-banner"):
            continue
        h2.name = "h3"
        h2["class"] = "sec"
    for h3 in sopa.find_all("h3"):
        if "sec" in (h3.get("class") or []):
            continue
        h3.name = "h4"
        h3["class"] = "sub"

    # Pilares: lista logo após um subtítulo que contém "Pilares"
    for h4 in sopa.find_all("h4", class_="sub"):
        if "Pilares" not in h4.get_text():
            continue
        lista = h4.find_next_sibling("ul")
        if not lista:
            continue
        grade = sopa.new_tag("div", attrs={"class": "pillars"})
        for li in lista.find_all("li", recursive=False):
            forte = li.find("strong")
            nome = forte.get_text(strip=True).rstrip(":") if forte else ""
            if forte:
                forte.decompose()
            card = sopa.new_tag("div", attrs={"class": "pillar"})
            h5 = sopa.new_tag("h5")
            h5.string = nome
            p = sopa.new_tag("p")
            corpo = li.decode_contents().strip()
            # sem o rótulo "Nome:", o texto começa em minúscula — capitaliza
            corpo = corpo[:1].upper() + corpo[1:]
            p.append(BeautifulSoup(corpo, "html.parser"))
            card.extend([h5, p])
            grade.append(card)
        lista.replace_with(grade)

    for ul in sopa.find_all("ul"):
        ul["class"] = "feat"

    for bq in sopa.find_all("blockquote"):
        bq.name = "div"
        bq["class"] = "note"

    # Perguntas frequentes: parágrafo iniciado por negrito terminado em "?"
    for p in sopa.find_all("p"):
        primeiro = next((c for c in p.children
                         if not (isinstance(c, str) and not c.strip())), None)
        if getattr(primeiro, "name", None) != "strong":
            continue
        pergunta = primeiro.get_text(strip=True)
        if not pergunta.endswith("?"):
            continue
        primeiro.extract()
        caixa = sopa.new_tag("div", attrs={"class": "faq"})
        q = sopa.new_tag("div", attrs={"class": "q"})
        q.string = pergunta
        a = sopa.new_tag("div", attrs={"class": "a"})
        a.append(BeautifulSoup(p.decode_contents().strip(), "html.parser"))
        caixa.extend([q, a])
        p.replace_with(caixa)

    # Tabelas
    for tabela in sopa.find_all("table"):
        cab = [th.get_text(strip=True) for th in tabela.find_all("th")]
        if "Resposta" in cab:
            tabela["class"] = "form"
            idx = cab.index("Resposta")
            for tr in tabela.find("tbody").find_all("tr"):
                tds = tr.find_all("td")
                if len(tds) > idx:
                    tds[idx]["class"] = "ans"
                    agrupar_opcoes(sopa, tds[idx])
        elif cab and cab[0] == "Área":
            tabela["class"] = "mods"
        for td in tabela.find_all("td"):
            c = classe_celula(td.get_text())
            if c:
                td["class"] = c

    # Rodapé do documento (último parágrafo em itálico)
    paragrafos = sopa.find_all("p")
    if paragrafos and paragrafos[-1].find("em") and \
            paragrafos[-1].get_text(strip=True) == paragrafos[-1].em.get_text(strip=True):
        paragrafos[-1]["class"] = "closing"

    # Primeira faixa sem quebra de página (cabeçalho do documento vem antes)
    faixas = sopa.find_all(class_="part-banner")
    for i, f in enumerate(faixas):
        f["class"] = ["part-banner"] + (["break"] if (i > 0 or com_sumario) else [])

    cabecalho = (
        f'<div class="doc-header"><img src="{LOGO.as_uri()}" alt="AlinhaJá">'
        f'<div><div class="t1">Plataforma AlinhaJá</div>'
        f'<div class="t2">{titulo_doc}</div></div></div><div class="rule"></div>'
    )
    sumario = ""
    if com_sumario:
        itens = "".join(
            f'<div class="toc-item"><div class="toc-num">{i}</div><div>'
            f'<h4>{nome}</h4><p>{desc}</p></div></div>'
            for i, (nome, desc) in enumerate(partes, start=1))
        sumario = f'<div class="toc-title">Sumário</div>{itens}'

    css = (AQUI / "estilo.css").read_text(encoding="utf-8")
    return (f'<meta charset="utf-8"><style>{css}</style>'
            f'<div class="opening">{cabecalho}{sumario}</div>{sopa}')


def capa(args) -> str:
    chips = "".join(f'<span class="chip">{c.strip()}</span>'
                    for c in args.chips.split(",") if c.strip())
    tpl = (AQUI / "capa.html").read_text(encoding="utf-8")
    return (tpl.replace("{{LOGO}}", LOGO.as_uri())
               .replace("{{TITULO}}", args.title)
               .replace("{{SUBTITULO}}", args.subtitle)
               .replace("{{CHIPS}}", chips)
               .replace("{{EDICAO}}", args.edition))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("entrada")
    ap.add_argument("saida")
    ap.add_argument("--title", required=True, help="título da capa (aceita <br>)")
    ap.add_argument("--subtitle", required=True)
    ap.add_argument("--chips", default="")
    ap.add_argument("--edition", required=True)
    ap.add_argument("--footer", required=True, help="texto do rodapé das páginas")
    ap.add_argument("--no-toc", action="store_true")
    args = ap.parse_args()

    md = Path(args.entrada).read_text(encoding="utf-8")
    titulo_doc = re.sub(r"<br\s*/?>", " ", args.title)

    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        (tmp / "capa.html").write_text(capa(args), encoding="utf-8")
        (tmp / "corpo.html").write_text(
            converter(md, not args.no_toc, titulo_doc), encoding="utf-8")
        subprocess.run(
            ["node", str(AQUI / "render.mjs"), str(tmp), args.footer],
            check=True, env={**os.environ})
        escritor = PdfWriter()
        for nome in ("capa.pdf", "corpo.pdf"):
            for pagina in PdfReader(tmp / nome).pages:
                escritor.add_page(pagina)
        escritor.add_metadata({"/Title": f"AlinhaJá — {titulo_doc}",
                               "/Author": "AlinhaJá"})
        with open(args.saida, "wb") as f:
            escritor.write(f)
    total = len(PdfReader(args.saida).pages)
    print(f"{args.saida}: {total} páginas")


if __name__ == "__main__":
    sys.exit(main())
