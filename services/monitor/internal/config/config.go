package config

import (
    "fmt"
    "os"
    "strconv"
    "strings"
    "time"
)

type Config struct {
    // Network configuration
    RPCURL      string
    WSRPCURL    string
    ChainID     int64
    
    // Database configuration
    DatabaseURL string // Supabase PostgreSQL URL
    
    // Redis configuration
    RedisURL string
    
    // Monitoring configuration
    BlockConfirmations   int
    PositionCheckInterval time.Duration
    MaxConcurrentChecks  int
    
    // Contract addresses
    PositionManagerAddress string
    VaultAddresses         []string
    
    // Oracle configuration
    OraclePrecompile string
    PriceUpdateInterval time.Duration
    
    // Performance settings
    BatchSize int
    WorkerCount int
    
    // Logging
    LogLevel string
    
    // Metrics
    MetricsEnabled bool
    MetricsPort    int
}

func Load() (*Config, error) {
    cfg := &Config{
        // Default values
        BlockConfirmations:    2,
        PositionCheckInterval: 30 * time.Second,
        MaxConcurrentChecks:   10,
        BatchSize:            100,
        WorkerCount:          5,
        LogLevel:            "info",
        MetricsEnabled:      true,
        MetricsPort:         9090,
        PriceUpdateInterval: 5 * time.Second,
    }
    
    // Load from environment
    cfg.RPCURL = getEnvOrDefault("RPC_URL", "https://rpc.hyperliquid.xyz/evm")
    cfg.WSRPCURL = getEnvOrDefault("WS_RPC_URL", "wss://rpc.hyperliquid.xyz/evm")
    cfg.DatabaseURL = getEnvRequired("DATABASE_URL")
    cfg.RedisURL = getEnvOrDefault("REDIS_URL", "localhost:6379")
    
    // Chain configuration
    chainID, err := strconv.ParseInt(getEnvOrDefault("CHAIN_ID", "999"), 10, 64)
    if err != nil {
        return nil, fmt.Errorf("invalid CHAIN_ID: %w", err)
    }
    cfg.ChainID = chainID
    
    // Oracle configuration
    cfg.OraclePrecompile = getEnvOrDefault("ORACLE_PRECOMPILE", "0x0000000000000000000000000000000000000807")
    
    // Contract addresses
    cfg.PositionManagerAddress = getEnvRequired("POSITION_MANAGER_ADDRESS")
    vaultAddrs := getEnvOrDefault("VAULT_ADDRESSES", "")
    if vaultAddrs != "" {
        cfg.VaultAddresses = strings.Split(vaultAddrs, ",")
    }
    
    // Performance tuning
    if maxChecks := os.Getenv("MAX_CONCURRENT_CHECKS"); maxChecks != "" {
        cfg.MaxConcurrentChecks, _ = strconv.Atoi(maxChecks)
    }
    
    if batchSize := os.Getenv("BATCH_SIZE"); batchSize != "" {
        cfg.BatchSize, _ = strconv.Atoi(batchSize)
    }
    
    if workerCount := os.Getenv("WORKER_COUNT"); workerCount != "" {
        cfg.WorkerCount, _ = strconv.Atoi(workerCount)
    }
    
    // Intervals
    if checkInterval := os.Getenv("POSITION_CHECK_INTERVAL"); checkInterval != "" {
        duration, err := time.ParseDuration(checkInterval)
        if err == nil {
            cfg.PositionCheckInterval = duration
        }
    }
    
    if priceInterval := os.Getenv("PRICE_UPDATE_INTERVAL"); priceInterval != "" {
        duration, err := time.ParseDuration(priceInterval)
        if err == nil {
            cfg.PriceUpdateInterval = duration
        }
    }
    
    return cfg, nil
}

func getEnvRequired(key string) string {
    value := os.Getenv(key)
    if value == "" {
        panic(fmt.Sprintf("required environment variable %s not set", key))
    }
    return value
}

func getEnvOrDefault(key, defaultValue string) string {
    if value := os.Getenv(key); value != "" {
        return value
    }
    return defaultValue
}