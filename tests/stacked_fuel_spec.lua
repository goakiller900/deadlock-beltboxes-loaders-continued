local failures = 0
local assertions = 0

local function deepcopy(value, seen)
	if type(value) ~= "table" then
		return value
	end
	seen = seen or {}
	if seen[value] then
		return seen[value]
	end
	local result = {}
	seen[value] = result
	for key, nested in pairs(value) do
		result[deepcopy(key, seen)] = deepcopy(nested, seen)
	end
	return setmetatable(result, getmetatable(value))
end

table.deepcopy = deepcopy

settings = {
	startup = {
		["deadlock-stack-size"] = {value = 5},
		["deadlock-stacking-batch-stacking"] = {value = false},
	},
}

data = {
	raw = {
		item = {},
		recipe = {},
		technology = {},
		["item-group"] = {},
		["item-subgroup"] = {
			beltboxes = {
				type = "item-subgroup",
				name = "beltboxes",
				group = "logistics",
			},
		},
	},
}

function data:extend(prototypes)
	for _, prototype in ipairs(prototypes) do
		self.raw[prototype.type] = self.raw[prototype.type] or {}
		self.raw[prototype.type][prototype.name] = prototype
	end
end

local messages = {}
function log(message)
	table.insert(messages, message)
end

local function expect(condition, message)
	assertions = assertions + 1
	if not condition then
		failures = failures + 1
		io.stderr:write("FAIL: " .. message .. "\n")
	end
end

local function expect_equal(actual, expected, message)
	expect(actual == expected, string.format("%s (expected %s, got %s)", message, tostring(expected), tostring(actual)))
end

local function expect_energy(item, expected, message)
	local value = tonumber(string.match(item.fuel_value or "", "^[%d%.]+"))
	expect_equal(value, expected, message)
end

local function add_item(name, properties)
	properties = properties or {}
	properties.type = properties.type or "item"
	properties.name = name
	properties.icon = properties.icon or "__base__/graphics/icons/coal.png"
	properties.icon_size = properties.icon_size or 64
	properties.stack_size = properties.stack_size or 100
	properties.subgroup = properties.subgroup or "raw-material"
	properties.order = properties.order or name
	data.raw[properties.type] = data.raw[properties.type] or {}
	data.raw[properties.type][name] = properties
	return properties
end

local function add_stack_pair(base_name, represented_count, batch_size)
	batch_size = batch_size or 1
	local stack_name = "deadlock-stack-" .. base_name
	add_item(stack_name, {stack_size = 20})
	data.raw.recipe["deadlock-stacks-stack-" .. base_name] = {
		type = "recipe",
		name = "deadlock-stacks-stack-" .. base_name,
		enabled = false,
		ingredients = {{type = "item", name = base_name, amount = represented_count * batch_size}},
		results = {{type = "item", name = stack_name, amount = batch_size}},
	}
	data.raw.recipe["deadlock-stacks-unstack-" .. base_name] = {
		type = "recipe",
		name = "deadlock-stacks-unstack-" .. base_name,
		enabled = false,
		ingredients = {{type = "item", name = stack_name, amount = batch_size}},
		results = {{type = "item", name = base_name, amount = represented_count * batch_size}},
	}
	data.raw.technology["stacking-" .. base_name] = {
		type = "technology",
		name = "stacking-" .. base_name,
		effects = {
			{type = "unlock-recipe", recipe = "deadlock-stacks-stack-" .. base_name},
			{type = "unlock-recipe", recipe = "deadlock-stacks-unstack-" .. base_name},
		},
	}
	return data.raw.item[stack_name]
end

local DBL = require("prototypes.stacked_fuel")

local function update(base_name)
	DBL.update_stacked_fuel("deadlock-stack-" .. base_name, base_name, "item")
	return data.raw.item["deadlock-stack-" .. base_name]
end

-- Matching default density: use the normal residue stack and preserve all fuel properties.
add_item("ash-match", {stack_size = 1000})
add_stack_pair("ash-match", 5)
add_item("coal-match", {
	stack_size = 50,
	fuel_value = "4MJ",
	fuel_category = "chemical",
	fuel_acceleration_multiplier = 1.2,
	fuel_top_speed_multiplier = 1.1,
	fuel_emissions_multiplier = 0.8,
	fuel_glow_color = {r = 0.2, g = 0.3, b = 0.4},
	burnt_result = "ash-match",
})
add_stack_pair("coal-match", 5)
local coal_match = update("coal-match")
expect_equal(coal_match.burnt_result, "deadlock-stack-ash-match", "matching residue density uses the normal residue stack")
expect_energy(coal_match, 20, "matching stacked fuel preserves total energy")
expect_equal(coal_match.fuel_category, "chemical", "fuel category is copied")
expect_equal(coal_match.fuel_acceleration_multiplier, 1.2, "fuel acceleration multiplier is copied")
expect_equal(coal_match.fuel_top_speed_multiplier, 1.1, "fuel top speed multiplier is copied")
expect_equal(coal_match.fuel_emissions_multiplier, 0.8, "fuel emissions multiplier is copied")
expect_equal((coal_match.fuel_glow_color or {}).g, 0.3, "fuel glow color is copied")
expect(data.raw.item["deadlock-stacked-fuel-residue-ash-match-5"] == nil, "matching density does not create a residue bundle")

-- Supported high-density mismatch: create an exact 50-count residue bundle.
add_item("ash-high", {stack_size = 1000, weight = 2})
add_stack_pair("ash-high", 64, 4)
add_item("coal-high", {
	stack_size = 50,
	fuel_value = "4MJ",
	fuel_category = "chemical",
	burnt_result = "ash-high",
})
add_stack_pair("coal-high", 50, 4)
local coal_high = update("coal-high")
local ash_50_bundle = "deadlock-stacked-fuel-residue-ash-high-50"
local ash_50_recipe = "deadlock-stacked-fuel-residue-unpack-ash-high-50"
expect_equal(coal_high.burnt_result, ash_50_bundle, "mismatched residue density uses an exact-count bundle")
expect_energy(coal_high, 200, "batch stack recipes preserve per-stack fuel energy")
expect(data.raw.item[ash_50_bundle] ~= nil, "the exact-count bundle item is generated")
expect_equal(data.raw.item[ash_50_bundle].hidden, true, "the exact-count bundle is hidden from logistics selectors")
expect(data.raw.item[ash_50_bundle].fuel_value == nil, "the exact-count bundle is not fuel")
expect(data.raw.item[ash_50_bundle].burnt_result == nil, "the exact-count bundle has no recursive burnt result")
expect_equal(data.raw.item[ash_50_bundle].weight, 100, "bundle weight represents all residue items")
expect_equal(data.raw.recipe[ash_50_recipe].ingredients[1].amount, 1, "bundle conversion consumes one bundle")
expect_equal(data.raw.recipe[ash_50_recipe].results[1].amount, 50, "bundle conversion returns the exact residue count")
expect_equal(data.raw.recipe[ash_50_recipe].enabled, true, "bundle conversion needs no technology migration")
expect_equal(data.raw.recipe[ash_50_recipe].categories[1], "crafting", "bundle conversion supports safe hand crafting")
expect_equal(data.raw.recipe[ash_50_recipe].categories[2], "unstacking", "bundle conversion supports beltboxes")

-- Multiple fuels sharing the same residue and represented count reuse one bundle.
add_item("coke-high", {
	fuel_value = "5MJ",
	fuel_category = "chemical",
	burnt_result = "ash-high",
})
add_stack_pair("coke-high", 50)
local coke_high = update("coke-high")
expect_equal(coke_high.burnt_result, ash_50_bundle, "multiple fuels reuse the deterministic exact-count bundle")

-- Residue density lower than fuel density still has an exact, hand-craftable conversion.
add_item("small-residue", {stack_size = 20})
add_stack_pair("small-residue", 20)
add_item("large-fuel", {
	fuel_value = "1MJ",
	fuel_category = "chemical",
	burnt_result = "small-residue",
})
add_stack_pair("large-fuel", 100)
local large_fuel = update("large-fuel")
local residue_100_bundle = "deadlock-stacked-fuel-residue-small-residue-100"
expect_equal(large_fuel.burnt_result, residue_100_bundle, "lower residue density uses an exact bundle")
expect_equal(data.raw.item[residue_100_bundle].stack_size, 1, "large bundles remain transportable without claiming excess inventory density")
expect_equal(data.raw.recipe["deadlock-stacked-fuel-residue-unpack-small-residue-100"].results[1].amount, 100, "lower-density residue conversion remains exact")

-- A source fuel with a different residue uses that residue generically.
add_item("spent-canister", {stack_size = 200})
add_stack_pair("spent-canister", 10)
add_item("canister-fuel", {
	fuel_value = "2MJ",
	fuel_category = "chemical",
	burnt_result = "spent-canister",
})
add_stack_pair("canister-fuel", 10)
expect_equal(update("canister-fuel").burnt_result, "deadlock-stack-spent-canister", "non-ash burnt results use their matching stack")

-- Fuels without a burnt result and non-fuels do not create residue mechanisms.
add_item("clean-fuel", {fuel_value = "3MJ", fuel_category = "chemical"})
add_stack_pair("clean-fuel", 8)
local clean_fuel = update("clean-fuel")
expect_energy(clean_fuel, 24, "fuel without a burnt result keeps stacked fuel energy")
expect(clean_fuel.burnt_result == nil, "fuel without a burnt result remains without one")
add_item("not-fuel")
add_stack_pair("not-fuel", 5)
local not_fuel = update("not-fuel")
expect(not_fuel.fuel_value == nil, "non-fuel stacked items remain non-fuel")

-- Actual recipe ratios, not prototype stack_size fields, determine represented count.
add_item("recipe-residue", {stack_size = 999})
add_stack_pair("recipe-residue", 7)
add_item("recipe-fuel", {
	stack_size = 999,
	fuel_value = "2MJ",
	fuel_category = "chemical",
	burnt_result = "recipe-residue",
})
add_stack_pair("recipe-fuel", 7)
local recipe_fuel = update("recipe-fuel")
expect_energy(recipe_fuel, 14, "modified prototype stack sizes do not override actual recipe ratios")
expect_equal(recipe_fuel.burnt_result, "deadlock-stack-recipe-residue", "modified stack sizes still match when recipe ratios match")

-- Preserve a correct result supplied by another mod.
add_item("foreign-residue", {stack_size = 100})
add_stack_pair("foreign-residue", 12)
add_item("foreign-fuel", {
	fuel_value = "1MJ",
	fuel_category = "chemical",
	burnt_result = "foreign-residue",
})
local foreign_stack = add_stack_pair("foreign-fuel", 12)
foreign_stack.burnt_result = "deadlock-stack-foreign-residue"
expect_equal(update("foreign-fuel").burnt_result, "deadlock-stack-foreign-residue", "a provably correct existing result is preserved")

-- Replace a demonstrably incorrect ordinary residue result.
add_item("wrong-residue", {stack_size = 100})
add_stack_pair("wrong-residue", 10)
add_item("wrong-fuel", {
	fuel_value = "1MJ",
	fuel_category = "chemical",
	burnt_result = "wrong-residue",
})
local wrong_stack = add_stack_pair("wrong-fuel", 10)
wrong_stack.burnt_result = "wrong-residue"
expect_equal(update("wrong-fuel").burnt_result, "deadlock-stack-wrong-residue", "one ordinary residue is replaced when it underproduces")

-- No normal residue stack: create an exact bundle on demand.
add_item("unstacked-residue", {stack_size = 100})
add_item("orphan-fuel", {
	fuel_value = "1MJ",
	fuel_category = "chemical",
	burnt_result = "unstacked-residue",
})
add_stack_pair("orphan-fuel", 6)
expect_equal(update("orphan-fuel").burnt_result, "deadlock-stacked-fuel-residue-unstacked-residue-6", "an unstackable residue gets an exact bundle")

-- A density-matching residue stack with no usable conversion is not returned.
add_item("locked-residue", {stack_size = 100})
add_stack_pair("locked-residue", 6)
data.raw.technology["stacking-locked-residue"] = nil
add_item("locked-fuel", {
	fuel_value = "1MJ",
	fuel_category = "chemical",
	burnt_result = "locked-residue",
})
add_stack_pair("locked-fuel", 6)
expect_equal(update("locked-fuel").burnt_result, "deadlock-stacked-fuel-residue-locked-residue-6", "an unusable normal unstack recipe uses an enabled exact bundle")

-- If a normal residue stack becomes available later, prefer it over our bundle.
add_item("late-residue", {stack_size = 100})
add_item("late-fuel", {
	fuel_value = "1MJ",
	fuel_category = "chemical",
	burnt_result = "late-residue",
})
add_stack_pair("late-fuel", 6)
local late_fuel = update("late-fuel")
expect_equal(late_fuel.burnt_result, "deadlock-stacked-fuel-residue-late-residue-6", "missing residue stack initially uses a bundle")
add_stack_pair("late-residue", 6)
expect_equal(update("late-fuel").burnt_result, "deadlock-stack-late-residue", "a later matching normal residue stack is preferred")

-- Fractional represented counts cannot be converted per burnt item and disable fuel safely.
add_item("fractional-residue", {stack_size = 100})
add_item("fractional-fuel", {
	fuel_value = "1MJ",
	fuel_category = "chemical",
	burnt_result = "fractional-residue",
})
local fractional_stack = add_stack_pair("fractional-fuel", 5)
data.raw.recipe["deadlock-stacks-stack-fractional-fuel"].results[1].amount = 2
data.raw.recipe["deadlock-stacks-unstack-fractional-fuel"].ingredients[1].amount = 2
fractional_stack.fuel_value = "999MJ"
fractional_stack.fuel_category = "chemical"
local fractional_result = update("fractional-fuel")
expect(fractional_result.fuel_value == nil, "fractional residue quantities disable stacked fuel")
expect(fractional_result.fuel_category == nil, "fractional fallback removes the fuel category")

-- Unknown third-party burnt results are not overwritten; unsafe fuel behavior is disabled.
add_item("unknown-residue", {stack_size = 100})
add_stack_pair("unknown-residue", 9)
add_item("unknown-result", {stack_size = 1})
add_item("unknown-fuel", {
	fuel_value = "1MJ",
	fuel_category = "chemical",
	burnt_result = "unknown-residue",
})
local unknown_stack = add_stack_pair("unknown-fuel", 9)
unknown_stack.burnt_result = "unknown-result"
local unknown_fuel = update("unknown-fuel")
expect_equal(unknown_fuel.burnt_result, "unknown-result", "an unproven third-party result is not overwritten")
expect(unknown_fuel.fuel_value == nil, "an unproven third-party result disables stacked fuel")

-- Prototype-name collisions fail closed without overwriting the colliding item.
add_item("collision-residue", {stack_size = 100})
add_stack_pair("collision-residue", 20)
add_item("collision-fuel", {
	fuel_value = "1MJ",
	fuel_category = "chemical",
	burnt_result = "collision-residue",
})
add_stack_pair("collision-fuel", 10)
local collision_name = "deadlock-stacked-fuel-residue-collision-residue-10"
local colliding_item = add_item(collision_name, {stack_size = 123})
local collision_fuel = update("collision-fuel")
expect(collision_fuel.fuel_value == nil, "an incompatible bundle-name collision disables stacked fuel")
expect_equal(data.raw.item[collision_name], colliding_item, "an incompatible colliding prototype is not overwritten")

-- Stack and unstack recipe disagreement cannot prove quantity and fails closed.
add_item("disagree-residue", {stack_size = 100})
add_stack_pair("disagree-residue", 5)
add_item("disagree-fuel", {
	fuel_value = "1MJ",
	fuel_category = "chemical",
	burnt_result = "disagree-residue",
})
add_stack_pair("disagree-fuel", 5)
data.raw.recipe["deadlock-stacks-unstack-disagree-fuel"].results[1].amount = 6
local disagree_fuel = update("disagree-fuel")
expect(disagree_fuel.fuel_value == nil, "disagreeing stack and unstack recipes disable stacked fuel")

if failures > 0 then
	for _, message in ipairs(messages) do
		io.stderr:write(message .. "\n")
	end
	error(string.format("%d of %d assertions failed", failures, assertions))
end

print(string.format("PASS: %d stacked-fuel assertions", assertions))
