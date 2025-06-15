package price

import (
    "context"
    "encoding/json"
    "fmt"
    "math"
    "math/big"
    "sync"
    "time"

    "github.com/ethereum/go-ethereum/common"
    "github.com/ethereum/go-ethereum/ethclient"
    "github.com/redis/go-redis/v9"
    "github.com/shopspring/decimal"
    "github.com/sirupsen/logrus"
)

const (
    // Price precision constants
    Q96  = 96
    Q192 = 192
)

// PoolData represents the current state of a liquidity pool
type PoolData struct {
    Address      common.Address
    Token0       common.Address
    Token1       common.Address
    Fee          *big.Int
    TickSpacing  int32
    SqrtPriceX96 *big.Int
    Tick         int32
    Liquidity    *big.Int
}

// PriceData represents calculated prices
type PriceData struct {
    Pool        common.Address
    Token0Price decimal.Decimal
    Token1Price decimal.Decimal
    Tick        int32
    Timestamp   time.Time
}

// Oracle handles price monitoring and caching
type Oracle struct {
    ethClient   *ethclient.Client
    redisClient *redis.Client
    logger      *logrus.Logger
    
    pools      map[common.Address]*PoolData
    poolsMutex sync.RWMutex
    
    updateInterval time.Duration
    ctx           context.Context
    cancel        context.CancelFunc
}

// NewOracle creates a new price oracle instance
func NewOracle(ethClient *ethclient.Client, redisClient *redis.Client, logger *logrus.Logger) *Oracle {
    return &Oracle{
        ethClient:      ethClient,
        redisClient:    redisClient,
        logger:         logger,
        pools:          make(map[common.Address]*PoolData),
        updateInterval: 5 * time.Second,
    }
}

// Start begins the price monitoring process
func (o *Oracle) Start(ctx context.Context) {
    o.ctx, o.cancel = context.WithCancel(ctx)
    
    ticker := time.NewTicker(o.updateInterval)
    defer ticker.Stop()
    
    // Initial update
    o.updatePrices()
    
    for {
        select {
        case <-ticker.C:
            o.updatePrices()
        case <-o.ctx.Done():
            o.logger.Info("Price oracle stopped")
            return
        }
    }
}

// Stop halts the price monitoring
func (o *Oracle) Stop() {
    if o.cancel != nil {
        o.cancel()
    }
}

// AddPool adds a pool to monitor
func (o *Oracle) AddPool(pool *PoolData) {
    o.poolsMutex.Lock()
    defer o.poolsMutex.Unlock()
    
    o.pools[pool.Address] = pool
    o.logger.WithField("pool", pool.Address.Hex()).Info("Added pool to price oracle")
}

// GetPrice returns the latest price for a pool
func (o *Oracle) GetPrice(poolAddress common.Address) (*PriceData, error) {
    // First check Redis cache
    cacheKey := fmt.Sprintf("price:%s", poolAddress.Hex())
    
    cached, err := o.redisClient.Get(o.ctx, cacheKey).Result()
    if err == nil {
        var priceData PriceData
        if err := json.Unmarshal([]byte(cached), &priceData); err == nil {
            return &priceData, nil
        }
    }
    
    // If not in cache, fetch from pool
    o.poolsMutex.RLock()
    pool, exists := o.pools[poolAddress]
    o.poolsMutex.RUnlock()
    
    if !exists {
        return nil, fmt.Errorf("pool not monitored: %s", poolAddress.Hex())
    }
    
    return o.fetchPoolPrice(pool)
}

// updatePrices updates prices for all monitored pools
func (o *Oracle) updatePrices() {
    o.poolsMutex.RLock()
    pools := make([]*PoolData, 0, len(o.pools))
    for _, pool := range o.pools {
        pools = append(pools, pool)
    }
    o.poolsMutex.RUnlock()
    
    var wg sync.WaitGroup
    for _, pool := range pools {
        wg.Add(1)
        go func(p *PoolData) {
            defer wg.Done()
            
            priceData, err := o.fetchPoolPrice(p)
            if err != nil {
                o.logger.WithError(err).WithField("pool", p.Address.Hex()).Error("Failed to fetch pool price")
                return
            }
            
            // Cache in Redis with TTL
            cacheKey := fmt.Sprintf("price:%s", p.Address.Hex())
            priceJSON, _ := json.Marshal(priceData)
            o.redisClient.Set(o.ctx, cacheKey, priceJSON, 30*time.Second)
            
            // Also store in Redis TimeSeries if available
            o.storePriceTimeSeries(priceData)
        }(pool)
    }
    
    wg.Wait()
}

// fetchPoolPrice fetches the current price from a pool contract
func (o *Oracle) fetchPoolPrice(pool *PoolData) (*PriceData, error) {
    // In a real implementation, this would call the pool contract
    // For now, we'll use the stored data and calculate prices
    
    // Calculate prices from sqrtPriceX96
    token0Price, token1Price := o.calculatePricesFromSqrtPriceX96(pool.SqrtPriceX96)
    
    return &PriceData{
        Pool:        pool.Address,
        Token0Price: token0Price,
        Token1Price: token1Price,
        Tick:        pool.Tick,
        Timestamp:   time.Now(),
    }, nil
}

// calculatePricesFromSqrtPriceX96 converts sqrtPriceX96 to human-readable prices
func (o *Oracle) calculatePricesFromSqrtPriceX96(sqrtPriceX96 *big.Int) (decimal.Decimal, decimal.Decimal) {
    // sqrtPriceX96 = sqrt(price) * 2^96
    // price = (sqrtPriceX96 / 2^96)^2
    
    // Handle nil input
    if sqrtPriceX96 == nil {
        return decimal.NewFromInt(1), decimal.NewFromInt(1)
    }
    
    Q96Decimal := decimal.NewFromInt(1).Shift(96)
    sqrtPriceDecimal := decimal.NewFromBigInt(sqrtPriceX96, 0)
    
    // price = (sqrtPriceX96 / 2^96)^2
    sqrtPrice := sqrtPriceDecimal.Div(Q96Decimal)
    price := sqrtPrice.Mul(sqrtPrice)
    
    // token0Price = price (token1 per token0)
    // token1Price = 1 / price (token0 per token1)
    token0Price := price
    token1Price := decimal.NewFromInt(1).Div(price)
    
    return token0Price, token1Price
}

// storePriceTimeSeries stores price data in Redis TimeSeries
func (o *Oracle) storePriceTimeSeries(priceData *PriceData) {
    timestamp := priceData.Timestamp.UnixMilli()
    
    // Store token0 price
    key0 := fmt.Sprintf("ts:price:%s:token0", priceData.Pool.Hex())
    o.redisClient.Do(o.ctx, "TS.ADD", key0, timestamp, priceData.Token0Price.String())
    
    // Store token1 price
    key1 := fmt.Sprintf("ts:price:%s:token1", priceData.Pool.Hex())
    o.redisClient.Do(o.ctx, "TS.ADD", key1, timestamp, priceData.Token1Price.String())
    
    // Store tick
    keyTick := fmt.Sprintf("ts:tick:%s", priceData.Pool.Hex())
    o.redisClient.Do(o.ctx, "TS.ADD", keyTick, timestamp, priceData.Tick)
}

// GetPriceHistory retrieves historical price data from Redis TimeSeries
func (o *Oracle) GetPriceHistory(poolAddress common.Address, duration time.Duration) ([]PriceData, error) {
    endTime := time.Now()
    startTime := endTime.Add(-duration)
    
    key := fmt.Sprintf("ts:price:%s:token0", poolAddress.Hex())
    
    // Query Redis TimeSeries
    _ = o.redisClient.Do(o.ctx, "TS.RANGE", key, 
        startTime.UnixMilli(), 
        endTime.UnixMilli())
    
    // Parse results and return
    // Implementation depends on Redis TimeSeries response format
    
    return []PriceData{}, nil
}

// CalculateVolatility calculates price volatility for a pool
func (o *Oracle) CalculateVolatility(poolAddress common.Address, period time.Duration) (decimal.Decimal, error) {
    prices, err := o.GetPriceHistory(poolAddress, period)
    if err != nil {
        return decimal.Zero, err
    }
    
    if len(prices) < 2 {
        return decimal.Zero, fmt.Errorf("insufficient price data for volatility calculation")
    }
    
    // Calculate returns
    returns := make([]decimal.Decimal, 0, len(prices)-1)
    for i := 1; i < len(prices); i++ {
        prevPrice := prices[i-1].Token0Price
        currPrice := prices[i].Token0Price
        
        if prevPrice.IsZero() {
            continue
        }
        
        // Calculate log return using math package since decimal doesn't have Ln
        ratio, _ := currPrice.Div(prevPrice).Float64()
        ret := decimal.NewFromFloat(math.Log(ratio))
        returns = append(returns, ret)
    }
    
    if len(returns) == 0 {
        return decimal.Zero, nil
    }
    
    // Calculate standard deviation of returns
    mean := decimal.Zero
    for _, ret := range returns {
        mean = mean.Add(ret)
    }
    mean = mean.Div(decimal.NewFromInt(int64(len(returns))))
    
    variance := decimal.Zero
    for _, ret := range returns {
        diff := ret.Sub(mean)
        variance = variance.Add(diff.Mul(diff))
    }
    variance = variance.Div(decimal.NewFromInt(int64(len(returns))))
    
    // Standard deviation is square root of variance
    // Using math package since decimal doesn't have Sqrt
    varianceFloat, _ := variance.Float64()
    volatility := decimal.NewFromFloat(math.Sqrt(varianceFloat))
    
    return volatility, nil
}