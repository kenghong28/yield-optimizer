# HyperEVM Yield Optimizer

An automated yield optimizer for concentrated liquidity positions on HyperEVM. The system monitors liquidity positions and automatically rebalances them when they go out of range to maximize yield generation.

## Architecture

- **Go Services**: Core monitoring and rebalancing logic
- **Bun Services**: API, WebSocket, and admin dashboard
- **Smart Contracts**: Vault and strategy management on HyperEVM

## Features

- 🔄 Automated position rebalancing
- 📊 Real-time position monitoring
- 💹 Multiple rebalancing strategies
- 🛡️ MEV protection
- 📈 Performance analytics
- 🔐 Secure vault management

## Tech Stack

- **Backend**: Go (core services), Bun (API services)
- **Blockchain**: Solidity, Ethers.js
- **Database**: PostgreSQL with TimescaleDB
- **Cache**: Redis
- **Infrastructure**: Docker, Docker Compose

## Getting Started

### Prerequisites

- Go 1.21+
- Bun 1.0+
- Node.js 18+ (for Hardhat)
- Docker & Docker Compose
- PostgreSQL 16+
- Redis 7+

### Installation

1. Clone the repository:
```bash
git clone https://github.com/yourusername/hyperevm-yield-optimizer.git
cd hyperevm-yield-optimizer
```

2. Install dependencies:
```bash
# Go services
cd services/monitor && go mod download
cd ../rebalancer && go mod download

# Bun services
cd ../api && bun install
cd ../websocket && bun install

# Smart contracts
cd ../../contracts && npm install
```

3. Set up environment variables:
```bash
cp .env.example .env
# Edit .env with your configuration
```

4. Start infrastructure:
```bash
docker-compose up -d postgres redis
```

5. Deploy contracts:
```bash
cd contracts
npx hardhat run scripts/deploy.js --network hyperevm
```

6. Start services:
```bash
# In separate terminals
cd services/monitor && go run .
cd services/api && bun run dev
```

## Project Structure

```
hyperevm-yield-optimizer/
├── services/
│   ├── monitor/        # Go: Position monitoring
│   ├── rebalancer/     # Go: Rebalancing execution
│   ├── gateway/        # Go: API gateway
│   ├── api/           # Bun: GraphQL API
│   ├── websocket/     # Bun: Real-time updates
│   └── admin/         # Bun: Admin dashboard
├── packages/
│   ├── shared-types/  # TypeScript type definitions
│   ├── config/        # Shared configuration
│   └── utils/         # Shared utilities
├── contracts/
│   ├── src/           # Solidity contracts
│   ├── test/          # Contract tests
│   └── scripts/       # Deployment scripts
└── docs/              # Documentation
```

## Development

### Running Tests

```bash
# Go tests
cd services/monitor && go test ./...

# Bun tests
cd services/api && bun test

# Contract tests
cd contracts && npx hardhat test
```

### Building for Production

```bash
# Build all services
docker-compose build

# Or build individually
cd services/monitor && go build -o bin/monitor
cd services/api && bun build src/index.ts --target=bun
```

## Contributing

Please read [CONTRIBUTING.md](CONTRIBUTING.md) for details on our code of conduct and the process for submitting pull requests.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.