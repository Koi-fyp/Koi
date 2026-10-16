"""Print the first https://...modal.run URL found in a file (e.g. `modal deploy` output). Exit 1 if none."""
import re
import sys

text = open(sys.argv[1], encoding="utf-8", errors="replace").read()
m = re.search(r"https://[A-Za-z0-9._-]+\.modal\.run", text)
if not m:
    sys.exit(1)
print(m.group(0).rstrip("/"))
