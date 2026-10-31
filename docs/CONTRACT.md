# 파인딩 레드 (FINDING RED) — 개발 계약서 v0.2

> 이 문서가 프로젝트의 단일 기준이다. 모든 에이전트는 작업 전에 전부 읽고, 여기 적힌 이름·형식·수치를 그대로 쓴다.
> 계약을 바꿔야 할 것 같으면 **고치지 말고** 보고서의 "계약 변경 제안"에 적는다. 계약 변경은 오케스트레이터만 한다.

---

## 0. 한 장 요약 (검수자용)

- **정체성**: 2013년 모바일 FPS의 규칙과 감성을 거의 그대로 살린 **추억 + 협동** 게임. 원작의 이름·그림·소리·맵·UI는 쓰지 않고 전부 새로 만든다.
- **목표**: 스테이지마다 정해진 수의 **레드**를 처치하면 클리어. 레드가 아닌 몬스터를 죽이면 최고 평가(★3)를 놓친다.
- **협동**: 서버 1개 = 파티 1개 (1~4명). 인원이 늘면 목표 수도 늘고, 누가 나가면 줄어든다. 쓰러진 동료는 살릴 수 있다.
- **평가(도장)**: ★1 클리어 / ★2 기준 시간 안에 클리어 / ★3 팀 전체가 레드 외 처치 0. 조건별로 따로 저장되고 여러 판에 걸쳐 모을 수 있다.
- **진행**: 로비(준비) → 스테이지 투표 → 카운트다운 → 플레이 → 결과 → 로비.
- **첫 목표 = 수직 슬라이스**: 맵 1개, 무기 2개, 몬스터 2종, 1~4인 협동, 저장. 여기서 손맛과 재미를 확인한 뒤 늘린다.
- **수익화(나중)**: 게임패스(꾸미기·편의), 개발자 상품(골드), 보상형 광고(월 순방문자 2천 명 달성 후, 결과 보상 2배). **도장은 돈으로 못 산다. 유료 뽑기 없음. 동료 부활은 무료.**

### 확정된 결정

| # | 항목 | 결정 |
|---|---|---|
| D1 | 이름 | 파인딩 레드 (FINDING RED) |
| D2 | 레드의 행동 | 사람을 보면 도망간다 (공격 안 함). 계속 뛰지는 못하고 지친다 |
| D3 | 도장 조건 | 위 3가지, 조건별 독립, 누적 수집 |
| D4 | 시간 제한 | 기준 시간의 3배 지나면 실패 |
| D5 | 스테이지 해금 | 파티에 해금한 사람이 한 명이라도 있으면 선택 가능. 클리어하면 참가자 전원 다음 스테이지 해금 |
| D6 | 최대 인원 | 4명 |
| D7 | 게임 방식 | 원작과 거의 같게. 새 요소는 협동 관련만 (부활, 인원별 목표, 팀 도장) + 방망이 넉백 |

---

## 1. 게임 규칙

### 1.1 스테이지 흐름

| 페이즈 | 시간 | 내용 |
|---|---|---|
| `Lobby` | 무제한 | 각자 **준비** 버튼. 접속자 전원 준비 → 즉시 `Vote`. 한 명이라도 준비하고 20초 지나면 `Vote` (준비 안 한 사람은 관전) |
| `Vote` | 10초 | 해금된 스테이지 중 투표. 동점이면 낮은 번호. 무투표면 파티가 해금한 가장 높은 스테이지 |
| `Countdown` | 5초 | 맵 로드, 참가자 전원 `PlayerSpawn`으로 이동, 무기 지급, 칠판에 미션 표시 |
| `Playing` | 최대 `ParTime × 3` | 아래 승패 규칙 |
| `Result` | 8초 | 결과·도장·보상 표시 후 로비로 |

- 플레이 중 들어온 사람은 로비에서 기다리다 다음 판부터 참가.
- 로비에 **친구 초대** 버튼 (`SocialService:PromptGameInvite`).
- 출시 때 Creator Dashboard에서 **비공개 서버를 무료로** 켠다 (모르는 사람 없이 친구끼리 하려는 사람용).

### 1.2 승패

- **클리어**: 팀 레드 처치 수 ≥ 목표 수.
- **실패**: (a) 참가자 전원이 `Downed` 또는 `Out`인 상태가 `AllDownGraceSeconds`(10초) 동안 이어짐, 또는 (b) `ParTime × 3` 초과.
- 목표 수: `Target = Red.Base + Red.PerExtra × (인원 − 1)`.
- **누가 나가면** 남은 인원 기준으로 다시 계산하되 **내려가기만** 한다. 처치 수가 새 목표 이상이면 즉시 클리어.
- 맵에 생성되는 레드 수: 시작 인원 기준 `Target + Red.Spare`. 레드는 리스폰하지 않는다.

### 1.3 도장

- 조건 비트: `Clear = 1`, `Fast = 2` (클리어 시간 ≤ `ParTime`), `Clean = 4` (클리어 + 팀 `PenaltyKills == 0`).
- 실패한 판은 0.
- 저장은 **누적**: `Flags = 이전 Flags | 이번 Flags`. 화면에 보이는 도장 수 = 켜진 비트 수 (0~3). `BestTime`도 따로 저장.
- 그래서 "빨리 깬 판"과 "깨끗하게 깬 판"이 달라도 둘 다 기록되고, 나중에 3개를 모을 수 있다.

### 1.4 처치 판정

- 모든 몬스터 사망은 `StageFlow:ReportKill(kind, byPlayer, cause)` 한 곳으로 모인다.
- `kind == "Red"`면 누가/무엇이 죽였든 팀 카운트 +1 (폭탄에 휘말린 레드도 인정).
- `Enemies[kind].Penalty == true`이고 `byPlayer ~= nil`이면 `PenaltyKills += 1`.
- 플레이어가 쏴서 터진 폭탄의 폭발 피해는 그 플레이어 소유(`byPlayer` = 쏜 사람). 폭탄이 스스로 터지면 `byPlayer = nil`.

### 1.5 체력·쓰러짐·부활

- HP 100, 자동 회복 없음. 플레이어는 **Roblox식으로 죽지 않는다**: 피해는 서버의 `StageFlow:DamagePlayer`로만 들어가고, HP가 0이 되면 `Downed`. 진짜 체력은 플레이어 속성 `HP`이고 Humanoid 체력은 쓰지 않는다 (C가 Humanoid 사망을 막는다).
- `Downed`: 이동 속도 4, 사격 불가. 30초(`BleedOutSeconds`) 안에 못 일어나면 `Out` (그 판 관전).
- 동료 부활: 쓰러진 사람 6스터드 안에서 상호작용 키(E, 모바일 버튼)를 3초 누르기 → HP 50으로 일어남. **무료.**
- 솔로는 쓰러지면 (a)의 10초 유예 후 실패.
- 아군 사격 없음. 플레이어의 폭발은 플레이어에게 피해를 주지 않는다 (몬스터 폭탄은 준다).

### 1.6 보상

- 클리어한 참가자 전원 같은 골드: `Reward.Base + Reward.PerStamp × 이번 판 도장 수`, 그 스테이지 첫 클리어면 `Reward.FirstClear` 추가.
- 실패해도 팀 레드 처치 1마리당 `Reward.PerRedOnFail` (전원 동일).

### 1.7 몬스터 (기본 수치는 `Config/Enemies.luau`)

| Kind | 단계 | HP | 행동 | 공격 | Penalty |
|---|---|---|---|---|---|
| `Red` | 슬라이스 | 30 | 배회(8). 시야 40 안에 플레이어가 보이면 반대 방향으로 도주(13) 4초 → 지쳐서 2초 느려짐(6) → 반복 | 없음 | false (목표) |
| `White` | 슬라이스 | 60 | 배회(8). 25 안에 들어오거나 맞으면 추격(18). 플레이어를 15초 못 잡으면 포기하고 배회 | 근접 10 / 1초, 사거리 4 | true |
| `Bear` | MVP | 200 | 느리게 배회(6). 12 안에 오거나 맞으면 돌진(22) | 근접 25 / 1.5초 | true |
| `Bomb` | MVP | 10 | 20 안에 오면 다가옴(14). 5 안에서 1.2초 뒤 폭발 | 반경 12, 플레이어 40 / 몬스터 100 | false |

- 플레이어 걷기 속도 16. 레드는 플레이어보다 느리지만 시야가 넓어서, 돌아서 접근하거나 몰아서 잡는 게 요령이 된다.
- `White`는 맵 마커에 `HasKey`가 있으면 열쇠를 들고 있고, 죽으면 그 자리에 열쇠를 떨군다 (MVP).

### 1.8 무기 (기본 수치는 `Config/Weapons.luau`)

| Id | 단계 | 종류 | 피해 | 연사(발/초) | 탄창/예비 | 비고 |
|---|---|---|---|---|---|---|
| `Bat` | 슬라이스 | 근접 | 레드 35 / **비목표 0 + 넉백·2초 기절** | 1.5 | ∞ | 사거리 7, 전방 60° 안 가장 가까운 1마리 |
| `Pistol` | 슬라이스 | 히트스캔 | 15 | 4 | 12 / 48 | 재장전 1.2초, 사거리 250 |
| `Rifle` | MVP | 히트스캔 자동 | 12 | 10 | 30 / 120 | 재장전 1.8초 |
| `Sniper` | MVP | 히트스캔 | 100 | 0.8 | 5 / 15 | 우클릭 줌 |
| `Grenade` | MVP | 투척 | 120 | 1 | 3개 | 2.5초 뒤 반경 14 폭발 |
| `Rocket` | MVP | 투사체 | 150 | 0.5 | 1 / 4 | 속도 120, 반경 10 폭발 |

- **방망이 넉백**: 비목표 몬스터를 죽이지 않고 밀쳐내는 수단. 벌점 없이 위기를 넘기게 해 준다 (OX 서바이벌의 넉백을 응용).
- 기본 소지: `Bat`, `Pistol`. 나머지는 상점에서 골드로 영구 구매. 스테이지 시작 때 보유 무기 전부 탄약 가득.
- 맵의 `AmmoPickup`은 들고 있는 무기 예비탄 +50%, `HealthPickup`은 HP +40 (MVP).

### 1.9 열쇠·돌문 (MVP)

- 열쇠는 **팀 공용**: 누가 줍든 팀이 가진다. `KeyDoor`는 같은 색 열쇠를 팀이 가지고 있으면 플레이어가 닿을 때 열린다 (열쇠는 소모되지 않음).

### 1.10 차량 (확장)

- `VehicleSpawn` 마커에 차 1대. 운전석 1 + 사격 가능한 좌석 3. 차로 몬스터를 쳐도 피해 없음.

### 1.11 사운드·타격감 (슬라이스 필수)

- 사격·피격·처치·히트마커·쓰러짐·클리어 소리는 슬라이스에 들어간다. 소리 없는 FPS는 검수할 수 없다.
- 사운드 ID는 `Config/Audio.luau`에 키로 모은다. 빈 문자열이면 코드가 조용히 건너뛴다.
- 오케스트레이터가 기본 효과음을 직접 합성해 파일로 주고, 검수자가 Roblox에 업로드해서 ID를 채운다. 외부 사이트에서 받은 소리는 쓰지 않는다.

---

## 2. 기술 구조

### 2.1 도구와 명령

| 도구 | 용도 |
|---|---|
| Rojo 7.4 | 파일 → `.rbxl` 빌드. **로컬 파일이 단일 기준.** Studio에서 직접 고친 스크립트는 덮어써진다 |
| luau-lsp 1.54 | 타입 검사 (`--!strict`) |
| Lune 0.10 | Studio 밖 순수 로직 테스트 |
| Roblox Studio | 실제 플레이 검증 (검수자, 또는 연결되면 Studio MCP로 실행·로그 수집만) |

- 에이전트 작업 환경에는 Studio가 없다. 그래서 **게임 로직은 가능한 한 순수 함수 모듈로 빼서 Lune으로 테스트**한다 (OX 서바이벌의 `Rules`/`Profile` 방식).
- Studio MCP를 쓰게 되더라도 **실행·검증 용도로만** 쓴다. 스크립트 수정은 항상 파일에서.

### 2.2 완료 조건은 두 단계

1. **자동 검사 통과**: `tools/check.sh` (빌드 + 타입 검사 + 테스트) 오류 0. 에이전트가 확인.
2. **플레이 검증 통과**: 보고서의 검수 체크리스트를 Studio에서 실제로 수행 (솔로 + "클라이언트 2명" 테스트). 검수자가 확인.

에이전트 보고서에는 두 상태를 따로 적는다. 2단계 전까지는 "완료"가 아니라 "검수 대기"다.

### 2.3 폴더 구조와 Roblox 매핑

```
default.project.json
src/
  shared/      → ReplicatedStorage.Shared
    Net.luau          리모트 이름·생성·검증 헬퍼            [오케스트레이터]
    Types.luau        공용 타입·서비스 인터페이스           [오케스트레이터]
    Rules.luau        목표 수·도장·보상 순수 함수           [오케스트레이터]
    Config/
      Game.luau       흐름·체력·보상 수치                   [오케스트레이터]
      Stages.luau     스테이지 목록·메타데이터              [오케스트레이터]
      Audio.luau      사운드 키 → ID                        [오케스트레이터]
      Weapons.luau                                          [A]
      Enemies.luau                                          [B]
    WeaponMath.luau   사격 검증 순수 함수                   [A]
    Models/
      WeaponModels.luau  파트로 조립하는 총 모델            [A]
      EnemyModels.luau   파트로 조립하는 몬스터 모델        [B]
  server/      → ServerScriptService.Server
    Main.server.luau                                        [오케스트레이터]
    Services/
      DataService.luau  Profile.luau  StageFlow.luau        [C]
      WeaponService.luau                                    [A]
      EnemyService.luau  EnemyBrain.luau                    [B]
      StageService.luau  MapBuilder.luau                    [D]
    Maps/  Lobby.luau  S1_1.luau ...                        [D]
  client/      → StarterPlayer.StarterPlayerScripts.Client
    Main.client.luau                                        [오케스트레이터]
    Controllers/
      CameraController.luau  WeaponController.luau          [A]
      EnemyFX.luau                                          [B]
      HUDController.luau  LobbyUI.luau                      [C]
tests/   *.spec.luau  (각자 자기 모듈 테스트)
tools/   check.sh
docs/    CONTRACT.md  reports/<A|B|C|D>.md
```

**파일 소유 규칙**: 대괄호의 소유자만 그 파일을 만들고 고친다. 다른 사람 파일이 필요하면 공개 API만 호출한다. 남의 파일에 버그가 있으면 보고서에 적는다.

### 2.4 서비스 규칙

- 모든 서버 서비스는 `Init(ctx: Types.Context)`와 `Start()`를 가진다. `Main`이 전부 `Init` → 전부 `Start` 순서로 부른다.
- 다른 서비스는 `ctx.Services.X`로만 접근하고, **§3의 공개 API만** 호출한다.
- 클라이언트 컨트롤러도 같은 패턴 (`Init(ctx: Types.ClientContext)`, `Start()`).
- 모든 모듈 첫 줄 `--!strict`. 식별자는 영어, 플레이어에게 보이는 문자열은 한국어.
- **외부 에셋 금지**: Toolbox·InsertService·남의 모델 없음. 모델은 코드로 파트를 조립한다. 소리는 `Config/Audio`의 키로만 재생한다.

### 2.5 보안 규칙

- 클라이언트 → 서버 리모트 핸들러는 **모든 인자의 타입을 검사**하고, NaN·무한대·범위 밖 값은 버린다 (`Net.vector`, `Net.number` 헬퍼).
- 플레이어별 요청 속도 제한 (`Net.throttle`).
- 피해·처치·탄약·골드·도장은 전부 서버가 결정. 클라이언트는 "이렇게 쐈다/맞췄다고 주장한다"만 보낸다.
- **라운드 Id**: 스테이지가 시작될 때마다 `RoundId`가 1씩 오른다. 플레이 관련 요청(`Fire` `Throw` `Interact`)은 `R`(라운드 Id)을 담고, 서버는 현재 라운드와 다르면 버린다. 몬스터 Id도 서버 전체에서 다시 쓰지 않는다.
- **처치 중복 방지**: `EnemyService:Damage`는 이미 죽은 몬스터에 대해 항상 `false`를 반환하고, `ReportKill`은 몬스터 하나당 정확히 한 번만 불린다.

### 2.6 몬스터 구현 방식

- 몬스터는 **서버가 소유한 실제 모델**이다. `workspace.Enemies` 폴더 아래, `PrimaryPart` 이름은 `Root`, 속성 `EnemyId: number`, `Kind: string`, `HasKey: boolean`.
- 이동은 서버가 담당하고 (`Root:SetNetworkOwner(nil)`), 길찾기는 PathfindingService를 쓰되 서버 전체 초당 8회 이하로 제한한다. Humanoid를 쓸지 여부는 B가 정한다.
- `EnemyService`는 몬스터마다 `Root` 위치를 10Hz로 0.5초분 기록한다 (사격 검증용 `PositionAt`).
- 죽으면 즉시 `IsAlive = false`, 넉백 연출 후 3초 안에 제거.
- 성능 목표: 몬스터 30마리 + 플레이어 4명에서 서버 프레임 안정. 부족하면 나중에 B 파일 안에서만 최적화한다 (공개 API는 유지).

### 2.7 사격 판정 방식

1. 클라이언트가 레이캐스트로 몬스터 모델을 맞히면 그 모델의 `EnemyId`와 맞은 지점을 `Fire`로 보낸다. 발사 시각 `T`는 `workspace:GetServerTimeNow()`. 근접 무기(`Bat`)는 `Id`/`P` 없이 보내고 서버가 대상을 고른다.
2. 서버(`WeaponService`)가 `WeaponMath`로 검증한다:
   - 라운드 Id 일치, 무기 보유, 연사 간격(10% 여유), 탄창 > 0, 플레이어 상태 `Alive`
   - 발사 원점이 플레이어 머리에서 8스터드 이내, **머리 → 원점 사이를 지오메트리가 막지 않음**, 방향 벡터 길이 ≈ 1
   - 주장한 지점이 사거리 이내, 방향과 지점 사이 각도 < 3°
   - 몬스터의 **과거 위치**(발사 시각, 최대 0.4초 전까지)가 지점에서 `반지름 + 2.5` 이내
   - 원점 → 지점 사이를 맵 지오메트리가 막지 않음
3. 통과하면 `EnemyService:Damage`. 탄약은 맞든 안 맞든 차감.
4. 다른 클라이언트에는 `Effect`로 총알 궤적을 그리게 한다.

### 2.8 데이터 저장

- OX 서바이벌의 `DataService` 구조를 이식한다: 세션 리스(`UpdateAsync`), 자동 저장, `BindToClose`, 로드 실패 시 킥.
- **결과 지급 이력**(`Results`, 최근 20개)과 **결제 영수증 이력**(`Receipts`, 최근 100개)은 분리한다. 하나가 많이 쌓여도 다른 쪽이 밀려나지 않게.
- Studio 테스트: 기본은 메모리 저장(`StudioUseDataStore = false`). **재접속 유지 검증은 별도 테스트 플레이스**를 게시해서 "Studio의 API 서비스 접근"을 켜고, `StudioUseDataStore = true` + `StudioDataStoreName`(운영 저장소와 다른 이름)으로 한다.

---

## 3. 인터페이스 (코드 계약)

아래 타입은 `src/shared/Types.luau`에 그대로 들어간다. 타입 검사기가 계약 위반을 잡아준다.

### 3.1 공용 타입

```lua
export type Phase = "Lobby" | "Vote" | "Countdown" | "Playing" | "Result"
export type LifeState = "Alive" | "Downed" | "Out" | "Spectating"

export type MatchState = {
    Phase: Phase,
    RoundId: number,          -- 스테이지 시작마다 +1
    EndsAt: number?,          -- workspace:GetServerTimeNow() 기준
    StageId: string?,         -- "1-1"
    Target: number,
    Killed: number,           -- 팀 레드 처치
    PenaltyKills: number,
    StartedAt: number?,
    ParTime: number?,
    Party: { number },        -- 참가자 UserId
    Ready: { number }?,       -- Lobby 중 준비한 UserId
    Ballot: { [string]: number }?,   -- Vote 중 스테이지별 표 수
    Options: { string }?,            -- Vote 중 선택지
    Result: StageResult?,
}

export type StageResult = {
    StageId: string, Cleared: boolean, Flags: number,   -- 이번 판 도장 비트
    Seconds: number, Killed: number, Target: number, PenaltyKills: number,
    Gold: { [string]: number },      -- tostring(UserId) → 받은 골드 (리모트용 문자열 키)
}

export type StageRecord = { Flags: number, BestTime: number? }

export type Profile = {
    Version: number, Gold: number,
    Owned: { [string]: boolean },             -- 무기 Id → 보유
    Stages: { [string]: StageRecord },        -- 스테이지 Id → 누적 기록. Flags & 1 이면 클리어
    Stats: { RedKills: number, Clears: number, Plays: number },
    Results: { string },                      -- 지급한 결과 Id, 최근 20개
    Receipts: { string },                     -- 처리한 영수증 Id, 최근 100개
}

export type KillCause = "Bullet" | "Melee" | "Explosion" | "Other"
```

### 3.2 리모트 (`Net.luau`)

`Main.server`가 `ReplicatedStorage.Remotes` 폴더에 생성한다. 이름은 아래 그대로.

| 이름 | 방향 | 인자 |
|---|---|---|
| `State` | S→C 전체 | `MatchState` |
| `Ready` | C→S | `on: boolean` |
| `Vote` | C→S | `stageId: string` |
| `Fire` | C→S | `{ R: number, W: string, O: Vector3, D: Vector3, T: number, Id: number?, P: Vector3? }` |
| `Reload` | C→S | `weaponId: string` |
| `Throw` | C→S | `{ R: number, W: string, O: Vector3, D: Vector3, Power: number }` |
| `Equip` | C→S | `weaponId: string` |
| `Interact` | C→S | `{ R: number, Kind: "ReviveStart" \| "ReviveStop", Target: number }` |
| `Effect` | S→C 전체 | `kind: string, data: { [string]: any }` |
| `Feedback` | S→C 개인 | `{ Kind: string, Text: string?, [string]: any }` |
| `Request` | C→S | `kind: string, arg: any` (상점 등, MVP 이후) |

`Effect` 종류: `Shot {From, To, W, UserId}`, `Melee {UserId, Target: number?}`, `Knockback {Id}`, `EnemyDeath {Id, Pos, From}`, `Explosion {Pos, Radius}`, `Projectile {Id, From, Dir, Speed}`.
`Feedback` 종류: `Hit {Killed: boolean, Penalty: boolean}` (쏜 사람에게만), `Message {Text}`, `Hurt {Amount}`.

### 3.3 플레이어 속성 (서버가 설정, HUD가 읽음)

| 속성 | 타입 | 설명 |
|---|---|---|
| `Life` | string | `LifeState` |
| `HP` | number | 0~100 |
| `Equipped` | string | 무기 Id |
| `Mag_<Id>` / `Ammo_<Id>` | number | 탄창 / 예비탄 |
| `Gold` | number | |
| `StageFlags` | string | JSON `{ ["1-1"]=7, ... }` |
| `DataReady` | boolean | 저장 데이터 로드 완료 |
| `ReviveProgress` | number | 0~1, 부활 받는 중 |

### 3.4 서버 서비스 API

```lua
export type DataService = {
    Init: (self: DataService, ctx: Context) -> (), Start: (self: DataService) -> (),
    Get: (self: DataService, player: Player) -> Profile?,
    Mutate: (self: DataService, player: Player, fn: (Profile) -> boolean) -> boolean,
    Save: (self: DataService, player: Player, release: boolean) -> boolean,
    ApplyResult: (self: DataService, player: Player, resultId: string, stageId: string,
        flags: number, seconds: number, gold: number, redKills: number) -> boolean,
    UnlockedStages: (self: DataService, player: Player) -> { string },
}

export type StageFlow = {
    Init: (self: StageFlow, ctx: Context) -> (), Start: (self: StageFlow) -> (),
    GetState: (self: StageFlow) -> MatchState,
    RoundId: (self: StageFlow) -> number,
    GetParty: (self: StageFlow) -> { Player },           -- 이번 판 참가자 (나간 사람 제외)
    IsPlaying: (self: StageFlow) -> boolean,
    GetLife: (self: StageFlow, player: Player) -> LifeState,
    DamagePlayer: (self: StageFlow, player: Player, amount: number, sourceKind: string) -> (),
    HealPlayer: (self: StageFlow, player: Player, amount: number) -> (),
    ReportKill: (self: StageFlow, kind: string, byPlayer: Player?, cause: KillCause) -> (),
    GiveTeamKey: (self: StageFlow, color: string) -> (),
    HasTeamKey: (self: StageFlow, color: string) -> boolean,
}

export type StageHandle = {
    StageId: string,
    Model: Model,                                        -- workspace.Stage
    Markers: { [string]: { BasePart } },                 -- 태그 → 마커 파트들
}

export type StageService = {
    Init: (self: StageService, ctx: Context) -> (), Start: (self: StageService) -> (),
    Load: (self: StageService, stageId: string) -> StageHandle,
    Unload: (self: StageService) -> (),
    Current: (self: StageService) -> StageHandle?,
    LobbySpawn: (self: StageService, index: number) -> CFrame,
    SetBoard: (self: StageService, text: string) -> (),      -- 현재 스테이지 칠판 문구
    SetLobbyBoard: (self: StageService, text: string) -> (), -- 로비 안내판
    GeometryParams: (self: StageService) -> RaycastParams,   -- 맵 지오메트리만 포함
}

export type EnemyService = {
    Init: (self: EnemyService, ctx: Context) -> (), Start: (self: EnemyService) -> (),
    SpawnStage: (self: EnemyService, handle: StageHandle, redCount: number) -> (),
    ClearAll: (self: EnemyService) -> (),
    Damage: (self: EnemyService, id: number, amount: number, byPlayer: Player?,
        cause: KillCause, from: Vector3?) -> boolean,      -- true = 이번에 죽음
    Knockback: (self: EnemyService, id: number, direction: Vector3, stunSeconds: number) -> (),
    IsAlive: (self: EnemyService, id: number) -> boolean,
    GetKind: (self: EnemyService, id: number) -> string?,
    GetRadius: (self: EnemyService, id: number) -> number,
    PositionAt: (self: EnemyService, id: number, serverTime: number) -> Vector3?,
    QueryRadius: (self: EnemyService, center: Vector3, radius: number) -> { number },
}

export type WeaponService = {
    Init: (self: WeaponService, ctx: Context) -> (), Start: (self: WeaponService) -> (),
    GiveLoadout: (self: WeaponService, player: Player) -> (),     -- 보유 무기 전부, 탄약 가득
    StripLoadout: (self: WeaponService, player: Player) -> (),
    AddAmmoPercent: (self: WeaponService, player: Player, percent: number) -> (),
    Explode: (self: WeaponService, center: Vector3, radius: number, enemyDamage: number,
        playerDamage: number, byPlayer: Player?) -> (),
}

export type Services = {
    Data: DataService, Flow: StageFlow, Stage: StageService,
    Enemy: EnemyService, Weapon: WeaponService,
}

export type Context = { Services: Services, Remotes: Folder }
```

**호출 방향** (이 외의 호출은 금지):

```
StageFlow ──→ Stage:Load/Unload/LobbySpawn/SetBoard/SetLobbyBoard, Enemy:SpawnStage/ClearAll,
              Weapon:GiveLoadout/StripLoadout, Data:*
EnemyService ──→ Flow:ReportKill/DamagePlayer/GetParty/GetLife, Stage:GeometryParams,
                 Weapon:Explode (Bomb)
WeaponService ──→ Enemy:Damage/Knockback/PositionAt/GetRadius/GetKind/IsAlive/QueryRadius,
                  Flow:RoundId/GetLife/DamagePlayer, Stage:GeometryParams, Data:Get
```

### 3.5 클라이언트 API

```lua
export type ClientContext = {
    Remotes: Folder,
    Controllers: {
        Camera: { SetFirstPerson: (self: any, on: boolean) -> (), SetZoom: (self: any, fov: number?) -> () },
        Weapon: { SetEnabled: (self: any, on: boolean) -> () },
        HUD: { Toast: (self: any, text: string) -> () },
    },
    State: () -> MatchState,                              -- 최신 State 리모트 값
    PlaySound: (key: string, at: Vector3?) -> (),         -- Config/Audio 키, 빈 ID면 무시
}
```

- `HUDController`가 `State` 리모트를 받아 `ctx.State`를 갱신하고, 페이즈와 `Life`에 따라 `Camera:SetFirstPerson`, `Weapon:SetEnabled`를 부른다 (로비·관전은 3인칭, 무기 끔).

### 3.6 Config 스키마

```lua
-- Config/Game.luau
{
    MaxPlayers = 4, ReadyTimeoutSeconds = 20, VoteSeconds = 10, CountdownSeconds = 5, ResultSeconds = 8,
    TimeLimitMultiplier = 3, MaxHP = 100, ReviveHP = 50, BleedOutSeconds = 30,
    AllDownGraceSeconds = 10, ReviveHoldSeconds = 3, ReviveRange = 6, DownedWalkSpeed = 4,
    WalkSpeed = 16, StageOrigin = Vector3.new(2000, 0, 0),
    Reward = { PerRedOnFail = 2 },
    DataStoreName = "FindingRed_Profiles_v1", StudioDataStoreName = "FindingRed_STUDIO_v1",
    AutoSaveSeconds = 60, SessionLeaseSeconds = 180,
    StudioUseDataStore = false, StudioStartGold = 2000,
}

-- Config/Stages.luau
{
    Order = { "1-1", ... },
    ["1-1"] = { Name = "첫 사냥", Map = "S1_1", ParTime = 90,
        Red = { Base = 6, PerExtra = 3, Spare = 2 },
        Reward = { Base = 30, PerStamp = 10, FirstClear = 50 },
        Board = "레드 %d마리 잡기" },     -- %d = Target
}

-- Config/Audio.luau
{ PistolShot = "", BatSwing = "", BatHit = "", Reload = "", DryFire = "", HitMarker = "",
  RedDeath = "", PenaltyKill = "", WhiteAlert = "", WhiteAttack = "", PlayerHurt = "",
  Downed = "", Revived = "", Countdown = "", StageClear = "", StageFail = "", Stamp = "" }

-- Config/Weapons.luau        [A]
{ Order = { "Bat", "Pistol", ... }, Default = { "Bat", "Pistol" },
  [Id] = { Name: string, Kind: "Melee"|"Hitscan"|"Throw"|"Projectile", Damage: number,
           Rate: number, Mag: number?, Reserve: number?, Reload: number?, Range: number,
           Spread: number?, Radius: number?, Fuse: number?, Speed: number?,
           Auto: boolean?, Zoom: number?, Knockback: { Speed: number, Stun: number }?,
           Price: number, Sound: string } }

-- Config/Enemies.luau        [B]
{ [Kind] = { Name: string, HP: number, Radius: number, Speed: number, RunSpeed: number,
             Sight: number, Penalty: boolean,
             Flee: { Run: number, Rest: number, RestSpeed: number }?,
             GiveUpSeconds: number?,
             Melee: { Damage: number, Interval: number, Range: number }?,
             Blast: { Trigger: number, Fuse: number, Radius: number, PlayerDamage: number, EnemyDamage: number }?,
             Color: Color3 } }
```

### 3.7 맵 계약 (`MapBuilder`)

맵 모듈은 데이터만 반환한다:

```lua
export type MapSpec = {
    Parts: { { Shape: "Block"|"Wedge"|"Cylinder"|"Ball", Size: Vector3, Pos: Vector3,
               Rot: Vector3?, Color: Color3, Material: Enum.Material?, Collide: boolean? } },
    Markers: { { Tag: string, Pos: Vector3, Rot: Vector3?, Attr: { [string]: any }? } },
}
```

- 좌표는 맵 기준. `MapBuilder`가 `Config.Game.StageOrigin`만큼 옮겨 `workspace.Stage`에 짓는다. 로비는 원점 근처 `workspace.Lobby`.
- 마커는 투명·충돌 없는 1×1×1 파트, `CollectionService` 태그 + 속성. `StageService`는 **태그로만** 마커를 찾는다 (손으로 지은 맵도 같은 태그면 동작).

| 태그 | 속성 | 필수 |
|---|---|---|
| `PlayerSpawn` | — | 4개 이상 |
| `EnemySpawn` | `Kind: string`, `Count: number`(Red 제외), `Radius: number`, `HasKey: boolean?`, `KeyColor: string?` | Red 마커는 `Count` 대신 `Weight` |
| `Board` | — | 시작 지점 칠판 1개 (미션 문구) |
| `KeyDoor` / `KeyPickup` | `Color: string` | MVP |
| `AmmoPickup` / `HealthPickup` | — | MVP |
| `VehicleSpawn` | `Kind: string` | 확장 |

- 레드 배분: `EnemyService`가 `Target + Spare`마리를 Red 마커들의 `Weight` 비율로 나눠 `Radius` 안에 무작위 배치.

---

## 4. 1차 웨이브 = 수직 슬라이스

**범위**: 로비 + 스테이지 `1-1` 하나, 무기 `Bat` `Pistol`, 몬스터 `Red` `White`, 1~4인 협동, 쓰러짐·부활, 도장, 저장, 효과음.

| 에이전트 | 파일 | 플레이 검증 체크리스트 (검수자가 Studio에서 확인) |
|---|---|---|
| **A 무기** | `Config/Weapons`, `WeaponMath`, `WeaponModels`, `WeaponService`, `CameraController`, `WeaponController` | 1인칭 고정, 화면에 권총·방망이, 1/2키·모바일 버튼 전환, 좌클릭 사격, R 재장전, 탄약 숫자 변화, 히트마커와 소리, 방망이로 화이트가 밀려나고 기절 |
| **B 몬스터** | `Config/Enemies`, `EnemyBrain`, `EnemyModels`, `EnemyService`, `EnemyFX` | 레드가 돌아다니다 다가가면 도망가고 지치면 느려짐, 화이트가 쫓아와 때리고 15초 뒤 포기, 30마리에서도 서버가 안 끊김, 죽으면 날아가는 연출 |
| **C 흐름·데이터** | `Profile`, `DataService`(OX 이식), `StageFlow`, `HUDController`, `LobbyUI` | 준비→투표→카운트다운→플레이→결과 순환, "레드 3/8" 카운터, 쓰러짐·동료 부활(2인 테스트), 한 명 나가면 목표 감소, 도장 표시, 테스트 플레이스에서 재접속 시 도장·골드 유지, 초대 버튼 |
| **D 맵** | `MapBuilder`, `StageService`, `Maps/Lobby`, `Maps/S1_1` | 로비와 스테이지가 지어짐, 칠판 문구, 4명 스폰 정상, 끼임·추락 없음, 레드가 숨을 수 있는 구조물이 있음 |

**모든 에이전트 공통**

1. 이 문서 전체와 `src/shared/Types.luau`를 먼저 읽는다.
2. 자기 소유 파일만 만든다/고친다. 순수 로직은 따로 모듈로 빼서 `tests/<이름>.spec.luau`에 Lune 테스트를 쓴다.
3. 다른 서비스는 아직 스텁일 수 있다. 스텁이 반환하는 값에 기대지 말고 계약된 API만 호출한다.
4. `tools/check.sh` 오류 0을 확인한다.
5. `docs/reports/<A|B|C|D>.md`에 보고서: 만든 파일, 공개 API 구현 여부, 테스트 결과, **자동 검사 상태 / 플레이 검증 상태(검수 대기)**, 검수 체크리스트(Studio에서 눌러볼 순서), 알려진 한계, 계약 변경 제안.

---

## 5. 이후 단계

| 단계 | 내용 |
|---|---|
| 첫 협동 테스트 | 슬라이스를 친구 2~4명과 플레이. 수치 조정 |
| 공개 MVP | 맵 3개, `Bear` `Bomb`, `Rifle` `Sniper` `Grenade` `Rocket`, 열쇠·돌문, 픽업, 상점, 모바일 다듬기 |
| 콘텐츠 확장 | 스테이지 12개, 차량, 게임패스, 일일 퀘스트(OX 이식), 월 순방문자 2천 명 달성 후 보상형 광고 |

---

## 6. 변경 이력

- **v0.2 (2026-10-31)**
  - 이름 파인딩 레드, 목표 몬스터 `Red`. 원작 방식 유지 + 협동 (식별·미끼 같은 변형 요소는 넣지 않음).
  - 외부 리뷰 반영: 도장 조건별 비트 저장 + 누적, 레드 도주 속도 13 + 지침, 광고 부활 제거(동료 부활 무료), 머리→원점 장애물 검사, `RoundId`, 결과/영수증 이력 분리, Studio 테스트 저장소 분리, 몬스터를 서버 모델로 단순화, 준비·초대·비공개 서버, 이탈 시 목표 감소, 사운드 슬라이스 필수, 완료 조건 2단계, 1차를 맵 1개 수직 슬라이스로 축소.
  - 반영하지 않음: 위험한 적의 처치 벌점 제거 (장르의 핵심 긴장이라 유지하고, 대신 방망이 넉백으로 벌점 없이 버틸 수단 추가).
- v0.1 (2026-10-31) 초안.
