data:extend({
  {
    type = "int-setting",
    name = "tvh-discovery-distance-km",
    setting_type = "startup",
    default_value = 100000,
    minimum_value = 1000,
    maximum_value = 4000000,
    order = "a[progression]-a[discovery-distance]"
  },
  {
    type = "double-setting",
    name = "tvh-cargo-capacity-multiplier",
    setting_type = "startup",
    default_value = 1.0,
    minimum_value = 0.1,
    maximum_value = 100.0,
    order = "a[progression]-b[cargo-capacity]"
  },
  {
    type = "bool-setting",
    name = "tvh-development-commands",
    setting_type = "startup",
    default_value = false,
    order = "z[development]-a[commands]"
  }
})
