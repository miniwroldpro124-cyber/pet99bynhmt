-- modules/pets.lua
-- Pet rendering and hatching.
return function(ctx)
    local tab = ctx.win:CreateTab("Pets", "rbxassetid://87867412432006")
    local ui = ctx.ui

    ui.section(tab, "Speed")
    ui.toggle(tab, {
        name = "Pet Speed", key = "petSpeed", default = false,
        note = "Hooks CalculateSpeedMultiplier and snaps pet positions to their target each frame.",
    })
    ui.slider(tab, {
        name = "Pet Re-route", key = "PetRouteRate",
        range = { 0.05, 0.5 }, increment = 0.05, suffix = "s", value = 0.15,
    })

    ui.section(tab, "Hatching")
    ui.toggle(tab, {
        name = "Auto Hatch", key = "autoEgg", default = false,
        note = "Buys and hatches the nearest egg, up to 50 per pass.",
    })
    ui.toggle(tab, {
        name = "Hide Egg Effects", key = "hideEggFx", default = false,
        note = "Kills hatch particles, beams and lights under every egg-named folder.",
    })

    ui.section(tab, "Targeting")
    ui.toggle(tab, {
        name = "Route All Pets", key = "petAll", default = true,
        note = "Every owned pet is sent at the target instead of the nearest half.",
    })
    ui.toggle(tab, {
        name = "Pet Bulk Join", key = "petBulkJoin", default = true,
        note = "Fires Breakables_JoinPetBulk once per target so pets count on the first hit.",
    })
end
