package monitor

import (
    "context"
    "encoding/json"
    "fmt"
    "math/big"
    "sync"
    "time"

    "github.com/ethereum/go-ethereum"
    "github.com/ethereum/go-ethereum/common"
    "github.com/ethereum/go-ethereum/ethclient"
    "github.com/jackc/pgx/v5/pgtype"
    "github.com/jackc/pgx/v5/pgxpool"
    "github.com/redis/go-redis/v9"
    "github.com/sirupsen/logrus"

    "hyperevm-yield-optimizer/internal/database"
    "hyperevm-yield-optimizer/services/monitor/internal/price"
    "hyperevm-yield-optimizer/services/monitor/internal/types"
)

// Service handles position monitoring and range detection
type Service struct {
    ethClient    *ethclient.Client
    db           *database.Queries
    pgPool       *pgxpool.Pool
    redisClient  *redis.Client
    priceOracle  *price.Oracle
    logger       *logrus.Logger
    
    // Configuration
    blockConfirmations int
    checkInterval      time.Duration
    maxConcurrent      int
    
    // Internal state
    positions      map[string]*types.Position
    positionsMutex sync.RWMutex
    
    // Control
    ctx    context.Context
    cancel context.CancelFunc
    wg     sync.WaitGroup
}

// NewService creates a new monitoring service
func NewService(
    ethClient *ethclient.Client,
    pgPool *pgxpool.Pool,
    redisClient *redis.Client,
    priceOracle *price.Oracle,
    logger *logrus.Logger,
) *Service {
    return &Service{
        ethClient:          ethClient,
        db:                database.New(pgPool),
        pgPool:            pgPool,
        redisClient:       redisClient,
        priceOracle:       priceOracle,
        logger:            logger,
        blockConfirmations: 2,
        checkInterval:     30 * time.Second,
        maxConcurrent:     10,
        positions:         make(map[string]*types.Position),
    }
}

// Start begins the monitoring service
func (s *Service) Start(ctx context.Context) error {
    s.ctx, s.cancel = context.WithCancel(ctx)
    
    // Load monitored pools
    if err := s.loadMonitoredPools(); err != nil {
        return fmt.Errorf("failed to load monitored pools: %w", err)
    }
    
    // Start block listener
    s.wg.Add(1)
    go s.blockListener()
    
    // Start position checker
    s.wg.Add(1)
    go s.positionChecker()
    
    // Start volatility calculator
    s.wg.Add(1)
    go s.volatilityCalculator()
    
    s.logger.Info("Monitor service started")
    return nil
}

// Shutdown gracefully stops the service
func (s *Service) Shutdown(ctx context.Context) error {
    s.logger.Info("Shutting down monitor service...")
    
    // Cancel context to stop goroutines
    s.cancel()
    
    // Wait for goroutines to finish
    done := make(chan struct{})
    go func() {
        s.wg.Wait()
        close(done)
    }()
    
    select {
    case <-done:
        s.logger.Info("Monitor service stopped gracefully")
        return nil
    case <-ctx.Done():
        s.logger.Warn("Monitor service shutdown timeout")
        return ctx.Err()
    }
}

// loadMonitoredPools loads pools to monitor from database
func (s *Service) loadMonitoredPools() error {
    pools, err := s.db.GetMonitoredPools(s.ctx)
    if err != nil {
        return err
    }
    
    for _, pool := range pools {
        poolData := &price.PoolData{
            Address:     common.HexToAddress(pool.PoolAddress),
            Token0:      common.HexToAddress(pool.Token0Address),
            Token1:      common.HexToAddress(pool.Token1Address),
            Fee:         big.NewInt(int64(pool.Fee)),
            TickSpacing: pool.TickSpacing,
        }
        
        s.priceOracle.AddPool(poolData)
        s.logger.WithField("pool", pool.PoolAddress).Info("Added pool to monitoring")
    }
    
    return nil
}

// blockListener listens for new blocks and processes events
func (s *Service) blockListener() {
    defer s.wg.Done()
    
    // Use polling instead of WebSocket subscription since HyperEVM doesn't support it
    ticker := time.NewTicker(10 * time.Second) // Poll every 10 seconds
    defer ticker.Stop()
    
    var lastBlock uint64
    
    for {
        select {
        case <-s.ctx.Done():
            return
            
        case <-ticker.C:
            // Get latest block number
            latestBlock, err := s.ethClient.BlockNumber(s.ctx)
            if err != nil {
                s.logger.WithError(err).Error("Failed to get latest block")
                continue
            }
            
            // Process new blocks
            if latestBlock > lastBlock {
                s.logger.WithField("block", latestBlock).Debug("New block detected")
                
                // Process block after confirmations
                if latestBlock > uint64(s.blockConfirmations) {
                    blockNumber := latestBlock - uint64(s.blockConfirmations)
                    go s.processBlock(blockNumber)
                }
                
                lastBlock = latestBlock
            }
        }
    }
}

// processBlock processes events from a confirmed block
func (s *Service) processBlock(blockNumber uint64) {
    ctx, cancel := context.WithTimeout(s.ctx, 30*time.Second)
    defer cancel()
    
    // Query for swap events
    query := ethereum.FilterQuery{
        FromBlock: big.NewInt(int64(blockNumber)),
        ToBlock:   big.NewInt(int64(blockNumber)),
        Topics:    [][]common.Hash{{common.HexToHash("0xc42079f94a6350d7e6235f29174924f928cc2ac818eb64fed8004e115fbcca67")}}, // Swap event
    }
    
    logs, err := s.ethClient.FilterLogs(ctx, query)
    if err != nil {
        s.logger.WithError(err).Error("Failed to filter logs")
        return
    }
    
    // Process logs
    // Process logs individually since BulkInsertEvents is not available
    for _, log := range logs {
        eventData := map[string]interface{}{
            "pool":   log.Address.Hex(),
            "topics": log.Topics,
            "data":   log.Data,
        }
        
        // Log the event for monitoring
        s.logger.WithFields(logrus.Fields{
            "block":    log.BlockNumber,
            "tx":       log.TxHash.Hex(),
            "address":  log.Address.Hex(),
            "logIndex": log.Index,
            "event":    "Swap",
        }).Debug("Processed blockchain event")
        
        // TODO: Store event data if needed
        _ = eventData
    }
}

// positionChecker periodically checks position status
func (s *Service) positionChecker() {
    defer s.wg.Done()
    
    ticker := time.NewTicker(s.checkInterval)
    defer ticker.Stop()
    
    // Initial check
    s.checkAllPositions()
    
    for {
        select {
        case <-ticker.C:
            s.checkAllPositions()
            
        case <-s.ctx.Done():
            return
        }
    }
}

// checkAllPositions checks all monitored positions
func (s *Service) checkAllPositions() {
    ctx, cancel := context.WithTimeout(s.ctx, 5*time.Minute)
    defer cancel()
    
    // Get vault addresses from config or database
    vaultAddresses := []string{} // TODO: Load from config
    
    if len(vaultAddresses) == 0 {
        return
    }
    
    // Get latest position snapshots
    positions, err := s.db.GetLatestPositionSnapshots(ctx, vaultAddresses)
    if err != nil {
        s.logger.WithError(err).Error("Failed to get position snapshots")
        return
    }
    
    // Check each position concurrently
    sem := make(chan struct{}, s.maxConcurrent)
    var wg sync.WaitGroup
    
    for _, pos := range positions {
        wg.Add(1)
        sem <- struct{}{}
        
        go func(position database.PositionSnapshots) {
            defer wg.Done()
            defer func() { <-sem }()
            
            s.checkPosition(ctx, position)
        }(pos)
    }
    
    wg.Wait()
    
    // Check for positions needing rebalance
    s.checkRebalanceNeeded(ctx)
}

// checkPosition checks a single position and updates its status
func (s *Service) checkPosition(ctx context.Context, position database.PositionSnapshots) {
    // Get current pool price
    poolAddr := common.HexToAddress(position.PoolAddress)
    priceData, err := s.priceOracle.GetPrice(poolAddr)
    if err != nil {
        s.logger.WithError(err).WithField("pool", position.PoolAddress).Error("Failed to get pool price")
        return
    }
    
    // Create new snapshot
    _, err = s.db.InsertPositionSnapshot(ctx, database.InsertPositionSnapshotParams{
        PositionID:   position.PositionID,
        VaultAddress: position.VaultAddress,
        PoolAddress:  position.PoolAddress,
        TokenID:      position.TokenID,
        TickCurrent:  priceData.Tick,
        TickLower:    position.TickLower,
        TickUpper:    position.TickUpper,
        Liquidity:    position.Liquidity,
        FeesEarned:   position.FeesEarned, // TODO: Fetch from contract
        Value0:       position.Value0,       // TODO: Calculate current values
        Value1:       position.Value1,
    })
    
    if err != nil {
        s.logger.WithError(err).Error("Failed to insert position snapshot")
        return
    }
    
    // Log position status
    inRange := priceData.Tick >= position.TickLower && priceData.Tick < position.TickUpper
    if !inRange {
        s.logger.WithFields(logrus.Fields{
            "position_id": position.PositionID,
            "vault":       position.VaultAddress,
            "tick":        priceData.Tick,
            "range":       fmt.Sprintf("[%d, %d]", position.TickLower, position.TickUpper),
        }).Warn("Position out of range")
    }
}

// checkRebalanceNeeded checks if any positions need rebalancing
func (s *Service) checkRebalanceNeeded(ctx context.Context) {
    // Get positions out of range
    outOfRange, err := s.db.GetPositionsOutOfRange(ctx)
    if err != nil {
        s.logger.WithError(err).Error("Failed to get out of range positions")
        return
    }
    
    for _, pos := range outOfRange {
        // Check if position has been out of range for too long
        secondsOut, _ := pos.SecondsSinceUpdate.Float64()
        if secondsOut > 300 { // 5 minutes
            s.logger.WithFields(logrus.Fields{
                "position_id": pos.PositionID,
                "vault":       pos.VaultAddress,
                "seconds_out": pos.SecondsSinceUpdate,
            }).Warn("Position needs rebalancing")
            
            // Queue rebalance request
            s.queueRebalance(ctx, pos)
        }
    }
    
    // Also check positions near range edge
    // Get positions near range edge (within 10% of edge)
    var threshold pgtype.Numeric
    if err := threshold.Scan("10"); err != nil {
        s.logger.WithError(err).Error("Failed to set threshold")
        return
    }
    nearEdge, err := s.db.GetPositionsNearRangeEdge(ctx, threshold)
    if err != nil {
        s.logger.WithError(err).Error("Failed to get near edge positions")
        return
    }
    
    for _, pos := range nearEdge {
        s.logger.WithFields(logrus.Fields{
            "position_id":      pos.PositionID,
            "vault":           pos.VaultAddress,
            "range_percentage": pos.RangePercentage,
        }).Info("Position near range edge")
    }
}

// queueRebalance queues a position for rebalancing
func (s *Service) queueRebalance(ctx context.Context, position database.GetPositionsOutOfRangeRow) error {
    request := types.RebalanceRequest{
        PositionID:   position.PositionID.String(),
        VaultAddr:    position.VaultAddress,
        OldTickLower: position.TickLower,
        OldTickUpper: position.TickUpper,
        Reason:       "Out of range",
        Urgency:      5,
        Timestamp:    time.Now(),
    }
    
    // Serialize request
    data, err := json.Marshal(request)
    if err != nil {
        return err
    }
    
    // Push to Redis queue
    return s.redisClient.LPush(ctx, "rebalance:queue", data).Err()
}

// volatilityCalculator periodically calculates volatility metrics
func (s *Service) volatilityCalculator() {
    defer s.wg.Done()
    
    ticker := time.NewTicker(5 * time.Minute)
    defer ticker.Stop()
    
    for {
        select {
        case <-ticker.C:
            s.calculateVolatilityMetrics()
            
        case <-s.ctx.Done():
            return
        }
    }
}

// calculateVolatilityMetrics calculates volatility for all pools
func (s *Service) calculateVolatilityMetrics() {
    ctx, cancel := context.WithTimeout(s.ctx, 2*time.Minute)
    defer cancel()
    
    pools, err := s.db.GetMonitoredPools(ctx)
    if err != nil {
        s.logger.WithError(err).Error("Failed to get monitored pools")
        return
    }
    
    periods := []int32{5, 15, 60, 240, 1440} // 5min, 15min, 1hr, 4hr, 24hr
    
    for _, pool := range pools {
        for _, period := range periods {
            volatility, err := s.priceOracle.CalculateVolatility(
                common.HexToAddress(pool.PoolAddress),
                time.Duration(period)*time.Minute,
            )
            
            if err != nil {
                continue
            }
            
            // Store volatility metric
            // Convert decimal values to pgtype.Numeric
            var pgVolatility, pgHigh, pgLow, pgMean pgtype.Numeric
            _ = pgVolatility.Scan(volatility.String())
            _ = pgHigh.Scan("0")
            _ = pgLow.Scan("0")
            _ = pgMean.Scan("0")
            
            _, err = s.db.InsertVolatilityMetric(ctx, database.InsertVolatilityMetricParams{
                PoolAddress:    pool.PoolAddress,
                PeriodMinutes:  period,
                Volatility:     pgVolatility,
                HighPrice:      pgHigh, // TODO: Calculate from price history
                LowPrice:       pgLow,
                MeanPrice:      pgMean,
                SampleCount:    0,
            })
            
            if err != nil {
                s.logger.WithError(err).Error("Failed to insert volatility metric")
            }
        }
    }
}