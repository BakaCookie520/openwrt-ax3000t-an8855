"""Offline tests: upstream polling, trusted provenance and draft-only publication."""

import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
from github_actions import (  # noqa: E402
    APIError, GitHub, WORKFLOWS, artifact_name, digest, metadata,
    successful_run, validate_metadata, write_json,
)


def load_script(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / "scripts" / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


state = load_script("ci-build-state")
publisher = load_script("publish-stable-release")
REPO = "owner/router"
COMMIT = "a" * 40
REPO_COMMIT = "b" * 40


def build_metadata(run_id=10, channel="stable", attempt=1, tag="v25.12.6"):
    return {
        "schema_version": 1, "repository": REPO, "channel": channel,
        "upstream_ref": "main" if channel == "main" else tag,
        "upstream_commit": COMMIT, "repository_commit": REPO_COMMIT,
        "run_id": run_id, "run_attempt": attempt, "run_number": run_id,
    }


class FakeGitHub(GitHub):
    def __init__(self, channel="stable", run_id=10):
        super().__init__(REPO)
        self.runs = {}
        self.jobs = {}
        self.run_artifacts = {}
        self.releases = []
        self.assets = {}
        self.blobs = {}
        self.tags = {}
        self.calls = []
        self.next_id = 100
        self.upload_error = False
        self.add_run(channel, run_id)

    def add_run(self, channel, run_id, attempt=1):
        self.runs[run_id] = {
            "id": run_id, "run_number": run_id, "run_attempt": attempt,
            "repository": {"full_name": REPO}, "head_repository": {"full_name": REPO},
            "head_branch": "master", "head_sha": REPO_COMMIT,
            "path": WORKFLOWS[channel][0], "event": "schedule",
            "status": "completed", "conclusion": "success",
        }
        self.jobs[run_id] = [{
            "name": WORKFLOWS[channel][1], "status": "completed", "conclusion": "success",
        }]
        self.run_artifacts[run_id] = [{
            "name": artifact_name(channel, run_id, attempt), "expired": False,
        }]

    def pages(self, path, key=None):
        if path.endswith("/releases"):
            return iter(copy.deepcopy(self.releases))
        if path.endswith("/jobs"):
            return iter(copy.deepcopy(self.jobs[int(path.split("/runs/")[1].split("/")[0])]))
        if path.endswith("/artifacts"):
            return iter(copy.deepcopy(self.run_artifacts[int(path.split("/")[-2])]))
        if path.endswith("/assets"):
            return iter(copy.deepcopy(self.assets.get(int(path.split("/")[-2]), [])))
        raise AssertionError(path)

    def request(self, path, method="GET", data=None, binary=False):
        self.calls.append((method, path, copy.deepcopy(data)))
        if path == "repos/openwrt/openwrt/commits/v25.12.6":
            return {"sha": COMMIT}
        if path == self.base:
            return {"default_branch": "master"}
        if "/actions/runs/" in path:
            run_id = int(path.split("/")[-1])
            if run_id not in self.runs:
                raise APIError("not found", 404)
            return copy.deepcopy(self.runs[run_id])
        if "/git/ref/tags/" in path:
            tag = path.split("/")[-1]
            if tag not in self.tags:
                raise APIError("no tag", 404)
            return {"object": {"sha": self.tags[tag]}}
        if path.endswith("/git/refs") and method == "POST":
            self.tags[data["ref"].split("/")[-1]] = data["sha"]
            return {}
        if "/releases/assets/" in path:
            asset_id = int(path.split("/")[-1])
            if binary:
                return self.blobs[asset_id]
            if method == "DELETE":
                for release_assets in self.assets.values():
                    release_assets[:] = [item for item in release_assets if item["id"] != asset_id]
                return None
        if path.endswith("/releases") and method == "POST":
            self.next_id += 1
            release = {"id": self.next_id, "immutable": False, **data}
            self.releases.append(release)
            return copy.deepcopy(release)
        if "/releases/" in path and method == "PATCH":
            release_id = int(path.split("/")[-1])
            release = next(item for item in self.releases if item["id"] == release_id)
            release.update(data)
            return copy.deepcopy(release)
        raise AssertionError((method, path, data))

    def upload(self, tag, paths):
        release = next(item for item in self.releases if item["tag_name"] == tag)
        if not release["draft"]:
            raise AssertionError("Assets were changed on a public release")
        target = self.assets.setdefault(release["id"], [])
        for index, path in enumerate(paths):
            if self.upload_error and index == 1:
                raise RuntimeError("simulated upload failure")
            target[:] = [item for item in target if item["name"] != path.name]
            self.next_id += 1
            content = path.read_bytes()
            target.append({
                "id": self.next_id, "name": path.name, "state": "uploaded",
                "size": len(content), "digest": "sha256:" + hashlib.sha256(content).hexdigest(),
            })
            self.blobs[self.next_id] = content


class WorkspaceTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.directory = Path(self.temp.name)
        self.api = FakeGitHub()

    def tearDown(self):
        self.temp.cleanup()

    def artifacts(self, value=None):
        directory = self.directory / "input"
        directory.mkdir(exist_ok=True)
        value = value or build_metadata()
        for name in publisher.REQUIRED:
            (directory / name).write_text("fixture\n", encoding="utf-8")
        write_json(directory / "BUILD-METADATA.json", value)
        (directory / "BUILD-INFO.txt").write_text(
            f"OpenWrt commit: {value['upstream_commit']}\n", encoding="utf-8"
        )
        for name in ("full.manifest", "recovery.manifest"):
            (directory / name).write_text("kernel - matching-abi\n", encoding="utf-8")
        for name in ("full.config", "recovery.config"):
            (directory / name).write_text(
                "CONFIG_TARGET_mediatek_filogic_DEVICE_xiaomi_mi-router-ax3000t-an8855=y\n",
                encoding="utf-8",
            )
        for name in (
            "full-openwrt-xiaomi_mi-router-ax3000t-an8855-squashfs-sysupgrade.bin",
            "recovery-openwrt-xiaomi_mi-router-ax3000t-an8855-initramfs-factory.ubi",
            "recovery-openwrt-xiaomi_mi-router-ax3000t-an8855-initramfs-kernel.bin",
            "full-feeds.buildinfo", "key.pub", "build.log",
        ):
            (directory / name).write_bytes(b"validated fixture\n")
        self.checksums(directory)
        return directory

    def checksums(self, directory):
        (directory / "SHA256SUMS.txt").write_text(
            "".join(f"{digest(path)}  ./{path.name}\n" for path in sorted(directory.iterdir())
                    if path.name != "SHA256SUMS.txt"), encoding="utf-8",
        )

    def publish(self, api=None):
        # Each invocation models a fresh hosted release runner.
        staging = self.directory / f"staging-{len(list(self.directory.glob('staging-*')))}"
        return publisher.publish(api or self.api, 10, self.directory / "input", staging)


class BuildStateTests(WorkspaceTest):
    def test_metadata_cli_checks_actual_checkout_and_hashes_provenance(self):
        directory = self.directory / "artifacts"
        directory.mkdir()
        (directory / "full.config").write_text("config\n", encoding="utf-8")
        environment = {
            "GITHUB_REPOSITORY": REPO, "GITHUB_SHA": REPO_COMMIT, "GITHUB_RUN_ID": "10",
            "GITHUB_RUN_ATTEMPT": "1", "GITHUB_RUN_NUMBER": "10",
        }
        arguments = [
            "ci-build-state.py", "metadata", "--channel", "stable", "--ref", "v25.12.6",
            "--commit", COMMIT, "--tree", str(self.directory), "--artifacts", str(directory),
        ]
        with patch.dict(os.environ, environment), patch.object(sys, "argv", arguments):
            with patch.object(state.subprocess, "check_output", return_value="c" * 40 + "\n"):
                with self.assertRaises(ValueError):
                    state.main()
            self.assertFalse((directory / "BUILD-METADATA.json").exists())
            with patch.object(state.subprocess, "check_output", return_value=COMMIT + "\n"):
                state.main()
        self.assertEqual(
            json.loads((directory / "BUILD-METADATA.json").read_text(encoding="utf-8")),
            build_metadata(),
        )
        lines = (directory / "SHA256SUMS.txt").read_text(encoding="utf-8").splitlines()
        self.assertIn(f"{digest(directory / 'BUILD-METADATA.json')}  ./BUILD-METADATA.json", lines)

    def test_only_verified_unchanged_scheduled_build_is_skipped(self):
        record = self.directory / "record.json"
        write_json(record, build_metadata())
        self.assertFalse(state.should_build(self.api, "stable", "v25.12.6", COMMIT, record, "schedule"))
        for event in ("workflow_dispatch", "push", "pull_request"):
            self.assertTrue(state.should_build(self.api, "stable", "v25.12.6", COMMIT, record, event))
        for channel, tag, commit in (
            ("stable", "v25.12.7", COMMIT), ("stable", "v25.12.6", "c" * 40),
            ("main", "main", COMMIT),
        ):
            self.assertTrue(state.should_build(self.api, channel, tag, commit, record, "schedule"))

    def test_missing_corrupt_and_deleted_records_rebuild(self):
        record = self.directory / "record.json"
        self.assertTrue(state.should_build(self.api, "stable", "v25.12.6", COMMIT, record, "schedule"))
        record.write_text("{bad", encoding="utf-8")
        self.assertTrue(state.should_build(self.api, "stable", "v25.12.6", COMMIT, record, "schedule"))
        write_json(record, build_metadata(99))
        self.assertTrue(state.should_build(self.api, "stable", "v25.12.6", COMMIT, record, "schedule"))

    def test_failed_cancelled_skipped_fork_and_nondefault_runs_never_skip(self):
        mutations = [
            ("conclusion", "failure"), ("conclusion", "cancelled"),
            ("status", "in_progress"), ("head_branch", "feature"),
            ("path", WORKFLOWS["main"][0]), ("event", "pull_request"),
            ("head_repository", {"full_name": "fork/router"}), ("run_attempt", 2),
        ]
        record = self.directory / "record.json"
        write_json(record, build_metadata())
        original = copy.deepcopy(self.api.runs[10])
        for key, value in mutations:
            with self.subTest(key=key, value=value):
                self.api.runs[10] = {**original, key: value}
                self.assertTrue(state.should_build(self.api, "stable", "v25.12.6", COMMIT, record, "schedule"))
        self.api.runs[10] = original
        self.api.jobs[10][0]["conclusion"] = "skipped"
        self.assertTrue(state.should_build(self.api, "stable", "v25.12.6", COMMIT, record, "schedule"))

    def test_api_failure_is_not_treated_as_missing_state(self):
        record = self.directory / "record.json"
        write_json(record, build_metadata())
        with patch.object(self.api, "request", side_effect=APIError("forbidden", 403)):
            with self.assertRaises(APIError):
                state.should_build(self.api, "stable", "v25.12.6", COMMIT, record, "schedule")

    def test_resolve_stable_numeric_versions_and_peeled_tag(self):
        releases = [
            {"tag_name": tag, "draft": draft, "prerelease": prerelease}
            for tag, draft, prerelease in (
                ("v25.12.9", False, False), ("v25.12.10", False, False),
                ("v99.0.0", True, False), ("v26.0.0-rc1", False, True),
                ("v24.10.99", False, False), ("main", False, False),
            )
        ]
        with patch.object(self.api, "pages", return_value=iter(releases)), patch.object(
            state.subprocess, "run", return_value=subprocess.CompletedProcess(
                [], 0, f"{'c' * 40}\trefs/tags/v25.12.10\n{COMMIT}\trefs/tags/v25.12.10^{{}}\n", ""
            )
        ):
            self.assertEqual(state.resolve(self.api, "stable"), ("v25.12.10", COMMIT))

    def test_resolve_main_and_upstream_errors_fail_closed(self):
        with patch.object(state.subprocess, "run", return_value=subprocess.CompletedProcess(
            [], 0, f"{COMMIT}\trefs/heads/main\n", ""
        )):
            self.assertEqual(state.resolve(self.api, "main"), ("main", COMMIT))
        with patch.object(state.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, "", "")):
            with self.assertRaises(ValueError):
                state.resolve(self.api, "main")
        with patch.object(self.api, "pages", return_value=iter([])):
            with self.assertRaises(ValueError):
                state.resolve(self.api, "stable")
        with patch.object(state.subprocess, "run", side_effect=subprocess.CalledProcessError(1, "git")):
            with self.assertRaises(subprocess.CalledProcessError):
                state.resolve(self.api, "main")

    def test_metadata_requires_complete_provenance(self):
        environment = {
            "GITHUB_REPOSITORY": REPO, "GITHUB_SHA": REPO_COMMIT, "GITHUB_RUN_ID": "10",
            "GITHUB_RUN_ATTEMPT": "1", "GITHUB_RUN_NUMBER": "10",
        }
        with patch.dict(os.environ, environment):
            self.assertEqual(metadata("stable", "v25.12.6", COMMIT), build_metadata())
        for key, value in (("upstream_commit", "bad"), ("run_attempt", 0), ("upstream_ref", "v1.2.3-rc1")):
            with self.subTest(key=key), self.assertRaises(ValueError):
                validate_metadata({**build_metadata(), key: value})


class ReleaseGateTests(WorkspaceTest):
    def test_legacy_artifact_requires_explicit_manual_migration(self):
        self.api.run_artifacts[10] = [{
            "name": f"firmware-stable-latest-{REPO_COMMIT}", "expired": False,
        }]
        with self.assertRaises(ValueError):
            state.release_candidate(self.api, 10)
        with patch.dict(os.environ, {"GITHUB_EVENT_NAME": "workflow_dispatch"}):
            run, name = state.release_candidate(self.api, 10, "v25.12.6")
        self.assertEqual(run["id"], 10)
        self.assertEqual(name, f"firmware-stable-latest-{REPO_COMMIT}")
        with patch.dict(os.environ, {"GITHUB_EVENT_NAME": "workflow_run"}):
            with self.assertRaises(ValueError):
                state.release_candidate(self.api, 10, "v25.12.6")
        self.api.runs[10]["run_attempt"] = 2
        with patch.dict(os.environ, {"GITHUB_EVENT_NAME": "workflow_dispatch"}):
            with self.assertRaises(ValueError):
                state.release_candidate(self.api, 10, "v25.12.6")

    def test_skipped_build_is_noop_but_missing_artifacts_is_failure(self):
        self.assertIsNotNone(state.release_candidate(self.api, 10))
        self.api.jobs[10][0]["conclusion"] = "skipped"
        self.assertIsNone(state.release_candidate(self.api, 10))
        self.api.jobs[10][0]["conclusion"] = "success"
        self.api.run_artifacts[10] = []
        with self.assertRaises(ValueError):
            state.release_candidate(self.api, 10)

    def test_snapshot_and_failed_cancelled_runs_cannot_release(self):
        for channel in ("main", "stable"):
            api = FakeGitHub(channel)
            if channel == "stable":
                api.runs[10]["conclusion"] = "failure"
            with self.assertRaises(ValueError):
                state.release_candidate(api, 10)
        self.api.runs[10]["conclusion"] = "cancelled"
        with self.assertRaises(ValueError):
            successful_run(self.api, "stable", 10)

    def test_wrong_attempt_or_expired_artifact_is_rejected(self):
        for artifact in (
            {"name": "firmware-stable-10-2", "expired": False},
            {"name": "firmware-stable-10-1", "expired": True},
        ):
            self.api.run_artifacts[10] = [artifact]
            with self.assertRaises(ValueError):
                state.release_candidate(self.api, 10)


class PublicationTests(WorkspaceTest):
    def legacy_artifacts(self):
        directory = self.artifacts()
        (directory / "BUILD-METADATA.json").unlink()
        for path in list(directory.glob("*-openwrt-*.bin")) + list(directory.glob("*-openwrt-*.ubi")):
            path.rename(path.with_name(path.name.replace("-openwrt-", "-openwrt-25.12.6-")))
        for name in ("full.config", "recovery.config"):
            with (directory / name).open("a", encoding="utf-8") as stream:
                stream.write('CONFIG_VERSION_REPO="https://mirrors.ustc.edu.cn/openwrt/releases/25.12.6"\n')
        self.checksums(directory)
        return directory

    def test_legacy_provenance_is_derived_only_after_original_checksum_verification(self):
        directory = self.legacy_artifacts()
        original_manifest = (directory / "SHA256SUMS.txt").read_bytes()
        with patch.object(self.api, "request", return_value={"sha": COMMIT}) as request:
            value, files = publisher.validate_artifacts(directory, self.api, self.api.runs[10], "v25.12.6")
        request.assert_called_once_with("repos/openwrt/openwrt/commits/v25.12.6")
        self.assertEqual(value["upstream_commit"], COMMIT)
        self.assertEqual(value["provenance"], "verified-legacy-artifact")
        self.assertEqual(value["original_checksums_sha256"], hashlib.sha256(original_manifest).hexdigest())
        self.assertFalse((directory / "BUILD-METADATA.json").exists())
        self.assertEqual((directory / "SHA256SUMS.txt").read_bytes(), original_manifest)
        staged = publisher.stage_assets(files, self.directory / "staged-legacy", value)
        self.assertIn("BUILD-METADATA.json", [path.name for path in staged])
        (directory / "packages.tar.gz").write_bytes(b"tampered")
        with patch.object(self.api, "request") as request, self.assertRaises(ValueError):
            publisher.validate_artifacts(directory, self.api, self.api.runs[10], "v25.12.6")
        request.assert_not_called()

    def test_legacy_wrong_version_source_or_retried_run_is_rejected(self):
        directory = self.legacy_artifacts()
        with patch.object(self.api, "request", return_value={"sha": "c" * 40}):
            with self.assertRaises(ValueError):
                publisher.validate_artifacts(directory, self.api, self.api.runs[10], "v25.12.6")
        with self.assertRaises(ValueError):
            publisher.validate_artifacts(directory, self.api, self.api.runs[10], "v25.12.7")
        with self.assertRaises(ValueError):
            publisher.validate_artifacts(directory, self.api, {**self.api.runs[10], "run_attempt": 2}, "v25.12.6")

    def test_legacy_publication_and_publication_only_retry(self):
        directory = self.legacy_artifacts()
        for staging, expected in (("first", "published"), ("retry", "unchanged")):
            self.assertEqual(publisher.publish(
                self.api, 10, directory, self.directory / staging, "v25.12.6"
            ), expected)
        self.assertFalse(self.api.releases[0]["draft"])
        self.assertFalse((directory / "BUILD-METADATA.json").exists())

    def test_verify_only_never_mutates_github(self):
        directory = self.legacy_artifacts()
        self.assertEqual(publisher.publish(
            self.api, 10, directory, self.directory / "verify", "v25.12.6", verify_only=True
        ), "verified")
        self.assertFalse(any(method != "GET" for method, _, _ in self.api.calls))
        self.assertFalse(self.api.releases)
        self.assertFalse(self.api.tags)

    def test_wrong_board_or_oversized_image_never_creates_release(self):
        directory = self.artifacts()
        (directory / "full.config").write_text("CONFIG_TARGET_stock=y\n", encoding="utf-8")
        self.checksums(directory)
        with self.assertRaises(ValueError):
            self.publish()
        self.artifacts()
        image = next(directory.glob("full-*.bin"))
        with image.open("r+b") as stream:
            stream.truncate(101 * 1024 * 1024)
        self.checksums(directory)
        with self.assertRaises(ValueError):
            self.publish()
        self.assertFalse(self.api.releases)

    def test_first_release_is_draft_until_verified_and_has_exact_checksums(self):
        self.artifacts()
        self.assertEqual(self.publish(), "published")
        release = self.api.releases[0]
        self.assertEqual(release["tag_name"], "v25.12.6")
        self.assertFalse(release["draft"])
        self.assertFalse(release["prerelease"])
        self.assertEqual(release["make_latest"], "true")
        self.assertEqual(self.api.tags, {"v25.12.6": REPO_COMMIT})
        assets = {item["name"]: item for item in self.api.assets[release["id"]]}
        self.assertNotIn("build.log", assets)
        manifest = self.api.blobs[assets["SHA256SUMS.txt"]["id"]].decode()
        self.assertNotIn("build.log", manifest)
        for line in manifest.splitlines():
            checksum, name = line.split("  ")
            self.assertEqual(checksum, assets[name]["digest"].removeprefix("sha256:"))

    def test_repeated_publication_is_idempotent(self):
        self.artifacts()
        self.publish()
        self.api.calls.clear()
        self.assertEqual(self.publish(), "unchanged")
        self.assertFalse(any(method != "GET" for method, _, _ in self.api.calls))

    def test_same_version_replaces_managed_assets_but_never_moves_tag(self):
        self.artifacts()
        old = build_metadata(9)
        self.api.releases = [{
            "id": 1, "tag_name": "v25.12.6", "name": "old", "draft": False,
            "prerelease": False, "body": publisher.release_body(old),
        }]
        self.api.tags["v25.12.6"] = "c" * 40
        self.api.assets[1] = [
            {"id": 2, "name": "manual-note.txt"},
            {"id": 3, "name": "old.pub"},
        ]
        self.assertEqual(self.publish(), "published")
        self.assertEqual(len(self.api.releases), 1)
        self.assertEqual(self.api.tags["v25.12.6"], "c" * 40)
        names = {item["name"] for item in self.api.assets[1]}
        self.assertIn("manual-note.txt", names)
        self.assertNotIn("old.pub", names)

    def test_older_build_cannot_overwrite_newer_same_version(self):
        self.artifacts()
        self.api.releases = [{
            "id": 1, "tag_name": "v25.12.6", "draft": False, "prerelease": False,
            "body": publisher.release_body(build_metadata(11)),
        }]
        self.assertEqual(self.publish(), "stale")
        self.assertFalse(any(method != "GET" for method, _, _ in self.api.calls))

    def test_same_run_older_attempt_cannot_overwrite_later_attempt(self):
        self.artifacts()
        self.api.releases = [{
            "id": 1, "tag_name": "v25.12.6", "draft": False, "prerelease": False,
            "body": publisher.release_body(build_metadata(attempt=2)),
        }]
        self.assertEqual(self.publish(), "stale")

    def test_older_version_is_not_marked_latest(self):
        self.artifacts()
        self.api.releases = [{
            "id": 1, "tag_name": "v25.12.7", "draft": False, "prerelease": False,
        }]
        self.assertEqual(self.publish(), "published")
        release = next(item for item in self.api.releases if item["tag_name"] == "v25.12.6")
        self.assertEqual(release["make_latest"], "false")

    def test_upload_failure_stays_draft_and_can_resume(self):
        self.artifacts()
        self.api.upload_error = True
        with self.assertRaises(RuntimeError):
            self.publish()
        self.assertTrue(self.api.releases[0]["draft"])
        self.api.upload_error = False
        self.assertEqual(self.publish(), "published")
        self.assertEqual(len(self.api.releases), 1)
        self.assertFalse(self.api.releases[0]["draft"])

    def test_bad_remote_digest_never_publishes(self):
        self.artifacts()
        original = self.api.upload
        def corrupt(tag, paths):
            original(tag, paths)
            self.api.assets[self.api.releases[0]["id"]][0]["digest"] = "sha256:" + "0" * 64
        with patch.object(self.api, "upload", side_effect=corrupt), self.assertRaises(ValueError):
            self.publish()
        self.assertTrue(self.api.releases[0]["draft"])

    def test_missing_digest_downloads_and_verifies_asset_bytes(self):
        self.artifacts()
        self.publish()
        for asset in self.api.assets[self.api.releases[0]["id"]]:
            del asset["digest"]
        self.assertEqual(self.publish(), "unchanged")

    def test_missing_tampered_wrong_channel_or_wrong_run_artifacts_are_rejected(self):
        directory = self.artifacts()
        (directory / "packages.tar.gz").write_text("tampered", encoding="utf-8")
        with self.assertRaises(ValueError):
            self.publish()
        self.checksums(directory)
        (directory / "recovery.manifest").unlink()
        self.checksums(directory)
        with self.assertRaises(ValueError):
            self.publish()
        for value in (build_metadata(channel="main"), build_metadata(11)):
            self.artifacts(value)
            with self.assertRaises(ValueError):
                self.publish()
        self.assertFalse(self.api.releases)

    def test_unsafe_checksum_path_wrong_abi_and_unexpected_file_are_rejected(self):
        directory = self.artifacts()
        (directory / "SHA256SUMS.txt").write_text("a" * 64 + "  ../escape\n", encoding="utf-8")
        with self.assertRaises(ValueError):
            self.publish()
        self.artifacts()
        (directory / "recovery.manifest").write_text("kernel - wrong\n", encoding="utf-8")
        self.checksums(directory)
        with self.assertRaises(ValueError):
            self.publish()
        self.artifacts()
        (directory / "unvalidated-initramfs.bin").write_bytes(b"not allowed")
        self.checksums(directory)
        with self.assertRaises(ValueError):
            self.publish()

    def test_immutable_release_fails_without_mutation(self):
        self.artifacts()
        self.api.releases = [{"id": 1, "tag_name": "v25.12.6", "immutable": True}]
        with self.assertRaises(ValueError):
            self.publish()
        self.assertFalse(any(method != "GET" for method, _, _ in self.api.calls))


class WorkflowContractTests(unittest.TestCase):
    def test_polling_provenance_recording_and_release_permissions(self):
        for channel, filename, minute in (("main", "ci.yml", 17), ("stable", "stable-latest.yml", 37)):
            text = (ROOT / ".github/workflows" / filename).read_text(encoding="utf-8")
            self.assertIn(f"cron: '{minute} */6 * * *'", text)
            self.assertIn("if: needs.preflight.outputs.should_build == 'true'", text)
            self.assertIn("needs.build.result == 'success'", text)
            self.assertIn("github.event.repository.default_branch", text)
            self.assertIn(f"name: firmware-{channel}-${{{{ github.run_id }}}}-${{{{ github.run_attempt }}}}", text)
            self.assertLess(text.index("Record verified build provenance"), text.index("Upload workflow artifacts"))
            self.assertIn("actions/cache/save@v6", text)
        main = (ROOT / ".github/workflows/ci.yml").read_text(encoding="utf-8")
        self.assertIn("github.event_name != 'pull_request'", main)
        release = (ROOT / ".github/workflows/release.yml").read_text(encoding="utf-8")
        self.assertIn("workflows: [Stable OpenWrt Build - AX3000T-AN8855]", release)
        self.assertNotIn("semantic-release", release)
        self.assertNotIn("issues: write", release)
        self.assertNotIn("pull-requests: write", release)
        self.assertIn('release-gate --run-id "$BUILD_RUN_ID"', release)
        self.assertFalse((ROOT / ".releaserc.json").exists())


class GitHubClientTests(unittest.TestCase):
    def test_pagination_visits_later_pages(self):
        api = GitHub(REPO)
        first = [{"tag_name": "v24.10.1"} for _ in range(100)]
        with patch.object(api, "request", side_effect=[first, [{"tag_name": "v25.12.6"}]]) as request:
            values = list(api.pages("repos/openwrt/openwrt/releases"))
        self.assertEqual(len(values), 101)
        self.assertEqual(values[-1]["tag_name"], "v25.12.6")
        self.assertIn("page=2", request.call_args_list[-1].args[0])

    def test_read_transients_retry_but_mutations_do_not(self):
        failed = subprocess.CompletedProcess([], 1, b"", b"gh: unavailable (HTTP 503)")
        success = subprocess.CompletedProcess([], 0, b'{"ok": true}', b"")
        api = GitHub(REPO)
        with patch("github_actions.subprocess.run", side_effect=[failed, success]) as execute, patch(
            "github_actions.time.sleep"
        ):
            self.assertEqual(api.request(api.base), {"ok": True})
            self.assertEqual(execute.call_count, 2)
        with patch("github_actions.subprocess.run", return_value=failed) as execute:
            with self.assertRaises(APIError):
                api.request(api.base + "/releases", "POST", {"draft": True})
            self.assertEqual(execute.call_count, 1)


if __name__ == "__main__":
    unittest.main()
