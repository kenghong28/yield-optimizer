-- Function to calculate if a position is in range
CREATE OR REPLACE FUNCTION is_position_in_range(
    p_tick_current INTEGER,
    p_tick_lower INTEGER,
    p_tick_upper INTEGER
) RETURNS BOOLEAN AS $$
BEGIN
    RETURN p_tick_current >= p_tick_lower AND p_tick_current < p_tick_upper;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Function to calculate range percentage (0-100, where 50 is middle of range)
CREATE OR REPLACE FUNCTION calculate_range_percentage(
    p_tick_current INTEGER,
    p_tick_lower INTEGER,
    p_tick_upper INTEGER
) RETURNS NUMERIC AS $$
DECLARE
    range_size INTEGER;
    position_in_range INTEGER;
BEGIN
    IF p_tick_current < p_tick_lower THEN
        RETURN 0;
    ELSIF p_tick_current >= p_tick_upper THEN
        RETURN 100;
    ELSE
        range_size := p_tick_upper - p_tick_lower;
        position_in_range := p_tick_current - p_tick_lower;
        RETURN ROUND((position_in_range::NUMERIC / range_size::NUMERIC) * 100, 2);
    END IF;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Function to get latest position status for a vault
CREATE OR REPLACE FUNCTION get_latest_position_status(p_vault_address VARCHAR)
RETURNS TABLE (
    position_id UUID,
    vault_address VARCHAR,
    pool_address VARCHAR,
    tick_current INTEGER,
    tick_lower INTEGER,
    tick_upper INTEGER,
    in_range BOOLEAN,
    range_percentage NUMERIC,
    liquidity NUMERIC,
    last_update TIMESTAMP WITH TIME ZONE
) AS $$
BEGIN
    RETURN QUERY
    SELECT DISTINCT ON (ps.position_id)
        ps.position_id,
        ps.vault_address,
        ps.pool_address,
        ps.tick_current,
        ps.tick_lower,
        ps.tick_upper,
        ps.in_range,
        ps.range_percentage,
        ps.liquidity,
        ps.snapshot_at as last_update
    FROM position_snapshots ps
    WHERE ps.vault_address = p_vault_address
    ORDER BY ps.position_id, ps.snapshot_at DESC;
END;
$$ LANGUAGE plpgsql;

-- Function to calculate volatility for a pool
CREATE OR REPLACE FUNCTION calculate_pool_volatility(
    p_pool_address VARCHAR,
    p_period_minutes INTEGER
) RETURNS TABLE (
    volatility NUMERIC,
    high_price NUMERIC,
    low_price NUMERIC,
    mean_price NUMERIC,
    sample_count INTEGER
) AS $$
BEGIN
    RETURN QUERY
    WITH price_data AS (
        SELECT 
            token0_price,
            snapshot_at
        FROM price_snapshots
        WHERE pool_address = p_pool_address
        AND snapshot_at >= NOW() - (p_period_minutes || ' minutes')::INTERVAL
        ORDER BY snapshot_at
    ),
    stats AS (
        SELECT 
            STDDEV(token0_price) as volatility,
            MAX(token0_price) as high_price,
            MIN(token0_price) as low_price,
            AVG(token0_price) as mean_price,
            COUNT(*) as sample_count
        FROM price_data
    )
    SELECT 
        COALESCE(stats.volatility, 0),
        COALESCE(stats.high_price, 0),
        COALESCE(stats.low_price, 0),
        COALESCE(stats.mean_price, 0),
        COALESCE(stats.sample_count, 0)::INTEGER
    FROM stats;
END;
$$ LANGUAGE plpgsql;

-- Function to get positions needing rebalance
CREATE OR REPLACE FUNCTION get_positions_needing_rebalance(
    p_out_of_range_minutes INTEGER DEFAULT 5,
    p_range_threshold NUMERIC DEFAULT 10.0
) RETURNS TABLE (
    position_id UUID,
    vault_address VARCHAR,
    pool_address VARCHAR,
    tick_current INTEGER,
    tick_lower INTEGER,
    tick_upper INTEGER,
    range_percentage NUMERIC,
    minutes_out_of_range INTEGER,
    liquidity NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    WITH latest_positions AS (
        SELECT DISTINCT ON (ps.position_id)
            ps.position_id,
            ps.vault_address,
            ps.pool_address,
            ps.tick_current,
            ps.tick_lower,
            ps.tick_upper,
            ps.range_percentage,
            ps.in_range,
            ps.liquidity,
            ps.snapshot_at
        FROM position_snapshots ps
        WHERE ps.liquidity > 0
        ORDER BY ps.position_id, ps.snapshot_at DESC
    ),
    out_of_range_duration AS (
        SELECT 
            lp.position_id,
            lp.vault_address,
            lp.pool_address,
            lp.tick_current,
            lp.tick_lower,
            lp.tick_upper,
            lp.range_percentage,
            lp.liquidity,
            MIN(ps.snapshot_at) as first_out_of_range
        FROM latest_positions lp
        JOIN position_snapshots ps ON ps.position_id = lp.position_id
        WHERE ps.snapshot_at > NOW() - INTERVAL '1 hour'
        AND (NOT ps.in_range OR ps.range_percentage <= p_range_threshold OR ps.range_percentage >= (100 - p_range_threshold))
        GROUP BY lp.position_id, lp.vault_address, lp.pool_address, 
                 lp.tick_current, lp.tick_lower, lp.tick_upper, 
                 lp.range_percentage, lp.liquidity
    )
    SELECT 
        oor.position_id,
        oor.vault_address,
        oor.pool_address,
        oor.tick_current,
        oor.tick_lower,
        oor.tick_upper,
        oor.range_percentage,
        EXTRACT(EPOCH FROM (NOW() - oor.first_out_of_range)) / 60 as minutes_out_of_range,
        oor.liquidity
    FROM out_of_range_duration oor
    WHERE EXTRACT(EPOCH FROM (NOW() - oor.first_out_of_range)) / 60 >= p_out_of_range_minutes;
END;
$$ LANGUAGE plpgsql;

-- Function to calculate optimal tick range based on volatility
CREATE OR REPLACE FUNCTION calculate_optimal_tick_range(
    p_current_tick INTEGER,
    p_volatility NUMERIC,
    p_tick_spacing INTEGER,
    p_range_multiplier NUMERIC DEFAULT 2.0
) RETURNS TABLE (
    tick_lower INTEGER,
    tick_upper INTEGER
) AS $$
DECLARE
    tick_range INTEGER;
BEGIN
    -- Calculate tick range based on volatility
    -- Higher volatility = wider range
    tick_range := GREATEST(
        p_tick_spacing * 2, -- Minimum range
        ROUND(p_volatility * p_range_multiplier * 10000 / p_tick_spacing) * p_tick_spacing
    );
    
    -- Center the range around current tick
    tick_lower := (p_current_tick - tick_range / 2) / p_tick_spacing * p_tick_spacing;
    tick_upper := tick_lower + tick_range;
    
    RETURN QUERY SELECT tick_lower, tick_upper;
END;
$$ LANGUAGE plpgsql;