"""
seed_grievances.py — Seed synthetic citizen_grievances for a constituency

Usage:
    python infra/scripts/seed_grievances.py --project YOUR_PROJECT_ID \
        [--constituency MH-PUN-WEST-01]

Designed to demo 'new MP onboarded in minutes' — a fresh constituency gets
realistic grievance data so every dashboard tab shows meaningful content
immediately after BigQuery seeding.

Currently ships Pune West (MH-PUN-WEST-01) synthetic data.
"""

import argparse
import uuid
from datetime import datetime, timedelta
import random

from google.cloud import bigquery

PROJECT_ID = None  # Set via --project arg
DATASET_ID = "janmat_analytics"
TABLE_ID   = "citizen_grievances"


def _days_ago(n: int) -> str:
    dt = datetime.utcnow() - timedelta(days=n)
    return dt.strftime("%Y-%m-%d %H:%M:%S UTC")


# ─────────────────────────────────────────────────────────────────────────────
# Pune West — 22 synthetic grievances across categories, languages, input types
# Realistic translated_text, summaries, urgency scores, and geo-coordinates
# ─────────────────────────────────────────────────────────────────────────────
PUNE_WEST_GRIEVANCES = [
    # ── Roads ──────────────────────────────────────────────────────────────
    {
        "submission_id":      str(uuid.uuid4()),
        "input_type":         "audio",
        "raw_input_gcs_uri":  "gs://janmat-media/MH-PUN-WEST-01/audio/sample_road_01.mp4",
        "source_language":    "mr",
        "translated_text":    "The road near Warje Malwadi market has large potholes. Two-wheelers have accidents daily. No repair work in two years.",
        "category":           "Roads",
        "latitude":           18.4815,
        "longitude":          73.8102,
        "summary_en":         "Severe potholes on Warje Malwadi market road causing daily accidents.",
        "urgency_rating":     5,
        "processing_status":  "processed",
        "submitted_at":       _days_ago(3),
        "constituency_id":    "MH-PUN-WEST-01",
    },
    {
        "submission_id":      str(uuid.uuid4()),
        "input_type":         "image",
        "raw_input_gcs_uri":  "gs://janmat-media/MH-PUN-WEST-01/images/pothole_bavdhan.jpg",
        "source_language":    "mr",
        "translated_text":    "Bavdhan Khurd approach road is completely broken after monsoon. Schoolchildren cannot walk safely.",
        "category":           "Roads",
        "latitude":           18.5140,
        "longitude":          73.7710,
        "summary_en":         "Post-monsoon road damage in Bavdhan Khurd blocking safe access for school children.",
        "urgency_rating":     5,
        "processing_status":  "processed",
        "submitted_at":       _days_ago(7),
        "constituency_id":    "MH-PUN-WEST-01",
    },
    {
        "submission_id":      str(uuid.uuid4()),
        "input_type":         "text",
        "raw_input_gcs_uri":  None,
        "source_language":    "en",
        "translated_text":    "Street lights on the Kothrud connector road have been non-functional for 3 months. Night travel is dangerous.",
        "category":           "Roads",
        "latitude":           18.5070,
        "longitude":          73.8082,
        "summary_en":         "Street lights non-functional on Kothrud connector road for 3 months.",
        "urgency_rating":     3,
        "processing_status":  "processed",
        "submitted_at":       _days_ago(14),
        "constituency_id":    "MH-PUN-WEST-01",
    },
    {
        "submission_id":      str(uuid.uuid4()),
        "input_type":         "audio",
        "raw_input_gcs_uri":  "gs://janmat-media/MH-PUN-WEST-01/audio/road_pirangut_02.mp4",
        "source_language":    "mr",
        "translated_text":    "Pirangut to Paud road has no footpath. Pedestrians share the road with trucks. Multiple injuries this month.",
        "category":           "Roads",
        "latitude":           18.5025,
        "longitude":          73.7245,
        "summary_en":         "No footpath on Pirangut-Paud road; pedestrians at risk from truck traffic.",
        "urgency_rating":     4,
        "processing_status":  "processed",
        "submitted_at":       _days_ago(5),
        "constituency_id":    "MH-PUN-WEST-01",
    },
    # ── Water ──────────────────────────────────────────────────────────────
    {
        "submission_id":      str(uuid.uuid4()),
        "input_type":         "text",
        "raw_input_gcs_uri":  None,
        "source_language":    "mr",
        "translated_text":    "Piped water supply in Pirangut village comes only twice a week and is muddy. Residents forced to buy tankers.",
        "category":           "Water",
        "latitude":           18.5018,
        "longitude":          73.7238,
        "summary_en":         "Pirangut village receives muddy piped water only twice weekly; residents buying tanker water.",
        "urgency_rating":     5,
        "processing_status":  "processed",
        "submitted_at":       _days_ago(2),
        "constituency_id":    "MH-PUN-WEST-01",
    },
    {
        "submission_id":      str(uuid.uuid4()),
        "input_type":         "image",
        "raw_input_gcs_uri":  "gs://janmat-media/MH-PUN-WEST-01/images/water_leak_warje.jpg",
        "source_language":    "en",
        "translated_text":    "A major water pipeline is leaking near Warje signal for two weeks. Huge wastage and road waterlogging.",
        "category":           "Water",
        "latitude":           18.4820,
        "longitude":          73.8090,
        "summary_en":         "Two-week pipeline leak at Warje signal causing water wastage and road flooding.",
        "urgency_rating":     4,
        "processing_status":  "processed",
        "submitted_at":       _days_ago(10),
        "constituency_id":    "MH-PUN-WEST-01",
    },
    {
        "submission_id":      str(uuid.uuid4()),
        "input_type":         "audio",
        "raw_input_gcs_uri":  "gs://janmat-media/MH-PUN-WEST-01/audio/water_bavdhan.mp4",
        "source_language":    "mr",
        "translated_text":    "Bavdhan Khurd has no municipal water connection. We depend entirely on private water tankers at Rs 500 per load.",
        "category":           "Water",
        "latitude":           18.5130,
        "longitude":          73.7700,
        "summary_en":         "Bavdhan Khurd has no municipal water; community pays Rs 500 per tanker load.",
        "urgency_rating":     5,
        "processing_status":  "processed",
        "submitted_at":       _days_ago(18),
        "constituency_id":    "MH-PUN-WEST-01",
    },
    # ── Education ──────────────────────────────────────────────────────────
    {
        "submission_id":      str(uuid.uuid4()),
        "input_type":         "text",
        "raw_input_gcs_uri":  None,
        "source_language":    "mr",
        "translated_text":    "ZP primary school in Warje has 280 students but only 4 teachers. Upper primary classes are absent most days.",
        "category":           "Education",
        "latitude":           18.4808,
        "longitude":          73.8095,
        "summary_en":         "Warje ZP school has 280 students but only 4 teachers; upper primary classes not held regularly.",
        "urgency_rating":     4,
        "processing_status":  "processed",
        "submitted_at":       _days_ago(21),
        "constituency_id":    "MH-PUN-WEST-01",
    },
    {
        "submission_id":      str(uuid.uuid4()),
        "input_type":         "audio",
        "raw_input_gcs_uri":  "gs://janmat-media/MH-PUN-WEST-01/audio/school_pirangut.mp4",
        "source_language":    "mr",
        "translated_text":    "Pirangut village has no secondary school. Children must travel 12 km to Paud, many girls drop out after 7th grade.",
        "category":           "Education",
        "latitude":           18.5022,
        "longitude":          73.7242,
        "summary_en":         "No secondary school in Pirangut; girls dropping out at 7th grade due to 12 km travel distance.",
        "urgency_rating":     5,
        "processing_status":  "processed",
        "submitted_at":       _days_ago(6),
        "constituency_id":    "MH-PUN-WEST-01",
    },
    {
        "submission_id":      str(uuid.uuid4()),
        "input_type":         "image",
        "raw_input_gcs_uri":  "gs://janmat-media/MH-PUN-WEST-01/images/school_roof_bavdhan.jpg",
        "source_language":    "mr",
        "translated_text":    "The roof of Bavdhan Khurd primary school is leaking. During rains, classrooms flood and children cannot study.",
        "category":           "Education",
        "latitude":           18.5132,
        "longitude":          73.7708,
        "summary_en":         "Bavdhan Khurd primary school roof leaking; classrooms flooded during rains.",
        "urgency_rating":     4,
        "processing_status":  "processed",
        "submitted_at":       _days_ago(9),
        "constituency_id":    "MH-PUN-WEST-01",
    },
    # ── Health ─────────────────────────────────────────────────────────────
    {
        "submission_id":      str(uuid.uuid4()),
        "input_type":         "text",
        "raw_input_gcs_uri":  None,
        "source_language":    "en",
        "translated_text":    "Pirangut village primary health centre is open only 3 days a week. No doctor available on weekends. Patients go to Paud.",
        "category":           "Health",
        "latitude":           18.5016,
        "longitude":          73.7236,
        "summary_en":         "Pirangut PHC open only 3 days/week; no weekend doctor — patients travel 15 km to Paud.",
        "urgency_rating":     5,
        "processing_status":  "processed",
        "submitted_at":       _days_ago(4),
        "constituency_id":    "MH-PUN-WEST-01",
    },
    {
        "submission_id":      str(uuid.uuid4()),
        "input_type":         "audio",
        "raw_input_gcs_uri":  "gs://janmat-media/MH-PUN-WEST-01/audio/health_warje.mp4",
        "source_language":    "mr",
        "translated_text":    "No maternity ward in the area. Pregnant women travel to KEM Hospital which is 9 km away. Two deliveries happened at home last month.",
        "category":           "Health",
        "latitude":           18.4812,
        "longitude":          73.8097,
        "summary_en":         "No local maternity care; two home deliveries last month due to 9 km distance to nearest maternity facility.",
        "urgency_rating":     5,
        "processing_status":  "processed",
        "submitted_at":       _days_ago(8),
        "constituency_id":    "MH-PUN-WEST-01",
    },
    {
        "submission_id":      str(uuid.uuid4()),
        "input_type":         "text",
        "raw_input_gcs_uri":  None,
        "source_language":    "mr",
        "translated_text":    "Bavdhan dispensary has been out of basic medicines for three months. Patients buy at pharmacies at full price.",
        "category":           "Health",
        "latitude":           18.5136,
        "longitude":          73.7706,
        "summary_en":         "Bavdhan dispensary has had no essential medicines for 3 months.",
        "urgency_rating":     4,
        "processing_status":  "processed",
        "submitted_at":       _days_ago(25),
        "constituency_id":    "MH-PUN-WEST-01",
    },
    # ── Sanitation ─────────────────────────────────────────────────────────
    {
        "submission_id":      str(uuid.uuid4()),
        "input_type":         "image",
        "raw_input_gcs_uri":  "gs://janmat-media/MH-PUN-WEST-01/images/garbage_warje.jpg",
        "source_language":    "en",
        "translated_text":    "Garbage not collected in Warje Malwadi for 10 days. Pile is near the school and poses health risk to children.",
        "category":           "Sanitation",
        "latitude":           18.4817,
        "longitude":          73.8100,
        "summary_en":         "10-day garbage backlog next to Warje Malwadi school; health risk to children.",
        "urgency_rating":     4,
        "processing_status":  "processed",
        "submitted_at":       _days_ago(1),
        "constituency_id":    "MH-PUN-WEST-01",
    },
    {
        "submission_id":      str(uuid.uuid4()),
        "input_type":         "audio",
        "raw_input_gcs_uri":  "gs://janmat-media/MH-PUN-WEST-01/audio/sanitation_pirangut.mp4",
        "source_language":    "mr",
        "translated_text":    "No public toilets in Pirangut. Women are forced to use open areas. Swachh Bharat toilet built last year is locked and unusable.",
        "category":           "Sanitation",
        "latitude":           18.5024,
        "longitude":          73.7239,
        "summary_en":         "Pirangut lacks usable public toilets; Swachh Bharat toilet locked — women using open areas.",
        "urgency_rating":     5,
        "processing_status":  "processed",
        "submitted_at":       _days_ago(12),
        "constituency_id":    "MH-PUN-WEST-01",
    },
    {
        "submission_id":      str(uuid.uuid4()),
        "input_type":         "text",
        "raw_input_gcs_uri":  None,
        "source_language":    "mr",
        "translated_text":    "Open drain in Bavdhan Khurd overflowing into the road during rains. Breeding ground for mosquitoes, dengue cases rising.",
        "category":           "Sanitation",
        "latitude":           18.5133,
        "longitude":          73.7703,
        "summary_en":         "Open drain overflow in Bavdhan Khurd creating dengue breeding ground during rains.",
        "urgency_rating":     5,
        "processing_status":  "processed",
        "submitted_at":       _days_ago(16),
        "constituency_id":    "MH-PUN-WEST-01",
    },
    # ── Electricity ────────────────────────────────────────────────────────
    {
        "submission_id":      str(uuid.uuid4()),
        "input_type":         "text",
        "raw_input_gcs_uri":  None,
        "source_language":    "en",
        "translated_text":    "Power cuts in Kothrud Extension area last 6-8 hours daily. MSEDCL complaints are not addressed.",
        "category":           "Electricity",
        "latitude":           18.5068,
        "longitude":          73.8074,
        "summary_en":         "Kothrud Extension faces 6-8 hour daily power cuts; MSEDCL unresponsive to complaints.",
        "urgency_rating":     3,
        "processing_status":  "processed",
        "submitted_at":       _days_ago(20),
        "constituency_id":    "MH-PUN-WEST-01",
    },
    {
        "submission_id":      str(uuid.uuid4()),
        "input_type":         "audio",
        "raw_input_gcs_uri":  "gs://janmat-media/MH-PUN-WEST-01/audio/electricity_pirangut.mp4",
        "source_language":    "mr",
        "translated_text":    "Pirangut has no electricity for 3 homes near the old temple. Grid extension request pending for 2 years.",
        "category":           "Electricity",
        "latitude":           18.5019,
        "longitude":          73.7243,
        "summary_en":         "Three Pirangut homes lack electricity access; grid extension application pending 2 years.",
        "urgency_rating":     4,
        "processing_status":  "processed",
        "submitted_at":       _days_ago(30),
        "constituency_id":    "MH-PUN-WEST-01",
    },
    # ── Flooding ───────────────────────────────────────────────────────────
    {
        "submission_id":      str(uuid.uuid4()),
        "input_type":         "image",
        "raw_input_gcs_uri":  "gs://janmat-media/MH-PUN-WEST-01/images/flood_warje.jpg",
        "source_language":    "mr",
        "translated_text":    "Warje low-lying area floods every monsoon. Houses submerged for 3-4 days. No drainage plan from PMC in 5 years.",
        "category":           "Flooding",
        "latitude":           18.4805,
        "longitude":          73.8088,
        "summary_en":         "Warje low-lying area floods every monsoon; no PMC drainage plan for 5 years.",
        "urgency_rating":     5,
        "processing_status":  "processed",
        "submitted_at":       _days_ago(45),
        "constituency_id":    "MH-PUN-WEST-01",
    },
    {
        "submission_id":      str(uuid.uuid4()),
        "input_type":         "text",
        "raw_input_gcs_uri":  None,
        "source_language":    "en",
        "translated_text":    "Storm water drain near Bavdhan Khurd is choked with debris. Roads flood within 30 minutes of rain.",
        "category":           "Flooding",
        "latitude":           18.5128,
        "longitude":          73.7695,
        "summary_en":         "Choked storm drain in Bavdhan Khurd causes road flooding within 30 minutes of rain.",
        "urgency_rating":     4,
        "processing_status":  "processed",
        "submitted_at":       _days_ago(33),
        "constituency_id":    "MH-PUN-WEST-01",
    },
    # ── Agriculture ────────────────────────────────────────────────────────
    {
        "submission_id":      str(uuid.uuid4()),
        "input_type":         "audio",
        "raw_input_gcs_uri":  "gs://janmat-media/MH-PUN-WEST-01/audio/agri_pirangut.mp4",
        "source_language":    "mr",
        "translated_text":    "No agricultural extension officer in Pirangut taluka. Farmers unaware of PM-KISAN scheme. Last visit was 18 months ago.",
        "category":           "Agriculture",
        "latitude":           18.5021,
        "longitude":          73.7241,
        "summary_en":         "No agricultural extension officer in Pirangut for 18 months; farmers missing PM-KISAN benefits.",
        "urgency_rating":     3,
        "processing_status":  "processed",
        "submitted_at":       _days_ago(50),
        "constituency_id":    "MH-PUN-WEST-01",
    },
    {
        "submission_id":      str(uuid.uuid4()),
        "input_type":         "text",
        "raw_input_gcs_uri":  None,
        "source_language":    "mr",
        "translated_text":    "Mula river embankment near Bavdhan is eroding. Farm land is being lost. Dam authority not responding.",
        "category":           "Agriculture",
        "latitude":           18.5145,
        "longitude":          73.7720,
        "summary_en":         "Mula river bank erosion near Bavdhan destroying farmland; dam authority unresponsive.",
        "urgency_rating":     4,
        "processing_status":  "processed",
        "submitted_at":       _days_ago(60),
        "constituency_id":    "MH-PUN-WEST-01",
    },
]


def seed(project_id: str, constituency: str = "MH-PUN-WEST-01") -> None:
    if constituency != "MH-PUN-WEST-01":
        print(f"ℹ️  No synthetic grievances defined for {constituency} — skipping.")
        return

    client = bigquery.Client(project=project_id)
    table_ref = f"{project_id}.{DATASET_ID}.{TABLE_ID}"

    rows = PUNE_WEST_GRIEVANCES
    errors = client.insert_rows_json(table_ref, rows)
    if errors:
        print(f"❌ BigQuery insert errors: {errors}")
        raise RuntimeError("Grievance seed failed")

    print(f"✅ Seeded {len(rows)} grievance rows into {table_ref} (constituency={constituency})")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--project",      required=True, help="GCP Project ID")
    parser.add_argument("--constituency", default="MH-PUN-WEST-01",
                        choices=["MH-PUN-WEST-01"],
                        help="Target constituency (default: MH-PUN-WEST-01)")
    args = parser.parse_args()
    seed(args.project, args.constituency)
