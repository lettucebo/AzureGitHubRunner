[繁體中文](README_zh-tw.md) | **English**

---

# VM Self-Hosted Runner Documentation

Deploy Linux VMs on Azure using Terraform and automatically configure multiple GitHub Self-hosted Runners.

## 📚 Documentation Index

| Document | Description |
|----------|-------------|
| [QUICKSTART.md](QUICKSTART.md) | Quick start guide |
| [SSH_QUICKSTART.md](SSH_QUICKSTART.md) | SSH quick setup |
| [SSH_KEY_GUIDE.md](SSH_KEY_GUIDE.md) | Complete SSH key guide |
| [SSH_SIMPLE_GUIDE.md](SSH_SIMPLE_GUIDE.md) | Simple SSH guide |
| [SPOT_VM_GUIDE.md](SPOT_VM_GUIDE.md) | Spot VM cost optimization guide |

## 🏗️ Architecture

```
┌─────────────────────────────────────────┐
│           Azure Linux VM                 │
│     (Standard_D4s_v5 / Spot VM)         │
├─────────────────────────────────────────┤
│  ┌─────────┐ ┌─────────┐ ┌─────────┐   │
│  │ Runner 1│ │ Runner 2│ │ Runner N│   │
│  └─────────┘ └─────────┘ └─────────┘   │
│                                          │
│  • .NET SDK 8.0                         │
│  • Node.js (20, 22, 24)                 │
│  • Docker                                │
│  • systemd service management           │
└─────────────────────────────────────────┘
```

## 💰 Cost Estimation

| VM Type | Specs | Regular Price | Spot Price | Savings |
|---------|-------|--------------|-----------|---------|
| Standard_D4s_v5 | 4C/16G | ~$150/month | ~$29/month | 80% |
| Standard_D8s_v5 | 8C/32G | ~$300/month | ~$58/month | 80% |

## 🔗 Source Code

Source code is located at [src/vm-runner/](../../src/vm-runner/)
