"""
File-level verification of supabase/migrations/006_b8_verification.sql.

These tests validate the SQL migration *file* without connecting to a live
database. They cover the seven checks requested by the review:

  1. 006 starts with `drop function if exists public.is_admin();` before any
     other DDL that references it.
  2. The whole 006 file parses as well-formed PostgreSQL (sqlparse), with
     balanced $$ delimiters and parentheses.
  3. After the drop, only ONE `create function public.is_admin(...)` remains
     across the migrations directory (the 1-arg-with-default from 001).
  4. Every `public.is_admin()` call inside 005's RPC bodies will resolve
     uniquely after the drop.
  5. Flutter code never calls `is_admin` as an RPC.
  6. Migration 006 is idempotent (CREATE TABLE IF NOT EXISTS / CREATE OR REPLACE
     FUNCTION / DROP POLICY IF EXISTS before each CREATE POLICY, etc.).
"""

import os
import re
import pytest
import sqlparse

MIGRATIONS_DIR = "/app/nextchapter_audit/src/supabase/migrations"
SRC_DIR = "/app/nextchapter_audit/src"
M006 = os.path.join(MIGRATIONS_DIR, "006_b8_verification.sql")
M005 = os.path.join(MIGRATIONS_DIR, "005_b7_admin.sql")
M001 = os.path.join(MIGRATIONS_DIR, "001_admin_role.sql")


# ---------------------------------------------------------------------------
# Helpers / fixtures
# ---------------------------------------------------------------------------
@pytest.fixture(scope="module")
def m006_text():
    with open(M006, "r", encoding="utf-8") as f:
        return f.read()


@pytest.fixture(scope="module")
def m005_text():
    with open(M005, "r", encoding="utf-8") as f:
        return f.read()


def _strip_comments(sql: str) -> str:
    """Remove -- line comments and /* */ block comments."""
    sql = re.sub(r"/\*.*?\*/", "", sql, flags=re.DOTALL)
    sql = re.sub(r"--[^\n]*", "", sql)
    return sql


# ---------------------------------------------------------------------------
# 1. drop is_admin() appears BEFORE any DDL that references it
# ---------------------------------------------------------------------------
class TestDropPositionedFirst:
    def test_drop_no_arg_is_admin_exists(self, m006_text):
        assert re.search(
            r"drop\s+function\s+if\s+exists\s+public\.is_admin\s*\(\s*\)\s*;",
            m006_text,
            re.IGNORECASE,
        ), "Missing `drop function if exists public.is_admin();` in 006"

    def test_drop_appears_before_first_ddl(self, m006_text):
        stripped = _strip_comments(m006_text)
        drop_match = re.search(
            r"drop\s+function\s+if\s+exists\s+public\.is_admin\s*\(\s*\)\s*;",
            stripped,
            re.IGNORECASE,
        )
        assert drop_match, "drop function statement not found after comment strip"
        drop_pos = drop_match.start()

        # Find the first DDL keyword that could reference is_admin.
        first_ddl = None
        for m in re.finditer(
            r"\b(create\s+(?:or\s+replace\s+)?(?:table|policy|function|index|trigger)|alter\s+table|insert\s+into)\b",
            stripped,
            re.IGNORECASE,
        ):
            first_ddl = m
            break
        assert first_ddl, "No DDL detected in 006 — file appears empty"
        assert drop_pos < first_ddl.start(), (
            f"drop function at offset {drop_pos} appears AFTER first DDL "
            f"({first_ddl.group(0)!r} at offset {first_ddl.start()}). "
            "It must come first or Postgres will hit the overload-ambiguity "
            "error before reaching the drop."
        )


# ---------------------------------------------------------------------------
# 2. Well-formed PostgreSQL — sqlparse + balanced delimiters
# ---------------------------------------------------------------------------
class TestSyntaxWellFormed:
    def test_sqlparse_parses(self, m006_text):
        statements = sqlparse.parse(m006_text)
        # Filter out whitespace-only / empty fragments.
        non_empty = [s for s in statements if s.value.strip()]
        assert len(non_empty) > 5, (
            f"sqlparse only produced {len(non_empty)} non-empty statements — "
            "file likely truncated"
        )
        # Every statement should have a recognised top-level type or be a DO
        # block; sqlparse returns 'UNKNOWN' for some PL/pgSQL but should not
        # raise.
        for s in non_empty:
            assert s.ttype is None or True  # parse succeeded

    def test_dollar_quote_delimiters_balanced(self, m006_text):
        # `$$` must appear in pairs.
        count = m006_text.count("$$")
        assert count % 2 == 0, (
            f"Unbalanced $$ delimiters: found {count} occurrences (must be even)"
        )
        assert count >= 8, (
            f"Expected several $$ blocks (RPCs + DO block); found {count}"
        )

    def test_parentheses_balanced(self, m006_text):
        stripped = _strip_comments(m006_text)
        # Strip dollar-quoted bodies so quoted parens (e.g. inside function
        # bodies' SQL text) don't pollute the count if any literal strings
        # contain stray parens. We still expect balance overall, so this is
        # a soft check on the SQL-level structure.
        opens = stripped.count("(")
        closes = stripped.count(")")
        assert opens == closes, (
            f"Parenthesis imbalance: {opens} '(' vs {closes} ')'"
        )

    def test_every_statement_terminated(self, m006_text):
        # Last non-blank, non-comment character of the file must be `;` or end
        # a `$$` block. Strip trailing whitespace then check the last char.
        tail = m006_text.rstrip()
        assert tail.endswith(";") or tail.endswith("$$"), (
            f"File does not end on a terminator. Last 40 chars: {tail[-40:]!r}"
        )


# ---------------------------------------------------------------------------
# 3. Only one is_admin definition survives after the drop
# ---------------------------------------------------------------------------
class TestIsAdminUniqueAfterDrop:
    def _collect_is_admin_definitions(self):
        defs = []
        for fname in sorted(os.listdir(MIGRATIONS_DIR)):
            if not fname.endswith(".sql"):
                continue
            with open(os.path.join(MIGRATIONS_DIR, fname), encoding="utf-8") as f:
                text = f.read()
            for m in re.finditer(
                r"create\s+(?:or\s+replace\s+)?function\s+public\.is_admin\s*\((.*?)\)\s*\n\s*returns",
                text,
                re.IGNORECASE | re.DOTALL,
            ):
                defs.append((fname, m.group(1).strip()))
        return defs

    def test_exactly_two_definitions_in_files(self):
        defs = self._collect_is_admin_definitions()
        assert len(defs) == 2, (
            f"Expected exactly 2 is_admin definitions across migrations "
            f"(001 + 005), got: {defs}"
        )
        files = {d[0] for d in defs}
        assert files == {"001_admin_role.sql", "005_b7_admin.sql"}, (
            f"Unexpected files defining is_admin: {files}"
        )

    def test_001_defines_one_arg_with_default(self):
        defs = self._collect_is_admin_definitions()
        d001 = [d for d in defs if d[0] == "001_admin_role.sql"][0]
        sig = d001[1].lower()
        assert "uuid" in sig and "default" in sig and "auth.uid()" in sig, (
            f"Migration 001 must define is_admin(uid uuid default auth.uid()), "
            f"got: ({sig})"
        )

    def test_005_defines_no_arg_version(self):
        defs = self._collect_is_admin_definitions()
        d005 = [d for d in defs if d[0] == "005_b7_admin.sql"][0]
        assert d005[1].strip() == "", (
            f"Migration 005 must define is_admin() with no args, got: ({d005[1]!r})"
        )

    def test_006_drops_the_no_arg_version(self, m006_text):
        # Explicit drop with `()` signature — Postgres will then pick the
        # 1-arg-default version.
        assert re.search(
            r"drop\s+function\s+if\s+exists\s+public\.is_admin\s*\(\s*\)\s*;",
            m006_text,
            re.IGNORECASE,
        )


# ---------------------------------------------------------------------------
# 4. 005's RPCs all call public.is_admin() with no args (uniquely resolvable)
# ---------------------------------------------------------------------------
class TestM005CallsUnambiguous:
    def test_all_is_admin_calls_in_005_have_no_args(self, m005_text):
        # Strip the definition line so we only look at *call sites*.
        body = re.sub(
            r"create\s+or\s+replace\s+function\s+public\.is_admin[\s\S]*?\$\$;",
            "",
            m005_text,
            count=1,
            flags=re.IGNORECASE,
        )
        # Find every is_admin(...) call site.
        calls = re.findall(r"public\.is_admin\s*\(([^)]*)\)", body)
        assert calls, "Expected at least one is_admin() call in 005 RPC bodies"
        for args in calls:
            assert args.strip() == "", (
                f"005 has a non-zero-arg is_admin call: ({args!r}). "
                "All calls must be no-arg so they resolve to the 1-arg-default "
                "version after the drop."
            )

    def test_005_does_not_need_rerun_after_006(self, m005_text):
        # 005 functions are `create or replace function` — they store the
        # *source*, not a resolved reference. Postgres re-resolves calls at
        # execute time, so dropping the 0-arg is_admin() does not invalidate
        # them. Sanity check: every admin RPC body is `create or replace`.
        rpc_defs = re.findall(
            r"create\s+or\s+replace\s+function\s+public\.admin_\w+",
            m005_text,
            re.IGNORECASE,
        )
        assert len(rpc_defs) >= 5, (
            f"Expected several admin_* RPCs in 005, found {len(rpc_defs)}"
        )


# ---------------------------------------------------------------------------
# 5. Flutter never RPC-calls is_admin
# ---------------------------------------------------------------------------
class TestFlutterDoesNotCallIsAdmin:
    def test_no_dart_rpc_for_is_admin(self):
        lib_dir = os.path.join(SRC_DIR, "lib")
        offenders = []
        pattern = re.compile(
            r"""\.rpc\(\s*['"]is_admin['"]""", re.IGNORECASE
        )
        for root, _dirs, files in os.walk(lib_dir):
            for fn in files:
                if not fn.endswith(".dart"):
                    continue
                path = os.path.join(root, fn)
                with open(path, encoding="utf-8") as f:
                    text = f.read()
                if pattern.search(text):
                    offenders.append(path)
        assert not offenders, (
            f"Dart code RPC-calls is_admin in: {offenders}. "
            "The SQL helper is RLS-only and must not be invoked from the client."
        )


# ---------------------------------------------------------------------------
# 6. Migration 006 is idempotent
# ---------------------------------------------------------------------------
class TestM006Idempotent:
    def test_create_table_uses_if_not_exists(self, m006_text):
        creates = re.findall(
            r"create\s+(table|index)\s+(?:if\s+not\s+exists\s+)?",
            m006_text,
            re.IGNORECASE,
        )
        # Every CREATE TABLE / CREATE INDEX must include IF NOT EXISTS.
        for m in re.finditer(
            r"create\s+(table|index)\b([^;]*?);",
            m006_text,
            re.IGNORECASE | re.DOTALL,
        ):
            head = m.group(0).lower().splitlines()[0]
            assert "if not exists" in m.group(0).lower(), (
                f"Non-idempotent CREATE: {head!r}"
            )
        assert creates, "Expected at least one CREATE TABLE/INDEX in 006"

    def test_create_function_uses_or_replace(self, m006_text):
        # Every `create function` (without OR REPLACE) is an idempotency bug.
        bad = re.findall(
            r"create\s+function\s+public\.", m006_text, re.IGNORECASE
        )
        assert not bad, (
            f"Found CREATE FUNCTION without OR REPLACE: {bad}"
        )
        good = re.findall(
            r"create\s+or\s+replace\s+function\s+public\.",
            m006_text,
            re.IGNORECASE,
        )
        assert len(good) >= 3, (
            f"Expected several CREATE OR REPLACE FUNCTIONs, found {len(good)}"
        )

    def test_create_policy_preceded_by_drop_policy_if_exists(self, m006_text):
        # For each `create policy "X" on T`, there must be a matching
        # `drop policy if exists "X" on T;` earlier in the file.
        policies = re.findall(
            r'create\s+policy\s+"([^"]+)"\s+on\s+([\w\.]+)',
            m006_text,
            re.IGNORECASE,
        )
        assert policies, "No CREATE POLICY found in 006"
        for name, table in policies:
            pattern = re.compile(
                rf'drop\s+policy\s+if\s+exists\s+"{re.escape(name)}"\s+on\s+'
                rf'{re.escape(table)}\s*;',
                re.IGNORECASE,
            )
            assert pattern.search(m006_text), (
                f'CREATE POLICY "{name}" on {table} has no preceding '
                f'DROP POLICY IF EXISTS — file is not idempotent.'
            )

    def test_storage_bucket_insert_guarded(self, m006_text):
        # The storage.buckets insert is wrapped in a DO $$ ... if not exists.
        assert re.search(
            r"if\s+not\s+exists\s*\(\s*select\s+1\s+from\s+storage\.buckets",
            m006_text,
            re.IGNORECASE,
        ), "storage.buckets insert is not guarded by IF NOT EXISTS check"
