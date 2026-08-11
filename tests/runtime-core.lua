package.path = "./?.lua;./?/init.lua;" .. package.path

defines = {
  inventory = {
    chest = 1,
    robot_cargo = 2,
    character_main = 3,
    character_guns = 4,
    character_ammo = 5,
    character_armor = 6,
    character_trash = 7,
  },
}

local passed = 0
local function test(name, run)
  local ok, failure = pcall(run)
  if not ok then error(name .. ": " .. tostring(failure), 0) end
  passed = passed + 1
end

local function equal(actual, expected)
  assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local config = require("scripts.config")
local state = require("scripts.state")
local discovery = require("scripts.discovery")
local vessel = require("scripts.vessel")
local cargo = require("scripts.cargo")
local readiness = require("scripts.readiness")

test("config reads startup values and fails development commands closed", function()
  settings = nil
  equal(config.discovery_distance_km(), 100000)
  equal(config.cargo_capacity(), 1000000)
  equal(config.development_commands_enabled(), false)
  settings = {startup = {
    [config.SETTING_DISCOVERY_DISTANCE] = {value = 25000},
    [config.SETTING_CARGO_CAPACITY_MULTIPLIER] = {value = 2},
    [config.SETTING_DEVELOPMENT_COMMANDS] = {value = true},
  }}
  equal(config.discovery_distance_km(), 25000)
  equal(config.cargo_capacity(), 2000000)
  equal(config.development_commands_enabled(), true)
  settings = nil
end)

test("state schema is serialisable and progression reconciliation is monotonic", function()
  local store = {}
  local mission = state.ensure_force(1, store)
  equal(store.tvh.schema_version, 1)
  equal(mission.phase, config.PHASE.LOCKED)
  mission.max_shattered_distance_km = -10
  state.normalise_force(mission)
  equal(mission.max_shattered_distance_km, 0)

  local force = {index = 1, technologies = {
    [config.SIGNAL_TECHNOLOGY] = {researched = true},
    [config.NAVIGATION_TECHNOLOGY] = {researched = false},
  }}
  state.reconcile_force(force, mission)
  equal(mission.phase, config.PHASE.DISCOVERED)
  force.technologies[config.NAVIGATION_TECHNOLOGY].researched = true
  state.reconcile_force(force, mission)
  equal(mission.phase, config.PHASE.ENABLED)
  mission.phase = config.PHASE.COMPLETE
  force.technologies[config.NAVIGATION_TECHNOLOGY].researched = false
  state.reconcile_force(force, mission)
  equal(mission.phase, config.PHASE.COMPLETE)
end)

test("discovery measures only outward travel and triggers exactly once", function()
  local connection = {
    from = {name = config.SOLAR_SYSTEM_EDGE},
    to = {name = config.SHATTERED_PLANET},
    length = 4000000,
  }
  local platform = {
    valid = true,
    space_connection = connection,
    distance = 0.025,
    last_visited_space_location = {name = config.SOLAR_SYSTEM_EDGE},
  }
  equal(discovery.outward_distance_km(platform), 100000)
  platform.last_visited_space_location = {name = config.SHATTERED_PLANET}
  equal(discovery.outward_distance_km(platform), nil)
  platform.last_visited_space_location = {name = config.SOLAR_SYSTEM_EDGE}

  storage = {}
  local technology = {researched = false}
  local force = {
    index = 1,
    platforms = {[1] = platform},
    technologies = {[config.SIGNAL_TECHNOLOGY] = technology},
    connected_players = {},
  }
  force.script_trigger_research = function(name)
    assert(name == config.SIGNAL_TECHNOLOGY)
    technology.researched = true
  end
  local changed, mission = discovery.scan_force(force, 120, {threshold_km = 100000})
  equal(changed, true)
  equal(mission.phase, config.PHASE.DISCOVERED)
  equal(mission.discovery_tick, 120)
  equal(discovery.scan_force(force, 180, {threshold_km = 100000}), false)
end)

local function make_inventory(size, stack_count, weight)
  local inventory = {valid = true, object_name = "LuaInventory", weight = weight or 0}
  for index = 1, stack_count or 0 do
    inventory[index] = {valid_for_read = true, count = 1}
  end
  setmetatable(inventory, {__len = function() return size end})
  inventory.get_item_count = function()
    local count = 0
    for index = 1, size do
      local stack = inventory[index]
      if stack and stack.valid_for_read then count = count + stack.count end
    end
    return count
  end
  inventory.is_empty = function() return inventory.get_item_count() == 0 end
  inventory.transfer_from_inventory = function(source)
    local target_index = 1
    for source_index = 1, #source do
      local stack = source[source_index]
      if stack and stack.valid_for_read then
        while inventory[target_index] do target_index = target_index + 1 end
        if target_index <= size then
          inventory[target_index] = stack
          source[source_index] = nil
        end
      end
    end
    inventory.weight = inventory.weight + source.weight
    source.weight = 0
    return inventory.get_item_count()
  end
  inventory.destroy = function() inventory.valid = false end
  return inventory
end

test("cargo snapshots transfer directly, verify, restore, and destroy", function()
  local source = make_inventory(48, 3, 750000)
  local runtime_game = {
    create_inventory = function(size) return make_inventory(size, 0, 0) end,
  }
  local snapshot, failure = cargo.create_snapshot(source, runtime_game)
  assert(snapshot, failure)
  equal(source.is_empty(), true)
  equal(snapshot.fingerprint.items, 3)
  equal(snapshot.fingerprint.weight, 750000)

  local destination = make_inventory(48, 0, 0)
  local restored, restore_failure = cargo.restore(snapshot, destination)
  assert(restored, restore_failure)
  equal(destination.get_item_count(), 3)
  equal(destination.weight, 750000)
  assert(cargo.destroy_snapshot(snapshot))
  equal(snapshot.inventory.valid, false)
end)

test("vessel placement enforces platform, phase, and singleton ownership", function()
  storage = {}
  local entities = {}
  local force = {index = 1, platforms = {}}
  local platform = {valid = true, index = 10, name = "Homeward One"}
  local surface = {valid = true, platform = platform}
  platform.surface = surface
  force.platforms[platform.index] = platform
  local player = {valid = true, insert = function() return 1 end, print = function() end}
  game = {
    get_entity_by_unit_number = function(unit) return entities[unit] end,
    get_player = function() return player end,
  }
  script = {register_on_object_destroyed = function(entity) return 1000 + entity.unit_number end}
  state.ensure_force(force).phase = config.PHASE.ENABLED

  local first = {
    valid = true, name = config.VESSEL_NAME, unit_number = 1,
    force = force, surface = surface, position = {x = 0, y = 0},
    destroy = function() end,
  }
  entities[1] = first
  local result = vessel.on_built({entity = first, player_index = 1})
  equal(result.accepted, true)
  equal(state.ensure_force(force).vessel_platform_index, 10)

  local second = {
    valid = true, name = config.VESSEL_NAME, unit_number = 2,
    force = force, surface = surface, position = {x = 1, y = 1},
  }
  second.destroy = function() second.valid = false end
  entities[2] = second
  result = vessel.on_built({entity = second, player_index = 1})
  equal(result.accepted, false)
  equal(result.reason, "already-exists")
  equal(second.valid, false)
end)

test("readiness derives every guard and reacts to cargo and cursor changes", function()
  storage = {}
  local inventory = make_inventory(48, 0, 0)
  local platform = {
    valid = true,
    index = 20,
    name = "Homeward One",
    space_location = {name = config.STAGING_LOCATION},
    space_connection = nil,
    distance = nil,
    state = 7,
  }
  local surface = {valid = true, index = 30, platform = platform}
  platform.surface = surface
  local force = {
    index = 1,
    platforms = {[20] = platform},
    technologies = {[config.NAVIGATION_TECHNOLOGY] = {researched = true}},
  }
  local entity = {
    valid = true,
    name = config.VESSEL_NAME,
    unit_number = 5,
    force = force,
    surface = surface,
    get_inventory = function() return inventory end,
  }
  local empty_inventory = make_inventory(1, 0, 0)
  local character = {valid = true, get_inventory = function() return empty_inventory end}
  local player = {
    force = force,
    character = character,
    physical_surface = surface,
    cursor_stack = {valid_for_read = false},
  }
  local mission = state.ensure_force(force)
  mission.phase = config.PHASE.ENABLED
  mission.vessel_unit_number = 5
  mission.vessel_platform_index = 20
  game = {get_entity_by_unit_number = function() return entity end}

  local result = readiness.evaluate(player, {force_state = mission, vessel = entity, capacity = 100})
  equal(result.ready, true)
  inventory.weight = 101
  equal(readiness.evaluate(player, {force_state = mission, vessel = entity, capacity = 100}).ready, false)
  inventory.weight = 0
  player.cursor_stack.valid_for_read = true
  local cursor_result = readiness.evaluate(player, {force_state = mission, vessel = entity, capacity = 100})
  equal(cursor_result.checks.personal_inventory_empty, false)
  equal(cursor_result.ready, false)
end)

io.write("runtime core tests passed (" .. passed .. ")\n")
