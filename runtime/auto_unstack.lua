local auto_unstack = {}

local STACK_PREFIX = "deadlock-stack-"

local function quality_name(stack)
	local ok, quality = pcall(function()
		return stack.quality
	end)
	if not ok or quality == nil then
		return nil
	end
	if type(quality) == "string" then
		return quality
	end
	return quality.name
end

local function stack_spoil_metadata(stack)
	local ok_tick, spoil_tick = pcall(function()
		return stack.spoil_tick
	end)
	local spoilable = ok_tick and type(spoil_tick) == "number" and spoil_tick ~= 0
	if not spoilable then
		return true, nil
	end
	local ok_percent, spoil_percent = pcall(function()
		return stack.spoil_percent
	end)
	if not ok_percent or type(spoil_percent) ~= "number" then
		return false, nil
	end
	return true, spoil_percent
end

local function is_stacked_item(item_name)
	return type(item_name) == "string"
		and string.sub(item_name, 1, #STACK_PREFIX) == STACK_PREFIX
end

local function stack_matches_output(stack, item_name, quality, spoil_percent)
	if not stack.valid_for_read
		or stack.name ~= item_name
		or quality_name(stack) ~= quality
	then
		return false
	end
	if spoil_percent == nil then
		return true
	end
	local metadata_available, existing_spoil_percent = stack_spoil_metadata(stack)
	return metadata_available and existing_spoil_percent == spoil_percent
end

-- Plan one represented bundle without mutating either inventory. Existing output
-- stacks are used only when their quality and freshness are identical; otherwise
-- a filtered/barred destination must expose an empty slot that can accept the
-- exact ItemStackDefinition.
local function plan_one_bundle(
	receiving_inventory,
	base_name,
	base_stack_size,
	represented_count,
	quality,
	spoil_percent
)
	local remaining = represented_count
	local existing = {}
	local empty
	local definition = {
		name = base_name,
		count = represented_count,
		quality = quality,
	}
	if spoil_percent ~= nil then
		definition.spoil_percent = spoil_percent
	end

	for index = 1, #receiving_inventory do
		local destination = receiving_inventory[index]
		if stack_matches_output(destination, base_name, quality, spoil_percent) then
			local amount = math.min(remaining, base_stack_size - destination.count)
			if amount > 0 then
				table.insert(existing, {stack = destination, amount = amount})
				remaining = remaining - amount
				if remaining == 0 then break end
			end
		elseif not destination.valid_for_read and not empty then
			local candidate = {
				name = definition.name,
				count = remaining,
				quality = definition.quality,
				spoil_percent = definition.spoil_percent,
			}
			local ok, accepted = pcall(function()
				return destination.can_set_stack(candidate)
			end)
			if ok and accepted then
				empty = {stack = destination, definition = candidate}
				remaining = 0
				break
			end
		end
	end

	if remaining ~= 0 then
		return nil
	end
	return {existing = existing, empty = empty}
end

local function apply_plan(plan)
	-- set_stack can fail without changing the slot. Apply the empty-slot write
	-- first, then the infallible bounded count increments.
	if plan.empty then
		local ok, written = pcall(function()
			return plan.empty.stack.set_stack(plan.empty.definition)
		end)
		if not ok or not written then
			return false
		end
	end
	for _, addition in ipairs(plan.existing) do
		addition.stack.count = addition.stack.count + addition.amount
	end
	return true
end

function auto_unstack.convert_stack(source_stack, receiving_inventory, configured_stack_size, maximum_count)
	if not source_stack or not source_stack.valid_for_read or not is_stacked_item(source_stack.name) then
		return 0, nil
	end

	local base_name = string.sub(source_stack.name, #STACK_PREFIX + 1)
	local base_prototype = prototypes.item[base_name]
	if not base_prototype then
		return 0, "missing-base-prototype"
	end

	local quality = quality_name(source_stack)
	if not quality then
		return 0, "quality-unavailable"
	end
	local metadata_available, spoil_percent = stack_spoil_metadata(source_stack)
	if not metadata_available then
		return 0, "spoil-metadata-unavailable"
	end

	local represented_count = math.min(configured_stack_size, base_prototype.stack_size)
	local source_count = source_stack.count
	if maximum_count then
		source_count = math.min(source_count, maximum_count)
	end
	if source_count <= 0 or represented_count <= 0 then
		return 0, nil
	end

	local converted = 0
	while converted < source_count do
		local plan = plan_one_bundle(
			receiving_inventory,
			base_name,
			base_prototype.stack_size,
			represented_count,
			quality,
			spoil_percent
		)
		if not plan then
			break
		end
		if not apply_plan(plan) then
			return converted, "destination-write-failed"
		end
		source_stack.count = source_stack.count - 1
		converted = converted + 1
	end

	return converted, nil
end

function auto_unstack.convert_inventory(
	sending_inventory,
	receiving_inventory,
	configured_stack_size,
	filter_name,
	filter_quality,
	maximum_count
)
	local converted = 0
	local first_refusal
	for index = #sending_inventory, 1, -1 do
		local stack = sending_inventory[index]
		if stack and stack.valid_for_read and is_stacked_item(stack.name) then
			local stack_quality = quality_name(stack)
			local name_matches = not filter_name or stack.name == filter_name
			local quality_matches = not filter_quality or stack_quality == filter_quality
			if name_matches and quality_matches then
				local remaining = maximum_count and (maximum_count - converted) or nil
				if remaining == nil or remaining > 0 then
					local count, refusal = auto_unstack.convert_stack(
						stack,
						receiving_inventory,
						configured_stack_size,
						remaining
					)
					converted = converted + count
					if refusal and not first_refusal then
						first_refusal = {name = stack.name, reason = refusal}
					end
				end
			end
		end
	end
	return converted, first_refusal
end

return auto_unstack
