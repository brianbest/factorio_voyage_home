-- Cargo weight and fidelity-preserving, direct-stack transfer helpers.

local config = require("scripts.config")
local vessel = require("scripts.vessel")

local cargo = {}

local function as_inventory(source)
  if not source then return nil end
  if source.object_name == "LuaInventory" then return source end
  if source.get_inventory then return vessel.inventory(source) end
  return source -- Allows simple inventory doubles in tests.
end

function cargo.capacity(runtime_prototypes)
  return config.cargo_capacity(runtime_prototypes)
end

function cargo.weight(source)
  local inventory = as_inventory(source)
  return inventory and tonumber(inventory.weight) or 0
end

function cargo.fingerprint(source)
  local inventory = as_inventory(source)
  if not inventory then return {items = 0, stacks = 0, weight = 0} end
  local stacks = 0
  for index = 1, #inventory do
    local stack = inventory[index]
    if stack and stack.valid_for_read then stacks = stacks + 1 end
  end
  return {
    items = inventory.get_item_count(),
    stacks = stacks,
    weight = tonumber(inventory.weight) or 0,
  }
end

function cargo.is_within_capacity(source, capacity)
  local maximum = capacity or cargo.capacity()
  local weight = cargo.weight(source)
  return weight <= maximum, weight, maximum
end

local function same_fingerprint(expected, actual)
  return expected.items == actual.items
    and expected.weight == actual.weight
end

-- Returns a snapshot record owning a LuaInventory. The record is deliberately
-- not suitable for storage; the reset transaction must finish synchronously.
function cargo.create_snapshot(source, runtime_game, size)
  local source_inventory = as_inventory(source)
  if not (source_inventory and source_inventory.valid ~= false) then
    return nil, "source-inventory-invalid"
  end
  local active_game = runtime_game or game
  local snapshot_inventory = active_game.create_inventory(size or #source_inventory)
  local expected = cargo.fingerprint(source_inventory)
  snapshot_inventory.transfer_from_inventory(source_inventory)
  local actual = cargo.fingerprint(snapshot_inventory)

  if not source_inventory.is_empty() or not same_fingerprint(expected, actual) then
    source_inventory.transfer_from_inventory(snapshot_inventory)
    snapshot_inventory.destroy()
    return nil, "cargo-snapshot-verification-failed"
  end
  return {inventory = snapshot_inventory, fingerprint = expected}
end

function cargo.rollback(snapshot, destination)
  if not (snapshot and snapshot.inventory and snapshot.inventory.valid ~= false) then
    return false, "snapshot-invalid"
  end
  local destination_inventory = as_inventory(destination)
  if not destination_inventory then return false, "destination-inventory-invalid" end
  destination_inventory.transfer_from_inventory(snapshot.inventory)
  return snapshot.inventory.is_empty(), snapshot.inventory.is_empty()
    and nil or "cargo-rollback-incomplete"
end

function cargo.restore(snapshot, destination)
  if not (snapshot and snapshot.inventory and snapshot.inventory.valid ~= false) then
    return false, "snapshot-invalid"
  end
  local destination_inventory = as_inventory(destination)
  if not (destination_inventory and destination_inventory.valid ~= false) then
    return false, "destination-inventory-invalid"
  end
  if not destination_inventory.is_empty() then return false, "destination-not-empty" end
  destination_inventory.transfer_from_inventory(snapshot.inventory)
  local failure
  if not snapshot.inventory.is_empty() then
    failure = "arrival-cache-too-small"
  elseif not same_fingerprint(snapshot.fingerprint, cargo.fingerprint(destination_inventory)) then
    failure = "cargo-restore-verification-failed"
  end
  if failure then
    -- Destination was required to start empty, so moving it back cannot absorb
    -- unrelated items. Leave callers with the original intact snapshot.
    snapshot.inventory.transfer_from_inventory(destination_inventory)
    if not destination_inventory.is_empty() then
      return false, failure .. "-and-rollback-incomplete"
    end
    return false, failure
  end
  return true
end

function cargo.destroy_snapshot(snapshot)
  if snapshot and snapshot.inventory and snapshot.inventory.valid ~= false then
    if not snapshot.inventory.is_empty() then return false, "snapshot-not-empty" end
    snapshot.inventory.destroy()
  end
  return true
end

return cargo
