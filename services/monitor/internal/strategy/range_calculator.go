package strategy

import (
    "fmt"
    "math"
    
    "github.com/shopspring/decimal"
)

// RangeCalculator calculates optimal tick ranges for positions
type RangeCalculator struct {
    tickSpacing int32
}

// NewRangeCalculator creates a new range calculator
func NewRangeCalculator(tickSpacing int32) *RangeCalculator {
    return &RangeCalculator{
        tickSpacing: tickSpacing,
    }
}

// CalculateFixedRange calculates a fixed range around the current tick
func (rc *RangeCalculator) CalculateFixedRange(currentTick int32, tickRadius int32) (int32, int32) {
    // Ensure range is aligned to tick spacing
    tickLower := rc.alignToTickSpacing(currentTick - tickRadius)
    tickUpper := rc.alignToTickSpacing(currentTick + tickRadius)
    
    // Ensure upper > lower
    if tickUpper <= tickLower {
        tickUpper = tickLower + rc.tickSpacing
    }
    
    return tickLower, tickUpper
}

// CalculateVolatilityAdjustedRange calculates range based on volatility
func (rc *RangeCalculator) CalculateVolatilityAdjustedRange(
    currentTick int32,
    volatility decimal.Decimal,
    sigmaMultiplier float64,
) (int32, int32) {
    // Higher volatility = wider range
    // tickRange = volatility * sigmaMultiplier * scalingFactor
    
    // Convert volatility to tick range
    // This is a simplified calculation - in production, use proper volatility scaling
    volFloat, _ := volatility.Float64()
    tickRange := int32(volFloat * sigmaMultiplier * 10000)
    
    // Minimum range
    minRange := rc.tickSpacing * 10
    if tickRange < minRange {
        tickRange = minRange
    }
    
    // Calculate bounds
    halfRange := tickRange / 2
    tickLower := rc.alignToTickSpacing(currentTick - halfRange)
    tickUpper := rc.alignToTickSpacing(currentTick + halfRange)
    
    return tickLower, tickUpper
}

// CalculateBollingerBands calculates range using Bollinger Bands
func (rc *RangeCalculator) CalculateBollingerBands(
    prices []decimal.Decimal,
    maPeriod int,
    stdDevMultiplier float64,
) (int32, int32, error) {
    if len(prices) < maPeriod {
        return 0, 0, ErrInsufficientData
    }
    
    // Calculate moving average
    ma := rc.calculateMA(prices[len(prices)-maPeriod:])
    
    // Calculate standard deviation
    stdDev := rc.calculateStdDev(prices[len(prices)-maPeriod:], ma)
    
    // Calculate bands
    upper := ma.Add(stdDev.Mul(decimal.NewFromFloat(stdDevMultiplier)))
    lower := ma.Sub(stdDev.Mul(decimal.NewFromFloat(stdDevMultiplier)))
    
    // Convert prices to ticks
    currentPrice := prices[len(prices)-1]
    tickLower := rc.priceToTick(lower, currentPrice)
    tickUpper := rc.priceToTick(upper, currentPrice)
    
    return rc.alignToTickSpacing(tickLower), rc.alignToTickSpacing(tickUpper), nil
}

// CalculateMeanReversionRange calculates range assuming mean reversion
func (rc *RangeCalculator) CalculateMeanReversionRange(
    prices []decimal.Decimal,
    lookbackPeriod int,
    rangePercent float64,
) (int32, int32, error) {
    if len(prices) < lookbackPeriod {
        return 0, 0, ErrInsufficientData
    }
    
    // Calculate mean price
    meanPrice := rc.calculateMA(prices[len(prices)-lookbackPeriod:])
    
    // Calculate range as percentage of mean
    rangeSize := meanPrice.Mul(decimal.NewFromFloat(rangePercent / 100))
    
    upper := meanPrice.Add(rangeSize.Div(decimal.NewFromInt(2)))
    lower := meanPrice.Sub(rangeSize.Div(decimal.NewFromInt(2)))
    
    // Convert to ticks
    currentPrice := prices[len(prices)-1]
    tickLower := rc.priceToTick(lower, currentPrice)
    tickUpper := rc.priceToTick(upper, currentPrice)
    
    return rc.alignToTickSpacing(tickLower), rc.alignToTickSpacing(tickUpper), nil
}

// CalculateDynamicRange combines multiple strategies
func (rc *RangeCalculator) CalculateDynamicRange(
    currentTick int32,
    volatility decimal.Decimal,
    prices []decimal.Decimal,
    params DynamicRangeParams,
) (int32, int32) {
    // Start with volatility-based range
    volLower, volUpper := rc.CalculateVolatilityAdjustedRange(
        currentTick,
        volatility,
        params.VolatilitySigma,
    )
    
    // If we have price history, also calculate Bollinger Bands
    if len(prices) >= params.BollingerPeriod {
        bbLower, bbUpper, err := rc.CalculateBollingerBands(
            prices,
            params.BollingerPeriod,
            params.BollingerSigma,
        )
        
        if err == nil {
            // Take the wider range for safety
            if bbLower < volLower {
                volLower = bbLower
            }
            if bbUpper > volUpper {
                volUpper = bbUpper
            }
        }
    }
    
    // Apply min/max constraints
    rangeSize := volUpper - volLower
    if rangeSize < params.MinRangeTicks {
        halfDiff := (params.MinRangeTicks - rangeSize) / 2
        volLower -= halfDiff
        volUpper += halfDiff
    } else if rangeSize > params.MaxRangeTicks {
        halfDiff := (rangeSize - params.MaxRangeTicks) / 2
        volLower += halfDiff
        volUpper -= halfDiff
    }
    
    return rc.alignToTickSpacing(volLower), rc.alignToTickSpacing(volUpper)
}

// Helper functions

func (rc *RangeCalculator) alignToTickSpacing(tick int32) int32 {
    return (tick / rc.tickSpacing) * rc.tickSpacing
}

func (rc *RangeCalculator) calculateMA(prices []decimal.Decimal) decimal.Decimal {
    sum := decimal.Zero
    for _, price := range prices {
        sum = sum.Add(price)
    }
    return sum.Div(decimal.NewFromInt(int64(len(prices))))
}

func (rc *RangeCalculator) calculateStdDev(prices []decimal.Decimal, mean decimal.Decimal) decimal.Decimal {
    sumSquaredDiff := decimal.Zero
    for _, price := range prices {
        diff := price.Sub(mean)
        sumSquaredDiff = sumSquaredDiff.Add(diff.Mul(diff))
    }
    
    variance := sumSquaredDiff.Div(decimal.NewFromInt(int64(len(prices))))
    
    // Use math package for square root since decimal doesn't have Sqrt
    varianceFloat, _ := variance.Float64()
    return decimal.NewFromFloat(math.Sqrt(varianceFloat))
}

func (rc *RangeCalculator) priceToTick(price, referencePrice decimal.Decimal) int32 {
    // tick = log(price/referencePrice) / log(1.0001)
    // This is a simplified calculation
    ratio := price.Div(referencePrice)
    logRatio, _ := ratio.Float64()
    tick := math.Log(logRatio) / math.Log(1.0001)
    
    return int32(tick)
}

// Types

type DynamicRangeParams struct {
    VolatilitySigma  float64
    BollingerPeriod  int
    BollingerSigma   float64
    MinRangeTicks    int32
    MaxRangeTicks    int32
}

var (
    ErrInsufficientData = fmt.Errorf("insufficient data for calculation")
)