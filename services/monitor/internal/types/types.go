package types

import (
    "math/big"
    "time"
)

// Position represents a concentrated liquidity position
type Position struct {
    ID          string
    TokenID     *big.Int
    Owner       string
    VaultAddr   string
    PoolAddr    string
    Token0      string
    Token1      string
    TickLower   int32
    TickUpper   int32
    Liquidity   *big.Int
    InRange     bool
    LastChecked time.Time
}

// Pool represents a liquidity pool
type Pool struct {
    Address      string
    Token0       string
    Token1       string
    Fee          *big.Int
    TickSpacing  int32
    CurrentTick  int32
    CurrentPrice *big.Int
    Liquidity    *big.Int
}

// PriceData represents price information
type PriceData struct {
    Pool         string
    Token0Price  *big.Float
    Token1Price  *big.Float
    Tick         int32
    Timestamp    time.Time
}

// RebalanceRequest represents a request to rebalance a position
type RebalanceRequest struct {
    PositionID   string
    VaultAddr    string
    OldTickLower int32
    OldTickUpper int32
    NewTickLower int32
    NewTickUpper int32
    Reason       string
    Urgency      int // 1-10, higher is more urgent
    EstimatedGas *big.Int
    Timestamp    time.Time
}

// VaultStatus represents the current status of a vault
type VaultStatus struct {
    Address          string
    TotalValueLocked *big.Int
    ActivePositions  int
    InRangePositions int
    LastRebalance    time.Time
    APY              float64
}

// BlockEvent represents a blockchain event
type BlockEvent struct {
    BlockNumber     int64
    TransactionHash string
    LogIndex        uint
    ContractAddress string
    EventName       string
    EventData       map[string]interface{}
    Timestamp       time.Time
}

// PositionSnapshot represents a point-in-time snapshot of a position
type PositionSnapshot struct {
    ID          string
    PositionID  string
    VaultAddr   string
    TickCurrent int32
    TickLower   int32
    TickUpper   int32
    Liquidity   *big.Int
    InRange     bool
    FeesEarned  *big.Int
    Value0      *big.Int
    Value1      *big.Int
    SnapshotAt  time.Time
}

// MonitoringMetrics represents monitoring metrics
type MonitoringMetrics struct {
    BlocksProcessed      int64
    EventsProcessed      int64
    PositionsMonitored   int64
    RebalancesTriggered  int64
    AverageCheckDuration time.Duration
    LastBlockProcessed   int64
    LastUpdateTime       time.Time
}

// StrategyParams represents parameters for rebalancing strategies
type StrategyParams struct {
    Type              string // "fixed_range", "volatility_adaptive", "bollinger", "mean_reversion"
    TickRadius        int32  // For fixed range
    VolatilityPeriod  int    // For volatility adaptive
    RebalanceThreshold float64 // Percentage out of range before rebalancing
    MinRebalanceInterval time.Duration
    MaxGasPrice       *big.Int
}

// RangeCalculation represents a calculated range for a position
type RangeCalculation struct {
    TickLower    int32
    TickUpper    int32
    OptimalRatio float64 // Optimal token0/token1 ratio
    Confidence   float64 // 0-1, confidence in the calculation
}

// VolatilityData represents volatility metrics
type VolatilityData struct {
    Pool            string
    Period          time.Duration
    StandardDev     float64
    MeanPrice       float64
    High            float64
    Low             float64
    SampleCount     int
    CalculatedAt    time.Time
}