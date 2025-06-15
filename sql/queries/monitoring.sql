-- name: InsertPriceSnapshot :one
INSERT INTO price_snapshots (
    pool_address,
    token0_address,
    token1_address,
    sqrt_price_x96,
    tick,
    liquidity,
    token0_price,
    token1_price
) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
RETURNING id, snapshot_at;

-- name: BulkInsertPriceSnapshots :copyfrom
INSERT INTO price_snapshots (
    pool_address,
    token0_address,
    token1_address,
    sqrt_price_x96,
    tick,
    liquidity,
    token0_price,
    token1_price
) VALUES ($1, $2, $3, $4, $5, $6, $7, $8);

-- name: GetLatestPriceByPool :one
SELECT 
    pool_address,
    token0_address,
    token1_address,
    sqrt_price_x96,
    tick,
    liquidity,
    token0_price,
    token1_price,
    snapshot_at
FROM price_snapshots
WHERE pool_address = $1
ORDER BY snapshot_at DESC
LIMIT 1;

-- name: GetPriceHistory :many
SELECT 
    tick,
    token0_price,
    token1_price,
    snapshot_at
FROM price_snapshots
WHERE pool_address = $1
AND snapshot_at >= $2
AND snapshot_at <= $3
ORDER BY snapshot_at ASC;

-- name: InsertPositionSnapshot :one
INSERT INTO position_snapshots (
    position_id,
    vault_address,
    pool_address,
    token_id,
    tick_current,
    tick_lower,
    tick_upper,
    liquidity,
    in_range,
    range_percentage,
    fees_earned,
    value0,
    value1
) VALUES (
    $1, $2, $3, $4, $5, $6, $7, $8,
    is_position_in_range($5, $6, $7),
    calculate_range_percentage($5, $6, $7),
    $9, $10, $11
)
RETURNING id, snapshot_at, in_range, range_percentage;

-- name: GetLatestPositionSnapshots :many
SELECT DISTINCT ON (position_id)
    id,
    position_id,
    vault_address,
    pool_address,
    token_id,
    tick_current,
    tick_lower,
    tick_upper,
    liquidity,
    in_range,
    range_percentage,
    fees_earned,
    value0,
    value1,
    snapshot_at
FROM position_snapshots
WHERE vault_address = ANY($1::VARCHAR[])
ORDER BY position_id, snapshot_at DESC;

-- name: GetPositionsOutOfRange :many
SELECT 
    position_id,
    vault_address,
    pool_address,
    tick_current,
    tick_lower,
    tick_upper,
    range_percentage,
    liquidity,
    EXTRACT(EPOCH FROM (NOW() - snapshot_at)) as seconds_since_update
FROM position_snapshots ps
WHERE ps.snapshot_at = (
    SELECT MAX(snapshot_at)
    FROM position_snapshots ps2
    WHERE ps2.position_id = ps.position_id
)
AND NOT ps.in_range
AND ps.liquidity > 0
ORDER BY seconds_since_update DESC;

-- name: GetPositionsNearRangeEdge :many
SELECT 
    position_id,
    vault_address,
    pool_address,
    tick_current,
    tick_lower,
    tick_upper,
    range_percentage,
    liquidity
FROM position_snapshots ps
WHERE ps.snapshot_at = (
    SELECT MAX(snapshot_at)
    FROM position_snapshots ps2
    WHERE ps2.position_id = ps.position_id
)
AND ps.in_range = true
AND (ps.range_percentage <= $1 OR ps.range_percentage >= (100 - $1))
AND ps.liquidity > 0;

-- name: InsertVolatilityMetric :one
INSERT INTO volatility_metrics (
    pool_address,
    period_minutes,
    volatility,
    high_price,
    low_price,
    mean_price,
    sample_count
) VALUES ($1, $2, $3, $4, $5, $6, $7)
RETURNING id, calculated_at;

-- name: GetLatestVolatility :one
SELECT 
    volatility,
    high_price,
    low_price,
    mean_price,
    sample_count,
    calculated_at
FROM volatility_metrics
WHERE pool_address = $1
AND period_minutes = $2
ORDER BY calculated_at DESC
LIMIT 1;

-- name: GetVolatilityHistory :many
SELECT 
    period_minutes,
    volatility,
    high_price,
    low_price,
    mean_price,
    calculated_at
FROM volatility_metrics
WHERE pool_address = $1
AND calculated_at >= $2
ORDER BY calculated_at DESC;

-- name: GetMonitoredPools :many
SELECT 
    id,
    pool_address,
    token0_address,
    token1_address,
    fee,
    tick_spacing,
    is_active
FROM monitored_pools
WHERE is_active = true;

-- name: AddMonitoredPool :one
INSERT INTO monitored_pools (
    pool_address,
    token0_address,
    token1_address,
    fee,
    tick_spacing
) VALUES ($1, $2, $3, $4, $5)
RETURNING id;

-- name: GetPositionHistory :many
SELECT 
    tick_current,
    tick_lower,
    tick_upper,
    in_range,
    range_percentage,
    fees_earned,
    snapshot_at
FROM position_snapshots
WHERE position_id = $1
AND snapshot_at >= $2
ORDER BY snapshot_at ASC;