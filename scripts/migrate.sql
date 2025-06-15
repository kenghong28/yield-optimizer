-- Migration script for setting up the yield optimizer database
-- Run this manually in your PostgreSQL database

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Create basic tables without partitioning for testing
-- (partitioning extensions might not be available in test environment)

-- Monitored pools
CREATE TABLE IF NOT EXISTS monitored_pools (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    pool_address VARCHAR(42) UNIQUE NOT NULL,
    token0_address VARCHAR(42) NOT NULL,
    token1_address VARCHAR(42) NOT NULL,
    fee INTEGER NOT NULL,
    tick_spacing INTEGER NOT NULL,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Blockchain events (simplified for testing)
CREATE TABLE IF NOT EXISTS blockchain_events (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    block_number BIGINT NOT NULL,
    transaction_hash VARCHAR(66) NOT NULL,
    log_index INTEGER NOT NULL,
    contract_address VARCHAR(42) NOT NULL,
    event_name VARCHAR(100) NOT NULL,
    event_data JSONB NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Price snapshots (simplified for testing)
CREATE TABLE IF NOT EXISTS price_snapshots (
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
);

-- Position snapshots (simplified for testing)
CREATE TABLE IF NOT EXISTS position_snapshots (
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
    range_percentage NUMERIC(5, 2),
    fees_earned NUMERIC(78, 18) DEFAULT 0,
    value0 NUMERIC(78, 18) DEFAULT 0,
    value1 NUMERIC(78, 18) DEFAULT 0,
    snapshot_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Volatility metrics (simplified for testing)
CREATE TABLE IF NOT EXISTS volatility_metrics (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    pool_address VARCHAR(42) NOT NULL,
    period_minutes INTEGER NOT NULL,
    volatility NUMERIC(10, 6) NOT NULL,
    high_price NUMERIC(40, 18) NOT NULL,
    low_price NUMERIC(40, 18) NOT NULL,
    mean_price NUMERIC(40, 18) NOT NULL,
    sample_count INTEGER NOT NULL,
    calculated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Vaults
CREATE TABLE IF NOT EXISTS vaults (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    address VARCHAR(42) UNIQUE NOT NULL,
    name VARCHAR(100) NOT NULL,
    symbol VARCHAR(20) NOT NULL,
    strategy_type VARCHAR(50) NOT NULL,
    pool_address VARCHAR(42) NOT NULL,
    token0_address VARCHAR(42) NOT NULL,
    token1_address VARCHAR(42) NOT NULL,
    pool_fee INTEGER NOT NULL,
    performance_fee INTEGER NOT NULL DEFAULT 1000,
    management_fee INTEGER NOT NULL DEFAULT 100,
    total_value_locked NUMERIC(78, 18) DEFAULT 0,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Performance metrics (simplified for testing)
CREATE TABLE IF NOT EXISTS performance_metrics (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    vault_id UUID NOT NULL,
    metric_type VARCHAR(50) NOT NULL,
    value NUMERIC(40, 18) NOT NULL,
    period_start TIMESTAMP WITH TIME ZONE NOT NULL,
    period_end TIMESTAMP WITH TIME ZONE NOT NULL,
    recorded_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Rebalance history
CREATE TABLE IF NOT EXISTS rebalance_history (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    vault_id UUID NOT NULL,
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

-- Create basic indexes
CREATE INDEX IF NOT EXISTS idx_events_block_contract ON blockchain_events (block_number, contract_address);
CREATE INDEX IF NOT EXISTS idx_price_pool_time ON price_snapshots (pool_address, snapshot_at DESC);
CREATE INDEX IF NOT EXISTS idx_position_vault_time ON position_snapshots (vault_address, snapshot_at DESC);

-- Insert test data
INSERT INTO monitored_pools (pool_address, token0_address, token1_address, fee, tick_spacing) VALUES
('0x1111111111111111111111111111111111111111', '0x2222222222222222222222222222222222222222', '0x3333333333333333333333333333333333333333', 3000, 60)
ON CONFLICT (pool_address) DO NOTHING;

-- Test functions (simplified without partitioning dependencies)
CREATE OR REPLACE FUNCTION is_position_in_range(
    p_tick_current INTEGER,
    p_tick_lower INTEGER,
    p_tick_upper INTEGER
) RETURNS BOOLEAN AS $$
BEGIN
    RETURN p_tick_current >= p_tick_lower AND p_tick_current < p_tick_upper;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

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