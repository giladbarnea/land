#!/usr/bin/env python3.12
import os
import re
import shlex
import subprocess as sp
import sys
from argparse import ArgumentParser, ArgumentDefaultsHelpFormatter
from pathlib import Path

import semver

argparser = ArgumentParser(formatter_class=ArgumentDefaultsHelpFormatter)
argparser.add_argument(
    "dist",
    action="store_const",
    const="dist/*",
    default="dist/*",
    help='Files to upload to repository, default "dist/*"',
)
argparser.add_argument("-n", "--dry-run", type=bool)
argparser.add_argument("-r", "--repository", default="pypi", help="Example: testpypi")
parsed_args = argparser.parse_args()
dry_run = parsed_args.dry_run
repository = parsed_args.repository
distribution = parsed_args.dist

_print = lambda *args, **kwargs: print("\n", *args, **kwargs, end="\n\n")


def confirm(prompt="Continue?") -> bool:
    answer = ""
    while answer not in ("y", "n", "q"):
        answer = input(f"\n{prompt} [y/n/q]\t").lower()
        if answer == "q":
            sys.exit()
        if answer == "y":
            return True
        if answer == "n":
            return False


def bump_version(setup_py_content, version, bumped):
    replaced = setup_py_content.replace(version, str(bumped), 1)
    before, after = map(
        str.strip,
        set(setup_py_content.splitlines()).symmetric_difference(set(replaced.splitlines())),
    )
    if dry_run:
        _print(
            "dry run: would have made the following changes to setup.py;",
            "before:",
            before,
            "after:",
            after,
            sep="\n",
        )
        return
    with open("./setup.py", "w") as f:
        f.write(replaced)
    _print(f"Replaced {before} with {after} successfully")


def main():
    if not os.getenv("VIRTUAL_ENV", None):
        if not confirm(
            "I want to run twine, but no activated virtual env detected, continue anyway?"
        ):
            sys.exit()

    if sp.getstatusoutput("command -v twine")[0] != 0:
        sys.exit(
            "`twine` command unavailable, install twine (python package) and try again"
        )
    if sp.getoutput(shlex.split("git status -s")):
        _print("Some uncommitted changes:")
        os.system("git status")
        if not confirm("Publish anyway?"):
            sys.exit()
    with open("./setup.py") as f:
        setup_py_content = f.read()
    version = re.search(
        r'(?<=version)[\'":\s=]+(\d+[.\d]+)', setup_py_content
    ).groups()[0]
    parsed = semver.VersionInfo.parse(version)
    bumped = parsed.bump_patch()
    if bumped.patch == 10:
        bumped = parsed.bump_minor()
    if confirm(f"Current version is {version}, bump to {bumped}?"):
        bump_version(setup_py_content, version, bumped)

    if Path("./dist").is_dir() or Path("./build").is_dir():
        cmd = "rm -rf dist build"
        if (
            confirm(f"Run '{cmd}'?")
            and (status := os.system(cmd)) != 0
            and not confirm(f"'{cmd}' failed, continue anyway?")
        ):
            sys.exit(status)
    else:
        _print("dist and/or build dirs don't exist")

    py_exec = sp.getoutput("which python3")
    if confirm(
        f"run 'python3 setup.py sdist bdist_wheel'? python executable is {py_exec!r}"
    ):
        if status := os.system("python3 setup.py sdist bdist_wheel"):
            sys.exit(status)
    if not confirm(f"run 'twine upload -r {repository} {distribution}'?"):
        sys.exit()
    # asks for password
    sys.exit(os.system(f"twine upload -r {repository!r} {distribution}"))


if __name__ == "__main__":
    main()
