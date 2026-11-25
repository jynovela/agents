"""Unit test for itemctl --version."""

import io
import unittest
from contextlib import redirect_stdout

import app


class VersionTest(unittest.TestCase):
    def test_version_matches_package_version(self):
        out = io.StringIO()
        with redirect_stdout(out), self.assertRaises(SystemExit):
            app.main(["--version"])
        self.assertEqual(out.getvalue().strip(), f"itemctl {app.__version__}")


if __name__ == "__main__":
    unittest.main()
