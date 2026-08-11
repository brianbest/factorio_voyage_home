-- Tracks outward progress from the Solar System Edge to the Shattered Planet.

local config = require("scripts.config")
local state = require("scripts.state")

local discovery = {}

local function endpoint_name(endpoint)
  return endpoint and endpoint.name
end

-- Pure helper. Returns kilometres travelled outward, or nil when the platform
-- is not currently proving an outward journey on the required connection.
function discovery.outward_distance_km(platform)
  if not (platform and platform.valid ~= false) then return nil end
  local connection = platform.space_connection
  local normalised = tonumber(platform.distance)
  if not connection or normalised == nil then return nil end

  local from_name = endpoint_name(connection.from)
  local to_name = endpoint_name(connection.to)
  local edge = config.SOLAR_SYSTEM_EDGE
  local shattered = config.SHATTERED_PLANET
  if not ((from_name == edge and to_name == shattered)
    or (from_name == shattered and to_name == edge))
  then
    return nil
  end

  local last = platform.last_visited_space_location
  if endpoint_name(last) ~= edge then return nil end

  local progress = from_name == edge and normalised or (1 - normalised)
  if progress < 0 or progress > 1 then return nil end
  return (tonumber(connection.length) or 0) * progress
end

local function default_notify(force)
  for _, player in pairs(force.connected_players or {}) do
    player.print({"tvh-message.signal-discovered"})
  end
end

function discovery.trigger(force, force_state, tick, deps)
  deps = deps or {}
  if force_state.phase ~= config.PHASE.LOCKED then return false end
  local technology = force.technologies and force.technologies[config.SIGNAL_TECHNOLOGY]
  if not technology then
    local logger = deps.log or log
    logger("[TVH] Cannot trigger discovery: technology prototype is missing")
    return false
  end

  force.script_trigger_research(config.SIGNAL_TECHNOLOGY)
  -- A scripted trigger may be rejected if another mod changed the technology.
  if not technology.researched then
    local logger = deps.log or log
    logger("[TVH] Scripted discovery trigger did not research the technology")
    return false
  end

  force_state.phase = config.PHASE.DISCOVERED
  force_state.discovery_tick = tick
  local notify = deps.notify or default_notify
  notify(force)
  if deps.refresh_force then deps.refresh_force(force) end
  return true
end

function discovery.scan_force(force, tick, deps)
  deps = deps or {}
  local force_state = deps.force_state or state.ensure_force(force)
  if force_state.phase ~= config.PHASE.LOCKED then return false, force_state end

  for _, platform in pairs(force.platforms or {}) do
    local kilometres = discovery.outward_distance_km(platform)
    if kilometres then
      force_state.max_shattered_distance_km = math.max(
        force_state.max_shattered_distance_km,
        kilometres
      )
    end
  end

  local threshold = deps.threshold_km or config.discovery_distance_km()
  if force_state.max_shattered_distance_km >= threshold then
    return discovery.trigger(force, force_state, tick, deps), force_state
  end
  return false, force_state
end

function discovery.scan_all(runtime_game, deps)
  local active_game = runtime_game or game
  local changed = false
  for _, force in pairs(active_game.forces) do
    if discovery.scan_force(force, active_game.tick, deps) then changed = true end
  end
  return changed
end

function discovery.on_research_finished(event, deps)
  local research = event and event.research
  if not (research and research.valid ~= false
    and research.name == config.NAVIGATION_TECHNOLOGY)
  then
    return false
  end
  local force_state = state.ensure_force(research.force)
  if force_state.phase == config.PHASE.COMPLETE
    or force_state.phase == config.PHASE.TRANSITIONING
  then
    return false
  end
  force_state.phase = config.PHASE.ENABLED
  if deps and deps.notify_navigation then
    deps.notify_navigation(research.force)
  else
    for _, player in pairs(research.force.connected_players or {}) do
      player.print({"tvh-message.navigation-complete"})
    end
  end
  if deps and deps.refresh_force then deps.refresh_force(research.force) end
  return true
end

return discovery
