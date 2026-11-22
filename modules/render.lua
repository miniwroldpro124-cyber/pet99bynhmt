-- modules/render.lua
-- Client-side rendering, White Screen, CPU/RAM reducer, and Anti-AFK.
return function(ctx)
    local tab = ctx.win:CreateTab("Render", "rbxassetid://6035047409")
    local ui = ctx.ui

    ui.section(tab, "Performance & Power Saving")
    ui.toggle(tab, {
        name = "White Screen (Disable 3D Render)", key = "whiteScreen", default = false,
        note = "Covers viewport with white overlay and disables 3D rendering for near-zero GPU usage.",
    })
    ui.toggle(tab, {
        name = "Reduce CPU & RAM", key = "reduceCpuRam", default = false,
        note = "Lowers QualityLevel, disables shadows & Lighting post-FX, caps FPS, cleans debris & particles.",
    })
    ui.slider(tab, {
        name = "Reduce CPU FPS Cap", key = "LowCpuFpsCap",
        range = { 5, 60 }, increment = 5, suffix = " fps", value = 15,
    })

    ui.section(tab, "Effects")
    ui.toggle(tab, {
        name = "Reduce Breakable Effects", key = "optBreakables", default = false,
        note = "Strips particle emitters, beams and trails from breakables. Restored on OFF.",
    })
    ui.toggle(tab, {
        name = "Reduce Pet Effects", key = "optPets", default = false,
    })

    ui.section(tab, "Session")
    ui.toggle(tab, {
        name = "Anti AFK", key = "antiAfk", default = false,
        note = "Keeps the session alive with no idle kick.",
    })
end
