--!strict
-- STUB (orchestrator). Owner: C. Replace with the real match loop.
local Types = require(game:GetService("ReplicatedStorage").Shared.Types)
local StageFlow = {}

local state: Types.MatchState = {
	Phase = "Lobby",
	RoundId = 0,
	Target = 0,
	Killed = 0,
	PenaltyKills = 0,
	Party = {},
}

function StageFlow.Init(self: Types.StageFlow, ctx: Types.Context) end
function StageFlow.Start(self: Types.StageFlow) end
function StageFlow.GetState(self: Types.StageFlow): Types.MatchState
	return state
end
function StageFlow.RoundId(self: Types.StageFlow): number
	return state.RoundId
end
function StageFlow.GetParty(self: Types.StageFlow): { Player }
	return {}
end
function StageFlow.IsPlaying(self: Types.StageFlow): boolean
	return false
end
function StageFlow.GetLife(self: Types.StageFlow, player: Player): Types.LifeState
	return "Spectating"
end
function StageFlow.DamagePlayer(self: Types.StageFlow, player: Player, amount: number, sourceKind: string, from: Vector3?) end
function StageFlow.HealPlayer(self: Types.StageFlow, player: Player, amount: number) end
function StageFlow.ReportKill(self: Types.StageFlow, kind: string, byPlayer: Player?, cause: Types.KillCause) end
function StageFlow.GiveTeamKey(self: Types.StageFlow, color: string) end
function StageFlow.HasTeamKey(self: Types.StageFlow, color: string): boolean
	return false
end

return StageFlow
