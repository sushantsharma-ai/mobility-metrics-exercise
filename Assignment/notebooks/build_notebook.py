"""Builds analysis.ipynb, which just runs the two SQL files in sql/ against
the data package and shows what each query returns. The actual write-up of
what these results mean is in ../INVESTIGATION.md. Run with:
  python notebooks/build_notebook.py
  jupyter nbconvert --to notebook --execute --inplace notebooks/analysis.ipynb
  jupyter nbconvert --to html notebooks/analysis.ipynb
"""
import nbformat as nbf

nb = nbf.v4.new_notebook()
cells = []

def md(src):
    cells.append(nbf.v4.new_markdown_cell(src))

def code(src):
    cells.append(nbf.v4.new_code_cell(src))

md(r"""
# Validation run

This runs sql/01_cleaning_and_checks.sql and sql/02_analysis.sql against
the data package and shows what each query returns. The write-up of what
these results mean, and the reasoning behind each step, is in
../INVESTIGATION.md.
""")

code(r"""
import duckdb
from pathlib import Path

_cwd = Path('.').resolve()
ROOT = _cwd if (_cwd / 'sql').exists() else _cwd.parent

con = duckdb.connect(':memory:')

def run_file(path):
    sql_text = (ROOT / 'sql' / path).read_text().replace("'data/", f"'{ROOT}/data/")
    stmts = [s.strip() for s in '\n'.join(
        l for l in sql_text.splitlines() if not l.strip().startswith('--')
    ).split(';') if s.strip()]
    return [con.execute(s).df() for s in stmts]
""")

md("## sql/01_cleaning_and_checks.sql")

code(r"""
cleaning_results = run_file('01_cleaning_and_checks.sql')
for df in cleaning_results:
    if not df.empty:
        print(df.to_string(index=False))
        print()
""")

md("## sql/02_analysis.sql")

code(r"""
analysis_results = run_file('02_analysis.sql')
for df in analysis_results:
    if not df.empty:
        print(df.to_string(index=False))
        print()
""")

nb['cells'] = cells
nb['metadata'] = {
    'kernelspec': {'display_name': 'mobility-exercise', 'language': 'python', 'name': 'mobility-exercise'},
    'language_info': {'name': 'python'},
}

import pathlib
out_path = pathlib.Path(__file__).parent / 'analysis.ipynb'
with open(out_path, 'w') as f:
    nbf.write(nb, f)
print(f"Wrote {out_path}")
