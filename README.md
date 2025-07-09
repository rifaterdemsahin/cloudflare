# Cloudflare Tunnel for Proxmox Home Lab

This repository contains guides and configurations for setting up Cloudflare Tunnel to securely expose services running in a Proxmox home lab environment.

## 📄 Documents

1.  **[Architectural Overview (`formulas/1_architecture.md`)](formulas/1_architecture.md)**
    *   Provides a visual diagram and explanation of how Cloudflare Tunnel integrates with a Proxmox setup.

2.  **[Proxmox Setup Guide (`formulas/2_proxmoxsetup.md`)](formulas/2_proxmoxsetup.md)**
    *   Step-by-step instructions for installing and configuring `cloudflared` within a VM or LXC container on Proxmox to expose your local services.

## 🚀 Quick Start

1.  Review the [Architectural Overview](formulas/1_architecture.md) to understand the setup.
2.  Follow the [Proxmox Setup Guide](formulas/2_proxmoxsetup.md) to implement Cloudflare Tunnel.

---

*This setup allows you to securely access your home lab services from anywhere without opening inbound ports on your router, leveraging Cloudflare's network for protection and accessibility.*
