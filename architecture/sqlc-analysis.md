# sqlc Analysis for HyperEVM Yield Optimizer

## What is sqlc?

`sqlc` is a **code generator** that creates type-safe Go code from SQL queries. Instead of an ORM, it takes your actual SQL and generates perfectly typed Go interfaces.

### Core Philosophy
- **SQL-first**: Write actual SQL, get type-safe Go code
- **No runtime magic**: Everything is generated at compile time
- **Zero dependencies**: No ORM runtime overhead
- **Full SQL power**: Complete access to PostgreSQL 17 features

## 🚀 **Why sqlc is PERFECT for PostgreSQL 17 Partitioning**

### **Complete PostgreSQL 17 Support**
Since you write raw SQL, you get 100% access to PostgreSQL 17's partitioning features:

```sql
-- schema.sql - Your actual SQL
CREATE TABLE blockchain_events (
    id UUID DEFAULT gen_random_uuid(),
    block_number BIGINT NOT NULL,
    transaction_hash VARCHAR(66) NOT NULL,
    event_data JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
) PARTITION BY RANGE (created_at);

-- Setup automatic partitioning
SELECT pg_partman.create_parent(
    p_parent_table => 'public.blockchain_events',
    p_control => 'created_at',
    p_type => 'range',
    p_interval => 'daily',
    p_premake => 7
);

-- Indexes for partitioned tables
CREATE INDEX CONCURRENTLY idx_events_vault_type 
ON blockchain_events (created_at, (event_data->>'vault'), (event_data->>'type'));
```

### **Generated Type-Safe Code**

```sql
-- queries.sql - Your queries
-- name: InsertBlockchainEvent :one
INSERT INTO blockchain_events (block_number, transaction_hash, event_data)
VALUES ($1, $2, $3)
RETURNING id, created_at;

-- name: GetRecentVaultEvents :many
SELECT id, block_number, transaction_hash, event_data, created_at
FROM blockchain_events 
WHERE event_data->>'vault' = $1
AND created_at >= NOW() - INTERVAL '24 hours'
ORDER BY created_at DESC;

-- name: GetPositionsOutOfRange :many
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

-- name: BulkInsertEvents :copyfrom
INSERT INTO blockchain_events (block_number, transaction_hash, event_data)
VALUES ($1, $2, $3);
```

sqlc generates:

```go
// Generated code (queries.sql.go)
package database

import (
    "context"
    "time"
    "encoding/json"
)

type BlockchainEvent struct {
    ID              string          `json:"id"`
    BlockNumber     int64           `json:"block_number"`
    TransactionHash string          `json:"transaction_hash"`
    EventData       json.RawMessage `json:"event_data"`
    CreatedAt       time.Time       `json:"created_at"`
}

type Queries struct {
    db DBTX
}

func (q *Queries) InsertBlockchainEvent(ctx context.Context, arg InsertBlockchainEventParams) (BlockchainEvent, error) {
    // Generated implementation with full type safety
}

func (q *Queries) GetRecentVaultEvents(ctx context.Context, vaultAddress string) ([]BlockchainEvent, error) {
    // Generated implementation
}

func (q *Queries) GetPositionsOutOfRange(ctx context.Context) ([]GetPositionsOutOfRangeRow, error) {
    // Generated implementation with custom return type
}

// Bulk insert with COPY FROM for maximum performance
func (q *Queries) BulkInsertEvents(ctx context.Context, arg []BulkInsertEventsParams) (int64, error) {
    // Generated COPY FROM implementation
}
```

## 📊 **Performance Comparison**

| Approach | Query Performance | Type Safety | PostgreSQL 17 Features | Development Speed |
|----------|------------------|-------------|------------------------|-------------------|
| **sqlc** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ |
| Raw pgx | ⭐⭐⭐⭐⭐ | ⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐ |
| Bun ORM | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| GORM | ⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐ | ⭐⭐⭐⭐⭐ |

### **Why sqlc Wins for DeFi/Blockchain**

1. **Zero Runtime Overhead**: No ORM reflection or query building
2. **Full SQL Power**: Complete access to PostgreSQL 17 partitioning
3. **Type Safety**: Compile-time verification of queries and types
4. **Performance**: Direct SQL execution, no abstraction layer
5. **COPY FROM Support**: Built-in bulk insert optimization

## 🛠 **Implementation for Yield Optimizer**

### **Project Setup**

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
```

### **Schema Definition**

```sql
-- sql/schema/001_initial.sql
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_partman";

-- Partitioned events table
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
    tick_current INTEGER,
    tick_lower INTEGER,
    tick_upper INTEGER,
    liquidity NUMERIC(78, 0),
    in_range BOOLEAN,
    fees_earned NUMERIC(78, 18),
    snapshot_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
) PARTITION BY RANGE (snapshot_at);

SELECT pg_partman.create_parent(
    p_parent_table => 'public.position_snapshots',
    p_control => 'snapshot_at',
    p_type => 'range',
    p_interval => 'daily',
    p_premake => 7
);

-- Performance-optimized indexes
CREATE INDEX CONCURRENTLY idx_events_contract_time 
ON blockchain_events (contract_address, created_at);

CREATE INDEX CONCURRENTLY idx_events_vault_type 
ON blockchain_events ((event_data->>'vault'), (event_data->>'type'), created_at);

CREATE INDEX CONCURRENTLY idx_snapshots_position_time
ON position_snapshots (position_id, snapshot_at);
```

### **Query Definitions**

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
SELECT id, block_number, transaction_hash, event_name, event_data, created_at
FROM blockchain_events 
WHERE event_data->>'vault' = $1
AND created_at >= $2
AND created_at <= $3
ORDER BY created_at DESC;

-- name: GetSwapEventsForAnalysis :many
SELECT 
    event_data->>'vault' as vault_address,
    CAST(event_data->>'amount0' AS NUMERIC) as amount0,
    CAST(event_data->>'amount1' AS NUMERIC) as amount1,
    created_at
FROM blockchain_events 
WHERE event_name = 'Swap'
AND created_at >= NOW() - INTERVAL '24 hours'
ORDER BY created_at;

-- name: GetRealtimePositionStatus :many
SELECT 
    ps.position_id,
    ps.vault_address,
    ps.tick_current,
    ps.tick_lower,
    ps.tick_upper,
    ps.in_range,
    ps.liquidity,
    ps.fees_earned,
    EXTRACT(EPOCH FROM (NOW() - ps.snapshot_at)) as seconds_ago
FROM position_snapshots ps
WHERE ps.snapshot_at = (
    SELECT MAX(snapshot_at)
    FROM position_snapshots ps2
    WHERE ps2.position_id = ps.position_id
)
AND ps.vault_address = ANY($1::VARCHAR[]);

-- name: InsertPositionSnapshot :one
INSERT INTO position_snapshots (
    position_id,
    vault_address,
    tick_current,
    tick_lower,
    tick_upper,
    liquidity,
    in_range,
    fees_earned
) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
RETURNING id, snapshot_at;
```

### **Go Service Implementation**

```go
// internal/services/monitor.go
package services

import (
    "context"
    "time"
    
    "github.com/jackc/pgx/v5/pgxpool"
    "your-project/internal/database"
)

type MonitorService struct {
    db      *database.Queries
    pool    *pgxpool.Pool
}

func NewMonitorService(pool *pgxpool.Pool) *MonitorService {
    return &MonitorService{
        db:   database.New(pool),
        pool: pool,
    }
}

// High-performance bulk event insertion
func (s *MonitorService) ProcessBlockEvents(ctx context.Context, events []BlockEvent) error {
    // Convert to sqlc parameters
    params := make([]database.BulkInsertEventsParams, len(events))
    for i, event := range events {
        params[i] = database.BulkInsertEventsParams{
            BlockNumber:     event.BlockNumber,
            TransactionHash: event.TxHash,
            LogIndex:        int32(event.LogIndex),
            ContractAddress: event.Contract,
            EventName:       event.Name,
            EventData:       event.Data,
        }
    }
    
    // Use COPY FROM for maximum performance
    _, err := s.db.BulkInsertEvents(ctx, params)
    return err
}

// Type-safe vault event retrieval
func (s *MonitorService) GetVaultActivity(ctx context.Context, vaultAddr string, since time.Time) ([]database.BlockchainEvent, error) {
    return s.db.GetVaultEvents(ctx, database.GetVaultEventsParams{
        EventData: vaultAddr,
        CreatedAt: since,
        CreatedAt_2: time.Now(),
    })
}

// Real-time position monitoring
func (s *MonitorService) CheckPositionsOutOfRange(ctx context.Context, vaultAddresses []string) ([]database.GetRealtimePositionStatusRow, error) {
    return s.db.GetRealtimePositionStatus(ctx, vaultAddresses)
}
```

### **Migration and Deployment**

```go
// cmd/migrate/main.go
package main

import (
    "context"
    "fmt"
    "io/fs"
    "path/filepath"
    
    "github.com/jackc/pgx/v5/pgxpool"
    "github.com/golang-migrate/migrate/v4"
    "github.com/golang-migrate/migrate/v4/database/postgres"
    "github.com/golang-migrate/migrate/v4/source/iofs"
)

//go:embed sql/schema/*.sql
var migrationFiles embed.FS

func main() {
    pool, err := pgxpool.New(context.Background(), os.Getenv("DATABASE_URL"))
    if err != nil {
        log.Fatal(err)
    }
    defer pool.Close()
    
    // Run migrations
    source, err := iofs.New(migrationFiles, "sql/schema")
    if err != nil {
        log.Fatal(err)
    }
    
    driver, err := postgres.WithInstance(pool.Config().ConnConfig.Database, &postgres.Config{})
    if err != nil {
        log.Fatal(err)
    }
    
    m, err := migrate.NewWithInstance("iofs", source, "postgres", driver)
    if err != nil {
        log.Fatal(err)
    }
    
    if err := m.Up(); err != nil && err != migrate.ErrNoChange {
        log.Fatal(err)
    }
    
    fmt.Println("Database migrated successfully")
}
```

## 🏆 **Why sqlc is the BEST Choice for Your Yield Optimizer**

### **Advantages for DeFi/Blockchain:**

1. **Performance**: Raw SQL performance with type safety
2. **PostgreSQL 17 Full Support**: Complete access to partitioning, JSONB, etc.
3. **Blockchain-Optimized**: Perfect for event-driven architecture
4. **Zero Runtime Dependencies**: No ORM overhead
5. **Compile-Time Safety**: Catch SQL errors at build time
6. **COPY FROM Support**: Bulk inserts for high-throughput event processing

### **Perfect for Time-Series Data:**
- ✅ Native partitioning support
- ✅ Optimized range queries
- ✅ JSONB event data handling
- ✅ Bulk insert performance
- ✅ Complex analytical queries

### **Development Experience:**
- ✅ Write SQL, get type-safe Go
- ✅ IDE autocompletion for generated code
- ✅ Compile-time query validation
- ✅ Easy to understand generated code
- ✅ No magic, no surprises

## 🎯 **Final Recommendation: Use sqlc**

For your HyperEVM yield optimizer, `sqlc` is the **perfect choice** because:

1. **PostgreSQL 17 Native**: Full access to latest partitioning features
2. **DeFi Performance**: Handles high-frequency blockchain event processing
3. **Type Safety**: Compile-time verification prevents runtime errors
4. **Simplicity**: Write SQL, get Go - no ORM complexity
5. **Future-Proof**: Always supports latest PostgreSQL features

sqlc gives you the best of both worlds: **the performance of raw SQL with the safety of strongly typed Go code**.