local DBL = require("prototypes.shared")

local BUNDLE_PREFIX = "deadlock-stacked-fuel-residue-"
local BUNDLE_RECIPE_PREFIX = "deadlock-stacked-fuel-residue-unpack-"
local verified_exact_bundles = {}
local verified_bundle_recipes = {}
local remove_unused_bundle

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

local fuel_properties = {
	"fuel_category",
	"fuel_acceleration_multiplier",
	"fuel_top_speed_multiplier",
	"fuel_emissions_multiplier",
	"fuel_acceleration_multiplier_quality_bonus",
	"fuel_top_speed_multiplier_quality_bonus",
	"fuel_glow_color",
}

local function copy(value)
	if type(value) == "table" then
		return table.deepcopy(value)
	end
	return value
end

local function find_item_prototype(item_name)
	for _, item_type in ipairs(item_prototype_types) do
		if data.raw[item_type] and data.raw[item_type][item_name] then
			return data.raw[item_type][item_name], item_type
		end
	end
	return nil, nil
end

local function greatest_common_divisor(a, b)
	while b ~= 0 do
		a, b = b, a % b
	end
	return a
end

local function make_ratio(numerator, denominator)
	if type(numerator) ~= "number" or type(denominator) ~= "number" then
		return nil
	end
	if numerator <= 0 or denominator <= 0 then
		return nil
	end
	if numerator % 1 ~= 0 or denominator % 1 ~= 0 then
		return nil
	end
	local divisor = greatest_common_divisor(numerator, denominator)
	return {
		numerator = numerator / divisor,
		denominator = denominator / divisor,
	}
end

local function ratios_equal(left, right)
	return left
		and right
		and left.numerator == right.numerator
		and left.denominator == right.denominator
end

local function invert_ratio(ratio)
	if not ratio then
		return nil
	end
	return make_ratio(ratio.denominator, ratio.numerator)
end

local function product_name(product)
	return product.name or product[1]
end

local function product_type(product)
	return product.type or "item"
end

local function exact_product_amount(product)
	if product.probability and product.probability ~= 1 then
		return nil
	end
	if product.amount then
		return product.amount
	end
	if product[2] then
		return product[2]
	end
	if product.amount_min and product.amount_max and product.amount_min == product.amount_max then
		return product.amount_min
	end
	return nil
end

local function total_item_amount(products, item_name)
	if type(products) ~= "table" then
		return nil
	end
	local total = 0
	local found = false
	for _, product in pairs(products) do
		if product_type(product) == "item" and product_name(product) == item_name then
			local amount = exact_product_amount(product)
			if not amount or amount <= 0 then
				return nil
			end
			total = total + amount
			found = true
		end
	end
	if not found then
		return nil
	end
	return total
end

local function recipe_variants(recipe)
	local variants = {}
	if recipe.ingredients or recipe.results or recipe.result then
		table.insert(variants, recipe)
	end
	if recipe.normal then
		table.insert(variants, recipe.normal)
	end
	if recipe.expensive then
		table.insert(variants, recipe.expensive)
	end
	return variants
end

local function result_amount(variant, item_name)
	if variant.results then
		return total_item_amount(variant.results, item_name)
	end
	if variant.result == item_name then
		return variant.result_count or 1
	end
	return nil
end

local function recipe_ratio(recipe, ingredient_name, result_name)
	if not recipe then
		return nil
	end
	local expected_ratio
	local variants = recipe_variants(recipe)
	if #variants == 0 then
		return nil
	end
	for _, variant in ipairs(variants) do
		local ingredient_amount = total_item_amount(variant.ingredients, ingredient_name)
		local output_amount = result_amount(variant, result_name)
		local variant_ratio = make_ratio(ingredient_amount, output_amount)
		if not variant_ratio then
			return nil
		end
		if expected_ratio and not ratios_equal(expected_ratio, variant_ratio) then
			return nil
		end
		expected_ratio = variant_ratio
	end
	return expected_ratio
end

local function only_entry(entries)
	if type(entries) ~= "table" then
		return nil
	end
	local entry
	local count = 0
	for _, candidate in pairs(entries) do
		count = count + 1
		entry = candidate
	end
	if count ~= 1 then
		return nil
	end
	return entry
end

local function has_quality_controls(product)
	return product.quality_min ~= nil
		or product.quality_max ~= nil
		or product.quality_change ~= nil
end

local function is_exact_recipe_entry(entry, item_name, amount, is_product)
	if type(entry) ~= "table"
		or product_type(entry) ~= "item"
		or product_name(entry) ~= item_name
		or has_quality_controls(entry)
	then
		return false
	end
	if is_product and (
		entry.probability ~= nil
		or entry.amount_min ~= nil
		or entry.amount_max ~= nil
	) then
		return false
	end
	return (entry.amount or entry[2]) == amount
end

local function variant_is_exact_conversion(variant, ingredient_name, ingredient_amount, result_name, result_amount)
	local ingredient = only_entry(variant.ingredients)
	if not is_exact_recipe_entry(ingredient, ingredient_name, ingredient_amount, false) then
		return false
	end
	if variant.results then
		local result = only_entry(variant.results)
		return is_exact_recipe_entry(result, result_name, result_amount, true)
	end
	return variant.result == result_name
		and (variant.result_count or 1) == result_amount
end

local function recipe_has_category(recipe, category_name)
	if recipe.categories then
		for _, category in pairs(recipe.categories) do
			if category == category_name then
				return true
			end
		end
		return false
	end
	return recipe.category == category_name
end

local function recipe_is_exact_conversion(recipe, ingredient_name, ingredient_amount, result_name, result_amount, category_name)
	if not recipe
		or recipe.can_set_quality == false
		or not recipe_has_category(recipe, category_name)
	then
		return false
	end
	local variants = recipe_variants(recipe)
	if #variants == 0 then
		return false
	end
	for _, variant in ipairs(variants) do
		if not variant_is_exact_conversion(
			variant,
			ingredient_name,
			ingredient_amount,
			result_name,
			result_amount
		) then
			return false
		end
	end
	return true
end

local function represented_ratio(base_item_name, stacked_item_name, source_item_type)
	local source_item
	if source_item_type and data.raw[source_item_type] then
		source_item = data.raw[source_item_type][base_item_name]
	else
		source_item = find_item_prototype(base_item_name)
	end
	if not source_item
		or type(source_item.stack_size) ~= "number"
		or source_item.stack_size <= 0
		or source_item.stack_size % 1 ~= 0
	then
		return nil
	end

	local represented_count = math.min(DBL.STACK_SIZE, source_item.stack_size)
	local recipe_multiplier = DBL.RECIPE_MULTIPLIER
	if type(represented_count) ~= "number"
		or represented_count <= 0
		or represented_count % 1 ~= 0
		or type(recipe_multiplier) ~= "number"
		or recipe_multiplier <= 0
		or recipe_multiplier % 1 ~= 0
	then
		return nil
	end

	local stack_recipe = data.raw.recipe["deadlock-stacks-stack-" .. base_item_name]
	local unstack_recipe = data.raw.recipe["deadlock-stacks-unstack-" .. base_item_name]
	if not recipe_is_exact_conversion(
		stack_recipe,
		base_item_name,
		represented_count * recipe_multiplier,
		stacked_item_name,
		recipe_multiplier,
		"stacking"
	) or not recipe_is_exact_conversion(
		unstack_recipe,
		stacked_item_name,
		recipe_multiplier,
		base_item_name,
		represented_count * recipe_multiplier,
		"unstacking"
	) then
		return nil
	end
	return make_ratio(represented_count, 1)
end

local function multiply_digit_string(digits, multiplier)
	local result = {}
	local carry = 0
	for index = #digits, 1, -1 do
		local product = tonumber(string.sub(digits, index, index)) * multiplier + carry
		table.insert(result, 1, string.format("%d", product % 10))
		carry = math.floor(product / 10)
	end
	while carry > 0 do
		table.insert(result, 1, string.format("%d", carry % 10))
		carry = math.floor(carry / 10)
	end
	return table.concat(result)
end

local function multiply_number_unit(property, multiplier)
	if type(property) ~= "string"
		or type(multiplier) ~= "number"
		or multiplier <= 0
		or multiplier % 1 ~= 0
	then
		return nil
	end

	local value, unit = string.match(property, "^%s*([%d]+%.?[%d]*)%s*([kMGTPEZYRQ]?[JW])%s*$")
	if not value then
		value, unit = string.match(property, "^%s*(%.[%d]+)%s*([kMGTPEZYRQ]?[JW])%s*$")
	end
	if not value then
		return nil
	end

	local whole, fraction = string.match(value, "^(%d*)%.(%d*)$")
	if not whole then
		whole = value
		fraction = ""
	end
	local digits = string.gsub(whole .. fraction, "^0+", "")
	if digits == "" then
		return nil
	end

	local multiplied = multiply_digit_string(digits, multiplier)
	local decimal_places = #fraction
	if decimal_places > 0 then
		while #multiplied <= decimal_places do
			multiplied = "0" .. multiplied
		end
		local split = #multiplied - decimal_places
		multiplied = string.sub(multiplied, 1, split) .. "." .. string.sub(multiplied, split + 1)
		multiplied = string.gsub(multiplied, "0+$", "")
		multiplied = string.gsub(multiplied, "%.$", "")
	end
	multiplied = string.gsub(multiplied, "^0+(%d)", "%1")
	if string.sub(multiplied, 1, 1) == "." then
		multiplied = "0" .. multiplied
	end
	return multiplied .. unit
end

local function remove_fuel_properties(stacked_item)
	local previous_burnt_result = stacked_item.burnt_result
	stacked_item.fuel_value = nil
	stacked_item.burnt_result = nil
	for _, property_name in ipairs(fuel_properties) do
		stacked_item[property_name] = nil
	end
	if remove_unused_bundle then
		remove_unused_bundle(previous_burnt_result)
	end
end

local function apply_fuel_properties(stacked_item, source_item, represented_count)
	for _, property_name in ipairs(fuel_properties) do
		stacked_item[property_name] = copy(source_item[property_name])
	end
	stacked_item.fuel_value = multiply_number_unit(source_item.fuel_value, represented_count)
	return stacked_item.fuel_value ~= nil
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

local function bundle_name(residue_name, represented_count)
	return string.format("%s%s-%d", BUNDLE_PREFIX, residue_name, represented_count)
end

local function bundle_recipe_name(residue_name, represented_count)
	return string.format("%s%s-%d", BUNDLE_RECIPE_PREFIX, residue_name, represented_count)
end

local function recipe_has_only_item(products, item_name)
	if type(products) ~= "table" then
		return false
	end
	local found = false
	for _, product in pairs(products) do
		if product_type(product) ~= "item"
			or product_name(product) ~= item_name
			or has_quality_controls(product)
		then
			return false
		end
		if not exact_product_amount(product) then
			return false
		end
		found = true
	end
	return found
end

local function variant_has_only_conversion(variant, ingredient_name, result_name)
	if not recipe_has_only_item(variant.ingredients, ingredient_name) then
		return false
	end
	if variant.results then
		return recipe_has_only_item(variant.results, result_name)
	end
	return variant.result == result_name and (variant.result_count or 1) > 0
end

local function recipe_has_only_conversion(recipe, ingredient_name, result_name)
	local variants = recipe_variants(recipe)
	if #variants == 0 then
		return false
	end
	for _, variant in ipairs(variants) do
		if not variant_has_only_conversion(variant, ingredient_name, result_name) then
			return false
		end
	end
	return true
end

local function recipe_is_unlocked(recipe_name)
	for _, technology in pairs(data.raw.technology or {}) do
		if technology.enabled ~= false then
			for _, effect in pairs(technology.effects or {}) do
				if effect.type == "unlock-recipe" and effect.recipe == recipe_name then
					return true
				end
			end
		end
	end
	return false
end

local function list_has_value(values, expected)
	for _, value in pairs(values or {}) do
		if value == expected then
			return true
		end
	end
	return false
end

local function category_is_available(category_name)
	for _, character in pairs(data.raw.character or {}) do
		if list_has_value(character.crafting_categories, category_name) then
			return true
		end
	end
	for _, prototype_type in ipairs({"assembling-machine", "furnace", "rocket-silo"}) do
		for _, machine in pairs(data.raw[prototype_type] or {}) do
			if list_has_value(machine.crafting_categories, category_name) then
				return true
			end
		end
	end
	return false
end

local function recipe_category_is_available(recipe)
	local categories = recipe.categories or (recipe.category and {recipe.category}) or {"crafting"}
	for _, category in pairs(categories) do
		if category_is_available(category) then
			return true
		end
	end
	return false
end

local function recipe_is_usable(recipe)
	return (recipe.enabled ~= false or recipe_is_unlocked(recipe.name))
		and recipe_category_is_available(recipe)
end

local function exact_conversion_exists(item_name, residue_name, expected_ratio)
	local item = find_item_prototype(item_name)
	if not item or item.fuel_value or item.burnt_result then
		return false
	end
	for recipe_name, recipe in pairs(data.raw.recipe) do
		if recipe_has_only_conversion(recipe, item_name, residue_name)
			and recipe_is_usable(recipe)
			and recipe.can_set_quality ~= false
			and ratios_equal(invert_ratio(recipe_ratio(recipe, item_name, residue_name)), expected_ratio)
		then
			DBL.debug(string.format("Using exact residue conversion %s for %s", recipe_name, item_name))
			return true
		end
	end
	return false
end

local function create_bundle(residue_name, residue, represented_count)
	local name = bundle_name(residue_name, represented_count)
	local recipe_name = bundle_recipe_name(residue_name, represented_count)
	local expected_ratio = make_ratio(represented_count, 1)
	local existing_item = find_item_prototype(name)
	local existing_recipe = data.raw.recipe[recipe_name]

	if existing_item or existing_recipe then
		if verified_exact_bundles[name]
			and existing_item
			and existing_recipe
			and exact_conversion_exists(name, residue_name, expected_ratio)
		then
			return name
		end
		DBL.log_error(string.format(
			"Cannot create exact residue bundle %s because its item or recipe name is already in use by an incompatible prototype",
			name
		))
		return nil
	end

	local icons = prototype_icons(residue)
	if not icons then
		DBL.log_error(string.format(
			"Cannot create exact residue bundle for %s because the residue has no icon",
			residue_name
		))
		return nil
	end

	local recipe_icons = table.deepcopy(icons)
	table.insert(recipe_icons, {
		icon = "__deadlock-beltboxes-loaders-continued__/graphics/icons/square/arrow-u-64.png",
		icon_size = 64,
		scale = 0.25,
	})

	local bundle_stack_size = 1
	if residue.stack_size then
		bundle_stack_size = math.max(1, math.floor(residue.stack_size / represented_count))
	end

	local bundle = {
		type = "item",
		name = name,
		localised_name = {
			"item-name.deadlock-stacking-stack",
			localised_item_name(residue_name, residue),
			tostring(represented_count),
		},
		icons = icons,
		stack_size = bundle_stack_size,
		hidden = true,
		hidden_in_factoriopedia = true,
		flags = {},
		subgroup = residue.subgroup or "other",
		order = string.format("%s[deadlock-residue-%d]", residue.order or "z", represented_count),
		auto_recycle = false,
		inventory_move_sound = copy(residue.inventory_move_sound),
		pick_sound = copy(residue.pick_sound),
		drop_sound = copy(residue.drop_sound),
	}
	if residue.weight then
		bundle.weight = residue.weight * represented_count
	end

	local recipe = {
		type = "recipe",
		name = recipe_name,
		localised_name = {
			"recipe-name.deadlock-stacking-unstack",
			localised_item_name(residue_name, residue),
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
		results = {{type = "item", name = residue_name, amount = represented_count}},
		energy_required = math.max(0.1, represented_count / 15),
		icons = recipe_icons,
		allow_as_intermediate = false,
		hide_from_stats = true,
		auto_recycle = false,
		can_set_quality = true,
	}

	data:extend({bundle, recipe})
	verified_exact_bundles[name] = true
	verified_bundle_recipes[name] = recipe_name
	DBL.debug(string.format(
		"Created exact residue bundle %s representing %d %s",
		name,
		represented_count,
		residue_name
	))
	return name
end

local function contains_reference(value, item_name, recipe_name, seen)
	if type(value) == "string" then
		return value == item_name or value == recipe_name
	end
	if type(value) ~= "table" then
		return false
	end
	seen = seen or {}
	if seen[value] then
		return false
	end
	seen[value] = true
	for key, nested in pairs(value) do
		if contains_reference(key, item_name, recipe_name, seen)
			or contains_reference(nested, item_name, recipe_name, seen)
		then
			return true
		end
	end
	return false
end

remove_unused_bundle = function(item_name)
	local recipe_name = verified_bundle_recipes[item_name]
	if not recipe_name then
		return
	end

	for prototype_type, prototypes in pairs(data.raw) do
		for prototype_name, prototype in pairs(prototypes) do
			local is_bundle_item = prototype_type == "item" and prototype_name == item_name
			local is_bundle_recipe = prototype_type == "recipe" and prototype_name == recipe_name
			if not is_bundle_item
				and not is_bundle_recipe
				and contains_reference(prototype, item_name, recipe_name)
			then
				return
			end
		end
	end

	data.raw.recipe[recipe_name] = nil
	data.raw.item[item_name] = nil
	verified_bundle_recipes[item_name] = nil
	verified_exact_bundles[item_name] = nil
	DBL.debug(string.format("Removed unused exact residue bundle %s", item_name))
end

local function set_burnt_result(stacked_item, item_name)
	local previous_burnt_result = stacked_item.burnt_result
	stacked_item.burnt_result = item_name
	if previous_burnt_result ~= item_name then
		remove_unused_bundle(previous_burnt_result)
	end
end

local function existing_result_is_known_incorrect(existing_result, residue_name, normal_stack_name)
	return existing_result == residue_name
		or existing_result == normal_stack_name
		or verified_exact_bundles[existing_result] == true
end

local function matching_normal_burnt_result(source_ratio, residue_name)
	local normal_stack_name = "deadlock-stack-" .. residue_name
	local normal_stack = data.raw.item[normal_stack_name]
	local normal_unstack_recipe = data.raw.recipe["deadlock-stacks-unstack-" .. residue_name]
	if normal_stack and normal_unstack_recipe and recipe_is_usable(normal_unstack_recipe) then
		local residue_ratio = represented_ratio(residue_name, normal_stack_name)
		if ratios_equal(source_ratio, residue_ratio) then
			return normal_stack_name
		end
	end
	return nil
end

local function choose_exact_bundle(source_ratio, residue_name, residue)
	if source_ratio.denominator ~= 1 then
		DBL.log_warning(string.format(
			"Cannot represent fractional burnt-result quantity %d/%d for %s",
			source_ratio.numerator,
			source_ratio.denominator,
			residue_name
		))
		return nil
	end
	return create_bundle(residue_name, residue, source_ratio.numerator)
end

function DBL.is_exact_residue_bundle(item_name)
	return verified_exact_bundles[item_name] == true
end

function DBL.get_stack_represented_ratio(base_item_name, source_item_type)
	return represented_ratio(base_item_name, "deadlock-stack-" .. base_item_name, source_item_type)
end

function DBL.update_stacked_fuel(stacked_item_name, source_item_name, source_item_type)
	local stacked_item = data.raw.item[stacked_item_name]
	local source_item = data.raw[source_item_type] and data.raw[source_item_type][source_item_name]
	if not stacked_item then
		return
	end
	if not source_item or not source_item.fuel_value then
		remove_fuel_properties(stacked_item)
		return
	end

	local source_ratio = represented_ratio(source_item_name, stacked_item_name, source_item_type)
	if not source_ratio then
		DBL.log_warning(string.format(
			"Disabling fuel behavior for %s because its stack and unstack recipes do not exactly match the expected Deadlock density",
			stacked_item_name
		))
		remove_fuel_properties(stacked_item)
		return
	end

	local existing_result = stacked_item.burnt_result
	if not apply_fuel_properties(stacked_item, source_item, source_ratio.numerator) then
		DBL.log_warning(string.format(
			"Disabling fuel behavior for %s because its fuel value cannot be multiplied safely",
			stacked_item_name
		))
		remove_fuel_properties(stacked_item)
		return
	end

	if not source_item.burnt_result then
		set_burnt_result(stacked_item, nil)
		return
	end

	local residue_name = source_item.burnt_result
	local residue = find_item_prototype(residue_name)
	if not residue then
		DBL.log_warning(string.format(
			"Disabling fuel behavior for %s because burnt result %s is not an item prototype",
			stacked_item_name,
			residue_name
		))
		remove_fuel_properties(stacked_item)
		return
	end

	local normal_result = matching_normal_burnt_result(source_ratio, residue_name)
	if existing_result then
		if normal_result and existing_result == normal_result then
			return
		end
		if normal_result and DBL.is_exact_residue_bundle(existing_result) then
			set_burnt_result(stacked_item, normal_result)
			return
		end
		if (existing_result == residue_name and ratios_equal(source_ratio, make_ratio(1, 1)))
			or exact_conversion_exists(existing_result, residue_name, source_ratio)
		then
			DBL.debug(string.format(
				"Preserving existing exact burnt result %s on %s",
				existing_result,
				stacked_item_name
			))
			return
		end

		local normal_stack_name = "deadlock-stack-" .. residue_name
		if not existing_result_is_known_incorrect(existing_result, residue_name, normal_stack_name) then
			DBL.log_warning(string.format(
				"Disabling fuel behavior for %s because existing burnt result %s cannot be proven exact",
				stacked_item_name,
				existing_result
			))
			remove_fuel_properties(stacked_item)
			return
		end
	end

	local desired_result = normal_result or choose_exact_bundle(source_ratio, residue_name, residue)
	if not desired_result then
		remove_fuel_properties(stacked_item)
		return
	end

	set_burnt_result(stacked_item, desired_result)
end

return DBL
