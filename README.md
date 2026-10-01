# OpenG2P Customer Bundle

Bootstrapper and template pack that creates **private destination repos** (helm,
versions) and **extension repos** (registry, bridge, pbms connectors) for a
customer.

This repository does **not** hold customer domain code. The customer writes code
in the extension repos this tool creates. Those extension repos are seeded with
CI that, on every push, computes a version, builds Docker images, pushes helm
charts to `<customer>-helm`, and pushes the changelog to `<customer>-versions`.

## Status

**Design Draft v1** — design is in-repo; implementation (packs, destinations,
bootstrap) comes next.

## Design

See **[docs/design.md](docs/design.md)** for the full design (includes diagrams):

- Private `<customer>-helm` — CI destination for packaged `.tgz` (like [openg2p-helm](https://github.com/OpenG2P/openg2p-helm), no public Pages)
- Private `<customer>-versions` — CI destination for changelogs (like [versions](https://github.com/OpenG2P/versions))
- Extension repos (customer code + seeded CI):
  - Registry → [farmer-registry](https://github.com/OpenG2P/farmer-registry/tree/1.2) shape
  - Bridge → [g2p-bridge-connectors](https://github.com/OpenG2P/g2p-bridge-connectors) shape
  - PBMS → connectors repo (bridge-like); product remains [pbms](https://github.com/OpenG2P/pbms)
- Diagrams: [docs/diagrams/](docs/diagrams/)

Manifest example: **[schema/customer.manifest.yaml](schema/customer.manifest.yaml)**

## License

[MPL-2.0](LICENSE)
