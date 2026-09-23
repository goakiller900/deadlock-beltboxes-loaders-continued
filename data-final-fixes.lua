-- Factorio 2.1 merged RecipePrototype.category and additional_categories into categories.
-- Keep compatibility for recipes created by this mod/API and by older bridge mods.
for _, recipe in pairs(data.raw.recipe) do
	if recipe.category then
		recipe.categories = recipe.categories or { recipe.category }
		recipe.category = nil
	end
	if recipe.additional_categories then
		recipe.categories = recipe.categories or {}
		for _, category in pairs(recipe.additional_categories) do
			table.insert(recipe.categories, category)
		end
		recipe.additional_categories = nil
	end
end

-- run late stack updates for changes to stack sizes, fuel values, etc
deadlock.deferred_stacked_item_updates()

-- update the character prototype to allow "hand-unstacking"
table.insert(data.raw["character"]["character"].crafting_categories, "unstacking")

-- Fix for Factorio 2.1.20+ prototype requirements
-- Iterates through all created items and safely converts fuel properties into table structures
for item_name, item_prototype in pairs(data.raw["item"]) do
    if item_name:find("^deadlock%-stack%-") and item_prototype.fuel_value then
        if not item_prototype.fuel_categories or type(item_prototype.fuel_categories) ~= "table" then
            -- Attempt to read categories from the base item blueprint
            local base_name = item_name:gsub("^deadlock%-stack%-", "")
            local base_item = data.raw["item"][base_name]
            
            if base_item and base_item.fuel_categories and type(base_item.fuel_categories) == "table" then
                item_prototype.fuel_categories = base_item.fuel_categories
            elseif base_item and base_item.fuel_category then
                item_prototype.fuel_categories = {base_item.fuel_category}
            else
                item_prototype.fuel_categories = {"chemical"} -- Standard baseline fallback
            end
            
            -- Strip out legacy single string property to satisfy the strict validation
            item_prototype.fuel_category = nil 
        end
    end
end
