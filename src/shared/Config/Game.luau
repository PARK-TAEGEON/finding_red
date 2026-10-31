--!strict
-- Flow, health and reward tuning (CONTRACT §3.6). Pure data. Owner: orchestrator.
return {
	MaxPlayers = 4,
	ReadyTimeoutSeconds = 20,
	VoteSeconds = 10,
	CountdownSeconds = 5, -- unused since v0.5 (start room replaces countdown)
	StartRoomSeconds = 20, -- v0.5: door auto-opens after this
	DoorInteractRange = 5,
	LoadingSeconds = 1.5,
	ResultSeconds = 8,
	TimeLimitMultiplier = 3,
	CoopScale = 0.5,

	MaxHP = 100,
	ReviveHP = 50,
	BleedOutSeconds = 30,
	AllDownGraceSeconds = 10,
	ReviveHoldSeconds = 3,
	ReviveRange = 6,
	DownedWalkSpeed = 4,
	WalkSpeed = 16,
	SprintSpeed = 24,

	StageOrigin = { 2000, 0, 0 },
	Reward = { PerRedOnFail = 2 },

	DataStoreName = "FindingRed_Profiles_v1",
	StudioDataStoreName = "FindingRed_STUDIO_v1",
	AutoSaveSeconds = 60,
	SessionLeaseSeconds = 180,
	StudioUseDataStore = false,
	StudioStartGold = 2000,
}
