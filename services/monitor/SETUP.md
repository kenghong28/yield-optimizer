# Monitor Service Setup Guide

## Prerequisites

1. **Supabase Database** - You already have the connection URL
2. **Redis Instance** - For caching (optional for testing)

## Database Setup

### Step 1: Run SQL Schema in Supabase

1. Go to your Supabase project dashboard
2. Navigate to **SQL Editor**
3. Run the following SQL files in order:

**First, run extensions:**
```sql
-- Enable required PostgreSQL extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
-- Note: pg_partman might not be available in Supabase, skip if error
-- CREATE EXTENSION IF NOT EXISTS "pg_partman";
CREATE EXTENSION IF NOT EXISTS "pg_stat_statements";
```

**Then, run the table creation script (simplified for Supabase):**
```sql
-- Monitored pools
CREATE TABLE monitored_pools (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    pool_address VARCHAR(42) NOT NULL UNIQUE,
    token0_address VARCHAR(42) NOT NULL,
    token1_address VARCHAR(42) NOT NULL,
    fee INTEGER NOT NULL,
    tick_spacing INTEGER NOT NULL,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Price snapshots (simplified without partitioning for Supabase)
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
);

-- Position snapshots
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
    fees_earned NUMERIC(40, 18) DEFAULT 0,
    value0 NUMERIC(40, 18) DEFAULT 0,
    value1 NUMERIC(40, 18) DEFAULT 0,
    in_range BOOLEAN NOT NULL,
    range_percentage NUMERIC(10, 4),
    snapshot_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Volatility metrics
CREATE TABLE volatility_metrics (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    pool_address VARCHAR(42) NOT NULL,
    period_minutes INTEGER NOT NULL,
    volatility NUMERIC(20, 10) NOT NULL,
    high_price NUMERIC(40, 18) NOT NULL,
    low_price NUMERIC(40, 18) NOT NULL,
    mean_price NUMERIC(40, 18) NOT NULL,
    sample_count INTEGER NOT NULL,
    calculated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create indexes for better performance
CREATE INDEX idx_price_snapshots_pool_time ON price_snapshots(pool_address, snapshot_at DESC);
CREATE INDEX idx_position_snapshots_position_time ON position_snapshots(position_id, snapshot_at DESC);
CREATE INDEX idx_position_snapshots_range ON position_snapshots(in_range, snapshot_at DESC);
CREATE INDEX idx_volatility_metrics_pool_period ON volatility_metrics(pool_address, period_minutes, calculated_at DESC);
```

### Step 2: Add Sample Data (Optional)

To test the service, you can add a sample monitored pool:

```sql
INSERT INTO monitored_pools (
    pool_address,
    token0_address,
    token1_address,
    fee,
    tick_spacing
) VALUES (
    '0x1234567890abcdef1234567890abcdef12345678',
    '0xA0b86a33E6441b1c29030E8C0ad2f2cbACA3d95',  -- Example token0
    '0xB31f66aa3c1e785363f0875a1b74e27b85fd66c7',  -- Example token1
    3000,  -- 0.3% fee
    60     -- Tick spacing
);
```

## Redis Setup (Optional)

For local Redis:
```bash
# Install Redis
brew install redis

# Start Redis
redis-server
```

Or use Docker:
```bash
docker run -d -p 6379:6379 redis:7-alpine
```

## Run the Monitor Service

1. **Update environment variables** (already done):
   ```bash
   DATABASE_URL=postgresql://postgres:Bto1Ane6W7t9vcoN@db.mlqhxgvmztducrhmkhzw.supabase.co:5432/postgres
   REDIS_URL=localhost:6379
   ```

2. **Start the service**:
   ```bash
   cd /Users/kenghong/claude-playground/yield-optimizer/services/monitor
   ./monitor
   ```

## Troubleshooting

### Connection Issues
- Ensure your IP is whitelisted in Supabase
- Check if the database URL is correct
- Verify network connectivity

### Missing Tables
- Run the SQL schema setup above
- Check Supabase logs for any errors

### Redis Connection
- Redis is optional for basic functionality
- Service will warn but continue without Redis

## Expected Behavior

Once properly set up, the monitor service will:
1. ✅ Connect to Supabase PostgreSQL
2. ✅ Connect to HyperEVM blockchain
3. ✅ Start monitoring pools and positions
4. ✅ Log price updates and range checks