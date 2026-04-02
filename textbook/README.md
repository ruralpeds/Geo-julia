# Geographic Analysis in Julia — Interactive Textbook

A Quarto-based interactive textbook built from the four-volume series in `../textbooks/2026-03-30/`.

## Rendering

Install [Quarto](https://quarto.org/docs/get-started/) (v1.4+), then:

```bash
cd textbook/
quarto preview   # live preview at localhost:4567
quarto render    # build static site to _book/
```

## Structure

```
textbook/
├── _quarto.yml          # Book configuration
├── index.qmd            # Landing page
├── assets/
│   └── custom.css       # Julia-themed styles
├── vol1/                # Chapters 1–10: Foundations
├── vol2/                # Chapters 11–15: Gap Analysis
├── vol3/                # Chapters 16–25: Package Engineering
├── vol4/                # Chapters 26–34: Advanced Methods
└── appendices/          # Appendices A–D and References
```

## Source

Generated from `textbooks/2026-03-30/` docx files using `scripts/build_textbook.py`.

Code blocks use `eval: false` by default — the book renders without a running Julia kernel.
To execute code interactively, use the Pluto notebooks in `HealthcareGeo/notebooks/`.
