--!strict
-- Contract types. Source of truth for every service/controller signature (CONTRACT.md §3).
-- Owner: orchestrator. Agents: read, never edit. Propose changes in your report.

export type Vec3 = { number } -- {x, y, z} for pure modules
export type Phase = "Lobby" | "Vote" | "Countdown" | "Playing" | "Result"
export type LifeState = "Alive" | "Downed" | "Out" | "Spectating"
export type KillCause = "Bullet" | "Melee" | "Explosion" | "Vehicle" | "Trap" | "Other"

export type StageResult = {
	StageId: string,
	Cleared: boolean,
	Flags: number,
	NewFlags: number,
	Seconds: number,
	Killed: number,
	Target: number,
	PenaltyKills: number,
	Gold: { [string]: number },
}

export type MatchState = {
	Phase: Phase,
	RoundId: number,
	EndsAt: number?,
	StageId: string?,
	Target: number,
	Killed: number,
	PenaltyKills: number,
	StartedAt: number?,
	ParTime: number?,
	Party: { number },
	Ready: { number }?,
	Ballot: { [string]: number }?,
	Options: { string }?,
	Keys: { string }?,
	Result: StageResult?,
}

export type StageRecord = { Flags: number, BestTime: number? }

export type Profile = {
	Version: number,
	Gold: number,
	Owned: { [string]: boolean },
	Stages: { [string]: StageRecord },
	Stats: { RedKills: number, Clears: number, Plays: number },
	Settings: { Sensitivity: number },
	Results: { string },
	Receipts: { string },
}

-- Maps (pure data) ------------------------------------------------------------
export type MapPart = {
	Shape: "Block" | "Wedge" | "Cylinder" | "Ball",
	Size: Vec3,
	Pos: Vec3,
	Rot: Vec3?,
	Color: string,
	Material: string,
	Collide: boolean?,
	Transparency: number?,
	Name: string?,
}
export type MapMarker = {
	Tag: string,
	Pos: Vec3,
	Rot: Vec3?,
	Id: string?,
	Attr: { [string]: string | number | boolean }?,
}
export type MapGimmick = { Type: string, Id: string, Attr: { [string]: string | number | boolean } }
export type MapSpec = {
	Name: string,
	Size: Vec3,
	Parts: { MapPart },
	Markers: { MapMarker },
	Gimmicks: { MapGimmick }?,
}

-- Server services --------------------------------------------------------------
export type DataService = {
	Init: (self: DataService, ctx: Context) -> (),
	Start: (self: DataService) -> (),
	Get: (self: DataService, player: Player) -> Profile?,
	Mutate: (self: DataService, player: Player, fn: (Profile) -> boolean) -> boolean,
	Save: (self: DataService, player: Player, release: boolean) -> boolean,
	ApplyResult: (
		self: DataService,
		player: Player,
		resultId: string,
		stageId: string,
		flags: number,
		seconds: number,
		gold: number,
		redKills: number
	) -> boolean,
	UnlockedStages: (self: DataService, player: Player) -> { string },
}

export type StageFlow = {
	Init: (self: StageFlow, ctx: Context) -> (),
	Start: (self: StageFlow) -> (),
	GetState: (self: StageFlow) -> MatchState,
	RoundId: (self: StageFlow) -> number,
	GetParty: (self: StageFlow) -> { Player },
	IsPlaying: (self: StageFlow) -> boolean,
	GetLife: (self: StageFlow, player: Player) -> LifeState,
	DamagePlayer: (self: StageFlow, player: Player, amount: number, sourceKind: string, from: Vector3?) -> (),
	HealPlayer: (self: StageFlow, player: Player, amount: number) -> (),
	ReportKill: (self: StageFlow, kind: string, byPlayer: Player?, cause: KillCause) -> (),
	GiveTeamKey: (self: StageFlow, color: string) -> (),
	HasTeamKey: (self: StageFlow, color: string) -> boolean,
}

export type StageHandle = {
	StageId: string,
	Model: Model,
	Markers: { [string]: { BasePart } },
}

export type StageService = {
	Init: (self: StageService, ctx: Context) -> (),
	Start: (self: StageService) -> (),
	Load: (self: StageService, stageId: string) -> StageHandle,
	Unload: (self: StageService) -> (),
	Current: (self: StageService) -> StageHandle?,
	LobbySpawn: (self: StageService, index: number) -> CFrame,
	SetBoard: (self: StageService, lines: { string }) -> (),
	SetLobbyBoard: (self: StageService, text: string) -> (),
	GeometryParams: (self: StageService) -> RaycastParams,
}

export type EnemyService = {
	Init: (self: EnemyService, ctx: Context) -> (),
	Start: (self: EnemyService) -> (),
	SpawnStage: (self: EnemyService, handle: StageHandle, redCount: number) -> (),
	ClearAll: (self: EnemyService) -> (),
	Damage: (
		self: EnemyService,
		id: number,
		amount: number,
		byPlayer: Player?,
		cause: KillCause,
		from: Vector3?
	) -> boolean,
	Knockback: (self: EnemyService, id: number, direction: Vector3, stunSeconds: number) -> (),
	IsAlive: (self: EnemyService, id: number) -> boolean,
	GetKind: (self: EnemyService, id: number) -> string?,
	GetRadius: (self: EnemyService, id: number) -> number,
	PositionAt: (self: EnemyService, id: number, serverTime: number) -> Vector3?,
	QueryRadius: (self: EnemyService, center: Vector3, radius: number) -> { number },
}

export type WeaponService = {
	Init: (self: WeaponService, ctx: Context) -> (),
	Start: (self: WeaponService) -> (),
	PrepareStage: (self: WeaponService, handle: StageHandle) -> (),
	ClearStage: (self: WeaponService) -> (),
	GiveLoadout: (self: WeaponService, player: Player) -> (),
	StripLoadout: (self: WeaponService, player: Player) -> (),
	AddAmmoPercent: (self: WeaponService, player: Player, percent: number) -> (),
	Explode: (
		self: WeaponService,
		center: Vector3,
		radius: number,
		enemyDamage: number,
		playerDamage: number,
		byPlayer: Player?
	) -> (),
}

export type Services = {
	Data: DataService,
	Flow: StageFlow,
	Stage: StageService,
	Enemy: EnemyService,
	Weapon: WeaponService,
}

export type Context = { Services: Services, Remotes: Folder }

-- Client controllers ------------------------------------------------------------
export type CameraController = {
	Init: (self: CameraController, ctx: ClientContext) -> (),
	Start: (self: CameraController) -> (),
	SetFirstPerson: (self: CameraController, on: boolean) -> (),
	SetZoom: (self: CameraController, fov: number?) -> (),
	SetSensitivity: (self: CameraController, value: number) -> (),
}
export type WeaponController = {
	Init: (self: WeaponController, ctx: ClientContext) -> (),
	Start: (self: WeaponController) -> (),
	SetEnabled: (self: WeaponController, on: boolean) -> (),
	Attack: (self: WeaponController, down: boolean) -> (),
	Aim: (self: WeaponController, on: boolean) -> (),
	Reload: (self: WeaponController) -> (),
	Cycle: (self: WeaponController) -> (),
}
export type EnemyFX = {
	Init: (self: EnemyFX, ctx: ClientContext) -> (),
	Start: (self: EnemyFX) -> (),
}
export type HUDController = {
	Init: (self: HUDController, ctx: ClientContext) -> (),
	Start: (self: HUDController) -> (),
	Toast: (self: HUDController, text: string) -> (),
}
export type LobbyUI = {
	Init: (self: LobbyUI, ctx: ClientContext) -> (),
	Start: (self: LobbyUI) -> (),
}
export type MobileControls = {
	Init: (self: MobileControls, ctx: ClientContext) -> (),
	Start: (self: MobileControls) -> (),
}

export type ClientControllers = {
	Camera: CameraController,
	Weapon: WeaponController,
	Enemy: EnemyFX,
	HUD: HUDController,
	Lobby: LobbyUI,
	Mobile: MobileControls,
}

export type ClientContext = {
	Remotes: Folder,
	Controllers: ClientControllers,
	State: () -> MatchState,
	SetState: (state: MatchState) -> (),
	PlaySound: (key: string, at: Vector3?) -> (),
}

return {}
