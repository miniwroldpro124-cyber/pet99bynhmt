-- modules/render.lua
-- Client-side rendering and anti-afk.
return function(ctx)
    local tab = ctx.win:CreateTab("Render", "rbxassetid://6035047409")
    local ui = ctx.ui

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
