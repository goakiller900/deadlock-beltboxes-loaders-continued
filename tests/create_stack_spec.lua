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
local shared = {
	item_order = { ["late-deleted-item"] = "a" },
	debug = function() end,
	log_warning = function(message) table.insert(warnings, message) end,
}
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

local destroyed
deadlock = {
	destroy_stack = function(item_name)
		destroyed = item_name
		data.raw.item["deadlock-stack-" .. item_name] = nil
	end,
}

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

data.raw.item["late-deleted-item"] = nil
shared.deferred_stacked_item_updates()

expect(destroyed == "late-deleted-item", "a source removed by another mod destroys its generated stack")
expect(data.raw.item["deadlock-stack-late-deleted-item"] == nil, "no orphaned stacked prototype remains")
expect(#warnings == 1 and warnings[1]:find("destroying its generated stack", 1, true), "late source removal is reported")

if failures > 0 then
	error(string.format("%d of %d create-stack assertions failed", failures, assertions))
end

print(string.format("create stack tests passed: %d assertions", assertions))
