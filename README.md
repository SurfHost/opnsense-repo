# SurfHost OPNsense plugin repository

One package repository for all SurfHost OPNsense plugins. Add it once and every plugin below shows up under **System > Firmware > Plugins**.

## Add the repository

On the firewall, in a root shell (SSH or console, option 8):

```sh
fetch -o /usr/local/etc/pkg/repos/surfhost.conf https://surfhost.github.io/opnsense-repo/surfhost.conf
pkg update
```

Then go to **System > Firmware > Plugins**, click **Click to view the community plugins** and install from there. Install and remove plugins through that page rather than with `pkg`, so OPNsense keeps them registered and reinstalls them after a configuration restore.

## Plugins

| Package | What it does | Source |
|---|---|---|
| `os-openvpn-auth-oauth2` | Microsoft Entra ID (OIDC) single sign-on for OpenVPN | [opnsense-plugin-entra-sso](https://github.com/SurfHost/opnsense-plugin-entra-sso) |
| `os-speedtest-surfhost` | Internet speed test with history, schedule and dashboard widget | [opnsense-plugin-speedtest](https://github.com/SurfHost/opnsense-plugin-speedtest) |

The live list per OPNsense ABI is at <https://surfhost.github.io/opnsense-repo/>.

## Remove the repository

Remove the plugins first, then:

```sh
rm /usr/local/etc/pkg/repos/surfhost.conf
pkg update
```

## Publishing (maintainers)

Packages are built and published from an OPNsense build box by each plugin's own `tools/release.sh`, which ends by calling [`tools/publish.sh`](tools/publish.sh) from this repository with the packages it built. `publish.sh` only replaces packages with the same name, so plugins release independently, and it regenerates the catalogue and `index.html` over everything in the ABI directory.

- `main` holds `surfhost.conf` (the single source of truth, copied to Pages on each publish) and the tools.
- `gh-pages` holds the served repository. Never check it out on Windows: the ABI directories contain colons.
- Priority 0 is deliberate: OPNsense's own repository (priority 11) wins for any package name both offer. Never use a negative priority; pkg stores it unsigned.
- Packages must be rebuilt for every OPNsense major release (new ABI or plugin framework changes).
