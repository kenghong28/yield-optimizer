# HyperEVM Yield Optimizer Implementation Plan (Go + Bun)

## Project Overview

Building a concentrated liquidity yield optimizer on HyperEVM using:
- **Go**: Core services (monitoring, rebalancing, event processing)
- **Bun**: API services (GraphQL, WebSocket, admin dashboard)
- **Solidity**: Smart contracts for vault and strategy management

## Phase 1: Project Setup and Foundation

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
```

### Step 2: Set Up Go Services

```bash
# Monitor Service
cd services/monitor
go mod init github.com/yourusername/hyperevm-yield-optimizer/services/monitor

# Create main.go
cat > main.go << 'EOF'
package main

import (
    "context"
    "log"
    "os"
    "os/signal"
    "syscall"
    
    "github.com/ethereum/go-ethereum/ethclient"
)

func main() {
    ctx, cancel := context.WithCancel(context.Background())
    defer cancel()
    
    // Connect to HyperEVM
    client, err := ethclient.Dial("https://rpc.hyperliquid.xyz/evm")
    if err != nil {
        log.Fatal("Failed to connect to HyperEVM:", err)
    }
    defer client.Close()
    
    log.Println("Connected to HyperEVM")
    
    // Handle graceful shutdown
    sigChan := make(chan os.Signal, 1)
    signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)
    <-sigChan
    
    log.Println("Shutting down...")
}
EOF

# Install dependencies
go get github.com/ethereum/go-ethereum
go get github.com/joho/godotenv
go get github.com/sirupsen/logrus
```

### Step 3: Set Up Bun API Service

```bash
cd services/api
bun init -y

# Install dependencies
bun add elysia @elysiajs/cors @elysiajs/swagger
bun add @pothos/core @pothos/plugin-errors graphql graphql-yoga
bun add ethers@^6 viem
bun add -d @types/bun typescript

# Create index.ts
cat > src/index.ts << 'EOF'
import { Elysia } from "elysia";
import { cors } from "@elysiajs/cors";
import { swagger } from "@elysiajs/swagger";

const app = new Elysia()
  .use(cors())
  .use(swagger())
  .get("/", () => ({ message: "HyperEVM Yield Optimizer API" }))
  .get("/health", () => ({ status: "healthy", timestamp: new Date() }))
  .listen(3000);

console.log(`🚀 API running at ${app.server?.hostname}:${app.server?.port}`);
EOF
```

### Step 4: Smart Contract Setup

```bash
cd contracts

# Initialize Hardhat project
npm init -y
npm install --save-dev hardhat @nomicfoundation/hardhat-toolbox
npm install @openzeppelin/contracts

# Create hardhat config
cat > hardhat.config.js << 'EOF'
require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();

module.exports = {
  solidity: {
    version: "0.8.24",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  },
  networks: {
    hyperevm: {
      url: "https://rpc.hyperliquid.xyz/evm",
      chainId: 999,
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : []
    },
    hardhat: {
      forking: {
        url: "https://rpc.hyperliquid.xyz/evm"
      }
    }
  }
};
EOF
```

### Step 5: Docker Setup

```yaml
# docker-compose.yml
version: '3.9'

services:
  # Go Services
  monitor:
    build: ./services/monitor
    environment:
      - RPC_URL=https://rpc.hyperliquid.xyz/evm
      - REDIS_URL=redis://redis:6379
    depends_on:
      - redis
      - postgres
    restart: unless-stopped

  rebalancer:
    build: ./services/rebalancer
    environment:
      - RPC_URL=https://rpc.hyperliquid.xyz/evm
      - PRIVATE_KEY=${REBALANCER_PRIVATE_KEY}
    depends_on:
      - redis
      - postgres

  # Bun Services
  api:
    build: ./services/api
    ports:
      - "3000:3000"
    environment:
      - DATABASE_URL=postgresql://postgres:password@postgres:5432/yield_optimizer
      - REDIS_URL=redis://redis:6379
    depends_on:
      - postgres
      - redis

  websocket:
    build: ./services/websocket
    ports:
      - "3001:3001"
    environment:
      - REDIS_URL=redis://redis:6379

  # Infrastructure
  postgres:
    image: timescale/timescaledb:latest-pg16
    environment:
      - POSTGRES_PASSWORD=password
      - POSTGRES_DB=yield_optimizer
    volumes:
      - postgres_data:/var/lib/postgresql/data
    ports:
      - "5432:5432"

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"

volumes:
  postgres_data:
```

## Phase 2: Core Implementation

### Monitor Service (Go)

```go
// services/monitor/internal/monitor/service.go
package monitor

import (
    "context"
    "math/big"
    "sync"
    "time"
    
    "github.com/ethereum/go-ethereum"
    "github.com/ethereum/go-ethereum/common"
    "github.com/ethereum/go-ethereum/core/types"
    "github.com/ethereum/go-ethereum/ethclient"
)

type Service struct {
    client      *ethclient.Client
    pools       map[common.Address]*Pool
    positions   map[string]*Position
    mu          sync.RWMutex
    rebalanceCh chan *RebalanceRequest
}

type Pool struct {
    Address     common.Address
    Token0      common.Address
    Token1      common.Address
    Fee         *big.Int
    TickSpacing int
}

type Position struct {
    TokenId     *big.Int
    Owner       common.Address
    Pool        common.Address
    TickLower   int32
    TickUpper   int32
    Liquidity   *big.Int
    InRange     bool
    LastChecked time.Time
}

func (s *Service) Start(ctx context.Context) error {
    // Subscribe to new blocks
    headers := make(chan *types.Header)
    sub, err := s.client.SubscribeNewHead(ctx, headers)
    if err != nil {
        return err
    }
    
    go func() {
        for {
            select {
            case err := <-sub.Err():
                log.Error("Subscription error:", err)
                return
            case header := <-headers:
                s.processBlock(ctx, header)
            case <-ctx.Done():
                return
            }
        }
    }()
    
    return nil
}

func (s *Service) processBlock(ctx context.Context, header *types.Header) {
    // Check all positions
    s.mu.RLock()
    positions := make([]*Position, 0, len(s.positions))
    for _, pos := range s.positions {
        positions = append(positions, pos)
    }
    s.mu.RUnlock()
    
    // Process positions concurrently
    var wg sync.WaitGroup
    semaphore := make(chan struct{}, 10) // Limit concurrent checks
    
    for _, pos := range positions {
        wg.Add(1)
        semaphore <- struct{}{}
        
        go func(p *Position) {
            defer wg.Done()
            defer func() { <-semaphore }()
            
            if err := s.checkPosition(ctx, p); err != nil {
                log.WithError(err).Error("Failed to check position")
            }
        }(pos)
    }
    
    wg.Wait()
}
```

### API Service (Bun)

```typescript
// services/api/src/schema.ts
import SchemaBuilder from "@pothos/core";
import ErrorsPlugin from "@pothos/plugin-errors";

const builder = new SchemaBuilder({
  plugins: [ErrorsPlugin],
});

// Define types
builder.objectType('Vault', {
  fields: (t) => ({
    id: t.exposeID('id'),
    address: t.exposeString('address'),
    totalValueLocked: t.exposeString('totalValueLocked'),
    currentAPY: t.exposeFloat('currentAPY'),
    strategy: t.field({
      type: 'Strategy',
      resolve: (vault) => vault.strategy,
    }),
    positions: t.field({
      type: ['Position'],
      resolve: (vault) => vault.positions,
    }),
  }),
});

builder.objectType('Position', {
  fields: (t) => ({
    tokenId: t.exposeString('tokenId'),
    pool: t.exposeString('pool'),
    tickLower: t.exposeInt('tickLower'),
    tickUpper: t.exposeInt('tickUpper'),
    liquidity: t.exposeString('liquidity'),
    inRange: t.exposeBoolean('inRange'),
    feesEarned: t.exposeString('feesEarned'),
  }),
});

// Queries
builder.queryType({
  fields: (t) => ({
    vault: t.field({
      type: 'Vault',
      args: {
        address: t.arg.string({ required: true }),
      },
      resolve: async (_, { address }, ctx) => {
        return ctx.vaultService.getVault(address);
      },
    }),
    userVaults: t.field({
      type: ['Vault'],
      args: {
        userAddress: t.arg.string({ required: true }),
      },
      resolve: async (_, { userAddress }, ctx) => {
        return ctx.vaultService.getUserVaults(userAddress);
      },
    }),
  }),
});

// Mutations
builder.mutationType({
  fields: (t) => ({
    deposit: t.field({
      type: 'DepositResult',
      args: {
        vaultAddress: t.arg.string({ required: true }),
        amount0: t.arg.string({ required: true }),
        amount1: t.arg.string({ required: true }),
      },
      resolve: async (_, args, ctx) => {
        return ctx.vaultService.deposit(args);
      },
    }),
  }),
});

export const schema = builder.toSchema();
```

### Smart Contracts

```solidity
// contracts/src/YieldOptimizerVault.sol
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

contract YieldOptimizerVault is ERC20, ReentrancyGuard, Ownable, Pausable {
    struct Position {
        uint256 tokenId;
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
    }
    
    address public immutable token0;
    address public immutable token1;
    address public strategy;
    address public keeper;
    
    Position public currentPosition;
    uint256 public lastRebalance;
    uint256 public performanceFee = 1000; // 10%
    
    event Deposit(address indexed user, uint256 shares, uint256 amount0, uint256 amount1);
    event Withdraw(address indexed user, uint256 shares, uint256 amount0, uint256 amount1);
    event Rebalance(uint256 oldTokenId, uint256 newTokenId, int24 tickLower, int24 tickUpper);
    
    constructor(
        address _token0,
        address _token1,
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) {
        token0 = _token0;
        token1 = _token1;
    }
    
    function deposit(
        uint256 amount0Desired,
        uint256 amount1Desired
    ) external nonReentrant whenNotPaused returns (uint256 shares) {
        // Implementation
    }
    
    function withdraw(uint256 shares) external nonReentrant returns (uint256 amount0, uint256 amount1) {
        // Implementation
    }
    
    function rebalance() external onlyKeeper {
        require(block.timestamp >= lastRebalance + 1 hours, "Too soon");
        // Implementation
    }
}
```

## Phase 3: Development Workflow

### Local Development

```bash
# Terminal 1: Start infrastructure
docker-compose up postgres redis

# Terminal 2: Start Go monitor service
cd services/monitor
go run .

# Terminal 3: Start Bun API
cd services/api
bun run dev

# Terminal 4: Deploy contracts
cd contracts
npx hardhat run scripts/deploy.js --network hyperevm
```

### Testing Strategy

```bash
# Go tests
cd services/monitor
go test ./... -v

# Bun tests
cd services/api
bun test

# Smart contract tests
cd contracts
npx hardhat test
```

## Next Steps

1. **Implement Concentrated Liquidity Logic**
   - Deploy Uniswap V3 contracts or custom implementation
   - Build position management functions
   - Create rebalancing algorithms

2. **Build Monitoring System**
   - Real-time position tracking
   - Volatility calculation
   - Range optimization

3. **Develop Rebalancing Strategies**
   - Fixed range strategy
   - Volatility-based strategy
   - Mean reversion strategy

4. **Create User Interface**
   - Vault deposit/withdraw
   - Performance dashboard
   - Strategy configuration

5. **Add Security Features**
   - MEV protection
   - Slippage controls
   - Emergency pause