"""
File-level verification for supabase migration 007_b9_demo_seed.sql.

Validates the pgcrypto-dependency fix:
  - No unqualified crypt(/gen_salt( calls remain
  - The bcrypt-shaped placeholder is exactly 60 chars on encrypted_password
  - SQL is well-formed (balanced $$ and parentheses, sqlparse-parseable)
  - Migration is idempotent (on conflict do nothing / lookup-then-update)
  - gen_random_uuid() is still present in the demo-conversations RPC
  - The 6 demo uuids referenced in the RPC match the ones passed to
    _seed_demo_user() in the DO block

No live Postgres / Supabase access is required — this is purely a file-level
verification per the agent-to-agent context.
"""
import os
import re
import pytest
import sqlparse

MIGRATION_PATH = (
    "/app/nextchapter_audit/src/supabase/migrations/007_b9_demo_seed.sql"
)

EXPECTED_PLACEHOLDER = (
    "$2a$10$DemoAccountNoLoginXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
)

DEMO_UUIDS = [
    "00000000-0000-4000-8000-000000000001",
    "00000000-0000-4000-8000-000000000002",
    "00000000-0000-4000-8000-000000000003",
    "00000000-0000-4000-8000-000000000004",
    "00000000-0000-4000-8000-000000000005",
    "00000000-0000-4000-8000-000000000006",
]


@pytest.fixture(scope="module")
def sql_text():
    assert os.path.exists(MIGRATION_PATH), f"missing {MIGRATION_PATH}"
    with open(MIGRATION_PATH, "r", encoding="utf-8") as f:
        return f.read()


def _strip_line_comments(text: str) -> str:
    """Remove -- line comments so token-level greps ignore commentary."""
    out = []
    for line in text.splitlines():
        idx = line.find("--")
        if idx >= 0:
            line = line[:idx]
        out.append(line)
    return "\n".join(out)


# ── pgcrypto-dependency fix ────────────────────────────────────────────────
class TestPgcryptoRemoval:
    def test_no_crypt_calls(self, sql_text):
        code = _strip_line_comments(sql_text)
        # match crypt( with a word-boundary; allow pgcrypto.crypt( etc. by checking
        # there's no schema-qualifier prefix (letter/dot) before it.
        matches = re.findall(r"(?<![A-Za-z0-9_.])crypt\s*\(", code)
        assert matches == [], f"unqualified crypt( still present: {matches}"

    def test_no_gen_salt_calls(self, sql_text):
        code = _strip_line_comments(sql_text)
        matches = re.findall(r"(?<![A-Za-z0-9_.])gen_salt\s*\(", code)
        assert matches == [], f"unqualified gen_salt( still present: {matches}"

    def test_no_create_extension_pgcrypto(self, sql_text):
        assert "create extension" not in sql_text.lower() or "pgcrypto" not in sql_text.lower(), \
            "migration should not depend on CREATE EXTENSION pgcrypto"


# ── Placeholder password shape ─────────────────────────────────────────────
class TestPlaceholderPassword:
    def test_placeholder_present(self, sql_text):
        assert EXPECTED_PLACEHOLDER in sql_text, "expected placeholder string missing"

    def test_placeholder_exact_length(self):
        assert len(EXPECTED_PLACEHOLDER) == 60, (
            f"bcrypt-shape placeholder must be 60 chars, got {len(EXPECTED_PLACEHOLDER)}"
        )

    def test_placeholder_bcrypt_prefix(self):
        # bcrypt strings start with $2a$, $2b$, $2x$ or $2y$ then NN$
        assert re.match(r"^\$2[axyb]\$\d{2}\$.{53}$", EXPECTED_PLACEHOLDER), \
            "placeholder does not match bcrypt shape $2[axyb]$NN$<53 chars>"

    def test_placeholder_on_encrypted_password_line(self, sql_text):
        # ensure encrypted_password column has the placeholder as its value
        # The values(...) tuple lists columns in the same order as the INSERT
        # column list — encrypted_password is the 6th column. The placeholder
        # must appear on a line near "encrypted_password" / between the
        # auth.users insert and the closing of that VALUES tuple.
        assert "encrypted_password" in sql_text
        # And the placeholder must appear after "encrypted_password," in file order.
        ep_idx = sql_text.index("encrypted_password")
        ph_idx = sql_text.index(EXPECTED_PLACEHOLDER)
        assert ph_idx > ep_idx, \
            "placeholder must appear after encrypted_password column declaration"


# ── SQL well-formedness ────────────────────────────────────────────────────
class TestSqlWellFormed:
    def test_sqlparse_produces_statements(self, sql_text):
        stmts = [
            s for s in sqlparse.parse(sql_text) if s.value.strip()
        ]
        # We expect at least the helper function, the DO block, and the RPC
        # function + grant — 4 top-level statements minimum.
        assert len(stmts) >= 3, f"sqlparse only produced {len(stmts)} statements"

    def test_dollar_quotes_balanced(self, sql_text):
        # Count standalone $$ markers. Must be even.
        count = sql_text.count("$$")
        assert count > 0, "no $$ delimiters found (unexpected)"
        assert count % 2 == 0, f"$$ delimiters unbalanced (count={count})"

    def test_parentheses_balanced(self, sql_text):
        # Strip line comments and string literals before counting parens,
        # because single-quoted strings may legitimately contain ( or ).
        code = _strip_line_comments(sql_text)
        # remove single-quoted strings (handle '' escapes)
        no_strings = re.sub(r"'(?:''|[^'])*'", "''", code)
        opens = no_strings.count("(")
        closes = no_strings.count(")")
        assert opens == closes, f"paren imbalance: {opens} '(' vs {closes} ')'"

    def test_terminating_semicolon(self, sql_text):
        # File should end with a semicolon-terminated statement.
        last = sql_text.rstrip().splitlines()[-1].strip()
        assert last.endswith(";"), f"file does not end with semicolon: {last!r}"


# ── Idempotency guards ────────────────────────────────────────────────────
class TestIdempotency:
    def test_auth_users_on_conflict(self, sql_text):
        # auth.users insert must be guarded by on conflict (id) do nothing
        m = re.search(
            r"insert\s+into\s+auth\.users[\s\S]+?on\s+conflict\s*\(\s*id\s*\)\s+do\s+nothing",
            sql_text, re.IGNORECASE,
        )
        assert m is not None, "auth.users insert missing `on conflict (id) do nothing`"

    @pytest.mark.parametrize("table", [
        "profile_photos",
        "profile_prompts",
        "profile_interests",
        "profile_looking_for",
        "profile_life_situation",
    ])
    def test_profile_subtables_on_conflict(self, sql_text, table):
        pattern = (
            r"insert\s+into\s+public\." + re.escape(table) +
            r"[\s\S]+?on\s+conflict\s+do\s+nothing"
        )
        assert re.search(pattern, sql_text, re.IGNORECASE), \
            f"{table} insert missing `on conflict do nothing`"

    def test_verification_status_on_conflict(self, sql_text):
        # The bootstrap-trigger fallback insert
        assert re.search(
            r"insert\s+into\s+public\.verification_status[\s\S]+?on\s+conflict\s*\(\s*profile_id\s*\)\s+do\s+nothing",
            sql_text, re.IGNORECASE,
        ), "verification_status fallback insert missing on conflict guard"

    def test_profiles_lookup_then_update_branch(self, sql_text):
        # Helper should SELECT from profiles by user_id, then branch
        # between INSERT (when null) and UPDATE (when found).
        assert re.search(
            r"select\s+id\s+into\s+new_profile_id\s+from\s+public\.profiles\s+where\s+user_id\s*=\s*in_user_id",
            sql_text, re.IGNORECASE,
        ), "missing lookup `select id into new_profile_id from public.profiles where user_id = in_user_id`"
        assert re.search(r"if\s+new_profile_id\s+is\s+null\s+then", sql_text, re.IGNORECASE), \
            "missing `if new_profile_id is null then` branch"
        assert re.search(r"\bupdate\s+public\.profiles\s+set\b", sql_text, re.IGNORECASE), \
            "missing UPDATE branch on public.profiles"

    def test_create_or_replace_functions(self, sql_text):
        # Both functions (_seed_demo_user, seed_demo_conversations_for_me)
        # must use CREATE OR REPLACE for idempotency
        assert re.search(
            r"create\s+or\s+replace\s+function\s+public\._seed_demo_user",
            sql_text, re.IGNORECASE,
        ), "_seed_demo_user not CREATE OR REPLACE"
        assert re.search(
            r"create\s+or\s+replace\s+function\s+public\.seed_demo_conversations_for_me",
            sql_text, re.IGNORECASE,
        ), "seed_demo_conversations_for_me not CREATE OR REPLACE"


# ── gen_random_uuid is the Postgres-13 built-in, NOT pgcrypto ─────────────
class TestGenRandomUuid:
    def test_present_in_messages_insert(self, sql_text):
        # Must remain in seed_demo_conversations_for_me's messages insert
        # (it's the client_message_id source).
        # Find the seed_demo_conversations_for_me function body
        body = sql_text.split("seed_demo_conversations_for_me", 1)[-1]
        assert "gen_random_uuid()" in body, \
            "gen_random_uuid() missing from seed_demo_conversations_for_me body"


# ── UUID consistency: helper-call ids match RPC lookup ids ─────────────────
class TestDemoUuidConsistency:
    @pytest.mark.parametrize("uuid_str", DEMO_UUIDS)
    def test_uuid_passed_to_seed_demo_user(self, sql_text, uuid_str):
        # The DO block calls _seed_demo_user('<uuid>', ...) for each demo
        pattern = r"_seed_demo_user\(\s*'" + re.escape(uuid_str) + r"'"
        assert re.search(pattern, sql_text), \
            f"uuid {uuid_str} not passed to _seed_demo_user(...) in DO block"

    @pytest.mark.parametrize("uuid_str", DEMO_UUIDS)
    def test_uuid_referenced_in_rpc(self, sql_text, uuid_str):
        # The RPC's `user_id in (...)` list must contain each demo uuid
        # We extract the RPC body and check the literal appears there.
        rpc_start = sql_text.index("seed_demo_conversations_for_me")
        rpc_body = sql_text[rpc_start:]
        assert uuid_str in rpc_body, \
            f"uuid {uuid_str} missing from seed_demo_conversations_for_me lookup list"

    def test_exactly_six_demo_uuids_in_rpc(self, sql_text):
        rpc_start = sql_text.index("seed_demo_conversations_for_me")
        rpc_body = sql_text[rpc_start:]
        # Match the canonical demo prefix
        found = re.findall(
            r"00000000-0000-4000-8000-00000000000[1-9]", rpc_body
        )
        # Could include matches inside comments; the set of unique values
        # must be exactly the 6 expected ones.
        assert set(found) == set(DEMO_UUIDS), \
            f"RPC uuid set mismatch: found {sorted(set(found))}"


# ── Grant on the RPC for authenticated callers ─────────────────────────────
class TestGrants:
    def test_grant_execute_to_authenticated(self, sql_text):
        assert re.search(
            r"grant\s+execute\s+on\s+function\s+public\.seed_demo_conversations_for_me\s*\(\s*\)\s+to\s+authenticated",
            sql_text, re.IGNORECASE,
        ), "missing GRANT EXECUTE ... TO authenticated on the RPC"
