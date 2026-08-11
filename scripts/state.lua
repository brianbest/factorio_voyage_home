-- Persistent mission state. Only plain serialisable values are stored here;
-- Lua objects are always resolved again from their stable indexes/unit numbers.

local config = require("scripts.config")

local state = {}

local VALID_PHASE = {}
for _, phase in pairs(config.PHASE) do VALID_PHASE[phase] = true end

local function is_force_state(value)
  return type(value) == "table" and VALID_PHASE[value.phase] == true
end

local function new_force_state()
  return {
    phase = config.PHASE.LOCKED,
    max_shattered_distance_km = 0,
    discovery_tick = nil,
    vessel_unit_number = nil,
    vessel_platform_index = nil,
    vessel_destroy_registration = nil,
    transition_nonce = nil,
    transition_seed = nil,
    completed_tick = nil,
  }
end

local function new_player_state()
  return {
    mission_gui_visible = false,
    confirmation_open = false,
  }
end

function state.ensure_root(store)
  local target = store or storage
  target.tvh = target.tvh or {}
  local root = target.tvh
  root.schema_version = tonumber(root.schema_version) or config.SCHEMA_VERSION
  root.forces = root.forces or {}
  root.players = root.players or {}
  return root
end

function state.get_root(store)
  return state.ensure_root(store)
end

function state.ensure_force(force_or_index, store)
  local root = state.ensure_root(store)
  local index = type(force_or_index) == "number" and force_or_index or force_or_index.index
  local force_state = root.forces[index]
  if not force_state then
    force_state = new_force_state()
    root.forces[index] = force_state
  end
  state.normalise_force(force_state)
  return force_state
end

function state.ensure_player(player_or_index, store)
  local root = state.ensure_root(store)
  local index = type(player_or_index) == "number" and player_or_index or player_or_index.index
  local player_state = root.players[index]
  if not player_state then
    player_state = new_player_state()
    root.players[index] = player_state
  end
  if player_state.mission_gui_visible == nil then player_state.mission_gui_visible = false end
  if player_state.confirmation_open == nil then player_state.confirmation_open = false end
  return player_state
end

function state.normalise_force(force_state)
  if not VALID_PHASE[force_state.phase] then force_state.phase = config.PHASE.LOCKED end
  force_state.max_shattered_distance_km = math.max(
    0,
    tonumber(force_state.max_shattered_distance_km) or 0
  )
  return force_state
end

function state.set_phase(force_or_state, phase, store)
  assert(VALID_PHASE[phase], "Invalid Voyage Home phase: " .. tostring(phase))
  local force_state = is_force_state(force_or_state) and force_or_state
    or state.ensure_force(force_or_state, store)
  force_state.phase = phase
  return force_state
end

function state.clear_vessel(force_or_state, store)
  local force_state = is_force_state(force_or_state) and force_or_state
    or state.ensure_force(force_or_state, store)
  force_state.vessel_unit_number = nil
  force_state.vessel_platform_index = nil
  force_state.vessel_destroy_registration = nil
  return force_state
end

function state.resolve_vessel(force_or_state, runtime_game)
  local force_state = is_force_state(force_or_state) and force_or_state
    or state.ensure_force(force_or_state)
  local unit_number = force_state.vessel_unit_number
  if not unit_number then return nil end
  local active_game = runtime_game or game
  local entity = active_game and active_game.get_entity_by_unit_number(unit_number)
  if not (entity and entity.valid and entity.name == config.VESSEL_NAME) then
    state.clear_vessel(force_state)
    return nil
  end
  return entity
end

-- Reconcile progression when the mod is installed into an existing save. Never
-- infer a phase while a reset is in progress or after it has completed.
function state.reconcile_force(force, force_state)
  force_state = force_state or state.ensure_force(force)
  if force_state.phase == config.PHASE.TRANSITIONING
    or force_state.phase == config.PHASE.COMPLETE
  then
    return force_state
  end

  local technologies = force.technologies or {}
  local signal = technologies[config.SIGNAL_TECHNOLOGY]
  local navigation = technologies[config.NAVIGATION_TECHNOLOGY]
  if navigation and navigation.researched then
    force_state.phase = config.PHASE.ENABLED
  elseif signal and signal.researched then
    force_state.phase = config.PHASE.DISCOVERED
  end
  return force_state
end

function state.initialise_game(runtime_game, store)
  local root = state.ensure_root(store)
  local active_game = runtime_game or game
  for _, force in pairs(active_game.forces) do
    state.reconcile_force(force, state.ensure_force(force, store))
  end
  for _, player in pairs(active_game.players) do
    state.ensure_player(player, store)
  end
  return root
end

return state
