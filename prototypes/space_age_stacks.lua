if not (mods and mods["space-age"]) then
	return
end

local DBL = require("prototypes.shared")

local registrations = {
	-- Tier 1: raw planetary resources and basic biological items.
	{tier = 1, name = "calcite", type = "item"},
	{tier = 1, name = "holmium-ore", type = "item"},
	{tier = 1, name = "ice", type = "item"},
	{tier = 1, name = "scrap", type = "item"},
	{tier = 1, name = "spoilage", type = "item"},
	{tier = 1, name = "biter-egg", type = "item", exact_trigger_spoilage = true},
	{tier = 1, name = "pentapod-egg", type = "item", exact_trigger_spoilage = true},
	{tier = 1, name = "jellynut", type = "capsule"},
	{tier = 1, name = "yumako", type = "capsule"},
	{tier = 1, name = "raw-fish", type = "capsule"},

	-- Tier 2: processed planetary materials and biological intermediates.
	{tier = 2, name = "carbon", type = "item"},
	{tier = 2, name = "holmium-plate", type = "item"},
	{tier = 2, name = "lithium", type = "item"},
	{tier = 2, name = "superconductor", type = "item"},
	{tier = 2, name = "tungsten-carbide", type = "item"},
	{tier = 2, name = "tungsten-plate", type = "item"},
	{tier = 2, name = "bioflux", type = "capsule"},
	{tier = 2, name = "jelly", type = "capsule"},
	{tier = 2, name = "nutrients", type = "item"},
	{tier = 2, name = "yumako-mash", type = "capsule"},

	-- Tier 3: advanced Aquilo intermediates.
	{tier = 3, name = "lithium-plate", type = "item"},
	{tier = 3, name = "quantum-processor", type = "item"},
}

for _, registration in ipairs(registrations) do
	local prototypes = data.raw[registration.type]
	if prototypes and prototypes[registration.name] then
		if registration.exact_trigger_spoilage then
			DBL.allow_exact_trigger_spoilage_source(registration.name, registration.type)
		end
		deadlock.add_stack(
			registration.name,
			string.format(
				"__deadlock-beltboxes-loaders-continued__/graphics/icons/square/stacked-%s.png",
				registration.name
			),
			string.format("deadlock-stacking-%d", registration.tier),
			DBL.VANILLA_ICON_SIZE,
			registration.type
		)
	end
end
