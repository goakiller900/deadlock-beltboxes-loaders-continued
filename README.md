# Deadlock's Stacking Beltboxes & Compact Loaders Continued

Community-maintained continuation of **Deadlock's Stacking Beltboxes & Compact Loaders**, updated for Factorio 2.1.

This mod adds small 1x1 loaders and beltboxes. These can be used to stack items from a belt, in-line, greatly increasing belt throughput.

## Status

This continuation currently focuses on keeping the original mod working on newer Factorio versions.

Tested with:

- Factorio 2.1
- Basic loaders
- Beltboxes
- Stacking and unstacking recipes

## Credits

Original authors:

- Deadlock989
- Shane Madden
- MasterBuilder

Continuation maintainer:

- goakiller900

All credit for the original mod, concept, graphics, and implementation belongs to the original authors.

## Unofficial continuation notice

This is not an official release from the original maintainers. It exists to keep the mod usable on newer Factorio versions.

If one of the original maintainers returns and wishes to resume maintenance, this continuation can be archived, redirected, or transferred as appropriate.

## License

This project remains licensed under the GNU General Public License version 3, as required by the original license.

## Modding API

This mod exposes the `deadlock` API from the original project for bridge mods and compatibility integrations.

For most integrations, add this mod as an optional dependency and call the API from `data-final-fixes.lua` after checking that `deadlock` exists.

Example dependency:

```json
{
  "dependencies": ["base >= 2.1", "?deadlock-beltboxes-loaders"],
  "factorio_version": "2.1"
}
```

Example usage:

```lua
if deadlock then
  deadlock.add_stack("example-item", "__ExampleMod__/graphics/icons/example-stack.png", "deadlock-stacking-1", 64)
end
```

Main API functions retained from the original mod:

- `deadlock.add_stack(item_name, graphic_path, target_tech, icon_size, item_type, mipmap_levels)`
- `deadlock.destroy_stack(item_name)`
- `deadlock.destroy_vanilla_stacks()`
- `deadlock.add_tier(tier_table)`

For detailed behavior, see the source files in `prototypes/public.lua`.
