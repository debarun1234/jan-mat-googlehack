"""
Citizen User Router — registration, profile, Firebase phone OTP bridge

Flow:
  1. Flutter app: Firebase Auth handles phone OTP verification
  2. Flutter sends Firebase ID token to POST /users/auth
  3. Backend verifies token (or trusts UID for POC), creates/returns user + JWT
  4. All subsequent requests carry our JWT

Endpoints:
  POST /users/auth              — Firebase ID token → our JWT
  POST /users/profile           — create/update profile
  GET  /users/profile           — get own profile
  GET  /users/submissions       — own submission history
  GET  /users/heatmap/{pin}     — constituency heatmap data for citizen view
"""

import uuid
from datetime import datetime, timezone
from typing import Annotated

import httpx
import structlog
from fastapi import APIRouter, Depends, HTTPException, Header
from google.cloud import firestore
from pydantic import BaseModel, Field, field_validator

from app.config import Settings, get_settings
from app.services.bigquery import BigQueryService, get_bigquery_service

log = structlog.get_logger()
router = APIRouter(prefix="/users", tags=["users"])

# ── Firestore user store — persists across container restarts ─────────
_db: firestore.AsyncClient | None = None


def _get_db() -> firestore.AsyncClient:
    global _db
    if _db is None:
        settings = get_settings()
        _db = firestore.AsyncClient(project=settings.gcp_project_id)
    return _db


async def _get_user(firebase_uid: str) -> dict | None:
    doc = await _get_db().collection("janmat_users").document(firebase_uid).get()
    return doc.to_dict() if doc.exists else None


async def _set_user(firebase_uid: str, data: dict) -> None:
    await _get_db().collection("janmat_users").document(firebase_uid).set(data)


async def _update_user(firebase_uid: str, updates: dict) -> None:
    await _get_db().collection("janmat_users").document(firebase_uid).update(updates)


_pincode_map: dict[str, str] = {
    "560064": "KA-BLR-NORTH-01",
    "560065": "KA-BLR-NORTH-01",
    "560092": "KA-BLR-NORTH-01",
    "560097": "KA-BLR-NORTH-01",
    "560024": "KA-BLR-NORTH-01",
    "560043": "KA-BLR-NORTH-01",
    "560073": "KA-BLR-NORTH-01",
}


# ── Models ─────────────────────────────────────────────────────────────


class FirebaseAuthRequest(BaseModel):
    firebase_uid: str
    phone_number: str = Field(pattern=r"^\+[1-9]\d{9,14}$")
    id_token: str | None = None  # Used for server-side verification in production


class UserProfileRequest(BaseModel):
    full_name: str = Field(min_length=2, max_length=200)
    town: str | None = None
    city: str = Field(min_length=2, max_length=200)
    state: str = Field(min_length=2, max_length=100)
    pin_code: str = Field(pattern=r"^[1-9][0-9]{5}$")
    phone_number: str

    @field_validator("full_name")
    @classmethod
    def name_strip(cls, v: str) -> str:
        return v.strip()


class UserResponse(BaseModel):
    user_id: str
    firebase_uid: str
    phone_number: str
    full_name: str | None
    town: str | None
    city: str | None
    state: str | None
    pin_code: str | None
    constituency_id: str | None
    submission_count: int
    created_at: str
    profile_complete: bool


class AuthResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user_id: str
    profile_complete: bool
    message: str


# ── Firebase token verification ────────────────────────────────────────


async def _verify_firebase_token(id_token: str, settings: Settings) -> str | None:
    """
    Verify Firebase ID token via Google Identity Toolkit REST API.
    Returns firebase_uid on success, None on failure.
    For POC: if no id_token provided, trust the firebase_uid directly.
    """
    if not id_token:
        return None  # POC: skip verification
    try:
        async with httpx.AsyncClient() as client:
            resp = await client.post(
                "https://identitytoolkit.googleapis.com/v1/accounts:lookup",
                params={
                    "key": settings.gcp_project_id
                },  # Using project ID as placeholder
                json={"idToken": id_token},
                timeout=10,
            )
            if resp.status_code == 200:
                data = resp.json()
                users = data.get("users", [])
                if users:
                    return users[0].get("localId")
    except Exception as e:
        log.warning("firebase_verify_failed", error=str(e))
    return None


def _make_user_jwt(
    user_id: str, firebase_uid: str, constituency_id: str, settings: Settings
) -> str:
    from datetime import timedelta
    from jose import jwt as jose_jwt

    payload = {
        "sub": user_id,
        "firebase_uid": firebase_uid,
        "constituency_id": constituency_id,
        "type": "citizen",
        "exp": datetime.now(timezone.utc) + timedelta(days=30),
        "iat": datetime.now(timezone.utc),
    }
    return jose_jwt.encode(
        payload, settings.jwt_secret, algorithm=settings.jwt_algorithm
    )


async def _get_current_user(
    authorization: Annotated[str | None, Header()] = None,
    settings: Settings = Depends(get_settings),
) -> dict:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing authentication token")
    token = authorization.split(" ", 1)[1]
    try:
        from jose import jwt as jose_jwt

        payload = jose_jwt.decode(
            token, settings.jwt_secret, algorithms=[settings.jwt_algorithm]
        )
        if payload.get("type") != "citizen":
            raise HTTPException(status_code=403, detail="Not a citizen token")
        return payload
    except Exception:
        raise HTTPException(status_code=401, detail="Invalid or expired token")


# ── Endpoints ──────────────────────────────────────────────────────────


@router.post("/auth", response_model=AuthResponse)
async def firebase_auth(
    request: FirebaseAuthRequest,
    settings: Annotated[Settings, Depends(get_settings)],
):
    """
    Bridge: Firebase phone OTP verified on client → our backend JWT.
    Creates user if first time, else updates last_login_at.
    """
    firebase_uid = request.firebase_uid

    # Optional: verify Firebase ID token (recommended in production)
    if request.id_token:
        verified_uid = await _verify_firebase_token(request.id_token, settings)
        if verified_uid and verified_uid != firebase_uid:
            raise HTTPException(status_code=401, detail="Token UID mismatch")

    # Create or update user record
    try:
        user = await _get_user(firebase_uid)
    except Exception as e:
        log.error("firestore_get_user_failed", error=str(e), firebase_uid=firebase_uid)
        raise HTTPException(
            status_code=500, detail=f"Database error: {type(e).__name__}: {str(e)}"
        )
    if user is None:
        user_id = str(uuid.uuid4())
        user = {
            "user_id": user_id,
            "firebase_uid": firebase_uid,
            "phone_number": request.phone_number,
            "full_name": None,
            "town": None,
            "city": None,
            "state": None,
            "pin_code": None,
            "constituency_id": settings.constituency_id,
            "submission_count": 0,
            "created_at": datetime.now(timezone.utc).isoformat(),
            "profile_complete": False,
        }
        try:
            await _set_user(firebase_uid, user)
        except Exception as e:
            log.error("firestore_set_user_failed", error=str(e))
            raise HTTPException(
                status_code=500, detail=f"Database error: {type(e).__name__}: {str(e)}"
            )
        log.info(
            "user_created",
            firebase_uid=firebase_uid,
            phone=request.phone_number[:6] + "****",
        )
    else:
        try:
            await _update_user(
                firebase_uid, {"last_login_at": datetime.now(timezone.utc).isoformat()}
            )
        except Exception as e:
            log.warning("firestore_update_login_failed", error=str(e))  # non-fatal

    token = _make_user_jwt(
        user["user_id"],
        firebase_uid,
        user.get("constituency_id", settings.constituency_id),
        settings,
    )

    return AuthResponse(
        access_token=token,
        user_id=user["user_id"],
        profile_complete=user.get("profile_complete", False),
        message="Welcome back"
        if user.get("profile_complete")
        else "Please complete your profile",
    )


@router.post("/profile", response_model=UserResponse)
async def update_profile(
    request: UserProfileRequest,
    current_user: Annotated[dict, Depends(_get_current_user)],
    settings: Annotated[Settings, Depends(get_settings)],
):
    """Create or update citizen profile."""
    firebase_uid = current_user["firebase_uid"]
    user = await _get_user(firebase_uid)
    if user is None:
        raise HTTPException(status_code=404, detail="User not found")

    constituency_id = _pincode_map.get(request.pin_code, settings.constituency_id)

    updates = {
        "full_name": request.full_name,
        "town": request.town,
        "city": request.city,
        "state": request.state,
        "pin_code": request.pin_code,
        "constituency_id": constituency_id,
        "profile_complete": True,
    }
    await _update_user(firebase_uid, updates)
    user.update(updates)

    log.info(
        "user_profile_updated",
        firebase_uid=firebase_uid,
        city=request.city,
        constituency=constituency_id,
    )
    return UserResponse(**user)


@router.get("/profile", response_model=UserResponse)
async def get_profile(
    current_user: Annotated[dict, Depends(_get_current_user)],
):
    """Get own profile."""
    firebase_uid = current_user["firebase_uid"]
    user = await _get_user(firebase_uid)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return UserResponse(**user)


@router.get("/submissions")
async def get_user_submissions(
    current_user: Annotated[dict, Depends(_get_current_user)],
    limit: int = 50,
):
    """Get own submission history from Firestore."""
    firebase_uid = current_user["firebase_uid"]
    docs = await (
        _get_db()
        .collection("janmat_users")
        .document(firebase_uid)
        .collection("submissions")
        .order_by("submitted_at", direction="DESCENDING")
        .limit(limit)
        .get()
    )
    return {
        "submissions": [doc.to_dict() for doc in docs],
        "total": len(docs),
    }


@router.get("/heatmap/{pin_code}")
async def get_citizen_heatmap(
    pin_code: str,
    category: str | None = None,
    bq: BigQueryService = Depends(get_bigquery_service),
):
    """
    Citizen-facing heatmap: returns demand hotspot data for their constituency.
    Fully transparent — citizens can see exactly what data drives MP decisions.
    """
    constituency_id = _pincode_map.get(pin_code, "KA-BLR-NORTH-01")
    try:
        data = await bq.get_heatmap_data(constituency_id)
        if category:
            data = [d for d in data if d.get("category") == category]

        return {
            "constituency_id": constituency_id,
            "pin_code": pin_code,
            "category_filter": category,
            "hotspots": data,
            "total_hotspots": len(data),
            "categories_available": list({d.get("category") for d in data}),
            "transparency_note": (
                "This data is aggregated and anonymized. "
                "Individual complaint details are never shown. "
                "Your submission contributes to this map."
            ),
        }
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


# ── Admin: list all users (MP only, accessed via dashboard) ──────────


@router.get("/admin/list")
async def list_users(
    constituency_id: str | None = None,
    city: str | None = None,
    state: str | None = None,
    limit: int = 100,
    offset: int = 0,
):
    """MP admin endpoint — list registered citizens with profile data."""
    docs = await _get_db().collection("janmat_users").get()
    users = [doc.to_dict() for doc in docs]

    if constituency_id:
        users = [u for u in users if u.get("constituency_id") == constituency_id]
    if city:
        users = [u for u in users if (u.get("city") or "").lower() == city.lower()]
    if state:
        users = [u for u in users if (u.get("state") or "").lower() == state.lower()]

    total = len(users)
    page = users[offset : offset + limit]

    # Strip sensitive fields for MP view
    safe = []
    for u in page:
        safe.append(
            {
                "user_id": u["user_id"],
                "full_name": u.get("full_name", "Anonymous"),
                "town": u.get("town"),
                "city": u.get("city"),
                "state": u.get("state"),
                "pin_code": u.get("pin_code"),
                "constituency_id": u.get("constituency_id"),
                "submission_count": u.get("submission_count", 0),
                "profile_complete": u.get("profile_complete", False),
                "joined": u.get("created_at", ""),
                # Phone intentionally omitted unless MP has explicit access
            }
        )

    return {
        "total": total,
        "limit": limit,
        "offset": offset,
        "users": safe,
        "summary": {
            "by_city": _count_by(users, "city"),
            "by_state": _count_by(users, "state"),
            "profile_complete": sum(1 for u in users if u.get("profile_complete")),
        },
    }


def _count_by(users: list[dict], field: str) -> dict:
    counts: dict[str, int] = {}
    for u in users:
        val = u.get(field) or "Unknown"
        counts[val] = counts.get(val, 0) + 1
    return dict(sorted(counts.items(), key=lambda x: x[1], reverse=True)[:10])
