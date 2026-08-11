-- The guarded, one-shot interstellar reset transaction.
--
-- Public API:
--   preflight(player, deps?) -> report
--   dry_run(player, deps?)   -> report (same checks, no mutations)
--   execute(player, deps?)   -> result
--
-- Runtime collaborators are dependency-injected so control.lua can keep event
-- wiring and UI ownership outside this high-risk module.  See resolve_* below
-- for the accepted dependency shapes.

local modifiers = require("scripts.modifiers")
local default_readiness = require("scripts.readiness")

local reset = {}

local TRANSIT_SURFACE_NAME = "tvh-transit"
local ARRIVAL_CACHE_NAME = "tvh-arrival-cache"
local AUTOSAVE_NAME = "tvh-pre-interstellar-jump"
local STAGING_LOCATION_NAME = "tvh-interstellar-staging"
local ARRIVAL_CACHE_SLOTS = 48
local UINT32_RANGE = 4294967296

-- This is deliberately a name allowlist.  Iterating game.planets would erase
-- surfaces introduced by other mods, which the MVP explicitly forbids.
local VANILLA_PLANETS = { "nauvis", "vulcanus", "fulgora", "gleba", "aquilo" }
local STARTING_LOCKS = {
  "vulcanus",
  "fulgora",
  "gleba",
  "aquilo",
  "solar-system-edge",
  "shattered-planet",
  STAGING_LOCATION_NAME,
}

reset.constants = {
  transit_surface_name = TRANSIT_SURFACE_NAME,
  arrival_cache_name = ARRIVAL_CACHE_NAME,
  arrival_cache_slots = ARRIVAL_CACHE_SLOTS,
  autosave_name = AUTOSAVE_NAME,
  vanilla_planets = VANILLA_PLANETS,
}

local function add_issue(list, code, message)
  list[#list + 1] = { code = code, message = message }
end

local function logger_for(deps)
  if deps and deps.log then
    return deps.log
  end
  return function(message)
    if log then log("[TVH reset] " .. message) end
  end
end

local function get_force_state(force, deps)
  if deps then
    if deps.state_for then return deps.state_for(force) end
    local state = deps.state
    if state then
      if state.for_force then return state.for_force(force) end
      if state.get_force_state then return state.get_force_state(force) end
      if state.ensure_force then return state.ensure_force(force) end
      if state.get then return state.get(force) end
    end
  end

  local root = storage and storage.tvh
  return root and root.forces and root.forces[force.index] or nil
end

local function evaluate_readiness(player, deps)
  if deps then
    if deps.evaluate_readiness then return deps.evaluate_readiness(player) end
    if deps.readiness and deps.readiness.evaluate then
      return deps.readiness.evaluate(player)
    end
  end
  return default_readiness.evaluate(player)
end

local function resolve_vessel(force_state, readiness_result, deps)
  if deps and deps.get_vessel then
    local vessel = deps.get_vessel(force_state, readiness_result)
    if vessel then return vessel end
  end
  if readiness_result and readiness_result.vessel then
    return readiness_result.vessel
  end
  if force_state and force_state.vessel_unit_number then
    return game.get_entity_by_unit_number(force_state.vessel_unit_number)
  end
  return nil
end

local function vessel_inventory(vessel, deps)
  if deps and deps.get_vessel_inventory then
    return deps.get_vessel_inventory(vessel)
  end
  return vessel and vessel.get_inventory(defines.inventory.chest) or nil
end

local function cache_inventory_size(cache_name)
  local prototype = prototypes and prototypes.entity and prototypes.entity[cache_name]
  if not prototype then return nil end
  return prototype.get_inventory_size(defines.inventory.chest)
end

local function normalized_seed(value)
  value = math.floor(tonumber(value) or 0) % UINT32_RANGE
  if value < 0 then value = value + UINT32_RANGE end
  return value
end

local function transition_seed(force, tick)
  -- All intermediate values remain below 2^53, where Lua numbers represent
  -- integers exactly.  No global RNG state is consumed.
  return normalized_seed((normalized_seed(tick) * 1664525) + (force.index * 1013904223))
end

local function planet_seed(seed, planet_name)
  local value = normalized_seed(seed)
  for index = 1, #planet_name do
    value = normalized_seed((value * 1664525) + string.byte(planet_name, index) + 1013904223)
  end
  return value
end

local function collect_planet_surfaces(seed)
  local surfaces = {}
  for _, planet_name in ipairs(VANILLA_PLANETS) do
    local planet = game.planets[planet_name]
    local surface = planet and planet.surface or nil
    if surface and surface.valid then
      surfaces[#surfaces + 1] = {
        name = planet_name,
        surface = surface,
        old_seed = surface.map_gen_settings.seed,
        new_seed = planet_seed(seed, planet_name),
      }
    end
  end
  return surfaces
end

local function count_platforms(force)
  local platforms = {}
  for _, platform in pairs(force.platforms) do
    if platform.valid then
      platforms[#platforms + 1] = { index = platform.index, name = platform.name }
    end
  end
  table.sort(platforms, function(left, right) return left.index < right.index end)
  return platforms
end

local function inventory_summary(inventory)
  local summary = { slots = #inventory, occupied_slots = 0, item_count = 0, weight = inventory.weight }
  for index = 1, #inventory do
    local stack = inventory[index]
    if stack.valid_for_read then
      summary.occupied_slots = summary.occupied_slots + 1
      summary.item_count = summary.item_count + stack.count
    end
  end
  return summary
end

---Run every non-mutating safety check and describe the destructive work.
---@param player LuaPlayer
---@param deps? table
---@return table report
function reset.preflight(player, deps)
  local report = {
    ok = false,
    dry_run = true,
    errors = {},
    warnings = {},
    plan = {
      autosave_name = AUTOSAVE_NAME,
      transit_surface_name = TRANSIT_SURFACE_NAME,
      arrival_cache_name = ARRIVAL_CACHE_NAME,
      platforms = {},
      planet_surfaces = {},
    },
  }

  if not player or not player.valid then
    add_issue(report.errors, "invalid-player", "A valid player is required.")
    return report
  end
  if game.is_multiplayer() then
    add_issue(report.errors, "multiplayer-unsupported", "The MVP transition is single-player only.")
  end

  local force = player.force
  local force_state = get_force_state(force, deps)
  report.force_index = force.index
  report.force_name = force.name
  report.phase = force_state and force_state.phase or nil

  if not force_state then
    add_issue(report.errors, "missing-force-state", "Mission state for this force is missing.")
  elseif force_state.phase ~= "ENABLED" then
    add_issue(report.errors, "wrong-phase", "Mission phase must be ENABLED, not " .. tostring(force_state.phase) .. ".")
  end
  if force_state and force_state.transition_nonce ~= nil then
    add_issue(report.errors, "nonce-already-committed", "A transition nonce has already been committed for this force.")
  end

  local readiness_result = evaluate_readiness(player, deps)
  report.readiness = readiness_result
  if not readiness_result then
    add_issue(report.errors, "missing-readiness-evaluator", "No readiness evaluator was supplied to the reset module.")
  elseif not readiness_result.ready then
    add_issue(report.errors, "not-ready", "The final readiness check did not pass.")
  end

  local nauvis = game.get_surface("nauvis")
  if not nauvis or not nauvis.valid then
    add_issue(report.errors, "missing-nauvis", "The Nauvis surface does not exist.")
  elseif not nauvis.planet or nauvis.planet.name ~= "nauvis" then
    add_issue(report.errors, "invalid-nauvis-association", "The Nauvis surface is not associated with the vanilla Nauvis planet.")
  end

  local transit = game.get_surface(TRANSIT_SURFACE_NAME)
  if transit then
    local expected_index = force_state and force_state.transition_transit_surface_index
    if not expected_index or transit.index ~= expected_index then
      add_issue(report.errors, "transit-surface-collision", "A surface named '" .. TRANSIT_SURFACE_NAME .. "' already exists and is not owned by this transition.")
    else
      add_issue(report.errors, "stale-transit-surface", "A transit surface from a prior transition attempt still exists.")
    end
  end

  local cache_size = cache_inventory_size(ARRIVAL_CACHE_NAME)
  report.arrival_cache_slots = cache_size
  if not cache_size then
    add_issue(report.errors, "missing-arrival-cache-prototype", "The arrival cache prototype is missing or has no chest inventory.")
  elseif cache_size < ARRIVAL_CACHE_SLOTS then
    add_issue(report.errors, "arrival-cache-too-small", "The arrival cache has fewer than 48 slots.")
  end

  local vessel = resolve_vessel(force_state, readiness_result, deps)
  report.vessel = vessel
  if not vessel or not vessel.valid then
    add_issue(report.errors, "missing-vessel", "The registered Interstellar Vessel is no longer valid.")
  else
    local inventory = vessel_inventory(vessel, deps)
    report.vessel_inventory = inventory
    if not inventory or not inventory.valid then
      add_issue(report.errors, "missing-vessel-inventory", "The Interstellar Vessel cargo inventory is unavailable.")
    else
      report.cargo = inventory_summary(inventory)
      if cache_size and #inventory > cache_size then
        add_issue(report.errors, "cargo-slot-overflow", "The vessel has more inventory slots than the arrival cache.")
      end
    end
  end

  local seed = transition_seed(force, game.tick)
  report.planned_transition_seed = seed
  report.plan.platforms = count_platforms(force)
  for _, entry in ipairs(collect_planet_surfaces(seed)) do
    report.plan.planet_surfaces[#report.plan.planet_surfaces + 1] = {
      name = entry.name,
      old_seed = entry.old_seed,
      new_seed = entry.new_seed,
    }
  end
  if #report.plan.planet_surfaces == 0 then
    add_issue(report.errors, "no-planet-surfaces", "No vanilla Space Age planet surfaces were found to regenerate.")
  end

  report.ok = #report.errors == 0
  return report
end

---Alias that emphasizes this call never mutates game state.
function reset.dry_run(player, deps)
  return reset.preflight(player, deps)
end

local function transfer_slotwise(source, destination)
  if #destination < #source then
    return false, "destination inventory is smaller than source inventory"
  end
  for index = 1, #source do
    local source_stack = source[index]
    if source_stack.valid_for_read then
      local destination_stack = destination[index]
      if destination_stack.valid_for_read then
        return false, "destination slot " .. index .. " is not empty"
      end
      if not destination_stack.transfer_stack(source_stack) or source_stack.valid_for_read then
        return false, "direct transfer failed at slot " .. index
      end
    end
  end
  return true
end

local function rollback_slotwise(temporary, original)
  if #original < #temporary then
    return false, "original inventory is smaller than temporary inventory"
  end
  for index = 1, #temporary do
    local temporary_stack = temporary[index]
    if temporary_stack.valid_for_read then
      local original_stack = original[index]
      -- Unlike the forward transfer, the source slot can contain the
      -- untransferred remainder of the same original stack. transfer_stack
      -- safely merges it and gives us an exact full-transfer result.
      if not original_stack.transfer_stack(temporary_stack) or temporary_stack.valid_for_read then
        return false, "direct rollback failed at slot " .. index
      end
    end
  end
  return true
end

local function snapshot_cargo(inventory)
  local before = inventory_summary(inventory)
  local temporary = game.create_inventory(#inventory, { "entity-name.tvh-interstellar-vessel" })
  local ok, reason = transfer_slotwise(inventory, temporary)
  local after = inventory_summary(temporary)

  if not ok or not inventory.is_empty()
      or before.occupied_slots ~= after.occupied_slots
      or before.item_count ~= after.item_count
      or before.weight ~= after.weight then
    local rolled_back, rollback_reason = rollback_slotwise(temporary, inventory)
    if temporary.valid then temporary.destroy() end
    local suffix = rolled_back and "" or ("; rollback also failed: " .. tostring(rollback_reason))
    return nil, "cargo snapshot verification failed: " .. tostring(reason or "inventory mismatch") .. suffix
  end
  return temporary, before
end

local function mark_step(force_state, nonce, step, emit)
  force_state.transition_step = step
  force_state.transition_step_tick = game.tick
  emit("nonce=" .. tostring(nonce) .. " step=" .. step)
end

local function create_transit_surface(seed)
  local surface = game.create_surface(TRANSIT_SURFACE_NAME, {
    seed = seed,
    width = 64,
    height = 64,
    no_enemies_mode = true,
    default_enable_all_autoplace_controls = false,
    autoplace_controls = {},
  })
  surface.generate_with_lab_tiles = true
  surface.always_day = true
  surface.request_to_generate_chunks({ 0, 0 }, 1)
  -- This API is explicitly synchronous: it blocks until all requested chunks
  -- have been generated, so execute() requires no continuation event.
  surface.force_generate_chunk_requests()
  return surface
end

local function destroy_platforms(force)
  local platforms = {}
  for _, platform in pairs(force.platforms) do
    if platform.valid then platforms[#platforms + 1] = platform end
  end
  for _, platform in ipairs(platforms) do
    if platform.valid then platform.destroy(0) end
  end
  return #platforms
end

local function regenerate_planets(force, seed)
  local regenerated = {}
  local enemy = game.forces.enemy
  for _, entry in ipairs(collect_planet_surfaces(seed)) do
    local surface = entry.surface
    local settings = surface.map_gen_settings
    settings.seed = entry.new_seed
    surface.map_gen_settings = settings
    surface.clear(false)
    surface.clear_pollution()
    force.clear_chart(surface)
    if enemy and enemy.valid then
      enemy.set_evolution_factor(0, surface)
      enemy.set_evolution_factor_by_pollution(0, surface)
      enemy.set_evolution_factor_by_time(0, surface)
      enemy.set_evolution_factor_by_killing_spawners(0, surface)
    end
    regenerated[#regenerated + 1] = { name = entry.name, seed = entry.new_seed }
  end
  return regenerated
end

local function enforce_starting_unlocks(force)
  if game.planets.nauvis then force.unlock_space_location("nauvis") end
  for _, location_name in ipairs(STARTING_LOCKS) do
    if prototypes.space_location[location_name] then
      force.lock_space_location(location_name)
    end
  end
  force.lock_space_platforms()
end

local function prepare_arrival(force, temporary, deps)
  local nauvis = game.get_surface("nauvis")
  assert(nauvis and nauvis.valid, "Nauvis disappeared during reset")

  local origin = (deps and deps.arrival_origin) or { 0, 0 }
  local radius = (deps and deps.arrival_chunk_radius) or 8
  nauvis.request_to_generate_chunks(origin, radius)
  nauvis.force_generate_chunk_requests()

  local character_position = nauvis.find_non_colliding_position("character", origin, 64, 0.5)
  assert(character_position, "could not find a safe character position on regenerated Nauvis")
  force.set_spawn_position(character_position, nauvis)

  local desired_cache_position = { character_position.x + 4, character_position.y }
  local cache_position = nauvis.find_non_colliding_position(ARRIVAL_CACHE_NAME, desired_cache_position, 64, 0.5, true)
  assert(cache_position, "could not find a safe arrival-cache position")

  local cache = nauvis.create_entity {
    name = ARRIVAL_CACHE_NAME,
    position = cache_position,
    force = force,
    create_build_effect_smoke = false,
  }
  assert(cache and cache.valid, "arrival cache creation failed")
  cache.destructible = false
  cache.minable_flag = false

  local inventory = cache.get_inventory(defines.inventory.chest)
  assert(inventory and inventory.valid, "arrival cache has no valid chest inventory")
  local expected = inventory_summary(temporary)
  local transferred, reason = transfer_slotwise(temporary, inventory)
  local actual = inventory_summary(inventory)
  assert(transferred, "arrival cargo transfer failed: " .. tostring(reason))
  assert(temporary.is_empty(), "temporary cargo inventory was not emptied")
  assert(expected.occupied_slots == actual.occupied_slots
      and expected.item_count == actual.item_count
      and expected.weight == actual.weight,
    "arrival cargo verification failed")

  return {
    surface = nauvis,
    character_position = character_position,
    cache = cache,
    cache_position = cache_position,
    cargo = actual,
  }
end

local function complete_ui(force, deps)
  if not deps then return end
  if deps.ui and deps.ui.destroy_all_for_force then
    deps.ui.destroy_all_for_force(force)
  elseif deps.destroy_all_ui_for_force then
    deps.destroy_all_ui_for_force(force)
  end
end

---Execute the complete reset synchronously after one final preflight.
---On an error after nonce commit, phase intentionally remains TRANSITIONING and
---the last step remains in storage; the named autosave is the recovery path.
---@param player LuaPlayer
---@param deps? table
---@return table result
function reset.execute(player, deps)
  local report = reset.preflight(player, deps)
  if not report.ok then
    return { ok = false, code = "preflight-failed", report = report }
  end

  local force = player.force
  local force_state = get_force_state(force, deps)
  local inventory = report.vessel_inventory
  local emit = logger_for(deps)

  -- The autosave request is made before even the reversible inventory move.
  game.auto_save(AUTOSAVE_NAME, true)

  local temporary, cargo_before = snapshot_cargo(inventory)
  if not temporary then
    return { ok = false, code = "cargo-snapshot-failed", error = cargo_before, report = report }
  end

  local modifier_snapshot_ok, modifier_snapshot = pcall(modifiers.snapshot, force)
  if not modifier_snapshot_ok then
    local rolled_back, rollback_reason = rollback_slotwise(temporary, inventory)
    if temporary.valid then temporary.destroy() end
    return {
      ok = false,
      code = "modifier-snapshot-failed",
      error = tostring(modifier_snapshot),
      rollback_ok = rolled_back,
      rollback_error = rollback_reason,
    }
  end

  local seed = transition_seed(force, game.tick)
  local nonce = tostring(force.index) .. ":" .. tostring(game.tick) .. ":" .. tostring(seed)
  force_state.phase = "TRANSITIONING"
  force_state.transition_nonce = nonce
  force_state.transition_seed = seed
  force_state.transition_started_tick = game.tick
  mark_step(force_state, nonce, "nonce-committed", emit)

  local result = { ok = false, nonce = nonce, seed = seed, cargo = cargo_before }
  local succeeded, failure = xpcall(function()
    mark_step(force_state, nonce, "creating-transit-surface", emit)
    local transit = create_transit_surface(seed)
    force_state.transition_transit_surface_index = transit.index

    mark_step(force_state, nonce, "moving-player-to-transit", emit)
    assert(player.teleport({ 0, 0 }, transit), "player could not be teleported to transit surface")

    mark_step(force_state, nonce, "destroying-platforms", emit)
    result.platforms_destroyed = destroy_platforms(force)

    mark_step(force_state, nonce, "regenerating-planets", emit)
    result.regenerated_planets = regenerate_planets(force, seed)

    mark_step(force_state, nonce, "resetting-force", emit)
    force.reset()
    enforce_starting_unlocks(force)

    mark_step(force_state, nonce, "restoring-modifiers", emit)
    result.modifiers = modifiers.restore(force, modifier_snapshot, emit)

    mark_step(force_state, nonce, "creating-arrival", emit)
    local arrival = prepare_arrival(force, temporary, deps)
    result.arrival_cache_unit_number = arrival.cache.unit_number
    result.arrival_position = arrival.character_position

    mark_step(force_state, nonce, "moving-player-to-nauvis", emit)
    assert(player.teleport(arrival.character_position, arrival.surface), "player could not be teleported to Nauvis")
    if player.character and player.character.valid then
      player.character.health = player.character.max_health
    end

    mark_step(force_state, nonce, "committing", emit)
    temporary.destroy()
    assert(game.delete_surface(transit), "transit surface could not be deleted")

    force_state.vessel_unit_number = nil
    force_state.vessel_platform_index = nil
    force_state.vessel_destroy_registration = nil
    force_state.transition_transit_surface_index = nil
    arrival.cache.destructible = true
    arrival.cache.minable_flag = true
    -- Phase is the final commit marker. Nothing that can reasonably fail is
    -- performed between this write and the successful return.
    force_state.phase = "COMPLETE"
    force_state.completed_tick = game.tick
    force_state.transition_step = "complete"
    force_state.transition_step_tick = game.tick
    result.ok = true
  end, function(error_message)
    return tostring(error_message)
  end)

  if not succeeded then
    emit("nonce=" .. nonce .. " FAILED after step=" .. tostring(force_state.transition_step) .. ": " .. failure)
    result.code = "transition-failed"
    result.error = failure
    result.last_step = force_state.transition_step
    result.recovery_save = AUTOSAVE_NAME
    return result
  end

  -- UI cleanup is deliberately outside the cargo commit. A broken UI hook must
  -- not turn a successfully verified world reset into a failed transaction.
  local ui_ok, ui_error = pcall(complete_ui, force, deps)
  if not ui_ok then emit("post-commit UI cleanup failed: " .. tostring(ui_error)) end
  if deps and deps.on_complete then
    local hook_ok, hook_error = pcall(deps.on_complete, player, result)
    if not hook_ok then emit("post-commit completion hook failed: " .. tostring(hook_error)) end
  end

  player.print({ "tvh-message.arrival-complete" })
  emit("nonce=" .. nonce .. " step=complete")
  return result
end

return reset
