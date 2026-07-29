local failures = 0
local assertions = 0

local function deepcopy(value, seen)
	if type(value) ~= "table" then return value end
	seen = seen or {}
	if seen[value] then return seen[value] end
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
		capsule = {},
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

function data:extend(prototypes_to_add)
	for _, prototype in ipairs(prototypes_to_add) do
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
	expect(actual == expected, string.format(
		"%s (expected %s, got %s)",
		message,
		tostring(expected),
		tostring(actual)
	))
end

local function add_item(name, properties)
	properties = properties or {}
	properties.type = properties.type or "item"
	properties.name = name
	properties.icon = properties.icon or "__base__/graphics/icons/spoilage.png"
	properties.icon_size = properties.icon_size or 64
	properties.stack_size = properties.stack_size or 100
	properties.subgroup = properties.subgroup or "raw-material"
	properties.order = properties.order or name
	data.raw[properties.type] = data.raw[properties.type] or {}
	data.raw[properties.type][name] = properties
	return properties
end

local function add_stack_pair(base_name, item_type)
	item_type = item_type or "item"
	local source = data.raw[item_type][base_name]
	local represented_count = math.min(DBL.STACK_SIZE, source.stack_size)
	local batch_size = DBL.RECIPE_MULTIPLIER
	local stack_name = "deadlock-stack-" .. base_name
	add_item(stack_name, {stack_size = math.max(1, math.floor(source.stack_size / represented_count))})
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
	return data.raw.item[stack_name]
end

DBL = require("prototypes.stacked_fuel")
DBL = require("prototypes.stacked_spoilage")

-- Matching densities use the ordinary stacked spoil result and copy the source timer exactly.
DBL.STACK_SIZE = 5
add_item("spoilage", {stack_size = 200})
add_stack_pair("spoilage")
local bioflux = add_item("bioflux", {
	type = "capsule",
	stack_size = 100,
	spoil_ticks = 432000,
	spoil_result = "spoilage",
	spoil_quality_change = 1,
	spoil_quality_min = "normal",
	spoil_quality_max = "legendary",
	spoil_level = 3,
	flags = {"ignore-spoil-time-modifier"},
})
local bioflux_stack = add_stack_pair("bioflux", "capsule")
expect(DBL.validate_spoilable_stack_source("bioflux", "capsule"), "ordinary spoilage source validates")
expect(DBL.update_stacked_spoilage("deadlock-stack-bioflux", "bioflux", "capsule"), "ordinary spoilage update succeeds")
expect_equal(bioflux_stack.spoil_ticks, 432000, "spoil_ticks is copied without density multiplication")
expect_equal(bioflux_stack.spoil_result, "deadlock-stack-spoilage", "matching density uses normal stacked spoilage")
expect_equal(bioflux_stack.spoil_quality_change, 1, "spoil quality change is copied")
expect_equal(bioflux_stack.spoil_quality_min, "normal", "spoil quality minimum is copied")
expect_equal(bioflux_stack.spoil_quality_max, "legendary", "spoil quality maximum is copied")
expect_equal(bioflux_stack.spoil_level, 3, "spoil level is copied")
expect_equal(bioflux_stack.flags[1], "ignore-spoil-time-modifier", "spoil-time modifier flag is copied")
expect(bioflux.spoil_ticks == bioflux_stack.spoil_ticks, "stacked and base spoil durations are identical")

-- Removing source spoil behavior clears stale stacked properties.
bioflux.spoil_ticks = nil
bioflux.spoil_result = nil
bioflux.flags = {}
expect(DBL.update_stacked_spoilage("deadlock-stack-bioflux", "bioflux", "capsule"), "non-spoilable resynchronization succeeds")
expect(bioflux_stack.spoil_ticks == nil, "stale stacked spoil timer is cleared")
expect(bioflux_stack.spoil_result == nil, "stale stacked spoil result is cleared")
expect(bioflux_stack.spoil_quality_change == nil, "stale stacked quality behavior is cleared")
expect(#bioflux_stack.flags == 0, "stale spoil-time modifier flag is cleared")

-- Mismatched densities generate one deterministic exact-count bundle.
DBL.STACK_SIZE = 100
add_item("spoilage-high", {stack_size = 200})
add_stack_pair("spoilage-high")
add_item("yumako", {
	type = "capsule",
	stack_size = 50,
	spoil_ticks = 216000,
	spoil_result = "spoilage-high",
})
local yumako_stack = add_stack_pair("yumako", "capsule")
expect(DBL.update_stacked_spoilage("deadlock-stack-yumako", "yumako", "capsule"), "mismatched density update succeeds")
local bundle_name = "deadlock-stacked-spoil-result-spoilage-high-50"
local recipe_name = "deadlock-stacked-spoil-result-unpack-spoilage-high-50"
expect_equal(yumako_stack.spoil_result, bundle_name, "mismatched density uses deterministic bundle name")
expect(DBL.is_exact_spoil_result_bundle(bundle_name), "generated bundle is recognized structurally")
expect(not DBL.is_exact_spoil_result_bundle("deadlock-stacked-spoil-result-made-up-50"), "bundle prefix alone is not trusted")
expect(data.raw.item[bundle_name] ~= nil, "exact spoil-result bundle item exists")
expect(data.raw.item[bundle_name].hidden, "exact spoil-result bundle is hidden")
expect(data.raw.item[bundle_name].hidden_in_factoriopedia, "exact spoil-result bundle is hidden in Factoriopedia")
expect(data.raw.item[bundle_name].spoil_ticks == nil, "exact spoil-result bundle cannot recursively spoil")
expect_equal(data.raw.recipe[recipe_name].ingredients[1].name, bundle_name, "bundle recipe consumes the exact bundle")
expect_equal(data.raw.recipe[recipe_name].ingredients[1].amount, 1, "bundle recipe consumes one bundle")
expect_equal(data.raw.recipe[recipe_name].results[1].name, "spoilage-high", "bundle recipe returns the normal result")
expect_equal(data.raw.recipe[recipe_name].results[1].amount, 50, "bundle recipe returns the represented result count")
expect(data.raw.recipe[recipe_name].allow_productivity == false, "bundle recipe disallows productivity")
expect(data.raw.recipe[recipe_name].can_set_quality == true, "bundle recipe preserves selected quality")
expect(data.raw.recipe[recipe_name].results[1].always_fresh == nil, "bundle conversion does not force fresh results")
expect(data.raw.recipe[recipe_name].results[1].percent_spoiled == nil, "bundle conversion does not set result freshness")
expect(data.raw.recipe[recipe_name].results[1].reset_freshness_on_craft == nil, "bundle conversion does not reset freshness")
local original_bundle = data.raw.item[bundle_name]
local original_recipe = data.raw.recipe[recipe_name]
expect(DBL.update_stacked_spoilage("deadlock-stack-yumako", "yumako", "capsule"), "repeated bundle synchronization succeeds")
expect(data.raw.item[bundle_name] == original_bundle, "repeated generation reuses the same bundle item")
expect(data.raw.recipe[recipe_name] == original_recipe, "repeated generation reuses the same bundle recipe")

-- Late registration of a matching result stack may replace this module's
-- verified bundle without deleting it or making load order unsafe.
DBL.STACK_SIZE = 5
add_item("late-result", {stack_size = 100})
add_item("late-source", {stack_size = 100, spoil_ticks = 600, spoil_result = "late-result"})
local late_source_stack = add_stack_pair("late-source")
expect(DBL.update_stacked_spoilage("deadlock-stack-late-source", "late-source", "item"), "source registered before result stack uses an exact bundle")
local late_bundle_name = "deadlock-stacked-spoil-result-late-result-5"
expect_equal(late_source_stack.spoil_result, late_bundle_name, "early source receives deterministic result bundle")
local late_bundle = data.raw.item[late_bundle_name]
add_stack_pair("late-result")
expect(DBL.update_stacked_spoilage("deadlock-stack-late-source", "late-source", "item"), "late matching result stack resynchronizes safely")
expect_equal(late_source_stack.spoil_result, "deadlock-stack-late-result", "late matching result stack replaces the verified bundle")
expect(data.raw.item[late_bundle_name] == late_bundle, "superseded exact bundle remains append-only")

-- The public API refuses exact internal bundles before it can generate another stack.
package.loaded["prototypes.public"] = nil
require("prototypes.public")
deadlock.add_stack(bundle_name, "__base__/graphics/icons/spoilage.png", nil, 64, "item")
expect(data.raw.item["deadlock-stack-" .. bundle_name] == nil, "exact spoil-result bundles cannot recursively stack")

-- A non-spoilable special result can use the same exact mechanism.
DBL.STACK_SIZE = 5
add_item("iron-ore-special", {stack_size = 50})
add_stack_pair("iron-ore-special")
add_item("iron-bacteria-test", {
	stack_size = 50,
	spoil_ticks = 3600,
	spoil_result = "iron-ore-special",
})
local bacteria_stack = add_stack_pair("iron-bacteria-test")
expect(DBL.validate_spoilable_stack_source("iron-bacteria-test", "item"), "non-recursive special result validates")
expect(DBL.update_stacked_spoilage("deadlock-stack-iron-bacteria-test", "iron-bacteria-test", "item"), "non-recursive special result synchronizes")
expect_equal(bacteria_stack.spoil_result, "deadlock-stack-iron-ore-special", "matching special result uses its normal stack")

-- Recipe batching does not alter the represented density or copied spoil time.
DBL.RECIPE_MULTIPLIER = 4
add_item("spoilage-batch", {stack_size = 200})
add_stack_pair("spoilage-batch")
add_item("batch-source", {spoil_ticks = 600, spoil_result = "spoilage-batch", stack_size = 100})
local batch_stack = add_stack_pair("batch-source")
expect(DBL.update_stacked_spoilage("deadlock-stack-batch-source", "batch-source", "item"), "batched spoilable recipes validate")
expect_equal(batch_stack.spoil_ticks, 600, "batch multiplier does not alter spoil duration")
expect_equal(batch_stack.spoil_result, "deadlock-stack-spoilage-batch", "batch multiplier does not alter represented spoil result")
DBL.RECIPE_MULTIPLIER = 1

-- Unsupported or ambiguous sources fail closed.
add_item("missing-result-source", {spoil_ticks = 60, spoil_result = "does-not-exist"})
expect(not DBL.validate_spoilable_stack_source("missing-result-source", "item"), "missing spoil result is rejected")
add_item("trigger-source", {
	spoil_ticks = 60,
	spoil_result = "spoilage",
	spoil_to_trigger_result = {items_per_trigger = 1, trigger = {}},
})
expect(not DBL.validate_spoilable_stack_source("trigger-source", "item"), "trigger-based spoil result is rejected")
add_item("recursive-result", {spoil_ticks = 60, spoil_result = "spoilage"})
add_item("recursive-source", {spoil_ticks = 60, spoil_result = "recursive-result"})
expect(not DBL.validate_spoilable_stack_source("recursive-source", "item"), "recursive spoil chain is rejected")
add_item("self-source", {spoil_ticks = 60, spoil_result = "self-source"})
expect(not DBL.validate_spoilable_stack_source("self-source", "item"), "self-recursive spoil result is rejected")
add_item("no-result-source", {spoil_ticks = 60})
expect(not DBL.validate_spoilable_stack_source("no-result-source", "item"), "spoilable without item result is rejected")
add_item("fractional-ticks-source", {spoil_ticks = 1.5, spoil_result = "spoilage"})
expect(not DBL.validate_spoilable_stack_source("fractional-ticks-source", "item"), "fractional spoil timer is rejected")

-- Any result-level freshness override disables the spoilable stack.
for _, property_name in ipairs({"always_fresh", "percent_spoiled", "reset_freshness_on_craft"}) do
	local source_name = "freshness-override-" .. property_name
	add_item(source_name, {spoil_ticks = 60, spoil_result = "spoilage"})
	add_stack_pair(source_name)
	data.raw.recipe["deadlock-stacks-stack-" .. source_name].results[1][property_name] =
		property_name == "percent_spoiled" and 0.25 or true
	expect(
		not DBL.update_stacked_spoilage("deadlock-stack-" .. source_name, source_name, "item"),
		property_name .. " freshness override fails closed"
	)
end

-- Modified noncanonical stack recipes cannot silently create refrigerated items.
add_item("tampered-source", {spoil_ticks = 60, spoil_result = "spoilage"})
add_stack_pair("tampered-source")
data.raw.recipe["deadlock-stacks-stack-tampered-source"].results[1].amount = 2
expect(not DBL.update_stacked_spoilage("deadlock-stack-tampered-source", "tampered-source", "item"), "noncanonical stack recipe fails closed")

-- Bundle name collisions fail closed without overwriting the foreign prototype.
DBL.STACK_SIZE = 7
add_item("collision-result", {stack_size = 100})
add_item("deadlock-stacked-spoil-result-collision-result-7", {stack_size = 1})
add_item("collision-source", {stack_size = 100, spoil_ticks = 60, spoil_result = "collision-result"})
add_stack_pair("collision-source")
expect(not DBL.update_stacked_spoilage("deadlock-stack-collision-source", "collision-source", "item"), "bundle item collision fails closed")
expect_equal(data.raw.item["deadlock-stacked-spoil-result-collision-result-7"].stack_size, 1, "foreign collision item is not overwritten")

if failures > 0 then
	for _, message in ipairs(messages) do
		io.stderr:write(message .. "\n")
	end
	error(string.format("%d of %d assertions failed", failures, assertions))
end

print(string.format("PASS: %d stacked-spoilage assertions", assertions))
