--!strict
-- Sound key -> "rbxassetid://..." (empty = silent). Pure data. Owner: orchestrator.
-- The reviewer fills these after uploading the generated sound files.
local Audio: { [string]: string } = {
	PistolShot = "",
	SniperShot = "",
	BatSwing = "",
	BatHit = "",
	Reload = "",
	DryFire = "",
	HitMarker = "",
	RedDeath = "",
	PenaltyKill = "",
	Alert = "",
	WhiteAttack = "",
	PlayerHurt = "",
	Downed = "",
	Revived = "",
	Pickup = "",
	Countdown = "",
	StageClear = "",
	StageFail = "",
	Stamp = "",
}
return Audio
