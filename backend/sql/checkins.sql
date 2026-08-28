-- =============================================================================
-- ATMOS TRS — check-ins (reference schema for PostgreSQL / MySQL / analytics)
-- Mirrors Firestore collection `checkins`: user_id, location_id, checkin_time
-- Every QR scan inserts a new row (no deduplication at insert).
-- =============================================================================

CREATE TABLE IF NOT EXISTS checkins (
  id              BIGSERIAL PRIMARY KEY,
  user_id         TEXT NOT NULL,
  location_id     TEXT NOT NULL,
  checkin_time    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_checkins_user_location_time
  ON checkins (user_id, location_id, checkin_time DESC);

CREATE INDEX IF NOT EXISTS idx_checkins_time
  ON checkins (checkin_time DESC);

CREATE INDEX IF NOT EXISTS idx_checkins_location
  ON checkins (location_id);

-- -----------------------------------------------------------------------------
-- Analytics (date range + optional location filter)
-- Replace :start, :end, :location_id as needed.
-- -----------------------------------------------------------------------------

-- 1) Total check-ins (COUNT(*))
SELECT COUNT(*) AS total_checkins
FROM checkins
WHERE checkin_time >= :start
  AND checkin_time < :end
  AND (:location_id IS NULL OR location_id = :location_id);

-- 2) Unique tourists (COUNT(DISTINCT user_id)) — each person counts once
SELECT COUNT(DISTINCT user_id) AS unique_tourists
FROM checkins
WHERE checkin_time >= :start
  AND checkin_time < :end
  AND (:location_id IS NULL OR location_id = :location_id);

-- Combined summary (one row)
SELECT
  COUNT(*) AS total_checkins,
  COUNT(DISTINCT user_id) AS unique_tourists
FROM checkins
WHERE checkin_time >= :start
  AND checkin_time < :end
  AND (:location_id IS NULL OR location_id = :location_id);

-- Per-location breakdown (optional)
SELECT
  location_id,
  COUNT(*) AS total_checkins,
  COUNT(DISTINCT user_id) AS unique_tourists
FROM checkins
WHERE checkin_time >= :start
  AND checkin_time < :end
GROUP BY location_id
ORDER BY total_checkins DESC;
