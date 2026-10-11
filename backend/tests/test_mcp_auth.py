"""Xác thực MCP: verify JWT của identity-service (INV-03, INV-07), quyền theo `mcp_access` (INV-04),
discovery RFC 9728 (INV-05/INV-06)."""

from __future__ import annotations

import hashlib
import hmac
import json
import time
from datetime import datetime, timezone

import httpx
import jwt
import pytest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from fastapi import FastAPI
from fastapi.testclient import TestClient

from app import mcp_auth
from app.mcp_auth import InvalidToken, JwksCache, JwksUnavailable, authorize_sub, verify_token
from app.tables import McpAccess
from tests.test_auth import add_user

BASE = "https://study.example.test"
ISS = "https://identity.example.test"
AUD = f"{BASE}/mcp"
SUB = "6f1c0a52-4a0e-4d8f-9a55-0c2b6d1e9f10"


class Signer:
    """Khoá RSA + JWKS giả của identity-service, dùng chung cho test MCP."""

    def __init__(self, kid: str = "k1"):
        self.kid = kid
        self.private = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        jwk = jwt.algorithms.RSAAlgorithm.to_jwk(self.private.public_key(), as_dict=True)
        self.jwks = {"keys": [{**jwk, "kid": kid, "use": "sig", "alg": "RS256"}]}

    def token(self, **overrides) -> str:
        now = int(time.time())
        claims = {"iss": ISS, "aud": AUD, "sub": SUB, "exp": now + 3600, "iat": now, "scope": "content"}
        claims.update(overrides)
        claims = {k: v for k, v in claims.items() if v is not None}
        return jwt.encode(claims, self.private, algorithm="RS256", headers={"kid": self.kid})

    def cache(self) -> JwksCache:
        return JwksCache(f"{ISS}/.well-known/jwks.json", fetch=lambda url: self.jwks)


@pytest.fixture(scope="module")
def signer() -> Signer:
    return Signer()


def _verify(signer: Signer, token: str, keys: JwksCache | None = None) -> dict:
    return verify_token(token, audience=AUD, iss=ISS, keys=keys or signer.cache())


def test_valid_token_returns_claims(signer):
    claims = _verify(signer, signer.token())
    assert claims["sub"] == SUB and claims["aud"] == AUD


@pytest.mark.parametrize(
    "overrides",
    [
        {"aud": "fishing-rod"},  # token của client cũ (INV-07)
        {"aud": "https://moneyflow.jacons-corp.com/mcp"},  # token của connector khác (INV-07)
        {"iss": "https://evil.example.test"},
        {"exp": int(time.time()) - 120},  # quá leeway 30s
        {"sub": None},
        {"sub": "  "},
        {"exp": None},
    ],
)
def test_rejects_wrong_claims(signer, overrides):
    with pytest.raises(InvalidToken):
        _verify(signer, signer.token(**overrides))


def test_rejects_hs256_signed_with_public_key(signer):
    # Tấn công nhầm thuật toán: lấy khoá công khai làm secret HMAC.
    pem = signer.private.public_key().public_bytes(
        serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo
    )
    claims = {"iss": ISS, "aud": AUD, "sub": SUB, "exp": int(time.time()) + 60}
    # PyJWT không cho dùng PEM làm secret HMAC khi encode; dựng token tay như kẻ tấn công.
    header = jwt.utils.base64url_encode(b'{"alg":"HS256","kid":"k1","typ":"JWT"}')
    body = jwt.utils.base64url_encode(json.dumps(claims).encode())
    sig = jwt.utils.base64url_encode(hmac.new(pem, header + b"." + body, hashlib.sha256).digest())
    forged = (header + b"." + body + b"." + sig).decode()
    with pytest.raises(InvalidToken):
        _verify(signer, forged)


def test_rejects_alg_none(signer):
    claims = {"iss": ISS, "aud": AUD, "sub": SUB, "exp": int(time.time()) + 60}
    token = jwt.encode(claims, None, algorithm="none", headers={"kid": "k1"})
    with pytest.raises(InvalidToken):
        _verify(signer, token)


def test_rejects_signature_from_other_key_with_same_kid(signer):
    other = Signer(kid=signer.kid)
    with pytest.raises(InvalidToken):
        _verify(signer, other.token())


@pytest.mark.parametrize("token", ["", "abc", "a.b.c", "Bearer x"])
def test_rejects_garbage(signer, token):
    with pytest.raises(InvalidToken):
        _verify(signer, token)


def test_verify_bearer_needs_bearer_scheme(signer, monkeypatch):
    monkeypatch.setenv("IDENTITY_ISSUER", ISS)
    monkeypatch.setitem(mcp_auth._caches, ISS, signer.cache())
    assert mcp_auth.verify_bearer(f"Bearer {signer.token()}", BASE)["sub"] == SUB
    for header in (None, "", signer.token(), f"Basic {signer.token()}", "Bearer   "):
        with pytest.raises(InvalidToken):
            mcp_auth.verify_bearer(header, BASE)


class _Clock:
    def __init__(self):
        self.now = 1000.0

    def __call__(self) -> float:
        return self.now


def test_unknown_kid_refetches_at_most_once_per_interval(signer):
    calls = []
    clock = _Clock()
    cache = JwksCache("u", fetch=lambda url: calls.append(url) or signer.jwks, min_refresh=60, clock=clock)
    other = Signer(kid="random-kid")
    for _ in range(20):  # kẻ tấn công gửi kid ngẫu nhiên liên tục
        with pytest.raises(InvalidToken):
            _verify(signer, other.token(), keys=cache)
    assert len(calls) == 1
    clock.now += 61
    with pytest.raises(InvalidToken):
        _verify(signer, other.token(), keys=cache)
    assert len(calls) == 2
    assert _verify(signer, signer.token(), keys=cache)["sub"] == SUB
    assert len(calls) == 2  # kid đã biết: không tải lại


def test_key_rotation_picked_up_after_min_refresh(signer):
    clock = _Clock()
    new = Signer(kid="k2")
    current = {"jwks": signer.jwks}
    cache = JwksCache("u", fetch=lambda url: current["jwks"], min_refresh=60, clock=clock)
    assert _verify(signer, signer.token(), keys=cache)
    current["jwks"] = {"keys": signer.jwks["keys"] + new.jwks["keys"]}
    clock.now += 61
    assert _verify(new, new.token(), keys=cache)["sub"] == SUB


def test_jwks_down_without_cached_keys_is_unavailable_not_invalid(signer):


    def down(url):
        raise httpx.ConnectError("down")

    with pytest.raises(JwksUnavailable):
        _verify(signer, signer.token(), keys=JwksCache("u", fetch=down))


def test_jwks_down_keeps_cached_keys(signer):


    clock = _Clock()
    state = {"up": True}

    def fetch(url):
        if not state["up"]:
            raise httpx.ConnectError("down")
        return signer.jwks

    cache = JwksCache("u", fetch=fetch, max_age=100, clock=clock)
    assert _verify(signer, signer.token(), keys=cache)
    state["up"] = False
    clock.now += 200  # khoá cũ quá hạn, tải lại thất bại → vẫn dùng khoá đang có
    assert _verify(signer, signer.token(), keys=cache)["sub"] == SUB


# --- Quyền theo mcp_access (INV-04) --------------------------------------------------------------


def _grant(session, sub=SUB, roles=("learner", "admin"), email="admin@gmail.com"):
    user = add_user(session, email=email, roles=roles)
    session.add(McpAccess(sub=sub, user_id=user.id, label="test"))
    session.flush()
    return user


def test_authorize_sub_none_without_grant(db_session):
    add_user(db_session, roles=("learner", "admin"))
    assert authorize_sub(db_session, SUB) is None


def test_authorize_sub_returns_admin(db_session):
    user = _grant(db_session)
    current = authorize_sub(db_session, SUB)
    assert current is not None and current.id == user.id and current.is_admin
    assert current.session_id == mcp_auth.MCP_SESSION_ID
    assert authorize_sub(db_session, "other-sub") is None


def test_authorize_sub_none_after_revoke(db_session):
    _grant(db_session)
    row = db_session.get(McpAccess, SUB)
    row.revoked_at = datetime.now(timezone.utc)
    db_session.flush()
    assert authorize_sub(db_session, SUB) is None


def test_authorize_sub_none_when_user_lost_admin(db_session):
    user = _grant(db_session)
    user.roles = ["learner"]
    db_session.flush()
    assert authorize_sub(db_session, SUB) is None


def test_authorize_sub_ignores_open_mode(db_session, monkeypatch):
    # INV-03: AUTH_OPEN_AS không cấp quyền MCP.
    add_user(db_session, email="open@gmail.com", roles=("learner", "admin"))
    monkeypatch.setenv("AUTH_OPEN_AS", "open@gmail.com")
    assert authorize_sub(db_session, SUB) is None


# --- Discovery (INV-05/INV-06) ---------------------------------------------------------------------


@pytest.fixture()
def prm_client() -> TestClient:
    app = FastAPI()
    app.include_router(mcp_auth.router)
    return TestClient(app)


def test_prm_not_configured_is_404(prm_client, monkeypatch):
    monkeypatch.delenv("PUBLIC_BASE_URL", raising=False)
    assert prm_client.get("/.well-known/oauth-protected-resource/mcp").status_code == 404


def test_prm_points_to_identity_service(prm_client, monkeypatch):
    monkeypatch.setenv("PUBLIC_BASE_URL", BASE + "/")
    monkeypatch.setenv("IDENTITY_ISSUER", ISS)
    for path in ("/.well-known/oauth-protected-resource", "/.well-known/oauth-protected-resource/mcp"):
        body = prm_client.get(path).json()
        assert body == {
            "resource": AUD,  # == aud backend kiểm (INV-06)
            "authorization_servers": [ISS],
            "scopes_supported": ["content"],
            "bearer_methods_supported": ["header"],
        }


def test_www_authenticate_points_to_prm():
    header = mcp_auth.www_authenticate(BASE, invalid=True)
    assert header.startswith("Bearer ")
    assert f'resource_metadata="{BASE}/.well-known/oauth-protected-resource/mcp"' in header
    assert 'error="invalid_token"' in header
    assert "error=" not in mcp_auth.www_authenticate(BASE, invalid=False)
