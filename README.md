# docker-warp-socks 

Connect to Cloudflare WARP and expose a `socks5`/`http` proxy, via userspace
WireGuard in [sing-box](https://github.com/SagerNet/sing-box). No `NET_ADMIN`,
no `--privileged`, no kernel module.

This fork differs from upstream in three ways:

- **No runtime `curl | sh` from a shortlink.** The WARP registration logic is
  vendored into the image (`create-cloudflare-warp.sh`) and runs locally, so the
  image is auditable and reproducible.
- **No referral-farming.** There is no `referrer` field and no loop that credits
  bonus data to any account. It registers a single free account.
- **Pinned sing-box** instead of "fetch the latest beta at build time".

## Run

```sh
docker run --restart=always -itd \
    --name warp_socks \
    -p 9091:9091 \
    ghcr.io/<your-username>/<your-repo>:latest
```

Verify (expect `warp=on`):

```sh
curl -x socks5h://127.0.0.1:9091 -fsSL https://www.cloudflare.com/cdn-cgi/trace
curl -x http://127.0.0.1:9091     -fsSL https://www.cloudflare.com/cdn-cgi/trace
```

## Environment variables

| Var            | Default                        | Purpose                                            |
| -------------- | ------------------------------ | -------------------------------------------------- |
| `NET_PORT`     | `9091`                         | Listen port for the mixed (socks/http) inbound.    |
| `SOCK_USER`    | _(unset)_                      | If set with `SOCK_PWD`, enables proxy auth.        |
| `SOCK_PWD`     | _(unset)_                      | Proxy password.                                    |
| `WARP_LICENSE` | _(unset)_                      | Optional: attach a WARP+ key **you already own**.  |
| `WARP_SERVER`  | `engage.cloudflareclient.com`  | WARP endpoint host.                                |
| `WARP_PORT`    | `2408`                         | WARP endpoint port.                                |
| `WARP_MTU`     | `1280`                         | Tunnel MTU. Lower than a host path of 1420 allows. |

`WARP_LICENSE` binds the new account to an existing WARP+ subscription (the
"share across up to 5 devices" model). It does not generate or farm a license;
leave it unset for a normal free account.

## Build locally

```sh
docker build -t warp-socks .
# pin a different sing-box:
docker build --build-arg SINGBOX_VERSION=1.13.12 -t warp-socks .
```

## CI / publishing

`.github/workflows/build.yml` builds a multi-arch image and pushes to GHCR on
push to `main`, on `v*` tags, or via manual dispatch. It uses the built-in
`GITHUB_TOKEN` (no secrets to configure) and publishes to
`ghcr.io/<owner>/<repo>`.

After the first successful run, make the package public if you want anonymous
pulls: **GitHub → your profile → Packages → the package → Package settings →
Change visibility → Public**.

## Credits

- [SagerNet/sing-box](https://github.com/SagerNet/sing-box)
- [ViRb3/wgcf](https://github.com/ViRb3/wgcf)
- Upstream (sus calls to bit.ly, I wouldn't use): [Mon-ius/Docker-Warp-Socks](https://github.com/Mon-ius/Docker-Warp-Socks)

## Disclaimer

Not affiliated with or endorsed by Cloudflare. Using WARP this way may be subject
to Cloudflare's terms of service; you are responsible for your own use.
