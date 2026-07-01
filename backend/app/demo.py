"""
Demo mode — returns realistic mock data when DEMO_MODE=true.
Used for local Docker testing without GCP credentials.
"""
import uuid
from datetime import datetime, timezone, timedelta
from fastapi import APIRouter
from fastapi.responses import JSONResponse

router = APIRouter(tags=["demo"])

_SUBMISSIONS = [
    {
        "submission_id": "sub-demo001",
        "input_type": "text",
        "category": "Roads",
        "urgency_rating": 4,
        "summary_en": "Pothole on main road near ward 4 school causing accidents",
        "constituency_id": "KA-BLR-NORTH-01",
        "latitude": 13.0827,
        "longitude": 77.5877,
        "processing_status": "processed",
        "submitted_at": (datetime.now(timezone.utc) - timedelta(hours=2)).isoformat(),
    },
    {
        "submission_id": "sub-demo002",
        "input_type": "audio",
        "category": "Water",
        "urgency_rating": 5,
        "summary_en": "No water supply for 3 days in Hebbal area",
        "constituency_id": "KA-BLR-NORTH-01",
        "latitude": 13.0500,
        "longitude": 77.5900,
        "processing_status": "processed",
        "submitted_at": (datetime.now(timezone.utc) - timedelta(hours=5)).isoformat(),
    },
    {
        "submission_id": "sub-demo003",
        "input_type": "image",
        "category": "Sanitation",
        "urgency_rating": 3,
        "summary_en": "Garbage overflow at market area not cleared for a week",
        "constituency_id": "KA-BLR-NORTH-01",
        "latitude": 13.0650,
        "longitude": 77.5800,
        "processing_status": "processed",
        "submitted_at": (datetime.now(timezone.utc) - timedelta(hours=10)).isoformat(),
    },
    {
        "submission_id": "sub-demo004",
        "input_type": "text",
        "category": "Education",
        "urgency_rating": 3,
        "summary_en": "Primary school lacks toilets — girls drop out due to this",
        "constituency_id": "KA-BLR-NORTH-01",
        "latitude": 13.0700,
        "longitude": 77.5950,
        "processing_status": "processed",
        "submitted_at": (datetime.now(timezone.utc) - timedelta(hours=20)).isoformat(),
    },
    {
        "submission_id": "sub-demo005",
        "input_type": "text",
        "category": "Health",
        "urgency_rating": 5,
        "summary_en": "PHC closed — no doctor for 2 weeks, patients travelling 30km",
        "constituency_id": "KA-BLR-NORTH-01",
        "latitude": 13.0400,
        "longitude": 77.5700,
        "processing_status": "processed",
        "submitted_at": (datetime.now(timezone.utc) - timedelta(days=1)).isoformat(),
    },
]

_HOTSPOTS = [
    {
        "hotspot_id": "hs-001",
        "category": "Roads",
        "center_lat": 13.0827,
        "center_lon": 77.5877,
        "radius_km": 1.2,
        "complaint_count": 47,
        "avg_urgency": 3.8,
        "demand_score": 72.4,
        "gap_index": 0.65,
        "priority_score": 0.82,
        "priority_rank": 1,
        "ward_id": "WARD-04",
        "suggested_project": "Road resurfacing and pothole repair — Ward 4",
        "evidence_log": "47 complaints in 1.2km radius. Census data shows 12,000 residents affected. No road maintenance in 3 years (infrastructure gap index: 0.65). Avg urgency 3.8/5.",
        "computed_at": datetime.now(timezone.utc).isoformat(),
        "constituency_id": "KA-BLR-NORTH-01",
    },
    {
        "hotspot_id": "hs-002",
        "category": "Water",
        "center_lat": 13.0500,
        "center_lon": 77.5900,
        "radius_km": 0.8,
        "complaint_count": 31,
        "avg_urgency": 4.5,
        "demand_score": 68.1,
        "gap_index": 0.78,
        "priority_score": 0.79,
        "priority_rank": 2,
        "ward_id": "WARD-07",
        "suggested_project": "Water pipeline extension — Hebbal North",
        "evidence_log": "31 complaints, avg urgency 4.5/5. Area not covered by municipal water grid. 8,500 residents rely on tankers. Infrastructure gap index: 0.78.",
        "computed_at": datetime.now(timezone.utc).isoformat(),
        "constituency_id": "KA-BLR-NORTH-01",
    },
    {
        "hotspot_id": "hs-003",
        "category": "Sanitation",
        "center_lat": 13.0650,
        "center_lon": 77.5800,
        "radius_km": 0.5,
        "complaint_count": 23,
        "avg_urgency": 3.2,
        "demand_score": 55.3,
        "gap_index": 0.55,
        "priority_score": 0.71,
        "priority_rank": 3,
        "ward_id": "WARD-02",
        "suggested_project": "Solid waste management — Market Area Ward 2",
        "evidence_log": "23 complaints about waste overflow. Market area generates 2.1 tons/day. Collection frequency: 3x/week vs recommended 7x/week.",
        "computed_at": datetime.now(timezone.utc).isoformat(),
        "constituency_id": "KA-BLR-NORTH-01",
    },
    {
        "hotspot_id": "hs-004",
        "category": "Education",
        "center_lat": 13.0700,
        "center_lon": 77.5950,
        "radius_km": 1.5,
        "complaint_count": 18,
        "avg_urgency": 3.0,
        "demand_score": 48.6,
        "gap_index": 0.60,
        "priority_score": 0.65,
        "priority_rank": 4,
        "ward_id": "WARD-09",
        "suggested_project": "Toilet block construction — 3 primary schools",
        "evidence_log": "18 complaints. 3 schools serving 2,400 students lack adequate sanitation. Girls enrolment drop 34% in grades 6-8. UDISE data confirms infrastructure gap.",
        "computed_at": datetime.now(timezone.utc).isoformat(),
        "constituency_id": "KA-BLR-NORTH-01",
    },
    {
        "hotspot_id": "hs-005",
        "category": "Health",
        "center_lat": 13.0400,
        "center_lon": 77.5700,
        "radius_km": 2.0,
        "complaint_count": 15,
        "avg_urgency": 4.8,
        "demand_score": 58.4,
        "gap_index": 0.72,
        "priority_score": 0.68,
        "priority_rank": 5,
        "ward_id": "WARD-12",
        "suggested_project": "PHC staffing and medical supply — Ward 12",
        "evidence_log": "15 complaints, urgency 4.8/5. PHC serving 18,000 residents has no permanent doctor for 2 weeks. Nearest alternative is 28km away.",
        "computed_at": datetime.now(timezone.utc).isoformat(),
        "constituency_id": "KA-BLR-NORTH-01",
    },
]


# ── Demo endpoints — mirror the real API contract ─────────────────────

@router.post("/intake/text")
async def demo_submit_text(body: dict):
    sid = f"sub-{uuid.uuid4().hex[:12]}"
    return {
        "submission_id": sid,
        "status": "processed",
        "category": "Roads",
        "urgency_rating": 3,
        "summary_en": f"[DEMO] Processed: {str(body.get('text', ''))[:80]}",
        "message": "Submission received and is being processed",
    }


@router.post("/intake/audio")
async def demo_submit_audio():
    return {
        "submission_id": f"sub-{uuid.uuid4().hex[:12]}",
        "status": "processed",
        "category": "Water",
        "urgency_rating": 4,
        "summary_en": "[DEMO] Audio transcribed: Water supply issue reported",
        "message": "Submission received and is being processed",
    }


@router.post("/intake/image")
async def demo_submit_image():
    return {
        "submission_id": f"sub-{uuid.uuid4().hex[:12]}",
        "status": "processed",
        "category": "Sanitation",
        "urgency_rating": 3,
        "summary_en": "[DEMO] Image analysed: Sanitation issue detected",
        "message": "Submission received and is being processed",
    }


@router.get("/intake/status/{submission_id}")
async def demo_status(submission_id: str):
    return {"submission_id": submission_id, "status": "processed"}


@router.get("/analytics/heatmap")
async def demo_heatmap(category: str = "All", constituency_id: str = "KA-BLR-NORTH-01"):
    data = _HOTSPOTS if category == "All" else [h for h in _HOTSPOTS if h["category"] == category]
    return {"hotspots": data, "total": len(data), "demo": True}


@router.get("/dashboard/overview")
async def demo_overview():
    return {
        "constituency_id": "KA-BLR-NORTH-01",
        "total_submissions": 134,
        "submissions_last_7d": 47,
        "categories": {"Roads": 38, "Water": 31, "Sanitation": 23, "Education": 18, "Health": 24},
        "avg_urgency": 3.7,
        "hotspots_identified": 5,
        "top_category": "Roads",
        "demo": True,
    }


@router.get("/dashboard/projects")
async def demo_projects():
    return {"projects": _HOTSPOTS, "total": len(_HOTSPOTS), "demo": True}


@router.get("/dashboard/submissions")
async def demo_submissions(limit: int = 20, offset: int = 0):
    return {
        "submissions": _SUBMISSIONS[offset: offset + limit],
        "total": len(_SUBMISSIONS),
        "demo": True,
    }


@router.get("/users/profile")
async def demo_profile():
    return {"message": "No profile in demo mode — authenticate via Firebase"}


@router.get("/users/admin/list")
async def demo_users_list(limit: int = 50, offset: int = 0, city: str = None, state: str = None):
    users = [
        {"user_id": f"u-{i:03d}", "phone": f"+9199990{i:05d}", "city": "Bengaluru",
         "state": "Karnataka", "preferred_language": "kn", "submissions_count": (i % 5) + 1,
         "registered_at": (datetime.now(timezone.utc) - timedelta(days=i*2)).isoformat()}
        for i in range(1, 21)
    ]
    return {"users": users[offset:offset+limit], "total": 20, "demo": True}


@router.get("/dashboard/export/csv")
async def demo_export_csv():
    from fastapi.responses import StreamingResponse
    import io
    rows = ["rank,category,ward,complaint_count,priority_score,suggested_project"]
    for h in _HOTSPOTS:
        rows.append(
            f"{h['priority_rank']},{h['category']},{h['ward_id']},"
            f"{h['complaint_count']},{h['priority_score']},\"{h['suggested_project']}\""
        )
    content = "\n".join(rows)
    return StreamingResponse(
        io.BytesIO(content.encode()),
        media_type="text/csv",
        headers={"Content-Disposition": "attachment; filename=janmat_priorities_demo.csv"},
    )


@router.post("/analytics/cluster")
async def demo_cluster(body: dict = None):
    return {"status": "ok", "clusters_identified": 5, "demo": True}


@router.post("/analytics/score")
async def demo_score(body: dict = None):
    return {"status": "ok", "hotspots_scored": 5, "demo": True}


@router.post("/auth/verify")
async def demo_auth():
    import jwt as pyjwt
    token = pyjwt.encode(
        {"sub": "demo-user", "phone": "+91-9999999999", "demo": True},
        "demo-secret",
        algorithm="HS256",
    )
    return {"access_token": token, "token_type": "bearer", "profile_complete": False}


@router.post("/dashboard/auth/login")
async def demo_dashboard_login():
    """OAuth2 password flow stub — used by Node.js dashboard in demo mode."""
    import jwt as pyjwt
    token = pyjwt.encode(
        {"sub": "mp@janmat.demo", "role": "mp", "constituency_id": "KA-BLR-NORTH-01", "demo": True},
        "demo-secret",
        algorithm="HS256",
    )
    return {"access_token": token, "token_type": "bearer", "constituency_id": "KA-BLR-NORTH-01"}


@router.get("/dashboard/heatmap")
async def demo_dashboard_heatmap():
    """Heatmap endpoint as proxied by Node.js dashboard."""
    return {"hotspots": _HOTSPOTS, "total": len(_HOTSPOTS), "demo": True}


@router.get("/dashboard/trends")
async def demo_trends(days: int = 30):
    """Trend data — mock 30-day submission volume by category."""
    return {
        "days": days,
        "series": [
            {"category": "Roads",      "submissions": [4, 3, 5, 6, 4, 3, 7, 5, 6, 4]},
            {"category": "Water",      "submissions": [2, 3, 4, 3, 2, 5, 3, 4, 3, 2]},
            {"category": "Sanitation", "submissions": [1, 2, 2, 3, 1, 2, 2, 3, 2, 1]},
            {"category": "Education",  "submissions": [1, 1, 2, 1, 2, 1, 1, 2, 1, 1]},
            {"category": "Health",     "submissions": [1, 2, 1, 2, 1, 1, 2, 1, 2, 1]},
        ],
        "demo": True,
    }


@router.get("/analytics/stats/{constituency_id}")
async def demo_stats(constituency_id: str):
    """Constituency analytics stats."""
    return {
        "constituency_id": constituency_id,
        "total_submissions": 134,
        "processed": 127,
        "pending": 7,
        "hotspots_identified": 5,
        "avg_urgency": 3.7,
        "top_category": "Roads",
        "category_breakdown": {"Roads": 38, "Water": 31, "Sanitation": 23, "Education": 18, "Health": 24},
        "submission_trend_7d": [12, 15, 11, 18, 14, 9, 16],
        "demo": True,
    }
