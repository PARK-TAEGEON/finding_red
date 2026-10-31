--!strict
-- Enemy tuning (CONTRACT §1.8, schema §3.6). Pure data: no Roblox globals, no requires. Owner: B.
-- Speeds are Humanoid WalkSpeed (studs/s), distances in studs, times in seconds, colors "#RRGGBB".
-- Wave 1 behaviour exists for Red and White. Bomb/Raptor/Missile are data only (MVP); EnemyService
-- skips spawning kinds it has no behaviour for.
-- v0.5: `Behavior` picks the brain ("Chase" = notice -> "!" -> chase + melee -> leash/return,
-- "Flee" = notice -> "!" -> run away -> tire). Red chases by default (CONTRACT §1.12.1); its old flee
-- tuning stays in `Flee` so a future variant can set Behavior = "Flee".

export type FleeConfig = { Run: number, Rest: number, RestSpeed: number }
export type MeleeConfig = { Damage: number, Interval: number, Range: number }
export type BlastConfig = { Trigger: number, Fuse: number, Radius: number, PlayerDamage: number, EnemyDamage: number }

export type EnemyConfig = {
	Name: string,
	HP: number,
	Radius: number, -- hit radius used by weapon validation (GetRadius)
	Behavior: string?, -- "Chase" | "Flee"; nil = inferred (Flee table -> Flee, Melee + Leash -> Chase)
	Speed: number, -- wander / return speed
	RunSpeed: number, -- chase (or flee) speed
	Sight: number, -- detection distance (needs line of sight)
	Leash: number?, -- chasers give up beyond this distance from home
	Penalty: boolean, -- killing it by a player costs the team ★3
	Flee: FleeConfig?,
	Melee: MeleeConfig?,
	Blast: BlastConfig?,
	Body: string,
	Accent: string,
}

local Enemies: { [string]: EnemyConfig } = {
	Red = {
		Name = "레드",
		Behavior = "Chase",
		HP = 30,
		Radius = 2,
		Speed = 8,
		RunSpeed = 14, -- slower than player walk (16): you can back-pedal and shoot
		Sight = 35,
		Leash = 40,
		Penalty = false,
		Melee = { Damage = 8, Interval = 1.2, Range = 4 },
		Flee = { Run = 4, Rest = 2, RestSpeed = 6 }, -- only used when Behavior = "Flee"
		Body = "#D92B22",
		Accent = "#FFD21F", -- eyes
	},
	White = {
		Name = "화이트",
		Behavior = "Chase",
		HP = 60,
		Radius = 2,
		Speed = 8,
		RunSpeed = 18,
		Sight = 25,
		Leash = 50,
		Penalty = true,
		Melee = { Damage = 10, Interval = 1, Range = 4 },
		Body = "#F2F2F2",
		Accent = "#16181D", -- visor
	},

	-- MVP (data only, no behaviour yet) ------------------------------------------------
	Bomb = {
		Name = "폭탄",
		HP = 10,
		Radius = 2,
		Speed = 6,
		RunSpeed = 14,
		Sight = 20,
		Leash = 40,
		Penalty = false,
		Blast = { Trigger = 5, Fuse = 1.2, Radius = 12, PlayerDamage = 40, EnemyDamage = 100 },
		Body = "#2B2B33",
		Accent = "#FF5A1F",
	},
	Raptor = {
		Name = "랩터",
		HP = 120,
		Radius = 2.5,
		Speed = 10,
		RunSpeed = 22,
		Sight = 35,
		Leash = 70,
		Penalty = true,
		Melee = { Damage = 20, Interval = 1, Range = 5 },
		Body = "#4E9A3A",
		Accent = "#F2E14C",
	},
	Missile = {
		Name = "미사일",
		HP = 1,
		Radius = 1.5,
		Speed = 30,
		RunSpeed = 30,
		Sight = 0,
		Penalty = false,
		Melee = { Damage = 15, Interval = 1, Range = 3 },
		Body = "#8A8F99",
		Accent = "#FF3B30",
	},
}

return Enemies
