local icons = require("prototypes.icons")

data:extend({
  {
    type = "technology",
    name = "tvh-interstellar-signal",
    icon = "__space-age__/graphics/technology/solar-system-edge.png",
    icon_size = 256,
    essential = true,
    research_trigger = {
      type = "scripted",
      trigger_description = {
        "technology-trigger.tvh-interstellar-signal",
        settings.startup["tvh-discovery-distance-km"].value
      }
    },
    order = "z[the-voyage-home]-a[interstellar-signal]"
  },
  {
    type = "technology",
    name = "tvh-interstellar-navigation",
    icons = icons.staging,
    essential = true,
    prerequisites = {"tvh-interstellar-signal"},
    effects = {
      {
        type = "unlock-recipe",
        recipe = "tvh-interstellar-vessel"
      },
      {
        type = "unlock-space-location",
        space_location = "tvh-interstellar-staging",
        use_icon_overlay_constant = true
      }
    },
    unit = {
      count = 5000,
      time = 60,
      ingredients = {
        {"automation-science-pack", 1},
        {"logistic-science-pack", 1},
        {"chemical-science-pack", 1},
        {"production-science-pack", 1},
        {"utility-science-pack", 1},
        {"space-science-pack", 1},
        {"metallurgic-science-pack", 1},
        {"agricultural-science-pack", 1},
        {"electromagnetic-science-pack", 1},
        {"cryogenic-science-pack", 1},
        {"promethium-science-pack", 1}
      }
    },
    order = "z[the-voyage-home]-b[interstellar-navigation]"
  }
})
