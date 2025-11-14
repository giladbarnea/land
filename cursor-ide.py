#!/usr/bin/env -S uv run --script
# /// script
# dependencies = [
#   "pandas",
#   "numpy",
#   "apsw"
# ]
# ///
# Data map (succinct)
# - Non-SQLite files:
#   - ~/Library/Application Support/Cursor/User/History/<session>/*   — generated code/outputs from chats
#   - ~/Library/Application Support/Cursor/Backups/**                 — backup copies of edited files
#
# - SQLite references (cursorDiskKV):
#   - bubbleId:<thread-id>:<bubble-id>                — message JSON (type=1 user / 2 assistant, text, richText, context)
#   - composerData:<thread-id>                        — per-thread state and ordering (conversationMap, richText/text, status)
#   - messageRequestContext:<thread-id>:<bubble-id>   — attached context incl. file paths (visibleFiles, relativePath, selections)
#   - codeBlockDiff:*, codeBlockData:*                — diffs/suggested code blocks linked to messages/files
#
# - Reconstruction:
#   Group bubbleId by <thread-id>, order by rowid; enrich with messageRequestContext paths.
#   Large/final code often exists only on disk (History/Backups/workspace), not duplicated verbatim in bubble text.

# Inspection notes (useful queries while exploring the DBs):
# - List tables
#   SELECT name FROM sqlite_master WHERE type='table' ORDER BY name;
#
# - Column info for a table
#   PRAGMA table_info('ItemTable');
#   PRAGMA table_info('cursorDiskKV');
#
# - Row counts per table
#   SELECT COUNT(1) FROM ItemTable;
#   SELECT COUNT(1) FROM cursorDiskKV;
#
# - Peek at keys
#   SELECT key FROM ItemTable LIMIT 20;
#   SELECT key FROM ItemTable WHERE key LIKE '%chat%' OR key LIKE '%conversation%' OR key LIKE '%thread%' LIMIT 50;
#   SELECT DISTINCT key FROM cursorDiskKV LIMIT 20;
#   SELECT DISTINCT key FROM cursorDiskKV WHERE key LIKE '%chat%' OR key LIKE '%conversation%' OR key LIKE '%thread%' OR key LIKE '%message%' LIMIT 50;
#
# - Find snippet hits (values often JSON-encoded; use LIKE on the raw text/blob)
#   SELECT key, substr(value, 1, 200)
#   FROM cursorDiskKV
#   WHERE typeof(value) IN ('text','blob') AND value LIKE '%traceback%'
#   LIMIT 10;
#
# - Rough JSON shape/size (helps decide whether to parse JSON client-side)
#   SELECT key, length(value) FROM cursorDiskKV LIMIT 10;
#
# - Quick Python one-liners used during exploration (via `uv run --with=apsw python -c`):
#   List tables with counts:
#     import apsw; p='…/state.vscdb'; c=apsw.Connection(p); cur=c.cursor();
#     print([r[0] for r in cur.execute("SELECT name FROM sqlite_master WHERE type='table'")]);
#     print({t: next(cur.execute(f'SELECT COUNT(1) FROM {t}'))[0] for (t,) in cur.execute("SELECT name FROM sqlite_master WHERE type='table'")})
#   Sample keys:
#     for (k,) in cur.execute("SELECT key FROM ItemTable LIMIT 20"): print(k)
#   Snippet search:
#     kw='traceback';
#     for k,v in cur.execute("SELECT key,value FROM cursorDiskKV WHERE typeof(value) IN ('text','blob') AND value LIKE ? LIMIT 5", (f'%{kw}%',)):
#         s=v.decode('utf-8','ignore') if isinstance(v,(bytes,bytearray)) else str(v); print(k, s[:160].replace('\n',' '))
import argparse
import json
import re
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Sequence, Tuple

import apsw

CURSOR_STORAGE_DIR_PATH = Path(
    "/Users/giladbarnea/Library/Application Support/Cursor/User/globalStorage/"
)
STATE_SQLITE_PATH = CURSOR_STORAGE_DIR_PATH / "state.sqlite"
STATE_VSCDB_PATH = CURSOR_STORAGE_DIR_PATH / "state.vscdb"


def list_tables(connection: apsw.Connection) -> List[str]:
    cursor = connection.cursor()
    return [
        r[0]
        for r in cursor.execute(
            "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
        )
    ]  # type: ignore[index]


def table_columns(connection: apsw.Connection, table: str) -> List[Tuple[str, str]]:
    cursor = connection.cursor()
    safe_table = table.replace("'", "''")
    query = "PRAGMA table_info('" + safe_table + "')"
    return [(r[1], (r[2] or "").upper()) for r in cursor.execute(query)]  # type: ignore[index]


def is_text_affinity(declared_type_upper: str) -> bool:
    if not declared_type_upper:
        return True
    return (
        "TEXT" in declared_type_upper
        or "CHAR" in declared_type_upper
        or "CLOB" in declared_type_upper
    )


def try_json_loads(value: Any) -> Optional[Any]:
    if isinstance(value, (bytes, bytearray)):
        try:
            value = value.decode("utf-8", errors="ignore")
        except Exception:
            return None
    if isinstance(value, str):
        text = value.strip()
        if not text or (text[0] not in "[{" or text[-1] not in "]}"):
            return None
        try:
            return json.loads(text)
        except Exception:
            return None
    return None


def walk_names_from_json(obj: Any) -> Iterable[str]:
    if isinstance(obj, dict):
        for k, v in obj.items():
            if k in {"name", "title", "label"} and isinstance(v, str) and v.strip():
                yield v.strip()
            yield from walk_names_from_json(v)
    elif isinstance(obj, list):
        for item in obj:
            yield from walk_names_from_json(item)


def search_itemtable_for_keyword(
    connection: apsw.Connection, keyword: str, limit: int
) -> Iterable[str]:
    cursor = connection.cursor()
    try:
        for key, value in cursor.execute(
            "SELECT key, value FROM ItemTable WHERE typeof(value) IN ('text','blob') AND value LIKE ? LIMIT ?",
            (f"%{keyword}%", limit),
        ):
            data = try_json_loads(value)
            if data is None:
                continue
            for name in walk_names_from_json(data):
                yield name
    except apsw.SQLError:
        return []


def search_generic_tables_for_keyword(
    connection: apsw.Connection, keyword: str, per_table_limit: int
) -> Iterable[str]:
    cursor = connection.cursor()
    for table in list_tables(connection):
        if table == "ItemTable":
            continue
        cols = table_columns(connection, table)
        text_cols = [c for c, t in cols if is_text_affinity(t)]
        if not text_cols:
            continue
        name_cols = [
            c
            for c, _ in cols
            if c.lower() in {"name", "title", "label", "chat_name", "conversation_name"}
        ]
        where = " OR ".join([f"{c} LIKE ?" for c in text_cols])
        params: List[Any] = [f"%{keyword}%"] * len(text_cols)
        try:
            selected_cols = ", ".join([*(name_cols or []), *(text_cols[:3])])
            query = f"SELECT {selected_cols} FROM {table} WHERE {where} LIMIT ?"
            params.append(per_table_limit)
            for row in cursor.execute(query, params):
                row_values = list(row)
                for idx, col in enumerate(name_cols):
                    val = row_values[idx]
                    if isinstance(val, str) and val.strip():
                        yield val.strip()
                for cell in row_values[len(name_cols) :]:
                    data = try_json_loads(cell)
                    if data is None:
                        continue
                    for name in walk_names_from_json(data):
                        yield name
        except apsw.SQLError:
            continue


def collect_matches(
    keyword: str, total_limit: int, per_table_limit: int, debug: bool = False
) -> Counter:
    names: Counter = Counter()
    for db_path in (STATE_SQLITE_PATH, STATE_VSCDB_PATH):
        try:
            conn = apsw.Connection(str(db_path))
        except Exception:
            continue
        try:
            if debug:
                tabs = list_tables(conn)
                print(f"DB: {db_path}")
                print(f"Tables: {tabs}")
            # Prefer ItemTable if present
            if "ItemTable" in list_tables(conn):
                for name in search_itemtable_for_keyword(conn, keyword, total_limit):
                    names[name] += 1
            # Also do a lightweight generic scan
            for name in search_generic_tables_for_keyword(
                conn, keyword, per_table_limit
            ):
                names[name] += 1
        finally:
            try:
                conn.close()
            except Exception:
                pass
    return names


def print_results(names: Counter) -> None:
    if not names:
        print("No matching chat names found.")
        return
    items = sorted(names.items(), key=lambda kv: (-kv[1], kv[0].lower()))
    print(f"Found {len(items)} matching chat names:\n")
    for i, (name, count) in enumerate(items, start=1):
        print(f"{i:>3}. {name}  (hits: {count})")


def safe_decode(value: Any) -> str:
    if isinstance(value, (bytes, bytearray)):
        try:
            return value.decode("utf-8", "ignore")
        except Exception:
            return ""
    return str(value) if value is not None else ""


def extract_plain_text_from_bubble(bubble_obj: Dict[str, Any], shorten: bool = True) -> str:
    text = bubble_obj.get("text")
    if isinstance(text, str) and text.strip():
        return text.strip()
    rich = bubble_obj.get("richText")
    if isinstance(rich, str) and rich.strip():
        # Rich text is often a JSON string; avoid heavy parsing, return a short marker
        snippet = rich.strip().replace("\n", " ")
        return snippet[:200] if shorten else snippet
    return ""


def parse_thread_id_from_bubble_key(key: str) -> Optional[str]:
    # Format: bubbleId:<thread-id>:<bubble-id>
    if not key.startswith("bubbleId:"):
        return None
    parts = key.split(":", 2)
    if len(parts) < 3:
        return None
    return parts[1]


def parse_bubble_id_from_bubble_key(key: str) -> Optional[str]:
    parts = key.split(":", 2)
    if len(parts) < 3:
        return None
    return parts[2]


def load_thread_bubbles(conn: apsw.Connection, thread_id: str, max_bubbles: int) -> List[Tuple[int, str, Dict[str, Any]]]:
    cursor = conn.cursor()
    results: List[Tuple[int, str, Dict[str, Any]]] = []
    try:
        for rowid, key, value in cursor.execute(
            "SELECT rowid, key, value FROM cursorDiskKV WHERE key LIKE ? ORDER BY rowid LIMIT ?",
            (f"bubbleId:{thread_id}:%", max_bubbles),
        ):
            s = safe_decode(value)
            obj: Dict[str, Any] = {}
            t = s.strip()
            if t.startswith("{") and t.endswith("}"):
                try:
                    obj = json.loads(t)
                except Exception:
                    obj = {}
            results.append((int(rowid), str(key), obj))
    except apsw.SQLError:
        pass
    return results


def load_message_request_context(conn: apsw.Connection, thread_id: str, bubble_id: str) -> Optional[Dict[str, Any]]:
    cursor = conn.cursor()
    key = f"messageRequestContext:{thread_id}:{bubble_id}"
    try:
        row = next(cursor.execute("SELECT value FROM cursorDiskKV WHERE key = ?", (key,)))
    except StopIteration:
        return None
    except apsw.SQLError:
        return None
    s = safe_decode(row[0])
    t = s.strip()
    if t.startswith("{") and t.endswith("}"):
        try:
            return json.loads(t)
        except Exception:
            return None
    return None


def extract_paths_from_context(obj: Dict[str, Any]) -> List[str]:
    paths: List[str] = []
    def walk(o: Any) -> None:
        if isinstance(o, dict):
            for k, v in o.items():
                if isinstance(v, str) and "/" in v and "Users" in v:
                    paths.append(v)
                walk(v)
        elif isinstance(o, list):
            for it in o:
                walk(it)
    walk(obj)
    # Deduplicate but preserve order
    seen = set()
    unique: List[str] = []
    for p in paths:
        if p not in seen:
            seen.add(p)
            unique.append(p)
    return unique[:5]


def print_thread(conn: apsw.Connection, thread_id: str, max_bubbles: Optional[int] = None, shorten_text: bool = True) -> None:
    """Print a single thread's messages with optional limits and text shortening."""
    bubble_limit = max_bubbles if max_bubbles is not None else 999999
    
    # Load composerData (optional)
    comp = None
    try:
        row = next(conn.cursor().execute(
            "SELECT value FROM cursorDiskKV WHERE key = ?",
            (f"composerData:{thread_id}",),
        ))
        comp_s = safe_decode(row[0])
        if comp_s.strip().startswith("{") and comp_s.strip().endswith("}"):
            try:
                comp = json.loads(comp_s)
            except Exception:
                comp = None
    except StopIteration:
        pass
    
    # Load bubbles ordered by rowid
    bubbles = load_thread_bubbles(conn, thread_id, bubble_limit)
    for _, bubble_key, bubble_obj in bubbles:
        bubble_id = parse_bubble_id_from_bubble_key(bubble_key) or "?"
        role_type = bubble_obj.get("type")
        role = "U" if role_type == 1 else ("A" if role_type == 2 else "?")
        text = extract_plain_text_from_bubble(bubble_obj, shorten=shorten_text)
        if text:
            if shorten_text:
                text_line = text.replace("\n", " ")
                print(f"[{role}] {text_line[:300]}")
            else:
                print(f"[{role}] {text}")
        else:
            print(f"[{role}] (no text)")
        # Context (files referenced)
        ctx = load_message_request_context(conn, thread_id, bubble_id)
        if ctx:
            paths = extract_paths_from_context(ctx)
            if paths:
                print("    files:")
                for p in paths:
                    print(f"     - {p}")


def thread_explorer(keyword: str, max_threads: int, max_bubbles: int, debug: bool = False, shorten_text: bool = True) -> None:
    threads_to_db: Dict[str, str] = {}
    threads_to_hits: Dict[str, int] = defaultdict(int)
    # First, find matching bubbles across DBs
    for db_path in (STATE_SQLITE_PATH, STATE_VSCDB_PATH):
        try:
            conn = apsw.Connection(str(db_path))
        except Exception:
            continue
        cur = conn.cursor()
        try:
            for key, value in cur.execute(
                "SELECT key, value FROM cursorDiskKV WHERE key LIKE 'bubbleId:%' AND typeof(value) IN ('text','blob') AND value LIKE ? LIMIT 2000",
                (f"%{keyword}%",),
            ):
                key_str = str(key)
                thread_id = parse_thread_id_from_bubble_key(key_str)
                if not thread_id:
                    continue
                threads_to_db.setdefault(thread_id, str(db_path.name))
                threads_to_hits[thread_id] += 1
        except apsw.SQLError:
            pass
        finally:
            try:
                conn.close()
            except Exception:
                pass

    if not threads_to_hits:
        print("No threads found containing the keyword.")
        return

    # Rank threads by hit count
    ranked_threads = sorted(threads_to_hits.items(), key=lambda kv: (-kv[1], kv[0]))[:max_threads]

    for idx, (thread_id, hit_count) in enumerate(ranked_threads, start=1):
        db_name = threads_to_db.get(thread_id, "?")
        print(f"\n=== Thread {idx}: {thread_id} [DB: {db_name}] — matches: {hit_count} ===")
        # Open the specific DB that had the thread
        db_path = STATE_SQLITE_PATH if db_name == STATE_SQLITE_PATH.name else STATE_VSCDB_PATH
        try:
            conn = apsw.Connection(str(db_path))
        except Exception:
            print("  (Cannot open DB)")
            continue
        try:
            print_thread(conn, thread_id, max_bubbles=max_bubbles, shorten_text=shorten_text)
        finally:
            try:
                conn.close()
            except Exception:
                pass


def print_thread_by_id(thread_id: str) -> None:
    """Print a complete thread by its ID, searching across both databases."""
    found = False
    for db_path in (STATE_SQLITE_PATH, STATE_VSCDB_PATH):
        try:
            conn = apsw.Connection(str(db_path))
        except Exception:
            continue
        try:
            # Check if cursorDiskKV table exists
            tables = list_tables(conn)
            if "cursorDiskKV" not in tables:
                continue
            
            # Check if thread exists in this DB
            cur = conn.cursor()
            try:
                row = next(cur.execute(
                    "SELECT key FROM cursorDiskKV WHERE key LIKE ? LIMIT 1",
                    (f"bubbleId:{thread_id}:%",)
                ))
            except StopIteration:
                continue
            except apsw.SQLError:
                continue
            
            # Thread found in this DB
            found = True
            print(f"=== Thread: {thread_id} [DB: {db_path.name}] ===\n")
            print_thread(conn, thread_id, max_bubbles=None, shorten_text=False)
            break
        finally:
            try:
                conn.close()
            except Exception:
                pass
    
    if not found:
        print(f"Thread ID '{thread_id}' not found in any database.")


def is_thread_id(query: str) -> bool:
    """Check if query looks like a thread ID (UUID format)."""
    pattern = r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    return bool(re.match(pattern, query, re.IGNORECASE))


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Search Cursor state DBs for conversations by keyword or print a specific thread by ID",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter
    )
    parser.add_argument(
        "query",
        help="Thread ID (UUID format) to print in full, or keyword to search for (SQLite LIKE; case-insensitive for ASCII)",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=500,
        help="Max matches to pull from ItemTable per DB",
    )
    parser.add_argument(
        "--per-table-limit",
        type=int,
        default=50,
        help="Max rows to pull per generic table",
    )
    parser.add_argument(
        "--debug", action="store_true", help="Print schema info while scanning"
    )
    parser.add_argument(
        "--snippets",
        action="store_true",
        help="Also print matching snippets with source context",
    )
    parser.add_argument(
        "--explore",
        action="store_true",
        help="Rebuild matched threads and print ordered user/assistant messages (thread explorer)",
    )
    parser.add_argument(
        "--max-threads",
        type=int,
        default=3,
        help="Max number of matched threads to render",
    )
    parser.add_argument(
        "--max-bubbles",
        type=int,
        default=200,
        help="Max messages per thread to render",
    )
    parser.add_argument(
        "--no-shorten",
        action="store_true",
        help="Don't shorten/truncate message text",
    )
    args = parser.parse_args()

    # Check if query is a thread ID first
    if is_thread_id(args.query):
        print_thread_by_id(args.query)
        return

    if args.explore:
        thread_explorer(args.query, args.max_threads, args.max_bubbles, debug=args.debug, shorten_text=not args.no_shorten)
        return

    names = collect_matches(args.query, args.limit, args.per_table_limit, debug=args.debug)
    if names:
        print_results(names)
        if not args.snippets:
            return

    # Snippet fallback or explicit request
    def extract_text_from_json(obj: Any, max_texts: int = 5) -> List[str]:
        """Recursively extract human-readable text from JSON structure."""
        texts: List[str] = []
        
        def walk(o: Any, depth: int = 0) -> None:
            if depth > 5 or len(texts) >= max_texts:
                return
            
            if isinstance(o, dict):
                # Special handling for known structures
                if "text" in o and isinstance(o["text"], str) and o["text"].strip():
                    texts.append(o["text"].strip())
                    return
                if "richText" in o and isinstance(o["richText"], str):
                    # richText might be JSON itself
                    try:
                        rich = json.loads(o["richText"])
                        walk(rich, depth + 1)
                    except:
                        pass
                
                # Look for text-like fields
                for key, val in o.items():
                    if key in {"_v", "type", "id", "fsPath", "external", "$mid", "diffId", "uri"}:
                        continue  # Skip technical metadata
                    if isinstance(val, str) and len(val) > 10 and len(val) < 500:
                        # Potential human text (not too short, not too long)
                        if not val.startswith("{") and not val.startswith("["):
                            texts.append(val.strip())
                    else:
                        walk(val, depth + 1)
            
            elif isinstance(o, list):
                for item in o:
                    walk(item, depth + 1)
        
        walk(obj)
        return texts
    
    def format_snippet(key: str, raw_text: str, shorten: bool = True) -> str:
        """Format a snippet by extracting meaningful text from JSON."""
        # Try to parse as JSON
        try:
            data = json.loads(raw_text)
            
            # For bubbleId entries, use specialized extraction
            if key.startswith("bubbleId:"):
                text = extract_plain_text_from_bubble(data, shorten=shorten)
                if text:
                    if shorten:
                        text = text.replace("\n", " ").strip()
                        return (text[:300] + "…") if len(text) > 300 else text
                    else:
                        return text
                else:
                    return "(no text in bubble)"
            
            # For all other JSON, extract text generically
            texts = extract_text_from_json(data, max_texts=3)
            if texts:
                combined = " | ".join(texts[:3])
                if shorten:
                    combined = combined.replace("\n", " ").strip()
                    return (combined[:300] + "…") if len(combined) > 300 else combined
                else:
                    return combined
            else:
                # No text found, show JSON structure hint
                return f"(JSON: {list(data.keys())[:5] if isinstance(data, dict) else 'array'})"
        
        except (json.JSONDecodeError, Exception):
            pass
        
        # Not JSON or parsing failed - show as-is
        s = raw_text.replace("\n", " ").strip()
        if shorten:
            return (s[:160] + "…") if len(s) > 160 else s
        else:
            return s

    print("\nMatching snippets:\n")
    total_shown = 0
    shorten_snippets = not args.no_shorten
    for db_path in (STATE_SQLITE_PATH, STATE_VSCDB_PATH):
        try:
            conn = apsw.Connection(str(db_path))
        except Exception:
            continue
        cur = conn.cursor()
        try:
            # ItemTable
            if "ItemTable" in list_tables(conn):
                try:
                    for key, value in cur.execute(
                        "SELECT key, value FROM ItemTable WHERE typeof(value) IN ('text','blob') AND value LIKE ? LIMIT ?",
                        (f"%{args.query}%", min(100, args.limit)),
                    ):
                        text = (
                            value.decode("utf-8", "ignore")
                            if isinstance(value, (bytes, bytearray))
                            else str(value)
                        )
                        formatted = format_snippet(str(key), text, shorten_snippets)
                        print(f"- [{db_path.name}] ItemTable key={key}: {formatted}")
                        total_shown += 1
                        if total_shown >= 100:
                            return
                except apsw.SQLError:
                    pass
            # cursorDiskKV
            tables = set(list_tables(conn))
            if "cursorDiskKV" in tables:
                try:
                    for key, value in cur.execute(
                        "SELECT key, value FROM cursorDiskKV WHERE typeof(value) IN ('text','blob') AND value LIKE ? LIMIT ?",
                        (f"%{args.query}%", min(100, args.per_table_limit)),
                    ):
                        text = (
                            value.decode("utf-8", "ignore")
                            if isinstance(value, (bytes, bytearray))
                            else str(value)
                        )
                        formatted = format_snippet(str(key), text, shorten_snippets)
                        print(f"- [{db_path.name}] cursorDiskKV key={key}: {formatted}")
                        total_shown += 1
                        if total_shown >= 100:
                            return
                except apsw.SQLError:
                    pass
            # Generic tables text columns
            for table in tables:
                if table in {"ItemTable", "cursorDiskKV"}:
                    continue
                cols = table_columns(conn, table)
                text_cols = [c for c, t in cols if is_text_affinity(t)]
                for col in text_cols[:2]:
                    try:
                        query = f"SELECT {col} FROM {table} WHERE typeof({col}) IN ('text','blob') AND {col} LIKE ? LIMIT ?"
                        for (value,) in cur.execute(query, (f"%{args.query}%", 5)):
                            text = (
                                value.decode("utf-8", "ignore")
                                if isinstance(value, (bytes, bytearray))
                                else str(value)
                            )
                            # Use empty key for generic table entries
                            formatted = format_snippet("", text, shorten_snippets)
                            print(f"- [{db_path.name}] {table}.{col}: {formatted}")
                            total_shown += 1
                            if total_shown >= 100:
                                return
                    except apsw.SQLError:
                        continue
        finally:
            try:
                conn.close()
            except Exception:
                pass


if __name__ == "__main__":
    main()
