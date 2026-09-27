import os
from pathlib import Path
import subprocess
import tempfile
import unittest

import release


class BumpLevelTest(unittest.TestCase):
    def test_levels(self):
        cases = {
            "fix: handle empty lease": 1,
            "fix(mysql): reconnect": 1,
            "feat: add option": 2,
            "Feat(cli): add flag": 2,
            "feat!: drop legacy config": 3,
            "refactor(core)!: rename table": 3,
            "fix: x\n\nBREAKING CHANGE: schema changed": 3,
            "chore: bump deps": 0,
            "ci: add pipeline": 0,
            "Merge pull request #1 from user/branch": 0,
            "added missing files": 0,
        }
        for message, level in cases.items():
            with self.subTest(message=message):
                self.assertEqual(release.bump_level(message), level)


class RepositoryTest(unittest.TestCase):
    def setUp(self):
        self.cwd = os.getcwd()
        self.tmp = tempfile.TemporaryDirectory()
        os.chdir(self.tmp.name)
        Path("include/udhcp").mkdir(parents=True)
        Path("CMakeLists.txt").write_text(
            "project(udhcp-sql VERSION 0.9.9 LANGUAGES C)\n")
        Path("include/udhcp/version.h").write_text(
            '#define VERSION "0.9.9-pre"\n')
        self.git("init", "-q")
        self.git("config", "user.email", "ci@example.com")
        self.git("config", "user.name", "CI")
        self.commit("chore: initial")

    def tearDown(self):
        os.chdir(self.cwd)
        self.tmp.cleanup()

    def git(self, *args):
        subprocess.run(["git", *args], check=True, capture_output=True)

    def commit(self, message):
        self.git("commit", "-q", "--allow-empty", "-m", message)

    def test_no_tags_uses_cmake_version(self):
        self.commit("fix: bug")
        self.assertEqual(release.plan(), "0.9.10")

    def test_bumps_from_latest_tag(self):
        self.commit("feat: old feature")
        self.git("tag", "v0.10.0")
        self.git("tag", "v0.2.0")
        self.git("tag", "not-a-version")
        self.commit("fix: bug")
        self.commit("feat: feature")
        self.assertEqual(release.plan(), "0.11.0")

    def test_major_bump(self):
        self.git("tag", "v1.2.3")
        self.commit("feat(api)!: breaking")
        self.assertEqual(release.plan(), "2.0.0")

    def test_no_release_without_releasable_commits(self):
        self.git("tag", "v1.2.3")
        self.commit("docs: readme")
        self.assertEqual(release.plan(), "")

    def test_no_release_when_head_tagged(self):
        self.commit("feat: feature")
        self.git("tag", "v1.0.0")
        self.assertEqual(release.plan(), "")

    def test_set_version(self):
        release.set_version("1.2.3")
        self.assertIn("VERSION 1.2.3 ", Path("CMakeLists.txt").read_text())
        self.assertIn('"1.2.3"', Path("include/udhcp/version.h").read_text())
        with self.assertRaises(ValueError):
            release.set_version("1.2")


if __name__ == "__main__":
    unittest.main()
