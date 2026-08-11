-- Factorio: The Voyage Home runtime entry point.
-- Domain behavior lives in scripts/**; this file owns lifecycle and event wiring.

local config = require("scripts.config")
local state = require("scripts.state")
local discovery = require("scripts.discovery")
local vessel = require("scripts.vessel")
local readiness = require("scripts.readiness")
local migrations = require("scripts.migrations")
local gui = require("scripts.gui")
local reset = require("scripts.reset")
local command_module = require("scripts.commands")

local function refresh_force(force)
  gui.refresh_force(force)
end

local function vessel_dependencies()
  return {
    script = script,
    refresh_force = refresh_force,
  }
end

local function reset_dependencies()
  return {
    state_for = state.ensure_force,
    readiness = readiness,
    ui = gui,
  }
end

local function apply_staging_lock(force)
  if not prototypes.space_location[config.STAGING_LOCATION] then return end
  local force_state = state.ensure_force(force)
  if force_state.phase == config.PHASE.ENABLED then
    force.unlock_space_location(config.STAGING_LOCATION)
  else
    force.lock_space_location(config.STAGING_LOCATION)
  end
end

local function initialize_runtime(event)
  migrations.run(event, {game = game, script = script, log = log})
  for _, force in pairs(game.forces) do apply_staging_lock(force) end
  for _, player in pairs(game.players) do gui.refresh_player(player) end
end

script.on_init(initialize_runtime)
script.on_configuration_changed(initialize_runtime)

script.on_nth_tick(config.SCAN_INTERVAL_TICKS, function()
  discovery.scan_all(game, {refresh_force = refresh_force})
  for _, player in pairs(game.connected_players) do gui.refresh_player(player) end
end)

script.on_event(defines.events.on_research_finished, function(event)
  if discovery.on_research_finished(event, {refresh_force = refresh_force}) then
    event.research.force.unlock_space_location(config.STAGING_LOCATION)
    event.research.force.print({"tvh-message.navigation-complete"})
  end
end)

local function on_built(event)
  vessel.on_built(event, vessel_dependencies())
end

script.on_event({
  defines.events.on_built_entity,
  defines.events.on_robot_built_entity,
  defines.events.on_space_platform_built_entity,
  defines.events.script_raised_built,
  defines.events.script_raised_revive,
}, on_built)

local function on_removed(event)
  vessel.on_removed(event, vessel_dependencies())
end

script.on_event({
  defines.events.on_player_mined_entity,
  defines.events.on_robot_mined_entity,
  defines.events.on_space_platform_mined_entity,
  defines.events.on_entity_died,
  defines.events.script_raised_destroy,
}, on_removed)

script.on_event(defines.events.on_object_destroyed, function(event)
  vessel.on_object_destroyed(event, vessel_dependencies())
end)

script.on_event(defines.events.on_space_platform_changed_state, function(event)
  if event.platform and event.platform.valid then refresh_force(event.platform.force) end
end)

script.on_event(defines.events.on_gui_opened, gui.on_gui_opened)
script.on_event(defines.events.on_gui_closed, gui.on_gui_closed)
script.on_event(defines.events.on_gui_click, function(event)
  gui.on_gui_click(event, {
    execute = reset.execute,
    reset_dependencies = reset_dependencies(),
  })
end)

local function refresh_player_event(event)
  local player = game.get_player(event.player_index)
  if player and player.valid then gui.refresh_player(player) end
end

script.on_event({
  defines.events.on_player_created,
  defines.events.on_player_joined_game,
  defines.events.on_player_changed_surface,
  defines.events.on_player_controller_changed,
  defines.events.on_player_cursor_stack_changed,
  defines.events.on_gui_inventory_action,
}, refresh_player_event)

command_module.register {
  state_for = state.ensure_force,
  readiness = readiness,
  refresh_force = refresh_force,
  reset_dependencies = reset_dependencies(),
  development_commands = config.development_commands_enabled(),
}
