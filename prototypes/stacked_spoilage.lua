local DBL = require("prototypes.shared")
require("prototypes.stacked_weight")

local BUNDLE_PREFIX = "deadlock-stacked-spoil-result-"
local BUNDLE_RECIPE_PREFIX = "deadlock-stacked-spoil-result-unpack-"
local verified_exact_bundles = {}
local exact_trigger_sources = {}
local verified_exact_trigger_results = {}

local item_prototype_types = {
	"item",
	"ammo",
	"armor",
	"blueprint",
	"blueprint-book",
	"capsule",
	"copy-paste-tool",
	"deconstruction-item",
	"gun",
	"item-with-entity-data",
	"item-with-inventory",
	"item-with-label",
	"item-with-tags",
	"module",
	"rail-planner",
	"repair-tool",
	"selection-tool",
	"space-platform-starter-pack",
	"spidertron-remote",
	"tool",
	"upgrade-item",
}

local spoil_properties = {
	"spoil_quality_change",
	"spoil_quality_min",
	"spoil_quality_max",
	"spoil_level",
}

local freshness_override_properties = {
	"always_fresh",
	"percent_spoiled",
	"reset_freshness_on_craft",
}

local function copy(value)
	if type(value) == "table" then
		return table.deepcopy(value)
	end
	return value
end

local function deep_equal(left, right)
	if type(left) ~= type(right) then
		return false
	end
	if type(left) ~= "table" then
		return left == right
	end
	for key, value in pairs(left) do
		if not deep_equal(value, right[key]) then
			return false
		end
	end
	for key in pairs(right) do
		if left[key] == nil then
			return false
		end
	end
	return true
end

local function trigger_source_key(source_item_name, source_item_type)
	return string.format("%s:%s", source_item_type, source_item_name)
end

local function exact_trigger_source_enabled(source_item_name, source_item_type)
	return exact_trigger_sources[trigger_source_key(source_item_name, source_item_type)] == true
end

local function trigger_items(trigger)
	if type(trigger) ~= "table" then
		return nil
	end
	if type(trigger.type) == "string" then
		return {trigger}
	end

	local count = 0
	for index, trigger_item in ipairs(trigger) do
		if index ~= count + 1
			or type(trigger_item) ~= "table"
			or type(trigger_item.type) ~= "string"
		then
			return nil
		end
		count = index
	end
	if count == 0 then
		return nil
	end
	for key in pairs(trigger) do
		if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > count then
			return nil
		end
	end
	return trigger
end

local function valid_trigger_spoil_result(spoil_to_trigger_result)
	return type(spoil_to_trigger_result) == "table"
		and type(spoil_to_trigger_result.items_per_trigger) == "number"
		and spoil_to_trigger_result.items_per_trigger > 0
		and spoil_to_trigger_result.items_per_trigger % 1 == 0
		and trigger_items(spoil_to_trigger_result.trigger) ~= nil
end

local function find_item_prototype(item_name)
	for _, item_type in ipairs(item_prototype_types) do
		if data.raw[item_type] and data.raw[item_type][item_name] then
			return data.raw[item_type][item_name], item_type
		end
	end
	return nil, nil
end

local function localised_item_name(item_name, prototype)
	if prototype.localised_name then
		return prototype.localised_name
	end
	return {"item-name." .. item_name}
end

local function prototype_icons(prototype)
	if prototype.icons then
		local icons = table.deepcopy(prototype.icons)
		for _, layer in pairs(icons) do
			layer.icon_size = layer.icon_size or prototype.icon_size or 64
		end
		return icons
	end
	if prototype.icon then
		return {{
			icon = prototype.icon,
			icon_size = prototype.icon_size or 64,
			icon_mipmaps = prototype.icon_mipmaps,
		}}
	end
	return nil
end

local function has_flag(prototype, expected)
	for _, flag in pairs(prototype.flags or {}) do
		if flag == expected then
			return true
		end
	end
	return false
end

local function copy_spoil_time_flag(stacked_item, source_item)
	local flags = {}
	for _, flag in pairs(stacked_item.flags or {}) do
		if flag ~= "ignore-spoil-time-modifier" then
			table.insert(flags, flag)
		end
	end
	if has_flag(source_item, "ignore-spoil-time-modifier") then
		table.insert(flags, "ignore-spoil-time-modifier")
	end
	stacked_item.flags = flags
end

local function clear_spoil_properties(stacked_item)
	stacked_item.spoil_ticks = nil
	stacked_item.spoil_result = nil
	stacked_item.spoil_to_trigger_result = nil
	for _, property_name in ipairs(spoil_properties) do
		stacked_item[property_name] = nil
	end
end

local function source_is_spoilable(source_item)
	return type(source_item.spoil_ticks) == "number" and source_item.spoil_ticks > 0
end

local function validate_source(source_item_name, source_item_type, source_item)
	if not source_is_spoilable(source_item) then
		return true
	end
	if source_item.spoil_ticks % 1 ~= 0 then
		DBL.log_warning(string.format(
			"Refusing to stack spoilable item %s because spoil_ticks is not an integer",
			source_item_name
		))
		return false
	end
	if source_item.spoil_to_trigger_result then
		if not exact_trigger_source_enabled(source_item_name, source_item_type) then
			DBL.log_warning(string.format(
				"Refusing to stack spoilable item %s because trigger-based spoil results require explicit exact-conversion opt-in",
				source_item_name
			))
			return false
		end
		if source_item.spoil_result ~= nil then
			DBL.log_warning(string.format(
				"Refusing to stack spoilable item %s because combined item and trigger spoil results are unsupported",
				source_item_name
			))
			return false
		end
		if not valid_trigger_spoil_result(source_item.spoil_to_trigger_result) then
			DBL.log_warning(string.format(
				"Refusing to stack spoilable item %s because its trigger spoil result is malformed",
				source_item_name
			))
			return false
		end
		return true
	end
	if type(source_item.spoil_result) ~= "string" then
		DBL.log_warning(string.format(
			"Refusing to stack spoilable item %s because it has no deterministic item spoil result",
			source_item_name
		))
		return false
	end

	local result = find_item_prototype(source_item.spoil_result)
	if not result then
		DBL.log_warning(string.format(
			"Refusing to stack spoilable item %s because spoil result %s is not an item prototype",
			source_item_name,
			source_item.spoil_result
		))
		return false
	end
	if source_item.spoil_result == source_item_name
		or source_is_spoilable(result)
		or result.spoil_to_trigger_result
	then
		DBL.log_warning(string.format(
			"Refusing to stack spoilable item %s because recursive spoil result %s is unsupported",
			source_item_name,
			source_item.spoil_result
		))
		return false
	end
	return true
end

local function ceil_div(numerator, denominator)
	return math.floor((numerator - 1) / denominator) + 1
end

local function exact_trigger_spoil_result(source_item_name, source_item, stacked_item, represented_count)
	local source_result = source_item.spoil_to_trigger_result
	local source_trigger_items = trigger_items(source_result and source_result.trigger)
	local items_per_trigger = source_result and source_result.items_per_trigger
	local maximum_stacked_count = stacked_item.stack_size
	if not source_trigger_items
		or type(items_per_trigger) ~= "number"
		or items_per_trigger <= 0
		or items_per_trigger % 1 ~= 0
		or type(represented_count) ~= "number"
		or represented_count <= 0
		or represented_count % 1 ~= 0
		or type(maximum_stacked_count) ~= "number"
		or maximum_stacked_count <= 0
		or maximum_stacked_count % 1 ~= 0
	then
		return nil
	end

	-- Factorio runs the source trigger ceil(count / items_per_trigger) times.
	-- A stacked item represents represented_count source items, so find one
	-- fixed trigger repetition and grouping that matches every possible partial
	-- LuaItemStack count for this generated prototype.
	local repetitions = ceil_div(represented_count, items_per_trigger)
	local stacked_items_per_trigger = math.min(
		maximum_stacked_count,
		math.floor((repetitions * items_per_trigger) / represented_count)
	)
	if stacked_items_per_trigger < 1 then
		return nil
	end
	for stacked_count = 1, maximum_stacked_count do
		local source_trigger_count = ceil_div(stacked_count * represented_count, items_per_trigger)
		local stacked_trigger_count = repetitions * ceil_div(stacked_count, stacked_items_per_trigger)
		if source_trigger_count ~= stacked_trigger_count then
			DBL.log_warning(string.format(
				"Refusing to stack trigger-spoilable item %s at density %d because partial stack count %d would run %d triggers instead of %d",
				source_item_name,
				represented_count,
				stacked_count,
				stacked_trigger_count,
				source_trigger_count
			))
			return nil
		end
	end

	local repeated_trigger = {}
	for _ = 1, repetitions do
		for _, trigger_item in ipairs(source_trigger_items) do
			table.insert(repeated_trigger, table.deepcopy(trigger_item))
		end
	end
	local result = table.deepcopy(source_result)
	result.items_per_trigger = stacked_items_per_trigger
	result.trigger = repeated_trigger
	return result
end

local function bundle_name(result_name, represented_count)
	return string.format("%s%s-%d", BUNDLE_PREFIX, result_name, represented_count)
end

local function bundle_recipe_name(result_name, represented_count)
	return string.format("%s%s-%d", BUNDLE_RECIPE_PREFIX, result_name, represented_count)
end

local function exact_entry(entry, item_name, amount)
	return type(entry) == "table"
		and (entry.type or "item") == "item"
		and (entry.name or entry[1]) == item_name
		and (entry.amount or entry[2]) == amount
		and entry.probability == nil
		and entry.amount_min == nil
		and entry.amount_max == nil
		and entry.extra_count_fraction == nil
		and entry.quality_min == nil
		and entry.quality_max == nil
		and entry.quality_change == nil
		and entry.always_fresh == nil
		and entry.percent_spoiled == nil
		and entry.reset_freshness_on_craft == nil
end

local function exact_bundle_exists(name, recipe_name, result_name, represented_count)
	local item = data.raw.item[name]
	local recipe = data.raw.recipe[recipe_name]
	return verified_exact_bundles[name] == true
		and item ~= nil
		and recipe ~= nil
		and recipe.categories ~= nil
		and recipe.categories[1] == "unstacking"
		and recipe.ingredients ~= nil
		and #recipe.ingredients == 1
		and exact_entry(recipe.ingredients[1], name, 1)
		and recipe.results ~= nil
		and #recipe.results == 1
		and exact_entry(recipe.results[1], result_name, represented_count)
		and recipe.can_set_quality ~= false
		and recipe.allow_productivity == false
end

local function create_bundle(result_name, result, represented_count)
	if type(represented_count) ~= "number"
		or represented_count <= 0
		or represented_count % 1 ~= 0
	then
		return nil
	end

	local name = bundle_name(result_name, represented_count)
	local recipe_name = bundle_recipe_name(result_name, represented_count)
	local existing_item = find_item_prototype(name)
	local existing_recipe = data.raw.recipe[recipe_name]
	if existing_item or existing_recipe then
		if exact_bundle_exists(name, recipe_name, result_name, represented_count) then
			return name
		end
		DBL.log_error(string.format(
			"Cannot create exact spoil-result bundle %s because its item or recipe name is already in use",
			name
		))
		return nil
	end

	local icons = prototype_icons(result)
	if not icons then
		DBL.log_error(string.format(
			"Cannot create exact spoil-result bundle for %s because the result has no icon",
			result_name
		))
		return nil
	end

	local recipe_icons = table.deepcopy(icons)
	table.insert(recipe_icons, {
		icon = "__deadlock-beltboxes-loaders-continued__/graphics/icons/square/arrow-u-64.png",
		icon_size = 64,
		scale = 0.25,
	})

	local bundle_stack_size = math.max(1, math.floor((result.stack_size or 1) / represented_count))
	local bundle = {
		type = "item",
		name = name,
		localised_name = {
			"item-name.deadlock-stacking-stack",
			localised_item_name(result_name, result),
			tostring(represented_count),
		},
		icons = icons,
		stack_size = bundle_stack_size,
		hidden = true,
		hidden_in_factoriopedia = true,
		flags = {},
		subgroup = result.subgroup or "other",
		order = string.format("%s[deadlock-spoil-result-%d]", result.order or "z", represented_count),
		auto_recycle = false,
		inventory_move_sound = copy(result.inventory_move_sound),
		pick_sound = copy(result.pick_sound),
		drop_sound = copy(result.drop_sound),
	}
	local recipe = {
		type = "recipe",
		name = recipe_name,
		localised_name = {
			"recipe-name.deadlock-stacking-unstack",
			localised_item_name(result_name, result),
		},
		categories = {"unstacking"},
		subgroup = bundle.subgroup,
		order = bundle.order,
		enabled = true,
		hidden = true,
		hidden_in_factoriopedia = true,
		hide_from_player_crafting = true,
		allow_decomposition = false,
		ingredients = {{type = "item", name = name, amount = 1}},
		results = {{type = "item", name = result_name, amount = represented_count}},
		energy_required = math.max(0.1, represented_count / 15),
		icons = recipe_icons,
		allow_as_intermediate = false,
		hide_from_stats = true,
		auto_recycle = false,
		can_set_quality = true,
		allow_productivity = false,
	}

	data:extend({bundle, recipe})
	if not DBL.apply_represented_item_weight(name, result_name, result, represented_count) then
		DBL.log_error(string.format(
			"Cannot create exact spoil-result bundle %s because its weight cannot be represented safely",
			name
		))
		data.raw.item[name] = nil
		data.raw.recipe[recipe_name] = nil
		return nil
	end
	verified_exact_bundles[name] = true
	DBL.debug(string.format(
		"Created exact spoil-result bundle %s representing %d %s",
		name,
		represented_count,
		result_name
	))
	return name
end

local function matching_stacked_result(source_ratio, result_name, result_type)
	local stacked_result_name = "deadlock-stack-" .. result_name
	if not data.raw.item[stacked_result_name] then
		return nil
	end
	local result_ratio = DBL.get_stack_represented_ratio(result_name, result_type)
	if result_ratio
		and result_ratio.numerator == source_ratio.numerator
		and result_ratio.denominator == source_ratio.denominator
	then
		return stacked_result_name
	end
	return nil
end

local function result_has_freshness_override(result)
	if type(result) ~= "table" then
		return false
	end
	for _, property_name in ipairs(freshness_override_properties) do
		if result[property_name] ~= nil then
			return true
		end
	end
	return false
end

local function recipe_preserves_native_freshness(recipe, result_name)
	if not recipe then
		return false
	end
	local variants = {recipe, recipe.normal, recipe.expensive}
	for _, variant in pairs(variants) do
		if variant and variant.results then
			for _, result in pairs(variant.results) do
				if (result.name or result[1]) == result_name
					and result_has_freshness_override(result)
				then
					return false
				end
			end
		end
	end
	return true
end

local function stack_recipes_preserve_native_freshness(source_item_name, stacked_item_name)
	return recipe_preserves_native_freshness(
		data.raw.recipe["deadlock-stacks-stack-" .. source_item_name],
		stacked_item_name
	) and recipe_preserves_native_freshness(
		data.raw.recipe["deadlock-stacks-unstack-" .. source_item_name],
		source_item_name
	)
end

function DBL.is_exact_spoil_result_bundle(item_name)
	return verified_exact_bundles[item_name] == true
end

function DBL.allow_exact_trigger_spoilage_source(source_item_name, source_item_type)
	if type(source_item_name) ~= "string" or type(source_item_type) ~= "string" then
		return false
	end
	exact_trigger_sources[trigger_source_key(source_item_name, source_item_type)] = true
	return true
end

function DBL.validate_spoilable_stack_source(source_item_name, source_item_type)
	local source_item = data.raw[source_item_type] and data.raw[source_item_type][source_item_name]
	return source_item ~= nil and validate_source(source_item_name, source_item_type, source_item)
end

function DBL.update_stacked_spoilage(stacked_item_name, source_item_name, source_item_type)
	local stacked_item = data.raw.item[stacked_item_name]
	local source_item = data.raw[source_item_type] and data.raw[source_item_type][source_item_name]
	if not stacked_item or not source_item then
		return false
	end
	if not source_is_spoilable(source_item) then
		clear_spoil_properties(stacked_item)
		verified_exact_trigger_results[stacked_item_name] = nil
		copy_spoil_time_flag(stacked_item, source_item)
		return true
	end
	if not validate_source(source_item_name, source_item_type, source_item) then
		return false
	end
	if not stack_recipes_preserve_native_freshness(source_item_name, stacked_item_name) then
		DBL.log_warning(string.format(
			"Refusing spoilable stack %s because its recipes override native freshness transfer",
			stacked_item_name
		))
		return false
	end

	local source_ratio = DBL.get_stack_represented_ratio(source_item_name, source_item_type)
	if not source_ratio or source_ratio.denominator ~= 1 then
		DBL.log_warning(string.format(
			"Refusing spoilable stack %s because its represented item count is not an exact integer",
			stacked_item_name
		))
		return false
	end
	if source_item.spoil_to_trigger_result then
		local desired_trigger_result = exact_trigger_spoil_result(
			source_item_name,
			source_item,
			stacked_item,
			source_ratio.numerator
		)
		if not desired_trigger_result then
			return false
		end

		local existing_trigger_result = stacked_item.spoil_to_trigger_result
		local verified_trigger_result = verified_exact_trigger_results[stacked_item_name]
		if existing_trigger_result
			and not deep_equal(existing_trigger_result, desired_trigger_result)
			and not (verified_trigger_result and deep_equal(existing_trigger_result, verified_trigger_result))
		then
			DBL.log_warning(string.format(
				"Refusing spoilable stack %s because its existing trigger spoil result cannot be proven exact",
				stacked_item_name
			))
			return false
		end
		if stacked_item.spoil_result ~= nil then
			DBL.log_warning(string.format(
				"Refusing spoilable stack %s because its existing item spoil result cannot be combined safely with trigger spoilage",
				stacked_item_name
			))
			return false
		end

		stacked_item.spoil_ticks = source_item.spoil_ticks
		stacked_item.spoil_result = nil
		stacked_item.spoil_to_trigger_result = desired_trigger_result
		verified_exact_trigger_results[stacked_item_name] = table.deepcopy(desired_trigger_result)
		for _, property_name in ipairs(spoil_properties) do
			stacked_item[property_name] = copy(source_item[property_name])
		end
		copy_spoil_time_flag(stacked_item, source_item)
		return true
	end

	local result, result_type = find_item_prototype(source_item.spoil_result)
	local desired_result = matching_stacked_result(source_ratio, source_item.spoil_result, result_type)
		or create_bundle(source_item.spoil_result, result, source_ratio.numerator)
	if not desired_result then
		return false
	end
	local existing_result_is_our_exact_bundle = stacked_item.spoil_result
		and exact_bundle_exists(
			stacked_item.spoil_result,
			bundle_recipe_name(source_item.spoil_result, source_ratio.numerator),
			source_item.spoil_result,
			source_ratio.numerator
		)
	if stacked_item.spoil_result
		and stacked_item.spoil_result ~= desired_result
		and not existing_result_is_our_exact_bundle
	then
		DBL.log_warning(string.format(
			"Refusing spoilable stack %s because existing spoil result %s cannot be proven exact",
			stacked_item_name,
			stacked_item.spoil_result
		))
		return false
	end
	local existing_trigger_result = stacked_item.spoil_to_trigger_result
	local verified_trigger_result = verified_exact_trigger_results[stacked_item_name]
	if existing_trigger_result
		and not (verified_trigger_result and deep_equal(existing_trigger_result, verified_trigger_result))
	then
		DBL.log_warning(string.format(
			"Refusing spoilable stack %s because its existing trigger spoil result cannot be replaced safely",
			stacked_item_name
		))
		return false
	end

	stacked_item.spoil_ticks = source_item.spoil_ticks
	stacked_item.spoil_result = desired_result
	stacked_item.spoil_to_trigger_result = nil
	verified_exact_trigger_results[stacked_item_name] = nil
	for _, property_name in ipairs(spoil_properties) do
		stacked_item[property_name] = copy(source_item[property_name])
	end
	copy_spoil_time_flag(stacked_item, source_item)
	return true
end

return DBL
