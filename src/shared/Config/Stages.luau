--!strict
-- Stage list and metadata (CONTRACT §3.6, §4). Pure data. Owner: orchestrator.
export type StageConfig = {
	Level: number,
	Name: string,
	Map: string,
	ParTime: number,
	Sky: "Day" | "Night",
	Red: { Base: number, Spare: number },
	Reward: { Base: number, PerStamp: number, FirstClear: number },
	Mission: string, -- %d = target
	Hint: string,
}

local Stages: { Order: { string }, [string]: any } = {
	Order = { "1-1", "1-2", "1-3" },

	["1-1"] = {
		Level = 1,
		Name = "첫 사냥",
		Map = "S1_1",
		ParTime = 40,
		Sky = "Day",
		Red = { Base = 1, Spare = 1 },
		Reward = { Base = 20, PerStamp = 10, FirstClear = 30 },
		Mission = "레드 %d마리 잡기",
		Hint = "레이더의 빨간 점을 찾아가세요",
	} :: StageConfig,

	["1-2"] = {
		Level = 1,
		Name = "높은 곳",
		Map = "S1_2",
		ParTime = 60,
		Sky = "Day",
		Red = { Base = 2, Spare = 1 },
		Reward = { Base = 25, PerStamp = 10, FirstClear = 30 },
		Mission = "레드 %d마리 잡기",
		Hint = "높은 곳의 레드는 저격총으로",
	} :: StageConfig,

	["1-3"] = {
		Level = 1,
		Name = "섞여 있다",
		Map = "S1_3",
		ParTime = 75,
		Sky = "Night",
		Red = { Base = 3, Spare = 1 },
		Reward = { Base = 30, PerStamp = 10, FirstClear = 40 },
		Mission = "레드 %d마리 잡기",
		Hint = "화이트는 쏘지 말고 방망이로 밀어내세요",
	} :: StageConfig,
}

return Stages
