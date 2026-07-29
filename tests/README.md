# Development tests

The Lua specifications run data-stage and runtime helper logic against small
mocked Factorio environments:

- `stacked_fuel_spec.lua` covers repository-derived stack densities, canonical
  and batch recipe validation, matching and mismatched residues, exact bundle
  reuse, current fuel properties, third-party conflicts, and fail-closed
  behavior.
- `stacked_spoilage_spec.lua` covers copied spoil timers, matching stacked
  results, deterministic exact-count bundles, quality fields, idempotence, and
  unsupported spoil-result rejection.
- `space_age_stacks_spec.lua` covers Space Age and prototype guards, tiers,
  prototype types, and generated icon paths.
- `auto_unstack_spec.lua` covers exact quality/freshness transfer, capacity and
  transactional destination safety, event filters, and fail-closed metadata
  handling.

Run it with Lua 5.2 or newer:

Run each `tests/*_spec.lua` file with Lua 5.2 or newer.

It can also be run without a locally installed Lua interpreter:

```text
npx --yes --package fengari-node-cli fengari tests/stacked_spoilage_spec.lua
```

The release builder excludes the `tests` directory from published mod archives.
