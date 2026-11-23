-- manifest.lua
-- Ordered module list for Steph HUB. main.lua downloads this file first,
-- then fetches each tab module with live progress on the loading screen.
return {
    { name = "Pumpkin Tycoon", file = "modules/event.lua",    icon = "rbxassetid://118952082110870" },
    { name = "Farm",           file = "modules/farm.lua",     icon = "rbxassetid://82329173638641" },
    { name = "Pets",           file = "modules/pets.lua",     icon = "rbxassetid://87867412432006" },
    { name = "World",          file = "modules/world.lua",    icon = "rbxassetid://16259403210" },
    { name = "Player",         file = "modules/player.lua",   icon = "rbxassetid://12130070198" },
    { name = "Progress",       file = "modules/progress.lua", icon = "rbxassetid://15642579187" },
    { name = "Consume",        file = "modules/consume.lua",  icon = "rbxassetid://16089599792" },
    { name = "Picks",          file = "modules/picks.lua",    icon = "rbxassetid://6031090990" },
    { name = "Cheat",          file = "modules/cheat.lua",    icon = "rbxassetid://6031090990" },
    { name = "Machines",       file = "modules/machines.lua", icon = "rbxassetid://126141499544212" },
    { name = "Render",         file = "modules/render.lua",   icon = "rbxassetid://6035047409" },
    { name = "Server",         file = "modules/server.lua",   icon = "rbxassetid://16093555964" },
    { name = "Config",         file = "modules/config.lua",   icon = "rbxassetid://6031090990" },
}
