-- Blockchain events with native partitioning
CREATE TABLE blockchain_events (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    block_number BIGINT NOT NULL,
    transaction_hash VARCHAR(66) NOT NULL,
    log_index INTEGER NOT NULL,
    contract_address VARCHAR(42) NOT NULL,
    event_name VARCHAR(100) NOT NULL,
    event_data JSONB NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
) PARTITION BY RANGE (created_at);

-- Setup automatic partitioning for events
SELECT pg_partman.create_parent(
    p_parent_table => 'public.blockchain_events',
    p_control => 'created_at',
    p_type => 'range',
    p_interval => 'daily',
    p_premake => 7,
    p_start_partition => CURRENT_DATE::TEXT
);

-- Price snapshots with partitioning
CREATE TABLE price_snapshots (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    pool_address VARCHAR(42) NOT NULL,
    token0_address VARCHAR(42) NOT NULL,
    token1_address VARCHAR(42) NOT NULL,
    sqrt_price_x96 NUMERIC(78, 0) NOT NULL,
    tick INTEGER NOT NULL,
    liquidity NUMERIC(78, 0) NOT NULL,
    token0_price NUMERIC(40, 18) NOT NULL,
    token1_price NUMERIC(40, 18) NOT NULL,
    snapshot_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
) PARTITION BY RANGE (snapshot_at);

SELECT pg_partman.create_parent(
    p_parent_table => 'public.price_snapshots',
    p_control => 'snapshot_at',
    p_type => 'range',
    p_interval => 'hourly',
    p_premake => 24
);

-- Position snapshots with partitioning
CREATE TABLE position_snapshots (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    position_id UUID NOT NULL,
    vault_address VARCHAR(42) NOT NULL,
    pool_address VARCHAR(42) NOT NULL,
    token_id NUMERIC(78, 0) NOT NULL,
    tick_current INTEGER NOT NULL,
    tick_lower INTEGER NOT NULL,
    tick_upper INTEGER NOT NULL,
    liquidity NUMERIC(78, 0) NOT NULL,
    in_range BOOLEAN NOT NULL,
    range_percentage NUMERIC(5, 2), -- How far from edge (0-100)
    fees_earned NUMERIC(78, 18) DEFAULT 0,
    value0 NUMERIC(78, 18) DEFAULT 0,
    value1 NUMERIC(78, 18) DEFAULT 0,
    snapshot_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
) PARTITION BY RANGE (snapshot_at);

SELECT pg_partman.create_parent(
    p_parent_table => 'public.position_snapshots',
    p_control => 'snapshot_at',
    p_type => 'range',
    p_interval => 'daily',
    p_premake => 7
);

-- Vaults (not partitioned)
CREATE TABLE vaults (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    address VARCHAR(42) UNIQUE NOT NULL,
    name VARCHAR(100) NOT NULL,
    symbol VARCHAR(20) NOT NULL,
    strategy_type VARCHAR(50) NOT NULL,
    pool_address VARCHAR(42) NOT NULL,
    token0_address VARCHAR(42) NOT NULL,
    token1_address VARCHAR(42) NOT NULL,
    pool_fee INTEGER NOT NULL, -- basis points
    performance_fee INTEGER NOT NULL DEFAULT 1000, -- basis points
    management_fee INTEGER NOT NULL DEFAULT 100,
    total_value_locked NUMERIC(78, 18) DEFAULT 0,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Pools being monitored
CREATE TABLE monitored_pools (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    pool_address VARCHAR(42) UNIQUE NOT NULL,
    token0_address VARCHAR(42) NOT NULL,
    token1_address VARCHAR(42) NOT NULL,
    fee INTEGER NOT NULL,
    tick_spacing INTEGER NOT NULL,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Rebalance history
CREATE TABLE rebalance_history (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    vault_id UUID NOT NULL REFERENCES vaults(id),
    position_id UUID NOT NULL,
    old_tick_lower INTEGER NOT NULL,
    old_tick_upper INTEGER NOT NULL,
    new_tick_lower INTEGER NOT NULL,
    new_tick_upper INTEGER NOT NULL,
    old_liquidity NUMERIC(78, 0) NOT NULL,
    new_liquidity NUMERIC(78, 0) NOT NULL,
    gas_used BIGINT NOT NULL,
    gas_price NUMERIC(78, 18) NOT NULL,
    slippage NUMERIC(10, 6),
    reason VARCHAR(200),
    strategy_params JSONB,
    transaction_hash VARCHAR(66),
    executed_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Volatility metrics with partitioning
CREATE TABLE volatility_metrics (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    pool_address VARCHAR(42) NOT NULL,
    period_minutes INTEGER NOT NULL, -- 5, 15, 60, 240, 1440
    volatility NUMERIC(10, 6) NOT NULL, -- Standard deviation
    high_price NUMERIC(40, 18) NOT NULL,
    low_price NUMERIC(40, 18) NOT NULL,
    mean_price NUMERIC(40, 18) NOT NULL,
    sample_count INTEGER NOT NULL,
    calculated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
) PARTITION BY RANGE (calculated_at);

SELECT pg_partman.create_parent(
    p_parent_table => 'public.volatility_metrics',
    p_control => 'calculated_at',
    p_type => 'range',
    p_interval => 'daily',
    p_premake => 7
);

-- Performance metrics with partitioning
CREATE TABLE performance_metrics (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    vault_id UUID NOT NULL,
    metric_type VARCHAR(50) NOT NULL, -- 'apy', 'tvl', 'fees_earned', 'il', 'rebalance_count'
    value NUMERIC(40, 18) NOT NULL,
    period_start TIMESTAMP WITH TIME ZONE NOT NULL,
    period_end TIMESTAMP WITH TIME ZONE NOT NULL,
    recorded_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
) PARTITION BY RANGE (recorded_at);

SELECT pg_partman.create_parent(
    p_parent_table => 'public.performance_metrics',
    p_control => 'recorded_at',
    p_type => 'range',
    p_interval => 'weekly',
    p_premake => 4
);

-- Create indexes for performance
CREATE INDEX CONCURRENTLY idx_events_block_contract 
ON blockchain_events (block_number, contract_address);

CREATE INDEX CONCURRENTLY idx_events_vault_type 
ON blockchain_events ((event_data->>'vault'), event_name, created_at);

CREATE INDEX CONCURRENTLY idx_price_pool_time 
ON price_snapshots (pool_address, snapshot_at DESC);

CREATE INDEX CONCURRENTLY idx_position_vault_time 
ON position_snapshots (vault_address, snapshot_at DESC);

CREATE INDEX CONCURRENTLY idx_position_range_status 
ON position_snapshots (vault_address, in_range, snapshot_at DESC);

CREATE INDEX CONCURRENTLY idx_volatility_pool_period 
ON volatility_metrics (pool_address, period_minutes, calculated_at DESC);

-- Automatic cleanup configuration
UPDATE pg_partman.part_config 
SET retention = '30 days',
    retention_keep_table = false,
    retention_keep_index = false
WHERE parent_table = 'public.blockchain_events';

UPDATE pg_partman.part_config 
SET retention = '7 days',
    retention_keep_table = false,
    retention_keep_index = false
WHERE parent_table = 'public.price_snapshots';

UPDATE pg_partman.part_config 
SET retention = '90 days',
    retention_keep_table = false,
    retention_keep_index = false
WHERE parent_table = 'public.position_snapshots';