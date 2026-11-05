import importlib.util
import os
import pathlib
import tempfile
import unittest

SCRIPT = pathlib.Path(__file__).resolve().parent.parent / "scripts" / "rewrite-koreader-paths.py"
spec = importlib.util.spec_from_file_location("rewrite", SCRIPT)
rw = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rw)

SYNC = '''return {
    ["books"] = {
        ["h1"] = {
            ["file"] = "/storage/emulated/0/Download/Wiek_kapitalizmu.epub",
        },
    },
    ["files"] = {
        ["/storage/emulated/0/Download/Wiek_kapitalizmu.epub"] = "h1",
        ["/storage/emulated/0/Downloads/other.epub"] = "h2",
        ["/storage/emulated/0/Download/Standalone/Bóg \\"techy\\".epub"] = "h3",
    },
    ["token"] = "/storage/emulated/0/Download-secret",
}
'''


def make(tmp, name="bookorbit_sync_state.lua", text=SYNC):
    path = pathlib.Path(tmp) / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
    return path


class MappingTests(unittest.TestCase):
    def test_prefix_is_path_aware(self):
        m = rw.parse_mappings([("/old", "/new")])
        self.assertEqual(rw.map_value("/old/a.epub", m), "/new/a.epub")
        self.assertEqual(rw.map_value("/old", m), "/new")
        self.assertIsNone(rw.map_value("/older/a.epub", m))

    def test_applied_once_longest_first(self):
        m = rw.parse_mappings([("/a", "/b"), ("/b", "/c")])
        self.assertEqual(rw.map_value("/a/x", m), "/b/x")
        self.assertEqual(rw.map_value("/b/x", m), "/c/x")

    def test_rejects_bad_mappings(self):
        for pair in [("", "/x"), ("/x", ""), ("x", "/y"), ("/", "/y"), ("/same", "/same")]:
            with self.assertRaises(rw.RewriteError):
                rw.parse_mappings([pair])

    def test_escaping_of_new_value(self):
        m = rw.parse_mappings([("/old", '/new"q\\x')])
        self.assertEqual(rw.map_value("/old/a", m), '/new\\"q\\\\x/a')

    def test_comment_lines_skipped(self):
        m = rw.parse_mappings([("/old", "/new")])
        text, changes = rw.rewrite_text('-- "/old/a"\nlocal x = "/old/b"', m)
        self.assertIn('-- "/old/a"', text)
        self.assertIn('"/new/b"', text)
        self.assertEqual(len(changes), 1)


class FileTests(unittest.TestCase):
    def run_main(self, tmp, *extra):
        return rw.main([tmp, "--map", "/storage/emulated/0/Download", "/storage/emulated/0/Books", *extra])

    def test_dry_run_changes_nothing(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = make(tmp)
            self.assertEqual(self.run_main(tmp), 0)
            self.assertEqual(path.read_text(encoding="utf-8"), SYNC)

    def test_apply_rewrites_and_backs_up(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = make(tmp)
            self.assertEqual(self.run_main(tmp, "--apply"), 0)
            new = path.read_text(encoding="utf-8")
            self.assertIn('"/storage/emulated/0/Books/Wiek_kapitalizmu.epub"', new)
            self.assertIn("/storage/emulated/0/Downloads/other.epub", new)  # sibling dir untouched
            self.assertIn("Download-secret", new)  # not a path-prefix match
            self.assertIn('Bóg \\"techy\\".epub', new)
            self.assertEqual(new.count("{"), SYNC.count("{"))
            backups = [p for p in pathlib.Path(tmp).iterdir() if p.name.startswith(".rewrite-backup")]
            self.assertEqual(len(backups), 1)
            self.assertEqual((backups[0] / "bookorbit_sync_state.lua").read_text(encoding="utf-8"), SYNC)

    def test_collision_aborts_without_writing(self):
        text = (
            'return {\n  ["/old/a.epub"] = "x",\n  ["/new/a.epub"] = "y",\n}\n'
        )
        with tempfile.TemporaryDirectory() as tmp:
            path = make(tmp, text=text)
            code = rw.main([tmp, "--map", "/old", "/new", "--apply"])
            self.assertEqual(code, 2)
            self.assertEqual(path.read_text(encoding="utf-8"), text)

    def test_non_allowlisted_and_old_files_untouched(self):
        with tempfile.TemporaryDirectory() as tmp:
            other = make(tmp, name="other.lua", text='return {["a"]="/old/x"}')
            old = make(tmp, name="bookorbit_sync_state.lua.old", text='return {["a"]="/old/x"}')
            self.assertEqual(rw.main([tmp, "--map", "/old", "/new", "--apply"]), 0)
            self.assertIn("/old/x", other.read_text(encoding="utf-8"))
            self.assertIn("/old/x", old.read_text(encoding="utf-8"))

    def test_sdr_metadata_included(self):
        with tempfile.TemporaryDirectory() as tmp:
            meta = make(tmp, name="Book.sdr/metadata.epub.lua", text='return {["doc_path"]="/old/Book.epub"}')
            self.assertEqual(rw.main([tmp, "--map", "/old", "/new", "--apply"]), 0)
            self.assertIn("/new/Book.epub", meta.read_text(encoding="utf-8"))

    def test_invalid_utf8_aborts_before_any_write(self):
        with tempfile.TemporaryDirectory() as tmp:
            good = make(tmp, name="history.lua", text='return {["file"]="/old/a"}')
            bad = pathlib.Path(tmp) / "settings.reader.lua"
            bad.write_bytes(b'return {"/old/\xff"}')
            self.assertEqual(rw.main([tmp, "--map", "/old", "/new", "--apply"]), 2)
            self.assertIn("/old/a", good.read_text(encoding="utf-8"))

    def test_symlink_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            real = make(tmp, name="real.txt", text="x")
            os.symlink(real, pathlib.Path(tmp) / "history.lua")
            self.assertEqual(rw.main([tmp, "--map", "/old", "/new"]), 2)

    def test_missing_workdir(self):
        self.assertEqual(rw.main(["/nonexistent-dir-xyz", "--map", "/a", "/b"]), 2)


if __name__ == "__main__":
    unittest.main()
