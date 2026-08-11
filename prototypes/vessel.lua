local icons = require("prototypes.icons")

local function scaled_chest_picture(scale_multiplier, tint)
  local picture = table.deepcopy(data.raw.container["steel-chest"].picture)

  for _, layer in ipairs(picture.layers) do
    layer.scale = (layer.scale or 1) * scale_multiplier
    if not layer.draw_as_shadow then
      layer.tint = tint
    end
  end

  return picture
end

local vessel = table.deepcopy(data.raw.container["steel-chest"])
vessel.name = "tvh-interstellar-vessel"
vessel.icons = icons.vessel
vessel.icon = nil
vessel.flags = {"placeable-neutral", "placeable-player", "player-creation"}
vessel.minable = {mining_time = 1, result = "tvh-interstellar-vessel"}
vessel.max_health = 2500
vessel.corpse = nil
vessel.dying_explosion = "medium-explosion"
vessel.collision_box = {{-2.4, -2.4}, {2.4, 2.4}}
vessel.selection_box = {{-2.5, -2.5}, {2.5, 2.5}}
vessel.drawing_box_vertical_extension = 0.8
vessel.fast_replaceable_group = nil
vessel.next_upgrade = nil
vessel.inventory_size = 48
vessel.inventory_type = "normal"
vessel.quality_affects_inventory_size = false
vessel.picture = scaled_chest_picture(4.5, {r = 0.30, g = 0.58, b = 1.0, a = 1.0})
vessel.surface_conditions = {
  {property = "pressure", min = 0, max = 0}
}
vessel.map_color = {r = 0.25, g = 0.60, b = 1.0, a = 1.0}
vessel.friendly_map_color = {r = 0.25, g = 0.60, b = 1.0, a = 1.0}
vessel.alert_icon_scale = 1.5
vessel.alert_icon_shift = {0, -1}

data:extend({
  {
    type = "item",
    name = "tvh-interstellar-vessel",
    icons = icons.vessel,
    subgroup = "space-platform",
    order = "z[the-voyage-home]-a[interstellar-vessel]",
    inventory_move_sound = table.deepcopy(data.raw.item["steel-chest"].inventory_move_sound),
    pick_sound = table.deepcopy(data.raw.item["steel-chest"].pick_sound),
    drop_sound = table.deepcopy(data.raw.item["steel-chest"].drop_sound),
    place_result = "tvh-interstellar-vessel",
    stack_size = 1,
    weight = 1 * tons
  },
  vessel,
  {
    type = "recipe",
    name = "tvh-interstellar-vessel",
    icons = icons.vessel,
    enabled = false,
    categories = {"tvh-interstellar-vessel-crafting"},
    subgroup = "space-platform",
    order = "z[the-voyage-home]-a[interstellar-vessel]",
    energy_required = 600,
    ingredients = {
      {type = "item", name = "quantum-processor", amount = 500},
      {type = "item", name = "low-density-structure", amount = 1000},
      {type = "item", name = "superconductor", amount = 500},
      {type = "item", name = "carbon-fiber", amount = 500},
      {type = "item", name = "tungsten-plate", amount = 1000},
      {type = "item", name = "lithium-plate", amount = 1000}
    },
    results = {
      {type = "item", name = "tvh-interstellar-vessel", amount = 1}
    },
    allow_productivity = false,
    allow_quality = true,
    allow_decomposition = false,
    auto_recycle = false
  }
})
