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
		["recipe-category"] = {},
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
	expect(
		actual == expected,
		string.format("%s (expected %s, got %s)", message, tostring(expected), tostring(actual))
	)
end

local function add_item(name, properties)
	properties = properties or {}
	properties.type = "item"
	properties.name = name
	properties.icon = "__base__/graphics/icons/iron-plate.png"
	properties.stack_size = properties.stack_size or 100
	properties.subgroup = "raw-material"
	data.raw.item[name] = properties
	return properties
end

local DBL = require("prototypes.stacked_weight")
require("prototypes.stacked_fuel")

-- Explicit prototype weights can be multiplied directly without a helper recipe.
local explicit_source = add_item("explicit-source", {weight = 4000})
local explicit_stack = add_item("explicit-stack", {stack_size = 20})
expect(
	DBL.apply_represented_item_weight("explicit-stack", "explicit-source", explicit_source, 5),
	"explicit weight synchronization succeeds"
)
expect_equal(explicit_stack.weight, 20000, "explicit stacked weight represents five source items")
expect(data.raw.recipe["explicit-stack"] == nil, "explicit weight does not create a helper recipe")

-- Automatically calculated source weights use a private decomposition recipe.
local automatic_source = add_item("automatic-source")
local automatic_stack = add_item("automatic-stack", {stack_size = 20})
expect(
	DBL.apply_represented_item_weight(
		"automatic-stack",
		"automatic-source",
		automatic_source,
		5
	),
	"automatic weight synchronization succeeds"
)
expect(automatic_stack.weight == nil, "automatic stacked weight does not copy the default weight")
expect_equal(
	automatic_stack.ingredient_to_weight_coefficient,
	1,
	"automatic helper preserves the full ingredient weight"
)

local helper = data.raw.recipe["automatic-stack"]
expect(helper ~= nil, "automatic weight creates a helper recipe")
expect_equal(helper.name, "automatic-stack", "helper recipe name matches its product for recipe ordering")
expect_equal(
	helper.categories[1],
	"deadlock-stacking-weight-calculation",
	"helper uses the private weight category"
)
expect(helper.enabled == false, "helper is disabled")
expect(helper.hidden == false, "helper remains eligible for Factorio's automatic weight algorithm")
expect(helper.hidden_in_factoriopedia, "helper is hidden in Factoriopedia")
expect(helper.hide_from_player_crafting, "helper is hidden from player crafting")
expect(helper.hide_from_signal_gui, "helper is hidden from signal selection")
expect(helper.hide_from_stats, "helper is hidden from production statistics")
expect(helper.hide_from_bonus_gui, "helper is hidden from the bonus GUI")
expect(helper.allow_decomposition, "helper is eligible for automatic weight decomposition")
expect(helper.allow_as_intermediate == false, "helper cannot be hand-crafting intermediate")
expect(helper.allow_intermediates == false, "helper cannot hand-craft its ingredients")
expect(helper.unlock_results == false, "helper does not unlock item filters")
expect(
	helper.requires_ingredients_to_unlock_results == false,
	"helper does not participate in result progression"
)
expect(helper.allow_consumption == false, "helper disallows consumption effects")
expect(helper.allow_speed == false, "helper disallows speed effects")
expect(helper.allow_pollution == false, "helper disallows pollution effects")
expect(helper.allow_quality == false, "helper disallows quality effects")
expect(helper.can_set_quality == false, "helper cannot select recipe quality")
expect_equal(helper.maximum_productivity, 0, "helper has no productivity bonus")
expect_equal(
	helper.results[1].ignored_by_productivity,
	1,
	"the entire helper output is excluded from productivity"
)
expect(helper.auto_recycle == false, "helper does not generate recycling recipes")
expect_equal(helper.ingredients[1].amount, 5, "helper uses the represented source count")
expect_equal(helper.results[1].amount, 1, "helper produces one represented item")

for _, prototypes in pairs(data.raw) do
	for _, prototype in pairs(prototypes) do
		expect(
			not (
				prototype.crafting_categories
				and prototype.crafting_categories[1] == "deadlock-stacking-weight-calculation"
			),
			"no crafting machine uses the private weight category"
		)
	end
end

-- Re-synchronization follows recipe changes rather than a stale configured density.
helper.ingredients[1].amount = 99
expect(
	DBL.apply_represented_item_weight(
		"automatic-stack",
		"automatic-source",
		automatic_source,
		10
	),
	"automatic helper re-synchronization succeeds"
)
expect_equal(helper.ingredients[1].amount, 10, "density changes update the represented count")

local function add_stack_pair(source_name, represented_count)
	local stack_name = "deadlock-stack-" .. source_name
	add_item(stack_name, {
		stack_size = math.floor(data.raw.item[source_name].stack_size / represented_count),
	})
	data.raw.recipe["deadlock-stacks-stack-" .. source_name] = {
		type = "recipe",
		name = "deadlock-stacks-stack-" .. source_name,
		categories = {"stacking"},
		ingredients = {{type = "item", name = source_name, amount = represented_count}},
		results = {{type = "item", name = stack_name, amount = 1}},
	}
	data.raw.recipe["deadlock-stacks-unstack-" .. source_name] = {
		type = "recipe",
		name = "deadlock-stacks-unstack-" .. source_name,
		categories = {"unstacking"},
		ingredients = {{type = "item", name = stack_name, amount = 1}},
		results = {{type = "item", name = source_name, amount = represented_count}},
	}
	return stack_name
end

-- The normal stack synchronization reads the exact ratio from the real recipes.
local third_party = add_item("third-party-auto", {stack_size = 100})
local third_party_stack_name = add_stack_pair("third-party-auto", 5)
expect(
	DBL.update_stacked_weight(third_party_stack_name, "third-party-auto", "item"),
	"third-party stack weight synchronization succeeds"
)
expect_equal(
	data.raw.recipe[third_party_stack_name].ingredients[1].amount,
	5,
	"third-party helper uses the stack recipe's represented count"
)

-- A configured density above the source stack size represents only the source stack size.
DBL.STACK_SIZE = 10
local small_source = add_item("small-explicit", {stack_size = 3, weight = 2000})
local small_stack_name = add_stack_pair("small-explicit", 3)
expect(
	DBL.update_stacked_weight(small_stack_name, "small-explicit", "item"),
	"limited-density stack weight synchronization succeeds"
)
expect_equal(
	data.raw.item[small_stack_name].weight,
	6000,
	"limited-density stacked weight represents the real count of three"
)
expect_equal(
	math.floor(1000000 / data.raw.item[small_stack_name].weight),
	166,
	"limited-density capacity is based on three represented items"
)

if failures > 0 then
	error(string.format("%d of %d stacked-weight assertions failed", failures, assertions))
end

print(string.format("PASS: %d stacked-weight assertions", assertions))
