#!/usr/bin/env python3.12
import argparse
import ast
import inspect
import os
import sys
import textwrap
from collections.abc import Callable, Generator
from fnmatch import fnmatch
from pathlib import Path
from typing import Annotated, Any, NewType

# We need both or neither, so we bunch them in a single try-except block.
try:
    from annotated_types import Predicate
    from typeguard import typechecked
except ImportError:
    Predicate = lambda func: func  # type: ignore # noqa: E731
    typechecked = lambda func: func  # type: ignore # noqa: E731

if sys.version_info[:2] >= (3, 13):
    from typing import TypeIs
else:
    try:
        from typing_extensions import TypeIs
    except ImportError:
        from typing import TypeGuard

        TypeIs = TypeGuard  # Bug: TypeGuard is not subscriptable

# sudo fd -H -I '.*' -t f / --format "{/}" | awk -F. '/\./ && index($0,".")!=1 {ext=tolower($NF); if (length(ext) <= 10 && ext ~ /[a-z]/ && ext ~ /^[a-z0-9]+$/) print ext}' > /tmp/exts.txt  # For all file names which have a name and an extension, write to file lowercased extensions which are alphanumeric, <= 10 characters long, and have at least one letter
# rg --type-list | py.eval "[print(extension) for line in lines for ext in line.split(': ')[1].split(', ') if (extension:=ext.removeprefix('*.').removeprefix('.*').removeprefix('.').removeprefix('*').lower()).isalnum()]" --readlines >> /tmp/exts.txt
# sort -u -o /tmp/exts.txt /tmp/exts.txt
SUPPORTED_EXTENSIONS = []
TPath = NewType("TPath", str)


def __is_glob(path) -> bool:
    if not isinstance(path, str):
        return False
    return any(c in path for c in "*?![]")


def __is_extension(name: str) -> bool:
    return name.startswith(".") and os.path.sep not in name


TGlob = Annotated[NewType("TGlob", str), Predicate(__is_glob)]
TExtension = Annotated[NewType("TExtension", str), Predicate(__is_extension)]

"""
TExclusion is a union of:
- TPath: A string representing a file or directory path. Matches by substring (e.g., "foo/bar" matches "foo/bar/baz").
- TGlob: A string representing a glob pattern.
- Callable[[TPath | TGlob], bool]: A function that takes a TPath or TGlob and returns a boolean.
"""
TExclusion = TPath | TGlob | Callable[[TPath | TGlob], bool]


DEFAULT_EXCLUSIONS: list[TExclusion] = [
    lambda x: x.endswith("egg-info"),
    "build",
    "bin",
    "dist",
    "node_modules",
    lambda x: x.startswith("."),
    lambda x: "cache" in str(x).lower(),
    # Build artifacts and dependencies
    "target",
    "vendor",
    "out",
    "coverage",
    # IDE and editor files
    "*.swp",
    "*.swo",
    # Language-specific
    "*.class",
    "*.o",
    "*.so",
    "*.dylib",
    # Logs and temporary files
    "logs",
    "*.log",
    "*.tmp",
    # Environment and secrets
    "secrets",
    "*.key",
    "*.pem",
]


@typechecked
def _describe_predicate(pred: TExclusion) -> str:
    if isinstance(pred, str):
        return pred

    pred_closure_vars = inspect.getclosurevars(pred)
    if pred_closure_vars.unbound == {"startswith"}:
        startswith = pred.__code__.co_consts[1]
        return f"paths starting with {startswith!r}"
    if pred_closure_vars.unbound == {"endswith"}:
        endswith = pred.__code__.co_consts[1]
        return f"paths ending with {endswith!r}"
    if " in " in inspect.getsource(pred):
        contains = pred.__code__.co_consts[1]
        return f"paths containing {contains!r}"
    raise ValueError(f"Unknown predicate: {pred}")


@typechecked
def _is_glob(path) -> TypeIs[TGlob]:
    return __is_glob(path)


@typechecked
def _is_extension(name: str) -> TypeIs[TExtension]:
    return __is_extension(name)


@typechecked
def print_single_file(
    file_path: Path,
    *,
    relative_to: Path | None = None,
    only_headers: bool,
    tag: str = "xml",
) -> None:
    """Print a single file's contents with header."""

    # Only print the relative path if the file is a subpath of the relative_to path.
    if relative_to and Path(relative_to).resolve() in [
        *Path(file_path).resolve().parents,
        Path(file_path).resolve(),
    ]:
        relative_path = os.path.relpath(file_path, start=relative_to)
    else:
        relative_path = str(file_path)

    try:
        with open(file_path, "r") as f:
            file_content = f.read().strip()
    except UnicodeDecodeError:
        with open(file_path, "rb") as f:
            file_content = f.read().strip()

    if not file_content:
        import logging

        logging.getLogger(__name__).warning(
            "Shouldn't happen: %s is empty, but `depth_first_walk` should have filtered it out before this function was called. Investigation log: reproduced whenthere was an empty hi.md which matched and --include-empty was specified.",
            file_path,
        )
        return None

    if only_headers:
        print(relative_path)
    else:
        if tag == "xml":
            template = "\n<{relative_path}>\n{file_content}\n</{relative_path}>\n\n"
        elif tag == "md":
            separator = "=" * (len(relative_path) + 8)
            template = f"\n# FILE: {{relative_path}}\n{separator}\n{{file_content}}\n\n---\n"
        else:
            raise ValueError(f"Unsupported tag format: {tag}")

        print(template.format(relative_path=relative_path, file_content=file_content))


@typechecked
def print_files_contents(
    root_dir,
    *,
    extensions: list[TExtension],
    exclude: list[TExclusion],
    only_headers: bool,
    include_empty: bool,
    tag: str = "xml",
) -> None:
    for root, _dirs, files in depth_first_walk(
        root_dir, exclude=exclude, include_empty=include_empty
    ):
        for file in files:
            # Check exclusions first
            if is_excluded(file, exclude=exclude):
                continue

            # Try to match the file against the extensions
            if any(
                fnmatch(file, extension_pattern)
                if _is_glob(extension_pattern)
                else file.endswith("." + extension_pattern.removeprefix("."))
                for extension_pattern in extensions
            ):
                file_path = Path(os.path.join(root, file))
                print_single_file(
                    file_path,
                    relative_to=root_dir,
                    only_headers=only_headers,
                    tag=tag,
                )


@typechecked
def depth_first_walk(
    root_dir, *, exclude: list[TExclusion], include_empty: bool
) -> Generator[tuple[Path, list, list], Any, None]:
    def _append(_entry):
        if _entry.is_dir():
            dirs.append(_entry.name)
        elif _entry.is_file():
            files.append(_entry.name)

    stack = [root_dir]
    while stack:
        current_dir = Path(stack.pop())
        dirs, files = [], []
        entry: os.DirEntry[str]
        with os.scandir(current_dir) as entries:
            for entry in entries:
                if is_excluded(entry, exclude=exclude):
                    continue
                if include_empty:
                    considered_empty = False
                else:
                    considered_empty = is_empty(entry)

                if considered_empty:
                    continue

                _append(entry)
        dirs.sort(key=str.casefold)
        files.sort(key=str.casefold)
        yield current_dir, dirs, files
        stack.extend(current_dir / d for d in reversed(dirs))


@typechecked
def is_excluded(entry: os.DirEntry[str] | str | TGlob | Path, *, exclude: list[TExclusion]) -> bool:
    path = Path(getattr(entry, "path", entry))
    name = path.name
    stem = path.stem
    entry_is_glob = _is_glob(entry)
    for _exclude in exclude:
        is_glob = entry_is_glob or _is_glob(_exclude)
        if callable(_exclude):
            if _exclude(name) or _exclude(stem) or _exclude(str(path)):
                return True
        elif is_glob:
            if fnmatch(name, _exclude) or fnmatch(str(path), _exclude) or fnmatch(stem, _exclude):
                return True
        elif (
            name == _exclude
            or str(path) == _exclude
            or stem == _exclude
            or (_is_extension(_exclude) and name.endswith(_exclude))
        ):
            return True
        else:
            _exclude_glob = f"*{_exclude}" if _is_extension(_exclude) else f"*{_exclude}*"
            if (
                fnmatch(name, _exclude_glob)
                or fnmatch(str(path), _exclude_glob)
                or fnmatch(stem, _exclude_glob)
            ):
                return True
    return False


@typechecked
def is_empty(entry: os.DirEntry[str] | Path) -> bool:
    """Uses ast and returns True if the file only contains import statements, __all__=... assignment, and/or docstrings."""
    if isinstance(entry, os.DirEntry):
        if entry.is_dir():
            return False
        path = entry.path
    else:  # Path object
        if not entry.is_file():
            return False
        path = entry

    try:
        with open(path, "r") as file:
            content = file.read()
    except UnicodeDecodeError:
        return False

    if not content.strip():
        return True

    try:
        tree = ast.parse(content)
    except SyntaxError:
        return False

    # Files containing only imports, __all__=..., or docstrings are considered empty.
    for node in ast.iter_child_nodes(tree):
        if isinstance(node, (ast.Import, ast.ImportFrom)):
            continue
        elif isinstance(node, ast.Assign):
            targets = node.targets
            if (
                len(targets) == 1
                and isinstance(targets[0], ast.Name)
                and targets[0].id == "__all__"
            ):
                continue
        elif (
            isinstance(node, ast.Expr)
            and isinstance(node.value, ast.Constant)
            and isinstance(node.value.value, str)
        ):
            # This is a string expression (docstring)
            continue
        else:
            return False
    return True


def get_default_extensions() -> list[TExclusion]:
    return [
        ".py",
        ".ts",
        ".tsx",
        ".json",
        ".json*",
        ".html",
        ".ini",
        ".toml",
        ".yaml",
        ".yml",
        ".sh",
        ".zsh"
    ]


def get_doc_extensions() -> list[str]:
    return [".md", ".rst", ".mdx"]


def get_test_exclusions() -> list[TExclusion]:
    return ["tests", "test", "spec.ts", "spec.ts*", "test.ts", "test.ts*"]


def get_lock_exclusions() -> list[TExclusion]:
    return [
        # Python
        "uv.lock",
        "poetry.lock",
        "Pipfile.lock",
        # JavaScript/Node
        "package-lock.json",
        "yarn.lock",
        "pnpm-lock.yaml",
        # Other languages
        "Gemfile.lock",
        "composer.lock",
        "Cargo.lock",
        "go.sum",
        "mix.lock",
    ]


def get_binary_exclusions() -> list[TExclusion]:
    return [
        # Binary files
        "*.pyc",
        "*.pyo",
        "*.pyd",
        "*.exe",
        "*.dll",
        "*.app",
        "*.deb",
        "*.rpm",
        # Archives
        "*.zip",
        "*.tar",
        "*.gz",
        "*.bz2",
        "*.xz",
        "*.7z",
        "*.rar",
        "*.jar",
        "*.war",
        "*.ear",
        # Media files
        "*.png",
        "*.jpg",
        "*.jpeg",
        "*.gif",
        "*.bmp",
        "*.ico",
        "*.svg",
        "*.mp3",
        "*.mp4",
        "*.avi",
        "*.mov",
        "*.wav",
        "*.pdf",  # TODO: Remove this when we support PDFs
        # Database and data files
        "*.db",
        "*.sqlite",
        "*.sqlite3",
        "*.dat",
        "*.bin",
    ]


@typechecked
def read_gitignore_file(gitignore_path: Path) -> list[TExclusion]:
    """Read a gitignore-like file and return list of exclusion patterns."""
    exclusions = []
    try:
        with open(gitignore_path, "r") as f:
            for line in f:
                stripped = line.strip()
                if stripped and not stripped.startswith("#"):
                    exclusions.append(stripped)
    except (FileNotFoundError, UnicodeDecodeError, PermissionError):
        pass
    return exclusions


@typechecked
def get_gitignore_exclusions(paths: list[str]) -> list[TExclusion]:
    """Get exclusions from gitignore files for given paths."""
    exclusions = []

    # Read global git ignore file
    home_config_ignore = Path.home() / ".config" / "git" / "ignore"
    exclusions.extend(read_gitignore_file(home_config_ignore))

    # Read gitignore files for each directory path
    for path_str in paths:
        path = Path(path_str)
        if path.is_dir():
            # Try .gitignore in the directory
            gitignore_path = path / ".gitignore"
            exclusions.extend(read_gitignore_file(gitignore_path))

            # Try .git/info/exclude in the directory
            git_exclude_path = path / ".git" / "info" / "exclude"
            exclusions.extend(read_gitignore_file(git_exclude_path))

    return exclusions


@typechecked
def resolve_exclusions(
    *,
    no_exclude: bool,
    custom_excludes: list[TExclusion],
    include_tests: bool,
    include_lock: bool,
    include_binary: bool,
    no_ignore: bool,
    paths: list[str],
) -> list[TExclusion]:
    """Resolve final exclusion list based on command line arguments."""
    if no_exclude:
        return []

    exclusions = DEFAULT_EXCLUSIONS.copy()
    exclusions.extend(custom_excludes)

    if not include_tests:
        exclusions.extend(get_test_exclusions())

    if not include_lock:
        exclusions.extend(get_lock_exclusions())

    if not include_binary:
        exclusions.extend(get_binary_exclusions())

    if not no_ignore:
        exclusions.extend(get_gitignore_exclusions(paths))
    return exclusions


@typechecked
def resolve_extensions(
    *,
    custom_extensions: list[str],
    no_docs: bool,
) -> list[str]:
    """Resolve final extension list based on command line arguments."""
    if custom_extensions:
        extensions = custom_extensions
    else:
        extensions = get_default_extensions()
        if not no_docs:
            extensions.extend(get_doc_extensions())

    return extensions


def main():
    epilog = textwrap.dedent(f"""
    DEFAULT MATCH CRITERIA
    When -t,--type is unspecified, the following file extensions are matched: {', '.join(resolve_extensions(custom_extensions=[], no_docs=False))}.

    NOTE ABOUT EXCLUSIONS
    Exclusions match rather eagerly, because each specified exclusion is handled like a substring match. For example, 'o/b' matches 'foo/bar/baz'.
    Extension exclusions are stricter, so '.py' matches 'foo.py' but not 'foo.pyc'.
    For more control, use glob patterns; specifying '*o/b' will match 'foo/b' but not 'foo/bar/baz'.
    
    KNOWN ISSUES
    - There is no easy way to include .dotfiles without specifying --no-exclude.
    """)
    parser = argparse.ArgumentParser(
        description="Prints the contents of files in a directory or specific file paths",
        add_help=True,
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=epilog,
    )

    parser.add_argument(
        "paths",
        type=str,
        nargs="*",
        help="Path(s) to one or more directories or files. Defaults to current directory if none specified.",
        default=["."],
    )

    # For UI consistency, uppercase flags are boolean "include" flags.
    parser.add_argument(
        "-T",
        "--include-tests",
        action="store_true",
        help="Include `test` and `tests` directories and spec.ts files.",
    )
    parser.add_argument(
        "-L",
        "--include-lock",
        action="store_true",
        help="Include lock files (e.g. package-lock.json, poetry.lock, Cargo.lock).",
    )
    parser.add_argument(
        "-a",
        "--text",
        "--include-binary",
        "--binary",
        action="store_true",
        dest="include_binary",
        help="Include binary files (e.g. *.pyc, *.jpg, *.zip, *.pdf).",
    )
    parser.add_argument(
        "-d",
        "--no-docs",
        action="store_true",
        help="Exclude `.md`, `.mdx` and `.rst` files. Has no effect if -t,--type is specified.",
    )
    parser.add_argument(
        "-E",
        "--include-empty",
        action="store_true",
        help="Include empty files and files that only contain imports and __all__=... expressions.",
    )
    parser.add_argument(
        "-l", "--only-headers", action="store_true", help="Print only the file paths."
    )
    parser.add_argument(
        "-t",
        "--type",
        type=str,
        default=[],
        help="Match only files with the given extensions (e.g. 'py', '.py') or glob patterns (e.g. '*py*', '*.pyc?'). Can be specified multiple times.",
        action="append",
    )
    parser.add_argument(
        "-x",
        "--exclude",
        type=str,
        help="Exclude files or directories whose path contains the given name/path or matches the given glob. Can be specified multiple times. By default, excludes "
        + ", ".join(map(_describe_predicate, DEFAULT_EXCLUSIONS))
        + ", and any files in .gitignore, .git/info/exclude, and ~/.config/git/ignore.",
        default=[],
        action="append",
    )
    parser.add_argument(
        "--no-exclude",
        action="store_true",
        help="Disable all exclusions (overrides --exclude).",
    )
    parser.add_argument(
        "-I",
        "--no-ignore",
        action="store_true",
        help="Disable gitignore file processing. By default, exclusions are loaded from .gitignore, .git/info/exclude, and ~/.config/git/ignore.",
    )
    
    parser.add_argument(
        "-y",
        "--yes",
        action="store_true",
        help="Do not prompt for confirmation. By default, the program will prompt for confirmation only if stdin and stdout are both a TTY.",
    )
    parser.add_argument(
        "--tag",
        type=str,
        choices=["xml", "md"],
        default="xml",
        help="Output format tag. 'xml' uses <path/to/file.ext> tags, 'md' uses markdown-style headers. Defaults to 'xml'.",
    )

    args = parser.parse_args()

    extensions = resolve_extensions(custom_extensions=args.type, no_docs=args.no_docs)

    exclusions = resolve_exclusions(
        no_exclude=args.no_exclude,
        custom_excludes=args.exclude,
        include_tests=args.include_tests,
        include_lock=args.include_lock,
        include_binary=args.include_binary,
        no_ignore=args.no_ignore,
        paths=args.paths,
    )

    if (
        not args.yes
        # We are not piped into
        and sys.stdin.isatty()
        # We are not piping to
        and sys.stdout.isatty()
    ):
        # Display execution settings
        print("\nProgram will execute with the following settings:")
        print("-" * 50)
        print(f"Paths                  {', '.join(args.paths)}")
        print(f"File extensions        {', '.join(extensions) if extensions else 'None specified'}")
        print(
            f"Exclusions             {', '.join(map(_describe_predicate, exclusions)) if exclusions else 'None'}"
        )
        print(f"Only print headers     {args.only_headers}")
        print(f"Include empty files    {args.include_empty}")
        print(f"Include docs files     {not args.no_docs}")
        print(f"Include test files     {args.include_tests}")
        print(f"Include lock files     {args.include_lock}")
        print(f"Include binary files   {args.include_binary}")
        print(f"Process gitignore      {not args.no_ignore}")
        print(f"Output tag format      {args.tag}")
        print("-" * 50)

        response = input("\nDo you want to continue? [Y/n]: ").lower().strip()
    else:
        response = "y"
    if response and response != "y":
        print("Operation cancelled.", file=sys.stderr)
        return

    for path_str in args.paths:
        path = Path(path_str).resolve()

        if path.is_file():
            print_single_file(
                path,
                relative_to=Path.cwd(),
                only_headers=args.only_headers,
                tag=args.tag,
            )
        elif path.is_dir():
            print_files_contents(
                path,
                extensions=extensions,
                exclude=exclusions,
                only_headers=args.only_headers,
                include_empty=args.include_empty,
                tag=args.tag,
            )
        else:
            print(
                f"Error: Path is neither a file nor a directory: {path}",
                file=sys.stderr,
            )


if __name__ == "__main__":
    main()
