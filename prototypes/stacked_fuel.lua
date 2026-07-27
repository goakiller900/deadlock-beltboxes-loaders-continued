local DBL = require("prototypes.shared")

local BUNDLE_PREFIX = "deadlock-stacked-fuel-residue-"
local BUNDLE_RECIPE_PREFIX = "deadlock-stacked-fuel-residue-unpack-"

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
	"spidertron-remote",
	"tool",
	"upgrade-item",
}

local fuel_properties = {
	"fuel_category",
	"fuel_acceleration_multiplier",
	"fuel_top_speed_multiplier",
	"fuel_emissions_multiplier",
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

local function ratio_as_number(ratio)
	return ratio.numerator / ratio.denominator
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

local function represented_ratio(base_item_name, stacked_item_name)
	local stack_recipe = data.raw.recipe["deadlock-stacks-stack-" .. base_item_name]
	local unstack_recipe = data.raw.recipe["deadlock-stacks-unstack-" .. base_item_name]
	local stack_ratio = recipe_ratio(stack_recipe, base_item_name, stacked_item_name)
	local unstack_ratio = invert_ratio(recipe_ratio(unstack_recipe, stacked_item_name, base_item_name))
	if not ratios_equal(stack_ratio, unstack_ratio) then
		return nil
	end
	return stack_ratio
end

local function multiply_number_unit(property, multiplier)
	if type(property) ~= "string" then
		return nil
	end
	local value, unit = string.match(property, "^%s*([%d%.]+)%s*(%a*)%s*$")
	value = tonumber(value)
	if not value then
		return nil
	end
	return tostring(value * multiplier) .. unit
end

local function remove_fuel_properties(stacked_item)
	stacked_item.fuel_value = nil
	for _, property_name in ipairs(fuel_properties) do
		stacked_item[property_name] = nil
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
		if product_type(product) ~= "item" or product_name(product) ~= item_name then
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
		for _, effect in pairs(technology.effects or {}) do
			if effect.type == "unlock-recipe" and effect.recipe == recipe_name then
				return true
			end
		end
	end
	return false
end

local function recipe_is_usable(recipe)
	return recipe.enabled ~= false or recipe_is_unlocked(recipe.name)
end

local function exact_conversion_exists(item_name, residue_name, expected_ratio)
	local item = find_item_prototype(item_name)
	if not item or item.fuel_value or item.burnt_result then
		return false
	end
	for recipe_name, recipe in pairs(data.raw.recipe) do
		if recipe_has_only_conversion(recipe, item_name, residue_name)
			and recipe_is_usable(recipe)
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
		if existing_item
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
		allow_decomposition = false,
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
		categories = {"crafting", "unstacking"},
		group = "intermediate-products",
		subgroup = bundle.subgroup,
		order = bundle.order,
		enabled = true,
		allow_decomposition = false,
		ingredients = {{type = "item", name = name, amount = 1}},
		results = {{type = "item", name = residue_name, amount = represented_count}},
		energy_required = math.max(0.1, represented_count / 15),
		icons = recipe_icons,
		allow_as_intermediate = false,
		hide_from_stats = true,
	}

	data:extend({bundle, recipe})
	DBL.debug(string.format(
		"Created exact residue bundle %s representing %d %s",
		name,
		represented_count,
		residue_name
	))
	return name
end

local function existing_result_is_known_incorrect(existing_result, residue_name, normal_stack_name)
	return existing_result == residue_name
		or existing_result == normal_stack_name
		or string.sub(existing_result, 1, #BUNDLE_PREFIX) == BUNDLE_PREFIX
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
	return string.sub(item_name, 1, #BUNDLE_PREFIX) == BUNDLE_PREFIX
end

function DBL.get_stack_represented_ratio(base_item_name)
	return represented_ratio(base_item_name, "deadlock-stack-" .. base_item_name)
end

function DBL.update_stacked_fuel(stacked_item_name, source_item_name, source_item_type)
	local stacked_item = data.raw.item[stacked_item_name]
	local source_item = data.raw[source_item_type] and data.raw[source_item_type][source_item_name]
	if not stacked_item or not source_item or not source_item.fuel_value then
		return
	end

	local source_ratio = represented_ratio(source_item_name, stacked_item_name)
	if not source_ratio then
		DBL.log_warning(string.format(
			"Disabling fuel behavior for %s because its represented source count cannot be proven from its stack and unstack recipes",
			stacked_item_name
		))
		remove_fuel_properties(stacked_item)
		return
	end

	if not apply_fuel_properties(stacked_item, source_item, ratio_as_number(source_ratio)) then
		DBL.log_warning(string.format(
			"Disabling fuel behavior for %s because its fuel value cannot be multiplied safely",
			stacked_item_name
		))
		remove_fuel_properties(stacked_item)
		return
	end

	if not source_item.burnt_result then
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
	local existing_result = stacked_item.burnt_result
	if existing_result then
		if normal_result and existing_result == normal_result then
			return
		end
		if normal_result and DBL.is_exact_residue_bundle(existing_result) then
			stacked_item.burnt_result = normal_result
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

	stacked_item.burnt_result = desired_result
end

return DBL
