#!/usr/bin/env python3.12
import builtins
from datetime import datetime as dt
from pathlib import Path

# from dateutil.parser import parse as parsedate
import click
import requests
from rich import print
from functools import cache

import os
import json
import hashlib
import functools


# https://techgaun.github.io/active-forks/index.html


@click.command()
@click.argument("repo")
def main(repo):
    repo = repo.removeprefix("https://").removeprefix("www.").removeprefix("github.com/")
    repodata = parse_fork_dates(github_api_get("repos/" + repo).json())
    commits_num = len(github_api_get(f"repos/{repo}/commits").json())
    branches_num = len(github_api_get(f"repos/{repo}/branches").json())
    forks = github_api_get(
        f"repos/{repo}/forks", params={"sort": "stargazers", "per_page": 100}
    ).json()
    ahead_forks, even_forks, behind_forks, longest_full_name_length = (
        group_forks_by_ahead_even_behind(forks, repodata)
    )
    print_original_repo_stats(branches_num, commits_num, repo, repodata)
    # print(repodata)
    # breakpoint()
    print(f"[bright_green bold]ahead_forks: {len(ahead_forks)}")
    for fork in sorted(
        ahead_forks, key=lambda _f: _f["stargazers_count"], reverse=True
    ):
        print(
            f"[on rgb(0,40,0)][rgb(0,215,0)]{pformat_fork(fork, longest_full_name_length)}"
        )
        print(get_fork_description(fork), end="\n\n")

    print(f"[bright_white bold]even_forks: {len(even_forks)}")
    for fork in sorted(even_forks, key=lambda _f: _f["stargazers_count"], reverse=True):
        print(pformat_fork(fork, longest_full_name_length))
        print(get_fork_description(fork), end="\n\n")

    print(f"[bright_yellow bold]behind_forks: {len(behind_forks)}")
    for fork in sorted(
        behind_forks, key=lambda _f: _f["stargazers_count"], reverse=True
    ):
        print(
            f"[on rgb(40,40,0)][rgb(215,215,0)]{pformat_fork(fork, longest_full_name_length)}"
        )
        print(get_fork_description(fork), end="\n\n")


def disk_cache(func):
    cache_dir = (Path.home() / ".cache/bashscripts")
    os.makedirs(cache_dir, exist_ok=True)
    cache_path = os.path.join(cache_dir, "getforks.json")

    @functools.wraps(func)
    def wrapper(**kwargs):
        messages = kwargs["messages"]
        user_message: str = messages[1]["content"]
        # key = json.dumps({"kwargs": kwargs}, sort_keys=True)
        key = user_message
        hash_key = hashlib.sha256(key.encode("utf-8")).hexdigest()

        try:
            with open(cache_path, "r") as f:
                cache = json.load(f)
        except (FileNotFoundError, json.JSONDecodeError):
            cache = {}

        if hash_key in cache:
            return cache[hash_key]

        # Call the function and store the result in cache
        result = func(**kwargs)
        cache[hash_key] = result
        try:
            with open(cache_path, "w") as f:
                json.dump(cache, f, indent=4)
        except Exception as e:
            print(f"Failed to write cache: {e!r}")

        return result

    return wrapper


def group_forks_by_ahead_even_behind(forks, repodata):
    ahead_forks = []
    even_forks = []
    behind_forks = []
    longest_full_name_length = 0
    for i, fork in enumerate(forks[:]):
        longest_full_name_length = max(len(fork["full_name"]), longest_full_name_length)
        fork[i] = parse_fork_dates(fork)
        if fork["pushed_at"] > repodata["pushed_at"]:
            ahead_forks.append(fork)
        elif fork["pushed_at"] == repodata["pushed_at"]:
            even_forks.append(fork)
        else:
            behind_forks.append(fork)
    return ahead_forks, even_forks, behind_forks, longest_full_name_length


def print_original_repo_stats(branches_num, commits_num, repo, repodata):
    print(f"[bright_white bold]{repo}:")
    builtins.print(f"\t{repodata['description']}")
    print(f"\t{commits_num:,} commits, {branches_num:,} branches")
    print(
        "\t"
        + "\n\t".join([
            f"{k:12} {v}"
            for k, v in repodata.items()
            if k.endswith("_at") or k in ("forks", "open_issues", "watchers")
        ])
    )


def parse_fork_dates(_fork):
    for _k, _v in _fork.items():
        if _k.endswith("_at"):
            _fork[_k] = dt.fromisoformat(_v.removesuffix("Z"))
    return _fork


def pformat_fork(fork, padding) -> str:
    return f"{fork['full_name']:{padding}} | Last push: {fork['pushed_at']} | ⭐️: {fork['stargazers_count']} | Link: {fork['html_url']}"


def get_fork_description(fork) -> str:
    return fork["description"] or ("🤖 " + summarize_readme(fork))


def summarize_readme(fork):
    from base64 import b64decode

    client = get_openai_client()
    # https://api.github.com/repos/OWNER/REPO/contents/PATH
    readme_content: str = b64decode(
        github_api_get(f"repos/{fork['full_name']}/contents/README.md")
        .json()["content"]
        .encode("utf-8")
    ).decode("utf-8")
    return cacheable_summary(client, readme_content)


def cacheable_summary(client, readme_content):
    messages = [
        {
            "role": "system",
            "content": "You are a masterful summarizer, able to summarize a code repository's README in a single sentence while capturing the essence of the project. The sentence should start with an action verb.",
        },
        {"role": "user", "content": readme_content},
    ]
    kwargs = dict(
        model="gpt-4-turbo-2024-04-09",
        messages=messages,
        stream=False,
        temperature=0.0,
    )
    return complete(**kwargs)


def github_api_get(url, headers={}, params={}):
    return requests.get(
        "https://api.github.com/" + url,
        headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {github_token()}",
            "X-GitHub-Api-Version": "2022-11-28",
            **headers,
        },
        params=params,
    )


@cache
def github_token():
    return Path.home().joinpath(".github-token").read_text().strip()


@cache
def get_openai_client():
    from openai import Client

    api_key = Path.home().joinpath(".openai-api-key").read_text().strip()
    return Client(api_key=api_key)


@disk_cache
def complete(**kwargs) -> str:
    client = get_openai_client()
    response = client.chat.completions.create(**kwargs)
    return response.choices[0].message.content


if __name__ == "__main__":
    main()
