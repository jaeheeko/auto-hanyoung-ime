"""docs/demo_template.html + docs/hanyoung.js → docs/index.html (한 파일). GitHub Pages와 buzz-html 양쪽에 그대로 쓴다."""
import os
ROOT = os.path.join(os.path.dirname(__file__), "..", "docs")
tpl = open(os.path.join(ROOT, "demo_template.html"), encoding="utf-8").read()
js = open(os.path.join(ROOT, "hanyoung.js"), encoding="utf-8").read()
assert "/*__HANYOUNG_JS__*/" in tpl
out = tpl.replace("/*__HANYOUNG_JS__*/", js)
with open(os.path.join(ROOT, "index.html"), "w", encoding="utf-8") as f:
    f.write(out)
print(f"docs/index.html: {len(out.encode()) / 1e3:.0f} KB")
