--[[
DOC STRING

functions
* ZombieState - "Class" to manage the zombie state
* ClimateState - "Class" to manage the climate state
* DZ_is_zombie_outdated - Check if the zombie's current stats are outdated
* DZ_initialise_zombies - Initialise the zombie's meta data
* DZ_set_zombie_metadata - Update the zombie's meta data
* DZ_seed_zombies - Seed the zombie stats based on the dictionary in ZombieState.zombie_random_modifier
* DZ_reset_sandbox - Reset the sandbox setting to DZ baseline zombie
* DZ_update_zombie - Update the zombie to the latest stats
* DZ_update_zombies - On Zombie Update tick, determine if the zombies need to be updated
* DZ_update_managers - Run the functions in the "Class" managers so they are up to date
* DefinitiveZombies_OnGameTimeLoaded - Set up the entire mod
--]]


--[[
List down each zombie stat the game monitors. And how many items each zombie stat has. 
(nomenclature: items is a PYQT reference to entrees in a drop-down box)
If a new zombie stats get added in a future game update, add it and its clamp value here
Remember to add the new zombie stat to "zombie_baseline" as well

: param dict DZ_ZOMBIE_STATS : All available in-game zombie stats
--]]
local DZ_ZOMBIE_STATS = {}
DZ_ZOMBIE_STATS["Speed"] = 3
DZ_ZOMBIE_STATS["Strength"] = 3
DZ_ZOMBIE_STATS["Toughness"] = 3
DZ_ZOMBIE_STATS["Cognition"] = 3
DZ_ZOMBIE_STATS["Memory"] = 4
DZ_ZOMBIE_STATS["Sight"] = 3
DZ_ZOMBIE_STATS["Hearing"] = 3

--[[
Variables
: param dict DZ_CLIMATE_MANAGER : "Class" to manage the climate
: param dict DZ_ZOMBIE_MANAGER : "Class" to manage the zombies
: param dict DZ_CLIMATES : List all climates the mod is suppose to monitor and handle
: param dict DZ_STATIC_CLIMATES : Climates which are calculated as a static value instead of a range of values
--]]
local DZ_CLIMATE_MANAGER = {}
local DZ_ZOMBIE_MANAGER = {}
local DZ_CLIMATES = {"DayLight", "Night", "Temperature", "FogIntensity", "RainIntensity", 
                     "SnowIntensity", "CloudIntensity", "WindIntensity", "MoonPhase", "Time"} 
local DZ_STATIC_CLIMATES = {"MoonPhase"}

--[[
Debugging Variables
: param float DZ_UPDATE_TICK_RATE : Affects how often the zombies should update their stats
: param float DZ_REROLL_MAX : Secondary key to space out how often zombies will update their stats
: param float DZ_MOONPHASE_DARK : How dark the world must be in order for the moonphase to become active
: param Bool DZ_DEBUG : Prints debugging text to the output log
--]]
local DZ_UPDATE_TICK_RATE = nil
local DZ_REROLL_MAX = nil
local DZ_MOONPHASE_DARK = nil
local DZ_DEBUG = nil


local function LOGGER(output)
		--Print the output to the output log.
		if DZ_DEBUG then 
				print(output) 
		end
end

-- Class ZombieState
--================================================================================
ZombieState = {}
ZombieState.__index = ZombieState

function ZombieState:new()
		--[[
		State manager which manages the zombies and their appropriate stat
		
		functions
		* _get_zombie_baseline - On game start, Copy the baseline zombie stats from sandbox into a look up table 
		* _get_zombie_active_stats - On game start, get a list of zombie stats the user has activated
		* _get_zombie_active_random_stats - On game start, store the zombie stat seeding into a look up table
		* _update_zombie_random_modifier - On game start, create a look up table for seeding of zombie stats
		* update_zombie_climate_modifier - create a look up table based on the climate states on how much we need to update the zombie stats
		* get_seed_effect - Get a seed for a zombie's stat based off the random table
		* update_zombie_latest_stats - Based off the calculations from the climate state, set the zombie's stats in the sandbox to it
 
		
		:param dict zombie_baseline: The baseline stats of the zombie
		:param dict zombie_active_stats: Zombie stats activated by the user
		:param dict zombie_latest_stats: The zombies expected stats after climate calculation
		:(DEPRECATED) param dict zombie_latest_stats_clamped: The zombies expected stats after climate calculation after being clamped
		:param dict zombie_climate_modifier: The zombies stat
		
		:param dict zombie_active_random_stats: which zombie stats should be seeded with random values
		:param dict zombie_random_modifier: stores the random seeding for zombies, seeded zombie stats will be determined by this
		--]]
		local self = setmetatable({}, ZombieState)
		self.zombie_baseline = {}
		self.zombie_active_stats = {}
		self.zombie_latest_stats = {}
		--self.zombie_latest_stats_clamped = {}
		self.zombie_climate_modifier = {}
		
		self.zombie_active_random_stats = {}
		self.zombie_random_modifier = {}
		return self
end


function ZombieState:_get_zombie_baseline()
	-- Copy the baseline zombie stats from sandbox into a look up table
	self.zombie_baseline["Speed"] = getSandboxOptions():getOptionByName("DefinitiveZombies.Speed"):getValue();
	self.zombie_baseline["Toughness"] = getSandboxOptions():getOptionByName("DefinitiveZombies.Toughness"):getValue();
	self.zombie_baseline["Strength"] = getSandboxOptions():getOptionByName("DefinitiveZombies.Strength"):getValue();
	self.zombie_baseline["Hearing"] = getSandboxOptions():getOptionByName("DefinitiveZombies.Hearing"):getValue();
	self.zombie_baseline["Sight"] = getSandboxOptions():getOptionByName("DefinitiveZombies.Sight"):getValue();
	self.zombie_baseline["Memory"] = getSandboxOptions():getOptionByName("DefinitiveZombies.Memory"):getValue();
	self.zombie_baseline["Cognition"] = getSandboxOptions():getOptionByName("DefinitiveZombies.Cognition"):getValue();
end


function ZombieState:_get_zombie_active_stats()
		--[[
		Determine which zombies states are activated in the sandbox and store them under zombie_active_stats.
		This is for optimisation as we will only calculate these climates states that are needed.
		This function runs on game/server start.
		--]]
		LOGGER("-----------------------------")
		LOGGER("GETTING ACTIVE ZOMBIE STATS")
		LOGGER("-----------------------------")
		for stat_name, value in pairs(DZ_ZOMBIE_STATS) do
			local enable_zombie_stat = getSandboxOptions():getOptionByName("DefinitiveZombies." .. stat_name .. "Enable")
			if enable_zombie_stat then 
					if getSandboxOptions():getOptionByName("DefinitiveZombies." .. stat_name .. "Enable"):getValue() then
							table.insert(self.zombie_active_stats, stat_name )
							LOGGER(stat_name .. " is enabled")
					else
							LOGGER(stat_name .. " is disabled")
					end
			end
		end
end


function ZombieState:_get_zombie_active_random_stats()
		--[[
		Determine which random zombies states are activated in the sandbox and store them under zombie_active_random_stats.
		This is for optimisation as we only process states which are active
		This function runs on game/server start.
		--]]
		LOGGER("-----------------------------")
		LOGGER("GETTING RANDOM SEEDING")
		LOGGER("-----------------------------")
		for stat_name, value in pairs(DZ_ZOMBIE_STATS) do
			local enable_zombie_stat = getSandboxOptions():getOptionByName("DefinitiveZombies." .. stat_name .. "_Seed_Enable")
			if enable_zombie_stat then 
					if getSandboxOptions():getOptionByName("DefinitiveZombies." .. stat_name .. "_Seed_Enable"):getValue() then
							table.insert(self.zombie_active_random_stats, stat_name )
							LOGGER(stat_name .. " seeding is enabled")
					else
							LOGGER(stat_name .. " seeding is disabled")
					end
			end
		end
end


function ZombieState:_update_zombie_random_modifier()
		--[[
		Create a look up table which determines the chance a zombie is assigned an effect. 
		eg.
		
		
		The effects  are properly converted to the appopriate stage. 
		eg. 
		A value of 6 means there is no change to the stage
		A value of 5 means to increase by 1 stage

		zombie_random_modifier[<stat_name>][<random_interval>][<seed_chance>]
		                                                      [<seed_effect>]
		zombie_random_modifier["Speed"]["Seed1"][25]
		                                        [99 stages]
		--]]

		LOGGER("-----------------------------")
		LOGGER("CALCULATING RANDOM SEEDING")
		LOGGER("-----------------------------")
		-- Initialise the dictionary 
		-- All zombie stats instead of just the active stats will be initialised
		
		for stat_name, value in pairs(DZ_ZOMBIE_STATS) do
				self.zombie_random_modifier[stat_name] = {}
				for i=1,5 do
						self.zombie_random_modifier[stat_name]["Seed" .. i] = {}
				end
				-- Give the seeds value which do not do anything
				self.zombie_random_modifier[stat_name]["Seed1"]["seed_chance"] = 100
				self.zombie_random_modifier[stat_name]["Seed1"]["seed_effect"] = 0
				self.zombie_random_modifier[stat_name]["Seed2"]["seed_chance"] = 100
				self.zombie_random_modifier[stat_name]["Seed2"]["seed_effect"] = 0
				self.zombie_random_modifier[stat_name]["Seed3"]["seed_chance"] = 100
				self.zombie_random_modifier[stat_name]["Seed3"]["seed_effect"] = 0
				self.zombie_random_modifier[stat_name]["Seed4"]["seed_chance"] = 100
				self.zombie_random_modifier[stat_name]["Seed4"]["seed_effect"] = 0			
				self.zombie_random_modifier[stat_name]["Seed5"]["seed_chance"] = 100
				self.zombie_random_modifier[stat_name]["Seed5"]["seed_effect"] = 0								
		end
		
		-- Calculate the seed chance
		for key, stat_name in pairs(self.zombie_active_random_stats) do
				local interval1 = getSandboxOptions():getOptionByName("DefinitiveZombies." .. stat_name .. "_Seed1"):getValue()
				local interval2 = getSandboxOptions():getOptionByName("DefinitiveZombies." .. stat_name .. "_Seed2"):getValue()
				local interval3 = getSandboxOptions():getOptionByName("DefinitiveZombies." .. stat_name .. "_Seed3"):getValue()
				local interval4 = getSandboxOptions():getOptionByName("DefinitiveZombies." .. stat_name .. "_Seed4"):getValue()
				local interval5 = getSandboxOptions():getOptionByName("DefinitiveZombies." .. stat_name .. "_Seed5"):getValue()
				
				-- Error check to prevent a divide by 0 error in case the user sets all seed_chance to 0
				if interval1 > 0 or interval2 > 0 or interval3 > 0 or interval4 > 0 or interval5> 0 then

						--Normalise the weights,  using default settings, interval1 = 0.2, interval2 = 0.4, etc. 
						local total_interval = interval1 + interval2 + interval3 + interval4 + interval5
						self.zombie_random_modifier[stat_name]["Seed1"]["seed_chance"] = interval1/total_interval
						self.zombie_random_modifier[stat_name]["Seed2"]["seed_chance"] = interval2/total_interval + self.zombie_random_modifier[stat_name]["Seed1"]["seed_chance"]
						self.zombie_random_modifier[stat_name]["Seed3"]["seed_chance"] = interval3/total_interval + self.zombie_random_modifier[stat_name]["Seed2"]["seed_chance"]
						self.zombie_random_modifier[stat_name]["Seed4"]["seed_chance"] = interval4/total_interval + self.zombie_random_modifier[stat_name]["Seed3"]["seed_chance"]
						self.zombie_random_modifier[stat_name]["Seed5"]["seed_chance"] = interval5/total_interval + self.zombie_random_modifier[stat_name]["Seed4"]["seed_chance"]
						
						-- Calculate the effect of the seed
						for i=1,5 do
								LOGGER("DefinitiveZombies." .. stat_name .. "_Seed" .. i .. "_Effect")
								local seed_effect = getSandboxOptions():getOptionByName("DefinitiveZombies." .. stat_name .. "_Seed" .. i .. "_Effect"):getValue()
								seed_effect = seed_effect - 6

								if seed_effect <= -5 then seed_effect = -99
								elseif seed_effect >= 5 then seed_effect = 99 end
				
								self.zombie_random_modifier[stat_name]["Seed" .. i]["seed_effect"] = seed_effect

						end
						
				end
				
			  LOGGER(stat_name)
				LOGGER("----------")
				LOGGER("Seed1: " .. self.zombie_random_modifier[stat_name]["Seed1"]["seed_chance"])
				LOGGER("Seed1 Effect: " .. self.zombie_random_modifier[stat_name]["Seed1"]["seed_effect"])
				LOGGER("Seed2: " .. self.zombie_random_modifier[stat_name]["Seed2"]["seed_chance"])
				LOGGER("Seed2 Effect: " .. self.zombie_random_modifier[stat_name]["Seed2"]["seed_effect"])
				LOGGER("Seed3: " .. self.zombie_random_modifier[stat_name]["Seed3"]["seed_chance"])
				LOGGER("Seed3 Effect: " .. self.zombie_random_modifier[stat_name]["Seed3"]["seed_effect"])
				LOGGER("Seed4: " .. self.zombie_random_modifier[stat_name]["Seed4"]["seed_chance"])
				LOGGER("Seed4 Effect: " .. self.zombie_random_modifier[stat_name]["Seed4"]["seed_effect"])
				LOGGER("Seed5: " .. self.zombie_random_modifier[stat_name]["Seed4"]["seed_chance"])
				LOGGER("Seed5 Effect: " .. self.zombie_random_modifier[stat_name]["Seed4"]["seed_effect"])
		end
		
end


function ZombieState:update_zombie_climate_modifier()	
		--[[ 
		Calculate how much the zombie's stats need to be modified/updated 
		based on the data from DZ_CLIMATE_MANAGER.
		This function only creates a dictionary, it does not update 
		the zombie's stats. Values are not clamped
		--]]
		LOGGER("----------------------------------------")
		LOGGER("CALCULATING ZOMBIE STAT MODIFIERS")
		LOGGER("----------------------------------------")
		LOGGER("Clearing previously cached data")
		for key, stat_name in ipairs(self.zombie_active_stats) do
				self.zombie_climate_modifier[stat_name] = 0
		end

		for climate_name, v in pairs(DZ_CLIMATE_MANAGER.sandbox_settings) do
				-- Check if the climate needs to be a static instead of a range
				local is_static_climate = false
				for key, static_climate in ipairs(DZ_STATIC_CLIMATES) do
						if static_climate == climate_name then
								is_static_climate = true
								break
						end 
				end
				
				local current_climate_interval = nil
				LOGGER("")
				LOGGER(string.upper(climate_name))
				LOGGER("----------")
				for climate_interval, va in pairs(DZ_CLIMATE_MANAGER.sandbox_settings[climate_name]) do
						local current_climate_value = DZ_CLIMATE_MANAGER.current_climate[climate_name]
						local climate_interval_value = DZ_CLIMATE_MANAGER.sandbox_settings[climate_name][climate_interval]["value"]

						--CALCULATE FOR STATIC
						if is_static_climate then
								if current_climate_value == climate_interval_value then
										LOGGER("Determining Static: " .. climate_interval_value)
										--Special logic for Moon Phase
										if (climate_name == "MoonPhase" and getClimateManager():getNightStrength() > DZ_MOONPHASE_DARK) then
												current_climate_interval = climate_interval
										end
								end
								
						--CALCULATE FOR RANGE
						-- climate_interval is the name of the interval
						-- climate_interval_value is the value from the interval in sandbox 
						-- current_climate_value the current value of the in-game climate
						else
								LOGGER("Determining Range: " .. climate_interval_value)
								--Special logic for Time climate
								if climate_name == "Time" then
										if current_climate_value > climate_interval_value then
												current_climate_interval = climate_interval
										else
												if not current_climate_interval then
														current_climate_interval = DZ_CLIMATE_MANAGER.sandbox_settings[climate_name][2]
												end
										end
										
								else
										if current_climate_value > climate_interval_value then
												current_climate_interval = climate_interval
										end
								end
						end
				end
						
				-- Determine how much value to add 
				if current_climate_interval then
						for key, stat_name in ipairs(self.zombie_active_stats) do
								local currentModifierState = self.zombie_climate_modifier[stat_name]
								local additionalModifierState = DZ_CLIMATE_MANAGER.sandbox_settings[climate_name][current_climate_interval][stat_name] - 6 
								if additionalModifierState <= -5 then additionalModifierState = -99 
								elseif additionalModifierState >= 5 then additionalModifierState = 99 end
								self.zombie_climate_modifier[stat_name] =  currentModifierState + additionalModifierState
								LOGGER(stat_name .. ": " .. self.zombie_climate_modifier[stat_name])
						end
				else
						LOGGER(climate_name .. ": Zombie stats not modified as the climate does not fit into any range/static")
				end
				

				-- Reset the loop
				is_static_climate = false
		end

end


function ZombieState:get_seed_effect(stat_name)
		--[[
		Look up the ZombieState:zombie_random_modifier and get a seed for the randomised zombie's stat
		
		: param stat_name (string) : The name of the zombie's stat, Speed, Strength, Memory, etc.
		--]]
		local seed1 = self.zombie_random_modifier[stat_name]["Seed1"]["seed_chance"]
		local seed2 = self.zombie_random_modifier[stat_name]["Seed2"]["seed_chance"]
		local seed3 = self.zombie_random_modifier[stat_name]["Seed3"]["seed_chance"]
		local seed4 = self.zombie_random_modifier[stat_name]["Seed4"]["seed_chance"]
		local seed5 = self.zombie_random_modifier[stat_name]["Seed5"]["seed_chance"]
		local seed_effect = 0
		
		local seed = ZombRandFloat(0, 1.0)
		if seed1 >= seed then
				seed_effect = self.zombie_random_modifier[stat_name]["Seed1"]["seed_effect"]
		end
		if seed1 < seed and seed <= seed2 then
				seed_effect = self.zombie_random_modifier[stat_name]["Seed2"]["seed_effect"]
		end
		if seed2 < seed and seed <= seed3 then
				seed_effect = self.zombie_random_modifier[stat_name]["Seed3"]["seed_effect"]
		end
		if seed3 < seed and seed <= seed4 then
				seed_effect = self.zombie_random_modifier[stat_name]["Seed4"]["seed_effect"]
		end
		if seed4 < seed and seed <= seed5 then
				seed_effect = self.zombie_random_modifier[stat_name]["Seed5"]["seed_effect"]
		end
		return seed_effect
end


function ZombieState:update_zombie_latest_stats()
		--[[
		Using self.zombie_climate_modifier calculate the expected zombie stats after climate influence.
		Zombie stat seeding will be calculated later on each individual zombie
		--]]
		LOGGER("-----------------------------")
		LOGGER("SETTING ZOMBIE SANDBOX STATES")
		LOGGER("-----------------------------")
		for key, stat_name in ipairs(self.zombie_active_stats) do
		
		--for stat_name, value in pairs(DZ_ZOMBIE_STATS) do
				local zombie_stat_baseline = getSandboxOptions():getOptionByName("DefinitiveZombies." .. stat_name):getValue()
				local zombie_stat_modifed = self.zombie_climate_modifier[stat_name] 
				local zombie_stat_combined =  zombie_stat_baseline + zombie_stat_modifed
				LOGGER("-------------------")
				LOGGER("zombie_stat_baseline " .. stat_name .. ": " .. zombie_stat_baseline )
				LOGGER("zombie_stat_modifed " .. stat_name .. ": " .. self.zombie_climate_modifier[stat_name] )
				
				LOGGER("zombie_stat_combined " .. stat_name .. ": " .. zombie_stat_combined )
				self.zombie_latest_stats[stat_name] = zombie_stat_combined

				-- Clamp the values
				value = DZ_ZOMBIE_STATS[stat_name]
				if zombie_stat_combined > value then
						local zombie_stat_clamped = value
				elseif zombie_stat_combined < 1 then
						local zombie_stat_clamped = 1
				end				
				--self.zombie_latest_stats_clamped[stat_name] = zombie_stat_clamped
				--getSandboxOptions():set("ZombieLore." .. stat_name, zombie_stat_combined)
		end
end





-- Climate Class
--================================================================================
ClimateState = {}
ClimateState.__index = ClimateState

function ClimateState:new()
		--[[
		CLASS ClimateState
		State manager which manages the climate. Stores climate values
		
		functions
		* _get_active_climate_states - On game start, get a list of climate states that the player has activated
		* _get_climate_settings - On game start, store the climate settings onto a look up table
		* get_current_climates - On game tick (10mins), record the current climate values
		
		-- Speech functions(WIP)
		* (WIP) getActiveClimateSpeech - Give text feedback to the player on esoteric weathers
		* updateCurrentClimateInterval
		* climateIntervalIsDifferent
		
		:param dict sandbox_settings: stores the settings from the sandbox so we don't have to query it everytime
		:param dict active_climate_states: Climates which are enabled by the user
		:param dict current_climate: The current in-game climate values
		Variables involved in speech
		:param dict ActiveClimateSpeech: 
		:param dict OldClimateInterval: 
		:param dict CurrentClimateInterval: 
		:param dict ClimateCooldown: 
		:param dict ClimateIsDifferent: 
		--]]
		-- State machine which manages the Climate state

		local self = setmetatable({}, ClimateState)
		self.sandbox_settings = {}
		self.active_climate_states = {}
		
		--Current climate values
		self.current_climate = {}
		
		--Vairables for speech
		self.ActiveClimateSpeech = {}
		self.OldClimateInterval = {}
		self.CurrentClimateInterval = {}
		self.ClimateCooldown = 0
		self.ClimateIsDifferent = false
		return self
end


function ClimateState:_get_active_climate_states()
		--[[
		Determine which climate states are activated in the sandbox and store them under active_climate_states.
		This is for optimisation as we will only calculate these climates states that are needed.
		We only need to run this once.
		--]]
		LOGGER("-----------------------------")
		LOGGER("GETTING ACTIVE CLIMATE STATES")
		LOGGER("-----------------------------")
		for key, climate_name in ipairs(DZ_CLIMATES) do
				local climate_enabled = getSandboxOptions():getOptionByName("DefinitiveZombies." .. climate_name .. "Enable")
				if climate_enabled then 
						if getSandboxOptions():getOptionByName("DefinitiveZombies." .. climate_name .. "Enable"):getValue() then
								table.insert(self.active_climate_states, climate_name )
								-- Check for speech
								LOGGER(climate_name .. " is enabled")
						else
								LOGGER(climate_name .. " is disabled")
						end
				end

		end
end


function ClimateState:_get_climate_settings()
		--[[
		Get the climate settings for the sandbox options and
		translate it into a dictionary. 
		<ClimateState>:[<climate_name>][<climate_interval>]["value"] = <climate_interval_value>
		<ClimateState>:[<climate_name>][<climate_interval>][<zombie_stat>] = <zombie_stat_value>
		...
		
		If we want the zombies gain one level in speed when it is the light levels are above 0.75
		The dictionary should look something like this. Note that it also stores all other zombie_stats
		even if they are not being used by the climate
		self.sandbox_settings["DayLight"]["DayLightLimit3"]["value"] = 0.75
		self.sandbox_settings["DayLight"]["DayLightLimit3"]["Speed"] = -1
		...
		--]]
		LOGGER("----------------------------------------")
		LOGGER("GETTING CLIMATE STATE SANDBOX SETTINGS")
		LOGGER("----------------------------------------")
		
		for k, climate_name in ipairs(self.active_climate_states) do
				self.sandbox_settings[climate_name] = {}
				for i=0,10 do
						local climate_interval = climate_name .. "_Interval" .. i 
						local sandboxsettingaExists = getSandboxOptions():getOptionByName("DefinitiveZombies." .. climate_interval)
						if sandboxsettingaExists then 
								local climate_interval_value = getSandboxOptions():getOptionByName("DefinitiveZombies." .. climate_interval):getValue()
								LOGGER("Getting Interval: " .. climate_interval .. " | " .. climate_interval_value)
								self.sandbox_settings[climate_name][climate_interval] = {value = climate_interval_value}
								for stat_name, value  in pairs(DZ_ZOMBIE_STATS) do
										local zombie_stat = climate_name .. "_Effect" .. i .. "_" .. stat_name
										local zombie_stat_value = getSandboxOptions():getOptionByName("DefinitiveZombies." .. zombie_stat):getValue()
										LOGGER("Effect: " .. zombie_stat .. " | " .. zombie_stat_value)
										self.sandbox_settings[climate_name][climate_interval][stat_name] = zombie_stat_value
								end
						end
				end
		end
end


function ClimateState:get_current_climates()
		--[[
		Get and store the current climate values
		--]]
		LOGGER("--------------------------")
		LOGGER("CURRENT CLIMATE STATES")
		LOGGER("--------------------------")
		self.current_climate = {DayLight = getClimateManager():getDayLightStrength(),
															Night = getClimateManager():getNightStrength(),
															Temperature = getClimateManager():getTemperature(),
															FogIntensity = getClimateManager():getFogIntensity(),
															RainIntensity = getClimateManager():getRainIntensity(),
															SnowIntensity = getClimateManager():getRainIntensity(),
															CloudIntensity = getClimateManager():getCloudIntensity(),
															WindIntensity = getClimateManager():getWindIntensity(),
															MoonPhase = getClimateMoon():getCurrentMoonPhase(),
															Time = getGameTime():getTimeOfDay()
															}
		for key, value in pairs(self.current_climate) do
		LOGGER(key .. ": " .. value)
		end
end


function ClimateState:getActiveClimateSpeech()
		-- On Start-up,
		-- Determine which climate states are activated in the sandbox
		-- used for calculation
		LOGGER("")
		LOGGER("-----------------------------")
		print("GETTING ACTIVE CLIMATE SPEECH")
		LOGGER("-----------------------------")
		local SpeechEnableExists = getSandboxOptions():getOptionByName("DefinitiveZombies.SpeechEnable"):getValue()
		if not SpeechEnableExists then
				LOGGER("All Speech is disabled")
		    return
		end
		
		for key, ClimateName in ipairs(DZ_CLIMATES) do
				local ClimateEnableExists = getSandboxOptions():getOptionByName("DefinitiveZombies." .. ClimateName .. "Enable"):getValue()
				if ClimateEnableExists then 
						local SpeechWeatherEnableExists = getSandboxOptions():getOptionByName("DefinitiveZombies.Speech" .. ClimateName .. "Enable"):getValue()
						if SpeechWeatherEnableExists then 
								table.insert(self.ActiveClimateSpeech, ClimateName )
								LOGGER(ClimateName .. " Speech is enabled")
						else
								LOGGER(ClimateName .. " Speech is disabled")
						end
				end
		end

end


function ClimateState:updateCurrentClimateInterval(climateName, curLimitIndex, currentclimateinterval, oldclimateinterval)

		--Compare the old climate
		limitName = curLimitIndex
		if curLimitIndex == nil then
				limitName = "0"
		end
		limitName = string.match(limitName, "%d+")

		currentclimateinterval[climateName] = tonumber(limitName)
	
end


function ClimateState:climateIntervalIsDifferent(currentclimateinterval, oldclimateinterval, climateisdifferent, activeclimatespeech)
		--[[for key, value in pairs(currentclimateinterval) do
				print(key .. ":" .. value)
		end
		for key, value in pairs(oldclimateinterval) do
				print(key .. ":" .. value)
		end--]]
		climateisdifferent = false
		for key,climateName in pairs(activeclimatespeech) do
				if oldclimateinterval[climateName] ~= currentclimateinterval[climateName] then
						climateisdifferent = true
				end
		end		
		
		-- Inform the player(s) that the climate has changed
		--if climateisdifferent
		
		
		-- Update the old climate interval with the current climate interval
		for key, climateName in pairs(activeclimatespeech) do
				if currentclimateinterval[climateName] then
						oldclimateinterval[climateName] = currentclimateinterval[climateName]
				end
		end
end


-- Utils
--================================================================================
--[[

--]]

local function DZ_is_zombie_outdated(zombieData)
		-- Check if the current zombie's stats is out of sync with the sandbox settings
		for key, stat_name in ipairs(DZ_ZOMBIE_MANAGER.zombie_active_stats) do
				if stat_name == "Speed" then
						if zombieData.DZspeed ~= (DZ_ZOMBIE_MANAGER.zombie_latest_stats["Speed"]) then
								zombieData.Outdated = true
								return 
						end
				
				elseif stat_name == "Toughness" then
						if zombieData.DZtoughness ~= (DZ_ZOMBIE_MANAGER.zombie_latest_stats["Toughness"]) then
								zombieData.Outdated = true
								return
						end

				elseif stat_name == "Strength" then
						if zombieData.DZstrength ~= (DZ_ZOMBIE_MANAGER.zombie_latest_stats["Strength"]) then
								zombieData.Outdated = true
								return
						end

				elseif stat_name == "Hearing" then
						if zombieData.DZhearing ~= (DZ_ZOMBIE_MANAGER.zombie_latest_stats["Hearing"]) then
								zombieData.Outdated = true
								return
						end

				elseif stat_name == "Sight" then
						if zombieData.DZsight ~= (DZ_ZOMBIE_MANAGER.zombie_latest_stats["Sight"]) then
								zombieData.Outdated = true
								return
						end

				elseif stat_name == "Memory" then
						if zombieData.DZmemory ~= (DZ_ZOMBIE_MANAGER.zombie_latest_stats["Memory"]) then
								zombieData.Outdated = true
								return
						end
						
				elseif stat_name == "Cognition" then
						if zombieData.DZcognition ~= (DZ_ZOMBIE_MANAGER.zombie_latest_stats["Cognition"]) then
								zombieData.Outdated = true
								return
						end
				end
		end
end


local function DZ_set_zombie_metadata(zombieData)
		-- Update the zombie's metadata. This is so that we know
		-- when it becomes outdated.
		for key, stat_name in ipairs(DZ_ZOMBIE_MANAGER.zombie_active_stats) do
				if stat_name == "Speed" then
						zombieData.DZspeed = DZ_ZOMBIE_MANAGER.zombie_latest_stats["Speed"]
						
				elseif stat_name == "Toughness" then
						zombieData.DZtoughness = DZ_ZOMBIE_MANAGER.zombie_latest_stats["Toughness"]

				elseif stat_name == "Strength" then
						zombieData.DZstrength = DZ_ZOMBIE_MANAGER.zombie_latest_stats["Strength"]
						
				elseif stat_name == "Hearing" then
						zombieData.DZhearing = DZ_ZOMBIE_MANAGER.zombie_latest_stats["Hearing"]

				elseif stat_name == "Sight" then
						zombieData.DZsight = DZ_ZOMBIE_MANAGER.zombie_latest_stats["Sight"]

				elseif stat_name == "Memory" then
						zombieData.DZmemory = DZ_ZOMBIE_MANAGER.zombie_latest_stats["Memory"]
						
				elseif stat_name == "Cognition" then
						zombieData.DZcognition = DZ_ZOMBIE_MANAGER.zombie_latest_stats["Cognition"]
				end
		end
end


local function DZ_initialise_zombies(zombie)
		-- Create the meta data for the zombie. Meta data is set to 9999 to force an update.
		local zombieData = zombie:getModData()
		zombieData.DZspeed = 9999
		zombieData.DZtoughness = 9999
		zombieData.DZstrength = 9999
		zombieData.DZhearing = 9999
		zombieData.DZsight = 9999
		zombieData.DZmemory = 9999
		zombieData.DZcognition = 9999
		zombieData.Initialised = true
end


local function DZ_seed_zombies(zombie)
		--[[ 
		Add randomisation to the zombie stats regardless if the stat is active as the check is done on
		DZ_update_zombie(). Adding an additional check just doubles the workload for no benefit
		
		: param zombie (zombie class): The class provided when Events.OnZombieUpdate is used
		--]]
		local zombieData = zombie:getModData()
		zombieData.DZspeedSeed = zombieData.DZspeedSeed or DZ_ZOMBIE_MANAGER:get_seed_effect("Speed")
		zombieData.DZtoughnessSeed = zombieData.DZtoughnessSeed or DZ_ZOMBIE_MANAGER:get_seed_effect("Toughness")
		zombieData.DZstrengthSeed = zombieData.DZstrengthSeed or DZ_ZOMBIE_MANAGER:get_seed_effect("Strength")
		zombieData.DZhearingSeed = zombieData.DZhearingSeed or DZ_ZOMBIE_MANAGER:get_seed_effect("Hearing")
		zombieData.DZsightSeed = zombieData.DZsightSeed or DZ_ZOMBIE_MANAGER:get_seed_effect("Sight")
		zombieData.DZmemorySeed = zombieData.DZmemorySeed or DZ_ZOMBIE_MANAGER:get_seed_effect("Memory")
		zombieData.DZcognitionSeed = zombieData.DZcognitionSeed or DZ_ZOMBIE_MANAGER:get_seed_effect("Cognition")
		zombieData.Seeded = true
end


local function DZ_reset_sandbox()
		--Reset the active zombies stats back to the baseline. 
		for key, stat_name in ipairs(DZ_ZOMBIE_MANAGER.zombie_active_stats) do
				zombie_stat = DZ_ZOMBIE_MANAGER.zombie_baseline[stat_name]
				getSandboxOptions():set("ZombieLore." .. stat_name, zombie_stat)
		end

end


local function DZ_update_zombie(zombie)
		--[[ 
		Update the active zombie stats to the latest climate state
		
		: param zombie (zombie class): The class provided when Events.OnZombieUpdate is used
		--]]
		
		local zombieData = zombie:getModData()
		for key, stat_name in ipairs(DZ_ZOMBIE_MANAGER.zombie_active_stats) do
		
				local latest = DZ_ZOMBIE_MANAGER.zombie_latest_stats[stat_name]
				local seed = 0
				if stat_name == "Speed" then
						seed = zombieData.DZspeedSeed or 0
				elseif stat_name == "Toughness" then
						seed = zombieData.DZtoughnessSeed or 0
				elseif stat_name == "Strength" then
						seed = zombieData.DZstrengthSeed or 0
				elseif stat_name == "Hearing" then
						seed = zombieData.DZhearingSeed or 0
				elseif stat_name == "Sight" then
						seed = zombieData.DZsightSeed or 0
				elseif stat_name == "Memory" then
						seed = zombieData.DZmemorySeed or 0
				elseif stat_name == "Cognition" then
						seed = zombieData.DZcognitionSeed or 0
				end

				local final_stat = latest + seed

				-- Clamp the values
				value = DZ_ZOMBIE_STATS[stat_name]
				if final_stat > value then
						final_stat = value
				elseif final_stat < 1 then
						final_stat = 1
				end
				getSandboxOptions():set("ZombieLore." .. stat_name, final_stat)
		end
		
		-- reset zombie
		zombie:makeInactive(true)
		zombie:makeInactive(false)		
		zombieData.Outdated = false
end


local function DZ_update_zombies(zombie)
		--[[
		Tells the zombie when they should update their stats. As this is an intensive process
		the update processed is staggered with 2 checks. 
		
		The first is a tick rate time check which uses the variable DZ_UPDATE_TICK_RATE.
		Once the zombie has accrued enough ticks, it will run the 2nd check. 
		
		The 2nd check is a random roll which uses the variable DZ_REROLL_MAX. 
		If the roll fails, the next roll is recalculated to increase the chances of succeeding
		until it becomes guranteed on the next roll
		--]]
		local zombieData = zombie:getModData()
		
		-- Initialise the updateinterval and rerollAttempts
		zombieData.Ticks = zombieData.Ticks or DZ_UPDATE_TICK_RATE
		zombieData.ForceUpdate = zombieData.ForceUpdate or 0
		zombieData.ForceInit = zombieData.ForceInit or false
		
		-- Run the update check
		if zombieData.Ticks >= DZ_UPDATE_TICK_RATE then
				if ZombRand(0, zombieData.ForceUpdate) == 0 then
						zombieData.Ticks = 0
						zombieData.ForceUpdate = DZ_REROLL_MAX
						if ((not isClient() and not isServer()) or (isClient() and not zombie:isRemoteZombie())) then
							-- Initialise zombie metadata 
							zombieData.Initialised = zombieData.Initialised or false
							zombieData.Seeded = zombieData.Seeded or false
							zombieData.Outdated = zombieData.Outdated or true
							-- Initialise the zombie
							if not zombieData.Initialised then
									DZ_initialise_zombies(zombie);
							end	
							-- Add randomisation to the zombie
							if not zombieData.Seeded then
									DZ_seed_zombies(zombie);
							end	
							-- Force the zombie to update it's stats. This fixes the issue
							-- where zombies do not update when any of the building spawn fixes are used
							if not zombieData.ForceInit then
									DZ_update_zombie(zombie);
									zombieData.ForceInit = true;
							end	
							
							-- Update the zombie if the stats are out of date
							DZ_is_zombie_outdated(zombieData)
							if zombieData.Outdated then
									DZ_update_zombie(zombie)
									DZ_set_zombie_metadata(zombieData)
									DZ_reset_sandbox()
							end
						end

				else
						zombieData.ForceUpdate = zombieData.ForceUpdate - 1
						zombieData.Ticks = 0;
				end
		else
				zombieData.Ticks = zombieData.Ticks + 1;
		end
end


local function DefinitiveZombies_Speech()
		-- Tell the player the state of the weather
		--[[print("Old Climate")
		print("----------------------------------------")
		for key,value in pairs(DZ_CLIMATE_MANAGER.OldClimateInterval) do
				print(key .. ":" .. value)
		end
		
		print("Current Climate")
		print("----------------------------------------")
		for key,value in pairs(DZ_CLIMATE_MANAGER.CurrentClimateInterval) do
				print(key .. ":" .. value)
		end--]]
		--getPlayer():Say("TEST SPEECH");
end


-- GAME START
--================================================================================
local function DZ_update_managers()
		LOGGER("Definitive Zombies LOG")
		LOGGER("=======================") 

		DZ_CLIMATE_MANAGER:get_current_climates()
		
		DZ_ZOMBIE_MANAGER:update_zombie_climate_modifier()
		DZ_ZOMBIE_MANAGER:update_zombie_latest_stats()
		
		--DefinitiveZombies_Speech()
		LOGGER("=======================")

end


-- GAME START
--================================================================================
local function DefinitiveZombies_OnGameTimeLoaded()
		--Initialise the settings on startup
		DZ_MOONPHASE_DARK = getSandboxOptions():getOptionByName("DefinitiveZombies.MoonPhaseMoonThreshold"):getValue()
    DZ_UPDATE_TICK_RATE = getSandboxOptions():getOptionByName("DefinitiveZombies.UpdateInterval"):getValue()
    DZ_REROLL_MAX = getSandboxOptions():getOptionByName("DefinitiveZombies.RerollAttempts"):getValue()
		DZ_DEBUG = getSandboxOptions():getOptionByName("DefinitiveZombies.DebugEnable"):getValue() 
		
		-- Init the Climate State
		DZ_CLIMATE_MANAGER = ClimateState:new()
		DZ_CLIMATE_MANAGER:_get_active_climate_states()
		--DZ_CLIMATE_MANAGER:getActiveClimateSpeech() -- Disabled for now
		DZ_CLIMATE_MANAGER:_get_climate_settings()
		
		-- Init the Zombie State
		DZ_ZOMBIE_MANAGER = ZombieState:new()
		DZ_ZOMBIE_MANAGER:_get_zombie_active_stats()
		DZ_ZOMBIE_MANAGER:_get_zombie_active_random_stats()
		DZ_ZOMBIE_MANAGER:_update_zombie_random_modifier()
		DZ_ZOMBIE_MANAGER:_get_zombie_baseline()
		
		--DZ_reset_sandbox()
		DZ_update_managers()
		
		--Updates
		Events.EveryTenMinutes.Add(DZ_update_managers);
		Events.OnZombieUpdate.Add(DZ_update_zombies);
end


Events.OnGameTimeLoaded.Add(DefinitiveZombies_OnGameTimeLoaded);