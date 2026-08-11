-- Storage migrations and post-migration object reconciliation.

local config = require("scripts.config")
local state = require("scripts.state")
local vessel = require("scripts.vessel")

local migrations = {}

local function migrate_to_v1(root)
  root.forces = root.forces or {}
  root.players = root.players or {}
  for _, force_state in pairs(root.forces) do state.normalise_force(force_state) end
  root.schema_version = 1
end

function migrations.run(_event, deps)
  deps = deps or {}
  local active_game = deps.game or game
  storage.tvh = storage.tvh or {schema_version = 0, forces = {}, players = {}}
  local root = storage.tvh
  local version = tonumber(root.schema_version) or 0

  if version < 1 then migrate_to_v1(root) end
  if root.schema_version > config.SCHEMA_VERSION then
    error("The Voyage Home storage schema is newer than this mod version")
  end

  state.initialise_game(active_game)
  local duplicate_count = 0
  for _, force in pairs(active_game.forces) do
    local recovered = vessel.recover_force(force, {
      script = deps.script,
      log = deps.log,
    })
    duplicate_count = duplicate_count + #recovered.duplicates
  end
  root.schema_version = config.SCHEMA_VERSION
  return {from_version = version, to_version = root.schema_version, duplicates = duplicate_count}
end

return migrations
