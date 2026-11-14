"""Small, standard-library helpers shared by the build and release entry points."""

import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time


UPSTREAM = "https://git.openwrt.org/openwrt/openwrt.git"
SHA = re.compile(r"^[0-9a-f]{40}$")
VERSION = re.compile(r"^v([0-9]+)\.([0-9]+)\.([0-9]+)$")
WORKFLOWS = {
    "main": (".github/workflows/ci.yml", "Build (mainline AN8855)"),
    "stable": (".github/workflows/stable-latest.yml", "Build (stable-latest)"),
}


class APIError(RuntimeError):
    def __init__(self, message, status=None):
        super().__init__(message)
        self.status = status


class GitHub:
    """Use the runner's official gh client for authentication and safe redirects."""

    def __init__(self, repository):
        if not re.fullmatch(r"[\w.-]+/[\w.-]+", repository):
            raise ValueError("Invalid GitHub repository")
        self.repository = repository
        self.base = f"repos/{repository}"

    def request(self, path, method="GET", data=None, binary=False):
        args = ["gh", "api", path, "--method", method]
        if binary:
            args += ["-H", "Accept: application/octet-stream"]
        else:
            args += ["-H", "Accept: application/vnd.github+json"]
        payload = None
        if data is not None:
            args += ["--input", "-"]
            payload = json.dumps(data).encode()
        for attempt in range(3):
            result = subprocess.run(args, input=payload, capture_output=True, timeout=180)
            if result.returncode == 0:
                if binary:
                    return result.stdout
                return json.loads(result.stdout) if result.stdout.strip() else None
            error = result.stderr.decode(errors="replace")
            match = re.search(r"HTTP (\d{3})", error)
            status = int(match[1]) if match else None
            if method == "GET" and attempt < 2 and (
                status is None or status == 429 or status >= 500
            ):
                time.sleep(2 ** attempt)
                continue
            raise APIError(f"GitHub {method} {path}: {error.strip()}", status)
        raise AssertionError("unreachable")

    def pages(self, path, key=None):
        separator = "&" if "?" in path else "?"
        for page in range(1, 1001):
            result = self.request(f"{path}{separator}per_page=100&page={page}")
            items = result[key] if key else result
            yield from items
            if len(items) < 100:
                return
        raise RuntimeError("GitHub pagination limit exceeded")

    def optional(self, path):
        try:
            return self.request(path)
        except APIError as error:
            if error.status == 404:
                return None
            raise

    def upload(self, tag, paths):
        subprocess.run(
            ["gh", "release", "upload", tag, "--repo", self.repository, "--clobber",
             *map(str, paths)],
            check=True, timeout=1800,
        )


def version_key(tag):
    match = VERSION.fullmatch(tag)
    if not match:
        raise ValueError(f"Not a formal OpenWrt version: {tag}")
    return tuple(map(int, match.groups()))


def output(**values):
    text = "".join(f"{key}={str(value).lower() if isinstance(value, bool) else value}\n"
                   for key, value in values.items())
    print(text, end="")
    if os.environ.get("GITHUB_OUTPUT"):
        with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as stream:
            stream.write(text)


def write_json(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def digest(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def artifact_name(channel, run_id, attempt):
    return f"firmware-{channel}-{int(run_id)}-{int(attempt)}"


def validate_metadata(value):
    if value.get("schema_version") != 1 or value.get("channel") not in WORKFLOWS:
        raise ValueError("Invalid build metadata schema or channel")
    if not re.fullmatch(r"[\w.-]+/[\w.-]+", value.get("repository", "")):
        raise ValueError("Invalid build repository")
    for key in ("upstream_commit", "repository_commit"):
        if not SHA.fullmatch(value.get(key, "")):
            raise ValueError(f"Invalid {key}")
    for key in ("run_id", "run_attempt", "run_number"):
        if type(value.get(key)) is not int or value[key] < 1:
            raise ValueError(f"Invalid {key}")
    if value["channel"] == "stable":
        version_key(value["upstream_ref"])
    elif value.get("upstream_ref") != "main":
        raise ValueError("Mainline metadata must reference main")
    return value


def metadata(channel, source_ref, commit):
    return validate_metadata({
        "schema_version": 1,
        "repository": os.environ["GITHUB_REPOSITORY"],
        "channel": channel,
        "upstream_ref": source_ref,
        "upstream_commit": commit,
        "repository_commit": os.environ["GITHUB_SHA"],
        "run_id": int(os.environ["GITHUB_RUN_ID"]),
        "run_attempt": int(os.environ["GITHUB_RUN_ATTEMPT"]),
        "run_number": int(os.environ["GITHUB_RUN_NUMBER"]),
    })


def successful_run(api, channel, run_id, allow_skipped=False):
    """Never infer a real build from the workflow's overall success alone."""
    run = api.request(f"{api.base}/actions/runs/{int(run_id)}")
    default = api.request(api.base)["default_branch"]
    path, job_name = WORKFLOWS[channel]
    allowed_events = {"schedule", "workflow_dispatch"}
    if channel == "main":
        allowed_events.add("push")
    if (
        run["repository"]["full_name"] != api.repository
        or run["head_repository"]["full_name"] != api.repository
        or run["head_branch"] != default
        or run["path"].split("@")[0] != path
        or run["event"] not in allowed_events
        or run["status"] != "completed"
        or run["conclusion"] != "success"
        or not SHA.fullmatch(run["head_sha"])
    ):
        raise ValueError("Not a successful trusted default-branch build run")
    jobs = list(api.pages(
        f"{api.base}/actions/runs/{run['id']}/attempts/{run['run_attempt']}/jobs", "jobs"
    ))
    builds = [job for job in jobs if job["name"] == job_name]
    if len(builds) != 1:
        raise ValueError("Expected exactly one firmware build job")
    if allow_skipped and builds[0]["conclusion"] == "skipped":
        return None
    if builds[0]["status"] != "completed" or builds[0]["conclusion"] != "success":
        raise ValueError("The actual firmware build job did not succeed")
    return run


def match_run(value, api, run):
    validate_metadata(value)
    expected = {
        "repository": api.repository,
        "repository_commit": run["head_sha"],
        "run_id": run["id"],
        "run_attempt": run["run_attempt"],
        "run_number": run["run_number"],
    }
    if any(value[key] != item for key, item in expected.items()):
        raise ValueError("Build metadata does not match the successful workflow run")
