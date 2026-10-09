local assertions = 0
local failures = 0

local function deepcopy(value)
	if type(value) ~= "table" then return value end
	local result = {}
	for key, nested in pairs(value) do
		result[deepcopy(key)] = deepcopy(nested)
	end
	return result
end

table.deepcopy = deepcopy

local function expect(condition, message)
	assertions = assertions + 1
	if not condition then
		failures = failures + 1
		io.stderr:write("FAIL: " .. message .. "\n")
	end
end

local warnings = {}
local updated_types = {}
local shared = {
	item_order = { ["late-deleted-item"] = "a" },
	recipe_order = { ["late-deleted-item"] = "a" },
	STACK_SIZE = 5,
	RECIPE_MULTIPLIER = 1,
	CRAFT_TIME = 1,
	debug = function() end,
	log_warning = function(message) table.insert(warnings, message) end,
}
shared.update_stacked_spoilage = function(_, _, item_type)
	table.insert(updated_types, {"spoilage", item_type})
	return true
end
shared.update_stacked_fuel = function(_, _, item_type)
	table.insert(updated_types, {"fuel", item_type})
end
shared.update_stacked_weight = function(_, _, item_type)
	table.insert(updated_types, {"weight", item_type})
end

package.loaded["prototypes.shared"] = shared
package.loaded["prototypes.stacked_weight"] = shared
package.loaded["prototypes.stacked_fuel"] = shared
package.loaded["prototypes.stacked_spoilage"] = shared

data = {
	raw = {
		item = {
			["late-deleted-item"] = {
				type = "item",
				name = "late-deleted-item",
				stack_size = 100,
				subgroup = "raw-material",
			},
		},
		["item-subgroup"] = {
			["raw-material"] = {name = "raw-material", group = "intermediate-products"},
		},
		["item-group"] = {
			["intermediate-products"] = {name = "intermediate-products"},
		},
	},
}

function data:extend(prototypes)
	for _, prototype in ipairs(prototypes) do
		self.raw[prototype.type] = self.raw[prototype.type] or {}
		self.raw[prototype.type][prototype.name] = prototype
	end
end

settings = {
	startup = {
		["deadlock-stacking-hide-unstacking"] = {value = false},
	},
}

local destroyed
deadlock = {
	destroy_stack = function(item_name)
		destroyed = item_name
		data.raw.item["deadlock-stack-" .. item_name] = nil
	end,
}

deadlock.get_item_stack_density = function(item_name, item_type)
	return math.min(5, data.raw[item_type][item_name].stack_size)
end

dofile("prototypes/create_stack.lua")

shared.create_stacked_item(
	"late-deleted-item",
	"item",
	"__test__/stacked-late-deleted-item.png",
	64,
	5,
	nil
)
expect(data.raw.item["deadlock-stack-late-deleted-item"] ~= nil, "test stack is queued for deferred updates")
expect(data.raw.item["deadlock-stack-late-deleted-item"].auto_recycle == false, "generated stacked items opt out of automatic recycling")

shared.create_stacking_recipes("late-deleted-item", "item", 5)
expect(data.raw.recipe["deadlock-stacks-stack-late-deleted-item"].auto_recycle == false, "stacking recipes opt out of automatic recycling")
expect(data.raw.recipe["deadlock-stacks-unstack-late-deleted-item"].auto_recycle == false, "unstacking recipes opt out of automatic recycling")

data.raw.item["late-deleted-item"] = nil
shared.deferred_stacked_item_updates()

expect(destroyed == "late-deleted-item", "a source removed by another mod destroys its generated stack")
expect(data.raw.item["deadlock-stack-late-deleted-item"] == nil, "no orphaned stacked prototype remains")
expect(#warnings == 1 and warnings[1]:find("destroying its generated stack", 1, true), "late source removal is reported")

-- Pyanodon's fawogae can be registered as an item and later replaced by
-- a module in another mod's data updates. Its generated stack must survive.
shared.item_order.fawogae = "b"
shared.recipe_order.fawogae = "b"
data.raw.item.fawogae = {
	type = "item",
	name = "fawogae",
	stack_size = 100,
	subgroup = "raw-material",
}
data.raw["item-subgroup"]["py-modules"] = {
	name = "py-modules",
	group = "intermediate-products",
}
shared.create_stacked_item("fawogae", "item", "__test__/fawogae.png", 64, 5, nil)
shared.create_stacking_recipes("fawogae", "item", 5)

local fawogae = data.raw.item.fawogae
data.raw.item.fawogae = nil
fawogae.type = "module"
fawogae.stack_size = 80
fawogae.subgroup = "py-modules"
fawogae.localised_name = {"item-name.py-fawogae"}
data.raw.module = { fawogae = fawogae }

destroyed = nil
shared.deferred_stacked_item_updates()
local stack = data.raw.item["deadlock-stack-fawogae"]
expect(destroyed == nil, "a source that moves to another supported item type is not destroyed")
expect(stack ~= nil, "stacked fawogae survives item-to-module conversion")
expect(stack and stack.stack_size == 16, "stack capacity tracks the module's current stack size")
expect(stack and stack.subgroup == "stacks-intermediate-products", "stack subgroup follows the converted source")
expect(stack and stack.localised_name[2] == fawogae.localised_name, "stack uses the module's localised name")
expect(data.raw.recipe["deadlock-stacks-stack-fawogae"] ~= nil, "stacking recipe survives type conversion")
expect(data.raw.recipe["deadlock-stacks-unstack-fawogae"] ~= nil, "unstacking recipe survives type conversion")
expect(#updated_types == 3, "converted source still runs all metadata updates")
for _, updated in ipairs(updated_types) do
	expect(updated[2] == "module", updated[1] .. " synchronizes against the current module type")
end
expect(warnings[#warnings]:find("changed prototype type", 1, true) ~= nil,
	"source prototype type change is logged")

-- Re-running deferred updates must retain the converted source and its stack.
shared.deferred_stacked_item_updates()
expect(destroyed == nil and data.raw.item["deadlock-stack-fawogae"] ~= nil,
	"subsequent deferred updates preserve a converted source")

if failures > 0 then
	error(string.format("%d of %d create-stack assertions failed", failures, assertions))
end

print(string.format("create stack tests passed: %d assertions", assertions))
