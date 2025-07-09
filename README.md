# Setting up Cloudflare Tunnel for Home Lab Proxy

This guide outlines the steps to set up Cloudflare Tunnel (`cloudflared`) to securely expose services running on your home lab to the internet via a Cloudflare proxy.

## Prerequisites

1.  **Cloudflare Account:** You need an active Cloudflare account.
2.  **Domain in Cloudflare:** You must have a domain name added to your Cloudflare account, with its DNS managed by Cloudflare.
3.  **Home Lab Server:** A server (Linux, macOS, Windows, or Docker environment) in your home lab where you will install `cloudflared`.

## Installation and Configuration Steps

### 1. Install `cloudflared`

Install the `cloudflared` daemon on your home lab server. Choose the method appropriate for your server's operating system:

*   **Linux:**
    *   Follow the instructions at the [Cloudflare Package Repository](https://pkg.cloudflare.com/) to add the repository and install `cloudflared` using your package manager (e.g., `apt` for Debian/Ubuntu, `yum` or `dnf` for Fedora/CentOS).
    *   Alternatively, download the latest release directly:
        *   amd64/x86-64: `wget https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64`
        *   arm64: `wget https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64`
        *   Make it executable: `chmod +x cloudflared-linux-amd64` (or `arm64`)
        *   Move it to your PATH: `sudo mv cloudflared-linux-amd64 /usr/local/bin/cloudflared`

*   **macOS:**
    *   Using Homebrew (recommended):
        ```bash
        brew install cloudflared
        ```
    *   Alternatively, download the [latest Darwin arm64 release](https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-darwin-arm64.tgz) or [latest Darwin amd64 release](https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-darwin-amd64.tgz) and extract it.

*   **Windows:**
    *   Using winget (recommended):
        ```powershell
        winget install --id Cloudflare.cloudflared
        ```
    *   Alternatively, download the [latest 64-bit executable](https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe) or [32-bit executable](https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-386.exe). Rename it to `cloudflared.exe` and place it in a directory included in your system's PATH.
    *   **Note:** `cloudflared` does not automatically update on Windows. You'll need to manually update it.

*   **Docker:**
    *   A Docker image is available on DockerHub: `cloudflare/cloudflared`.
        ```bash
        docker pull cloudflare/cloudflared
        ```

Verify installation:
```bash
cloudflared --version
```

### 2. Authenticate `cloudflared`

Log in `cloudflared` to your Cloudflare account. This command will open a browser window asking you to authorize the tunnel for your domain.
```bash
cloudflared login
```
Select the domain you want to use for the tunnel.

### 3. Create a Tunnel

Create a tunnel. Replace `<your-tunnel-name>` with a descriptive name for your tunnel (e.g., `homelab-tunnel`).
```bash
cloudflared tunnel create <your-tunnel-name>
```
This command will output a Tunnel UUID and create a credentials file (e.g., `<TUNNEL-UUID>.json`) in the default `cloudflared` directory (usually `~/.cloudflared/` on Linux/macOS or `%USERPROFILE%/.cloudflared` on Windows). **Note down the Tunnel UUID.**

### 4. Configure the Tunnel (Ingress Rules)

Create a configuration file named `config.yml` in the `cloudflared` directory (e.g., `~/.cloudflared/config.yml`).

**Example `config.yml`:**

```yaml
tunnel: <YOUR-TUNNEL-UUID> # Paste your Tunnel UUID here
credentials-file: /path/to/your/.cloudflared/<YOUR-TUNNEL-UUID>.json # Adjust path as per your OS and setup

ingress:
  - hostname: service1.yourdomain.com # Your desired public hostname
    service: http://localhost:8080    # The local service you want to expose
  - hostname: another-service.yourdomain.com
    service: http://192.168.1.100:3000 # Can be any IP/port on your local network
  # Add more services as needed
  - service: http_status:404 # Catch-all rule: if no hostname matches, return 404
```

*   Replace `<YOUR-TUNNEL-UUID>` with the UUID from the previous step.
*   Update `credentials-file` path if it's not in the default location or if running as a different user.
    *   Linux/macOS default: `~/.cloudflared/<YOUR-TUNNEL-UUID>.json`
    *   Windows default: `%USERPROFILE%/.cloudflared\<YOUR-TUNNEL-UUID>.json`
*   Under `ingress`, define your services:
    *   `hostname`: The public subdomain you'll use to access the service.
    *   `service`: The local URL of the service (e.g., `http://localhost:PORT`, `https://internal-ip:PORT`, `tcp://localhost:PORT` for TCP services like SSH).

### 5. Route DNS to the Tunnel

Create a DNS CNAME record in your Cloudflare dashboard for each hostname defined in your `config.yml`.

*   Go to your Cloudflare dashboard, select your domain, and navigate to the DNS settings.
*   For each hostname (e.g., `service1.yourdomain.com`):
    *   Type: `CNAME`
    *   Name: `service1` (or your chosen subdomain part)
    *   Target: `<YOUR-TUNNEL-UUID>.cfargotunnel.com` (Replace `<YOUR-TUNNEL-UUID>` with your tunnel's UUID)
    *   Proxy status: Proxied (Orange Cloud)

Alternatively, you can use the `cloudflared` command to manage DNS routing (this is often easier):
```bash
cloudflared tunnel route dns <your-tunnel-name> service1.yourdomain.com
cloudflared tunnel route dns <your-tunnel-name> another-service.yourdomain.com
```
Replace `<your-tunnel-name>` with the name you used in `cloudflared tunnel create`.

### 6. Run the Tunnel

Start the tunnel using its name:
```bash
cloudflared tunnel run <your-tunnel-name>
```
Or, if your `config.yml` is correctly set up in the default directory and names the tunnel, you might just run:
```bash
cloudflared tunnel run
```
If your configuration file is not in the default location, you can specify it:
```bash
cloudflared tunnel --config /path/to/your/config.yml run <your-tunnel-name>
```

Your services should now be accessible via the hostnames you configured.

### 7. Run `cloudflared` as a Service (Recommended for Persistence)

To ensure `cloudflared` starts automatically on boot and stays running, install it as a service.

*   **Linux (systemd):**
    ```bash
    sudo cloudflared service install
    sudo systemctl enable cloudflared
    sudo systemctl start cloudflared
    ```
    If you used a custom path for your `config.yml`, you might need to modify the service file or ensure `cloudflared` can find it. Typically, `cloudflared service install` will copy your default `~/.cloudflared/config.yml` to `/etc/cloudflared/config.yml` and use the tunnel credentials from `~/.cloudflared/<TUNNEL-UUID>.json` by copying it to `/etc/cloudflared/<TUNNEL-UUID>.json`. Ensure these paths are correct in `/etc/cloudflared/config.yml`.

*   **macOS (launchd):**
    ```bash
    sudo cloudflared service install
    # The service should start automatically. To manage:
    # sudo launchctl load /Library/LaunchDaemons/com.cloudflare.cloudflared.plist
    # sudo launchctl unload /Library/LaunchDaemons/com.cloudflare.cloudflared.plist
    ```
    Similar to Linux, check `/usr/local/etc/cloudflared/config.yml` (or equivalent) for configuration.

*   **Windows (as a service):**
    Open PowerShell as Administrator:
    ```powershell
    cloudflared.exe service install
    # The service should be set to start automatically.
    # You can manage it via the Services app (services.msc).
    ```
    The configuration and credentials files are typically expected in `C:\Windows\System32\config\systemprofile\.cloudflared\`. You may need to copy your `config.yml` and `<TUNNEL-UUID>.json` to this location before running `service install`, or ensure the service is configured to find them.

## Troubleshooting

*   **Logs:** Check `cloudflared` logs for errors. If running as a service:
    *   Linux: `journalctl -u cloudflared` or `sudo cloudflared service log`
    *   macOS: Check Console app or `/var/log/cloudflared.log` (path might vary).
    *   Windows: Event Viewer.
*   **Configuration:** Double-check your `config.yml` for syntax errors, correct tunnel UUID, and valid service URLs.
*   **DNS:** Ensure your CNAME records in Cloudflare DNS are correct and proxied.
*   **Firewall:** Ensure your home lab server's firewall allows `cloudflared` to make outbound connections and allows traffic to your local services (e.g., `localhost:8080`).
*   **Cloudflare Documentation:** Refer to the official [Cloudflare Tunnel documentation](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/) for the most up-to-date information and advanced configurations.

This README provides a foundational setup. Cloudflare Tunnel offers many more features like Access policies for authentication, load balancing, and more. Explore the official documentation to enhance your setup.
