"""Inline the localized catalogues (en, ur, ur-roman) into breathing_template.html -> breathing_reference.html.
    python build_reference.py"""
import json
from pathlib import Path

import catalogue as C

HERE = Path(__file__).resolve().parent
cat, i18n = C.load(), C.load_i18n()
problems = C.validate(cat) + C.validate_i18n(cat, i18n)
if problems:
    raise SystemExit("catalogue problems:\n" + "\n".join(problems))
cats = {lang: C.localize(cat, i18n, lang) for lang in C.LANGS}
blob = json.dumps(cats, ensure_ascii=False).replace("</", "<\\/")
html = (HERE / "breathing_template.html").read_text(encoding="utf-8").replace("/*EXERCISES_JSON*/", blob)
(HERE / "breathing_reference.html").write_text(html, encoding="utf-8")
print("wrote breathing_reference.html (en, ur, ur-roman)")
