# Database Strategy for HyperEVM Yield Optimizer with Supabase

## Current Supabase TimescaleDB Status

### 🚨 **Key Facts from Supabase Documentation**
- **Deprecated in PostgreSQL 17**: TimescaleDB extension is deprecated in Supabase projects using Postgres 17
- **Still supported in PostgreSQL 15**: Continue to work in Postgres 15 projects
- **Migration Required**: Must drop TimescaleDB before upgrading to Postgres 17
- **Limited Edition**: Supabase offers TimescaleDB Apache 2 Edition (some Community features unavailable)

## Recommended Database Architecture for Supabase

### Option 1: Supabase PostgreSQL 17 + Native Time-Series (Recommended)

Since you're using Supabase, leverage PostgreSQL 17's native capabilities instead of TimescaleDB:

```sql
-- Supabase PostgreSQL 17 Native Approach
-- Use native partitioning for time-series data

-- Events table with native partitioning
CREATE TABLE blockchain_events (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    block_number BIGINT NOT NULL,
    transaction_hash VARCHAR(66) NOT NULL,
    log_index INTEGER NOT NULL,
    contract_address VARCHAR(42) NOT NULL,
    event_name VARCHAR(100),
    event_data JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
) PARTITION BY RANGE (created_at);

-- Create partitions (can be automated with pg_cron)
CREATE TABLE blockchain_events_2024_12 PARTITION OF blockchain_events
FOR VALUES FROM ('2024-12-01') TO ('2025-01-01');

CREATE TABLE blockchain_events_2025_01 PARTITION OF blockchain_events
FOR VALUES FROM ('2025-01-01') TO ('2025-02-01');

-- Indexes optimized for time-series queries
CREATE INDEX idx_events_time_block ON blockchain_events (created_at, block_number);
CREATE INDEX idx_events_contract ON blockchain_events (contract_address, created_at);
CREATE INDEX idx_events_jsonb_gin ON blockchain_events USING GIN (event_data);

-- Position status tracking
CREATE TABLE position_snapshots (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    position_id UUID NOT NULL,
    vault_address VARCHAR(42) NOT NULL,
    tick_current INTEGER,
    tick_lower INTEGER,
    tick_upper INTEGER,
    liquidity NUMERIC(78, 0),
    in_range BOOLEAN,
    fees_earned NUMERIC(78, 18),
    snapshot_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
) PARTITION BY RANGE (snapshot_at);

-- Performance metrics table
CREATE TABLE performance_metrics (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    vault_id UUID NOT NULL,
    metric_type VARCHAR(50) NOT NULL, -- 'apy', 'tvl', 'fees', 'il'
    value NUMERIC(20, 8),
    period_start TIMESTAMP WITH TIME ZONE,
    period_end TIMESTAMP WITH TIME ZONE,
    recorded_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
) PARTITION BY RANGE (recorded_at);
```

### Supabase-Specific Optimizations

```sql
-- Use Supabase RLS for security
ALTER TABLE blockchain_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE position_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE performance_metrics ENABLE ROW LEVEL SECURITY;

-- Example RLS policies
CREATE POLICY "Users can view their vault events" ON blockchain_events
FOR SELECT USING (
    event_data->>'vault_owner' = auth.uid()::TEXT OR
    auth.role() = 'service_role'
);

-- Use Supabase realtime for live updates
ALTER PUBLICATION supabase_realtime ADD TABLE position_snapshots;
ALTER PUBLICATION supabase_realtime ADD TABLE performance_metrics;

-- Use pg_cron for automated partition management
SELECT cron.schedule(
    'create_monthly_partitions',
    '0 0 1 * *', -- First day of each month
    $$
    -- Create next month's partitions automatically
    $$
);
```

### Supabase Database Functions for Time-Series Analytics

```sql
-- Function to calculate position performance
CREATE OR REPLACE FUNCTION get_position_performance(
    position_uuid UUID,
    start_time TIMESTAMP WITH TIME ZONE,
    end_time TIMESTAMP WITH TIME ZONE
)
RETURNS TABLE (
    apy NUMERIC,
    total_fees NUMERIC,
    impermanent_loss NUMERIC,
    time_in_range NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    WITH snapshots AS (
        SELECT *
        FROM position_snapshots
        WHERE position_id = position_uuid
        AND snapshot_at BETWEEN start_time AND end_time
        ORDER BY snapshot_at
    ),
    performance_calc AS (
        SELECT
            EXTRACT(EPOCH FROM (MAX(snapshot_at) - MIN(snapshot_at))) / 31536000 as years,
            MAX(fees_earned) - MIN(fees_earned) as fee_diff,
            AVG(CASE WHEN in_range THEN 1 ELSE 0 END) as in_range_pct
        FROM snapshots
    )
    SELECT
        CASE WHEN pc.years > 0 
             THEN (pc.fee_diff / pc.years) 
             ELSE 0 
        END as apy,
        pc.fee_diff as total_fees,
        0::NUMERIC as impermanent_loss, -- Calculate based on your logic
        pc.in_range_pct as time_in_range
    FROM performance_calc pc;
END;
$$ LANGUAGE plpgsql;

-- Function for real-time position monitoring
CREATE OR REPLACE FUNCTION check_positions_out_of_range()
RETURNS TABLE (
    position_id UUID,
    vault_address VARCHAR(42),
    current_tick INTEGER,
    tick_lower INTEGER,
    tick_upper INTEGER,
    out_of_range_duration INTERVAL
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        ps.position_id,
        ps.vault_address,
        ps.tick_current,
        ps.tick_lower,
        ps.tick_upper,
        NOW() - ps.snapshot_at as out_of_range_duration
    FROM position_snapshots ps
    WHERE ps.snapshot_at = (
        SELECT MAX(snapshot_at)
        FROM position_snapshots ps2
        WHERE ps2.position_id = ps.position_id
    )
    AND NOT ps.in_range;
END;
$$ LANGUAGE plpgsql;
```

## Option 2: Supabase PostgreSQL 15 + TimescaleDB (Temporary)

If you need TimescaleDB features immediately and can accept being on PostgreSQL 15:

```sql
-- Enable TimescaleDB (only works on Postgres 15 in Supabase)
CREATE EXTENSION IF NOT EXISTS timescaledb;

-- Create hypertable
CREATE TABLE blockchain_events (
    id UUID DEFAULT gen_random_uuid(),
    block_number BIGINT NOT NULL,
    transaction_hash VARCHAR(66) NOT NULL,
    event_data JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

SELECT create_hypertable('blockchain_events', 'created_at');

-- Continuous aggregates
CREATE MATERIALIZED VIEW hourly_metrics
WITH (timescaledb.continuous) AS
SELECT
    time_bucket('1 hour', created_at) as hour,
    COUNT(*) as event_count,
    COUNT(DISTINCT contract_address) as unique_contracts
FROM blockchain_events
GROUP BY hour;
```

**Migration Plan**: Start with PostgreSQL 15 + TimescaleDB, then migrate to PostgreSQL 17 + native partitioning.

## Option 3: Hybrid Supabase + External Redis

Use Supabase for persistent data + external Redis for high-frequency time-series:

```typescript
// Architecture split
interface DatabaseStrategy {
  supabase: {
    // Persistent business data
    vaults: Vault[];
    users: User[];
    transactions: Transaction[];
    daily_snapshots: DailySnapshot[];
  };
  
  redis: {
    // High-frequency data (external service)
    price_feeds: PriceFeed[];
    position_status: PositionStatus[];
    rebalance_queue: RebalanceRequest[];
  };
}
```

## Updated Docker Compose for Supabase Integration

```yaml
# docker-compose.yml - Updated for Supabase
version: '3.9'

services:
  # Go Services (connect to Supabase)
  monitor:
    build: ./services/monitor
    environment:
      - SUPABASE_URL=${SUPABASE_URL}
      - SUPABASE_SERVICE_KEY=${SUPABASE_SERVICE_KEY}
      - REDIS_URL=redis://redis:6379
    depends_on:
      - redis

  # External Redis for high-frequency data
  redis:
    image: redis/redis-stack:latest
    command: >
      redis-server 
      --loadmodule /opt/redis-stack/lib/redistimeseries.so
      --appendonly yes
    volumes:
      - redis_data:/data
    ports:
      - "6379:6379"
      - "8001:8001"

  # Note: No local postgres needed - using Supabase

volumes:
  redis_data:
```

## Go Code for Supabase Integration

```go
// pkg/database/supabase.go
package database

import (
    "github.com/supabase-community/postgrest-go"
    "github.com/supabase-community/supabase-go"
)

type SupabaseClient struct {
    client *supabase.Client
}

func NewSupabaseClient(url, key string) *SupabaseClient {
    client := supabase.CreateClient(url, key)
    return &SupabaseClient{client: client}
}

func (s *SupabaseClient) InsertEvent(event *BlockchainEvent) error {
    _, _, err := s.client.From("blockchain_events").Insert(event, false, "", "", "").Execute()
    return err
}

func (s *SupabaseClient) GetPositionsOutOfRange() ([]Position, error) {
    var positions []Position
    _, err := s.client.From("position_snapshots").
        Select("*", "", false).
        Eq("in_range", "false").
        Execute(&positions)
    return positions, err
}

// Real-time subscriptions
func (s *SupabaseClient) SubscribeToPositionUpdates(callback func(Position)) {
    s.client.Realtime.Channel("position_snapshots").
        On("INSERT", "*", callback).
        Subscribe()
}
```

## Final Recommendation for Supabase

### **Use Supabase PostgreSQL 17 + External Redis**

1. **Supabase Advantages**:
   - Managed PostgreSQL 17 with latest features
   - Built-in auth, RLS, and real-time subscriptions
   - Edge functions for serverless compute
   - Automatic backups and scaling

2. **PostgreSQL 17 Native Features**:
   - Advanced partitioning for blockchain events
   - Improved JSON performance for event data
   - Better query optimization
   - No vendor lock-in with TimescaleDB

3. **External Redis for**:
   - Sub-second price monitoring
   - Real-time position status
   - Rebalancing queue management
   - High-frequency analytics

This approach gives you:
- ✅ No TimescaleDB deprecation concerns
- ✅ Latest PostgreSQL 17 features
- ✅ Supabase's managed benefits
- ✅ High-performance time-series with Redis
- ✅ Future-proof architecture

Would you like me to update the project structure to reflect this Supabase + Redis architecture?