local icons = {}

local STEEL_CHEST = "__base__/graphics/icons/steel-chest.png"
local QUANTUM_PROCESSOR = "__space-age__/graphics/icons/quantum-processor.png"
local PROMETHIUM_CHUNK = "__space-age__/graphics/icons/promethium-asteroid-chunk.png"
local SOLAR_SYSTEM_EDGE = "__space-age__/graphics/icons/solar-system-edge.png"
local STARMAP_EDGE = "__space-age__/graphics/icons/starmap-solar-system-edge.png"

icons.vessel = {
  {
    icon = STEEL_CHEST,
    icon_size = 64,
    tint = {r = 0.30, g = 0.58, b = 1.0, a = 1.0}
  },
  {
    icon = QUANTUM_PROCESSOR,
    icon_size = 64,
    scale = 0.34,
    shift = {8, 8}
  }
}

icons.arrival_cache = {
  {
    icon = STEEL_CHEST,
    icon_size = 64,
    tint = {r = 1.0, g = 0.66, b = 0.22, a = 1.0}
  },
  {
    icon = PROMETHIUM_CHUNK,
    icon_size = 64,
    scale = 0.32,
    shift = {8, 8}
  }
}

icons.staging = {
  {
    icon = SOLAR_SYSTEM_EDGE,
    icon_size = 64,
    tint = {r = 0.40, g = 0.75, b = 1.0, a = 1.0}
  },
  {
    icon = PROMETHIUM_CHUNK,
    icon_size = 64,
    scale = 0.30,
    shift = {8, 8}
  }
}

icons.staging_starmap = {
  {
    icon = STARMAP_EDGE,
    icon_size = 512,
    tint = {r = 0.32, g = 0.70, b = 1.0, a = 1.0}
  },
  {
    icon = PROMETHIUM_CHUNK,
    icon_size = 64,
    scale = 0.35
  }
}

return icons
