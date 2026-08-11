local icons = require("prototypes.icons")

local cache = table.deepcopy(data.raw.container["steel-chest"])
cache.name = "tvh-arrival-cache"
cache.icons = icons.arrival_cache
cache.icon = nil
cache.flags = {"placeable-neutral", "placeable-player", "player-creation"}
cache.minable = {mining_time = 0.5}
cache.max_health = 2000
cache.corpse = nil
cache.dying_explosion = "medium-explosion"
cache.collision_box = {{-0.9, -0.9}, {0.9, 0.9}}
cache.selection_box = {{-1, -1}, {1, 1}}
cache.fast_replaceable_group = nil
cache.next_upgrade = nil
cache.inventory_size = 48
cache.inventory_type = "normal"
cache.quality_affects_inventory_size = false
cache.map_color = {r = 1.0, g = 0.60, b = 0.16, a = 1.0}
cache.friendly_map_color = {r = 1.0, g = 0.60, b = 0.16, a = 1.0}
cache.picture = table.deepcopy(cache.picture)

for _, layer in ipairs(cache.picture.layers) do
  layer.scale = (layer.scale or 1) * 1.8
  if not layer.draw_as_shadow then
    layer.tint = {r = 1.0, g = 0.66, b = 0.22, a = 1.0}
  end
end

data:extend({cache})
