-- Executes the real settings, data, and data-updates stages against a focused
-- mock of the Space Age prototypes that The Voyage Home extends.

package.path = "./?.lua;./?/init.lua;" .. package.path

local passed = 0

local function test(name, callback)
  local ok, failure = pcall(callback)
  if not ok then error(name .. ": " .. tostring(failure), 0) end
  passed = passed + 1
  io.write("ok - " .. name .. "\n")
end

local function equal(actual, expected, message)
  if actual ~= expected then
    error((message or "values differ") .. ": expected " .. tostring(expected)
      .. ", got " .. tostring(actual), 2)
  end
end

local function close(actual, expected, epsilon, message)
  if math.abs(actual - expected) > epsilon then
    error((message or "values differ") .. ": expected approximately "
      .. tostring(expected) .. ", got " .. tostring(actual), 2)
  end
end

local function contains(values, expected)
  for _, value in ipairs(values) do
    if value == expected then return true end
  end
  return false
end

local function deepcopy(value, seen)
  if type(value) ~= "table" then return value end
  seen = seen or {}
  if seen[value] then return seen[value] end
  local result = {}
  seen[value] = result
  for key, child in pairs(value) do
    result[deepcopy(key, seen)] = deepcopy(child, seen)
  end
  return setmetatable(result, getmetatable(value))
end

table.deepcopy = deepcopy
tons = 1000000

data = {
  raw = {
    container = {
      ["steel-chest"] = {
        type = "container",
        name = "steel-chest",
        icon = "__base__/graphics/icons/steel-chest.png",
        inventory_size = 48,
        flags = {},
        picture = {
          layers = {
            {scale = 0.5},
            {scale = 0.5, draw_as_shadow = true},
          },
        },
      },
    },
    item = {
      ["steel-chest"] = {
        type = "item",
        name = "steel-chest",
        inventory_move_sound = {},
        pick_sound = {},
        drop_sound = {},
      },
    },
    ["space-connection"] = {
      ["solar-system-edge-shattered-planet"] = {
        type = "space-connection",
        name = "solar-system-edge-shattered-planet",
        from = "solar-system-edge",
        to = "shattered-planet",
        length = 4000000,
        asteroid_spawn_definitions = {
          {
            asteroid = "huge-metallic-asteroid",
            spawn_points = {
              {distance = 0.001, probability = 0.10, speed = 0.01, angle_when_stopped = 1},
              {distance = 0.002, probability = 0.12, speed = 0.01, angle_when_stopped = 1},
              {distance = 0.2, probability = 0.90, speed = 0.01, angle_when_stopped = 1},
            },
          },
          {
            type = "asteroid-chunk",
            asteroid = "metallic-asteroid-chunk",
            spawn_points = {
              {distance = 0.001, probability = 0.30, speed = 0.01, angle_when_stopped = 1},
              {distance = 0.2, probability = 0.05, speed = 0.01, angle_when_stopped = 1},
            },
          },
        },
      },
    },
    ["assembling-machine"] = {
      ["electromagnetic-plant"] = {
        type = "assembling-machine",
        name = "electromagnetic-plant",
        crafting_categories = {"electromagnetics"},
      },
    },
  },
}

function data:extend(prototypes_to_add)
  for _, prototype in ipairs(prototypes_to_add) do
    self.raw[prototype.type] = self.raw[prototype.type] or {}
    assert(not self.raw[prototype.type][prototype.name],
      "duplicate prototype " .. prototype.type .. "/" .. prototype.name)
    self.raw[prototype.type][prototype.name] = prototype
  end
end

-- Settings stage registers setting prototypes. Factorio then exposes their
-- selected values through settings.startup during the data stage.
dofile("settings.lua")

settings = {
  startup = {
    ["tvh-discovery-distance-km"] = {value = 100000},
    ["tvh-cargo-capacity-multiplier"] = {value = 1},
    ["tvh-development-commands"] = {value = false},
  },
}

dofile("data.lua")
dofile("data-updates.lua")

test("all custom prototype names are registered", function()
  local expected = {
    {"int-setting", "tvh-discovery-distance-km"},
    {"double-setting", "tvh-cargo-capacity-multiplier"},
    {"bool-setting", "tvh-development-commands"},
    {"recipe-category", "tvh-interstellar-vessel-crafting"},
    {"item", "tvh-interstellar-vessel"},
    {"recipe", "tvh-interstellar-vessel"},
    {"container", "tvh-interstellar-vessel"},
    {"container", "tvh-arrival-cache"},
    {"technology", "tvh-interstellar-signal"},
    {"technology", "tvh-interstellar-navigation"},
    {"space-location", "tvh-interstellar-staging"},
    {"space-connection", "tvh-interstellar-corridor"},
  }

  for _, identity in ipairs(expected) do
    assert(data.raw[identity[1]] and data.raw[identity[1]][identity[2]],
      "missing " .. identity[1] .. "/" .. identity[2])
  end
end)

test("signal trigger description parameters are property-tree-safe strings", function()
  local signal = data.raw.technology["tvh-interstellar-signal"]
  local description = signal.research_trigger.trigger_description
  equal(type(description), "table", "trigger_description")
  for index, element in ipairs(description) do
    equal(type(element), "string", "trigger_description element " .. index)
  end
end)

test("vessel and arrival cache remain fixed 48-slot containers", function()
  local vessel = data.raw.container["tvh-interstellar-vessel"]
  local cache = data.raw.container["tvh-arrival-cache"]
  equal(vessel.inventory_size, 48)
  equal(cache.inventory_size, 48)
  equal(vessel.inventory_type, "normal")
  equal(cache.inventory_type, "normal")
  equal(vessel.quality_affects_inventory_size, false)
  equal(cache.quality_affects_inventory_size, false)
  equal(data.raw.item["tvh-interstellar-vessel"].weight, 1000000)
end)

test("vessel recipe is wired only to the electromagnetic plant category", function()
  local category = "tvh-interstellar-vessel-crafting"
  local recipe = data.raw.recipe["tvh-interstellar-vessel"]
  local plant = data.raw["assembling-machine"]["electromagnetic-plant"]

  equal(#recipe.categories, 1)
  equal(recipe.categories[1], category)
  equal(recipe.energy_required, 600)
  equal(#recipe.ingredients, 6)
  assert(contains(plant.crafting_categories, category),
    "electromagnetic plant is missing vessel category")
end)

test("navigation research uses all eleven specified science packs", function()
  local navigation = data.raw.technology["tvh-interstellar-navigation"]
  local expected = {
    "automation-science-pack",
    "logistic-science-pack",
    "chemical-science-pack",
    "production-science-pack",
    "utility-science-pack",
    "space-science-pack",
    "metallurgic-science-pack",
    "agricultural-science-pack",
    "electromagnetic-science-pack",
    "cryogenic-science-pack",
    "promethium-science-pack",
  }
  local actual = {}
  for _, ingredient in ipairs(navigation.unit.ingredients) do
    actual[#actual + 1] = ingredient[1]
    equal(ingredient[2], 1, ingredient[1] .. " amount")
  end

  equal(navigation.unit.count, 5000)
  equal(navigation.unit.time, 60)
  equal(#actual, #expected)
  for index, name in ipairs(expected) do equal(actual[index], name) end
end)

test("corridor uses configured length and remaps early asteroid endpoints", function()
  local corridor = data.raw["space-connection"]["tvh-interstellar-corridor"]
  equal(corridor.from, "solar-system-edge")
  equal(corridor.to, "tvh-interstellar-staging")
  equal(corridor.length, 100000)
  equal(#corridor.asteroid_spawn_definitions, 2)

  for _, definition in ipairs(corridor.asteroid_spawn_definitions) do
    local points = definition.spawn_points
    equal(points[1].distance, 0.001)
    close(points[#points].distance, 0.999, 0.0000001)
    for index = 2, #points do
      assert(points[index].distance > points[index - 1].distance,
        "remapped asteroid points are not strictly increasing")
    end
  end

  -- The source's 0.002 point lies inside the first 2.5% and is retained.
  local huge_points = corridor.asteroid_spawn_definitions[1].spawn_points
  equal(#huge_points, 3)
  close(huge_points[2].distance, 0.001 + (0.002 - 0.001) / (0.025 - 0.001) * 0.998,
    0.0000001)

  -- The source definition is copied rather than mutated by corridor creation.
  local source = data.raw["space-connection"]["solar-system-edge-shattered-planet"]
  equal(source.asteroid_spawn_definitions[1].spawn_points[3].distance, 0.2)
end)

io.write(tostring(passed) .. " data-stage tests passed\n")
