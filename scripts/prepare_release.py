import re
import sys
from pathlib import Path

path = Path("README.md")
content, count = re.subn(
    r'(ShortcutField", from: ")[0-9]+\.[0-9]+\.[0-9]+',
    lambda match: match[1] + sys.argv[1],
    path.read_text(),
)
if not count:
    raise SystemExit("Could not update the ShortcutField installation version in README.md.")
path.write_text(content)
