#!/usr/bin/env python3
"""
build_textbook.py — Convert docx volumes to Quarto interactive textbook.

Usage:
    pip install python-docx
    python3 textbooks/scripts/build_textbook.py

Output: textbook/ directory with _quarto.yml and chapter .qmd files.
Render: cd textbook && quarto preview
"""

import json, re, os
from docx import Document

DOCX_DIR  = os.path.join(os.path.dirname(__file__), "..", "2026-03-30")
OUT_DIR   = os.path.join(os.path.dirname(__file__), "..", "..", "textbook")

FNAMES = {
    1: "Vol1_GeoAnalysis_Julia_Healthcare_Textbook.docx",
    2: "Vol2_GapAnalysis_OpenPopulationData.docx",
    3: "Vol3_PackageEngineering_BuildingTheEcosystem.docx",
    4: "Vol4_AdvancedMethods_RealData_Deployment.docx",
}

VOL_TITLES = {
    1: "Geographic Analysis in Julia: Healthcare and Rural Populations",
    2: "Gap Analysis and Open Population Data",
    3: "Package Engineering: Building the Missing Ecosystem",
    4: "Advanced Methods, Real Data, and Deployment",
}

# Chapter definitions: (vol, start_para, end_para, relpath, title, ch_num_or_None)
CHAPTERS = [
    (1, 28,  62,   'vol1/ch01.qmd', 'Foundations of Geographic Analysis in Healthcare', 1),
    (1, 62,  153,  'vol1/ch02.qmd', 'The Julia Language for Geospatial Science', 2),
    (1, 153, 318,  'vol1/ch03.qmd', 'The JuliaGeo Ecosystem: Packages and Architecture', 3),
    (1, 318, 476,  'vol1/ch04.qmd', 'Spatial Statistics for Population Health', 4),
    (1, 476, 548,  'vol1/ch05.qmd', 'Defining and Studying Rural Populations', 5),
    (1, 548, 572,  'vol1/ch06.qmd', 'State of the Art: Rural Health Geographic Analysis', 6),
    (1, 572, 690,  'vol1/ch07.qmd', 'Authoritative Data Sources for Rural Health GIS', 7),
    (1, 690, 850,  'vol1/ch08.qmd', 'Complete Julia Programming Guide for Healthcare GIS', 8),
    (1, 850, 937,  'vol1/ch09.qmd', 'Visualization, Cartography, and Dashboard Design in Julia', 9),
    (1, 937, 1236, 'vol1/ch10.qmd', 'Claude Code Specifications for the Geo Analysis System', 10),
    (1, 1236,1303, 'appendices/appA-C.qmd', 'Appendices A–C: Package Reference, Data Dictionary, Glossary', None),
    (2, 11,  309,  'vol2/ch11.qmd', "Deep Gap Analysis — What Julia's Geospatial Ecosystem Lacks", 11),
    (2, 309, 375,  'vol2/ch12.qmd', 'Bayesian Disease Mapping and CAR Models in Julia', 12),
    (2, 375, 641,  'vol2/ch13.qmd', 'Open-Source Population Data — A Complete Directory', 13),
    (2, 641, 853,  'vol2/ch14.qmd', 'Building the Missing Packages — A Community Roadmap', 14),
    (2, 853, 974,  'vol2/ch15.qmd', 'Full Integration Pipeline — Production Healthcare GIS', 15),
    (2, 974, 988,  'appendices/appD.qmd', 'Appendix D + Closing: Open Data Sources and Future Directions', None),
    (3, 11,  368,  'vol3/ch16.qmd', 'Julia Package Engineering Fundamentals', 16),
    (3, 368, 561,  'vol3/ch17.qmd', 'Building Spatial Weights — The Foundation of Every Spatial Analysis', 17),
    (3, 561, 772,  'vol3/ch18.qmd', "Full Implementation — Moran's I, LISA, and Getis-Ord G*", 18),
    (3, 772, 1030, 'vol3/ch19.qmd', 'Building Geocode.jl — Address Matching for Healthcare GIS', 19),
    (3, 1030,1227, 'vol3/ch20.qmd', 'Building SpatialReg.jl — Spatial Econometrics for Julia', 20),
    (3, 1227,1523, 'vol3/ch21.qmd', 'Testing, Documentation, CI/CD, and General Registry Submission', 21),
    (3, 1523,1941, 'vol3/ch22.qmd', 'Claude Code Programs — Complete Build Specifications', 22),
    (3, 1941,2149, 'vol3/ch23.qmd', 'Bridging Julia to Python and R — Production Interoperability', 23),
    (3, 2149,2266, 'vol3/ch24.qmd', 'Performance Engineering for Large-Scale Spatial Analysis', 24),
    (3, 2266,2348, 'vol3/ch25.qmd', 'Launch Sequence — From Zero to Registered Package', 25),
    (4, 10,  340,  'vol4/ch26.qmd', "Building PointPatterns.jl — Spatial Epidemiology's Missing Tool", 26),
    (4, 340, 516,  'vol4/ch27.qmd', 'Spatial Generalised Linear Models — Disease Counts and Proportions', 27),
    (4, 516, 719,  'vol4/ch28.qmd', 'Bivariate and Advanced Cartography in Julia', 28),
    (4, 719, 1015, 'vol4/ch29.qmd', 'A Complete Real-Data Healthcare Access Analysis Pipeline', 29),
    (4, 1015,1097, 'vol4/ch30.qmd', 'Interactive Dashboards with Pluto.jl', 30),
    (4, 1097,1229, 'vol4/ch31.qmd', 'Deploying Spatial Analysis as a Web Service with Genie.jl', 31),
    (4, 1229,1363, 'vol4/ch32.qmd', 'Contributing to Existing JuliaGeo Packages', 32),
    (4, 1363,1488, 'vol4/ch33.qmd', 'GPU Acceleration with CUDA.jl and Metal.jl', 33),
    (4, 1488,1604, 'vol4/ch34.qmd', 'The Complete Ecosystem Build — Master Claude Code Program', 34),
]

# ── Code detection patterns ────────────────────────────────────────────────────

CODE_START = re.compile(
    r'^('
    r'# ===|# ──|# ---'
    r'|# '                              # any code comment
    r'|using |import '
    r'|module [A-Z]'
    r'|function [a-z_!]|function \('
    r'|macro \w'
    r'|struct [A-Z]|mutable struct |abstract type '
    r'|@test|@btime|@time|@benchmark'
    r'|@\w+\s*[\(\[]'
    r'|julia>|\(\w[\w_]*\) pkg>'
    r'|\$ |curl |winget |juliaup |docker '
    r'|pip install|pip3'
    r'|```'
    r')'
)

CODE_SIGNAL = re.compile(
    r'(::[A-Za-z]|->|\) where \{|\) where\{)'
)


def is_clearly_prose(text: str) -> bool:
    t = text.strip()
    if len(t) < 45:
        return False
    words = t.split()
    if len(words) < 8:
        return False
    if not t[0].isupper():
        return False
    if t[-1] not in '.,:;)':
        return False
    if CODE_SIGNAL.search(t):
        return False
    english = {'the','a','an','is','are','was','were','of','for','in','to',
               'and','or','but','with','from','this','that','which','when',
               'where','its','their','these','those','also','can','will',
               'be','by','at','on','as','it','not','have','has'}
    word_set = set(w.lower().rstrip('.,;:()') for w in words)
    return len(word_set & english) >= 2


def emit_code_block(code_buf: list) -> list:
    """Return QMD lines for a fenced julia code block."""
    buf = list(code_buf)
    while buf and not buf[-1].strip():
        buf.pop()
    if not buf:
        return []
    cleaned = []
    for line in buf:
        s = line.strip()
        if s.startswith('```'):
            lang = s[3:].strip()
            cleaned.append(f'# (example: {lang})' if lang else '# (end example)')
        else:
            cleaned.append(line.rstrip())
    return ['```julia'] + cleaned + ['```', '']


def extract_docx(path: str) -> list:
    doc = Document(path)
    result = []
    for p in doc.paragraphs:
        text = p.text.rstrip()
        try:
            style = p.style.name if p.style else ''
        except Exception:
            style = ''
        result.append({"text": text, "style": style})
    return result


def paras_to_qmd(paras: list, ch_num_or_none, title: str, vol_num: int) -> str:
    lines = ['---']
    if ch_num_or_none:
        lines.append(f'title: "Chapter {ch_num_or_none}: {title}"')
    else:
        lines.append(f'title: "{title}"')
    lines.append(f'subtitle: "Volume {vol_num} — {VOL_TITLES[vol_num]}"')
    lines.append('---')
    lines.append('')

    IN_CODE = False
    code_buf: list = []
    blank_run = 0

    def flush_code():
        nonlocal IN_CODE, code_buf, blank_run
        lines.extend(emit_code_block(code_buf))
        IN_CODE = False
        code_buf = []
        blank_run = 0

    SKIP_PREFIXES = ('Chapter ', 'Appendix ', 'References', 'Closing', 'Table of')
    HEADING_LEVEL = {'Heading 1': '#', 'Heading 2': '##', 'Heading 3': '###'}

    for p in paras:
        text  = p['text']
        style = p['style']
        stripped = text.strip()

        if style in HEADING_LEVEL:
            if IN_CODE:
                flush_code()
            if style == 'Heading 1' and any(stripped.startswith(s) for s in SKIP_PREFIXES):
                continue
            lines.append(f'\n{HEADING_LEVEL[style]} {stripped}\n')
            blank_run = 0
            continue

        if not stripped:
            if IN_CODE:
                blank_run += 1
                if blank_run <= 3:
                    code_buf.append('')
            else:
                blank_run += 1
            continue

        blank_run = 0

        if IN_CODE:
            if is_clearly_prose(stripped) and len(code_buf) >= 2:
                flush_code()
                lines.append(stripped)
                lines.append('')
            else:
                code_buf.append(text.rstrip())
        else:
            if CODE_START.match(stripped) or CODE_SIGNAL.search(stripped):
                IN_CODE = True
                code_buf = [text.rstrip()]
            else:
                lines.append(stripped)
                lines.append('')

    if IN_CODE:
        flush_code()

    return '\n'.join(lines)


def main():
    print("Loading docx files...")
    vols = {}
    for v, fname in FNAMES.items():
        path = os.path.join(DOCX_DIR, fname)
        vols[v] = extract_docx(path)
        print(f"  Vol {v}: {len(vols[v])} paragraphs")

    print(f"\nGenerating QMD files to {OUT_DIR}/")
    created = 0
    for vol, start, end, relpath, title, ch_num in CHAPTERS:
        paras   = vols[vol][start:end]
        outpath = os.path.join(OUT_DIR, relpath)
        os.makedirs(os.path.dirname(outpath), exist_ok=True)
        content = paras_to_qmd(paras, ch_num, title, vol)
        with open(outpath, 'w') as f:
            f.write(content)
        n_blocks = content.count('```julia')
        print(f"  {relpath}  ({n_blocks} code blocks)")
        created += 1

    print(f"\nDone — {created} files created.")
    print("Render with:  cd textbook && quarto preview")


if __name__ == '__main__':
    main()
