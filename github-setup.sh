#!/bin/bash

echo "=== GitHub Setup for Yield Optimizer ==="
echo ""

# Check if gh is installed
if ! command -v gh &> /dev/null; then
    echo "GitHub CLI (gh) is not installed."
    echo "Install it with: brew install gh"
    exit 1
fi

# Check if already authenticated
if gh auth status &> /dev/null; then
    echo "✓ Already authenticated with GitHub"
    gh auth status
else
    echo "Need to authenticate with GitHub"
    echo "Run: gh auth login"
    echo ""
    echo "Choose:"
    echo "- GitHub.com"
    echo "- HTTPS"
    echo "- Login with a web browser (recommended)"
    echo ""
    gh auth login
fi

echo ""
echo "=== Setting up Git repository ==="

# Initialize git if needed
if [ ! -d .git ]; then
    echo "Initializing git repository..."
    git init
    git branch -M main
fi

# Configure git
echo "Configuring git..."
git config user.name "$(gh api user -q .name)"
git config user.email "$(gh api user -q .email)"

echo ""
echo "Git user configured as:"
git config user.name
git config user.email

echo ""
echo "=== Creating GitHub repository ==="

# Check if remote exists
if git remote get-url origin &> /dev/null; then
    echo "✓ Remote 'origin' already exists"
    git remote -v
else
    echo "Creating new GitHub repository..."
    
    # Create repo on GitHub
    gh repo create yield-optimizer \
        --public \
        --description "HyperEVM Yield Optimizer - Automated yield farming optimization" \
        --clone=false \
        --confirm || echo "Repository might already exist"
    
    # Add remote
    echo "Adding remote origin..."
    git remote add origin "https://github.com/$(gh api user -q .login)/yield-optimizer.git"
fi

echo ""
echo "=== Preparing first commit ==="

# Add all files
echo "Adding all files..."
git add .

# Create .gitignore if it doesn't exist
if [ ! -f .gitignore ]; then
    cat > .gitignore << 'EOF'
# Binaries
*.exe
*.dll
*.so
*.dylib
/services/monitor/monitor

# Test binary
*.test

# Output of go coverage
*.out
coverage.html

# Dependency directories
vendor/
node_modules/

# Go workspace
go.work

# Environment files
.env
.env.local
.env.*.local

# IDE
.vscode/
.idea/
*.swp
*.swo
*~

# OS
.DS_Store
Thumbs.db

# Kubernetes
kubeconfig
*.kubeconfig

# Helm
*.tgz
charts/*.tgz

# Docker
.dockerignore

# Monitoring
prometheus-data/
grafana-data/
alertmanager-data/

# Temporary files
*.tmp
*.temp
/tmp

# Logs
*.log
logs/

# Build artifacts
build/
dist/
EOF
    git add .gitignore
fi

echo ""
echo "Files to be committed:"
git status --short

echo ""
echo "=== Ready to push ==="
echo ""
echo "To complete the setup, run these commands:"
echo ""
echo "1. Commit your changes:"
echo "   git commit -m \"Initial commit: Kubernetes deployment with CI/CD\""
echo ""
echo "2. Push to GitHub:"
echo "   git push -u origin main"
echo ""
echo "3. View your repository:"
echo "   gh repo view --web"
echo ""
echo "Optional: Set repository topics:"
echo "   gh repo edit --add-topic kubernetes,golang,yield-optimizer,defi"