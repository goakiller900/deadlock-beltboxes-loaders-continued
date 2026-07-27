# Development tests

`stacked_fuel_spec.lua` runs the prototype-stage stacked-fuel logic against a
small mocked Factorio data environment. It covers recipe-derived quantities,
batch recipes, matching and mismatched residues, exact bundle reuse, fuel
properties, third-party conflicts, and fail-closed behavior.

Run it with Lua 5.2 or newer:

```text
lua tests/stacked_fuel_spec.lua
```

It can also be run without a locally installed Lua interpreter:

```text
npx --yes --package fengari-node-cli fengari tests/stacked_fuel_spec.lua
```

The release builder excludes the `tests` directory from published mod archives.
