include "pieceControl.lua"

local base, turret, spindle, fakespindle = piece('base', 'turret', 'spindle', 'fakespindle')

local guns = {}
for i=1,6 do
	guns[i] = {
		center = piece('center'..i),
		sleeve = piece('sleeve'..i),
		barrel = piece('barrel'..i),
		flare = piece('flare'..i),
		y = 0,
		z = 0,
	}
end

local hpi = math.pi*0.5

local headingSpeed = math.rad(2.5)
local pitchSpeed = math.rad(61) -- Float maths makes this exactly one revolution every 6 seconds.

guns[5].y = 11
guns[5].z = 7

local dis = math.sqrt(guns[5].y^2 + guns[5].z)
local ratio = math.tan(math.rad(60))

guns[6].y = guns[5].y + ratio*guns[5].z
guns[6].z = guns[5].z - ratio*guns[5].y
local dis6 = math.sqrt(guns[6].y^2 + guns[6].z^2)
guns[6].y = guns[6].y*dis/dis6
guns[6].z = guns[6].z*dis/dis6

guns[4].y = guns[5].y - ratio*guns[5].z
guns[4].z = guns[5].z + ratio*guns[5].y
local dis4 = math.sqrt(guns[4].y^2 + guns[4].z^2)
guns[4].y = guns[4].y*dis/dis4
guns[4].z = guns[4].z*dis/dis4

guns[1].y = -guns[4].y
guns[1].z = -guns[4].z

guns[2].y = -guns[5].y
guns[2].z = -guns[5].z

guns[3].y = -guns[6].y
guns[3].z = -guns[6].z

for i=1,6 do
	guns[i].ys = math.abs(guns[i].y)
	guns[i].zs = math.abs(guns[i].z)
end

local smokePiece = {spindle, turret}

include "constants.lua"

local spGetUnitIsStunned = Spring.GetUnitIsStunned
local spGetUnitRulesParam = Spring.GetUnitRulesParam

-- Signal definitions
local SIG_AIM = 2

local minSpinMult = 0.2
local spinScriptAccel = 0.05
local maxSpin = math.pi/3

local maxGainStoreTotal = 0.045
local maxLoseSpinStoreTotal = -0.15
local maxStoreFrames = 150
local defaultTimeFrames = 30
local lastGainStoreTime = 0
local lastLoseStoreTime = 0

local isAiming = false
local spinMult = 0
local gunNum = 1
local reloadChange = 0

local function UpdateSpin(gainSpin, loseSpin)
	local stunned_or_inbuild = spGetUnitIsStunned(unitID)
	reloadChange = (stunned_or_inbuild and 0) or (spGetUnitRulesParam(unitID, "lowpower") == 1 and 0) or (GG.att_ReloadChange[unitID] or 1)
	if gainSpin then
		local gameFrame = Spring.GetGameFrame()
		local timeDiff = gameFrame - lastGainStoreTime
		lastGainStoreTime = gameFrame
		lastLoseStoreTime = 0
		if timeDiff > maxStoreFrames then
			timeDiff = defaultTimeFrames
		end
		spinMult = spinMult + math.sqrt(spinMult) * reloadChange * maxGainStoreTotal * timeDiff / maxStoreFrames
		if spinMult > 1 then
			spinMult = 1
		end
	end
	if loseSpin then
		local gameFrame = Spring.GetGameFrame()
		local timeDiff = gameFrame - lastLoseStoreTime
		lastLoseStoreTime = gameFrame
		lastGainStoreTime = 0
		if timeDiff > maxStoreFrames then
			timeDiff = defaultTimeFrames
		end
		spinMult = spinMult + spinMult * maxLoseSpinStoreTotal * timeDiff / maxStoreFrames
		if spinMult < 0 then
			spinMult = 0
		end
	end
	if spinMult > reloadChange then
		spinMult = spinMult*0.97 - 0.0015
		if spinMult < 0 then
			spinMult = 0
		end
	end
	if reloadChange > 0 and spinMult < minSpinMult then
		spinMult = spinMult + 0.03
		if spinMult > minSpinMult then
			spinMult = minSpinMult
		end
	end
	Spin(spindle, x_axis, spinMult*maxSpin, spinScriptAccel)
	Spring.SetUnitRulesParam(unitID, "speed_bar", spinMult, LOS_ACCESS)
end

local function SpinThread()
	while true do
		UpdateSpin(false, isAiming)
		Sleep(1000)
	end
end

function script.Create()
	StartThread(GG.Script.SmokeUnit, unitID, smokePiece)
	for i = 1, 6 do
		Turn(guns[i].flare, x_axis, (math.rad(-60)* i + 1))
	end
	
	Spin(spindle, x_axis, spinMult*maxSpin, spinScriptAccel)
	StartThread(SpinThread, unitID, smokePiece)
end

function script.HitByWeapon()
	if Spring.GetUnitRulesParam(unitID,"disarmed") == 1 then
		GG.PieceControl.StopTurn (turret, y_axis)
		GG.PieceControl.StopTurn (spindle, x_axis)
	end
end

function script.AimWeapon(num, heading, pitch)
	Signal (SIG_AIM)
	SetSignalMask (SIG_AIM)

	while reloadChange <= 0 do
		Sleep(10)
	end

	local curHead = select (2, Spring.UnitScript.GetPieceRotation(turret))
	local headDiff = heading - curHead
	if math.abs(headDiff) > math.pi then
		headDiff = headDiff - math.abs(headDiff) / headDiff * math.tau
	end
	--Spring.Echo(headDiff*180/math.pi)

	if math.abs(headDiff) > hpi then
		heading = (heading + math.pi) % math.tau
		pitch = -pitch+math.pi
	end

	-- note, DRP can actually fire backwards
	if math.abs(headDiff) > 0.01 and math.abs(headDiff) < math.pi - 0.01 then
		UpdateSpin(false, true)
		isAiming = true
	end
	
	local spindlePitch = -pitch + (num - 1)* math.pi/3

	Turn(turret, y_axis, heading, headingSpeed*reloadChange)
	WaitForTurn(turret, y_axis)
	isAiming = false
	
	local currentSpindle = select(1, Spring.UnitScript.GetPieceRotation(spindle))
	local diff = math.abs(((currentSpindle - spindlePitch - math.pi) % math.tau) - math.pi)
	if diff < math.pi/3 then
		gunNum = num
	end
	return reloadChange > 0 and diff < 0.15*spinMult
end

function script.AimFromWeapon(num)
	return spindle
end

function script.QueryWeapon(num)
	return guns[gunNum].flare
end

local function gunFire(num)
	Move(guns[num].barrel, z_axis, guns[num].z*1.2, 8*guns[num].zs)
	Move(guns[num].barrel, y_axis, guns[num].y*1.2, 8*guns[num].ys)
	WaitForMove(guns[num].barrel, y_axis)
	Move(guns[num].barrel, z_axis, 0, 0.2*guns[num].zs)
	Move(guns[num].barrel, y_axis, 0, 0.2*guns[num].ys)
end

function script.Shot(num)
	--EmitSfx(base, 1024) BASE IS NOT CENTRAL
	EmitSfx(guns[gunNum].flare, 1025)
	EmitSfx(guns[gunNum].flare, 1026)
	StartThread(gunFire, gunNum)
end

function script.FireWeapon(num)
	Sleep(33)
	
	if spinMult < 1 then
		UpdateSpin(true)
	end
end

function script.Killed(recentDamage, maxHealth)
	local severity = recentDamage/maxHealth
	if severity <= .25 then
		Explode(base, SFX.NONE)
		Explode(spindle, SFX.NONE)
		Explode(turret, SFX.NONE)
		return 1
	elseif severity <= .50 then
		Explode(base, SFX.NONE)
		Explode(spindle, SFX.NONE)
		Explode(turret, SFX.NONE)
		return 1
	elseif severity <= .99 then
		Explode(base, SFX.SHATTER)
		Explode(spindle, SFX.SHATTER)
		Explode(turret, SFX.SHATTER)
		return 2
	else
		Explode(base, SFX.SHATTER)
		Explode(spindle, SFX.SHATTER)
		Explode(turret, SFX.SHATTER)
		return 2
	end
end
