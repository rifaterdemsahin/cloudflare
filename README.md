# Cloudflare Tunnel for Proxmox Home Lab

This repository provides comprehensive guidance, configurations, and automation scripts for setting up Cloudflare Tunnel to securely expose services running in a Proxmox home lab environment. This allows you to access your home lab services from anywhere without opening inbound ports on your router, leveraging Cloudflare's network for protection and accessibility.

## 🏗️ Architectural Overview

The following diagram illustrates how Cloudflare Tunnel integrates with a Proxmox setup:

```mermaid
graph TD
    A[🌐 User / Internet] --> B[Cloudflare Network];
    B --> C[🚀 Cloudflare Tunnel];
    C --> D[💻 cloudflared Daemon];

    subgraph PVE[Proxmox VE Host]
        direction LR
        D --> E[VM / LXC Container];
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

### 🔑 Key Components:

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

### 🔄 Traffic Flow:

1.  A user attempts to access `your-service.yourdomain.com`.
2.  DNS resolves `your-service.yourdomain.com` to Cloudflare's IPs.
3.  The request hits the Cloudflare Network.
4.  Cloudflare routes the request through the established Tunnel to the `cloudflared` daemon running in your Proxmox VM/LXC.
5.  `cloudflared` consults its `config.yml` and, based on the hostname (`your-service.yourdomain.com`), proxies the request to the appropriate internal IP address and port of your local service (e.g., `http://192.168.1.X:8080`).
6.  The local service processes the request and sends the response back through `cloudflared`, the tunnel, Cloudflare's network, and finally to the user.

### ✅ Advantages:

*   **Security:** No need to open inbound ports on your home router/firewall. `cloudflared` makes outbound connections only.
*   **Ease of Use:** Simplifies exposing services compared to traditional port forwarding and dynamic DNS.
*   **Cloudflare Features:** Leverage Cloudflare's DDoS protection, WAF (Web Application Firewall, on paid plans), caching, and SSL/TLS termination.
*   **Stable Hostnames:** Provides stable, publicly accessible hostnames for your dynamic IP home lab.
*   **Access Control:** Can be integrated with Cloudflare Access to add authentication and authorization to your services.

## 📄 Related Documents & Depths

While this README aims to be comprehensive, the `formulas/` directory contains the original detailed guides:

*   **[Original Architectural Overview (`formulas/1_architecture.md`)](formulas/1_architecture.md)**
*   **[Original Proxmox Setup Guide (`formulas/2_proxmoxsetup.md`)](formulas/2_proxmoxsetup.md)**
*   **[GoDaddy/Subdomain Specific Guide (`formulas/3-subdomain.md`)](formulas/3-subdomain.md)**
*   **[Combined GoDaddy & Proxmox Guide (`formulas/cloudflare_godaddy_proxmox.md`)](formulas/cloudflare_godaddy_proxmox.md)**

The `real/`, `semblance/`, `symbols/`, and `ui/` directories contain product requirement definitions and script details, which are summarized in relevant sections of this README.

---

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a pull request or open an issue for any bugs, improvements, or suggestions.

## 📜 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details (assuming a LICENSE file will be added).

## 🎯 Prerequisites

Before you begin, ensure you have the following:

1.  **☁️ Cloudflare Account:** An active Cloudflare account.
2.  **🌐 Domain Managed by Cloudflare:** A domain name added to your Cloudflare account, with its DNS managed by Cloudflare. (Alternatively, for subdomain-only setup, see the GoDaddy/Subdomain section).
3.  **🖥️ Proxmox VE Host:** A running Proxmox VE host.
4.  **🐧 Linux VM or LXC Container:** A Linux VM or LXC container (e.g., Debian, Ubuntu Server) running on Proxmox. This is where `cloudflared` will be installed. It should have internet access.

## 🛠️ Setup Instructions

These steps guide you through setting up Cloudflare Tunnel. They are performed primarily **inside your chosen Linux VM or LXC container** on Proxmox, unless otherwise specified.

### 1. Prepare Your Environment (Optional but Recommended)

This repository includes scripts to automate many steps. To use them:
1.  Clone this repository to your Linux VM/LXC.
2.  Navigate to the `symbols` directory.
3.  Copy `.env.example` to `.env`: `cp .env.example .env`
4.  Edit `.env` and fill in your specific details (Cloudflare API token, account ID, domain names, Proxmox IP, etc.). See `symbols/.env.example` for detailed instructions on each variable.
    *   **Important for API Token:** Create a Cloudflare API Token with permissions: Zone:Zone Settings:Read, Zone:Zone:Read, Zone:DNS:Edit, Account:Cloudflare Tunnel:Edit.

### 2. Install `cloudflared`

Install the `cloudflared` daemon on your Linux VM/LXC.

*   **Manual Method (Debian/Ubuntu):**
    ```bash
    # Add Cloudflare's GPG key
    sudo mkdir -p --mode=0755 /usr/share/keyrings
    curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | sudo tee /usr/share/keyrings/cloudflare-main.gpg > /dev/null
    # Add Cloudflare's apt repository
    echo 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared $(lsb_release -cs) main' | sudo tee /etc/apt/sources.list.d/cloudflared.list
    # Update package list and install cloudflared
    sudo apt update
    sudo apt install cloudflared
    ```
*   **Scripted Method:**
    Navigate to the `symbols` directory in the cloned repository and run:
    ```bash
    sudo bash install_cloudflared.sh
    ```

🔍 Verify installation:
```bash
cloudflared --version
```

### 3. Authenticate `cloudflared`

Log `cloudflared` into your Cloudflare account. This is crucial for creating and managing tunnels.

*   **Method 1: Browser Login (Interactive)**
    Run the following command. It will provide a URL to open in a browser on your main computer.
    ```bash
    cloudflared tunnel login
    ```
    Follow the prompts to log in and authorize the tunnel for your chosen domain. This downloads a `cert.pem` file (usually to `~/.cloudflared/` or `/root/.cloudflared/`).

*   **Method 2: API Token (Recommended for Automation)**
    If you've configured your `CF_API_TOKEN` and `ACCOUNT_ID` in the `.env` file, the scripts provided in this repository will attempt to use it. The `authenticate_cloudflared.sh` script primarily checks if these variables are set and provides guidance.
    ```bash
    # (In symbols/ directory)
    bash authenticate_cloudflared.sh
    ```
    Ensure `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` are exported or available to the `cloudflared` commands if not using the browser login.

### 4. Create a Cloudflare Tunnel

Create a tunnel to connect your services to Cloudflare.

*   **Manual Method:**
    Replace `<your-tunnel-name>` with a descriptive name (e.g., `proxmox-lab`).
    ```bash
    cloudflared tunnel create <your-tunnel-name>
    ```
    This will:
    *   Output a **Tunnel UUID** (e.g., `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`). **Note this UUID!**
    *   Create a credentials file (e.g., `<TUNNEL-UUID>.json`) in the `cloudflared` directory (e.g., `~/.cloudflared/` or `/root/.cloudflared/`). This file is vital.

*   **Scripted Method:**
    Ensure `TUNNEL_NAME` is set in your `.env` file.
    ```bash
    # (In symbols/ directory)
    bash create_cf_tunnel.sh
    ```
    The script will output the Tunnel Name, Tunnel ID, and the path to the credentials file. It will also attempt to save the `TUNNEL_ID` and `CREDENTIALS_FILE_PATH` to your `.env` file.

### 5. Configure DNS Routing

You need to create a CNAME DNS record in Cloudflare to point your desired hostname to your tunnel.

*   **Method 1: Via Cloudflare Dashboard (Manual)**
    1.  Go to your Cloudflare dashboard ➡️ Select your domain ➡️ DNS.
    2.  Click "Add record".
    3.  Type: `CNAME`
    4.  Name: Your desired subdomain (e.g., `proxmox`, `service1`).
    5.  Target: `<YOUR-TUNNEL-UUID>.cfargotunnel.com` (Use the Tunnel UUID from Step 4).
    6.  Proxy status: **Proxied** (Orange Cloud 🔶).
    7.  Save.

*   **Method 2: Using `cloudflared` command (Manual/Semi-Automated)**
    Replace `<your-tunnel-name-or-uuid>` and `your-subdomain.yourdomain.com`.
    ```bash
    cloudflared tunnel route dns <your-tunnel-name-or-uuid> your-subdomain.yourdomain.com
    ```
    Repeat for each hostname you want to route.

*   **Note on GoDaddy/External DNS for Subdomain:**
    If your main domain's DNS is managed by GoDaddy (or another provider) and you only want to delegate a subdomain (e.g., `proxmox.yourdomain.com`) to Cloudflare for the tunnel:
    1.  **At GoDaddy (or your DNS provider):** Create a CNAME record.
        *   Type: `CNAME`
        *   Name: `proxmox` (or your chosen subdomain)
        *   Value: `<YOUR-TUNNEL-UUID>.cfargotunnel.com`
        *   TTL: 1 hour (or as preferred)
    2.  **In Cloudflare:** Ensure your domain is added to Cloudflare (you can use a "Partial Setup / CNAME Setup" if Cloudflare prompted you to change nameservers, but you chose not to for the root domain). The tunnel routing will still work as long as the CNAME at GoDaddy points correctly to the Cloudflare tunnel URL. The `formulas/3-subdomain.md` and `formulas/cloudflare_godaddy_proxmox.md` files have more details on this approach.

### 6. Create `cloudflared` Configuration File (`config.yml`)

This file tells `cloudflared` how to route incoming requests from your public hostnames to your internal services.

*   **Manual Method:**
    Create a `config.yml` file. If running `cloudflared` as a service, this is typically `/etc/cloudflared/config.yml`. If running manually or for initial tests, it can be in `~/.cloudflared/config.yml` or `/root/.cloudflared/config.yml`.

    **Example `config.yml`:**
    ```yaml
    # Tunnel UUID from 'cloudflared tunnel create'
    tunnel: <YOUR-TUNNEL-UUID>
    # Path to the tunnel credentials file (e.g., /root/.cloudflared/YOUR-TUNNEL-UUID.json)
    credentials-file: /path/to/your/<TUNNEL-UUID>.json

    ingress:
      # Rule 1: Expose Proxmox VE web UI
      - hostname: proxmox.yourdomain.com
        service: https://<YOUR-PROXMOX-LOCAL-IP>:8006
        originRequest:
          noTLSVerify: true # Proxmox often uses a self-signed certificate

      # Rule 2: Expose another service (e.g., a web app in a VM)
      - hostname: webapp.yourdomain.com
        service: http://<IP-OF-VM-WITH-WEBAPP>:<PORT>

      # Catch-all rule: if no hostname matches, return 404 (recommended)
      - service: http_status:404
    ```
    *   Replace `<YOUR-TUNNEL-UUID>` with your actual Tunnel UUID.
    *   Update `credentials-file` to the absolute path of your `<TUNNEL-UUID>.json` file.
    *   Update `hostname` with your desired public hostnames.
    *   Update `service` with the local URL of your service (accessible from the VM/LXC running `cloudflared`).
    *   `noTLSVerify: true` is often needed for services like Proxmox that use self-signed SSL certificates locally.

*   **Scripted Method:**
    Ensure your `.env` file is populated with `TUNNEL_ID`, `CREDENTIALS_FILE_PATH` (usually set by `create_cf_tunnel.sh`), `SUBDOMAIN_NAME`, `DOMAIN_NAME`, `PROXMOX_IP`, and `PROXMOX_PORT`.
    ```bash
    # (In symbols/ directory)
    sudo bash generate_cf_config.sh
    ```
    This script will create `/etc/cloudflared/config.yml` by default, tailored for Proxmox access. Review the generated file.

### 7. Run `cloudflared`

*   **Method 1: Run in Foreground (for Testing)**
    Replace `<your-tunnel-name-or-uuid>` if your config isn't in a default location or named `config.yml`.
    ```bash
    # If config is at /etc/cloudflared/config.yml and tunnel ID is in it:
    cloudflared tunnel run <your-tunnel-name-or-uuid>
    # Or specify config explicitly:
    # cloudflared tunnel --config /path/to/your/config.yml run <your-tunnel-name-or-uuid>
    ```
    The tunnel name/UUID parameter might be optional if the `tunnel:` key in `config.yml` is correctly set to the UUID.
    Your services should become accessible via their public hostnames. Press `Ctrl+C` to stop.

*   **Method 2: Run as a Systemd Service (Recommended for Persistence)**
    This ensures `cloudflared` starts on boot and runs in the background.
    1.  **Install the service:**
        ```bash
        sudo cloudflared service install
        ```
        This usually copies your `config.yml` and credentials to `/etc/cloudflared/` if they are found in default user locations. **Verify paths in `/etc/cloudflared/config.yml`**, especially `credentials-file`, ensuring it points to `/etc/cloudflared/<TUNNEL-UUID>.json`. You might need to manually copy the credentials file and `cert.pem` to `/etc/cloudflared/` and adjust permissions (e.g., `sudo chown -R cloudflared:cloudflared /etc/cloudflared`, `sudo chmod 600 /etc/cloudflared/*.json`).

    2.  **Enable and start the service:**
        ```bash
        sudo systemctl enable cloudflared
        sudo systemctl start cloudflared
        ```

    3.  **Check status:**
        ```bash
        sudo systemctl status cloudflared
        journalctl -u cloudflared -f # To view live logs
        ```

*   **Scripted Service Management:**
    The `manage_cf_service.sh` script can help. Ensure `TUNNEL_NAME` and `CLOUDFLARED_CONFIG_PATH` (if not default) are in `.env`.
    ```bash
    # (In symbols/ directory)
    # To run in foreground for testing (uses TUNNEL_NAME from .env):
    sudo bash manage_cf_service.sh run

    # To install, start, stop, or check status of the systemd service:
    sudo bash manage_cf_service.sh install
    sudo bash manage_cf_service.sh start
    sudo bash manage_cf_service.sh status
    sudo bash manage_cf_service.sh stop
    ```

### 8. Configure Proxmox Firewall (Optional but Recommended Security Step)

If you are exposing your Proxmox VE web UI, it's a good security practice to configure its proxy (`pveproxy`) to only listen on localhost. The Cloudflare tunnel will then be the sole entry point.
**Perform this step on the Proxmox VE host itself, not inside the `cloudflared` VM/LXC.**

*   **Manual Method:**
    1.  Edit `/etc/default/pveproxy`:
        ```bash
        sudo nano /etc/default/pveproxy
        ```
    2.  Add or modify the `ALLOW_FROM` line:
        ```
        ALLOW_FROM="127.0.0.1,::1"
        ```
    3.  Save the file and restart the `pveproxy` service:
        ```bash
        sudo systemctl restart pveproxy
        ```

*   **Scripted Method (run on Proxmox VE host):**
    Copy `symbols/configure_proxmox_firewall.sh` to your Proxmox VE host and run it:
    ```bash
    sudo bash configure_proxmox_firewall.sh
    ```

## 🤖 Using the Automation Scripts (`symbols/`)

The `symbols/` directory contains Bash scripts to automate most of the setup process.

1.  **Prerequisites for Scripts:**
    *   Ensure `bash`, `curl`, `sudo`, and `systemd` (for service management) are available on your Linux VM/LXC.
    *   Clone this repository.
    *   Navigate to the `symbols/` directory.
    *   Copy `symbols/.env.example` to `symbols/.env`.
    *   **Crucially, populate `symbols/.env` with your Cloudflare API Token, Account ID, domain details, Proxmox IP, etc.**

2.  **Script Overview:**
    *   `install_cloudflared.sh`: Installs `cloudflared`.
    *   `authenticate_cloudflared.sh`: Guides on authentication (primarily checks for API token in `.env`).
    *   `create_cf_tunnel.sh`: Creates the tunnel and updates `.env` with `TUNNEL_ID` and `CREDENTIALS_FILE_PATH`.
    *   `generate_cf_config.sh`: Generates `/etc/cloudflared/config.yml` using values from `.env`.
    *   `manage_cf_service.sh {run|install|start|stop|status}`: Manages the `cloudflared` process/service.
    *   `configure_proxmox_firewall.sh`: (Run on Proxmox host) Configures `pveproxy`.

    Refer to `symbols/README.md` and comments within each script for more details. The `real/README.md` provides a task list that integrates these scripts.

## 🤔 Troubleshooting

*   **Logs are Key:**
    *   If running `cloudflared` directly: Check terminal output.
    *   If running as a service: `sudo journalctl -u cloudflared -f` or `sudo cloudflared service log`.
*   **Configuration (`config.yml`):**
    *   Verify `tunnel` UUID is correct.
    *   Ensure `credentials-file` path is absolute and correct, and the file exists.
    *   Validate YAML syntax.
    *   Check that `service` URLs are reachable from the `cloudflared` VM/LXC.
*   **DNS:**
    *   Confirm CNAME records in Cloudflare DNS point to `<YOUR-TUNNEL-UUID>.cfargotunnel.com` and are **Proxied (Orange Cloud)**.
    *   Allow time for DNS propagation if changes were recent.
*   **Firewalls:**
    *   **VM/LXC Firewall (e.g., `ufw`):** Ensure it allows outbound connections for `cloudflared`. `cloudflared` makes outbound connections only, so typically no inbound rules are needed on the VM/LXC for the tunnel itself.
    *   **Proxmox Host Firewall:** If your services are on other VMs/LXCs, ensure the Proxmox firewall allows traffic between the `cloudflared` VM/LXC and those service VMs/LXCs on the required ports.
    *   **Service-Level Firewalls:** Ensure the services themselves (e.g., web server on a VM) are listening on the expected IP and port and not blocked by their own internal firewall.
*   **Cloudflare Tunnel Dashboard:** Check your tunnel's status and connected `cloudflared` instances in the Cloudflare dashboard (Zero Trust -> Access -> Tunnels).
*   **Official Documentation:** The [Cloudflare Tunnel documentation](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/) is an excellent resource.

---
