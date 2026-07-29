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

prototypes = {
	item = {
		["bioflux"] = {name = "bioflux", stack_size = 100},
		["iron-plate"] = {name = "iron-plate", stack_size = 100},
	},
}

local auto_unstack = require("runtime.auto_unstack")

local function make_stack(name, count, quality, spoil_tick, spoil_percent)
	return {
		valid_for_read = true,
		name = name,
		count = count,
		quality = {name = quality},
		spoil_tick = spoil_tick,
		spoil_percent = spoil_percent,
	}
end

local function make_empty_slot(write_fails)
	local slot = {
		valid_for_read = false,
		write_fails = write_fails,
	}
	slot.can_set_stack = function()
		return true
	end
	slot.set_stack = function(definition)
		if slot.write_fails then return false end
		slot.valid_for_read = true
		slot.name = definition.name
		slot.count = definition.count
		slot.quality = {name = definition.quality}
		slot.spoil_tick = definition.spoil_percent and 1 or 0
		slot.spoil_percent = definition.spoil_percent
		slot.written_definition = definition
		return true
	end
	return slot
end

local function make_inventory(stacks, total_slots, failing_slot)
	local inventory = {}
	for index, stack in ipairs(stacks or {}) do
		inventory[index] = stack
	end
	while #inventory < (total_slots or #inventory) do
		inventory[#inventory + 1] = make_empty_slot(failing_slot and #inventory + 1 == failing_slot)
	end
	return inventory
end

-- Spoilable stacks preserve quality and spoil percentage exactly.
local spoilable = make_stack("deadlock-stack-bioflux", 2, "rare", 12000, 0.4)
local receiving = make_inventory({}, 1)
local converted, refusal = auto_unstack.convert_stack(spoilable, receiving, 5)
expect_equal(converted, 2, "two complete stacked items are converted")
expect(refusal == nil, "metadata-preserving conversion is not refused")
expect_equal(spoilable.count, 0, "exact source stack count is removed")
expect_equal(receiving[1].name, "bioflux", "base item name is inserted")
expect_equal(receiving[1].count, 10, "represented base-item quantity is inserted")
expect_equal(receiving[1].quality.name, "rare", "quality is preserved")
expect_equal(receiving[1].spoil_percent, 0.4, "spoil percentage is preserved")

-- Whole represented bundles are planned slot-by-slot, so partial bundles are never created.
local limited = make_stack("deadlock-stack-bioflux", 2, "uncommon", 12000, 0.25)
local limited_receiving = make_inventory({
	make_stack("bioflux", 95, "uncommon", 12000, 0.25),
}, 1)
local limited_count = auto_unstack.convert_stack(limited, limited_receiving, 5)
expect_equal(limited_count, 1, "exact matching capacity permits one complete represented bundle")
expect_equal(limited.count, 1, "only one exact source stacked item is removed")
expect_equal(limited_receiving[1].count, 100, "the exact-metadata output stack is filled without overflow")

local blocked = make_stack("deadlock-stack-bioflux", 1, "normal", 12000, 0.5)
local blocked_receiving = make_inventory({
	make_stack("bioflux", 96, "normal", 12000, 0.5),
}, 1)
local blocked_count = auto_unstack.convert_stack(blocked, blocked_receiving, 5)
expect_equal(blocked_count, 0, "insufficient capacity leaves the source untouched")
expect_equal(blocked.count, 1, "blocked source stack remains intact")
expect_equal(blocked_receiving[1].count, 96, "blocked conversion changes no destination count")

local different_freshness = make_stack("deadlock-stack-bioflux", 1, "normal", 12000, 0.5)
local different_freshness_receiving = make_inventory({
	make_stack("bioflux", 90, "normal", 12000, 0.4),
}, 1)
local different_freshness_count = auto_unstack.convert_stack(different_freshness, different_freshness_receiving, 5)
expect_equal(different_freshness_count, 0, "different destination freshness is not merged")
expect_equal(different_freshness.count, 1, "freshness-mismatch source remains untouched")
expect_equal(different_freshness_receiving[1].count, 90, "freshness-mismatch destination remains untouched")

-- Normal quality items also preserve quality and do not invent spoil metadata.
local plate = make_stack("deadlock-stack-iron-plate", 1, "legendary", 0, nil)
local plate_receiving = make_inventory({}, 1)
local plate_count = auto_unstack.convert_stack(plate, plate_receiving, 5)
expect_equal(plate_count, 1, "non-spoilable stack converts")
expect_equal(plate_receiving[1].quality.name, "legendary", "non-spoilable quality is preserved")
expect(plate_receiving[1].spoil_percent == nil, "non-spoilable conversion does not add spoil metadata")

-- Missing exact metadata fails closed.
local missing_spoil = setmetatable({
	valid_for_read = true,
	name = "deadlock-stack-bioflux",
	count = 1,
	quality = {name = "normal"},
	spoil_tick = 12000,
}, {
	__index = function(_, key)
		if key == "spoil_percent" then error("metadata unavailable") end
	end,
})
local missing_spoil_receiving = make_inventory({}, 1)
local missing_spoil_count, missing_spoil_reason = auto_unstack.convert_stack(missing_spoil, missing_spoil_receiving, 5)
expect_equal(missing_spoil_count, 0, "missing spoil metadata refuses conversion")
expect_equal(missing_spoil_reason, "spoil-metadata-unavailable", "missing spoil metadata reports the refusal reason")
expect_equal(missing_spoil.count, 1, "refused spoilable stack remains untouched")
expect(not missing_spoil_receiving[1].valid_for_read, "refused spoilable stack inserts nothing")

local missing_quality = setmetatable({
	valid_for_read = true,
	name = "deadlock-stack-iron-plate",
	count = 1,
	spoil_tick = 0,
}, {
	__index = function(_, key)
		if key == "quality" then error("quality unavailable") end
	end,
})
local missing_quality_receiving = make_inventory({}, 1)
local missing_quality_count, missing_quality_reason = auto_unstack.convert_stack(missing_quality, missing_quality_receiving, 5)
expect_equal(missing_quality_count, 0, "missing quality refuses conversion")
expect_equal(missing_quality_reason, "quality-unavailable", "missing quality reports the refusal reason")
expect_equal(missing_quality.count, 1, "quality-refused stack remains untouched")

-- An unexpected destination write failure occurs before source consumption.
local unexpected = make_stack("deadlock-stack-bioflux", 1, "rare", 12000, 0.6)
local unexpected_receiving = make_inventory({}, 1, 1)
local unexpected_count, unexpected_reason = auto_unstack.convert_stack(unexpected, unexpected_receiving, 5)
expect_equal(unexpected_count, 0, "unexpected destination write failure is refused")
expect_equal(unexpected_reason, "destination-write-failed", "unexpected destination failure reports its reason")
expect_equal(unexpected.count, 1, "unexpected destination failure does not consume the source")
expect(not unexpected_receiving[1].valid_for_read, "failed destination write leaves the destination empty")

-- Inventory conversion honors event name, quality, and count filters.
local filtered_inventory = make_inventory({
	make_stack("deadlock-stack-bioflux", 2, "rare", 12000, 0.2),
	make_stack("deadlock-stack-bioflux", 2, "normal", 12000, 0.7),
	make_stack("deadlock-stack-iron-plate", 1, "rare", 0, nil),
}, 4)
local filtered_count, filtered_refusal = auto_unstack.convert_inventory(
	filtered_inventory,
	filtered_inventory,
	5,
	"deadlock-stack-bioflux",
	"rare",
	1
)
expect_equal(filtered_count, 1, "event filter converts only the reported stacked count")
expect(filtered_refusal == nil, "filtered conversion has no refusal")
expect_equal(filtered_inventory[1].count, 1, "matching quality source is decremented")
expect_equal(filtered_inventory[2].count, 2, "different quality source remains untouched")
expect_equal(filtered_inventory[3].count, 1, "different item remains untouched")
expect_equal(filtered_inventory[4].spoil_percent, 0.2, "filtered slot's exact freshness is used")

-- Missing base prototypes fail closed.
local orphan = make_stack("deadlock-stack-does-not-exist", 1, "normal", 0, nil)
local orphan_receiving = make_inventory({}, 1)
local orphan_count, orphan_reason = auto_unstack.convert_stack(orphan, orphan_receiving, 5)
expect_equal(orphan_count, 0, "missing base prototype refuses conversion")
expect_equal(orphan_reason, "missing-base-prototype", "missing base prototype reports its reason")
expect_equal(orphan.count, 1, "orphan stack remains untouched")

if failures > 0 then
	error(string.format("%d of %d assertions failed", failures, assertions))
end

print(string.format("PASS: %d auto-unstack assertions", assertions))
