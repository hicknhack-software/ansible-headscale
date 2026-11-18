# Headscale Ansible roles

These roles install Headscale, PostgreSQL and Headscale-UI on a dedicated Ubuntu 24.04 VM. PostgreSQL uses the `headscale` database and database role. Headscale authenticates over the local PostgreSQL socket as the `headscale` Linux user. Its state and server keys live in `/var/lib/headscale`.

Run the roles with privilege escalation and gather the VM's network facts. Install collections with `ansible-galaxy collection install -r requirements.yml`.

Use `hicknhack-software.headscale/postgresql`, `hicknhack-software.headscale/server` and `hicknhack-software.headscale/headscale-ui` in that order. The optional `hicknhack-software.headscale/apache-proxy` role registers the public vhost with an existing `hicknhack-software.reverse-proxy` Apache instance and its ACME configuration. The calling inventory supplies the proxy host and handles VM creation, NAT and backups.

## PostgreSQL

The `postgresql` role has no parameters. It installs the distribution's PostgreSQL package, starts the local cluster and creates the database and peer-authenticated role.

## Headscale server

| Parameter | Default | Purpose |
| --- | --- | --- |
| `headscale_server_url` | Required | Public URL used by Tailscale clients. Use HTTPS when Apache terminates TLS or the embedded DERP relay is enabled. |
| `headscale_listen_address` | VM default IPv4 address | Private address on which Headscale listens. |
| `headscale_port` | `8080` | Private HTTP port for the control API and DERP. |
| `headscale_trusted_proxies` | `[]` | CIDRs allowed to supply client IP headers. Set this to the Apache proxy's private address with a `/32` prefix. |
| `headscale_dns_split_nameservers` | `{}` | Map of DNS suffixes to resolver addresses reachable from enrolled clients. Clients use these resolvers for the listed suffixes and keep their normal DNS for other domains. |
| `headscale_version` | `0.29.7` | Upstream release version and installed Debian package version. |
| `headscale_deb_arch` | `amd64` | Debian architecture in the upstream asset name. |
| `headscale_deb_checksum` | Pinned SHA-256 | Digest in `sha256:<hex>` format. Update it with the release version or architecture. |
| `headscale_derp_enabled` | `false` | Enable the embedded DERP relay. |
| `headscale_derp_region_id` | `999` | Numeric region ID for the embedded relay. |
| `headscale_derp_region_code` | `headscale` | Short region identifier. |
| `headscale_derp_region_name` | `Headscale` | Display name for the region. |
| `headscale_derp_ipv4` | Empty | Public IPv4 address to advertise for the embedded relay. |
| `headscale_stun_port` | `3478` | UDP listener for STUN. Forward this port from the VM host when using the embedded relay behind NAT. |
| `headscale_derp_map_urls` | Tailscale's default DERP map | List of external DERP map URLs. |

Headscale stores its policy in PostgreSQL. The default configuration disables MagicDNS and DNS overrides.

## Headscale-UI

| Parameter | Default | Purpose |
| --- | --- | --- |
| `headscale_ui_version` | `2026.03.17` | Upstream static UI release. |
| `headscale_ui_checksum` | Pinned SHA-256 | Digest in `sha256:<hex>` format. Update it with the release version. |
| `headscale_ui_root` | `/srv/headscale-ui` | Root directory for extracted, versioned releases. |
| `headscale_ui_listen_address` | VM default IPv4 address | Private IPv4 address on which Nginx serves the UI. |
| `headscale_ui_port` | `8081` | Private HTTP port for the UI. |

The role replaces the stock Nginx site on the dedicated VM. The UI lives under `/web/` on the same public origin as the Headscale API. Create a key with `sudo headscale apikeys create` on the VM and enter it in **Settings**. Both installation roles remove their download directories after use.

## Apache proxy

| Parameter | Default | Purpose |
| --- | --- | --- |
| `headscale_proxy_domain` | Required | Public hostname used by the vhost and certificate. |
| `headscale_proxy_backend_address` | VM default IPv4 address | Private guest address reachable from Apache. |
| `headscale_proxy_api_port` | `8080` | Guest port for Headscale. Match `headscale_port`. |
| `headscale_proxy_ui_port` | `8081` | Guest port for Headscale-UI. Match `headscale_ui_port`. |
| `headscale_proxy_ip_group` | `public` | IP group used by the reverse-proxy role for vhost naming. |
| `headscale_proxy_ports` | `{http: 80, https: 443}` | Apache's HTTP and HTTPS listener ports. |
| `proxy_delegate` | Reverse-proxy inventory default | Inventory host that runs Apache. |
| `reverse_proxy_facts_hostname` | Reverse-proxy inventory default | Inventory host for the vhost cleanup facts. |

Apache sends `/web` and its subpaths to Nginx on the VM and forwards other requests to Headscale, including protocol upgrades. Public HTTPS goes through Apache. Only SSH and the relay's UDP STUN port need dedicated host forwards.

## Tailscale client and subnet router

Run `hicknhack-software.headscale/client` on a Debian or Ubuntu system that can reach the intended subnets and the Headscale URL. The role uses the Tailscale stable APT repository and delegates Headscale CLI commands over Ansible to the inventory host running Headscale 0.29.7. Run with privilege escalation on both hosts.

| Parameter | Default | Purpose |
| --- | --- | --- |
| `headscale_client_server_url` | Required | Headscale control URL reachable from the Tailscale node. Use the public HTTPS URL for production. |
| `headscale_client_user` | Required | Name of the user that owns the new node. The role creates this user if it is missing. |
| `headscale_client_admin_host` | Current inventory host | Ansible host that can run the Headscale CLI against its local server socket. Set this to the server's inventory name for a separate subnet router. |
| `headscale_client_hostname` | Short inventory hostname | Hostname the client advertises to Headscale. |
| `headscale_client_routes` | `[]` | Complete list of canonical IPv4 or IPv6 subnet CIDRs to advertise and approve for this node. An empty list withdraws its routes. |
| `headscale_client_accept_routes` | `false` | Accept routes advertised by other routers. Enable this for a Linux workstation that needs to reach the advertised subnets. |

The role generates a single-use, ten-minute key for initial enrollment and deletes its temporary file. It verifies the node's identity before managing advertisements or approvals. It persists IP forwarding for the specified address families in `/etc/sysctl.d/99-headscale-subnet-router.conf`. With a permissive Headscale policy, any tailnet node can use an approved route. Limit access with grants if only particular users or ports should be reachable. [Headscale subnet route policy](https://headscale.net/0.29.7/ref/routes/#restrict-the-use-of-a-subnet-router-with-a-policy)

## Local development

Use Docker Compose to start the Ansible controller, Headscale, a subnet router, a tailnet client and an OpenSSH guest on an isolated network. The suite tests the database, API and UI, creates a Headscale user, enrolls both devices under that user, and checks that SSH to the isolated guest works only while the route is approved.

```bash
docker compose up -d
docker compose exec -T ansible bash tests/run.sh
docker compose down -v
```

While the stack is up, the API health endpoint is at `http://127.0.0.1:18080/health` and the UI is at `http://127.0.0.1:18081/web/`. Inspect the local VM through Compose for development. The production Apache vhost supplies the shared HTTPS origin.

In VS Code, open this repository in the provided Dev Container and run `bash tests/run.sh` in its terminal.
