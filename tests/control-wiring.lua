package.path = "./?.lua;./?/init.lua;" .. package.path

local next_event = 1
local event_names = {
  "on_research_finished",
  "on_built_entity",
  "on_robot_built_entity",
  "on_space_platform_built_entity",
  "script_raised_built",
  "script_raised_revive",
  "on_player_mined_entity",
  "on_robot_mined_entity",
  "on_space_platform_mined_entity",
  "on_entity_died",
  "script_raised_destroy",
  "on_object_destroyed",
  "on_space_platform_changed_state",
  "on_gui_opened",
  "on_gui_closed",
  "on_gui_click",
  "on_player_created",
  "on_player_joined_game",
  "on_player_changed_surface",
  "on_player_controller_changed",
  "on_player_cursor_stack_changed",
  "on_gui_inventory_action",
}

defines = {
  events = {},
  inventory = {chest = 1},
  controllers = {remote = 1},
  render_mode = {game = 1, chart = 2, chart_zoomed_in = 3},
  relative_gui_type = {container_gui = 1},
  relative_gui_position = {right = 1},
}
for _, name in ipairs(event_names) do
  defines.events[name] = next_event
  next_event = next_event + 1
end

settings = {
  startup = {
    ["tvh-development-commands"] = {value = false},
  },
}
storage = {}
prototypes = {space_location = {}}
log = function() end

local registrations = {events = {}}
script = {}
function script.on_init(handler) registrations.on_init = handler end
function script.on_configuration_changed(handler) registrations.on_configuration_changed = handler end
function script.on_nth_tick(interval, handler)
  registrations.nth_tick = {interval = interval, handler = handler}
end
function script.on_event(events, handler)
  if type(events) ~= "table" then events = {events} end
  for _, event in ipairs(events) do
    assert(type(event) == "number", "control registered an undefined event")
    registrations.events[event] = handler
  end
end

commands = {commands = {}}
function commands.add_command(name, _help, handler)
  assert(not commands.commands[name], "duplicate command registration: " .. name)
  commands.commands[name] = handler
end

dofile("control.lua")

assert(type(registrations.on_init) == "function", "on_init was not registered")
assert(type(registrations.on_configuration_changed) == "function",
  "on_configuration_changed was not registered")
assert(registrations.nth_tick.interval == 60, "platform scan must remain bounded to every 60 ticks")
for _, name in ipairs(event_names) do
  assert(type(registrations.events[defines.events[name]]) == "function",
    "missing event registration: " .. name)
end
assert(commands.commands["tvh-status"], "release status command missing")
assert(commands.commands["tvh-dry-run-reset"], "release dry-run command missing")
assert(not commands.commands["tvh-spawn-vessel"], "development command escaped fail-closed gate")

io.write("control wiring test passed (22 events, 2 release commands)\n")
