#!/usr/bin/env python3
"""Publish only verified stable firmware; replace same-version assets while draft."""

import argparse
import fnmatch
import hashlib
import json
import os
from pathlib import Path
import re
import shutil

from github_actions import (
    GitHub, VERSION, digest, match_run, output, successful_run,
    validate_metadata, version_key,
)


MARKER = re.compile(r"<!-- openwrt-build: (\{[^\n]+\}) -->")
REQUIRED = {
    "packages.tar.gz", "full.manifest", "recovery.manifest",
    "full.config", "recovery.config", "BUILD-INFO.txt", "BUILD-METADATA.json",
}
PATTERNS = (
    "full-*-squashfs-sysupgrade.bin",
    "recovery-*-initramfs-factory.ubi",
    "recovery-*-initramfs-kernel.bin",
    "recovery-*-initramfs-kernel.itb",
    "recovery-*-initramfs.itb",
    "*.buildinfo", "*.pub",
)


def managed(name):
    return name in REQUIRED | {"SHA256SUMS.txt"} or any(
        fnmatch.fnmatchcase(name, pattern) for pattern in PATTERNS
    )


def validate_artifacts(directory, api, run):
    directory = Path(directory)
    entries = list(directory.iterdir())
    if any(not item.is_file() or item.is_symlink() for item in entries):
        raise ValueError("Firmware artifacts must be regular flat files")
    files = {item.name: item for item in entries}
    if not REQUIRED | {"SHA256SUMS.txt"} <= files.keys():
        raise ValueError("Required firmware deliverables are missing")
    checksums = {}
    for line in files["SHA256SUMS.txt"].read_text(encoding="utf-8").splitlines():
        match = re.fullmatch(r"([0-9a-f]{64})  (?:\./)?([^/\\\r\n]+)", line)
        if not match or match[2] in {".", "..", "SHA256SUMS.txt"} or match[2] in checksums:
            raise ValueError("Unsafe or duplicate checksum manifest entry")
        checksums[match[2]] = match[1]
    if set(files) != set(checksums) | {"SHA256SUMS.txt"}:
        raise ValueError("Artifact files do not exactly match SHA256SUMS.txt")
    if any(digest(files[name]) != checksum for name, checksum in checksums.items()):
        raise ValueError("Firmware artifact checksum mismatch")
    if not REQUIRED <= files.keys() or any(files[name].stat().st_size == 0 for name in REQUIRED):
        raise ValueError("Required firmware deliverables are missing or empty")
    if any(not managed(name) and name != "build.log" for name in files):
        raise ValueError("Unexpected firmware artifact")
    full = [name for name in files if fnmatch.fnmatchcase(name, PATTERNS[0])]
    recovery = [name for name in files if fnmatch.fnmatchcase(name, PATTERNS[1])]
    fits = [
        name for name in files
        if any(fnmatch.fnmatchcase(name, pattern) for pattern in PATTERNS[2:5])
    ]
    if len(full) != 1 or len(recovery) != 1 or not fits:
        raise ValueError("Expected full sysupgrade, recovery UBI and recovery FIT")
    if any("ax3000t-an8855" not in name for name in full + recovery + fits):
        raise ValueError("Wrong firmware board")
    if files[full[0]].stat().st_size > 100 * 1024 * 1024 or any(
        files[name].stat().st_size > 26 * 1024 * 1024 for name in fits
    ):
        raise ValueError("Firmware exceeds the validated image size budget")
    abis = []
    for name in ("full.manifest", "recovery.manifest"):
        kernels = [
            line.split(" - ", 1)[1] for line in files[name].read_text(encoding="utf-8").splitlines()
            if line.startswith("kernel - ")
        ]
        if len(kernels) != 1:
            raise ValueError("Missing or ambiguous kernel ABI")
        abis.append(kernels[0])
    if abis[0] != abis[1]:
        raise ValueError("Full and recovery kernel ABIs differ")
    for name in ("full.config", "recovery.config"):
        if "CONFIG_TARGET_mediatek_filogic_DEVICE_xiaomi_mi-router-ax3000t-an8855=y" not in (
            files[name].read_text(encoding="utf-8").splitlines()
        ):
            raise ValueError("Firmware configuration selects the wrong board")
    value = validate_metadata(json.loads(files["BUILD-METADATA.json"].read_text(encoding="utf-8")))
    if value["channel"] != "stable":
        raise ValueError("Snapshot firmware cannot be released")
    match_run(value, api, run)
    if f"OpenWrt commit: {value['upstream_commit']}" not in files["BUILD-INFO.txt"].read_text(
        encoding="utf-8"
    ).splitlines():
        raise ValueError("BUILD-INFO and machine-readable provenance disagree")
    return value, {name: path for name, path in files.items() if managed(name)}


def stage_assets(files, destination):
    destination = Path(destination)
    if destination.exists():
        raise ValueError("Release staging directory must not already exist")
    destination.mkdir(parents=True)
    for name, path in files.items():
        if name != "SHA256SUMS.txt":
            shutil.copyfile(path, destination / name)
    paths = sorted(destination.iterdir())
    (destination / "SHA256SUMS.txt").write_text(
        "".join(f"{digest(path)}  {path.name}\n" for path in paths), encoding="utf-8"
    )
    return sorted(destination.iterdir())


def verify_remote(api, release_id, paths):
    assets = list(api.pages(f"{api.base}/releases/{release_id}/assets"))
    by_name = {asset["name"]: asset for asset in assets}
    if len(by_name) != len(assets):
        raise ValueError("Duplicate release asset names")
    expected = {path.name for path in paths}
    if {name for name in by_name if managed(name)} != expected:
        raise ValueError("Release asset inventory differs from the validated deliverables")
    for path in paths:
        asset = by_name[path.name]
        if asset["state"] != "uploaded" or asset["size"] != path.stat().st_size:
            raise ValueError(f"Incomplete release asset: {path.name}")
        checksum = asset.get("digest")
        if checksum is None:
            content = api.request(
                f"{api.base}/releases/assets/{asset['id']}", binary=True
            )
            checksum = "sha256:" + hashlib.sha256(content).hexdigest()
        if checksum != "sha256:" + digest(path):
            raise ValueError(f"Uploaded release asset checksum mismatch: {path.name}")


def release_body(value):
    repository = value["repository"]
    return (
        f"## OpenWrt {value['upstream_ref']} · AX3000T AN8855\n\n"
        "仅适用于 AN8855 单 UBI 布局；升级前请备份配置。\n\n"
        "- `full-*-squashfs-sysupgrade.bin`：日常完整固件。\n"
        "- `recovery-*-initramfs*`：精简恢复镜像，不是日常完整固件。\n"
        "- `packages.tar.gz`：同次构建的软件包及匹配内核模块。\n"
        "- 下载后使用 `SHA256SUMS.txt` 校验；完整／恢复镜像已通过体积和 ABI 检查。\n\n"
        f"上游源码：`{value['upstream_ref']}` / `{value['upstream_commit']}`  \n"
        f"本仓库源码：[{value['repository_commit']}]"
        f"(https://github.com/{repository}/commit/{value['repository_commit']})  \n"
        f"构建：[运行 {value['run_id']}，尝试 {value['run_attempt']}]"
        f"(https://github.com/{repository}/actions/runs/{value['run_id']})\n\n"
        "同一上游版本重新构建时，本 Release 的附件会被替换；"
        "已有 Git 标签保留首发指向，实际构建来源以本说明和 `BUILD-METADATA.json` 为准。\n\n"
        f"<!-- openwrt-build: {json.dumps(value, sort_keys=True)} -->\n"
    )


def publish(api, run_id, directory, staging):
    run = successful_run(api, "stable", run_id)
    value, files = validate_artifacts(directory, api, run)
    paths = stage_assets(files, staging)
    tag = value["upstream_ref"]
    releases = list(api.pages(f"{api.base}/releases"))
    matches = [release for release in releases if release["tag_name"] == tag]
    if len(matches) > 1:
        raise ValueError("Multiple releases exist for the same stable tag")
    existing = matches[0] if matches else None
    if existing and existing.get("immutable"):
        raise ValueError("Immutable releases prevent the selected same-version replacement policy")
    if existing:
        marker = MARKER.search(existing.get("body") or "")
        if marker:
            old = validate_metadata(json.loads(marker[1]))
            if old["repository"] != api.repository or old["upstream_ref"] != tag:
                raise ValueError("Existing release provenance belongs to another source")
            old_order = (old["run_number"], old["run_attempt"])
            new_order = (value["run_number"], value["run_attempt"])
            if old_order > new_order:
                print("A newer stable build already owns this release; refusing to roll back")
                return "stale"
            if old_order == new_order:
                if old != value:
                    raise ValueError("Conflicting provenance for the same build attempt")
                if not existing["draft"]:
                    try:
                        verify_remote(api, existing["id"], paths)
                        print("This successful build is already published with matching assets")
                        return "unchanged"
                    except ValueError:
                        print("Repairing incomplete or altered assets for the same build")
    # Tags are created once, never force-moved during same-version replacement.
    if api.optional(f"{api.base}/git/ref/tags/{tag}") is None:
        api.request(f"{api.base}/git/refs", "POST", {
            "ref": f"refs/tags/{tag}", "sha": value["repository_commit"],
        })
    payload = {
        "tag_name": tag, "name": f"OpenWrt {tag} · AX3000T AN8855",
        "body": release_body(value), "draft": True, "prerelease": False,
    }
    if existing:
        release = api.request(f"{api.base}/releases/{existing['id']}", "PATCH", payload)
    else:
        release = api.request(f"{api.base}/releases", "POST", payload)
    release_id = release["id"]
    expected = {path.name for path in paths}
    # Only our generated attachments are managed; unrelated manual assets survive.
    for asset in api.pages(f"{api.base}/releases/{release_id}/assets"):
        if managed(asset["name"]) and asset["name"] not in expected:
            api.request(f"{api.base}/releases/assets/{asset['id']}", "DELETE")
    api.upload(tag, paths)
    verify_remote(api, release_id, paths)
    # Re-read after upload so a higher version cannot accidentally lose Latest.
    published_versions = [
        version_key(item["tag_name"]) for item in api.pages(f"{api.base}/releases")
        if not item["draft"] and not item["prerelease"] and VERSION.fullmatch(item["tag_name"])
    ]
    latest = version_key(tag) >= max(published_versions, default=(0, 0, 0))
    api.request(f"{api.base}/releases/{release_id}", "PATCH", {
        "draft": False, "make_latest": "true" if latest else "false",
    })
    print(f"Published validated stable firmware: {tag}")
    return "published"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-id", type=int, required=True)
    parser.add_argument("--artifacts", required=True)
    parser.add_argument("--staging", required=True)
    args = parser.parse_args()
    result = publish(
        GitHub(os.environ["GITHUB_REPOSITORY"]), args.run_id, args.artifacts, args.staging
    )
    output(result=result)


if __name__ == "__main__":
    main()
