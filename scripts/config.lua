-- Central runtime configuration for The Voyage Home.
--
-- Prototype-stage code should use the same setting names and constants. Runtime
-- callers should prefer the accessor functions so tests can inject settings.

local config = {}

config.SCHEMA_VERSION = 1
config.SCAN_INTERVAL_TICKS = 60

config.DEFAULT_DISCOVERY_DISTANCE_KM = 100000
config.DEFAULT_CARGO_CAPACITY_MULTIPLIER = 1
config.DEFAULT_ROCKET_LIFT_WEIGHT = 1000000
config.VESSEL_INVENTORY_SIZE = 48

config.SETTING_DISCOVERY_DISTANCE = "tvh-discovery-distance-km"
config.SETTING_CARGO_CAPACITY_MULTIPLIER = "tvh-cargo-capacity-multiplier"
config.SETTING_DEVELOPMENT_COMMANDS = "tvh-development-commands"

config.SIGNAL_TECHNOLOGY = "tvh-interstellar-signal"
config.NAVIGATION_TECHNOLOGY = "tvh-interstellar-navigation"
config.VESSEL_NAME = "tvh-interstellar-vessel"
config.ARRIVAL_CACHE_NAME = "tvh-arrival-cache"
config.STAGING_LOCATION = "tvh-interstellar-staging"
config.CORRIDOR_CONNECTION = "tvh-interstellar-corridor"
config.SOLAR_SYSTEM_EDGE = "solar-system-edge"
config.SHATTERED_PLANET = "shattered-planet"
config.TRANSIT_SURFACE = "tvh-transit"
config.PRE_JUMP_AUTOSAVE = "tvh-pre-interstellar-jump"

config.PHASE = {
  LOCKED = "LOCKED",
  DISCOVERED = "DISCOVERED",
  ENABLED = "ENABLED",
  TRANSITIONING = "TRANSITIONING",
  COMPLETE = "COMPLETE",
}

local function startup_number(name, fallback)
  local startup = settings and settings.startup
  local setting = startup and startup[name]
  local value = setting and tonumber(setting.value)
  if value == nil then return fallback end
  return value
end

local function startup_boolean(name, fallback)
  local startup = settings and settings.startup
  local setting = startup and startup[name]
  if not setting or type(setting.value) ~= "boolean" then return fallback end
  return setting.value
end

function config.discovery_distance_km()
  return math.max(1, startup_number(
    config.SETTING_DISCOVERY_DISTANCE,
    config.DEFAULT_DISCOVERY_DISTANCE_KM
  ))
end

function config.cargo_capacity_multiplier()
  return math.max(0.1, startup_number(
    config.SETTING_CARGO_CAPACITY_MULTIPLIER,
    config.DEFAULT_CARGO_CAPACITY_MULTIPLIER
  ))
end

function config.development_commands_enabled()
  return startup_boolean(config.SETTING_DEVELOPMENT_COMMANDS, false)
end

-- Factorio 2.1 exposes this value through LuaPrototypes.utility_constants.
-- Keep the documented vanilla value as a defensive fallback for unit tests and
-- for a clearer failure mode if an older runtime loads the module.
function config.default_rocket_lift_weight(runtime_prototypes)
  local all_prototypes = runtime_prototypes or prototypes
  local constants = all_prototypes and all_prototypes.utility_constants
  local value = constants and tonumber(constants.default_rocket_lift_weight)
  return value or config.DEFAULT_ROCKET_LIFT_WEIGHT
end

function config.cargo_capacity(runtime_prototypes)
  return config.default_rocket_lift_weight(runtime_prototypes)
    * config.cargo_capacity_multiplier()
end

return config
