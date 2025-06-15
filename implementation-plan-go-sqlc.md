# HyperEVM Yield Optimizer Implementation Plan (Go + sqlc)

## Project Overview

Building a concentrated liquidity yield optimizer on HyperEVM using:
- **Go**: Core services (monitoring, rebalancing, event processing)
- **sqlc**: Type-safe SQL with full PostgreSQL 17 partitioning support
- **Bun**: API services (GraphQL, WebSocket, admin dashboard)
- **Solidity**: Smart contracts for vault and strategy management

## Phase 1: Project Setup with sqlc

### Step 1: Initialize Project Structure

```bash
# Create project root
mkdir hyperevm-yield-optimizer
cd hyperevm-yield-optimizer

# Initialize git
git init
echo "# HyperEVM Yield Optimizer" > README.md

# Create project structure
mkdir -p {services,packages,contracts,scripts,docs}
mkdir -p services/{monitor,rebalancer,gateway,api,websocket,admin}
mkdir -p packages/{shared-types,config,utils}
mkdir -p contracts/{src,test,scripts}
mkdir -p sql/{schema,queries}
```

### Step 2: Install sqlc

```bash
# Install sqlc
go install github.com/sqlc-dev/sqlc/cmd/sqlc@latest

# Verify installation
sqlc version
```

### Step 3: Configure sqlc

```yaml
# sqlc.yaml
version: "2"
sql:
  - engine: "postgresql"
    queries: "sql/queries/"
    schema: "sql/schema/"
    gen:
      go:
        package: "database"
        out: "internal/database"
        sql_package: "pgx/v5"
        emit_json_tags: true
        emit_prepared_queries: false
        emit_interface: true
        emit_exact_table_names: true
        emit_empty_slices: true
        overrides:
          - db_type: "jsonb"
            go_type: "encoding/json.RawMessage"
          - db_type: "uuid"
            go_type: "github.com/google/uuid.UUID"
          - db_type: "numeric"
            go_type: "github.com/shopspring/decimal.Decimal"
```

### Step 4: Database Schema with PostgreSQL 17 Partitioning

```sql
-- sql/schema/001_extensions.sql
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_partman";

-- sql/schema/002_tables.sql
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

-- Setup automatic partitioning
SELECT pg_partman.create_parent(
    p_parent_table => 'public.blockchain_events',
    p_control => 'created_at',
    p_type => 'range',
    p_interval => 'daily',
    p_premake => 7,
    p_start_partition => CURRENT_DATE::TEXT
);

-- Position snapshots with partitioning
CREATE TABLE position_snapshots (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    position_id UUID NOT NULL,
    vault_address VARCHAR(42) NOT NULL,
    token_id NUMERIC(78, 0) NOT NULL,
    tick_current INTEGER NOT NULL,
    tick_lower INTEGER NOT NULL,
    tick_upper INTEGER NOT NULL,
    liquidity NUMERIC(78, 0) NOT NULL,
    in_range BOOLEAN NOT NULL,
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

-- Performance metrics with partitioning
CREATE TABLE performance_metrics (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    vault_id UUID NOT NULL,
    metric_type VARCHAR(50) NOT NULL,
    value NUMERIC(20, 8) NOT NULL,
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

-- Vaults (not partitioned)
CREATE TABLE vaults (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    address VARCHAR(42) UNIQUE NOT NULL,
    strategy_type VARCHAR(50) NOT NULL,
    token0_address VARCHAR(42) NOT NULL,
    token1_address VARCHAR(42) NOT NULL,
    performance_fee INTEGER NOT NULL DEFAULT 1000, -- basis points
    management_fee INTEGER NOT NULL DEFAULT 100,
    total_value_locked NUMERIC(78, 18) DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
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
    gas_used BIGINT NOT NULL,
    gas_price NUMERIC(78, 18) NOT NULL,
    slippage NUMERIC(10, 6),
    reason VARCHAR(200),
    transaction_hash VARCHAR(66),
    executed_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Indexes for performance
CREATE INDEX CONCURRENTLY idx_events_block_contract 
ON blockchain_events (block_number, contract_address);

CREATE INDEX CONCURRENTLY idx_events_vault_type 
ON blockchain_events ((event_data->>'vault'), event_name, created_at);

CREATE INDEX CONCURRENTLY idx_snapshots_position_time 
ON position_snapshots (position_id, snapshot_at);

CREATE INDEX CONCURRENTLY idx_snapshots_vault_range 
ON position_snapshots (vault_address, in_range, snapshot_at);

-- sql/schema/003_functions.sql
-- Function to get latest position status
CREATE OR REPLACE FUNCTION get_latest_position_status(p_vault_address VARCHAR)
RETURNS TABLE (
    position_id UUID,
    vault_address VARCHAR,
    tick_current INTEGER,
    tick_lower INTEGER,
    tick_upper INTEGER,
    in_range BOOLEAN,
    liquidity NUMERIC,
    last_update TIMESTAMP WITH TIME ZONE
) AS $$
BEGIN
    RETURN QUERY
    SELECT DISTINCT ON (ps.position_id)
        ps.position_id,
        ps.vault_address,
        ps.tick_current,
        ps.tick_lower,
        ps.tick_upper,
        ps.in_range,
        ps.liquidity,
        ps.snapshot_at as last_update
    FROM position_snapshots ps
    WHERE ps.vault_address = p_vault_address
    ORDER BY ps.position_id, ps.snapshot_at DESC;
END;
$$ LANGUAGE plpgsql;
```

### Step 5: SQL Queries for sqlc

```sql
-- sql/queries/events.sql
-- name: InsertBlockchainEvent :one
INSERT INTO blockchain_events (
    block_number,
    transaction_hash,
    log_index,
    contract_address,
    event_name,
    event_data
) VALUES ($1, $2, $3, $4, $5, $6)
RETURNING id, created_at;

-- name: BulkInsertEvents :copyfrom
INSERT INTO blockchain_events (
    block_number,
    transaction_hash,
    log_index,
    contract_address,
    event_name,
    event_data
) VALUES ($1, $2, $3, $4, $5, $6);

-- name: GetVaultEvents :many
SELECT 
    id,
    block_number,
    transaction_hash,
    event_name,
    event_data,
    created_at
FROM blockchain_events
WHERE event_data->>'vault' = $1
AND created_at >= $2
AND created_at <= $3
ORDER BY created_at DESC
LIMIT $4;

-- name: GetSwapEvents :many
SELECT 
    block_number,
    event_data->>'vault' as vault_address,
    event_data->>'pool' as pool_address,
    CAST(event_data->>'amount0' AS NUMERIC) as amount0,
    CAST(event_data->>'amount1' AS NUMERIC) as amount1,
    CAST(event_data->>'tick' AS INTEGER) as tick,
    created_at
FROM blockchain_events
WHERE event_name = 'Swap'
AND created_at >= NOW() - INTERVAL '1 hour'
ORDER BY created_at DESC;

-- sql/queries/positions.sql
-- name: InsertPositionSnapshot :one
INSERT INTO position_snapshots (
    position_id,
    vault_address,
    token_id,
    tick_current,
    tick_lower,
    tick_upper,
    liquidity,
    in_range,
    fees_earned,
    value0,
    value1
) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
RETURNING id, snapshot_at;

-- name: GetLatestPositionSnapshots :many
SELECT DISTINCT ON (position_id)
    id,
    position_id,
    vault_address,
    token_id,
    tick_current,
    tick_lower,
    tick_upper,
    liquidity,
    in_range,
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
    tick_current,
    tick_lower,
    tick_upper,
    liquidity,
    EXTRACT(EPOCH FROM (NOW() - snapshot_at)) as seconds_out_of_range
FROM position_snapshots ps
WHERE ps.snapshot_at = (
    SELECT MAX(snapshot_at)
    FROM position_snapshots ps2
    WHERE ps2.position_id = ps.position_id
)
AND NOT ps.in_range
AND ps.liquidity > 0;

-- name: GetPositionHistory :many
SELECT 
    tick_current,
    tick_lower,
    tick_upper,
    in_range,
    fees_earned,
    snapshot_at
FROM position_snapshots
WHERE position_id = $1
AND snapshot_at >= $2
ORDER BY snapshot_at ASC;

-- sql/queries/vaults.sql
-- name: GetVault :one
SELECT 
    id,
    address,
    strategy_type,
    token0_address,
    token1_address,
    performance_fee,
    management_fee,
    total_value_locked,
    created_at,
    updated_at
FROM vaults
WHERE address = $1;

-- name: ListVaults :many
SELECT * FROM vaults
ORDER BY total_value_locked DESC;

-- name: UpdateVaultTVL :exec
UPDATE vaults
SET 
    total_value_locked = $2,
    updated_at = NOW()
WHERE id = $1;

-- sql/queries/rebalances.sql
-- name: InsertRebalanceHistory :one
INSERT INTO rebalance_history (
    vault_id,
    position_id,
    old_tick_lower,
    old_tick_upper,
    new_tick_lower,
    new_tick_upper,
    gas_used,
    gas_price,
    slippage,
    reason,
    transaction_hash
) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
RETURNING id, executed_at;

-- name: GetRebalanceHistory :many
SELECT * FROM rebalance_history
WHERE vault_id = $1
ORDER BY executed_at DESC
LIMIT $2;

-- sql/queries/metrics.sql
-- name: InsertPerformanceMetric :one
INSERT INTO performance_metrics (
    vault_id,
    metric_type,
    value,
    period_start,
    period_end
) VALUES ($1, $2, $3, $4, $5)
RETURNING id, recorded_at;

-- name: GetVaultPerformance :many
SELECT 
    metric_type,
    AVG(value) as avg_value,
    MIN(value) as min_value,
    MAX(value) as max_value,
    COUNT(*) as data_points
FROM performance_metrics
WHERE vault_id = $1
AND recorded_at >= $2
GROUP BY metric_type;
```

### Step 6: Generate sqlc Code

```bash
# Generate type-safe Go code from SQL
sqlc generate

# This creates internal/database/ with:
# - db.go (main interface)
# - models.go (struct definitions)
# - events.sql.go (event queries)
# - positions.sql.go (position queries)
# - vaults.sql.go (vault queries)
# - rebalances.sql.go (rebalance queries)
# - metrics.sql.go (metrics queries)
```

### Step 7: Go Services with sqlc

```go
// services/monitor/go.mod
module github.com/yourusername/hyperevm-yield-optimizer/services/monitor

go 1.21

require (
    github.com/ethereum/go-ethereum v1.13.5
    github.com/jackc/pgx/v5 v5.5.1
    github.com/redis/go-redis/v9 v9.3.0
    github.com/google/uuid v1.5.0
    github.com/shopspring/decimal v1.3.1
    github.com/sirupsen/logrus v1.9.3
)
```

```go
// services/monitor/internal/service/monitor.go
package service

import (
    "context"
    "encoding/json"
    "time"
    
    "github.com/ethereum/go-ethereum/ethclient"
    "github.com/jackc/pgx/v5/pgxpool"
    "github.com/redis/go-redis/v9"
    "github.com/shopspring/decimal"
    "github.com/sirupsen/logrus"
    
    "github.com/yourusername/hyperevm-yield-optimizer/internal/database"
)

type MonitorService struct {
    ethClient   *ethclient.Client
    db          *database.Queries
    pgPool      *pgxpool.Pool
    redisClient *redis.Client
    logger      *logrus.Logger
}

func NewMonitorService(
    ethClient *ethclient.Client,
    pgPool *pgxpool.Pool,
    redisClient *redis.Client,
    logger *logrus.Logger,
) *MonitorService {
    return &MonitorService{
        ethClient:   ethClient,
        db:          database.New(pgPool),
        pgPool:      pgPool,
        redisClient: redisClient,
        logger:      logger,
    }
}

// ProcessBlockEvents uses sqlc's bulk insert for maximum performance
func (s *MonitorService) ProcessBlockEvents(ctx context.Context, events []BlockEvent) error {
    // Convert to sqlc parameters
    params := make([]database.BulkInsertEventsParams, len(events))
    for i, event := range events {
        eventData, err := json.Marshal(event.Data)
        if err != nil {
            return err
        }
        
        params[i] = database.BulkInsertEventsParams{
            BlockNumber:     event.BlockNumber,
            TransactionHash: event.TxHash,
            LogIndex:        int32(event.LogIndex),
            ContractAddress: event.Contract,
            EventName:       event.Name,
            EventData:       eventData,
        }
    }
    
    // Use COPY FROM for maximum performance
    count, err := s.db.BulkInsertEvents(ctx, params)
    if err != nil {
        return err
    }
    
    s.logger.WithField("count", count).Info("Bulk inserted events")
    return nil
}

// CheckPositionsOutOfRange uses sqlc's optimized queries
func (s *MonitorService) CheckPositionsOutOfRange(ctx context.Context) error {
    positions, err := s.db.GetPositionsOutOfRange(ctx)
    if err != nil {
        return err
    }
    
    for _, pos := range positions {
        // Check if rebalance is needed
        if pos.SecondsOutOfRange.Float64 > 300 { // 5 minutes
            s.logger.WithFields(logrus.Fields{
                "position_id": pos.PositionID,
                "vault":       pos.VaultAddress,
                "tick_current": pos.TickCurrent,
                "tick_range":  fmt.Sprintf("[%d, %d]", pos.TickLower, pos.TickUpper),
            }).Warn("Position out of range for extended period")
            
            // Queue for rebalancing
            if err := s.queueRebalance(ctx, pos); err != nil {
                s.logger.WithError(err).Error("Failed to queue rebalance")
            }
        }
    }
    
    return nil
}

// SavePositionSnapshot stores position state using sqlc
func (s *MonitorService) SavePositionSnapshot(ctx context.Context, position *Position) error {
    _, err := s.db.InsertPositionSnapshot(ctx, database.InsertPositionSnapshotParams{
        PositionID:   position.ID,
        VaultAddress: position.VaultAddress,
        TokenID:      decimal.NewFromBigInt(position.TokenID, 0),
        TickCurrent:  position.TickCurrent,
        TickLower:    position.TickLower,
        TickUpper:    position.TickUpper,
        Liquidity:    decimal.NewFromBigInt(position.Liquidity, 0),
        InRange:      position.InRange,
        FeesEarned:   decimal.NewFromBigInt(position.FeesEarned, 0),
        Value0:       decimal.NewFromBigInt(position.Value0, 0),
        Value1:       decimal.NewFromBigInt(position.Value1, 0),
    })
    
    return err
}
```

### Step 8: API Service with Bun and sqlc

```typescript
// services/api/src/index.ts
import { Elysia } from "elysia";
import { cors } from "@elysiajs/cors";
import { Pool } from "pg";
import { createGraphQLHandler } from "./graphql";
import { Database } from "./database"; // sqlc generated client wrapper

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
});

const db = new Database(pool);

const app = new Elysia()
  .use(cors())
  .get("/", () => ({ message: "HyperEVM Yield Optimizer API" }))
  .post("/graphql", async ({ body }) => {
    const handler = createGraphQLHandler(db);
    return handler(body);
  })
  .get("/vaults", async () => {
    const vaults = await db.listVaults();
    return { vaults };
  })
  .get("/vault/:address", async ({ params }) => {
    const vault = await db.getVault(params.address);
    if (!vault) {
      throw new Error("Vault not found");
    }
    return vault;
  })
  .get("/positions/:vaultAddress", async ({ params }) => {
    const positions = await db.getLatestPositionSnapshots([params.vaultAddress]);
    return { positions };
  })
  .listen(3000);

console.log(`🚀 API running at ${app.server?.hostname}:${app.server?.port}`);
```

## Phase 2: Smart Contracts

```solidity
// contracts/src/YieldOptimizerVault.sol
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

interface IPositionManager {
    struct Position {
        uint96 nonce;
        address operator;
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
        uint256 feeGrowthInside0LastX128;
        uint256 feeGrowthInside1LastX128;
        uint128 tokensOwed0;
        uint128 tokensOwed1;
    }
    
    function positions(uint256 tokenId) external view returns (Position memory);
    function mint(address recipient, int24 tickLower, int24 tickUpper, uint128 amount) external returns (uint256);
    function burn(uint256 tokenId) external returns (uint256 amount0, uint256 amount1);
}

contract YieldOptimizerVault is ERC20, ReentrancyGuard, AccessControl, Pausable {
    bytes32 public constant KEEPER_ROLE = keccak256("KEEPER_ROLE");
    bytes32 public constant STRATEGIST_ROLE = keccak256("STRATEGIST_ROLE");
    
    IPositionManager public immutable positionManager;
    address public immutable token0;
    address public immutable token1;
    uint24 public immutable poolFee;
    
    uint256 public currentPositionId;
    uint256 public performanceFee = 1000; // 10%
    uint256 public lastRebalanceTime;
    
    event Deposit(address indexed user, uint256 shares, uint256 amount0, uint256 amount1);
    event Withdraw(address indexed user, uint256 shares, uint256 amount0, uint256 amount1);
    event Rebalance(
        uint256 oldPositionId,
        uint256 newPositionId,
        int24 newTickLower,
        int24 newTickUpper
    );
    
    constructor(
        address _positionManager,
        address _token0,
        address _token1,
        uint24 _poolFee,
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) {
        positionManager = IPositionManager(_positionManager);
        token0 = _token0;
        token1 = _token1;
        poolFee = _poolFee;
        
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(KEEPER_ROLE, msg.sender);
        _setupRole(STRATEGIST_ROLE, msg.sender);
    }
    
    function deposit(
        uint256 amount0Desired,
        uint256 amount1Desired
    ) external nonReentrant whenNotPaused returns (uint256 shares) {
        // Implementation
    }
    
    function withdraw(
        uint256 shares
    ) external nonReentrant returns (uint256 amount0, uint256 amount1) {
        // Implementation
    }
    
    function rebalance(
        int24 newTickLower,
        int24 newTickUpper
    ) external onlyRole(KEEPER_ROLE) {
        require(block.timestamp >= lastRebalanceTime + 1 hours, "Too soon");
        
        // Burn old position
        uint256 oldPositionId = currentPositionId;
        (uint256 amount0, uint256 amount1) = positionManager.burn(oldPositionId);
        
        // Mint new position
        uint128 liquidity = calculateOptimalLiquidity(amount0, amount1, newTickLower, newTickUpper);
        uint256 newPositionId = positionManager.mint(
            address(this),
            newTickLower,
            newTickUpper,
            liquidity
        );
        
        currentPositionId = newPositionId;
        lastRebalanceTime = block.timestamp;
        
        emit Rebalance(oldPositionId, newPositionId, newTickLower, newTickUpper);
    }
}
```

## Phase 3: Development Workflow

### Local Development

```bash
# Start infrastructure
docker-compose up -d postgres redis

# Generate sqlc code
sqlc generate

# Run migrations
migrate -path sql/schema -database $DATABASE_URL up

# Start Go monitor service
cd services/monitor
go run .

# Start Bun API in another terminal
cd services/api
bun run dev

# Deploy contracts
cd contracts
npx hardhat run scripts/deploy.js --network hyperevm
```

### Testing with sqlc

```go
// services/monitor/internal/service/monitor_test.go
package service

import (
    "context"
    "testing"
    
    "github.com/jackc/pgx/v5/pgxpool"
    "github.com/stretchr/testify/assert"
    "github.com/stretchr/testify/require"
    
    "github.com/yourusername/hyperevm-yield-optimizer/internal/database"
)

func TestBulkInsertEvents(t *testing.T) {
    // Setup test database
    ctx := context.Background()
    pool, err := pgxpool.New(ctx, "postgres://test:test@localhost:5432/test_db")
    require.NoError(t, err)
    defer pool.Close()
    
    db := database.New(pool)
    service := &MonitorService{db: db}
    
    // Test bulk insert
    events := []BlockEvent{
        {BlockNumber: 1000, TxHash: "0x123", Name: "Swap"},
        {BlockNumber: 1001, TxHash: "0x124", Name: "Mint"},
    }
    
    err = service.ProcessBlockEvents(ctx, events)
    assert.NoError(t, err)
    
    // Verify events were inserted
    vaultEvents, err := db.GetVaultEvents(ctx, database.GetVaultEventsParams{
        EventData: "0xvault",
        CreatedAt: time.Now().Add(-1 * time.Hour),
        CreatedAt_2: time.Now(),
        Limit: 10,
    })
    assert.NoError(t, err)
    assert.Len(t, vaultEvents, 2)
}
```

## Benefits of sqlc over Bun

1. **Zero Runtime Overhead**: No ORM reflection, direct SQL execution
2. **Full PostgreSQL 17 Support**: Complete access to partitioning features
3. **Type Safety**: Compile-time verification of SQL queries
4. **Performance**: COPY FROM support for bulk operations
5. **Transparency**: You see exactly what SQL is being executed
6. **No Magic**: No hidden queries or N+1 problems

## Next Steps

1. Implement price monitoring with Redis TimeSeries
2. Build rebalancing strategies
3. Create WebSocket service for real-time updates
4. Deploy smart contracts
5. Build frontend dashboard