-- modules/player.lua
-- Character controls. Local only, no remote calls, no engine keys.
return function(ctx)
    local tab = ctx.win:CreateTab("Player", "rbxassetid://12130070198")
    local ui = ctx.ui
    local player = ctx.player
    local UIS = game:GetService("UserInputService")

    local walk, jump, infinite, keep = 16, 50, false, true

    local function humanoid()
        local character = player.Character
        return character and character:FindFirstChildOfClass("Humanoid") or nil
    end

    local function apply()
        local mob = humanoid()
        if not mob then return end
        mob.WalkSpeed = walk
        mob.UseJumpPower = true
        mob.JumpPower = jump
    end

    ui.section(tab, "Movement")
    ui.slider(tab, {
        name = "Walk Speed",
        range = { 16, 300 }, increment = 1, suffix = " studs/s", value = 16,
        onChange = function(value) walk = value; apply() end,
    })
    ui.slider(tab, {
        name = "Jump Power",
        range = { 50, 400 }, increment = 5, value = 50,
        onChange = function(value) jump = value; apply() end,
    })

    ui.toggle(tab, {
        name = "Infinite Jump", default = false,
        note = "Every jump request re-enters the jumping state.",
        onChange = function(value) infinite = value end,
    })

    ui.toggle(tab, {
        name = "Keep Movement", default = true,
        note = "Re-applies speed and jump on every respawn.",
        onChange = function(value) keep = value == true; if keep then apply() end end,
    })

    UIS.JumpRequest:Connect(function()
        if not infinite then return end
        local mob = humanoid()
        if mob then
            mob:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    end)

    player.CharacterAdded:Connect(function(character)
        local mob = character:WaitForChild("Humanoid", 10)
        if not mob or not keep then return end
        mob.WalkSpeed = walk
        mob.UseJumpPower = true
        mob.JumpPower = jump
    end)

    ui.section(tab, "Character")
    ui.button(tab, "Reset Character", function()
        local mob = humanoid()
        if mob then
            mob.Health = 0
        end
        ui.notify("Player", "character reset")
    end)
    ui.button(tab, "Refresh Status", function()
        local ok, state = pcall(ctx.engine.GetStatus)
        if ok and type(state) == "table" then
            ui.notify("Status", ("world %s  -  profile %s")
                :format(tostring(state.world), tostring(state.profile)))
        else
            ui.notify("Status", "engine not reporting")
        end
    end)
end
