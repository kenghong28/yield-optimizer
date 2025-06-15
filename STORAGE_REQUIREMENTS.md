# Storage Requirements for Yield Optimizer

## 📊 Summary

Since you're using **Supabase as your external PostgreSQL database**, your Kubernetes storage requirements are minimal and optional.

## ✅ What You Need

### 1. **NO PostgreSQL PVC Required**
- ❌ **PostgreSQL PersistentVolumeClaim**: Not needed
- ✅ **External Supabase**: Handles all database storage
- ✅ **Managed Service**: Automatic backups, scaling, HA

### 2. **Optional Redis Cache PVC**
```yaml
# Development (recommended)
redis:
  persistence:
    enabled: false  # Uses EmptyDir - faster, no persistence

# Production (optional but recommended)  
redis:
  persistence:
    enabled: true   # Uses PVC - persists cache across restarts
    size: 5Gi
```

### 3. **Application Temporary Storage (Always Included)**
```yaml
# Automatically created EmptyDir volumes
volumes:
  - name: tmp
    emptyDir: {}
```

## 🎯 Recommendations by Environment

### Development Environment
```bash
# Minimal storage - no persistence
Storage Required: ~0 GB (EmptyDir only)
Cost: $0
PVCs: None
```

### Production Environment
```bash
# Optional Redis persistence for performance
Storage Required: ~5 GB (Redis cache only)
Cost: Minimal (cloud storage rates)
PVCs: 1 (Redis only)
```

## 🚀 Deployment Commands

### Deploy with NO persistence (fastest)
```bash
./deploy.sh dev install
# Uses EmptyDir for Redis, no PVCs created
```

### Deploy with Redis persistence only
```bash
./deploy.sh prod install  
# Creates 1 PVC for Redis cache (5GB)
```

## 💡 Cost Analysis

| Component | Development | Production | External |
|-----------|-------------|------------|----------|
| PostgreSQL | $0 | $0 | Supabase billing |
| Redis Cache | $0 | ~$2-5/month | - |
| App Storage | $0 | $0 | - |
| **Total K8s Storage** | **$0** | **~$2-5/month** | **Minimal** |

## 🔧 Configuration Examples

### Minimal Setup (No Persistence)
```yaml
redis:
  enabled: true
  persistence:
    enabled: false

postgresql:
  enabled: false  # Using external Supabase
```

### Production Setup (Redis Persistence Only)
```yaml
redis:
  enabled: true
  persistence:
    enabled: true
    size: 5Gi
    storageClass: "fast-ssd"

postgresql:
  enabled: false  # Using external Supabase
```

### Disable Everything (Supabase + External Redis)
```yaml
redis:
  enabled: false  # Use external Redis service

postgresql:
  enabled: false  # Using external Supabase
```

## ✨ Benefits of This Approach

1. **Cost Effective**: Minimal Kubernetes storage costs
2. **Simplified Management**: No database backup/restore in K8s
3. **High Availability**: Supabase handles HA automatically
4. **Scalability**: Database scales independently
5. **Security**: Managed database security updates
6. **Performance**: Dedicated database resources

## 🎯 Answer to Your Question

> **Do we need PersistentVolumeClaim if we are using Supabase for postgres?**

**NO** - You do NOT need PostgreSQL PVC with Supabase! 

**Only optional Redis PVC for caching performance.**

Your storage footprint: **Nearly zero** ✨