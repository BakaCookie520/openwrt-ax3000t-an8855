#!/usr/bin/env python3
"""Resolve/pin upstream sources and validate small successful-build cache records."""

import argparse
import json
import os
from pathlib import Path
import subprocess

from github_actions import (
    APIError, GitHub, SHA, UPSTREAM, VERSION, artifact_name, digest, match_run,
    metadata, output, successful_run, validate_metadata, version_key, write_json,
)


def resolve(api, channel):
    source_ref = "main"
    if channel == "stable":
        releases = (
            release for release in api.pages("repos/openwrt/openwrt/releases")
            if not release["draft"] and not release["prerelease"]
            and VERSION.fullmatch(release["tag_name"])
        )
        source_ref = max(
            (release["tag_name"] for release in releases), key=version_key, default=None
        )
        if source_ref is None:
            raise ValueError("No formal stable OpenWrt release found")
    ref = "refs/heads/main" if channel == "main" else f"refs/tags/{source_ref}"
    result = subprocess.run(
        ["git", "ls-remote", UPSTREAM, ref, f"{ref}^{{}}"],
        check=True, capture_output=True, text=True, timeout=120,
    )
    refs = {}
    for line in result.stdout.splitlines():
        commit, name = line.split()
        refs[name] = commit
    commit = refs.get(f"{ref}^{{}}", refs.get(ref, ""))
    if not SHA.fullmatch(commit):
        raise ValueError(f"Cannot resolve OpenWrt source: {source_ref}")
    return source_ref, commit


def should_build(api, channel, source_ref, commit, state, event):
    if event != "schedule":
        return True
    try:
        value = validate_metadata(json.loads(Path(state).read_text(encoding="utf-8")))
        if (
            value["repository"] != api.repository or value["channel"] != channel
            or value["upstream_ref"] != source_ref or value["upstream_commit"] != commit
        ):
            return True
        run = successful_run(api, channel, value["run_id"])
        match_run(value, api, run)
        return False
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(f"No verified successful build record: {error}")
        return True
    except APIError as error:
        if error.status == 404:
            print("Recorded build run no longer exists; rebuilding conservatively")
            return True
        raise


def release_candidate(api, run_id):
    run = successful_run(api, "stable", run_id, allow_skipped=True)
    if run is None:
        return None
    name = artifact_name("stable", run["id"], run["run_attempt"])
    artifacts = [
        item for item in api.pages(
            f"{api.base}/actions/runs/{run['id']}/artifacts", "artifacts"
        ) if item["name"] == name and not item["expired"]
    ]
    if len(artifacts) != 1:
        raise ValueError("Successful stable build has no unique, unexpired firmware artifact")
    return run, name


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=["resolve", "check", "metadata", "record", "release-gate"])
    parser.add_argument("--channel", choices=["main", "stable"])
    parser.add_argument("--ref")
    parser.add_argument("--commit")
    parser.add_argument("--state", default=".build-state/success.json")
    parser.add_argument("--tree")
    parser.add_argument("--artifacts")
    parser.add_argument("--run-id", type=int)
    args = parser.parse_args()
    api = GitHub(os.environ["GITHUB_REPOSITORY"])
    if args.operation == "release-gate":
        candidate = release_candidate(api, args.run_id)
        if candidate is None:
            output(eligible=False)
        else:
            run, name = candidate
            output(eligible=True, artifact_name=name, run_id=run["id"],
                   run_attempt=run["run_attempt"], source_sha=run["head_sha"])
        return
    if args.channel is None:
        parser.error("--channel is required")
    if args.operation == "resolve":
        source_ref, commit = resolve(api, args.channel)
        output(source_ref=source_ref, upstream_commit=commit,
               version=source_ref.removeprefix("v") if args.channel == "stable" else "")
    elif args.operation == "check":
        output(should_build=should_build(
            api, args.channel, args.ref, args.commit, args.state,
            os.environ["GITHUB_EVENT_NAME"],
        ))
    else:
        value = metadata(args.channel, args.ref, args.commit)
        if args.operation == "record":
            write_json(args.state, value)
        else:
            actual = subprocess.check_output(
                ["git", "-C", args.tree, "rev-parse", "HEAD"], text=True
            ).strip()
            if actual != value["upstream_commit"]:
                raise ValueError("Built OpenWrt commit differs from the resolved source")
            directory = Path(args.artifacts)
            write_json(directory / "BUILD-METADATA.json", value)
            files = sorted(p for p in directory.iterdir() if p.name != "SHA256SUMS.txt")
            checksums = "".join(f"{digest(path)}  ./{path.name}\n" for path in files)
            (directory / "SHA256SUMS.txt").write_text(checksums, encoding="utf-8")


if __name__ == "__main__":
    main()
