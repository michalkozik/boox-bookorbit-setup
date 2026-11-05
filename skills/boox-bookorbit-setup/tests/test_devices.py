import importlib.util
import pathlib
import unittest

SCRIPT = pathlib.Path(__file__).resolve().parent.parent / "scripts" / "check-devices.py"
spec = importlib.util.spec_from_file_location("check_devices", SCRIPT)
cd = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cd)

HEADER = "| " + " | ".join(cd.COLUMNS) + " |\n|" + "---|" * len(cd.COLUMNS) + "\n"


def doc(row):
    return HEADER + row + "\n"


GOOD = "| Boox X | 11 | arm64-v8a | monochrome | 1.0 | verified | Settings, About, tap Version 7 times | worked | ok |"


class DeviceTableTests(unittest.TestCase):
    def test_repo_file_is_valid(self):
        path = SCRIPT.parent.parent / "references" / "devices.md"
        self.assertEqual(cd.check(path.read_text(encoding="utf-8")), [])

    def test_good_row(self):
        self.assertEqual(cd.check(doc(GOOD)), [])

    def test_wrong_header(self):
        self.assertTrue(cd.check("| a | b |\n|---|---|\n| 1 | 2 |"))

    def test_bad_status_and_android(self):
        bad = GOOD.replace("verified", "great").replace("| 11 |", "| eleven |")
        self.assertEqual(len(cd.check(doc(bad))), 2)

    def test_verified_needs_path_and_launcher(self):
        bad = GOOD.replace("Settings, About, tap Version 7 times", "").replace("worked", "untested")
        self.assertEqual(len(cd.check(doc(bad))), 2)

    def test_sensitive_data_rejected(self):
        for leak in ["mail me a@b.example", "00:1a:2b:3c:4d:5e", "https://books.example.com", "192.168.1.5"]:
            self.assertTrue(cd.check(doc(GOOD.replace("| ok |", "| %s |" % leak))), leak)


if __name__ == "__main__":
    unittest.main()
