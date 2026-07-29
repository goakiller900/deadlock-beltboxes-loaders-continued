local DBL = require("prototypes.shared")

local WEIGHT_CATEGORY = "deadlock-stacking-weight-calculation"
local verified_weight_recipes = {}

local function ensure_weight_category()
	data.raw["recipe-category"] = data.raw["recipe-category"] or {}
	if not data.raw["recipe-category"][WEIGHT_CATEGORY] then
		data:extend({
			{
				type = "recipe-category",
				name = WEIGHT_CATEGORY,
			},
		})
	end
end

local function weight_recipe_is_ours(recipe_name)
	local recipe = data.raw.recipe and data.raw.recipe[recipe_name]
	return verified_weight_recipes[recipe_name] == true
		and recipe ~= nil
		and recipe.name == recipe_name
		and recipe.categories ~= nil
		and #recipe.categories == 1
		and recipe.categories[1] == WEIGHT_CATEGORY
end

local function create_or_update_weight_recipe(
	weighted_item_name,
	source_item_name,
	represented_count
)
	ensure_weight_category()

	local recipe = data.raw.recipe and data.raw.recipe[weighted_item_name]
	if recipe and not weight_recipe_is_ours(weighted_item_name) then
		DBL.log_error(string.format(
			"Cannot calculate automatic weight for %s because recipe name %s is already in use",
			weighted_item_name,
			weighted_item_name
		))
		return false
	end

	local ingredients = {{
		type = "item",
		name = source_item_name,
		amount = represented_count,
	}}
	local results = {{
		type = "item",
		name = weighted_item_name,
		amount = 1,
		-- The weight algorithm needs the recipe to support productivity to avoid
		-- its non-productivity one-stack weight clamp. Excluding the entire
		-- result and setting maximum_productivity to zero makes a bonus
		-- impossible even if a future machine gains this private category.
		ignored_by_productivity = 1,
	}}

	if recipe then
		recipe.ingredients = ingredients
		recipe.results = results
		return true
	end

	data:extend({
		{
			type = "recipe",
			-- A recipe matching the product name is always Factorio's first
			-- weight-calculation candidate.
			name = weighted_item_name,
			categories = {WEIGHT_CATEGORY},
			enabled = false,
			hidden = false,
			hidden_in_factoriopedia = true,
			hide_from_player_crafting = true,
			hide_from_signal_gui = true,
			hide_from_stats = true,
			hide_from_bonus_gui = true,
			allow_decomposition = true,
			allow_as_intermediate = false,
			allow_intermediates = false,
			unlock_results = false,
			requires_ingredients_to_unlock_results = false,
			allow_inserter_overload = false,
			ingredients = ingredients,
			results = results,
			energy_required = 1,
			allow_consumption = false,
			allow_speed = false,
			allow_productivity = true,
			maximum_productivity = 0,
			allow_pollution = false,
			allow_quality = false,
			can_set_quality = false,
			auto_recycle = false,
			raise_on_crafted = false,
		},
	})
	verified_weight_recipes[weighted_item_name] = true
	return true
end

function DBL.apply_represented_item_weight(
	weighted_item_name,
	source_item_name,
	source_item,
	represented_count
)
	local weighted_item = data.raw.item and data.raw.item[weighted_item_name]
	if not weighted_item
		or not source_item
		or type(represented_count) ~= "number"
		or represented_count <= 0
		or represented_count % 1 ~= 0
	then
		return false
	end

	if type(source_item.weight) == "number" then
		weighted_item.weight = source_item.weight * represented_count
		return true
	end

	-- A coefficient of 1 makes the private recipe's ingredient weight equal
	-- the represented source items' effective weight without the default 0.5
	-- material-loss coefficient.
	weighted_item.weight = nil
	weighted_item.ingredient_to_weight_coefficient = 1
	return create_or_update_weight_recipe(
		weighted_item_name,
		source_item_name,
		represented_count
	)
end

function DBL.update_stacked_weight(stacked_item_name, source_item_name, source_item_type)
	local source_prototypes = data.raw[source_item_type]
	local source_item = source_prototypes and source_prototypes[source_item_name]
	local represented_ratio = DBL.get_stack_represented_ratio
		and DBL.get_stack_represented_ratio(source_item_name, source_item_type)

	if not represented_ratio or represented_ratio.denominator ~= 1 then
		DBL.log_error(string.format(
			"Cannot synchronize weight for %s because its stack recipes do not have an exact represented item count",
			stacked_item_name
		))
		return false
	end

	return DBL.apply_represented_item_weight(
		stacked_item_name,
		source_item_name,
		source_item,
		represented_ratio.numerator
	)
end

return DBL
