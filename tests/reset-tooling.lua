package.path = "./?.lua;./?/init.lua;" .. package.path

defines = {inventory = {chest = 1}}
settings = {startup = { ["tvh-development-commands"] = {value = false} }}

local passed = 0
local function test(name, run)
  local ok, failure = pcall(run)
  if not ok then error(name .. ": " .. tostring(failure), 0) end
  passed = passed + 1
end

local function equal(actual, expected)
  assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function make_inventory(size)
  local inventory = {valid = true}
  local function make_slot()
    local slot = {valid_for_read = false, count = 0}
    function slot.transfer_stack(source)
      if not source.valid_for_read then return true end
      if slot.valid_for_read and slot.name ~= source.name then return false end
      slot.valid_for_read = true
      slot.name = source.name
      slot.count = (slot.count or 0) + source.count
      slot.item_weight = source.item_weight
      source.valid_for_read = false
      source.name = nil
      source.count = 0
      return true
    end
    return slot
  end
  for index = 1, size do inventory[index] = make_slot() end
  function inventory.is_empty()
    for index = 1, size do
      if inventory[index].valid_for_read then return false end
    end
    return true
  end
  function inventory.destroy() inventory.valid = false end
  return setmetatable(inventory, {
    __len = function() return size end,
    __index = function(_, key)
      if key ~= "weight" then return nil end
      local weight = 0
      for index = 1, size do
        local item = inventory[index]
        if item.valid_for_read then
          weight = weight + item.count * item.item_weight
        end
      end
      return weight
    end,
  })
end

local vessel_inventory = make_inventory(48)
vessel_inventory[1].valid_for_read = true
vessel_inventory[1].name = "quality-item"
vessel_inventory[1].count = 7
vessel_inventory[1].item_weight = 100
local cache_inventory = make_inventory(48)

local cache
local nauvis = {
  valid = true,
  index = 1,
  name = "nauvis",
  planet = {name = "nauvis"},
  map_gen_settings = {seed = 123, width = 0, height = 0},
  clear_count = 0,
}
function nauvis.clear() nauvis.clear_count = nauvis.clear_count + 1 end
function nauvis.clear_pollution() nauvis.pollution_cleared = true end
function nauvis.request_to_generate_chunks() nauvis.requested = true end
function nauvis.force_generate_chunk_requests() nauvis.generated = true end
function nauvis.find_non_colliding_position(name)
  return name == "character" and {x = 1, y = 2} or {x = 5, y = 2}
end
function nauvis.create_entity()
  cache = {valid = true, unit_number = 500, destructible = true, minable_flag = true}
  function cache.get_inventory() return cache_inventory end
  return cache
end

local platform = {valid = true, index = 4, name = "Ark"}
function platform.destroy(ticks) platform.destroy_ticks = ticks end

local force = {
  valid = true,
  index = 1,
  name = "player",
  platforms = {[4] = platform},
  recipes = {steel = {productivity_bonus = 0.25}},
  worker_robots_speed_modifier = 1.5,
  worker_robots_storage_bonus = 3,
  mining_drill_productivity_bonus = 0.4,
  laboratory_speed_modifier = 0.7,
  laboratory_productivity_bonus = 0.2,
}
function force.clear_chart() force.chart_cleared = true end
function force.reset()
  force.worker_robots_speed_modifier = 0
  force.worker_robots_storage_bonus = 0
  force.mining_drill_productivity_bonus = 0
  force.laboratory_speed_modifier = 0
  force.laboratory_productivity_bonus = 0
  force.recipes.steel.productivity_bonus = 0
end
function force.unlock_space_location() end
function force.lock_space_location() end
function force.lock_space_platforms() force.platforms_locked = true end
function force.set_spawn_position(position) force.spawn = position end

local enemy = {valid = true}
function enemy.set_evolution_factor() end
function enemy.set_evolution_factor_by_pollution() end
function enemy.set_evolution_factor_by_time() end
function enemy.set_evolution_factor_by_killing_spawners() end

local vessel = {valid = true, unit_number = 99}
function vessel.get_inventory() return vessel_inventory end

local player = {
  valid = true,
  admin = true,
  index = 1,
  force = force,
  character = {valid = true, health = 10, max_health = 250},
  printed = {},
}
function player.teleport(position, surface)
  player.surface = surface
  player.position = position
  return true
end
function player.print(message) player.printed[#player.printed + 1] = message end

storage = {tvh = {forces = {[1] = {
  phase = "ENABLED",
  transition_nonce = nil,
  vessel_unit_number = 99,
  vessel_platform_index = 4,
}}}}

local transit
game = {
  tick = 1000,
  planets = {nauvis = {surface = nauvis}},
  forces = {enemy = enemy},
}
function game.is_multiplayer() return false end
function game.get_surface(name)
  if name == "nauvis" then return nauvis end
  if name == "tvh-transit" then return transit end
end
function game.get_entity_by_unit_number() return vessel end
function game.get_player() return player end
function game.auto_save(name) game.autosave = name end
function game.create_inventory(size) return make_inventory(size) end
function game.create_surface(name, map_gen_settings)
  transit = {valid = true, index = 20, name = name, map_gen_settings = map_gen_settings}
  function transit.request_to_generate_chunks() end
  function transit.force_generate_chunk_requests() transit.generated = true end
  return transit
end
function game.delete_surface(surface)
  if surface ~= transit then return false end
  transit = nil
  return true
end
function game.print() end

prototypes = {
  utility_constants = {default_rocket_lift_weight = 1000000},
  entity = { ["tvh-arrival-cache"] = {get_inventory_size = function() return 48 end} },
  item = {},
  space_location = {
    nauvis = {}, vulcanus = {}, fulgora = {}, gleba = {}, aquilo = {},
    ["solar-system-edge"] = {}, ["shattered-planet"] = {},
    ["tvh-interstellar-staging"] = {},
  },
}

local modifiers = require("scripts.modifiers")
local reset = require("scripts.reset")

test("modifier snapshots preserve only positive recipe productivity", function()
  force.recipes.copper = {productivity_bonus = 0}
  local snapshot = modifiers.snapshot(force)
  equal(snapshot.recipe_productivity.steel, 0.25)
  equal(snapshot.recipe_productivity.copper, nil)
  force.recipes.copper = nil
end)

local dependencies = {
  state_for = function() return storage.tvh.forces[1] end,
  evaluate_readiness = function() return {ready = true, vessel = vessel} end,
  log = function() end,
}

test("dry run reports the exact plan without mutating state or cargo", function()
  local report = reset.dry_run(player, dependencies)
  assert(report.ok, report.errors[1] and report.errors[1].message)
  equal(#report.plan.platforms, 1)
  equal(#report.plan.planet_surfaces, 1)
  assert(report.plan.planet_surfaces[1].new_seed ~= 123)
  equal(storage.tvh.forces[1].phase, "ENABLED")
  equal(vessel_inventory[1].valid_for_read, true)
end)

test("reset performs one guarded, cargo-faithful transition", function()
  local outcome = reset.execute(player, dependencies)
  assert(outcome.ok, outcome.error or outcome.code)
  equal(game.autosave, "tvh-pre-interstellar-jump")
  equal(platform.destroy_ticks, 0)
  equal(nauvis.clear_count, 1)
  assert(nauvis.pollution_cleared)
  assert(nauvis.map_gen_settings.seed ~= 123)
  equal(force.worker_robots_speed_modifier, 1.5)
  equal(force.worker_robots_storage_bonus, 3)
  equal(force.recipes.steel.productivity_bonus, 0.25)
  equal(storage.tvh.forces[1].phase, "COMPLETE")
  equal(storage.tvh.forces[1].transition_step, "complete")
  assert(storage.tvh.forces[1].transition_nonce)
  assert(vessel_inventory.is_empty())
  equal(cache_inventory[1].count, 7)
  assert(cache.destructible and cache.minable_flag)
  equal(player.surface, nauvis)
  equal(player.character.health, 250)
  equal(transit, nil)
end)

test("a committed nonce prevents a second transition", function()
  storage.tvh.forces[1].phase = "ENABLED"
  local report = reset.preflight(player, dependencies)
  equal(report.ok, false)
  equal(report.errors[1].code, "nonce-already-committed")
end)

test("command registration fails cheats closed and is idempotent", function()
  local registered_commands = {}
  commands = {commands = {}}
  function commands.add_command(name, help, callback)
    commands.commands[name] = help
    registered_commands[name] = callback
  end
  local command_module = require("scripts.commands")
  local release = command_module.register()
  equal(#release.added, 2)
  assert(commands.commands["tvh-status"] and commands.commands["tvh-dry-run-reset"])
  equal(commands.commands["tvh-spawn-vessel"], nil)
  local development = command_module.register({development_commands = true})
  equal(#development.added, 6)
  local repeated = command_module.register({development_commands = true})
  equal(#repeated.added, 0)
  equal(#repeated.existing, 8)
end)

io.write("reset tooling tests passed (" .. passed .. ")\n")
