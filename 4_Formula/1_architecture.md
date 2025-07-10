# 🏗️ Cloudflare Tunnel on Proxmox: Architectural Overview

This document outlines the architecture of using Cloudflare Tunnel (`cloudflared`) to expose services hosted within a Proxmox Virtual Environment.

## Diagram

```mermaid
graph TD
    A[🌐 User / Internet] --> B{Cloudflare Network};
    B --> C[🚀 Cloudflare Tunnel];
    C --> D[💻 cloudflared Daemon];

    subgraph PVE[Proxmox VE Host]
        direction LR
        D -.-> E[VM / LXC Container];
        subgraph E_ENV [Linux Environment in VM/LXC]
            D
        end
        E --> F[Service 1 (e.g., Web App in VM/LXC)];
        E --> G[Service 2 (e.g., Database in VM/LXC)];
        E --> H[Service N (on Proxmox Host or another VM/LXC)];
    end

    style PVE fill:#f9f,stroke:#333,stroke-width:2px,color:#000
    style E_ENV fill:#ccf,stroke:#333,stroke-width:2px,color:#000
    style A fill:#add,stroke:#333,stroke-width:2px
    style B fill:#fd7e14,stroke:#333,stroke-width:2px,color:#fff
    style C fill:#fd7e14,stroke:#333,stroke-width:2px,color:#fff
    style D fill:#0dcaf0,stroke:#333,stroke-width:2px,color:#000
    style F fill:#ffc107,stroke:#333,stroke-width:2px,color:#000
    style G fill:#ffc107,stroke:#333,stroke-width:2px,color:#000
    style H fill:#ffc107,stroke:#333,stroke-width:2px,color:#000

    classDef default fill:#fff,stroke:#333,stroke-width:2px;
```

## 🔑 Key Components:

1.  **🌐 User / Internet:** Represents end-users accessing your services.
2.  **☁️ Cloudflare Network:** Cloudflare's global edge network. All traffic to your exposed services passes through here. It provides DDoS protection, caching (if configured), and other Cloudflare features.
3.  **🚀 Cloudflare Tunnel:** An outbound-only connection established by the `cloudflared` daemon from your Proxmox environment to the Cloudflare network. No inbound ports need to be opened on your router/firewall.
4.  **💻 `cloudflared` Daemon:** A lightweight piece of software running within a dedicated Virtual Machine (VM) or LXC container on your Proxmox host.
    *   It establishes and maintains the secure tunnel to Cloudflare.
    *   It proxies incoming requests from the tunnel to your local services based on the ingress rules defined in its configuration file (`config.yml`).
5.  **🏢 Proxmox VE Host:** Your physical server running Proxmox Virtual Environment.
6.  **🐧 VM / LXC Container (for `cloudflared`):** A Linux environment (e.g., Debian, Ubuntu) hosted on Proxmox. This is where the `cloudflared` daemon is installed and runs.
    *   **Isolation:** Running `cloudflared` in a dedicated VM/LXC provides isolation from other services and the Proxmox host itself.
7.  **🛠️ Local Services (Service 1, Service 2, etc.):** These are the applications you want to expose. They can be:
    *   Running within other VMs or LXC containers on the same Proxmox host.
    *   Running directly on the Proxmox host itself (less common for web services, but possible).
    *   Running on other machines on your local network that the `cloudflared` VM/LXC can reach.

## 🔄 Traffic Flow:

1.  A user attempts to access `your-service.yourdomain.com`.
2.  DNS resolves `your-service.yourdomain.com` to Cloudflare's IPs.
3.  The request hits the Cloudflare Network.
4.  Cloudflare routes the request through the established Tunnel to the `cloudflared` daemon running in your Proxmox VM/LXC.
5.  `cloudflared` consults its `config.yml` and, based on the hostname (`your-service.yourdomain.com`), proxies the request to the appropriate internal IP address and port of your local service (e.g., `http://192.168.1.X:8080`).
6.  The local service processes the request and sends the response back through `cloudflared`, the tunnel, Cloudflare's network, and finally to the user.

## ✅ Advantages:

*   **Security:** No need to open inbound ports on your home router/firewall. `cloudflared` makes outbound connections only.
*   **Ease of Use:** Simplifies exposing services compared to traditional port forwarding and dynamic DNS.
*   **Cloudflare Features:** Leverage Cloudflare's DDoS protection, WAF (Web Application Firewall, on paid plans), caching, and SSL/TLS termination.
*   **Stable Hostnames:** Provides stable, publicly accessible hostnames for your dynamic IP home lab.
*   **Access Control:** Can be integrated with Cloudflare Access to add authentication and authorization to your services.
```
