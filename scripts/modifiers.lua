-- Permanent force progress that is explicitly allowed to survive one jump.
--
-- This module intentionally knows nothing about mission state or the reset
-- transaction.  Keeping the allowlist here makes it difficult for a future
-- technology effect to begin surviving by accident.

local modifiers = {}

local FORCE_FIELDS = {
  "worker_robots_speed_modifier",
  "worker_robots_storage_bonus",
  "mining_drill_productivity_bonus",
  "laboratory_speed_modifier",
  "laboratory_productivity_bonus",
}

modifiers.FORCE_FIELDS = FORCE_FIELDS

local function emit(logger, message)
  if logger then
    logger(message)
  elseif log then
    log("[TVH modifiers] " .. message)
  end
end

---Capture only the fixed modifier allowlist from the MVP specification.
---@param force LuaForce
---@return table snapshot A storage-safe table containing numbers only.
function modifiers.snapshot(force)
  assert(force and force.valid, "cannot snapshot an invalid force")

  local snapshot = {
    force_fields = {},
    recipe_productivity = {},
  }

  for _, field in ipairs(FORCE_FIELDS) do
    snapshot.force_fields[field] = force[field]
  end

  for recipe_name, recipe in pairs(force.recipes) do
    local bonus = recipe.productivity_bonus
    if bonus and bonus > 0 then
      snapshot.recipe_productivity[recipe_name] = bonus
    end
  end

  return snapshot
end

---Restore an allowlisted snapshot after LuaForce::reset().
---@param force LuaForce
---@param snapshot table
---@param logger? fun(message:string)
---@return table result
function modifiers.restore(force, snapshot, logger)
  assert(force and force.valid, "cannot restore modifiers to an invalid force")
  assert(type(snapshot) == "table", "modifier snapshot is missing")

  local result = {
    restored_force_fields = {},
    restored_recipes = {},
    missing_recipes = {},
  }

  local fields = snapshot.force_fields or {}
  for _, field in ipairs(FORCE_FIELDS) do
    local value = fields[field]
    if type(value) == "number" then
      force[field] = value
      result.restored_force_fields[#result.restored_force_fields + 1] = field
    else
      emit(logger, "snapshot omitted numeric field '" .. field .. "'; default retained")
    end
  end

  for recipe_name, bonus in pairs(snapshot.recipe_productivity or {}) do
    local recipe = force.recipes[recipe_name]
    if recipe then
      recipe.productivity_bonus = bonus
      result.restored_recipes[#result.restored_recipes + 1] = recipe_name
    else
      result.missing_recipes[#result.missing_recipes + 1] = recipe_name
      emit(logger, "recipe '" .. recipe_name .. "' no longer exists; productivity was not restored")
    end
  end

  table.sort(result.restored_recipes)
  table.sort(result.missing_recipes)
  return result
end

return modifiers
