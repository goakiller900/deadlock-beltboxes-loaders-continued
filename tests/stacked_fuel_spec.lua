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
		character = {
			character = {
				type = "character",
				name = "character",
				crafting_categories = {"crafting", "unstacking"},
			},
		},
		furnace = {
			beltbox = {
				type = "furnace",
				name = "beltbox",
				crafting_categories = {"stacking", "unstacking"},
			},
		},
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

local DBL

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

local function add_stack_pair(base_name, batch_size)
	batch_size = batch_size or 1
	local source = data.raw.item[base_name]
	local represented_count = math.min(DBL.STACK_SIZE, source.stack_size)
	local stack_name = "deadlock-stack-" .. base_name
	add_item(stack_name, {stack_size = 20})
	data.raw.recipe["deadlock-stacks-stack-" .. base_name] = {
		type = "recipe",
		name = "deadlock-stacks-stack-" .. base_name,
		categories = {"stacking"},
		enabled = false,
		ingredients = {{type = "item", name = base_name, amount = represented_count * batch_size}},
		results = {{type = "item", name = stack_name, amount = batch_size}},
	}
	data.raw.recipe["deadlock-stacks-unstack-" .. base_name] = {
		type = "recipe",
		name = "deadlock-stacks-unstack-" .. base_name,
		categories = {"unstacking"},
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

DBL = require("prototypes.stacked_fuel")

local function update(base_name)
	DBL.update_stacked_fuel("deadlock-stack-" .. base_name, base_name, "item")
	return data.raw.item["deadlock-stack-" .. base_name]
end

-- Matching default density: use the normal residue stack and preserve all fuel properties.
DBL.STACK_SIZE = 5
add_item("ash-match", {stack_size = 1000})
add_stack_pair("ash-match")
add_item("coal-match", {
	stack_size = 50,
	fuel_value = "4MJ",
	fuel_category = "chemical",
	fuel_acceleration_multiplier = 1.2,
	fuel_top_speed_multiplier = 1.1,
	fuel_emissions_multiplier = 0.8,
	fuel_acceleration_multiplier_quality_bonus = 0.06,
	fuel_top_speed_multiplier_quality_bonus = 0.03,
	fuel_glow_color = {r = 0.2, g = 0.3, b = 0.4},
	burnt_result = "ash-match",
})
add_stack_pair("coal-match")
local coal_match = update("coal-match")
expect_equal(coal_match.burnt_result, "deadlock-stack-ash-match", "matching residue density uses the normal residue stack")
expect_energy(coal_match, 20, "matching stacked fuel preserves total energy")
expect_equal(coal_match.fuel_category, "chemical", "fuel category is copied")
expect_equal(coal_match.fuel_acceleration_multiplier, 1.2, "fuel acceleration multiplier is copied")
expect_equal(coal_match.fuel_top_speed_multiplier, 1.1, "fuel top speed multiplier is copied")
expect_equal(coal_match.fuel_emissions_multiplier, 0.8, "fuel emissions multiplier is copied")
expect_equal(coal_match.fuel_acceleration_multiplier_quality_bonus, 0.06, "fuel acceleration quality bonus is copied")
expect_equal(coal_match.fuel_top_speed_multiplier_quality_bonus, 0.03, "fuel top speed quality bonus is copied")
expect_equal((coal_match.fuel_glow_color or {}).g, 0.3, "fuel glow color is copied")
expect(data.raw.item["deadlock-stacked-fuel-residue-ash-match-5"] == nil, "matching density does not create a residue bundle")

-- Supported high-density mismatch: create an exact 50-count residue bundle.
DBL.STACK_SIZE = 64
DBL.RECIPE_MULTIPLIER = 4
add_item("ash-high", {stack_size = 1000, weight = 2})
add_stack_pair("ash-high", 4)
add_item("coal-high", {
	stack_size = 50,
	fuel_value = "4MJ",
	fuel_category = "chemical",
	burnt_result = "ash-high",
})
add_stack_pair("coal-high", 4)
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
expect_equal(#data.raw.recipe[ash_50_recipe].categories, 1, "bundle conversion has one focused category")
expect_equal(data.raw.recipe[ash_50_recipe].categories[1], "unstacking", "bundle conversion supports beltboxes")
expect_equal(data.raw.recipe[ash_50_recipe].hidden, true, "bundle recipe is hidden")
expect_equal(data.raw.recipe[ash_50_recipe].hidden_in_factoriopedia, true, "bundle recipe is hidden from Factoriopedia")
expect_equal(data.raw.recipe[ash_50_recipe].hide_from_player_crafting, true, "bundle recipe is hidden from player crafting")
expect_equal(data.raw.recipe[ash_50_recipe].auto_recycle, false, "bundle recipe is not auto-recycled")
expect_equal(data.raw.item[ash_50_bundle].auto_recycle, false, "bundle item is not auto-recycled")

-- Multiple fuels sharing the same residue and represented count reuse one bundle.
add_item("coke-high", {
	stack_size = 50,
	fuel_value = "5MJ",
	fuel_category = "chemical",
	burnt_result = "ash-high",
})
add_stack_pair("coke-high", 4)
local coke_high = update("coke-high")
expect_equal(coke_high.burnt_result, ash_50_bundle, "multiple fuels reuse the deterministic exact-count bundle")
local coal_high_ratio = DBL.get_stack_represented_ratio("coal-high", "item")
expect_equal(coal_high_ratio and coal_high_ratio.numerator, 50, "the represented count respects the source item stack-size cap")
DBL.RECIPE_MULTIPLIER = 1

-- Residue density lower than fuel density still has an exact unstacking conversion.
DBL.STACK_SIZE = 100
add_item("small-residue", {stack_size = 20})
add_stack_pair("small-residue")
add_item("large-fuel", {
	stack_size = 100,
	fuel_value = "1MJ",
	fuel_category = "chemical",
	burnt_result = "small-residue",
})
add_stack_pair("large-fuel")
local large_fuel = update("large-fuel")
local residue_100_bundle = "deadlock-stacked-fuel-residue-small-residue-100"
expect_equal(large_fuel.burnt_result, residue_100_bundle, "lower residue density uses an exact bundle")
expect_equal(data.raw.item[residue_100_bundle].stack_size, 1, "large bundles remain transportable without claiming excess inventory density")
expect_equal(data.raw.recipe["deadlock-stacked-fuel-residue-unpack-small-residue-100"].results[1].amount, 100, "lower-density residue conversion remains exact")

-- A source fuel with a different residue uses that residue generically.
DBL.STACK_SIZE = 10
add_item("spent-canister", {stack_size = 200})
add_stack_pair("spent-canister")
add_item("canister-fuel", {
	fuel_value = "2MJ",
	fuel_category = "chemical",
	burnt_result = "spent-canister",
})
add_stack_pair("canister-fuel")
expect_equal(update("canister-fuel").burnt_result, "deadlock-stack-spent-canister", "non-ash burnt results use their matching stack")

-- Fuels without a burnt result and non-fuels do not create residue mechanisms.
DBL.STACK_SIZE = 8
add_item("clean-fuel", {fuel_value = "3MJ", fuel_category = "chemical"})
add_stack_pair("clean-fuel")
local clean_fuel = update("clean-fuel")
expect_energy(clean_fuel, 24, "fuel without a burnt result keeps stacked fuel energy")
expect(clean_fuel.burnt_result == nil, "fuel without a burnt result remains without one")
add_item("not-fuel")
add_stack_pair("not-fuel")
local not_fuel = update("not-fuel")
expect(not_fuel.fuel_value == nil, "non-fuel stacked items remain non-fuel")

-- Repository density, not the stacked prototype stack_size, determines represented count.
DBL.STACK_SIZE = 7
add_item("recipe-residue", {stack_size = 999})
add_stack_pair("recipe-residue")
add_item("recipe-fuel", {
	stack_size = 999,
	fuel_value = "2MJ",
	fuel_category = "chemical",
	burnt_result = "recipe-residue",
})
local recipe_stack = add_stack_pair("recipe-fuel")
recipe_stack.stack_size = 3
local recipe_fuel = update("recipe-fuel")
expect_energy(recipe_fuel, 14, "modified prototype stack sizes do not override actual recipe ratios")
expect_equal(recipe_fuel.burnt_result, "deadlock-stack-recipe-residue", "modified stack sizes still match when recipe ratios match")

-- Preserve a correct result supplied by another mod.
DBL.STACK_SIZE = 12
add_item("foreign-residue", {stack_size = 100})
add_stack_pair("foreign-residue")
add_item("foreign-fuel", {
	fuel_value = "1MJ",
	fuel_category = "chemical",
	burnt_result = "foreign-residue",
})
local foreign_stack = add_stack_pair("foreign-fuel")
foreign_stack.burnt_result = "deadlock-stack-foreign-residue"
expect_equal(update("foreign-fuel").burnt_result, "deadlock-stack-foreign-residue", "a provably correct existing result is preserved")

-- Replace a demonstrably incorrect ordinary residue result.
DBL.STACK_SIZE = 10
add_item("wrong-residue", {stack_size = 100})
add_stack_pair("wrong-residue")
add_item("wrong-fuel", {
	fuel_value = "1MJ",
	fuel_category = "chemical",
	burnt_result = "wrong-residue",
})
local wrong_stack = add_stack_pair("wrong-fuel")
wrong_stack.burnt_result = "wrong-residue"
expect_equal(update("wrong-fuel").burnt_result, "deadlock-stack-wrong-residue", "one ordinary residue is replaced when it underproduces")

-- No normal residue stack: create an exact bundle on demand.
DBL.STACK_SIZE = 6
add_item("unstacked-residue", {stack_size = 100})
add_item("orphan-fuel", {
	fuel_value = "1MJ",
	fuel_category = "chemical",
	burnt_result = "unstacked-residue",
})
add_stack_pair("orphan-fuel")
expect_equal(update("orphan-fuel").burnt_result, "deadlock-stacked-fuel-residue-unstacked-residue-6", "an unstackable residue gets an exact bundle")

-- A density-matching residue stack with no usable conversion is not returned.
add_item("locked-residue", {stack_size = 100})
add_stack_pair("locked-residue")
data.raw.technology["stacking-locked-residue"] = nil
add_item("locked-fuel", {
	fuel_value = "1MJ",
	fuel_category = "chemical",
	burnt_result = "locked-residue",
})
add_stack_pair("locked-fuel")
expect_equal(update("locked-fuel").burnt_result, "deadlock-stacked-fuel-residue-locked-residue-6", "an unusable normal unstack recipe uses an enabled exact bundle")

-- If a normal residue stack becomes available later, prefer it over our bundle.
add_item("late-residue", {stack_size = 100})
add_item("late-fuel", {
	fuel_value = "1MJ",
	fuel_category = "chemical",
	burnt_result = "late-residue",
})
add_stack_pair("late-fuel")
local late_fuel = update("late-fuel")
local late_bundle = "deadlock-stacked-fuel-residue-late-residue-6"
local late_bundle_recipe = "deadlock-stacked-fuel-residue-unpack-late-residue-6"
expect_equal(late_fuel.burnt_result, late_bundle, "missing residue stack initially uses a bundle")
local retained_bundle_item = data.raw.item[late_bundle]
local retained_bundle_recipe = data.raw.recipe[late_bundle_recipe]
add_stack_pair("late-residue")
expect_equal(update("late-fuel").burnt_result, "deadlock-stack-late-residue", "a later matching normal residue stack is preferred")
expect(data.raw.item[late_bundle] ~= nil, "the old hidden bundle item remains available")
expect(data.raw.recipe[late_bundle_recipe] ~= nil, "the old hidden bundle recipe remains available")
expect(data.raw.item[late_bundle].hidden, "the retained bundle item stays hidden")
expect(data.raw.recipe[late_bundle_recipe].hidden, "the retained bundle recipe stays hidden")
expect_equal(update("late-fuel").burnt_result, "deadlock-stack-late-residue", "a retained old bundle does not affect the selected normal residue")
data.raw.recipe["deadlock-stacks-unstack-late-residue"].categories = {"unused-test-category"}
expect_equal(update("late-fuel").burnt_result, late_bundle, "the deterministic bundle is reused when the normal conversion becomes unavailable")
expect_equal(data.raw.item[late_bundle], retained_bundle_item, "bundle reuse does not replace the retained item prototype")
expect_equal(data.raw.recipe[late_bundle_recipe], retained_bundle_recipe, "bundle reuse does not replace the retained recipe prototype")

-- Noncanonical recipe amounts cannot prove represented count and disable fuel safely.
DBL.STACK_SIZE = 5
add_item("fractional-residue", {stack_size = 100})
add_item("fractional-fuel", {
	fuel_value = "1MJ",
	fuel_category = "chemical",
	burnt_result = "fractional-residue",
})
local fractional_stack = add_stack_pair("fractional-fuel")
data.raw.recipe["deadlock-stacks-stack-fractional-fuel"].results[1].amount = 2
data.raw.recipe["deadlock-stacks-unstack-fractional-fuel"].ingredients[1].amount = 2
fractional_stack.fuel_value = "999MJ"
fractional_stack.fuel_category = "chemical"
local fractional_result = update("fractional-fuel")
expect(fractional_result.fuel_value == nil, "noncanonical recipe quantities disable stacked fuel")
expect(fractional_result.fuel_category == nil, "noncanonical recipe fallback removes the fuel category")
expect(fractional_result.burnt_result == nil, "noncanonical recipe fallback removes the burnt result")

-- Unknown third-party burnt results are not overwritten; unsafe fuel behavior is disabled.
DBL.STACK_SIZE = 9
add_item("unknown-residue", {stack_size = 100})
add_stack_pair("unknown-residue")
add_item("unknown-result", {stack_size = 1})
add_item("unknown-fuel", {
	fuel_value = "1MJ",
	fuel_category = "chemical",
	burnt_result = "unknown-residue",
})
local unknown_stack = add_stack_pair("unknown-fuel")
unknown_stack.burnt_result = "unknown-result"
local unknown_fuel = update("unknown-fuel")
expect(unknown_fuel.burnt_result == nil, "an unproven third-party result is removed")
expect(unknown_fuel.fuel_value == nil, "an unproven third-party result disables stacked fuel")

-- Prototype-name collisions fail closed without overwriting the colliding item.
DBL.STACK_SIZE = 20
add_item("collision-residue", {stack_size = 100})
add_stack_pair("collision-residue")
add_item("collision-fuel", {
	stack_size = 10,
	fuel_value = "1MJ",
	fuel_category = "chemical",
	burnt_result = "collision-residue",
})
add_stack_pair("collision-fuel")
local collision_name = "deadlock-stacked-fuel-residue-collision-residue-10"
local colliding_item = add_item(collision_name, {stack_size = 123})
local collision_fuel = update("collision-fuel")
expect(collision_fuel.fuel_value == nil, "an incompatible bundle-name collision disables stacked fuel")
expect_equal(data.raw.item[collision_name], colliding_item, "an incompatible colliding prototype is not overwritten")

add_item("recipe-collision-residue", {stack_size = 100})
add_stack_pair("recipe-collision-residue")
add_item("recipe-collision-fuel", {
	stack_size = 10,
	fuel_value = "1MJ",
	fuel_category = "chemical",
	burnt_result = "recipe-collision-residue",
})
add_stack_pair("recipe-collision-fuel")
local colliding_recipe_name = "deadlock-stacked-fuel-residue-unpack-recipe-collision-residue-10"
local colliding_recipe = {
	type = "recipe",
	name = colliding_recipe_name,
	categories = {"crafting"},
	enabled = true,
	ingredients = {{type = "item", name = "recipe-collision-residue", amount = 1}},
	results = {{type = "item", name = "recipe-collision-residue", amount = 1}},
}
data.raw.recipe[colliding_recipe_name] = colliding_recipe
expect(update("recipe-collision-fuel").fuel_value == nil, "an incompatible bundle-recipe collision disables stacked fuel")
expect_equal(data.raw.recipe[colliding_recipe_name], colliding_recipe, "an incompatible colliding recipe is not overwritten")

-- Stack and unstack recipe disagreement cannot prove quantity and fails closed.
DBL.STACK_SIZE = 5
add_item("disagree-residue", {stack_size = 100})
add_stack_pair("disagree-residue")
add_item("disagree-fuel", {
	fuel_value = "1MJ",
	fuel_category = "chemical",
	burnt_result = "disagree-residue",
})
add_stack_pair("disagree-fuel")
data.raw.recipe["deadlock-stacks-unstack-disagree-fuel"].results[1].amount = 6
local disagree_fuel = update("disagree-fuel")
expect(disagree_fuel.fuel_value == nil, "disagreeing stack and unstack recipes disable stacked fuel")

-- Every supported high density uses the configured Deadlock density, not an inferred recipe ratio.
for _, density in ipairs({4, 5, 10, 20, 50, 64, 100, 128}) do
	DBL.STACK_SIZE = density
	local name = "density-fuel-" .. density
	add_item(name, {
		stack_size = 1000,
		fuel_value = "0.25MJ",
		fuel_category = "chemical",
	})
	add_stack_pair(name)
	local ratio = DBL.get_stack_represented_ratio(name, "item")
	expect_equal(ratio and ratio.numerator, density, "represented ratio uses configured density " .. density)
	expect_equal(ratio and ratio.denominator, 1, "represented ratio remains integral at density " .. density)
	expect_energy(update(name), density * 0.25, "fuel energy is exact at density " .. density)
end

-- Official decimal Energy notation, SI prefixes, and surrounding whitespace are preserved.
DBL.STACK_SIZE = 4
add_item("decimal-kilojoule-fuel", {
	fuel_value = " 0.25 kJ ",
	fuel_category = "chemical",
})
add_stack_pair("decimal-kilojoule-fuel")
expect_equal(update("decimal-kilojoule-fuel").fuel_value, "1kJ", "decimal kJ with whitespace is multiplied exactly")
add_item("leading-decimal-fuel", {
	fuel_value = ".5MJ",
	fuel_category = "chemical",
})
add_stack_pair("leading-decimal-fuel")
expect_equal(update("leading-decimal-fuel").fuel_value, "2MJ", "leading-decimal MJ is multiplied exactly")
add_item("unsupported-energy-fuel", {
	fuel_value = "1bananas",
	fuel_category = "chemical",
})
add_stack_pair("unsupported-energy-fuel")
expect(update("unsupported-energy-fuel").fuel_value == nil, "undocumented energy units fail closed")

-- Late source updates clear stale properties, burnt results, and removed fuel behavior.
DBL.STACK_SIZE = 5
add_item("mutable-residue", {stack_size = 100})
add_stack_pair("mutable-residue")
local mutable_source = add_item("mutable-fuel", {
	fuel_value = "2MJ",
	fuel_category = "chemical",
	fuel_acceleration_multiplier = 1.4,
	fuel_acceleration_multiplier_quality_bonus = 0.12,
	burnt_result = "mutable-residue",
})
add_stack_pair("mutable-fuel")
local mutable_stack = update("mutable-fuel")
expect_equal(mutable_stack.burnt_result, "deadlock-stack-mutable-residue", "initial mutable residue is synchronized")
mutable_source.fuel_value = "3MJ"
mutable_source.fuel_acceleration_multiplier = nil
mutable_source.fuel_acceleration_multiplier_quality_bonus = nil
mutable_source.burnt_result = nil
mutable_stack.fuel_top_speed_multiplier = 99
expect_equal(update("mutable-fuel").fuel_value, "15MJ", "late source fuel-value changes are synchronized")
expect(mutable_stack.fuel_acceleration_multiplier == nil, "removed acceleration multiplier is cleared")
expect(mutable_stack.fuel_acceleration_multiplier_quality_bonus == nil, "removed quality bonus is cleared")
expect(mutable_stack.fuel_top_speed_multiplier == nil, "unrelated stale fuel property is cleared")
expect(mutable_stack.burnt_result == nil, "removed source burnt result is cleared")
mutable_source.fuel_value = nil
mutable_stack.burnt_result = "mutable-residue"
update("mutable-fuel")
expect(mutable_stack.fuel_value == nil, "source fuel removal clears stacked fuel value")
expect(mutable_stack.fuel_category == nil, "source fuel removal clears stacked fuel category")
expect(mutable_stack.burnt_result == nil, "source fuel removal clears stale burnt result")
data.raw.item["mutable-fuel"] = nil
mutable_stack.fuel_value = "99MJ"
mutable_stack.fuel_category = "chemical"
update("mutable-fuel")
expect(mutable_stack.fuel_value == nil, "deleted source prototype clears stacked fuel behavior")

add_item("changed-residue-a")
add_item("changed-residue-b")
local changed_residue_source = add_item("changed-residue-fuel", {
	fuel_value = "1MJ",
	fuel_category = "chemical",
	burnt_result = "changed-residue-a",
})
add_stack_pair("changed-residue-fuel")
local changed_residue_stack = update("changed-residue-fuel")
local changed_bundle_a = "deadlock-stacked-fuel-residue-changed-residue-a-5"
local changed_bundle_b = "deadlock-stacked-fuel-residue-changed-residue-b-5"
expect_equal(changed_residue_stack.burnt_result, changed_bundle_a, "initial generated residue bundle is synchronized")
changed_residue_source.burnt_result = "changed-residue-b"
expect_equal(update("changed-residue-fuel").burnt_result, changed_bundle_b, "late source burnt-result changes are synchronized")
expect(data.raw.item[changed_bundle_a] ~= nil, "the obsolete generated residue bundle remains hidden")
expect_equal(update("changed-residue-fuel").burnt_result, changed_bundle_b, "an obsolete retained bundle does not affect the current result")

-- Source stack-size changes invalidate stale recipes; stacked item capacity changes do not.
DBL.STACK_SIZE = 10
local resized_source = add_item("resized-source-fuel", {
	stack_size = 10,
	fuel_value = "1MJ",
	fuel_category = "chemical",
})
local resized_stack = add_stack_pair("resized-source-fuel")
resized_stack.stack_size = 999
expect_energy(update("resized-source-fuel"), 10, "stacked prototype stack_size does not define represented count")
resized_source.stack_size = 4
expect(update("resized-source-fuel").fuel_value == nil, "source stack-size changes with stale recipes fail closed")

-- Residue stack-size changes invalidate the normal residue conversion and use an exact bundle.
DBL.STACK_SIZE = 10
local resized_residue = add_item("resized-residue", {stack_size = 10})
add_stack_pair("resized-residue")
add_item("resized-residue-fuel", {
	stack_size = 10,
	fuel_value = "1MJ",
	fuel_category = "chemical",
	burnt_result = "resized-residue",
})
local resized_residue_stack = add_stack_pair("resized-residue-fuel")
expect_equal(update("resized-residue-fuel").burnt_result, "deadlock-stack-resized-residue", "initial residue conversion matches")
resized_residue.stack_size = 4
resized_residue_stack.burnt_result = nil
expect_equal(update("resized-residue-fuel").burnt_result, "deadlock-stacked-fuel-residue-resized-residue-10", "changed residue density uses an exact bundle")

-- A custom third-party result is preserved only when its deterministic conversion is exact.
DBL.STACK_SIZE = 5
add_item("third-party-residue")
add_item("third-party-bundle", {stack_size = 20})
data.raw.recipe["third-party-unpack"] = {
	type = "recipe",
	name = "third-party-unpack",
	categories = {"crafting"},
	enabled = true,
	ingredients = {{type = "item", name = "third-party-bundle", amount = 1}},
	results = {{type = "item", name = "third-party-residue", amount = 5}},
}
add_item("third-party-fuel", {
	fuel_value = "1MJ",
	fuel_category = "chemical",
	burnt_result = "third-party-residue",
})
local third_party_stack = add_stack_pair("third-party-fuel")
third_party_stack.burnt_result = "third-party-bundle"
expect_equal(update("third-party-fuel").burnt_result, "third-party-bundle", "exact third-party residue bundle is preserved")

add_item("ambiguous-residue")
add_item("ambiguous-bundle")
add_item("ambiguous-extra")
data.raw.recipe["ambiguous-unpack"] = {
	type = "recipe",
	name = "ambiguous-unpack",
	categories = {"crafting"},
	enabled = true,
	ingredients = {{type = "item", name = "ambiguous-bundle", amount = 1}},
	results = {
		{type = "item", name = "ambiguous-residue", amount = 5},
		{type = "item", name = "ambiguous-extra", amount = 1},
	},
}
add_item("ambiguous-fuel", {
	fuel_value = "1MJ",
	fuel_category = "chemical",
	burnt_result = "ambiguous-residue",
})
local ambiguous_stack = add_stack_pair("ambiguous-fuel")
ambiguous_stack.burnt_result = "ambiguous-bundle"
local ambiguous_fuel = update("ambiguous-fuel")
expect(ambiguous_fuel.fuel_value == nil, "third-party conversion with unrelated output is rejected")
expect(ambiguous_fuel.burnt_result == nil, "rejected third-party burnt result is cleared")

-- Canonical recipes reject unrelated entries, fluids, probability fields, arbitrary same ratios, and disagreeing variants.
local invalid_recipe_index = 0
local function expect_invalid_stack_recipe(label, mutate)
	invalid_recipe_index = invalid_recipe_index + 1
	DBL.STACK_SIZE = 5
	local name = "invalid-recipe-fuel-" .. invalid_recipe_index
	add_item(name, {fuel_value = "1MJ", fuel_category = "chemical"})
	add_stack_pair(name)
	mutate(
		data.raw.recipe["deadlock-stacks-stack-" .. name],
		data.raw.recipe["deadlock-stacks-unstack-" .. name]
	)
	expect(update(name).fuel_value == nil, label)
end

add_item("unrelated-recipe-item")
expect_invalid_stack_recipe("unrelated stack ingredients are rejected", function(stack_recipe)
	table.insert(stack_recipe.ingredients, {type = "item", name = "unrelated-recipe-item", amount = 1})
end)
expect_invalid_stack_recipe("unrelated stack products are rejected", function(stack_recipe)
	table.insert(stack_recipe.results, {type = "item", name = "unrelated-recipe-item", amount = 1})
end)
expect_invalid_stack_recipe("fluid ingredients are rejected", function(stack_recipe)
	table.insert(stack_recipe.ingredients, {type = "fluid", name = "water", amount = 1})
end)
expect_invalid_stack_recipe("fluid products are rejected", function(_, unstack_recipe)
	table.insert(unstack_recipe.results, {type = "fluid", name = "water", amount = 1})
end)
expect_invalid_stack_recipe("probability fields are rejected even when probability is one", function(stack_recipe)
	stack_recipe.results[1].probability = 1
end)
expect_invalid_stack_recipe("recipes restricted to normal quality are rejected", function(stack_recipe)
	stack_recipe.can_set_quality = false
end)
expect_invalid_stack_recipe("quality-changing recipe products are rejected", function(_, unstack_recipe)
	unstack_recipe.results[1].quality_change = 1
end)
expect_invalid_stack_recipe("arbitrary recipes are rejected even when their ratios agree", function(stack_recipe, unstack_recipe)
	stack_recipe.ingredients[1].amount = 10
	stack_recipe.results[1].amount = 2
	unstack_recipe.ingredients[1].amount = 2
	unstack_recipe.results[1].amount = 10
end)
expect_invalid_stack_recipe("disagreeing recipe variants are rejected", function(stack_recipe)
	stack_recipe.normal = table.deepcopy(stack_recipe)
	stack_recipe.normal.ingredients[1].amount = 6
end)

DBL.STACK_SIZE = 5
add_item("agreeing-variant-fuel", {fuel_value = "1MJ", fuel_category = "chemical"})
add_stack_pair("agreeing-variant-fuel")
local agreeing_stack_recipe = data.raw.recipe["deadlock-stacks-stack-agreeing-variant-fuel"]
local agreeing_unstack_recipe = data.raw.recipe["deadlock-stacks-unstack-agreeing-variant-fuel"]
agreeing_stack_recipe.normal = table.deepcopy(agreeing_stack_recipe)
agreeing_unstack_recipe.expensive = table.deepcopy(agreeing_unstack_recipe)
expect_energy(update("agreeing-variant-fuel"), 5, "agreeing recipe variants remain valid")

-- Disabled technology unlocks do not make a residue recipe usable.
DBL.STACK_SIZE = 5
add_item("disabled-tech-residue")
add_stack_pair("disabled-tech-residue")
data.raw.technology["stacking-disabled-tech-residue"].enabled = false
add_item("disabled-tech-fuel", {
	fuel_value = "1MJ",
	fuel_category = "chemical",
	burnt_result = "disabled-tech-residue",
})
add_stack_pair("disabled-tech-fuel")
expect_equal(update("disabled-tech-fuel").burnt_result, "deadlock-stacked-fuel-residue-disabled-tech-residue-5", "disabled technology does not make normal residue conversion usable")

add_item("unavailable-category-residue")
add_stack_pair("unavailable-category-residue")
data.raw.recipe["deadlock-stacks-unstack-unavailable-category-residue"].categories = {"unused-test-category"}
add_item("unavailable-category-fuel", {
	fuel_value = "1MJ",
	fuel_category = "chemical",
	burnt_result = "unavailable-category-residue",
})
add_stack_pair("unavailable-category-fuel")
expect_equal(update("unavailable-category-fuel").burnt_result, "deadlock-stacked-fuel-residue-unavailable-category-residue-5", "unavailable recipe category does not make normal residue conversion usable")

-- Missing residue prototypes and icons fail closed.
add_item("missing-residue-fuel", {
	fuel_value = "1MJ",
	fuel_category = "chemical",
	burnt_result = "does-not-exist",
})
add_stack_pair("missing-residue-fuel")
expect(update("missing-residue-fuel").fuel_value == nil, "missing residue prototype disables fuel")
local iconless_residue = add_item("iconless-residue")
iconless_residue.icon = nil
iconless_residue.icons = nil
add_item("iconless-fuel", {
	fuel_value = "1MJ",
	fuel_category = "chemical",
	burnt_result = "iconless-residue",
})
add_stack_pair("iconless-fuel")
expect(update("iconless-fuel").fuel_value == nil, "missing residue icon disables fuel")

-- Current ItemPrototype descendants are found, and generated bundles are recognized structurally.
add_item("platform-residue", {
	type = "space-platform-starter-pack",
	stack_size = 1,
})
add_item("platform-fuel", {
	fuel_value = "1MJ",
	fuel_category = "chemical",
	burnt_result = "platform-residue",
})
add_stack_pair("platform-fuel")
local platform_fuel = update("platform-fuel")
expect_equal(platform_fuel.burnt_result, "deadlock-stacked-fuel-residue-platform-residue-5", "space-platform starter-pack residue is supported")
expect(DBL.is_exact_residue_bundle(platform_fuel.burnt_result), "generated bundle is recognized after structural creation")
expect(not DBL.is_exact_residue_bundle("deadlock-stacked-fuel-residue-made-up-5"), "bundle prefix alone is not trusted")
expect(data.raw.item[platform_fuel.burnt_result].allow_decomposition == nil, "bundle item has no invalid recipe-only field")
local platform_recipe = data.raw.recipe["deadlock-stacked-fuel-residue-unpack-platform-residue-5"]
expect(platform_recipe.group == nil, "bundle recipe has no invalid group field")
expect_equal(update("platform-fuel").burnt_result, platform_fuel.burnt_result, "repeated bundle synchronization is idempotent")

if failures > 0 then
	for _, message in ipairs(messages) do
		io.stderr:write(message .. "\n")
	end
	error(string.format("%d of %d assertions failed", failures, assertions))
end

print(string.format("PASS: %d stacked-fuel assertions", assertions))
