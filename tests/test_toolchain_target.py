"""Keep runtime admission, public CI and private export on one verified target."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
VERSION = "4.7.2.stable.official.ed1daf0bf"
COMMIT = "ed1daf0bf001b61586d9930840f2f1394092c079"
EDITOR_SHA = "cadd3204e728a35d3f13adb7fd0d7902636b79f6b95c40c265eb73b6c35329e4"
TEMPLATE_SHA = "f298490b8d44d934be425a5a65a51bf15f422428b229a06a6e11d9ffea248011"

class ToolchainTargetTests(unittest.TestCase):
    def read(self, name):
        return (ROOT / name).read_text()

    def test_public_exact_engine_and_official_digest(self):
        self.assertIn('"' + VERSION + '"', self.read("tools/test_public_ci.sh"))
        workflow = self.read(".github/workflows/public-checks.yml")
        self.assertIn("Godot_v4.7.2-stable_linux.x86_64.zip", workflow)
        self.assertIn(EDITOR_SHA, workflow)
        self.assertIn("godotengine/godot/releases/download/4.7.2-stable/", workflow)
        self.assertNotIn("4.6.3", workflow)

    def test_private_export_exact_editor_template_and_member(self):
        text = self.read("tools/export_linux.py")
        for value in [VERSION, 'TEMPLATE_VERSION = "4.7.2.stable"', TEMPLATE_SHA,
                      'TEMPLATE_SIZE = 73519416', 'TEMPLATE_MEMBER = "templates/linux_release.x86_64"']:
            self.assertIn(value, text)
        self.assertNotIn("4.6.3", text)

    def test_runtime_only_admits_verified_engine_without_weakening_context(self):
        text = self.read("scripts/ui/source_flat_board_lighting.gd")
        self.assertIn('version.major != 4 or version.minor != 7 or version.patch != 2', text)
        self.assertIn(COMMIT, text)
        self.assertNotIn("7d41c59c", text)
        self.assertIn('RenderingServer.get_current_rendering_method() != "gl_compatibility"', text)
        self.assertIn('lights.size() != 1', text)
        self.assertIn('material.get_meta("source_board_cull", "") == "back"', text)
        self.assertIn('camera_attributes != null', text)

    def test_active_run_docs_verify_the_same_official_target(self):
        names = ["README.md", "docs/board-ui.md", "docs/private-validation.md",
                 "docs/runtime-core.md", "docs/navigation-input.md"]
        for name in names:
            with self.subTest(document=name):
                text = self.read(name)
                self.assertIn("export GODOT=/absolute/path/to/Godot_v4.7.2-stable_linux.x86_64", text)
                self.assertIn('test "$("$GODOT" --version)" = "' + VERSION + '" || exit 1', text)
        self.assertNotIn("Godot 4.6", self.read("README.md"))
        self.assertNotIn("Godot 4.6", self.read("docs/board-ui.md"))
        self.assertNotIn("Use Godot 4.6", self.read("docs/private-validation.md"))
        self.assertNotIn("Run with Godot 4.6", self.read("docs/runtime-core.md"))
        navigation = self.read("docs/navigation-input.md")
        self.assertIn("历史探针在 `4.6.3.stable.official.7d41c59c4`", navigation)
        self.assertNotIn("当前固定引擎 `4.6.3", navigation)

if __name__ == "__main__":
    unittest.main()
