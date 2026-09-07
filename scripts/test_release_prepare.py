import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


class PreparationTests(unittest.TestCase):
    def test_updates_the_installation_example(self):
        root = Path(__file__).resolve().parent.parent
        original = (root / "README.md").read_text()
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "README.md"
            path.write_text(original)
            subprocess.run(
                [sys.executable, str(root / "scripts/prepare_release.py"), "9.8.7"],
                cwd=temporary,
                check=True,
            )
            updated = path.read_text()
            self.assertIn('ShortcutField", from: "9.8.7"', updated)
            old_version = re.search(r'ShortcutField", from: "([^"]+)"', original)[1]
            self.assertEqual(updated.replace('from: "9.8.7"', f'from: "{old_version}"'), original)


if __name__ == "__main__":
    unittest.main()
