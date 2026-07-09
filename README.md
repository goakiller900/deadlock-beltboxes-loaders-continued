# Deadlock's Stacking Beltboxes & Compact Loaders Continued

Community-maintained continuation of **Deadlock's Stacking Beltboxes & Compact Loaders**, updated for Factorio 2.1.

This mod adds compact 1x1 loaders and stacking beltboxes. Beltboxes convert eligible items into stacked variants and back again, allowing much higher throughput on transport belts while keeping the original gameplay style of the mod.

## Status

This continuation currently focuses on keeping the original mod usable on newer Factorio versions.

Tested with:

- Factorio 2.1
- Basic loaders
- Beltboxes
- Stacking and unstacking recipes

## Project history

The original mod was created by **Deadlock989** and later maintained/ported by **Shane Madden**, with contributions from **MasterBuilder** and others.

This repository is an unofficial continuation. It exists because the original project has not yet received a Factorio 2.1 release, while many saves and modpacks still depend on the stacking and loader gameplay provided by this mod.

## Credits

Original authors and maintainers:

- Deadlock989
- Shane Madden
- MasterBuilder

Continuation maintainer:

- goakiller900

All credit for the original concept, graphics, implementation, balance, and API design belongs to the original authors and contributors.

## Unofficial continuation notice

This is not an official release from the original maintainers. It is a community-maintained compatibility continuation.

If one of the original maintainers returns and wishes to resume maintenance, this continuation can be archived, redirected, or transferred as appropriate.

## License

This project remains licensed under the **GNU General Public License version 3**.

The original license and copyright notices must remain intact. Modified versions must also remain under GPLv3.

## Factorio 2.1 notes

Factorio 2.1 changed `RecipePrototype` handling so `category` and `additional_categories` are now represented through the `categories` table.

This continuation updates loader and beltbox recipes to use the new `categories` field directly and keeps a compatibility conversion for older bridge mods that may still create recipes with the old fields.

## Modding API

This mod keeps the original public API for bridge mods and compatibility integrations.

Use these functions from `data-final-fixes.lua` after checking that `deadlock` exists. This lets your mod remain compatible when this mod is not installed.

### Optional dependency

Add this mod as an optional dependency in your mod's `info.json`:

```json
{
  "name": "ExampleMod",
  "version": "0.1.0",
  "title": "Example Mod",
  "author": "YourName",
  "dependencies": ["base >= 2.1", "? deadlock-beltboxes-loaders-continued"],
  "factorio_version": "2.1"
}
```

### Basic stacked item example

```lua
-- data-final-fixes.lua
if deadlock then
  deadlock.add_stack(
    "example-item",
    "__ExampleMod__/graphics/icons/example-stack.png",
    "deadlock-stacking-1",
    64
  )
end
```

If you have many items, place them in a table and loop through them.

## API reference

### `deadlock.add_stack(item_name, graphic_path, target_tech, icon_size, item_type, mipmap_levels)`

Creates a stacked version of an item, plus stacking and unstacking recipes.

| Parameter | Required | Description |
|---|---:|---|
| `item_name` | Yes | Name of the base item to stack, for example `iron-plate`. |
| `graphic_path` | No | Path to a custom stacked icon. Strongly recommended for performance and visual quality. |
| `target_tech` | No | Technology that unlocks the stacking/unstacking recipes, for example `deadlock-stacking-1`. If omitted, your own mod must handle recipe unlocks. |
| `icon_size` | No | Icon size in pixels. Defaults to `64`. |
| `item_type` | No | Prototype type. Defaults to `item`. Other supported types include `ammo`, `gun`, `tool`, `repair-tool`, `module`, `capsule`, and `rail-planner`. |
| `mipmap_levels` | No | Mipmap levels for the custom icon, only used when `graphic_path` is supplied. |

Example:

```lua
if deadlock then
  deadlock.add_stack("copper-cable", nil, "deadlock-stacking-1", 64)
end
```

When no custom icon is supplied, the mod attempts to generate a layered icon automatically from the base item. This is convenient, but custom icons are better for performance and appearance.

### `deadlock.destroy_stack(item_name)`

Removes the stacked version of an item, its related recipes, and technology unlock references.

```lua
if deadlock then
  deadlock.destroy_stack("iron-plate")
end
```

Be careful with this function. Other mods may expect a stacked item to exist. If you remove it, you are responsible for any compatibility effects.

### `deadlock.destroy_vanilla_stacks()`

Removes all vanilla stacked items and recipes created by this mod.

```lua
if deadlock then
  deadlock.destroy_vanilla_stacks()
end
```

Use this if your overhaul mod wants to rebuild the stacking list from scratch.

### `deadlock.add_tier(tier_table)`

Creates a new loader and beltbox tier for a transport belt tier.

This is useful for mods that add new belts and want matching compact loaders and beltboxes.

Example:

```lua
if deadlock then
  deadlock.add_tier({
    transport_belt      = "rapid-transport-belt",
    underground_belt    = "rapid-underground-belt",
    splitter            = "rapid-splitter",
    technology          = "logistics-4",
    order               = "d",
    colour              = {r = 0.2, g = 0.8, b = 0.2},

    loader_ingredients  = {
      {type = "item", name = "express-transport-belt-loader", amount = 1},
      {type = "item", name = "iron-gear-wheel", amount = 20},
      {type = "fluid", name = "lubricant", amount = 40},
    },
    loader_category     = "crafting-with-fluid",

    beltbox_ingredients = {
      {type = "item", name = "express-transport-belt-beltbox", amount = 1},
      {type = "item", name = "iron-plate", amount = 40},
      {type = "item", name = "iron-gear-wheel", amount = 40},
      {type = "item", name = "processing-unit", amount = 5},
    },
    beltbox_category    = "crafting-with-fluid",
    beltbox_technology  = "deadlock-stacking-4",
  })
end
```

#### `tier_table` fields

| Field | Required | Description |
|---|---:|---|
| `transport_belt` | Yes | Name of the transport belt entity. Used for speed and naming defaults. |
| `underground_belt` | Conditional | Name of the related underground belt. Required unless custom loader and beltbox ingredients are provided. |
| `splitter` | No | Related splitter entity. Currently only passed through for styling integrations. |
| `colour` | No | Tint colour table for icons and entities. Defaults to pink if omitted. |
| `technology` | Recommended | Technology that unlocks the loader recipe. |
| `order` | Recommended | Sort/order string for generated items and recipes. |
| `loader` | No | Loader entity name. Defaults to `<transport_belt>-loader`. |
| `loader_item` | No | Loader item name. Defaults to the loader entity name. |
| `loader_recipe` | No | Loader recipe name. Defaults to the loader entity name. |
| `loader_ingredients` | Conditional | Loader recipe ingredients. Required if no `underground_belt` is provided. |
| `loader_category` | No | Crafting category for the loader recipe. Defaults to the related underground belt recipe category or `crafting`. |
| `beltbox` | No | Beltbox entity name. Defaults to `<transport_belt>-beltbox`. |
| `beltbox_item` | No | Beltbox item name. Defaults to the beltbox entity name. |
| `beltbox_recipe` | No | Beltbox recipe name. Defaults to the beltbox entity name. |
| `beltbox_ingredients` | Conditional | Beltbox recipe ingredients. Required if no `underground_belt` is provided. |
| `beltbox_category` | No | Crafting category for the beltbox recipe. Defaults to the related underground belt recipe category or `crafting`. |
| `beltbox_technology` | No | Technology that unlocks the beltbox recipe and related stacked items. Defaults to the beltbox name. Vanilla tiers use `deadlock-stacking-1`, `deadlock-stacking-2`, etc. for legacy compatibility. |

## Data stage guidance

Call the API from `data-final-fixes.lua` where possible. Some calls may work earlier, but many mods modify items, recipes, and technologies across `data.lua`, `data-updates.lua`, and `data-final-fixes.lua`. Calling late gives the API the best chance of seeing final prototype data.

## Icon guidance

`deadlock.add_stack()` can auto-generate layered icons when no custom icon is provided. This is useful for compatibility, but it is not ideal.

Custom stacked icons are recommended because:

- they look better,
- they reduce layered icon complexity,
- they avoid extra render work for items that may appear in large numbers.

## Migrations and compatibility

If your mod adds stacks to technologies and later removes or changes them, your mod is responsible for migrations.

If you delete stacked items that other mods expect, your mod is responsible for handling that compatibility impact.

## Troubleshooting

If stacked items, recipes, beltboxes, or loaders are missing:

1. Check that this mod is loaded.
2. Check that your integration runs in `data-final-fixes.lua`.
3. Check the Factorio log for warnings or errors from this mod.
4. Verify that the item, belt, recipe, and technology names used by your bridge mod actually exist.

Invalid prototype names or invalid recipe/category data can stop Factorio during startup. Read the full error message; it usually points directly to the bad prototype.
