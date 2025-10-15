#!/usr/bin/env python
# py39 $SCRIPTS/standalone/jenkins.py 5456 -b 3
import json
from dataclasses import dataclass
from typing import Any, Optional

import sys
import os

if os.environ.get("HOME") not in sys.path:
    sys.path.append(os.environ.get("HOME"))

try:
    from rich.traceback import install

    install(show_locals=True, width=os.getenv("COLUMNS", 170))
    from rich import print as pprint
except:
    pprint = print
    pass
# import debug
import time
from argparse import ArgumentParser
import subprocess as sp
import requests
from datetime import timedelta, datetime

username = os.environ.get("JENKINS_USERNAME", "")
token = os.environ.get("JENKINS_TOKEN", "")
print(f"$JENKINS_USERNAME: {username}", f"$JENKINS_TOKEN: {token}", sep="\n")


def sleep(sec):
    print(f"Sleeping {sec}s...")
    time.sleep(sec)


@dataclass
class Commit:
    sha: str
    message: str


@dataclass
class Branch:
    sha: str
    name: str


@dataclass
class Build:
    number: int
    url: str


@dataclass
class JenkinsJob:
    actions: list[dict]
    artifacts: list
    building: bool
    description: str
    displayName: str
    duration: int
    estimatedDuration: int
    executor: Any
    fullDisplayName: str
    id: int
    keepLog: bool
    number: int
    pr_id: int
    queueId: int
    result: str
    timestamp: int
    url: str
    changeSets: list
    culprits: list
    nextBuild: Optional[Build]
    previousBuild: Optional[Build]
    shortDescription: str = ""
    commit: Commit = None
    branch: Branch = None

    def __post_init__(self):
        if self.nextBuild:
            self.nextBuild = Build(**self.nextBuild)
        if self.previousBuild:
            self.previousBuild = Build(**self.previousBuild)
        for action in self.actions:
            if "causes" in action:
                causes = action["causes"]
                for cause in causes:
                    if "shortDescription" in cause:
                        self.shortDescription = cause["shortDescription"]
            elif (
                "buildsByBranchName" in action
                and f"PR-{self.pr_id}" in action["buildsByBranchName"]
            ):
                build = action["buildsByBranchName"][f"PR-{self.pr_id}"]
                # buildNumber, buildResult, marked, revision
                if buildResult := build.get("buildResult"):
                    print("\nbuildResult!", buildResult, end="\n\n")
                # other_marked = {k:v for k,v in build['marked'].items() if k != 'SHA1'}
                # if other_marked:
                #     print(f'\nOther marked! {other_marked}\n')
                self.commit = Commit(build["marked"]["SHA1"], "")
                branch, *branches = build["marked"]["branch"]
                self.branch = Branch(branch["SHA1"], branch["name"])
                if branches:
                    print(f"\nOther branches! {branches}\n")

    def pretty(self) -> str:
        now = datetime.now()
        start_time = datetime.fromtimestamp(self.timestamp // 1000)
        estimated_duration_td = timedelta(seconds=self.estimatedDuration // 1000)
        estimated_finish_time = start_time + estimated_duration_td
        return "\n".join([
            "\n",
            f"─" * 80,
            f"{self.fullDisplayName}",
            f"shortDescription: {self.shortDescription!r}",
            f"number: {self.number}",
            f"building: {self.building}",
            f"result: {self.result}",
            f"timestamp (start time): {start_time}",
            f"estimatedDuration: {estimated_duration_td}",
            f"estimated finish time: {estimated_finish_time} ({estimated_finish_time - now} left)",
            f"commit: {self.commit}",
            f"branch: {self.branch}",
            f"─" * 80,
        ])

    @classmethod
    def from_url(cls, job, build: int) -> "JenkinsJob":
        print(f"Fetching {build = }...")
        response = requests.get(
            f"http://jmaster-ssbu-01.rdlab.local/job/allot_secure_team_multiproject/job/{job}/{build}/api/python?pretty=true",
            auth=(username, token),
        )
        data = eval(response.text)

        data = remove_items_recursive(data, lambda k, v: k in ("_class",) or v == {})

        return cls(**data, pr_id=int(job.removeprefix("PR-")))


def loop(job: JenkinsJob):
    print(f"Started loop. Job:")
    pprint(job.pretty())
    unchanged_iterations = 0
    while job.nextBuild:
        job = JenkinsJob.from_url(
            "PR-" + str(job.pr_id).removeprefix("PR-"), job.nextBuild.number
        )
    last_job = job
    while True:
        print()
        if job.nextBuild:
            job = JenkinsJob.from_url(
                "PR-" + str(job.pr_id).removeprefix("PR-"), job.nextBuild.number
            )
        else:
            job = JenkinsJob.from_url(
                "PR-" + str(job.pr_id).removeprefix("PR-"), job.number
            )
        if job == last_job:
            print("Nothing changed.")
            unchanged_iterations += 1
            if unchanged_iterations % 10 == 0:
                pprint(job.pretty())
            sleep(30)
            continue
        diff = {
            k: v
            for k, v in job.__dict__.items()
            if v != last_job.__dict__[k] and not k.startswith("_")
        }
        pprint(diff)
        unchanged_iterations = 0
        last_job = job
        print(f"\x1b[1;95mUpdate!\x1b[0m")
        pprint(job.pretty())

        # if pr:
        #     last_build = pr.get_last_build()
        #
        #     print(last_build.full_display_name)
        #     for attr in ['building', 'estimated_duration']:
        #         print(f'\tlast_build.{attr}: {getattr(last_build, attr)}')
        #     test_report = last.get_test_report()
        #     for attr in ['empty', 'fail_count', 'pass_count', 'skip_count']:
        #         print(f'\ttest_report.{attr}: {getattr(test_report, attr)}')
        #     print()
        sleep(10)


def remove_items_recursive(obj, condition):
    if isinstance(obj, dict):
        tmp = {}
        for k in obj.keys():
            if condition(k, obj[k]):
                continue
            tmp[k] = remove_items_recursive(obj[k], condition)
        return tmp

    elif isinstance(obj, list):
        tmp = []
        for v in obj:
            if condition("", v):
                continue
            tmp.append(remove_items_recursive(v, condition))
        return tmp

    return obj


def main():
    argparser = ArgumentParser()
    argparser.add_argument("--pr", required=False)
    argparser.add_argument("--job", required=False)
    argparser.add_argument("-u", "--username")
    argparser.add_argument("-t", "--token")
    argparser.add_argument("-b", "--build", type=int, default=1)
    ns = argparser.parse_args()

    _username = ns.username
    _token = ns.token
    build = ns.build
    if not _username or not _token:
        if not os.getenv("BW_SESSION"):
            print("Running bw unlock --raw...")
            session_password = (
                sp.Popen("bw unlock --raw".split(), stdout=sp.PIPE)
                .stdout.read()
                .decode()
            )
            print(f'export BW_SESSION="{session_password}"')
            os.environ["BW_SESSION"] = session_password
        print("Running bw get item jenkins-ssbu --pretty...")
        out = (
            sp.Popen("bw get item jenkins-ssbu --pretty".split(), stdout=sp.PIPE)
            .stdout.read()
            .decode()
        )
        bw_jira = json.loads(out)
        _username = bw_jira["login"]["username"]
        _token = bw_jira["fields"][0]["value"]
    global username
    global token
    username = _username
    token = _token
    if ns.pr:
        pr = "PR-" + str(ns.pr).removeprefix("PR-")
        job = JenkinsJob.from_url(pr, build)
    elif ns.job:
        job = JenkinsJob.from_url(ns.job, build)
    else:
        raise ValueError("Either --pr or --job must be specified")
    loop(job)


if __name__ == "__main__":
    main()
