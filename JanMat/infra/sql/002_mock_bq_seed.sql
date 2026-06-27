-- ─────────────────────────────────────────
-- Mock Public Infrastructure Data
-- Load into BigQuery: janmat_infrastructure.public_infrastructure
--
-- Simulates Census 2011 + NFHS-5 data for
-- Bangalore North constituency (demo area)
-- ─────────────────────────────────────────
-- Run via:
--   bq load --source_format=NEWLINE_DELIMITED_JSON \
--     janmat_infrastructure.public_infrastructure \
--     gs://janmat-media-{PROJECT_ID}/seed/infrastructure.ndjson
--
-- OR use the Python seed script: /infra/scripts/seed_bigquery.py
-- ─────────────────────────────────────────

-- Education records
INSERT INTO `{PROJECT_ID}.janmat_infrastructure.public_infrastructure`
(village_id, village_name, latitude, longitude, constituency_id, ward_id, population,
 category, primary_schools, secondary_schools, school_enrollment_rate,
 nearest_secondary_school_km, teen_travel_distance_km,
 data_source, reference_year, last_updated)
VALUES
-- Villages severely underserved on education
('VIL-001', 'Yelahanka Village',   13.1007, 77.5963, 'KA-BLR-NORTH-01', 'WARD-04', 12400, 'Education', 2, 0, 0.61, 8.2, 10.1, 'NFHS5', 2021, '2024-01-01'),
('VIL-002', 'Kogilu Cross',        13.0912, 77.6034, 'KA-BLR-NORTH-01', 'WARD-05', 8700,  'Education', 1, 0, 0.54, 6.5, 8.4,  'NFHS5', 2021, '2024-01-01'),
('VIL-003', 'Jakkur Layout',       13.0750, 77.6100, 'KA-BLR-NORTH-01', 'WARD-06', 15200, 'Education', 3, 1, 0.72, 3.1, 4.2,  'Census2011', 2011, '2024-01-01'),
('VIL-004', 'Bagalur Village',     13.1450, 77.6280, 'KA-BLR-NORTH-01', 'WARD-07', 6200,  'Education', 1, 0, 0.48, 12.3, 14.5,'NFHS5', 2021, '2024-01-01'),
('VIL-005', 'Thanisandra Main',    13.0598, 77.6247, 'KA-BLR-NORTH-01', 'WARD-08', 22100, 'Education', 4, 2, 0.81, 1.8, 2.3,  'Census2011', 2011, '2024-01-01'),

-- Health records
('VIL-001', 'Yelahanka Village',   13.1007, 77.5963, 'KA-BLR-NORTH-01', 'WARD-04', 12400, 'Health', NULL, NULL, NULL, NULL, NULL, 'NFHS5', 2021, '2024-01-01'),
('VIL-002', 'Kogilu Cross',        13.0912, 77.6034, 'KA-BLR-NORTH-01', 'WARD-05', 8700,  'Health', NULL, NULL, NULL, NULL, NULL, 'NFHS5', 2021, '2024-01-01'),
('VIL-004', 'Bagalur Village',     13.1450, 77.6280, 'KA-BLR-NORTH-01', 'WARD-07', 6200,  'Health', NULL, NULL, NULL, NULL, NULL, 'NFHS5', 2021, '2024-01-01'),

-- Roads records
('VIL-001', 'Yelahanka Village',   13.1007, 77.5963, 'KA-BLR-NORTH-01', 'WARD-04', 12400, 'Roads', NULL, NULL, NULL, NULL, NULL, 'OpenStreetMap', 2023, '2024-01-01'),
('VIL-004', 'Bagalur Village',     13.1450, 77.6280, 'KA-BLR-NORTH-01', 'WARD-07', 6200,  'Roads', NULL, NULL, NULL, NULL, NULL, 'OpenStreetMap', 2023, '2024-01-01'),

-- Water records
('VIL-001', 'Yelahanka Village',   13.1007, 77.5963, 'KA-BLR-NORTH-01', 'WARD-04', 12400, 'Water', NULL, NULL, NULL, NULL, NULL, 'NFHS5', 2021, '2024-01-01'),
('VIL-002', 'Kogilu Cross',        13.0912, 77.6034, 'KA-BLR-NORTH-01', 'WARD-05', 8700,  'Water', NULL, NULL, NULL, NULL, NULL, 'NFHS5', 2021, '2024-01-01');

-- NOTE: Use infra/scripts/seed_bigquery.py for full dataset loading
-- The above is illustrative SQL; BQ uses standard INSERT syntax only in DML jobs.
