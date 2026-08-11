-- Mission, vessel-relative, and confirmation interfaces.
--
-- GUI state is intentionally advisory. The final click delegates to the reset
-- module, which performs a complete readiness/preflight calculation again.

local config = require("scripts.config")
local state = require("scripts.state")
local readiness = require("scripts.readiness")

local gui = {}

gui.NAME = {
  mission_button = "tvh-mission-button",
  mission_panel = "tvh-mission-panel",
  close_panel = "tvh-close-mission-panel",
  jump_button = "tvh-initiate-jump",
  confirmation = "tvh-jump-confirmation",
  cancel_jump = "tvh-cancel-jump",
  confirm_jump = "tvh-confirm-jump",
  vessel_panel = "tvh-vessel-relative-panel",
}

local CHECK_ORDER = {
  "navigation_researched",
  "vessel_present",
  "vessel_on_platform",
  "at_staging_point",
  "engineer_aboard",
  "cargo_within_limit",
  "personal_inventory_empty",
  "transition_idle",
}

local function valid(object)
  return object and object.valid ~= false
end

local function destroy(element)
  if valid(element) then element.destroy() end
end

local function clamp(value, minimum, maximum)
  return math.max(minimum, math.min(maximum, value))
end

local function player_for(index)
  local player = game.get_player(index)
  if player and player.valid then return player end
  return nil
end

local function is_remote_view(player)
  return player.controller_type == defines.controllers.remote
    or player.render_mode == defines.render_mode.chart
    or player.render_mode == defines.render_mode.chart_zoomed_in
end

local function phase_caption(phase)
  return {"tvh-phase." .. string.lower(phase or config.PHASE.LOCKED)}
end

local function format_weight(weight)
  -- Factorio weight values use grams; keep a stable localized integer display.
  return {"tvh-gui.weight-kilograms", math.floor((weight or 0) / 1000 + 0.5)}
end

local function add_heading(parent, caption)
  local label = parent.add { type = "label", caption = caption }
  label.style.font = "default-semibold"
  return label
end

local function add_key_value(table_element, key, value)
  table_element.add { type = "label", caption = key }
  local value_label = table_element.add { type = "label", caption = value }
  value_label.style.single_line = false
  return value_label
end

local function add_checklist(parent, result)
  add_heading(parent, {"tvh-gui.readiness"})
  local checks = parent.add { type = "table", column_count = 2 }
  for _, name in ipairs(CHECK_ORDER) do
    local passed = result.checks[name] == true
    checks.add {
      type = "sprite",
      sprite = passed and "utility/check_mark" or "utility/not_available",
      tooltip = passed and {"tvh-gui.check-passed"} or {"tvh-gui.check-failed"},
    }
    local label = checks.add {
      type = "label",
      caption = {"tvh-check." .. name},
    }
    if not passed then label.style.font_color = { 1, 0.45, 0.35 } end
  end
end

local function add_status(parent, player, result)
  local force_state = state.ensure_force(player.force)
  local details = parent.add { type = "table", column_count = 2 }
  add_key_value(details, {"tvh-gui.stage"}, phase_caption(force_state.phase))
  add_key_value(
    details,
    {"tvh-gui.discovery-distance"},
    {"tvh-gui.distance-progress", math.floor(force_state.max_shattered_distance_km),
      math.floor(config.discovery_distance_km())}
  )
  add_key_value(
    details,
    {"tvh-gui.platform"},
    result.platform_name or {"tvh-gui.none"}
  )
  add_key_value(
    details,
    {"tvh-gui.cargo"},
    {"tvh-gui.weight-progress", format_weight(result.cargo_weight),
      format_weight(result.cargo_capacity)}
  )

  local progress = parent.add {
    type = "progressbar",
    value = clamp(result.cargo_weight / math.max(1, result.cargo_capacity), 0, 1),
  }
  progress.style.horizontally_stretchable = true
  if result.cargo_weight > result.cargo_capacity then
    progress.style.color = { 1, 0.2, 0.15 }
  end
end

local function build_mission_panel(player)
  destroy(player.gui.left[gui.NAME.mission_panel])
  local frame = player.gui.left.add {
    type = "frame",
    name = gui.NAME.mission_panel,
    direction = "vertical",
    caption = {"tvh-gui.title"},
  }
  frame.style.width = 390

  local result = readiness.evaluate(player)
  add_status(frame, player, result)
  add_checklist(frame, result)

  local buttons = frame.add { type = "flow", direction = "horizontal" }
  buttons.style.top_margin = 8
  buttons.add {
    type = "button",
    name = gui.NAME.close_panel,
    caption = {"gui.close"},
  }
  buttons.add {
    type = "button",
    name = gui.NAME.jump_button,
    caption = {"tvh-gui.initiate-jump"},
    enabled = result.ready,
    tooltip = result.ready
      and {"tvh-gui.jump-ready-tooltip"}
      or {"tvh-gui.jump-disabled-tooltip"},
  }
  return frame
end

local function build_vessel_panel(player)
  destroy(player.gui.relative[gui.NAME.vessel_panel])
  local frame = player.gui.relative.add {
    type = "frame",
    name = gui.NAME.vessel_panel,
    direction = "vertical",
    caption = {"tvh-gui.vessel-status"},
    anchor = {
      gui = defines.relative_gui_type.container_gui,
      position = defines.relative_gui_position.right,
      name = config.VESSEL_NAME,
    },
  }
  frame.style.width = 330
  local result = readiness.evaluate(player)
  add_status(frame, player, result)
  if result.checks.at_staging_point then add_checklist(frame, result) end
  if result.cargo_weight > result.cargo_capacity then
    local warning = frame.add { type = "label", caption = {"tvh-gui.overweight-warning"} }
    warning.style.font_color = { 1, 0.35, 0.25 }
    warning.style.single_line = false
  end
  frame.add {
    type = "button",
    name = gui.NAME.jump_button,
    caption = {"tvh-gui.initiate-jump"},
    enabled = result.ready,
  }
end

function gui.destroy_confirmation(player)
  destroy(player.gui.screen[gui.NAME.confirmation])
  local player_state = state.ensure_player(player)
  player_state.confirmation_open = false
end

function gui.show_confirmation(player)
  local result = readiness.evaluate(player)
  if not result.ready then
    gui.show_readiness_error(player, result)
    return false
  end

  gui.destroy_confirmation(player)
  local frame = player.gui.screen.add {
    type = "frame",
    name = gui.NAME.confirmation,
    direction = "vertical",
    caption = {"tvh-confirm.title"},
  }
  frame.style.width = 560
  frame.auto_center = true

  local warning = frame.add { type = "label", caption = {"tvh-confirm.warning"} }
  warning.style.single_line = false
  warning.style.font_color = { 1, 0.45, 0.25 }
  frame.add { type = "line" }
  local erased = frame.add { type = "label", caption = {"tvh-confirm.erased"} }
  erased.style.single_line = false
  local preserved = frame.add { type = "label", caption = {"tvh-confirm.preserved"} }
  preserved.style.single_line = false
  local save = frame.add { type = "label", caption = {"tvh-confirm.autosave"} }
  save.style.single_line = false

  local buttons = frame.add { type = "flow", direction = "horizontal" }
  buttons.style.top_margin = 12
  buttons.add {
    type = "button",
    name = gui.NAME.cancel_jump,
    caption = {"gui.cancel"},
  }
  local confirm = buttons.add {
    type = "button",
    name = gui.NAME.confirm_jump,
    caption = {"tvh-confirm.confirm"},
    style = "confirm_button",
  }
  confirm.style.left_margin = 8

  state.ensure_player(player).confirmation_open = true
  player.opened = frame
  return true
end

function gui.show_readiness_error(player, result)
  result = result or readiness.evaluate(player)
  player.print({"tvh-message.not-ready"})
  for _, name in ipairs(CHECK_ORDER) do
    if not result.checks[name] then
      player.print({"tvh-message.failed-check", {"tvh-check." .. name}})
    end
  end
end

function gui.refresh_player(player)
  if not valid(player) then return end
  local force_state = state.ensure_force(player.force)
  local available = force_state.phase == config.PHASE.DISCOVERED
    or force_state.phase == config.PHASE.ENABLED
  local remote = is_remote_view(player)
  local player_state = state.ensure_player(player)

  if not available or not remote then
    destroy(player.gui.top[gui.NAME.mission_button])
    destroy(player.gui.left[gui.NAME.mission_panel])
    player_state.mission_gui_visible = false
  else
    if not valid(player.gui.top[gui.NAME.mission_button]) then
      player.gui.top.add {
        type = "sprite-button",
        name = gui.NAME.mission_button,
        sprite = "item/" .. config.VESSEL_NAME,
        tooltip = {"tvh-gui.open-mission"},
      }
    end
    if player_state.mission_gui_visible then build_mission_panel(player) end
  end

  local opened = player.opened
  if valid(opened) and opened.object_name == "LuaEntity" and opened.name == config.VESSEL_NAME then
    build_vessel_panel(player)
  end
end

function gui.refresh_force(force)
  for _, player in pairs(force.connected_players) do gui.refresh_player(player) end
end

function gui.destroy_all_for_force(force)
  for _, player in pairs(force.players) do
    destroy(player.gui.top[gui.NAME.mission_button])
    destroy(player.gui.left[gui.NAME.mission_panel])
    destroy(player.gui.relative[gui.NAME.vessel_panel])
    gui.destroy_confirmation(player)
    state.ensure_player(player).mission_gui_visible = false
  end
end

function gui.on_gui_opened(event)
  local player = player_for(event.player_index)
  if not player then return end
  if valid(event.entity) and event.entity.name == config.VESSEL_NAME then
    build_vessel_panel(player)
  end
end

function gui.on_gui_closed(event)
  local player = player_for(event.player_index)
  if not player then return end
  if valid(event.element) and event.element.name == gui.NAME.confirmation then
    gui.destroy_confirmation(player)
  end
  if valid(event.entity) and event.entity.name == config.VESSEL_NAME then
    destroy(player.gui.relative[gui.NAME.vessel_panel])
  end
end

function gui.on_gui_click(event, deps)
  deps = deps or {}
  local player = player_for(event.player_index)
  local element = event.element
  if not player or not valid(element) then return false end

  if element.name == gui.NAME.mission_button then
    local player_state = state.ensure_player(player)
    player_state.mission_gui_visible = not player_state.mission_gui_visible
    if player_state.mission_gui_visible then
      build_mission_panel(player)
    else
      destroy(player.gui.left[gui.NAME.mission_panel])
    end
    return true
  elseif element.name == gui.NAME.close_panel then
    state.ensure_player(player).mission_gui_visible = false
    destroy(player.gui.left[gui.NAME.mission_panel])
    return true
  elseif element.name == gui.NAME.jump_button then
    gui.show_confirmation(player)
    return true
  elseif element.name == gui.NAME.cancel_jump then
    gui.destroy_confirmation(player)
    return true
  elseif element.name == gui.NAME.confirm_jump then
    -- Closing first prevents a stale second click. reset.execute performs the
    -- authoritative readiness and preflight checks again.
    gui.destroy_confirmation(player)
    local execute = deps.execute
    if not execute then
      local reset = require("scripts.reset")
      execute = reset.execute
    end
    local outcome = execute(player, deps.reset_dependencies)
    if not outcome or not outcome.ok then
      player.print({"tvh-message.transition-aborted", outcome and outcome.error or "unknown"})
      gui.refresh_player(player)
    end
    return true
  end
  return false
end

return gui
