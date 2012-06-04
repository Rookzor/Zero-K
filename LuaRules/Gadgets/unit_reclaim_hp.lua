--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

function gadget:GetInfo()
  return {
    name      = "Reclaim HP changer",
    desc      = "Stops units from losing HP when reclaimed",
    author    = "Google Frog",
    date      = "Sep 28, 2009",
    license   = "GNU GPL, v2 or later",
    layer     = 0,
    enabled   = true  --  loaded by default?
  }
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

if (not gadgetHandler:IsSyncedCode()) then
  return false  --  no unsynced code
end

-- Speedups
local spSetUnitHealth = Spring.SetUnitHealth
local spGetUnitHealth = Spring.GetUnitHealth
local spValidUnitID   = Spring.ValidUnitID
local spGetUnitDefID  = Spring.GetUnitDefID

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- This way looks faster, there is a lot less useless iteration

local maxHealth = {}

for i=1,#UnitDefs do
	local ud = UnitDefs[i]
	maxHealth[i] = ud.health
end

 function gadget:AllowUnitBuildStep(builderID, builderTeam, unitID, unitDefID, part)
	if part < 0 then
		local health,_,_,_,build = spGetUnitHealth(unitID)
		spSetUnitHealth(unitID, health - maxHealth[unitDefID]*part)
		if build < 0.01 then
			Spring.DestroyUnit(unitID, false, true)
		end
	end
	return true
 end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- This is the alternate way of doing things. It iterates over all units which 
-- have been the target of a reclaim command and gives them back the health that
-- they lost in being reclaimed.
--[[

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local terraunitDefID = UnitDefNames["terraunit"].id

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local units = {}
local reclaimedUnit = {}
local unitsCount = 0

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

function gadget:GameFrame(n)
	for i=unitsCount, 1,-1 do
		-- Step backwards as a nill index will be filled by the end index
		local health,_,_,_,build = spGetUnitHealth(units[i].id)
			
		if health then -- check if it's a valid unit
			if build < units[i].lastBuild then
				spSetUnitHealth(units[i].id, health + (units[i].lastBuild - build)*units[i].maxHealth)
				units[i].lastBuild = build
			end
		else
			reclaimedUnit[units[i].id] = nil
			units[i] = units[unitsCount]
			units[unitsCount] = nil
			unitsCount = unitsCount - 1
		end
	end
end

function gadget:AllowCommand(unitID, unitDefID, teamID,cmdID, cmdParams, cmdOptions)
	
	if (cmdID == CMD.RECLAIM) and #cmdParams == 1 then
		if not reclaimedUnit[cmdParams[1] ] then
			if spValidUnitID(cmdParams[1]) then
				local ud = spGetUnitDefID(cmdParams[1])
				if ud ~= terraunitDefID then
					-- Add a unit to the reclaimed units list.
					local health,maxHP,_,_,build = spGetUnitHealth(cmdParams[1])
					unitsCount = unitsCount + 1
					units[unitsCount] = {id = cmdParams[1], lastBuild = build, maxHealth = maxHP}
					reclaimedUnit[cmdParams[1] ] = true
				end
			end
		end
	end
	return true -- allowed
end
--]]
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------