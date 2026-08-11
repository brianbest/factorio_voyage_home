-- Lightweight pure-module tests. These run in Fengari and deliberately mock
-- only the small Factorio API boundary each module consumes.

package.path = "./?.lua;./?/init.lua;" .. package.path

local passed = 0
local failed = 0

local function test(name, callback)
  local ok, message = pcall(callback)
  if ok then
    passed = passed + 1
    io.write("ok - " .. name .. "\n")
  else
    failed = failed + 1
    io.write("not ok - " .. name .. "\n  " .. tostring(message) .. "\n")
  end
end

local function equal(actual, expected, message)
  if actual ~= expected then
    error((message or "values differ") .. ": expected " .. tostring(expected)
      .. ", got " .. tostring(actual), 2)
  end
end

local function truthy(value, message)
  if not value then error(message or "expected truthy value", 2) end
end

settings = {
  startup = {
    ["tvh-discovery-distance-km"] = {value = 100000},
    ["tvh-cargo-capacity-multiplier"] = {value = 1},
    ["tvh-development-commands"] = {value = false},
  },
}
prototypes = {utility_constants = {default_rocket_lift_weight = 1000000}}
defines = {
  inventory = {
    chest = 1,
    character_main = 2,
    character_guns = 3,
    character_ammo = 4,
    character_armor = 5,
    character_trash = 6,
  },
}
log = function() end
storage = {}

local config = require("scripts.config")
local state = require("scripts.state")
local discovery = require("scripts.discovery")
local cargo = require("scripts.cargo")

test("configuration centralizes the two linked journey distances", function()
  equal(config.discovery_distance_km(), 100000)
  equal(config.cargo_capacity(), 1000000)
end)

test("force state initializes once and normalizes invalid values", function()
  local store = {}
  local first = state.ensure_force(7, store)
  equal(first.phase, config.PHASE.LOCKED)
  first.max_shattered_distance_km = -9
  first.phase = "NOT_A_PHASE"
  local second = state.ensure_force(7, store)
  equal(first, second)
  equal(second.phase, config.PHASE.LOCKED)
  equal(second.max_shattered_distance_km, 0)
end)

local outward_platform = {
  valid = true,
  distance = 0.25,
  last_visited_space_location = {name = "solar-system-edge"},
  space_connection = {
    length = 400000,
    from = {name = "solar-system-edge"},
    to = {name = "shattered-planet"},
  },
}

test("discovery reads normalized outward platform distance", function()
  equal(discovery.outward_distance_km(outward_platform), 100000)
end)

test("discovery rejects travel returning from the Shattered Planet", function()
  local returning = {
    valid = true,
    distance = 0.75,
    last_visited_space_location = {name = "shattered-planet"},
    space_connection = outward_platform.space_connection,
  }
  equal(discovery.outward_distance_km(returning), nil)
end)

test("discovery trigger is force-wide and one-time", function()
  local technology = {researched = false}
  local notifications = 0
  local force = {
    index = 1,
    technologies = {[config.SIGNAL_TECHNOLOGY] = technology},
    platforms = {[3] = outward_platform},
    script_trigger_research = function(name)
      equal(name, config.SIGNAL_TECHNOLOGY)
      technology.researched = true
    end,
  }
  local force_state = {
    phase = config.PHASE.LOCKED,
    max_shattered_distance_km = 0,
  }
  local triggered = discovery.scan_force(force, 600, {
    force_state = force_state,
    notify = function() notifications = notifications + 1 end,
  })
  truthy(triggered)
  equal(force_state.phase, config.PHASE.DISCOVERED)
  equal(force_state.discovery_tick, 600)
  equal(notifications, 1)
  equal(discovery.scan_force(force, 660, {force_state = force_state}), false)
  equal(notifications, 1)
end)

local function inventory(weight, item_count, stack_count)
  local result = {object_name = "LuaInventory", valid = true, weight = weight}
  for index = 1, stack_count do result[index] = {valid_for_read = true} end
  result.get_item_count = function() return item_count end
  result.is_empty = function() return item_count == 0 end
  return result
end

test("cargo fingerprint captures count, occupied slots, and engine weight", function()
  local fingerprint = cargo.fingerprint(inventory(750000, 125, 3))
  equal(fingerprint.weight, 750000)
  equal(fingerprint.items, 125)
  equal(fingerprint.stacks, 3)
end)

test("cargo capacity is inclusive at exactly one rocket lift", function()
  local within, weight, capacity = cargo.is_within_capacity(inventory(1000000, 1, 1))
  truthy(within)
  equal(weight, capacity)
end)

test("readiness is derived from current objects and blocks inventory bypass", function()
  storage = {}
  local empty = inventory(0, 0, 0)
  local vessel_inventory = inventory(500000, 10, 2)
  local platform_surface = {valid = true, index = 44}
  local platform = {
    valid = true,
    index = 12,
    name = "Homeward One",
    space_location = {name = config.STAGING_LOCATION},
    space_connection = nil,
    distance = nil,
  }
  platform_surface.platform = platform
  local force = {
    index = 1,
    technologies = {[config.NAVIGATION_TECHNOLOGY] = {researched = true}},
    platforms = {[12] = platform},
  }
  local entity = {
    valid = true,
    name = config.VESSEL_NAME,
    unit_number = 77,
    force = force,
    surface = platform_surface,
    get_inventory = function() return vessel_inventory end,
  }
  game = {get_entity_by_unit_number = function(number)
    if number == 77 then return entity end
  end}
  local force_state = state.ensure_force(force)
  force_state.phase = config.PHASE.ENABLED
  force_state.vessel_unit_number = 77
  force_state.vessel_platform_index = 12
  local character = {
    valid = true,
    get_inventory = function() return empty end,
  }
  local player = {
    force = force,
    character = character,
    physical_surface = platform_surface,
    cursor_stack = {valid_for_read = false},
  }
  local readiness = require("scripts.readiness")
  truthy(readiness.evaluate(player).ready)
  player.cursor_stack.valid_for_read = true
  local result = readiness.evaluate(player)
  equal(result.ready, false)
  equal(result.checks.personal_inventory_empty, false)
end)

io.write(string.format("\n%d passed, %d failed\n", passed, failed))
if failed > 0 then os.exit(1) end
