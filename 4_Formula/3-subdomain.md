Perfect! You can keep your GoDaddy nameservers and just forward the subdomain. Here’s how to do it:

## Step 1: Add Domain to Cloudflare (Partial Setup)

1. **Add domain to Cloudflare:**
- Log into Cloudflare dashboard
- Click “Add a Site”
- Enter `rifaterdemsahin.com`
- Choose Free plan
- **SKIP** the nameserver change step

## Step 2: Create CNAME Record at GoDaddy

1. **Log into GoDaddy:**
- Go to Domain Manager
- Click on your domain `rifaterdemsahin.com`
- Go to DNS Management
1. **Add CNAME record:**
- Type: `CNAME`
- Name: `proxmox`
- Value: `[TUNNEL-ID].cfargotunnel.com` (you’ll get this after creating the tunnel)
- TTL: 1 hour

## Step 3: Install Cloudflared on Your Homelab

**For Ubuntu/Debian:**

```bash
# Download and install cloudflared
curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb -o cloudflared.deb
sudo dpkg -i cloudflared.deb
```

## Step 4: Authenticate Cloudflared

```bash
cloudflared tunnel login
```

- This opens a browser window
- You’ll need to temporarily add your domain to Cloudflare for authentication
- Or use an API token instead

## Alternative: Use API Token (Recommended)

1. **Create API Token:**
- Go to Cloudflare dashboard → My Profile → API Tokens
- Create Custom Token with permissions:
  - Zone: Zone Settings:Read
  - Zone: Zone:Read
  - Zone: DNS:Edit
1. **Set environment variable:**

```bash
export CLOUDFLARE_API_TOKEN=your_api_token_here
```

## Step 5: Create the Tunnel

```bash
# Create tunnel
cloudflared tunnel create proxmox-tunnel

# Note the tunnel ID that gets generated (something like: 12345678-1234-1234-1234-123456789012)
```

## Step 6: Update GoDaddy CNAME Record

Now go back to GoDaddy and update the CNAME record:

- Name: `proxmox`
- Value: `[TUNNEL-ID].cfargotunnel.com`

Replace `[TUNNEL-ID]` with the actual tunnel ID from Step 5.

## Step 7: Configure the Tunnel

Create configuration file:

```bash
sudo mkdir -p /etc/cloudflared
sudo nano /etc/cloudflared/config.yml
```

Add this configuration:

```yaml
tunnel: proxmox-tunnel
credentials-file: /root/.cloudflared/[TUNNEL-ID].json

ingress:
  - hostname: proxmox.rifaterdemsahin.com
    service: https://[YOUR-PROXMOX-IP]:8006
    originRequest:
      noTLSVerify: true
  - service: http_status:404
```

Replace:

- `[TUNNEL-ID]` with your actual tunnel ID
- `[YOUR-PROXMOX-IP]` with your Proxmox server’s local IP (e.g., 192.168.1.100)

## Step 8: Run the Tunnel

**Test first:**

```bash
cloudflared tunnel run proxmox-tunnel
```

**Install as service:**

```bash
sudo cloudflared service install
sudo systemctl enable cloudflared
sudo systemctl start cloudflared
```

## Step 9: Test the Connection

- Visit: `https://proxmox.rifaterdemsahin.com`
- You should see your Proxmox login page

## Step 10: Configure Proxmox (Optional)

Edit Proxmox configuration:

```bash
sudo nano /etc/default/pveproxy
```

Add:

```
ALLOW_FROM="127.0.0.1,::1"
```

Restart Proxmox proxy:

```bash
sudo systemctl restart pveproxy
```

## Benefits of This Approach

- Keep your existing GoDaddy DNS setup
- Only the subdomain goes through Cloudflare
- No nameserver changes needed
- Still get Cloudflare’s security benefits for the tunnel

## Troubleshooting

**Check tunnel status:**

```bash
cloudflared tunnel list
cloudflared tunnel info proxmox-tunnel
systemctl status cloudflared
```

**Common issues:**

- **CNAME not resolving:** Wait 1-2 hours for DNS propagation
- **502 errors:** Verify Proxmox is accessible locally
- **Authentication issues:** Try using API token method

This method keeps your domain management simple while still providing secure access to your Proxmox homelab!​​​​​​​​​​​​​​​​