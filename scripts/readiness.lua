-- Computes the complete, derived final-jump checklist for one player.

local config = require("scripts.config")
local state = require("scripts.state")
local vessel = require("scripts.vessel")
local cargo = require("scripts.cargo")

local readiness = {}

local function valid(object)
  return object and object.valid ~= false
end

function readiness.personal_inventory_empty(player, inventory_ids)
  local character = player and player.character
  if not valid(character) then return false end
  local ids = inventory_ids or {
    defines.inventory.character_main,
    defines.inventory.character_guns,
    defines.inventory.character_ammo,
    defines.inventory.character_armor,
    defines.inventory.character_trash,
  }
  for _, inventory_id in ipairs(ids) do
    local inventory = character.get_inventory(inventory_id)
    if inventory and not inventory.is_empty() then return false end
  end
  local cursor = player.cursor_stack
  return not (cursor and cursor.valid_for_read)
end

function readiness.at_staging(platform)
  if not valid(platform) then return false end
  local location = platform.space_location
  return location and location.name == config.STAGING_LOCATION
    and platform.space_connection == nil
    and platform.distance == nil
end

function readiness.evaluate(player, deps)
  deps = deps or {}
  local force = player.force
  local force_state = deps.force_state or state.ensure_force(force)
  local entity = deps.vessel or state.resolve_vessel(force_state)
  local platform = valid(entity) and vessel.platform_for_entity(entity) or nil
  local technology = force.technologies and force.technologies[config.NAVIGATION_TECHNOLOGY]
  local inventory = valid(entity) and vessel.inventory(entity) or nil
  local capacity = deps.capacity or cargo.capacity(deps.prototypes)
  local weight = inventory and cargo.weight(inventory) or 0
  local physical_surface = player.physical_surface

  local checks = {
    phase_enabled = force_state.phase == config.PHASE.ENABLED,
    navigation_researched = technology and technology.researched == true or false,
    vessel_present = valid(entity) and entity.force.index == force.index or false,
    vessel_on_platform = valid(platform) or false,
    platform_present = valid(platform) or false,
    at_staging_point = readiness.at_staging(platform),
    engineer_aboard = valid(player.character) and valid(platform)
      and valid(physical_surface) and physical_surface.index == entity.surface.index or false,
    cargo_within_limit = inventory ~= nil and weight <= capacity or false,
    personal_inventory_empty = readiness.personal_inventory_empty(
      player,
      deps.personal_inventory_ids
    ),
    transition_idle = force_state.phase ~= config.PHASE.TRANSITIONING
      and force_state.phase ~= config.PHASE.COMPLETE,
  }

  local ready = true
  for _, passed in pairs(checks) do
    if not passed then ready = false break end
  end

  return {
    ready = ready,
    checks = checks,
    cargo_weight = weight,
    cargo_capacity = capacity,
    platform_name = valid(platform) and platform.name or nil,
    platform_state = valid(platform) and platform.state or nil,
    vessel = entity,
    platform = platform,
    vessel_inventory = inventory,
  }
end

return readiness
