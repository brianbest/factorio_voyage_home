local icons = require("prototypes.icons")

local corridor_length = settings.startup["tvh-discovery-distance-km"].value
local source_connection = data.raw["space-connection"]["solar-system-edge-shattered-planet"]

if not source_connection or not source_connection.asteroid_spawn_definitions then
  error("The Voyage Home requires the Space Age Solar System Edge-to-Shattered Planet connection")
end

local function interpolate_spawn_point(points, source_distance)
  if source_distance <= points[1].distance then
    local result = table.deepcopy(points[1])
    result.distance = source_distance
    return result
  end

  for index = 2, #points do
    local upper = points[index]
    if source_distance <= upper.distance then
      local lower = points[index - 1]
      local span = upper.distance - lower.distance
      local factor = span == 0 and 0 or (source_distance - lower.distance) / span
      local result = table.deepcopy(lower)
      result.distance = source_distance

      for _, key in ipairs({"probability", "speed", "angle_when_stopped"}) do
        if type(lower[key]) == "number" and type(upper[key]) == "number" then
          result[key] = lower[key] + (upper[key] - lower[key]) * factor
        end
      end

      return result
    end
  end

  local result = table.deepcopy(points[#points])
  result.distance = source_distance
  return result
end

-- The vanilla connection is 4,000,000 km long. Preserve only its opening
-- segment, then remap that segment over this corridor's full normalized range.
local function early_route_asteroids(definitions, source_length, target_length)
  local result = table.deepcopy(definitions)
  local source_start = 0.001
  local source_finish = math.min(0.999, math.max(source_start + 0.000001, target_length / source_length))

  for _, definition in ipairs(result) do
    local source_points = definition.spawn_points
    table.sort(source_points, function(a, b) return a.distance < b.distance end)

    local target_points = {
      interpolate_spawn_point(source_points, source_start)
    }

    for _, point in ipairs(source_points) do
      if point.distance > source_start and point.distance < source_finish then
        table.insert(target_points, table.deepcopy(point))
      end
    end

    table.insert(target_points, interpolate_spawn_point(source_points, source_finish))

    for _, point in ipairs(target_points) do
      local progress = (point.distance - source_start) / (source_finish - source_start)
      point.distance = 0.001 + progress * 0.998
    end

    definition.spawn_points = target_points
  end

  return result
end

data:extend({
  {
    type = "space-location",
    name = "tvh-interstellar-staging",
    icons = icons.staging,
    starmap_icons = icons.staging_starmap,
    order = "f[solar-system-edge]-z[interstellar-staging]",
    subgroup = "planets",
    gravity_pull = -10,
    distance = 68,
    orientation = 0.235,
    magnitude = 0.85,
    label_orientation = 0.12,
    parked_platforms_orientation = 0.72,
    draw_orbit = false,
    fly_condition = false,
    auto_save_on_first_trip = false,
    solar_power_in_space = 1,
    asteroid_spawn_influence = 0
  },
  {
    type = "space-connection",
    name = "tvh-interstellar-corridor",
    icons = icons.staging,
    subgroup = "planet-connections",
    order = "j[the-voyage-home]",
    from = "solar-system-edge",
    to = "tvh-interstellar-staging",
    length = corridor_length,
    asteroid_spawn_definitions = early_route_asteroids(
      source_connection.asteroid_spawn_definitions,
      source_connection.length,
      corridor_length
    )
  }
})
