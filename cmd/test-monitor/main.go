package main

import (
    "context"
    "fmt"
    "log"
    "os"
    "os/signal"
    "syscall"
    "time"

    "github.com/ethereum/go-ethereum/common"
    "github.com/ethereum/go-ethereum/ethclient"
    "github.com/jackc/pgx/v5/pgxpool"
    "github.com/joho/godotenv"
    "github.com/redis/go-redis/v9"
    "github.com/sirupsen/logrus"
    
    "hyperevm-yield-optimizer/internal/database"
    "hyperevm-yield-optimizer/services/monitor/internal/price"
)

func main() {
    // Load environment variables
    if err := godotenv.Load(); err != nil {
        log.Println("No .env file found, using environment variables")
    }

    // Initialize logger
    logger := logrus.New()
    logger.SetFormatter(&logrus.JSONFormatter{})
    
    logLevel := os.Getenv("LOG_LEVEL")
    switch logLevel {
    case "debug":
        logger.SetLevel(logrus.DebugLevel)
    case "warn":
        logger.SetLevel(logrus.WarnLevel)
    case "error":
        logger.SetLevel(logrus.ErrorLevel)
    default:
        logger.SetLevel(logrus.InfoLevel)
    }

    logger.Info("Starting HyperEVM Price Monitor Test")

    // Create context with cancellation
    ctx, cancel := context.WithCancel(context.Background())
    defer cancel()

    // Connect to databases
    if err := setupDatabases(ctx, logger); err != nil {
        logger.Fatal("Failed to setup databases:", err)
    }

    // Connect to HyperEVM
    rpcURL := getEnvOrDefault("RPC_URL", "https://rpc.hyperliquid.xyz/evm")
    ethClient, err := ethclient.Dial(rpcURL)
    if err != nil {
        logger.Fatal("Failed to connect to HyperEVM:", err)
    }
    defer ethClient.Close()

    // Test connection
    chainID, err := ethClient.ChainID(ctx)
    if err != nil {
        logger.Fatal("Failed to get chain ID:", err)
    }
    logger.WithField("chainID", chainID.String()).Info("Connected to HyperEVM")

    // Connect to Redis
    redisURL := getEnvOrDefault("REDIS_URL", "localhost:6379")
    redisClient := redis.NewClient(&redis.Options{
        Addr: redisURL,
    })
    defer redisClient.Close()

    // Test Redis connection
    pong, err := redisClient.Ping(ctx).Result()
    if err != nil {
        logger.Fatal("Failed to connect to Redis:", err)
    }
    logger.WithField("response", pong).Info("Connected to Redis")

    // Initialize price oracle
    priceOracle := price.NewOracle(ethClient, redisClient, logger)

    // Add some test pools (these are placeholder addresses)
    testPools := []*price.PoolData{
        {
            Address:     common.HexToAddress("0x1111111111111111111111111111111111111111"),
            Token0:      common.HexToAddress("0x2222222222222222222222222222222222222222"),
            Token1:      common.HexToAddress("0x3333333333333333333333333333333333333333"),
            TickSpacing: 60,
        },
    }

    for _, pool := range testPools {
        priceOracle.AddPool(pool)
    }

    // Start price oracle
    go priceOracle.Start(ctx)

    // Test price monitoring
    logger.Info("Price oracle started, testing for 30 seconds...")
    
    // Test ticker
    ticker := time.NewTicker(5 * time.Second)
    defer ticker.Stop()

    // Handle graceful shutdown
    sigChan := make(chan os.Signal, 1)
    signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)

    testDuration := time.After(30 * time.Second)

    for {
        select {
        case <-ticker.C:
            logger.Info("Price oracle is running...")
            
            // Test getting prices for monitored pools
            for _, pool := range testPools {
                priceData, err := priceOracle.GetPrice(pool.Address)
                if err != nil {
                    logger.WithError(err).Warn("Failed to get price")
                } else {
                    logger.WithFields(logrus.Fields{
                        "pool":         pool.Address.Hex(),
                        "token0_price": priceData.Token0Price.String(),
                        "tick":         priceData.Tick,
                    }).Info("Price data retrieved")
                }
            }

        case <-testDuration:
            logger.Info("Test completed successfully!")
            return

        case <-sigChan:
            logger.Info("Shutting down...")
            priceOracle.Stop()
            return
        }
    }
}

func setupDatabases(ctx context.Context, logger *logrus.Logger) error {
    // Connect to PostgreSQL
    databaseURL := os.Getenv("DATABASE_URL")
    if databaseURL == "" {
        return fmt.Errorf("DATABASE_URL environment variable required")
    }

    pool, err := pgxpool.New(ctx, databaseURL)
    if err != nil {
        return fmt.Errorf("failed to connect to PostgreSQL: %w", err)
    }
    defer pool.Close()

    // Test connection
    err = pool.Ping(ctx)
    if err != nil {
        return fmt.Errorf("failed to ping PostgreSQL: %w", err)
    }

    logger.Info("Connected to PostgreSQL")

    // Initialize database with sqlc
    db := database.New(pool)

    // Test a simple query to verify sqlc is working
    pools, err := db.GetMonitoredPools(ctx)
    if err != nil {
        logger.WithError(err).Warn("Could not get monitored pools (table may not exist yet)")
    } else {
        logger.WithField("count", len(pools)).Info("Found monitored pools")
    }

    return nil
}

func getEnvOrDefault(key, defaultValue string) string {
    if value := os.Getenv(key); value != "" {
        return value
    }
    return defaultValue
}