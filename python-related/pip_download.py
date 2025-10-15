#!python3
import requests
import re
import os
import sys

pkg, dest = sys.argv[1:3]
print(f"pkg: {pkg} | dest: {dest}")


def download(link):
    print(os.system(f'cd "{dest}" && wget "{link}" --no-check-certificate'))


url = f"https://pypi.org/project/{pkg}/#files"
print(f"url: ", url)
response = requests.get(url)
txt = response.text
if not response.ok:
    print(f"ERROR response not ok. txt:")
    print(txt)
    sys.exit(1)
print("response OK")

links = list(
    map(
        lambda m: m.group(),
        re.finditer(r'(?<=href=")https://files.pythonhosted.org[^"]+', txt),
    )
)
print(f"found {len(links)} links")
wheel_links = [link for link in links if link.endswith(".whl")]
if not wheel_links:
    print("ERROR no wheel links")
    sys.exit(1)

if len(wheel_links) == 1:
    print("found 1 wheel links")
    wheel_link = wheel_links[0]
    download(wheel_link)

else:
    print(f"found {len(wheel_links)} wheel links, which one to download?")
    print(wheel_links)
    index = int(input("index:  "))
    download(wheel_links[index])
sys.exit(0)
