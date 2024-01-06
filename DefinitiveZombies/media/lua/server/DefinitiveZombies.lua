-- STATE MANAGERS
local CLIMATE_STATE = {}
local ZOMBIE_STATE = {}

-- The number of enums each zombie stat has
-- This is used to clamp the values
local ZOMBIE_STATS = {}
ZOMBIE_STATS["Speed"] = 3
ZOMBIE_STATS["Strength"] = 3
ZOMBIE_STATS["Toughness"] = 3
ZOMBIE_STATS["Cognition"] = 3
ZOMBIE_STATS["Memory"] = 4
ZOMBIE_STATS["Sight"] = 3
ZOMBIE_STATS["Hearing"] = 3

--Variables
local DEFINITIVEZOMBIES_UPDATEINTERVAL = getSandboxOptions():getOptionByName("DefinitiveZombies.UpdateInterval"):getValue()
local DEFINITIVEZOMBIES_REROLLATTEMPTS = getSandboxOptions():getOptionByName("DefinitiveZombies.RerollAttempts"):getValue()

local DEFINITIVEZOMBIES_CLIMATEGAMESTATES = {"DayLight", "Night", "Temperature", "FogIntensity", "RainIntensity", 
                                             "SnowIntensity", "CloudIntensity", "WindIntensity", "MoonPhase"} 
local DEFINITIVEZOMBIES_ISSTATIC = {"MoonPhase"}


local function LOGGER(output)
		if getSandboxOptions():getOptionByName("DefinitiveZombies.DebugEnable"):getValue() then 
				print(output) 
		end
end

-- Class ZombieState
--================================================================================
ZombieState = {}
ZombieState.__index = ZombieState

function ZombieState:new()
		-- Keeps track and modifies the sandbox settings for the zombies
		local self = setmetatable({}, ZombieState)
		self.zombieSandboxSetting = {}
		self.activeZombieStates = {}
		return self
end

function ZombieState:setSandboxState()
		--Sets the Zombie State in sandbox
		LOGGER("-----------------------------")
		LOGGER("SETTING ZOMBIE SANDBOX STATES")
		LOGGER("-----------------------------")
		for ZombieStat, value in pairs(ZOMBIE_STATS) do
				local baselineState = getSandboxOptions():getOptionByName("DefinitiveZombies." .. ZombieStat):getValue()
				local modifierState = CLIMATE_STATE.ZombieStateModifier[ZombieStat]
				local newState =  baselineState + modifierState
				LOGGER("-------------------")
				LOGGER("baselineState " .. ZombieStat .. ": " .. baselineState )
				LOGGER("modifierState " .. ZombieStat .. ": " .. CLIMATE_STATE.ZombieStateModifier[ZombieStat] )
				
			
				-- Clamp the values
				-- Generally a lower number buffs the zombies while higher numbers debuff the zombie
				-- eg. sprinter = 1 | fast shambler = 2 | shambler = 3
				if newState > value then
						newState = value
				elseif newState < 1 then
						newState = 1
				end
				LOGGER("newState " .. ZombieStat .. ": " .. newState )
				getSandboxOptions():set("ZombieLore." .. ZombieStat, newState)
		end
end

function ZombieState:getActiveZombieStates()
		--Determine which zombie states will be updated 
end

function ZombieState:getSandboxSettings()
	self.zombieSandboxSetting["speed"] = getSandboxOptions():getOptionByName("ZombieLore.Speed"):getValue();
	self.zombieSandboxSetting["toughness"] = getSandboxOptions():getOptionByName("ZombieLore.Toughness"):getValue();
	self.zombieSandboxSetting["strength"] = getSandboxOptions():getOptionByName("ZombieLore.Strength"):getValue();
	self.zombieSandboxSetting["hearing"] = getSandboxOptions():getOptionByName("ZombieLore.Hearing"):getValue();
	self.zombieSandboxSetting["sight"] = getSandboxOptions():getOptionByName("ZombieLore.Sight"):getValue();
	self.zombieSandboxSetting["memory"] = getSandboxOptions():getOptionByName("ZombieLore.Memory"):getValue();
	self.zombieSandboxSetting["cognition"] = getSandboxOptions():getOptionByName("ZombieLore.Cognition"):getValue();

end
-- Climate Class
--================================================================================
ClimateState = {}
ClimateState.__index = ClimateState

function ClimateState:new()
		-- State machine which manages the Climate state

		local self = setmetatable({}, ClimateState)
		self.settings = {}
		self.ZombieStateModifier = {}
		self.ActiveClimateStates = {}
		self.ClimateGameStates = {}
		return self
end

function ClimateState:getActiveClimateStates()
		-- Determine which climate states are activated in the sandbox
		-- used for calculation
		LOGGER("-----------------------------")
		LOGGER("GETTING ACTIVE CLIMATE STATES")
		LOGGER("-----------------------------")
		for key, ClimateName in ipairs(DEFINITIVEZOMBIES_CLIMATEGAMESTATES) do
				local ClimateEnableExists = getSandboxOptions():getOptionByName("DefinitiveZombies." .. ClimateName .. "Enable")
				if ClimateEnableExists then 
						if getSandboxOptions():getOptionByName("DefinitiveZombies." .. ClimateName .. "Enable"):getValue() then
								table.insert(self.ActiveClimateStates, ClimateName )
								LOGGER(ClimateName .. " is enabled")
						else
								LOGGER(ClimateName .. " is disabled")
						end
				end
		end
end

function ClimateState:getSandboxSettings()
		-- Build a dictionary of the climateState for referencing
		-- Get the settings from Sandbox which will be used to calculate
		--<ClimateState>:[<ClimateName><ZombieState><SandboxSetting>] <>
		-- self.settings["DayLight"]["DayLightLimit1"][DayLightValue1] = 3
		LOGGER("----------------------------------------")
		LOGGER("GETTING CLIMATE STATE SANDBOX SETTINGS")
		LOGGER("----------------------------------------")
		
		for k, ClimateName in ipairs(self.ActiveClimateStates) do
				self.settings[ClimateName] = {}
				for i=0,10 do
						local sandboxsettinga = ClimateName .. "_Interval" .. i 
						local sandboxsettingaExists = getSandboxOptions():getOptionByName("DefinitiveZombies." .. sandboxsettinga)
						if sandboxsettingaExists then 
								local sandboxsettingaValue = getSandboxOptions():getOptionByName("DefinitiveZombies." .. sandboxsettinga):getValue()
								LOGGER("Getting Interval: " .. sandboxsettinga .. " | " .. sandboxsettingaValue)
								self.settings[ClimateName][sandboxsettinga] = {value = sandboxsettingaValue}
								for ZombieStat, key  in pairs(ZOMBIE_STATS) do
										local sandboxsetting = ClimateName .. "_Effect" .. i .. "_" .. ZombieStat
										local sandboxsettingValue = getSandboxOptions():getOptionByName("DefinitiveZombies." .. sandboxsetting):getValue()
										LOGGER("Effect: " .. sandboxsetting .. " | " .. sandboxsettingValue)
										self.settings[ClimateName][sandboxsettinga][ZombieStat] = sandboxsettingValue
								end
						end
				end
		end
end


function ClimateState:getZombieStateModifier()	
		-- Given a Zombie State, find out how much to 
		-- modify it to get a new State(if any)

		LOGGER("----------------------------------------")
		LOGGER("CALCULATING ZOMBIE STATE MODIFIERS")
		LOGGER("----------------------------------------")
		LOGGER("Clearing previously cached data")
		for ZombieStat, value in pairs(ZOMBIE_STATS) do
				self.ZombieStateModifier[ZombieStat] = 0
		end
		-- Get the 
		local minNightStrength = getSandboxOptions():getOptionByName("DefinitiveZombies.MoonPhaseMinimumNightStrength"):getValue()
		for climateName, v in pairs(self.settings) do
				-- Check if the climate needs to be a static instead of a range
				local isStatic = false
				for key, value in ipairs(DEFINITIVEZOMBIES_ISSTATIC) do
						if value == climateName then
								isStatic = true
								break
						end 
				end
				
				local curLimitIndex = nil
				LOGGER("")
				LOGGER(string.upper(climateName))
				LOGGER("----------")
				for limit, va in pairs(self.settings[climateName]) do
						local myState = self.ClimateGameStates[climateName]
						local limitVal = self.settings[climateName][limit]["value"]

						--CALCULATE FOR STATIC
						if isStatic then
								if myState == limitVal then
										LOGGER("Determining Static: " .. limitVal)
										-- get moonphase
										if (climateName == "MoonPhase" and getClimateManager():getNightStrength() > minNightStrength) then
												curLimitIndex = limit
										end
								end
								
						--CALCULATE FOR RANGE
						else
								LOGGER("Determining Range: " .. limitVal)
								if myState > limitVal then
										curLimitIndex = limit
								end
						end
				end
				
				if curLimitIndex then
						for ZombieStat, value in pairs(ZOMBIE_STATS) do

								local currentModifierState = self.ZombieStateModifier[ZombieStat]
								local additionalModifierState = self.settings[climateName][curLimitIndex][ZombieStat] - 6
								if additionalModifierState <= -5 then additionalModifierState = -99 
								elseif additionalModifierState >= 5 then additionalModifierState = 99 end
								self.ZombieStateModifier[ZombieStat] =  currentModifierState + additionalModifierState
								LOGGER(ZombieStat .. ": " .. self.ZombieStateModifier[ZombieStat])
						end
				else
						LOGGER(climateName .. ": Zombie stats not modified as it does not fit into any range/static")
				end
				
				isStatic = false
		end
end

function ClimateState:updateClimateState()
		-- Moniters and gets up to date information about the current weather
		LOGGER("--------------------------")
		LOGGER("WORLD CLIMATE STATES")
		LOGGER("--------------------------")
		self.ClimateGameStates = {DayLight = getClimateManager():getDayLightStrength(),
															Night = getClimateManager():getNightStrength(),
															Temperature = getClimateManager():getTemperature(),
															FogIntensity = getClimateManager():getFogIntensity(),
															RainIntensity = getClimateManager():getRainIntensity(),
															SnowIntensity = getClimateManager():getRainIntensity(),
															CloudIntensity = getClimateManager():getCloudIntensity(),
															WindIntensity = getClimateManager():getWindIntensity(),
															MoonPhase = getClimateMoon():getCurrentMoonPhase()
															}
		for key, value in pairs(self.ClimateGameStates) do
		LOGGER(key .. ": " .. value)
		end
end



local function DefinitiveZombies_isZombieOutdated(zombie)
	local zombieOutdated = true;
	
	if zombie.Speed ~= ZOMBIE_STATE.zombieSandboxSetting.speed or zombie.Toughness ~= ZOMBIE_STATE.zombieSandboxSetting.toughness
	or zombie.Strength ~= ZOMBIE_STATE.zombieSandboxSetting.strength or zombie.Hearing ~= ZOMBIE_STATE.zombieSandboxSetting.hearing
	or zombie.Sight ~= ZOMBIE_STATE.zombieSandboxSetting.sight or zombie.Memory ~= ZOMBIE_STATE.zombieSandboxSetting.memory
	or zombie.Cognition ~= ZOMBIE_STATE.zombieSandboxSetting.cognition
	then
		zombieOutdated = false;
	end

	return zombieOutdated;
end


local function DefinitiveZombies_UpdateZombies(zombie)
		local zombieData = zombie:getModData()
		zombieData.Ticks = zombieData.Ticks or 0
		zombieData.ForceUpdate = zombieData.ForceUpdate or DEFINITIVEZOMBIES_REROLLATTEMPTS
		if zombieData.Ticks >= DEFINITIVEZOMBIES_UPDATEINTERVAL then
				if ZombRand(0, zombieData.ForceUpdate) == 0 then
						local zombieOutdated = DefinitiveZombies_isZombieOutdated(zombie)
						if not zombieOutdated  
						and ((not isClient() and not isServer()) or (isClient() and not zombie:isRemoteZombie())) then
							zombie:makeInactive(true);
							zombie:makeInactive(false);
							zombieData.Ticks = 0
							zombieData.ForceUpdate = DEFINITIVEZOMBIES_REROLLATTEMPTS
						else
								zombieData.ForceUpdate = DEFINITIVEZOMBIES_REROLLATTEMPTS
						end
				
				else
						zombieData.ForceUpdate = zombieData.ForceUpdate - 1
						zombieData.Ticks = 0;
				end
		else
				zombieData.Ticks = zombieData.Ticks + 1;
		end
end


-- GAME START
--================================================================================
local function DefinitiveZombies_UpdateStateManagers()
		LOGGER("Definitive Zombies LOG")
		LOGGER("=======================") 

		CLIMATE_STATE:updateClimateState()
		CLIMATE_STATE:getZombieStateModifier()
		
		ZOMBIE_STATE:setSandboxState()
		
		LOGGER("=======================")

end

local function DefinitiveZombies_OnGameTimeLoaded()
		--Initialise the settings on startup
		CLIMATE_STATE = ClimateState:new()
		CLIMATE_STATE:getActiveClimateStates()
		CLIMATE_STATE:getSandboxSettings()
		
		ZOMBIE_STATE = ZombieState:new()
		ZOMBIE_STATE:getSandboxSettings()
		
		--Updates
		Events.EveryTenMinutes.Add(DefinitiveZombies_UpdateStateManagers);
		Events.OnZombieUpdate.Add(DefinitiveZombies_UpdateZombies);
end


Events.OnGameTimeLoaded.Add(DefinitiveZombies_OnGameTimeLoaded);