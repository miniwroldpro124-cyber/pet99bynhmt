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
    ui.toggle(tab, {
        name = "Super FPS Improve (Delete Unnecessary Map & FX)", key = "superFps", default = false,
        note = "Deletes unnecessary map props, trees, buildings, debris, decals, textures, and effects while keeping floors, breakables, eggs, and machines intact.",
    })
    ui.button(tab, "Delete Unnecessary Map & FX Now (1-Click)", function()
        if type(ctx.engine.SuperFpsClean) ~= "function" then
            ui.notify("Super FPS Improve", "SuperFpsClean is unavailable in current engine.")
            return
        end
        local removed, stripped, summary = ctx.engine.SuperFpsClean()
        ui.notify(
            "Super FPS Improve",
            summary or ("Removed %d unnecessary objects/FX (%d parts optimized)."):format(tonumber(removed) or 0, tonumber(stripped) or 0),
            5
        )
    end)

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
