--!strict
-- Weapon tuning (CONTRACT §1.9, §3.6). Pure data. Owner: A.
-- Kind: "Melee" | "Hitscan" | "Throw" | "Projectile". Mag/Reserve nil = infinite (melee).
-- Rate = shots per second. Range in studs. AimFov = right-click field of view. Scope = sniper overlay.
-- Sound = Config/Audio key played on attack.
-- Slice weapons: Bat, Pistol, Sniper. Rifle/Shotgun/Grenade/Rocket are MVP placeholders: their data
-- is here so the HUD/shop can show them, but only Melee/Hitscan are wired in wave 1
-- (Shotgun pellets, Throw and Projectile need the Throw remote / projectile code — later waves).

export type WeaponSpec = {
	Name: string,
	Kind: "Melee" | "Hitscan" | "Throw" | "Projectile",
	Slot: number,
	Damage: number,
	Rate: number,
	Mag: number?,
	Reserve: number?,
	Reload: number?,
	Range: number,
	Spread: number?,
	Pellets: number?,
	Radius: number?,
	Fuse: number?,
	Speed: number?,
	Auto: boolean?,
	AimFov: number?,
	Scope: boolean?,
	Knockback: { Speed: number, Stun: number }?,
	Cone: number?, -- melee: half-angle in degrees (60° cone = 30 each side)
	Price: number?,
	Sound: string,
}

local Weapons: { Order: { string }, Default: { string }, [string]: any } = {
	Order = { "Bat", "Pistol", "Sniper", "Rifle", "Shotgun", "Grenade", "Rocket" },
	Default = { "Bat", "Pistol" },

	Bat = {
		Name = "방망이",
		Kind = "Melee",
		Slot = 1,
		Damage = 35, -- Red; non-target (Penalty) enemies take 0 and are knocked back instead
		Rate = 1.5,
		Range = 7,
		Cone = 30,
		Knockback = { Speed = 45, Stun = 2 },
		Sound = "BatSwing",
	} :: WeaponSpec,

	Pistol = {
		Name = "권총",
		Kind = "Hitscan",
		Slot = 2,
		Damage = 15,
		Rate = 4,
		Mag = 12,
		Reserve = 48,
		Reload = 1.2,
		Range = 300,
		AimFov = 55,
		Sound = "PistolShot",
	} :: WeaponSpec,

	Sniper = {
		Name = "저격총",
		Kind = "Hitscan",
		Slot = 3,
		Damage = 100,
		Rate = 0.8,
		Mag = 5,
		Reserve = 10,
		Reload = 2.2,
		Range = 800,
		AimFov = 20,
		Scope = true,
		Sound = "SniperShot",
	} :: WeaponSpec,

	-- MVP placeholders --------------------------------------------------------------------
	Rifle = {
		Name = "소총",
		Kind = "Hitscan",
		Slot = 3,
		Damage = 12,
		Rate = 10,
		Mag = 30,
		Reserve = 90,
		Reload = 1.8,
		Range = 400,
		Spread = 1.2,
		Auto = true,
		AimFov = 50,
		Price = 500,
		Sound = "PistolShot",
	} :: WeaponSpec,

	Shotgun = {
		Name = "샷건",
		Kind = "Hitscan",
		Slot = 4,
		Damage = 8,
		Rate = 1,
		Mag = 6,
		Reserve = 18,
		Reload = 2.4,
		Range = 60,
		Spread = 6,
		Pellets = 8,
		AimFov = 60,
		Price = 600,
		Sound = "SniperShot",
	} :: WeaponSpec,

	Grenade = {
		Name = "수류탄",
		Kind = "Throw",
		Slot = 4,
		Damage = 120,
		Rate = 1,
		Mag = 1,
		Reserve = 1,
		Reload = 0.5,
		Range = 60,
		Radius = 12,
		Fuse = 2.5,
		Sound = "BatSwing",
	} :: WeaponSpec,

	Rocket = {
		Name = "로켓",
		Kind = "Projectile",
		Slot = 4,
		Damage = 150,
		Rate = 0.5,
		Mag = 1,
		Reserve = 3,
		Reload = 2.5,
		Range = 400,
		Radius = 10,
		Speed = 80,
		Sound = "SniperShot",
	} :: WeaponSpec,
}

return Weapons
