# do-ipv6-ddns

Automatically updates an IPv6 DNS record at do.de when the delegated IPv6 prefix changes.

This project is designed for IPv6 connections where the ISP dynamically assigns a new IPv6 prefix, such as Deutsche Glasfaser connections using DHCPv6 Prefix Delegation behind a UniFi Gateway.

The updater runs as a small Docker container, monitors the IPv6 address assigned to a specified network interface, detects prefix changes and updates the corresponding do.de FlexDNS record.

## Why?

With a dynamically delegated IPv6 prefix, the public IPv6 address of a server can change when the ISP assigns a new prefix.

Example:

    Old:
    2a00:6020:9443:e700:4e52:62ff:fea3:9506

    New:
    2a00:6020:9440:500:4e52:62ff:fea3:9506

The interface identifier remains the same:

    4e52:62ff:fea3:9506

while the delegated `/64` prefix changes.

Manually updating DNS after every prefix change is inconvenient and can result in downtime.

This container detects the new IPv6 prefix and updates the corresponding do.de FlexDNS record automatically.

## How it works

    ISP
     |
     | DHCPv6 Prefix Delegation
     v
    UniFi Gateway
     |
     | IPv6 /64
     v
    Server / br0
     |
     | detect current prefix
     v
    do-ipv6-ddns
     |
     | FlexDNS update
     v
    do.de
     |
     | AAAA record
     v
    myhomehub.de

The container periodically checks the configured network interface.

If the IPv6 prefix has not changed, nothing happens.

If a new prefix is detected, the updater sends the new prefix to do.de using the `ip6lanprefix` parameter.

## Current setup

The project was developed for the following setup:

- Deutsche Glasfaser
- UniFi Dream Machine SE
- DHCPv6 Prefix Delegation
- Unraid
- Docker
- `br0` as the relevant network interface
- do.de as DNS provider
- do.de FlexDNS

Example:

    LAN Prefix:
    2a00:6020:9440:500::/64

    Server IPv6:
    2a00:6020:9440:500:4e52:62ff:fea3:9506

The FlexDNS update sends the current LAN prefix to do.de.

The existing interface identifier is retained by the do.de FlexDNS configuration.

## Configuration

The container is configured using environment variables.

| Variable | Description | Example |
|---|---|---|
| `INTERFACE` | Network interface containing the global IPv6 address | `br0` |
| `HOSTNAME` | DNS hostname managed by FlexDNS | `myhomehub.de` |
| `DO_USER` | do.de FlexDNS username | `DDNS-KD26973-F2838` |
| `DO_PASS` | do.de FlexDNS password | secret |
| `CHECK_INTERVAL` | Check interval in seconds | `60` |

## Docker Compose

Example `docker-compose.yml`:

    services:
      do-ipv6-ddns:
        build: .
        container_name: do-ipv6-ddns
        restart: unless-stopped
        network_mode: host

        environment:
          INTERFACE: br0
          HOSTNAME: myhomehub.de
          DO_USER: ${DO_USER}
          DO_PASS: ${DO_PASS}
          CHECK_INTERVAL: 60

Using `${DO_USER}` and `${DO_PASS}` allows credentials to be supplied through environment variables without storing them directly in the Compose file.

## Environment variables

For local testing:

    export DO_USER='DDNS-KD26973-F2838'
    export DO_PASS='your-flexdns-password'

Check the username:

    echo "$DO_USER"

Do not print or commit the password.

Alternatively, Docker Compose can load the variables from a `.env` file.

Example `.env`:

    DO_USER=DDNS-KD26973-F2838
    DO_PASS=your-flexdns-password

Add `.env` to `.gitignore`:

    .env

Never commit credentials to GitHub.

## do.de FlexDNS

The updater uses the do.de FlexDNS endpoint with the `ip6lanprefix` parameter.

Example:

    curl -fsS -u "$DO_USER:$DO_PASS"       --get       --data-urlencode "hostname=myhomehub.de"       --data-urlencode "ip6lanprefix=2a00:6020:9440:500::/64"       "https://ddns.do.de/"

A successful request returns a response beginning with:

    good

The authoritative DNS server can then be checked:

    dig @ns1.domainoffensive.de AAAA myhomehub.de +short

Expected result:

    2a00:6020:9440:500:4e52:62ff:fea3:9506

## Prefix detection

The container monitors the configured interface, for example:

    br0

The interface is expected to have a global IPv6 address with a prefix length of `/64`.

Example:

    2a00:6020:9440:500:4e52:62ff:fea3:9506/64

The corresponding LAN prefix is:

    2a00:6020:9440:500::/64

If the detected prefix differs from the previously processed prefix, a FlexDNS update is triggered.

## Example prefix change

Before:

    2a00:6020:9443:e700::/64

Server:

    2a00:6020:9443:e700:4e52:62ff:fea3:9506

After:

    2a00:6020:9440:500::/64

Server:

    2a00:6020:9440:500:4e52:62ff:fea3:9506

The updater detects the change and sends:

    ip6lanprefix=2a00:6020:9440:500::/64

to do.de.

## Docker network mode

The container uses:

    network_mode: host

This is intentional.

The updater needs access to the host's actual network interfaces so it can inspect the IPv6 address assigned to `br0`.

Using a normal Docker bridge network would only expose the container's Docker network interfaces.

## DNS considerations

When testing whether an update has reached do.de, query an authoritative do.de nameserver:

    dig @ns1.domainoffensive.de AAAA myhomehub.de +short

Public recursive DNS resolvers such as Cloudflare (`1.1.1.1`) and Google (`8.8.8.8`) may temporarily return an older value because of DNS caching.

For example:

    dig @1.1.1.1 AAAA myhomehub.de +short
    dig @8.8.8.8 AAAA myhomehub.de +short

An old result from a public resolver does not necessarily mean that the FlexDNS update failed.

## Testing

Before deploying to Unraid, the FlexDNS endpoint can be tested manually:

    curl -fsS -u "$DO_USER:$DO_PASS"       --get       --data-urlencode "hostname=myhomehub.de"       --data-urlencode "ip6lanprefix=2a00:6020:9440:500::/64"       "https://ddns.do.de/"

A successful response should start with:

    good

Then verify the authoritative DNS server:

    dig @ns1.domainoffensive.de AAAA myhomehub.de +short

## Development

Build the Docker image:

    docker compose build

Start the container:

    docker compose up -d

View logs:

    docker compose logs -f

Stop the container:

    docker compose down

## Security

Never commit:

- FlexDNS passwords
- API credentials
- `.env` files containing secrets
- private keys

Use environment variables, Docker secrets, or another secure secret-management mechanism.

## Project status

The do.de FlexDNS mechanism with the `ip6lanprefix` parameter has been successfully tested.

Example:

    ip6lanprefix=2a00:6020:9440:500::/64

The resulting authoritative AAAA record was:

    2a00:6020:9440:500:4e52:62ff:fea3:9506

The next step is to finalize and test the automatic IPv6 prefix detection and change detection inside the Docker container.

## License

Add your preferred license here.
