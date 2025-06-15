package main

import (
    "context"
    "log"
    "os"
    "os/signal"
    "syscall"
    "time"

    "github.com/ethereum/go-ethereum/ethclient"
    "github.com/jackc/pgx/v5/pgxpool"
    "github.com/joho/godotenv"
    "github.com/redis/go-redis/v9"
    "github.com/sirupsen/logrus"
    
    "hyperevm-yield-optimizer/services/monitor/internal/config"
    "hyperevm-yield-optimizer/services/monitor/internal/monitor"
    "hyperevm-yield-optimizer/services/monitor/internal/price"
)

func main() {
    // Load environment variables
    if err := godotenv.Load(); err != nil {
        log.Println("No .env file found")
    }

    // Initialize logger
    logger := logrus.New()
    logger.SetFormatter(&logrus.JSONFormatter{})
    logger.SetLevel(logrus.InfoLevel)

    // Load configuration
    cfg, err := config.Load()
    if err != nil {
        logger.Fatal("Failed to load configuration:", err)
    }

    // Create context with cancellation
    ctx, cancel := context.WithCancel(context.Background())
    defer cancel()

    // Connect to Ethereum client
    ethClient, err := ethclient.Dial(cfg.RPCURL)
    if err != nil {
        logger.Fatal("Failed to connect to Ethereum client:", err)
    }
    defer ethClient.Close()

    // Connect to PostgreSQL (Supabase)
    pgPool, err := pgxpool.New(ctx, cfg.DatabaseURL)
    if err != nil {
        logger.Fatal("Failed to connect to PostgreSQL:", err)
    }
    defer pgPool.Close()

    // Connect to Redis
    redisClient := redis.NewClient(&redis.Options{
        Addr:     cfg.RedisURL,
        Password: "", // no password set
        DB:       0,  // use default DB
    })
    defer redisClient.Close()

    // Initialize services
    priceOracle := price.NewOracle(ethClient, redisClient, logger)
    monitorService := monitor.NewService(
        ethClient,
        pgPool,
        redisClient,
        priceOracle,
        logger,
    )

    // Start services
    logger.Info("Starting HyperEVM Yield Optimizer Monitor Service")
    
    // Start price oracle
    go priceOracle.Start(ctx)
    
    // Start monitoring service
    if err := monitorService.Start(ctx); err != nil {
        logger.Fatal("Failed to start monitor service:", err)
    }

    // Handle graceful shutdown
    sigChan := make(chan os.Signal, 1)
    signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)
    <-sigChan

    logger.Info("Shutting down monitor service...")
    
    // Give services time to cleanup
    shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), 30*time.Second)
    defer shutdownCancel()
    
    if err := monitorService.Shutdown(shutdownCtx); err != nil {
        logger.Error("Error during shutdown:", err)
    }
    
    logger.Info("Monitor service stopped")
}