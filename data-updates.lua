local plant = data.raw["assembling-machine"]["electromagnetic-plant"]

if not plant then
  error("The Voyage Home requires Space Age's electromagnetic plant prototype")
end

for _, category in ipairs(plant.crafting_categories) do
  if category == "tvh-interstellar-vessel-crafting" then
    return
  end
end

table.insert(plant.crafting_categories, "tvh-interstellar-vessel-crafting")
