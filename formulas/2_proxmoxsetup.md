# 🚇 Setting up Cloudflare Tunnel for Your Proxmox Home Lab 🏠

This guide outlines the steps to set up Cloudflare Tunnel (`cloudflared`) to securely expose services running on your Proxmox home lab (within VMs or LXC containers) to the internet via a Cloudflare proxy.

## 🎯 Prerequisites

1.  **☁️ Cloudflare Account:** You need an active Cloudflare account.
2.  **🌐 Domain in Cloudflare:** You must have a domain name added to your Cloudflare account, with its DNS managed by Cloudflare.
3.  **🖥️ Proxmox VE Host:** A running Proxmox VE host.
4.  **🐧 Linux VM or LXC Container:** You'll need a Linux Virtual Machine (VM) or an LXC container running on Proxmox. This is where `cloudflared` will be installed. A lightweight Linux distribution (like Debian or Ubuntu Server) is recommended.

## 🛠️ Installation and Configuration Steps

These steps should be performed **inside your chosen Linux VM or LXC container** on Proxmox.

### 1. 📦 Install `cloudflared`

Install the `cloudflared` daemon on your Linux VM/LXC.

*   **Recommended Method (using Cloudflare Package Repository):**
    *   Follow the instructions at the [Cloudflare Package Repository](https://pkg.cloudflare.com/) to add the repository and install `cloudflared` using your package manager.
    *   For Debian/Ubuntu based systems (common for Proxmox VMs/LXCs):
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

*   **Alternative (Manual Download - ensure you get the correct architecture for your VM/LXC):**
    *   amd64/x86-64: `wget https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64`
    *   arm64: `wget https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64`
    *   Make it executable: `chmod +x cloudflared-linux-amd64` (or `arm64`)
    *   Move it to your PATH: `sudo mv cloudflared-linux-amd64 /usr/local/bin/cloudflared`

🔍 Verify installation:
```bash
cloudflared --version
```

### 2. 🔑 Authenticate `cloudflared`

Log in `cloudflared` to your Cloudflare account. This command will generate a URL that you need to open in a browser on your main computer (not necessarily the Proxmox VM/LXC console if it's headless).
```bash
cloudflared login
```
Follow the prompts in the browser:
1.  Log in to your Cloudflare account.
2.  Select the domain you want to use for the tunnel.
3.  Authorize the tunnel.

Upon successful authentication, a `cert.pem` file will be downloaded to the default `cloudflared` directory (usually `~/.cloudflared/` or `/root/.cloudflared/` if running as root).

### 3.  Tunnel Creation

Create a tunnel. Replace `<your-tunnel-name>` with a descriptive name (e.g., `proxmox-lab-tunnel`).
```bash
cloudflared tunnel create <your-tunnel-name>
```
This command will:
*   Output a **Tunnel UUID**. 📝 **Note this UUID down!**
*   Create a credentials file (e.g., `<TUNNEL-UUID>.json`) in the `~/.cloudflared/` directory. This file contains the tunnel's secret.

### 4. ⚙️ Configure the Tunnel (Ingress Rules)

Create a configuration file named `config.yml` in the `~/.cloudflared/` directory.
If `~/.cloudflared` doesn't exist, create it: `mkdir ~/.cloudflared`

**Example `config.yml`:**

```yaml
# Tunnel UUID - paste the UUID from the 'cloudflared tunnel create' command
tunnel: <YOUR-TUNNEL-UUID>
# Path to the tunnel credentials file
credentials-file: /home/<your-user>/.cloudflared/<YOUR-TUNNEL-UUID>.json # Or /root/.cloudflared/... if running as root

# Ingress rules define how traffic is routed to your local services
ingress:
  # Rule 1: Expose a web service running on port 8080 in another VM/LXC or on the Proxmox host
  # (ensure your Proxmox VM/LXC running cloudflared can reach this IP and port)
  - hostname: service1.yourdomain.com # Your desired public hostname
    service: http://192.168.1.X:8080    # IP and port of the service within your Proxmox network

  # Rule 2: Expose a service running on the same VM/LXC as cloudflared
  - hostname: dashboard.yourdomain.com
    service: http://localhost:3000

  # Rule 3: Expose an SSH service (ensure the target machine allows SSH)
  # For SSH, you'll also need to configure Cloudflare Access for SSH or use the 'cloudflared access' client command.
  # - hostname: ssh.yourdomain.com
  #   service: ssh://192.168.1.Y:22

  # Add more services as needed

  # Catch-all rule: if no hostname matches, return 404 (recommended)
  - service: http_status:404
```

*   Replace `<YOUR-TUNNEL-UUID>` with your actual Tunnel UUID.
*   **Crucially**, update `credentials-file` to the correct path of your `<TUNNEL-UUID>.json` file.
    *   If you ran `cloudflared login` and `cloudflared tunnel create` as a regular user, it's likely `/home/<your-username>/.cloudflared/<YOUR-TUNNEL-UUID>.json`.
    *   If you ran them as `root`, it's `/root/.cloudflared/<YOUR-TUNNEL-UUID>.json`.
*   Under `ingress`:
    *   `hostname`: The public subdomain (e.g., `service1.yourdomain.com`).
    *   `service`: The local URL/address of the service *from the perspective of the VM/LXC running `cloudflared`*. This might be:
        *   `http://localhost:PORT` if the service is on the same VM/LXC.
        *   `http://<internal-ip-of-other-vm/lxc>:PORT` if the service is on another machine in your Proxmox network.
        *   `https://...` if the local service uses HTTPS (you might need to configure `noTLSVerify` if using self-signed certs locally, see Cloudflare docs).
        *   `tcp://<internal-ip>:PORT` for generic TCP services like SSH.

### 5. ↔️ Route DNS to the Tunnel

Create DNS CNAME records in your Cloudflare dashboard for each `hostname` you defined in `config.yml`.

*   Go to your Cloudflare dashboard ➡️ Select your domain ➡️ DNS settings.
*   For each hostname (e.g., `service1.yourdomain.com`):
    *   Type: `CNAME`
    *   Name: `service1` (or your chosen subdomain part like `dashboard`)
    *   Target: `<YOUR-TUNNEL-UUID>.cfargotunnel.com` (Use your actual Tunnel UUID)
    *   Proxy status: **Proxied** (Orange Cloud 🔶)

Alternatively, and often easier, use `cloudflared` to manage DNS (run from your VM/LXC):
```bash
cloudflared tunnel route dns <your-tunnel-name> service1.yourdomain.com
cloudflared tunnel route dns <your-tunnel-name> dashboard.yourdomain.com
# Add for each hostname
```
Replace `<your-tunnel-name>` with the name from `cloudflared tunnel create`.

### 6. 🚀 Run the Tunnel

Start the tunnel from your VM/LXC:
```bash
cloudflared tunnel run <your-tunnel-name>
```
If your `config.yml` is in `~/.cloudflared/config.yml` and correctly references the tunnel name or UUID, you might just be ableto run:
```bash
cloudflared tunnel run
```
To specify a config file not in the default location:
```bash
cloudflared tunnel --config /path/to/your/config.yml run <your-tunnel-name-or-uuid>
```

Your services should now be accessible via the hostnames you configured! 🎉

### 7. ⚙️ Run `cloudflared` as a Service (Recommended for Persistence)

To ensure `cloudflared` starts automatically on boot and stays running in your VM/LXC:

```bash
sudo cloudflared service install
sudo systemctl enable cloudflared --now # Enables and starts the service immediately
```
Check status:
```bash
sudo systemctl status cloudflared
```
When installing as a service, `cloudflared` typically copies `~/.cloudflared/config.yml` to `/etc/cloudflared/config.yml` and `~/.cloudflared/<TUNNEL-UUID>.json` (and `cert.pem`) to `/etc/cloudflared/`.
**Important:** Ensure the `tunnel` UUID and `credentials-file` path in `/etc/cloudflared/config.yml` are correct and point to `/etc/cloudflared/<YOUR-TUNNEL-UUID>.json`. The service runs as the `cloudflared` user, which doesn't have access to `/root/.cloudflared` or `/home/youruser/.cloudflared`.

You might need to manually copy these files if they weren't placed correctly by `service install` and adjust permissions:
```bash
# If config and creds are in /root/.cloudflared
sudo cp /root/.cloudflared/config.yml /etc/cloudflared/config.yml
sudo cp /root/.cloudflared/<YOUR-TUNNEL-UUID>.json /etc/cloudflared/
sudo cp /root/.cloudflared/cert.pem /etc/cloudflared/ # cert.pem is for the login, not strictly for running the tunnel after setup
sudo chown -R cloudflared:cloudflared /etc/cloudflared
sudo chmod 600 /etc/cloudflared/<YOUR-TUNNEL-UUID>.json # Secure credentials
```
Then edit `/etc/cloudflared/config.yml` to ensure `credentials-file` points to `/etc/cloudflared/<YOUR-TUNNEL-UUID>.json`.
Restart the service after changes: `sudo systemctl restart cloudflared`.

## 🤔 Troubleshooting

*   **📜 Logs:** Check `cloudflared` logs:
    *   If running directly: Output in your terminal.
    *   If running as a service: `journalctl -u cloudflared -f` or `sudo cloudflared service log`
*   **📄 Configuration:** Double-check `/etc/cloudflared/config.yml` (if running as service) or `~/.cloudflared/config.yml` for:
    *   Correct `tunnel` UUID.
    *   Correct `credentials-file` path.
    *   Valid YAML syntax.
    *   Correct local `service` URLs (can the VM/LXC access them?).
*   **🌐 DNS:** Ensure CNAME records in Cloudflare DNS are correct and **Proxied (Orange Cloud)**.
*   **🔥 Firewall (Proxmox & VM/LXC):**
    *   Ensure the VM/LXC's firewall (e.g., `ufw`) allows outbound connections for `cloudflared`.
    *   Ensure Proxmox host firewall allows traffic between the `cloudflared` VM/LXC and other VMs/LXCs that host your services if they are different.
    *   Ensure the services themselves are listening on the configured IPs/ports.
*   **🔗 Cloudflare Documentation:** The official [Cloudflare Tunnel documentation](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/) is your best friend!

This setup provides a secure way to access your Proxmox lab services. Explore Cloudflare Access policies for adding authentication to your exposed services! ✨
