# Design diagrams

Static SVG diagrams for [design.md](../design.md). These render in any markdown
preview (Cursor, VS Code, GitHub, GitLab) without a Mermaid extension.

| File | Section | What it shows |
|------|---------|---------------|
| [architecture-overview.svg](./architecture-overview.svg) | §3.1 | Bootstrap → extension repos → seeded CI publishes |
| [public-customer-mapping.svg](./public-customer-mapping.svg) | §3.2 | Public OpenG2P → customer private mapping |
| [publish-flow.svg](./publish-flow.svg) | §7.1 | Extension-repo CI: version → Docker → helm → changelog |
| [bootstrap-flow.svg](./bootstrap-flow.svg) | §9 | One-time bootstrap steps |

**Terminology:**

- **Extension repo** — where the customer writes code (registry / bridge / pbms connectors). Created with CI already seeded.
- **Destination repo** — `{customer}-helm` and `{customer}-versions`; CI write-only artifact stores.
