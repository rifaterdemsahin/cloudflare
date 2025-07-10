# Product Requirement: Core Feature Definition

## 🧩 Feature Name:
Secure Proxmox VE Access via Cloudflare Tunnel

## 🎯 Objective:
To establish a secure and reliable method for accessing the Proxmox VE web interface publicly using Cloudflare Tunnels and a custom subdomain (`proxmox.rifaterdemsahin.com`). This will allow convenient remote management of the homelab environment while leveraging Cloudflare's security features.

## 👤 User Stories:
- As a [user type, e.g., End User], I want to [action, e.g., securely log in], so that [benefit, e.g., I can access my account].
- As a [user type, e.g., Administrator], I want to [action, e.g., manage user roles], so that [benefit, e.g., I can control access levels].
- ...

## 🔁 Acceptance Criteria:
Define what success looks like. Use Gherkin-style (Given/When/Then) if possible.
- **Scenario 1:** [Scenario Name]
  - Given [precondition]
  - When [action is performed]
  - Then [expected outcome]
- ...

## 🛠️ Functional Requirements:
- What should the system do?
  - [e.g., The system shall allow users to register with an email and password.]
  - [e.g., The system shall encrypt passwords using bcrypt.]
- Any validations or rules?
  - [e.g., Password must be at least 8 characters long.]
  - [e.g., Email must be a valid format.]

## 📦 Non-functional Requirements:
- **Performance:** [e.g., Login response time should be < 500ms for 99% of requests.]
- **Reliability:** [e.g., System uptime should be 99.9%.]
- **Security:** [e.g., All sensitive data must be encrypted at rest and in transit. Comply with GDPR.]
- **Scalability:** [e.g., The system should support 10,000 concurrent users.]
- **Usability:** [e.g., The registration process should be intuitive and completable within 2 minutes.]
- ...

## 🧪 Edge Cases & Constraints:
- What should NOT happen?
  - [e.g., Users should not be able to register with an already existing email.]
  - [e.g., System should gracefully handle login attempts with incorrect credentials without revealing if the username exists.]
- Any limitations?
  - [e.g., Maximum 3 failed login attempts before temporary account lockout.]
  - [e.g., Feature relies on a third-party email verification service which has a rate limit of X emails/hour.]

## 🔗 Dependencies:
- **APIs:** [e.g., Email Verification API, Payment Gateway API]
- **Databases:** [e.g., PostgreSQL for user data, Redis for session management]
- **Other Systems:** [e.g., Logging infrastructure, Monitoring tools]

## 🖼️ UI/UX (optional):
Describe user interactions or include mockup reference.
- [e.g., Refer to Figma mockups: link_to_figma_project/page]
- [e.g., Login page will have fields for username/email and password, a 'Forgot Password' link, and a 'Sign Up' link.]

## 📊 Metrics for Success:
How will you measure if the feature works well?
- [e.g., Successful user registration rate: target 95%.]
- [e.g., Daily active users (DAU) utilizing the feature.]
- [e.g., Reduction in support tickets related to this feature by X%.]
- [e.g., Task completion time for key user stories.]

---

## Objectives and Key Results (OKRs) for Secure Proxmox Access

### Objective 1: Successfully establish secure, public access to the Proxmox VE dashboard via a Cloudflare Tunnel using `proxmox.rifaterdemsahin.com` by [Target Date, e.g., end of current week].
- **Key Result 1.1:** `cloudflared` daemon is successfully installed and authenticated on the designated homelab server.
- **Key Result 1.2:** A Cloudflare tunnel named `proxmox-tunnel` (or similar, as defined in `.env`) is created, and the CNAME DNS record `proxmox.rifaterdemsahin.com` is correctly configured and pointing to this tunnel.
- **Key Result 1.3:** The `cloudflared` configuration file (e.g., `/etc/cloudflared/config.yml`) is correctly generated, and the `cloudflared` service is running stably, routing `proxmox.rifaterdemsahin.com` to the local Proxmox VE instance (e.g., `https://[PROXMOX_IP]:8006`).
- **Key Result 1.4:** The Proxmox VE dashboard is consistently accessible externally via `https://proxmox.rifaterdemsahin.com` and passes basic connectivity and login tests.

### Objective 2: Automate critical parts of the Cloudflare Tunnel setup and management process for Proxmox VE access.
- **Key Result 2.1:** Bash scripts are developed and placed in the `symbols/` directory for installing `cloudflared`, authenticating, creating the tunnel, generating `config.yml`, and managing the `cloudflared` service.
- **Key Result 2.2:** Scripts utilize environment variables (via an `.env` file) for user-specific configurations like API tokens, domain names, and IP addresses, with a clear `.env.example` provided.
- **Key Result 2.3:** Scripts include verbose logging to aid in troubleshooting and confirm successful execution of steps.
- **Key Result 2.4:** The Proxmox firewall configuration (restricting `pveproxy` to localhost) is scripted or clearly documented as part of the automated/guided setup.

### Objective 3: Ensure the setup is well-documented and maintainable.
- **Key Result 3.1:** The `formulas/cloudflare_godaddy_proxmox.md` guide is up-to-date and reflects any refinements made during the scripting process.
- **Key Result 3.2:** The `real/README.md` contains a clear task list that aligns with these OKRs, referencing both manual and scripted steps.
- **Key Result 3.3:** All scripts in the `symbols/` folder are adequately commented to explain their purpose and logic.

---

## Project Task List to Achieve OKRs

This task list outlines the steps to set up secure Proxmox VE access via Cloudflare Tunnels, aligning with the OKRs defined above.

### Phase 1: Prerequisites and Initial Setup (Manual & Cloudflare/GoDaddy UI)

-   [ ] **1.1. Cloudflare Account & Domain Setup:**
    -   [ ] Ensure you have a Cloudflare account.
    -   [ ] Add your domain (`rifaterdemsahin.com`) to Cloudflare (Partial Setup - Skip Nameserver Change initially). (Ref: `formulas/cloudflare_godaddy_proxmox.md` Step 1)
-   [ ] **1.2. GoDaddy DNS Configuration (Manual):**
    -   [ ] Log in to GoDaddy and navigate to DNS Management for `rifaterdemsahin.com`.
    -   [ ] Be prepared to add a CNAME record for `proxmox` later. (Ref: `formulas/cloudflare_godaddy_proxmox.md` Step 2 & 6)
-   [ ] **1.3. Prepare `.env` file:**
    -   [ ] Copy `symbols/.env.example` to `symbols/.env`.
    -   [ ] Populate `symbols/.env` with your specific values:
        -   `CF_API_TOKEN`: Your Cloudflare API Token (Permissions: Zone:Zone Settings:Read, Zone:Zone:Read, Zone:DNS:Edit).
        -   `CF_ZONE_ID`: (Optional, if using API for DNS) The Zone ID for `rifaterdemsahin.com`.
        -   `ACCOUNT_ID`: Your Cloudflare Account ID (used by `cloudflared` for login via token).
        -   `TUNNEL_NAME`: e.g., `proxmox-tunnel`.
        -   `DOMAIN_NAME`: `rifaterdemsahin.com`.
        -   `SUBDOMAIN_NAME`: `proxmox`.
        -   `PROXMOX_IP`: Local IP of your Proxmox server (e.g., `192.168.1.100`).
        -   `PROXMOX_PORT`: `8006`.
-   [ ] **1.4. Homelab Server Preparation:**
    -   [ ] Ensure your homelab server (Ubuntu/Debian recommended) has internet access and `curl`, `sudo` available.

### Phase 2: `cloudflared` Installation and Tunnel Creation (Scripts & Manual DNS)

-   [ ] **2.1. Install `cloudflared` Daemon:**
    -   [ ] Run script: `sudo bash symbols/install_cloudflared.sh`. (Achieves KR1.1 in part)
-   [ ] **2.2. Authenticate `cloudflared`:**
    -   [ ] This step typically involves `cloudflared tunnel login` which opens a browser.
    -   [ ] Alternatively, ensure `CF_API_TOKEN` is correctly set in `symbols/.env` if scripts are adapted to use it for specific commands that support token-based auth without prior login. The `authenticate_cloudflared.sh` might assist or provide guidance.
    -   [ ] Script: `bash symbols/authenticate_cloudflared.sh` (primarily for token setup if applicable). (Completes KR1.1)
-   [ ] **2.3. Create Cloudflare Tunnel:**
    -   [ ] Run script: `bash symbols/create_cf_tunnel.sh`.
    -   [ ] **Note the Tunnel ID** output by the script. You will need this for GoDaddy and `config.yml`.
    -   [ ] Update `TUNNEL_ID` in your `symbols/.env` file with the actual ID. (Part of KR1.2)
-   [ ] **2.4. Update GoDaddy CNAME Record (Manual):**
    -   [ ] Go to GoDaddy DNS Management for `rifaterdemsahin.com`.
    -   [ ] Add/Update CNAME record:
        -   Type: `CNAME`
        -   Name: `proxmox` (or your `$SUBDOMAIN_NAME`)
        -   Value: `<YOUR_TUNNEL_ID>.cfargotunnel.com`
        -   TTL: 1 hour (or as preferred).
    -   (Completes KR1.2 regarding DNS)

### Phase 3: Tunnel Configuration and Service Management (Scripts)

-   [ ] **3.1. Generate `cloudflared` Configuration File:**
    -   [ ] Ensure `TUNNEL_ID` is correctly set in `symbols/.env`.
    -   [ ] Run script: `sudo bash symbols/generate_cf_config.sh`. (Achieves KR1.3 in part)
-   [ ] **3.2. Test the Tunnel (Optional but Recommended):**
    -   [ ] Run script: `sudo bash symbols/manage_cf_service.sh run`.
    -   [ ] Try accessing `https://proxmox.rifaterdemsahin.com`. Troubleshoot if necessary. Stop the test run (Ctrl+C).
-   [ ] **3.3. Install and Start `cloudflared` Service:**
    -   [ ] Run script: `sudo bash symbols/manage_cf_service.sh install`.
    -   [ ] Run script: `sudo bash symbols/manage_cf_service.sh start`.
    -   [ ] Verify service status: `sudo bash symbols/manage_cf_service.sh status`. (Completes KR1.3 regarding service stability)

### Phase 4: Proxmox Configuration (Script/Manual)

-   [ ] **4.1. Configure Proxmox `pveproxy` (Recommended for Security):**
    -   [ ] Run script: `sudo bash symbols/configure_proxmox_firewall.sh` (if created).
    -   [ ] OR Manually edit `/etc/default/pveproxy` to add `ALLOW_FROM="127.0.0.1,::1"`.
    -   [ ] Manually restart proxy: `sudo systemctl restart pveproxy`. (Achieves KR2.4 in part)

### Phase 5: Verification and Monitoring

-   [ ] **5.1. Test External Access:**
    -   [ ] Wait for DNS propagation (can take some time).
    -   [ ] Access `https://proxmox.rifaterdemsahin.com` from an external network.
    -   [ ] Perform login and basic navigation tests. (Achieves KR1.4)
-   [ ] **5.2. Monitor Tunnel Status:**
    -   [ ] Regularly check `sudo bash symbols/manage_cf_service.sh status`.
    -   [ ] Check Cloudflare Dashboard for tunnel status.

### Phase 6: Documentation and Review (Continuous)

-   [ ] **6.1. Update Main Guide:**
    -   [ ] Ensure `formulas/cloudflare_godaddy_proxmox.md` reflects any changes or improvements from this process. (Achieves KR3.1)
-   [ ] **6.2. Review Script Comments:**
    -   [ ] Ensure all scripts in `symbols/` are well-commented. (Achieves KR3.3)
-   [ ] **6.3. Review this Task List:**
    -   [ ] Ensure this task list in `real/README.md` is accurate and complete. (Achieves KR3.2)
