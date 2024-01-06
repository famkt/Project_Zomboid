local function DefinitiveZombies_displayCurrentText(variation)
    --local preText = getText("IGUI_PlayerText_HTCWarmupReactionPre_0" .. tostring(variation))
    --local postText = getText("IGUI_PlayerText_HTCWarmupReactionPost_0" .. tostring(variation))
    --local text = preText .. postText

		getPlayer():Say("This is a test");
end
--[[
local function HTC_onServerCommand(module, command, args)
    HTC_onCommand(module, command, args)
end

local function HTC_onClientCommand(module, command, player, args)
    HTC_onCommand(module, command, args)
end

if isServer() == false then
    Events.EveryOneMinute.Add(HTC_IndicatorUpdate);
    if isClient() == false then
        Events.OnClientCommand.Add(HTC_onClientCommand);
    else
        Events.OnServerCommand.Add(HTC_onServerCommand);
    end
end
--]]