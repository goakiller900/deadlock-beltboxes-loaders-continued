local failures = 0
local assertions = 0

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

local expected = {
	["bioflux"] = {tier = 2, type = "capsule"},
	["calcite"] = {tier = 1, type = "item"},
	["carbon"] = {tier = 2, type = "item"},
	["holmium-ore"] = {tier = 1, type = "item"},
	["holmium-plate"] = {tier = 2, type = "item"},
	["ice"] = {tier = 1, type = "item"},
	["jelly"] = {tier = 2, type = "capsule"},
	["jellynut"] = {tier = 1, type = "capsule"},
	["lithium"] = {tier = 2, type = "item"},
	["lithium-plate"] = {tier = 3, type = "item"},
	["nutrients"] = {tier = 2, type = "item"},
	["quantum-processor"] = {tier = 3, type = "item"},
	["raw-fish"] = {tier = 1, type = "capsule"},
	["scrap"] = {tier = 1, type = "item"},
	["spoilage"] = {tier = 1, type = "item"},
	["tungsten-carbide"] = {tier = 2, type = "item"},
	["tungsten-plate"] = {tier = 2, type = "item"},
	["yumako"] = {tier = 1, type = "capsule"},
	["yumako-mash"] = {tier = 2, type = "capsule"},
}

package.loaded["prototypes.shared"] = {VANILLA_ICON_SIZE = 64}

local function run(space_age_enabled, available)
	mods = space_age_enabled and {["space-age"] = true} or {}
	data = {raw = {item = {}, capsule = {}}}
	for name, registration in pairs(expected) do
		if available == nil or available[name] then
			data.raw[registration.type][name] = {name = name, type = registration.type}
		end
	end
	local calls = {}
	deadlock = {
		add_stack = function(name, icon, technology, icon_size, item_type)
			table.insert(calls, {
				name = name,
				icon = icon,
				technology = technology,
				icon_size = icon_size,
				item_type = item_type,
			})
		end,
	}
	dofile("prototypes/space_age_stacks.lua")
	return calls
end

local no_space_age = run(false)
expect_equal(#no_space_age, 0, "Space Age registrations disappear when the mod is absent")

local no_prototypes = run(true, {})
expect_equal(#no_prototypes, 0, "Space Age registrations disappear when source prototypes are absent")

local calls = run(true)
expect_equal(#calls, 19, "all supported Space Age registrations are created")
local seen = {}
for _, call in ipairs(calls) do
	local registration = expected[call.name]
	expect(registration ~= nil, "only expected Space Age items are registered: " .. call.name)
	expect(not seen[call.name], "Space Age item is registered only once: " .. call.name)
	seen[call.name] = true
	expect_equal(call.item_type, registration.type, "item prototype type is correct for " .. call.name)
	expect_equal(call.technology, "deadlock-stacking-" .. registration.tier, "stacking tier is correct for " .. call.name)
	expect_equal(call.icon_size, 64, "mipped icon base size is correct for " .. call.name)
	local expected_icon = "__deadlock-beltboxes-loaders-continued__/graphics/icons/square/stacked-" .. call.name .. ".png"
	expect_equal(call.icon, expected_icon, "icon path uses the internal item name for " .. call.name)
end
expect(not seen["tungsten-ore"], "existing vanilla tungsten registration is not duplicated")

local only_calcite = run(true, {calcite = true})
expect_equal(#only_calcite, 1, "prototype existence guard registers only available items")
expect_equal(only_calcite[1].name, "calcite", "prototype existence guard selects the available item")

if failures > 0 then
	error(string.format("%d of %d assertions failed", failures, assertions))
end

print(string.format("PASS: %d Space Age registration assertions", assertions))
