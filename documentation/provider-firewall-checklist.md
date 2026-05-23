# Provider Firewall Checklist

Apply these rules in the VPS provider firewall after bootstrapping.

## Inbound

- Deny public TCP 22.
- Allow public TCP 80 when hosting HTTP traffic.
- Allow public TCP 443 when hosting HTTPS traffic.
- Deny all other unsolicited public inbound traffic unless an application explicitly requires it.

## Tailnet SSH

Most providers cannot express "allow TCP 22 only from my Tailnet" because Tailscale traffic is encrypted over outbound WireGuard connections from the host. In that case, block public TCP 22 at the provider and rely on Tailscale plus the host firewall for Tailnet SSH.

## Outbound

Allow outbound traffic required for:

- OS package repositories.
- Tailscale coordination and DERP connectivity.
- Application-specific external services.

## Verification

After bootstrap:

```bash
ssh deploy@<tailscale-ip>
```

Then confirm public SSH is closed from a non-Tailnet network:

```bash
nc -vz <public-vps-ip> 22
```

HTTP/HTTPS should remain reachable only if `--web` was enabled:

```bash
nc -vz <public-vps-ip> 80
nc -vz <public-vps-ip> 443
```
