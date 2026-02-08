# Deployment Notes - SSL Certificate Management

## Recent Changes (2024)

### SSL Certificate Workflow Improvements

#### Problem Solved
The CI/CD pipeline was regenerating Let's Encrypt SSL certificates on every deployment, even when existing certificates were still valid. This was:
- Wasteful of Let's Encrypt API rate limits
- Unnecessary deployment time overhead
- Potentially hitting rate limits on frequent deployments

#### Solution Implemented
Added intelligent certificate checking before regeneration:

1. **Certificate Expiry Check** - New step checks existing certificates in the `ssl-certs` Docker volume
2. **Conditional Regeneration** - Only regenerates if:
   - No certificates exist, OR
   - Less than 30 days until expiry, OR
   - Manual force via `force_ssl_regen` workflow input
3. **Root SSH Key Support** - Added `ROOT_SSH_KEY` parameter to handle Docker operations without sudo issues

#### How It Works

```yaml
# Step 1: Check existing certificates
- name: 🔍 Check existing SSL certificates
  # Connects to server via SSH
  # Checks ssl-certs Docker volume
  # Calculates days until expiry
  # Sets output: needs_renewal (true/false)

# Step 2: Only regenerate if needed
- name: 🔐 Generate SSL Certificates
  if: steps.check-certs.outputs.needs_renewal == 'true' || inputs.force_ssl_regen == true
  # Only runs when certificates need renewal
```

#### Current Certificate Status (as of last deployment)
- **Type:** Let's Encrypt (Production)
- **Domains Covered:**
  - `7gram.xyz`
  - `*.7gram.xyz` (wildcard)
  - `*.sullivan.7gram.xyz` (wildcard)
- **Expiry:** May 9, 2026
- **Renewal Threshold:** 30 days before expiry

#### Workflow Outputs
The deployment now provides:
- `cert_exists` - Whether certificates were found
- `needs_renewal` - Whether renewal is needed
- `expiry_date` - Current certificate expiration date
- `days_until_expiry` - Days remaining until expiration

#### Manual Certificate Regeneration
To force SSL certificate regeneration:
1. Go to Actions → Freddy Deploy workflow
2. Click "Run workflow"
3. Enable "Force SSL regeneration"
4. Click "Run workflow"

#### Troubleshooting

**If certificates fail to deploy:**
- Check that `ROOT_SSH_KEY` secret is set in GitHub
- Verify Docker is installed on the server
- Check that `ssl-certs` volume is accessible

**If renewal fails:**
- Check Cloudflare API token is valid
- Verify DNS is properly configured
- Check Let's Encrypt rate limits (50 certs/week per domain)
- Review GitHub Actions logs for specific errors

#### Future Improvements
- Consider automated renewal checks via scheduled workflow
- Add Slack/Discord notifications for upcoming expirations
- Implement certificate monitoring dashboard