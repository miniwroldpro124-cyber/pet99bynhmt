-- manifest.lua
-- Ordered module list. main.lua downloads this file first, then one request per
-- entry. Add a tab by adding a row; nothing else in the project changes.
return {
    { name = "Farm",     file = "modules/farm.lua",     icon = "rbxassetid://82329173638641" },
    { name = "Pets",     file = "modules/pets.lua",     icon = "rbxassetid://87867412432006" },
    { name = "World",    file = "modules/world.lua",    icon = "rbxassetid://16259403210" },
    { name = "Progress", file = "modules/progress.lua", icon = "rbxassetid://15642579187" },
    { name = "Consume",  file = "modules/consume.lua",  icon = "rbxassetid://16089599792" },
    { name = "Machines", file = "modules/machines.lua", icon = "rbxassetid://126141499544212" },
    { name = "Render",   file = "modules/render.lua",   icon = "rbxassetid://6035047409" },
    { name = "Server",   file = "modules/server.lua",   icon = "rbxassetid://16093555964" },
}
