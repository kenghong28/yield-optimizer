# Go ORM PostgreSQL 17 Partitioning Support Analysis

## Current State of Go ORMs (2024)

Based on research, here's the reality of PostgreSQL 17 native partitioning support in Go ORMs:

### 📊 **ORM Support Matrix**

| ORM | Native Partitioning | Raw SQL Support | Community | Recommendation |
|-----|-------------------|-----------------|-----------|----------------|
| **Bun** | ❌ Limited | ✅ Excellent | Growing | **Best Hybrid** |
| **GORM** | ❌ None | ✅ Good | Largest | Popular but limited |
| **Ent** | ❌ None | ✅ Good | Facebook-backed | Code-first approach |
| **go-pg** | ✅ Basic | ✅ Excellent | Declining | **Best for partitioning** |
| **Raw SQL** | ✅ Full | ✅ Full | N/A | **Most control** |

## Detailed Analysis

### 1. **Bun ORM** (Recommended for Hybrid Approach)

```go
// Bun with custom partitioning
package main

import (
    "database/sql"
    "github.com/uptrace/bun"
    "github.com/uptrace/bun/dialect/pgdialect"
    "github.com/uptrace/bun/driver/pgdriver"
)

type BlockchainEvent struct {
    bun.BaseModel `bun:"table:blockchain_events"`
    
    ID              string    `bun:"id,pk,type:uuid,default:gen_random_uuid()"`
    BlockNumber     int64     `bun:"block_number,notnull"`
    TransactionHash string    `bun:"transaction_hash,notnull"`
    EventData       map[string]interface{} `bun:"event_data,type:jsonb"`
    CreatedAt       time.Time `bun:"created_at,notnull,default:current_timestamp"`
}

// Custom partitioning setup
func SetupPartitioning(db *bun.DB) error {
    // Create partitioned table with raw SQL
    _, err := db.Exec(`
        CREATE TABLE IF NOT EXISTS blockchain_events (
            id UUID DEFAULT gen_random_uuid(),
            block_number BIGINT NOT NULL,
            transaction_hash VARCHAR(66) NOT NULL,
            event_data JSONB,
            created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
        ) PARTITION BY RANGE (created_at)
    `)
    if err != nil {
        return err
    }
    
    // Setup automatic partitioning
    _, err = db.Exec(`
        SELECT pg_partman.create_parent(
            p_parent_table => 'public.blockchain_events',
            p_control => 'created_at',
            p_type => 'range',
            p_interval => 'daily',
            p_premake => 7
        )
    `)
    return err
}

// Use Bun for normal operations
func (s *Service) InsertEvent(ctx context.Context, event *BlockchainEvent) error {
    // Bun handles this normally, partitioning is transparent
    _, err := s.db.NewInsert().Model(event).Exec(ctx)
    return err
}

func (s *Service) GetRecentEvents(ctx context.Context, vaultAddress string) ([]BlockchainEvent, error) {
    var events []BlockchainEvent
    err := s.db.NewSelect().
        Model(&events).
        Where("event_data->>'vault' = ?", vaultAddress).
        Where("created_at >= ?", time.Now().Add(-24*time.Hour)).
        Order("created_at DESC").
        Scan(ctx)
    return events, err
}
```

**Pros:**
- ✅ Modern, actively maintained
- ✅ Excellent raw SQL support  
- ✅ Type-safe queries
- ✅ Good performance
- ✅ Supports migrations

**Cons:**
- ❌ No declarative partitioning
- ❌ Smaller community than GORM

### 2. **GORM** (Most Popular but Limited)

```go
// GORM with manual partitioning
package main

import (
    "gorm.io/gorm"
    "gorm.io/driver/postgres"
)

type BlockchainEvent struct {
    ID              string                 `gorm:"type:uuid;primaryKey;default:gen_random_uuid()"`
    BlockNumber     int64                  `gorm:"column:block_number;not null"`
    TransactionHash string                 `gorm:"column:transaction_hash;not null"`
    EventData       map[string]interface{} `gorm:"type:jsonb"`
    CreatedAt       time.Time              `gorm:"autoCreateTime"`
}

// TableName for GORM
func (BlockchainEvent) TableName() string {
    return "blockchain_events"
}

// Custom partitioning setup
func SetupGORMPartitioning(db *gorm.DB) error {
    // Must use raw SQL for partitioning
    return db.Exec(`
        CREATE TABLE IF NOT EXISTS blockchain_events (
            id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
            block_number BIGINT NOT NULL,
            transaction_hash VARCHAR(66) NOT NULL,
            event_data JSONB,
            created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
        ) PARTITION BY RANGE (created_at)
    `).Error
}

// GORM operations work normally
func (s *Service) CreateEvent(event *BlockchainEvent) error {
    return s.db.Create(event).Error
}

func (s *Service) FindRecentEvents(vaultAddress string) ([]BlockchainEvent, error) {
    var events []BlockchainEvent
    err := s.db.Where("event_data->>'vault' = ?", vaultAddress).
        Where("created_at >= ?", time.Now().Add(-24*time.Hour)).
        Find(&events).Error
    return events, err
}
```

**Pros:**
- ✅ Largest community
- ✅ Most documentation
- ✅ Familiar to many developers
- ✅ Rich ecosystem

**Cons:**
- ❌ No partitioning support
- ❌ Heavy/bloated
- ❌ Performance concerns

### 3. **go-pg** (Best Partitioning Support)

```go
// go-pg with native partitioning support
package main

import (
    "github.com/go-pg/pg/v10"
    "github.com/go-pg/pg/v10/orm"
)

type BlockchainEvent struct {
    tableName struct{} `pg:"blockchain_events,partition_by:RANGE (created_at)"`
    
    ID              string                 `pg:"id,pk,type:uuid,default:gen_random_uuid()"`
    BlockNumber     int64                  `pg:"block_number,notnull"`
    TransactionHash string                 `pg:"transaction_hash,notnull"`
    EventData       map[string]interface{} `pg:"event_data,type:jsonb"`
    CreatedAt       time.Time              `pg:"created_at,notnull,default:current_timestamp"`
}

// go-pg handles partitioning automatically
func SetupGoPGPartitioning(db *pg.DB) error {
    // Create partitioned table
    err := db.Model((*BlockchainEvent)(nil)).CreateTable(&orm.CreateTableOptions{
        IfNotExists: true,
    })
    if err != nil {
        return err
    }
    
    // Setup automatic partition management
    _, err = db.Exec(`
        SELECT pg_partman.create_parent(
            p_parent_table => 'blockchain_events',
            p_control => 'created_at',
            p_type => 'range',
            p_interval => 'daily'
        )
    `)
    return err
}

func (s *Service) InsertEvent(event *BlockchainEvent) error {
    _, err := s.db.Model(event).Insert()
    return err
}
```

**Pros:**
- ✅ Native partitioning support via tags
- ✅ Excellent PostgreSQL integration
- ✅ Good performance

**Cons:**
- ❌ Less active development
- ❌ Smaller community
- ❌ May not get PostgreSQL 17 updates quickly

### 4. **Raw SQL with pgx** (Maximum Control)

```go
// Maximum control with pgx
package main

import (
    "context"
    "github.com/jackc/pgx/v5"
    "github.com/jackc/pgx/v5/pgxpool"
)

type EventService struct {
    pool *pgxpool.Pool
}

func NewEventService(databaseURL string) (*EventService, error) {
    pool, err := pgxpool.New(context.Background(), databaseURL)
    if err != nil {
        return nil, err
    }
    
    service := &EventService{pool: pool}
    if err := service.setupPartitioning(); err != nil {
        return nil, err
    }
    
    return service, nil
}

func (s *EventService) setupPartitioning() error {
    ctx := context.Background()
    
    // Create partitioned table
    _, err := s.pool.Exec(ctx, `
        CREATE TABLE IF NOT EXISTS blockchain_events (
            id UUID DEFAULT gen_random_uuid(),
            block_number BIGINT NOT NULL,
            transaction_hash VARCHAR(66) NOT NULL,
            event_data JSONB,
            created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
        ) PARTITION BY RANGE (created_at)
    `)
    if err != nil {
        return err
    }
    
    // Setup automatic partitioning with pg_partman
    _, err = s.pool.Exec(ctx, `
        SELECT pg_partman.create_parent(
            p_parent_table => 'public.blockchain_events',
            p_control => 'created_at',
            p_type => 'range',
            p_interval => 'daily',
            p_premake => 7,
            p_start_partition => CURRENT_DATE::TEXT
        )
    `)
    return err
}

func (s *EventService) InsertEvent(ctx context.Context, event BlockchainEvent) error {
    query := `
        INSERT INTO blockchain_events (block_number, transaction_hash, event_data)
        VALUES ($1, $2, $3)
        RETURNING id, created_at
    `
    return s.pool.QueryRow(ctx, query, event.BlockNumber, event.TransactionHash, event.EventData).
        Scan(&event.ID, &event.CreatedAt)
}

func (s *EventService) GetRecentEvents(ctx context.Context, vaultAddress string, hours int) ([]BlockchainEvent, error) {
    query := `
        SELECT id, block_number, transaction_hash, event_data, created_at
        FROM blockchain_events 
        WHERE event_data->>'vault' = $1
        AND created_at >= NOW() - INTERVAL '%d hours'
        ORDER BY created_at DESC
    `
    
    rows, err := s.pool.Query(ctx, fmt.Sprintf(query, hours), vaultAddress)
    if err != nil {
        return nil, err
    }
    defer rows.Close()
    
    var events []BlockchainEvent
    for rows.Next() {
        var event BlockchainEvent
        err := rows.Scan(&event.ID, &event.BlockNumber, &event.TransactionHash, 
                        &event.EventData, &event.CreatedAt)
        if err != nil {
            return nil, err
        }
        events = append(events, event)
    }
    return events, nil
}
```

**Pros:**
- ✅ Full PostgreSQL 17 feature access
- ✅ Maximum performance
- ✅ Complete control over partitioning
- ✅ Latest PostgreSQL features immediately

**Cons:**
- ❌ More boilerplate code
- ❌ No ORM conveniences
- ❌ Manual query building

## Recommendations for HyperEVM Yield Optimizer

### **Option 1: Bun + Custom Partitioning (Recommended)**

```go
// Best balance of convenience and control
package database

import (
    "github.com/uptrace/bun"
    "github.com/uptrace/bun/dialect/pgdialect"
    "github.com/uptrace/bun/driver/pgdriver"
)

type DB struct {
    *bun.DB
}

func NewDB(dsn string) (*DB, error) {
    sqldb := sql.OpenDB(pgdriver.NewConnector(pgdriver.WithDSN(dsn)))
    bunDB := bun.NewDB(sqldb, pgdialect.New())
    
    db := &DB{DB: bunDB}
    if err := db.setupPartitioning(); err != nil {
        return nil, err
    }
    
    return db, nil
}

func (db *DB) setupPartitioning() error {
    // Setup all partitioned tables
    tables := []string{
        `CREATE TABLE IF NOT EXISTS blockchain_events (...) PARTITION BY RANGE (created_at)`,
        `CREATE TABLE IF NOT EXISTS position_snapshots (...) PARTITION BY RANGE (created_at)`,
        `CREATE TABLE IF NOT EXISTS performance_metrics (...) PARTITION BY RANGE (recorded_at)`,
    }
    
    for _, table := range tables {
        if _, err := db.Exec(table); err != nil {
            return err
        }
    }
    
    return db.setupAutoPartitioning()
}
```

### **Option 2: Pure pgx for Maximum Performance**

For critical paths like real-time monitoring:

```go
// High-performance service for critical operations
type MonitorService struct {
    pool *pgxpool.Pool
}

func (s *MonitorService) BulkInsertEvents(ctx context.Context, events []BlockchainEvent) error {
    // Use COPY for maximum insert performance
    _, err := s.pool.CopyFrom(ctx, pgx.Identifier{"blockchain_events"}, 
        []string{"block_number", "transaction_hash", "event_data"}, 
        pgx.CopyFromSlice(len(events), func(i int) ([]interface{}, error) {
            return []interface{}{events[i].BlockNumber, events[i].TransactionHash, events[i].EventData}, nil
        }))
    return err
}
```

## Final Architecture Recommendation

### **Hybrid Approach: Bun + pgx**

```go
// Use Bun for standard CRUD operations
type VaultService struct {
    db *bun.DB
}

func (s *VaultService) CreateVault(vault *Vault) error {
    _, err := s.db.NewInsert().Model(vault).Exec(context.Background())
    return err
}

// Use pgx for high-performance time-series operations
type EventService struct {
    pool *pgxpool.Pool
}

func (s *EventService) BulkInsertEvents(events []BlockchainEvent) error {
    // Maximum performance for event ingestion
}
```

**Benefits:**
- ✅ Best of both worlds
- ✅ ORM convenience for business logic
- ✅ Raw performance for time-series data
- ✅ Full PostgreSQL 17 partitioning support
- ✅ Type safety where it matters

This approach gives you the productivity of an ORM while maintaining full control over PostgreSQL 17's advanced partitioning features.