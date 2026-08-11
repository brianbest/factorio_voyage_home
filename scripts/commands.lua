-- Administrator and development commands for exercising the MVP loop.

local config = require("scripts.config")
local state = require("scripts.state")
local discovery = require("scripts.discovery")
local readiness = require("scripts.readiness")
local reset = require("scripts.reset")

local command_module = {}
local active_dependencies = {}
local registered = {}

local COMMAND_ORDER = {
  "tvh-status",
  "tvh-set-distance",
  "tvh-trigger-signal",
  "tvh-complete-navigation",
  "tvh-spawn-vessel",
  "tvh-unlock-staging",
  "tvh-reset-mission-state",
  "tvh-dry-run-reset",
}

local HELP = {
  ["tvh-status"] = "Show The Voyage Home mission and readiness state.",
  ["tvh-set-distance"] = "Development: set maximum Shattered Planet distance in kilometres.",
  ["tvh-trigger-signal"] = "Development: trigger the Interstellar Signal milestone.",
  ["tvh-complete-navigation"] = "Development: complete Interstellar Navigation research.",
  ["tvh-spawn-vessel"] = "Development: give the player one Interstellar Vessel.",
  ["tvh-unlock-staging"] = "Development: unlock the Interstellar Staging Point.",
  ["tvh-reset-mission-state"] = "Development: return mission state to LOCKED without resetting the world.",
  ["tvh-dry-run-reset"] = "Run all reset preflight checks and print the destructive plan without changing the world.",
}

local RELEASE_COMMAND = {
  ["tvh-status"] = true,
  ["tvh-dry-run-reset"] = true,
}

local function result(ok, code, lines, extra)
  local value = extra or {}
  value.ok = ok
  value.code = code
  value.lines = lines or {}
  return value
end

local function player_for(command)
  if command.player_index == nil then return nil end
  return game.get_player(command.player_index)
end

local function require_player(command)
  local player = player_for(command)
  if not player or not player.valid then
    return nil, result(false, "player-required", { "This command must be run by a player." })
  end
  return player
end

local function require_admin(command)
  local player, failure = require_player(command)
  if not player then return nil, failure end
  if not player.admin then
    return nil, result(false, "admin-required", { "This command is restricted to administrators." })
  end
  return player
end

local function force_state(force)
  local deps = active_dependencies
  if deps.state_for then return deps.state_for(force) end
  if deps.state and deps.state.ensure_force then return deps.state.ensure_force(force) end
  return state.ensure_force(force)
end

local function reset_dependencies()
  local source = active_dependencies.reset_dependencies or active_dependencies
  local deps = {}
  for key, value in pairs(source) do deps[key] = value end
  deps.state_for = deps.state_for or force_state
  deps.readiness = deps.readiness or readiness
  return deps
end

local function evaluate(player)
  local deps = active_dependencies
  if deps.evaluate_readiness then return deps.evaluate_readiness(player) end
  if deps.readiness and deps.readiness.evaluate then return deps.readiness.evaluate(player) end
  return readiness.evaluate(player)
end

local function yes_no(value)
  return value and "yes" or "no"
end

local function status_handler(command)
  local player, failure = require_admin(command)
  if not player then return failure end
  local mission = force_state(player.force)
  local ready = evaluate(player)
  local lines = {
    "The Voyage Home status",
    "  Phase: " .. tostring(mission.phase),
    "  Maximum Shattered Planet distance: " .. tostring(mission.max_shattered_distance_km or 0) .. " km",
    "  Vessel unit: " .. tostring(mission.vessel_unit_number or "none"),
    "  Platform: " .. tostring(ready.platform_name or mission.vessel_platform_index or "none"),
    "  Cargo: " .. tostring(ready.cargo_weight or 0) .. " / " .. tostring(ready.cargo_capacity or 0),
    "  Final jump ready: " .. yes_no(ready.ready),
    "  Transition nonce: " .. tostring(mission.transition_nonce or "none"),
    "  Transition step: " .. tostring(mission.transition_step or "none"),
  }
  local check_names = {}
  for name in pairs(ready.checks or {}) do check_names[#check_names + 1] = name end
  table.sort(check_names)
  for _, name in ipairs(check_names) do
    lines[#lines + 1] = "    " .. name .. ": " .. yes_no(ready.checks[name])
  end
  return result(true, "status", lines, { mission = mission, readiness = ready })
end

local function set_distance_handler(command)
  local player, failure = require_admin(command)
  if not player then return failure end
  local kilometres = tonumber(command.parameter)
  if not kilometres or kilometres < 0 then
    return result(false, "invalid-distance", { "Usage: /tvh-set-distance <non-negative kilometres>" })
  end
  local mission = force_state(player.force)
  mission.max_shattered_distance_km = kilometres
  return result(true, "distance-set", { "Maximum discovery distance set to " .. kilometres .. " km." }, { distance = kilometres })
end

local function trigger_signal_handler(command)
  local player, failure = require_admin(command)
  if not player then return failure end
  local mission = force_state(player.force)
  local trigger = active_dependencies.trigger_signal or discovery.trigger
  local triggered = trigger(player.force, mission, game.tick, active_dependencies)
  if not triggered then
    return result(false, "signal-not-triggered", { "Interstellar Signal was not triggered; check phase and technology prototype." })
  end
  return result(true, "signal-triggered", { "Interstellar Signal triggered." })
end

local function complete_navigation_handler(command)
  local player, failure = require_admin(command)
  if not player then return failure end
  local technology = player.force.technologies[config.NAVIGATION_TECHNOLOGY]
  if not technology then
    return result(false, "missing-navigation-technology", { "Interstellar Navigation technology is missing." })
  end
  technology.researched = true
  local mission = force_state(player.force)
  if mission.phase ~= config.PHASE.TRANSITIONING and mission.phase ~= config.PHASE.COMPLETE then
    mission.phase = config.PHASE.ENABLED
  end
  if active_dependencies.refresh_force then active_dependencies.refresh_force(player.force) end
  return result(true, "navigation-completed", { "Interstellar Navigation completed." })
end

local function spawn_vessel_handler(command)
  local player, failure = require_admin(command)
  if not player then return failure end
  if not prototypes.item[config.VESSEL_NAME] then
    return result(false, "missing-vessel-item", { "Interstellar Vessel item prototype is missing." })
  end
  local inserted = player.insert { name = config.VESSEL_NAME, count = 1 }
  if inserted ~= 1 then
    return result(false, "inventory-full", { "Player inventory has no room for the Interstellar Vessel." })
  end
  return result(true, "vessel-spawned", { "One Interstellar Vessel added to player inventory." })
end

local function unlock_staging_handler(command)
  local player, failure = require_admin(command)
  if not player then return failure end
  if not prototypes.space_location[config.STAGING_LOCATION] then
    return result(false, "missing-staging-location", { "Interstellar Staging Point prototype is missing." })
  end
  player.force.unlock_space_location(config.STAGING_LOCATION)
  return result(true, "staging-unlocked", { "Interstellar Staging Point unlocked." })
end

local function reset_mission_state_handler(command)
  local player, failure = require_admin(command)
  if not player then return failure end
  local mission = force_state(player.force)
  if mission.phase == config.PHASE.TRANSITIONING then
    return result(false, "transition-in-progress", { "Mission state cannot be reset while a transition is in progress. Recover from the pre-jump autosave." })
  end

  for _, technology_name in ipairs({ config.SIGNAL_TECHNOLOGY, config.NAVIGATION_TECHNOLOGY }) do
    local technology = player.force.technologies[technology_name]
    if technology then technology.researched = false end
  end
  player.force.lock_space_location(config.STAGING_LOCATION)

  mission.phase = config.PHASE.LOCKED
  mission.max_shattered_distance_km = 0
  mission.discovery_tick = nil
  mission.vessel_unit_number = nil
  mission.vessel_platform_index = nil
  mission.vessel_destroy_registration = nil
  mission.transition_nonce = nil
  mission.transition_seed = nil
  mission.transition_step = nil
  mission.transition_step_tick = nil
  mission.transition_started_tick = nil
  mission.transition_transit_surface_index = nil
  mission.completed_tick = nil
  if active_dependencies.refresh_force then active_dependencies.refresh_force(player.force) end
  return result(true, "mission-state-reset", { "Mission state returned to LOCKED. The world was not reset." })
end

local function dry_run_handler(command)
  local player, failure = require_admin(command)
  if not player then return failure end
  local report = reset.dry_run(player, reset_dependencies())
  local lines = {
    "Interstellar reset dry run: " .. (report.ok and "PASS" or "BLOCKED"),
    "  Autosave: " .. report.plan.autosave_name,
    "  Platforms to delete: " .. #report.plan.platforms,
    "  Vanilla planet surfaces to regenerate: " .. #report.plan.planet_surfaces,
    "  Planned seed: " .. tostring(report.planned_transition_seed),
  }
  for _, platform in ipairs(report.plan.platforms) do
    lines[#lines + 1] = "    platform " .. platform.index .. ": " .. platform.name
  end
  for _, planet in ipairs(report.plan.planet_surfaces) do
    lines[#lines + 1] = "    " .. planet.name .. ": seed " .. tostring(planet.old_seed) .. " -> " .. tostring(planet.new_seed)
  end
  for _, warning in ipairs(report.warnings) do
    lines[#lines + 1] = "  WARNING [" .. warning.code .. "]: " .. warning.message
  end
  for _, issue in ipairs(report.errors) do
    lines[#lines + 1] = "  BLOCKER [" .. issue.code .. "]: " .. issue.message
  end
  lines[#lines + 1] = "No game state was changed."
  return result(report.ok, report.ok and "dry-run-passed" or "dry-run-blocked", lines, { report = report })
end

local HANDLER = {
  ["tvh-status"] = status_handler,
  ["tvh-set-distance"] = set_distance_handler,
  ["tvh-trigger-signal"] = trigger_signal_handler,
  ["tvh-complete-navigation"] = complete_navigation_handler,
  ["tvh-spawn-vessel"] = spawn_vessel_handler,
  ["tvh-unlock-staging"] = unlock_staging_handler,
  ["tvh-reset-mission-state"] = reset_mission_state_handler,
  ["tvh-dry-run-reset"] = dry_run_handler,
}

local function emit(command, command_result)
  local player = player_for(command)
  local printer = player and function(line) player.print(line) end
    or function(line) game.print(line) end
  for _, line in ipairs(command_result.lines or {}) do printer(line) end
end

---Execute a handler directly. Exported to make command behavior unit-testable.
function command_module.execute(name, command, deps)
  if deps then active_dependencies = deps end
  local handler = HANDLER[name]
  if not handler then return result(false, "unknown-command", { "Unknown command: " .. tostring(name) }) end
  local command_result = handler(command)
  emit(command, command_result)
  return command_result
end

---Register all enabled commands. Repeated calls update dependencies and do not
---replace commands registered by another mod.
function command_module.register(deps)
  active_dependencies = deps or active_dependencies or {}
  -- Cheats fail closed in release saves. Tests/control.lua may still inject an
  -- explicit boolean, but a missing startup setting never enables them.
  local development_enabled = active_dependencies.development_commands
  if development_enabled == nil then
    development_enabled = config.development_commands_enabled()
  end
  local registration = { added = {}, existing = {}, disabled = {} }

  for _, name in ipairs(COMMAND_ORDER) do
    if development_enabled or RELEASE_COMMAND[name] then
      if registered[name] or commands.commands[name] then
        registration.existing[#registration.existing + 1] = name
      else
        local command_name = name
        commands.add_command(command_name, HELP[command_name], function(command)
          command_module.execute(command_name, command)
        end)
        registered[command_name] = true
        registration.added[#registration.added + 1] = command_name
      end
    else
      registration.disabled[#registration.disabled + 1] = name
    end
  end
  return registration
end

command_module.handlers = HANDLER

return command_module
