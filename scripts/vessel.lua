-- Interstellar Vessel placement, ownership, lookup, and recovery.

local config = require("scripts.config")
local state = require("scripts.state")

local vessel = {}

local function is_valid(object)
  return object and object.valid ~= false
end

function vessel.platform_for_entity(entity)
  if not is_valid(entity) then return nil end
  local surface = entity.surface
  local platform = surface and surface.platform
  if is_valid(platform) then return platform end
  return nil
end

function vessel.platform_by_index(force, platform_index)
  if not platform_index then return nil end
  local platform = force.platforms and force.platforms[platform_index]
  if is_valid(platform) then return platform end
  return nil
end

function vessel.inventory(entity)
  if not is_valid(entity) then return nil end
  return entity.get_inventory(defines.inventory.chest)
end

function vessel.register(entity, platform, force_state, runtime_script)
  force_state.vessel_unit_number = entity.unit_number
  force_state.vessel_platform_index = platform.index
  local active_script = runtime_script or script
  if active_script and active_script.register_on_object_destroyed then
    local registration = active_script.register_on_object_destroyed(entity)
    force_state.vessel_destroy_registration = registration
  else
    force_state.vessel_destroy_registration = nil
  end
  return entity
end

local function item_quality(entity, event)
  local stack = event and event.stack
  if stack and stack.valid_for_read and stack.quality then return stack.quality.name end
  return entity.quality and entity.quality.name or nil
end

local function refund_stack(entity, event)
  local stack = {name = config.VESSEL_NAME, count = 1}
  local quality = item_quality(entity, event)
  if quality then stack.quality = quality end
  return stack
end

local function spill(surface, position, force, stack)
  if not is_valid(surface) then return false end
  surface.spill_item_stack{
    position = position,
    stack = stack,
    enable_looted = true,
    force = force,
    allow_belts = false,
  }
  return true
end

-- Refund exactly one placement item. This is intentionally actor-aware because
-- build events do not share a common refund inventory in Factorio 2.1.
function vessel.refund(event, context)
  local stack = context.stack
  local player = event.player_index and game.get_player(event.player_index)
  if is_valid(player) then
    if player.insert(stack) == 1 then return "player" end
    spill(context.surface, context.position, context.force, stack)
    return "surface"
  end

  local robot = event.robot
  if is_valid(robot) then
    local inventory = robot.get_inventory(defines.inventory.robot_cargo)
    if inventory and inventory.insert(stack) == 1 then return "robot" end
    spill(context.surface, robot.position or context.position, context.force, stack)
    return "surface"
  end

  local platform = event.platform or context.platform
  local hub = is_valid(platform) and platform.hub or nil
  if is_valid(hub) and hub.insert(stack) == 1 then return "platform" end

  -- Script-raised construction has no consumed player/robot/platform item to
  -- return. Spilling here would manufacture a free vessel for another mod's
  -- placement attempt.
  if event.name == defines.events.script_raised_built
    or event.name == defines.events.script_raised_revive
  then
    return "not-required"
  end

  spill(context.surface, context.position, context.force, stack)
  return "surface"
end

local function reject(entity, event, reason, platform, deps)
  local context = {
    position = {x = entity.position.x, y = entity.position.y},
    surface = entity.surface,
    force = entity.force,
    platform = platform,
    stack = refund_stack(entity, event),
  }
  entity.destroy()
  local destination = vessel.refund(event, context)
  local player = event.player_index and game.get_player(event.player_index)
  local error_key = ({
    ["platform-only"] = "platform-only",
    ["not-enabled"] = context.force and state.ensure_force(context.force).phase
      == config.PHASE.COMPLETE and "mission-complete" or "navigation-required",
    ["already-exists"] = "one-vessel-only",
  })[reason]
  if is_valid(player) and error_key then player.print({"tvh-error." .. error_key}) end
  if deps and deps.on_rejected then deps.on_rejected(context.force, reason, destination) end
  return {accepted = false, reason = reason, refund_destination = destination}
end

function vessel.on_built(event, deps)
  deps = deps or {}
  local entity = event and (event.entity or event.created_entity)
  if not (is_valid(entity) and entity.name == config.VESSEL_NAME) then return nil end

  local platform = vessel.platform_for_entity(entity)
  if not platform then return reject(entity, event, "platform-only", nil, deps) end

  local force_state = state.ensure_force(entity.force)
  if force_state.phase ~= config.PHASE.ENABLED then
    return reject(entity, event, "not-enabled", platform, deps)
  end

  local existing = state.resolve_vessel(force_state)
  if is_valid(existing) and existing.unit_number ~= entity.unit_number then
    return reject(entity, event, "already-exists", platform, deps)
  end

  vessel.register(entity, platform, force_state, deps.script)
  if deps.refresh_force then deps.refresh_force(entity.force) end
  return {accepted = true, entity = entity, platform = platform}
end

function vessel.on_removed(event, deps)
  local entity = event and event.entity
  if not (entity and entity.name == config.VESSEL_NAME and entity.unit_number) then return false end
  local force_state = state.ensure_force(entity.force)
  if force_state.vessel_unit_number ~= entity.unit_number then return false end
  state.clear_vessel(force_state)
  if deps and deps.refresh_force then deps.refresh_force(entity.force) end
  return true
end

function vessel.on_object_destroyed(event, deps)
  local registration = event and event.registration_number
  if not registration then return false end
  for force_index, force_state in pairs(state.get_root().forces) do
    if force_state.vessel_destroy_registration == registration then
      state.clear_vessel(force_state)
      local force = game.forces[force_index]
      if deps and deps.refresh_force and force then deps.refresh_force(force) end
      return true
    end
  end
  return false
end

-- Repair a registration after configuration changes or a save/load. Multiple
-- pre-existing vessels are reported but never destroyed during recovery.
function vessel.recover_force(force, deps)
  deps = deps or {}
  local force_state = state.ensure_force(force)
  if force_state.phase == config.PHASE.COMPLETE then
    state.clear_vessel(force_state)
    return {entity = nil, duplicates = {}}
  end

  local registered = state.resolve_vessel(force_state)
  if is_valid(registered) and registered.force.index == force.index
    and vessel.platform_for_entity(registered)
  then
    local platform = vessel.platform_for_entity(registered)
    if not force_state.vessel_destroy_registration then
      vessel.register(registered, platform, force_state, deps.script)
    else
      force_state.vessel_platform_index = platform.index
    end
    return {entity = registered, platform = platform, duplicates = {}}
  end

  state.clear_vessel(force_state)
  local found = {}
  for _, platform in pairs(force.platforms or {}) do
    if is_valid(platform) and is_valid(platform.surface) then
      local entities = platform.surface.find_entities_filtered{
        name = config.VESSEL_NAME,
        force = force,
      }
      for _, entity in pairs(entities) do found[#found + 1] = entity end
    end
  end
  table.sort(found, function(a, b) return a.unit_number < b.unit_number end)

  local chosen = found[1]
  if chosen then
    local platform = vessel.platform_for_entity(chosen)
    vessel.register(chosen, platform, force_state, deps.script)
  end
  local duplicates = {}
  for index = 2, #found do duplicates[#duplicates + 1] = found[index] end
  if #duplicates > 0 then
    local logger = deps.log or log
    logger("[TVH] Multiple vessels found for force " .. force.name
      .. "; registered unit " .. chosen.unit_number .. " and left duplicates untouched")
  end
  return {entity = chosen, platform = chosen and vessel.platform_for_entity(chosen), duplicates = duplicates}
end

return vessel
