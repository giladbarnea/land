#!/usr/bin/env python3
"""
path/to/download_vid.py "https://..." [--out="out.mp4"]
OR
path/to/download_vid.py "https://..." --last=923 [--out="out.mp4"]
OR
path/to/download_vid.py "https://..." --start=0 --stop=100 [--out="out.mp4"]
"""

import os
import re
import sys
from multiprocessing import Process
from pathlib import Path
from time import time
import click
import requests
from igit.util.clickex import unrequired_opt
# from functools import partial

# if list(Path('.').glob('*.ts')):
#     sys.exit('working directory needs to have no .ts files')
from igit_debug import ExcHandler


def geturl(part):
    return VID_PART_RE.sub(str(part), link, count=1)


def prompt_cleanup(outdir=None):
    if outdir:
        if input(f"rm {outdir}/*.ts? y/n\t") == "y":
            os.system(f"rm {outdir}/*.ts")
    else:
        print("OUT DIR ISNT CLEAN!")
    if input(f'pkill --signal=9 --full ".*{Path(__file__).stem}.*"? y/n\t') == "y":
        os.system(f'pkill --signal=9 --full ".*{Path(__file__).stem}.*"')


def find_last_part(part_min=1, part_max=10000):
    print(f"part_min: {part_min}, part_max: {part_max}")
    part_prev = None
    part_next = None
    while (res := requests.get(geturl(part_min))).ok:
        results[part_min] = res
        part_next = (part_max + part_min) // 2
        if part_min == part_next:
            print(f"last part: {part_min}")
            return part_min
        print(f"\tpart_min ok: {part_min}, trying next: {part_next}")
        part_prev = part_min
        part_min = part_next
    else:
        print(f"\tpart_min too high: {part_min}. part_prev: {part_prev}")
        if part_prev is None:
            # while didn't occur even once (passed part_min was too high to begin with)
            return find_last_part(part_min // 2, part_min)

        if part_min - 1 == part_prev:
            # that's it
            print(f"last part: {part_prev}")
            return part_prev

        # part_prev is ok (because it's what part_min was when req was done),
        # but part_next is too high. try mid-way
        part_min = (part_prev + part_next) // 2
        print(
            f"\t{part_prev} is ok, but {part_next} is too high. working between {part_prev} and {part_next}: {part_min}"
        )
        while not (res := requests.get(geturl(part_min))).ok:
            # go lower as long as it's too high
            part_next = (part_prev + part_min) // 2
            if part_min == part_next:
                print(f"last part: {part_min}")
                return part_min
            print(f"\tpart_min is too high: {part_min}, trying next: {part_next}")
            part_min = part_next
        else:
            results[part_min] = res
            # now part_min is ok; try the last value that was too high
            part_max = part_min + (part_min - part_prev) + 1
            print(f"\t{part_min} is ok, but {part_max} is too high. recursing...")
            return find_last_part(part_min=part_min, part_max=part_max)


def download_files_range(start, stop, outdir: Path):
    for i in range(start, stop):
        progress = f"{round(((i - start + 1) / (stop - start)) * 100, 2)}%"
        file = outdir / f"{str(i).rjust(4, '0')}.ts"
        if i in results:
            res = results[i]
        else:
            if file.exists():
                print(
                    f"\tdownload_files_range({start}:{stop}) | {file} already existed | progress: {progress}"
                )
                continue
            else:
                res = requests.get(geturl(i))

        with open(file, mode="w+b") as f:
            f.write(res.content)
        print(
            f"\tdownload_files_range({start}:{stop}) | wrote {file} success | progress: {progress}"
        )


def concat_files(out: Path):
    # out = str(out)
    print(f"concat_files({out})")
    files = "|".join(map(str, sorted(out.parent.glob("*.ts"))))
    os.system(f'ffmpeg -i "concat:{files}" -c copy -bsf:a aac_adtstoasc "{out}"')
    print(f"concat_files({out}) | returning")


@click.command()
@click.argument("url")
@unrequired_opt("--start", default=0)
@unrequired_opt("--stop", type=int, default=None)
@unrequired_opt("--out", default="out.mp4", help="out file name")
@unrequired_opt("--proc", "max_processes", default=30, help="max processes")
def main(url, start=0, stop=None, out="out.mp4", max_processes=30):
    print(f"start: {start}, stop: {stop}, out: {out}, max_processes: {max_processes}")
    global link
    link = url
    global VID_PART_RE
    VID_PART_RE = re.compile(r"\d+(?=\.ts)")
    global results
    results = dict()
    if (out := Path(out)).exists():
        if input(f"{out} exists, overwrite? y/n\t") == "y":
            out.unlink()
        else:
            sys.exit("aborting")

    outdir = out.parent
    if not outdir.exists():
        if input(f"dir {outdir} does not exist, mkdir? y/n\t") == "y":
            os.system(f"mkdir {out.absolute()}")
            if not outdir.exists():
                sys.exit(f"failed mkdir {out.absolute()}")
        else:
            sys.exit("aborting")
    if stop is None:
        # download everything
        stop = int(find_last_part()) + 1
    else:
        if not requests.get(geturl(stop)).ok:  # sanity
            sys.exit(f"{geturl(stop)} didnt work (geturl({stop}))")

    starttime = time()
    max_processes = min(max_processes, stop - start)
    print(f"max_processes: {max_processes}")
    processes = []
    for process_i in range(max_processes):
        # split to max_processes concurrent
        _start = start + (stop // max_processes) * process_i
        _stop = start + (stop // max_processes) * (process_i + 1)
        print(f"process_i: {process_i} | download_files_range({_start}:{_stop})")

        p = Process(target=download_files_range, args=(_start, _stop, outdir))
        processes.append(p)
        p.start()
    else:
        # remainder (30 processes over 301 parts -> 30th proc downloads only 301th part)
        # TODO: this takes a proportionally bigger chunk
        _start = (stop // max_processes) * max_processes
        _stop = _start + stop % max_processes
        print(f"process_i: {max_processes} | download_files_range({_start}:{_stop})")
        p = Process(target=download_files_range, args=(_start, _stop, outdir))
        processes.append(p)
        p.start()
    for proc in processes:
        proc.join()
    endtime = time()
    print(
        f"\nDONE\n{stop - start} files over {max_processes} processes took {int(endtime - starttime)}s ({int(endtime - starttime) / stop - start}s per file)\n"
    )
    concat_files(out)
    prompt_cleanup(outdir)


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"{ExcHandler(e).shorter()}")
        prompt_cleanup()
