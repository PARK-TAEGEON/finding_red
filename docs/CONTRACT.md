# 파인딩 레드 (FINDING RED) — 개발 계약서 v0.3

> 이 문서가 프로젝트의 단일 기준이다. 모든 에이전트는 작업 전에 전부 읽고, 여기 적힌 이름·형식·수치를 그대로 쓴다.
> 계약을 바꿔야 할 것 같으면 **고치지 말고** 보고서의 "계약 변경 제안"에 적는다. 계약 변경은 오케스트레이터만 한다.
> 참고 자료: `docs/reference/ORIGINAL_NOTES.md` (원작 플레이 영상 관찰 기록). 느낌·문법만 참고하고 배치·그림은 베끼지 않는다.

---

## 0. 한 장 요약 (검수자용)

- **정체성**: 2013년 모바일 FPS의 규칙과 감성을 거의 그대로 살린 **추억 + 협동** 게임. 원작의 이름·그림·소리·맵·UI는 쓰지 않고 전부 새로 만든다.
- **목표**: 스테이지마다 정해진 수의 **레드**를 처치하면 클리어. 레드가 아닌 몬스터를 죽이면 최고 평가(★3)를 놓친다.
- **템포**: 원작처럼 **작은 경기장에서 30초~2분짜리 판을 빠르게 넘긴다.** 목표 수는 1마리부터 시작해서 점점 늘어난다.
- **무기**: 기본은 방망이 + 권총. 나머지는 **맵에 놓인 무기를 주워서** 그 판에서 쓴다 (플레이어마다 각자 1회).
- **협동**: 서버 1개 = 파티 1개 (1~4명). 인원이 늘면 목표 수가 늘고, 누가 나가면 줄어든다. 쓰러진 동료는 무료로 살린다.
- **평가(도장)**: ★1 클리어 / ★2 기준 시간 안에 클리어 / ★3 팀 전체가 레드 외 처치 0. 조건별로 따로 저장되고 여러 판에 걸쳐 모은다.
- **그래픽**: Roblox 기본 파트·재질과 R6 체형 몬스터로 원작의 단순한 느낌을 낸다. 외부 에셋은 총기 모델 정도만.
- **첫 목표 = 수직 슬라이스**: 레벨 1의 스테이지 1-1~1-3, 1~4인 협동, 저장, 효과음.

### 확정된 결정

| # | 항목 | 결정 |
|---|---|---|
| D1 | 이름 | 파인딩 레드 (FINDING RED) |
| D2 | 레드의 행동 | 자기 구역 안에서 배회. 사람을 발견하면 "!" 후 구역 안에서 도망. 공격 안 함 |
| D3 | 도장 조건 | 위 3가지, 조건별 독립, 누적 수집 |
| D4 | 시간 제한 | 기준 시간의 3배 지나면 실패 |
| D5 | 스테이지 해금 | 파티에 해금한 사람이 한 명이라도 있으면 선택 가능. 클리어하면 참가자 전원 다음 스테이지 해금 |
| D6 | 최대 인원 | 4명 |
| D7 | 게임 방식 | 원작과 거의 같게. 새 요소는 협동 관련만 (부활, 인원별 목표, 팀 도장) + 방망이 넉백 |

---

## 1. 게임 규칙

### 1.1 진행 흐름

| 페이즈 | 시간 | 내용 |
|---|---|---|
| `Lobby` | 무제한 | 각자 **준비** 버튼. 접속자 전원 준비 → 즉시 `Vote`. 한 명이라도 준비하고 20초 지나면 `Vote` (준비 안 한 사람은 관전) |
| `Vote` | 10초 | 해금된 스테이지 중 투표. 동점이면 낮은 번호. 무투표면 파티가 해금한 가장 높은 스테이지 |
| `Countdown` | 5초 | 맵 로드, 참가자 전원 `PlayerSpawn`으로 이동, 무기 지급, 칠판에 미션·힌트 표시 |
| `Playing` | 최대 `ParTime × 3` | 아래 승패 규칙 |
| `Result` | 8초 | "미션 성공!!" + 도장 연출 + 보상. 다음 판은 **같은 파티가 바로 다음 스테이지로 갈지 투표** (`Next` / `Retry` / `Lobby`), 기본값 `Next` |

- 원작처럼 판과 판 사이가 짧아야 한다. 결과 → 다음 스테이지 카운트다운까지 15초 이내.
- 플레이 중 들어온 사람은 로비에서 기다리다 다음 판부터 참가.
- 로비에 **친구 초대** 버튼 (`SocialService:PromptGameInvite`). 출시 때 Creator Dashboard에서 **비공개 서버를 무료로** 켠다.

### 1.2 승패와 목표 수

- **클리어**: 팀 레드 처치 수 ≥ 목표 수.
- **실패**: (a) 참가자 전원이 `Downed` 또는 `Out`인 상태가 `AllDownGraceSeconds`(10초) 이어짐, 또는 (b) `ParTime × 3` 초과.
- **목표 수**: `Target = ceil(Red.Base × (1 + CoopScale × (인원 − 1)))`, `CoopScale = 0.5`. 예) Base 1 → 1인 1, 2인 2, 4인 3마리 / Base 5 → 4인 13마리.
- **누가 나가면** 남은 인원 기준으로 다시 계산하되 **내려가기만** 한다. 처치 수가 새 목표 이상이면 즉시 클리어.
- 맵에 생성되는 레드 수: 시작 인원 기준 `Target + Red.Spare`. 레드는 리스폰하지 않는다.

### 1.3 도장

- 조건 비트: `Clear = 1`, `Fast = 2` (클리어 시간 ≤ `ParTime`), `Clean = 4` (클리어 + 팀 `PenaltyKills == 0`).
- 실패한 판은 0. 저장은 **누적**: `Flags = 이전 Flags | 이번 Flags`. 화면의 도장 수 = 켜진 비트 수. `BestTime`도 저장.

### 1.4 처치 판정

- 모든 몬스터 사망은 `StageFlow:ReportKill(kind, byPlayer, cause)` 한 곳으로 모인다.
- `kind == "Red"`면 누가/무엇이 죽였든 팀 카운트 +1 (폭탄·함정·차량에 당한 레드도 인정).
- `Enemies[kind].Penalty == true`이고 `byPlayer ~= nil`이면 `PenaltyKills += 1`. **차량으로 친 것도 운전자 소유.**
- 플레이어가 쏴서 터진 폭탄의 폭발은 그 플레이어 소유. 폭탄이 스스로 터지거나 함정에 죽으면 `byPlayer = nil`.

### 1.5 체력·쓰러짐·부활

- HP 100, 자동 회복 없음. 플레이어는 **Roblox식으로 죽지 않는다**: 피해는 서버의 `StageFlow:DamagePlayer`로만 들어가고, HP 0이면 `Downed`. 진짜 체력은 속성 `HP`, Humanoid 체력은 쓰지 않는다 (C가 Humanoid 사망을 막는다).
- 맞으면 화면 가장자리가 잠깐 빨개진다 (원작 피격 연출).
- `Downed`: 이동 속도 4, 사격 불가. 30초 안에 못 일어나면 `Out` (그 판 관전).
- 동료 부활: 쓰러진 사람 6스터드 안에서 상호작용(E / 모바일 버튼) 3초 → HP 50. **무료.**
- 솔로는 쓰러지면 (a)의 10초 유예 후 실패. 아군 사격 없음. 플레이어의 폭발은 플레이어에게 피해 없음.

### 1.6 이동·조작 (원작 버튼 구성 유지)

- 걷기 16, **달리기 24** (Shift / 모바일 `달리기` 버튼 토글), 점프 (원작처럼 상자·낮은 벽 위로 올라갈 수 있는 높이).
- PC: WASD + 마우스, 좌클릭 공격, 우클릭 조준, 1~4 무기, Q 무기 순환, R 재장전, E 상호작용, Esc 일시정지.
- 모바일: 왼쪽 이동 스틱, 오른쪽 화면 드래그 시점, 버튼 `공격` `조준` `점프` `달리기` `무기변경` (+ 부활 가능할 때 `부활`).
- 일시정지 메뉴: 계속하기 / 회전 감도 / 로비로.

### 1.7 보상

- 클리어한 참가자 전원 같은 골드: `Reward.Base + Reward.PerStamp × 이번 판 도장 수`, 첫 클리어면 `Reward.FirstClear` 추가.
- 실패해도 팀 레드 처치 1마리당 `Reward.PerRedOnFail` (전원 동일). 골드는 상점(MVP 이후)에서 쓴다.

### 1.8 몬스터 (기본 수치는 `Config/Enemies.luau`)

공통:
- **R6 체형**(머리·몸통·팔다리 6파트)을 코드로 조립. Roblox 기본 R6 걷기·대기 애니메이션 사용.
- 각 몬스터는 **집(스폰 마커)과 구역 반지름**을 가진다. 배회·도주는 구역 안에서만 한다. 추격은 `Leash` 거리까지만 하고 돌아간다.
- 플레이어를 발견하면 머리 위에 **"!"** 0.5초 → 행동 전환. 머리 위에 작은 **체력바**.
- 죽으면 맞은 방향으로 날아가며 쓰러진다 (OX 서바이벌의 넉백 연출 응용).

| Kind | 단계 | HP | 행동 | 공격 | Penalty |
|---|---|---|---|---|---|
| `Red` | 슬라이스 | 30 | 구역 배회(8). 시야 40에서 발견 → "!" → 구역 안에서 반대쪽으로 도주(13) 4초 → 지쳐서 2초 느림(6) → 반복 | 없음 | false (목표) |
| `White` | 슬라이스 | 60 | 구역 배회(8). 25 안에 오거나 맞으면 "!" → 추격(18), `Leash` 50 넘으면 포기하고 귀환 | 근접 10 / 1초, 사거리 4 | true |
| `Bomb` | MVP | 10 | 20 안에 오면 다가옴(14). 5 안에서 1.2초 뒤 폭발 | 반경 12, 플레이어 40 / 몬스터 100 | false |
| `Raptor` | MVP | 120 | 빠른 추격(22), 레드를 태울 수 있음 (`Rider`) | 근접 20 / 1초 | true |
| `Missile` | MVP | 1 | 정해진 경로를 날아다니는 함정형. 닿으면 피해 | 접촉 15 | false |

- 레드 모습: 빨간 몸, 노란 눈, 이빨. 화이트: 흰 몸, 검은 바이저. 실루엣만 봐도 구분돼야 한다.

### 1.9 무기 (기본 수치는 `Config/Weapons.luau`)

| Id | 단계 | 종류 | 피해 | 연사(발/초) | 탄창/예비 | 획득 |
|---|---|---|---|---|---|---|
| `Bat` | 슬라이스 | 근접 | 레드 35 / **비목표 0 + 넉백·2초 기절** | 1.5 | ∞ | 기본 |
| `Pistol` | 슬라이스 | 히트스캔 | 15 | 4 | 12 / 48 | 기본 |
| `Sniper` | 슬라이스 | 히트스캔 | 100 | 0.8 | 5 / 10 | 픽업 |
| `Rifle` | MVP | 히트스캔 자동 | 12 | 10 | 30 / 90 | 픽업·상점 |
| `Shotgun` | MVP | 히트스캔 8발 | 8×8 | 1 | 6 / 18 | 픽업·상점 |
| `Grenade` | MVP | 투척 | 120 | 1 | 2개 | 픽업 |
| `Rocket` | MVP | 투사체 | 150 | 0.5 | 1 / 3 | 픽업 |

- **픽업**: 맵의 `WeaponPickup` 마커 위에 무기 모델이 떠서 돈다. 4스터드 안으로 걸어가면 자동 획득. **플레이어마다 각자 1회** (내가 주우면 내 화면에서만 사라짐). 그 판이 끝나면 사라진다 (상점에서 산 무기는 영구).
- **조준**: 우클릭/`조준` 버튼 = 시야 좁히기 (권총 FOV 55, 저격총 스코프 FOV 20 + 화면 가림).
- **방망이 넉백**: 비목표를 죽이지 않고 밀쳐내는 수단 (벌점 없음).
- 무기 슬롯: 1 방망이, 2 권총, 3~4 픽업 무기.

### 1.10 기믹 (MVP부터, 스키마는 §3.7)

`KeyDoor`/`KeyPickup` (팀 공용 열쇠, HUD에 열쇠 아이콘), `ShootSwitch` (총으로 쏘면 연결된 문이 열림), `PressurePlate` (밟으면 연결 대상 작동), `Crusher` (천장 가시가 주기적으로 내려옴), `MissileLane` (미사일이 주기적으로 지나감), `Pen` (울타리 안에 화이트를 가둬 둠), `Vehicle` (자동차·헬기 — 몬스터를 밀어 처치, 레드는 인정·화이트는 벌점).

### 1.11 사운드·타격감 (슬라이스 필수)

- 사격·피격·처치·히트마커·"!" 발견·쓰러짐·클리어 소리는 슬라이스에 포함.
- 사운드 ID는 `Config/Audio.luau`에 키로 모은다. 빈 문자열이면 코드가 조용히 건너뛴다.
- 오케스트레이터가 기본 효과음을 합성해 주고, 검수자가 Roblox에 업로드해 ID를 채운다.

---

## 2. 기술 구조

### 2.1 도구

| 도구 | 용도 |
|---|---|
| Rojo 7.4 | 파일 → `.rbxl` 빌드. **로컬 파일이 단일 기준.** Studio에서 고친 스크립트는 덮어써진다 |
| luau-lsp 1.54 | 타입 검사. 계약 위반(§3 타입과 다른 함수)은 여기서 잡힌다 |
| Lune 0.10 | Studio 밖 순수 로직 테스트, 맵 데이터 덤프 |
| Python 3 | 맵 미리보기 이미지 렌더러 (`tools/map_preview.py`) |
| Roblox Studio | 실제 플레이 검증 (검수자) |

- 에이전트 환경에는 Studio가 없다. **게임 로직은 순수 함수 모듈로 빼서 Lune으로 테스트**한다.
- `tools/check.sh` = Rojo 빌드 + 타입 검사(`src/`) + Lune 테스트(`tests/`) + 맵 검사. 출력 마지막 줄이 `CHECK PASS`여야 한다.

### 2.2 완료 조건은 두 단계

1. **자동 검사 통과**: `tools/check.sh` → `CHECK PASS`. 에이전트가 확인.
2. **플레이 검증 통과**: 보고서의 검수 체크리스트를 Studio에서 실제로 수행 (솔로 + "클라이언트 2명" 테스트). 검수자가 확인.

에이전트 보고서에는 두 상태를 따로 적는다. 2단계 전까지는 "검수 대기"다.

### 2.3 폴더 구조와 Roblox 매핑

```
default.project.json
src/
  shared/      → ReplicatedStorage.Shared
    Types.luau  Net.luau  Rules.luau                        [오케스트레이터]
    Config/  Game.luau  Stages.luau  Audio.luau             [오케스트레이터]
             Weapons.luau                                    [A]
             Enemies.luau                                    [B]
    WeaponMath.luau                                          [A]
    EnemyLogic.luau                                          [B]  (순수 상태머신·구역 계산)
    Models/  WeaponModels.luau                               [A]
             EnemyModels.luau                                [B]
    Assets.luau                                              [오케스트레이터] (레지스트리)
  server/      → ServerScriptService.Server
    Main.server.luau                                         [오케스트레이터]
    Services/ DataService.luau  Profile.luau  StageFlow.luau [C]
              WeaponService.luau                             [A]
              EnemyService.luau                              [B]
              StageService.luau  MapBuilder.luau             [D]
    Maps/     Kit.luau  Lobby.luau  S1_1.luau  S1_2.luau  S1_3.luau   [D]
  client/      → StarterPlayer.StarterPlayerScripts.Client
    Main.client.luau                                         [오케스트레이터]
    Controllers/ CameraController.luau  WeaponController.luau  [A]
                 EnemyFX.luau                                  [B]
                 HUDController.luau  LobbyUI.luau  MobileControls.luau  [C]
assets/        → ReplicatedStorage.Assets (검수자가 넣는 .rbxm)
tests/   <name>.spec.luau  (각자 자기 모듈 테스트)
tools/   check.sh  run_tests.luau  dump_maps.luau  map_preview.py   [오케스트레이터 + D]
docs/    CONTRACT.md  reports/<A|B|C|D>.md  reference/
```

**파일 소유 규칙**: 대괄호의 소유자만 그 파일을 만들고 고친다. 새 파일이 필요하면 **자기 영역 폴더 안에** 만들고 보고서에 적는다. 남의 파일에 버그가 있으면 보고서에 적는다.

### 2.4 코딩 규칙

- 모든 모듈 첫 줄 `--!strict`. 식별자는 영어, 플레이어에게 보이는 문자열은 한국어.
- 서버 서비스는 아래 형태로 쓴다. 메서드는 `.`으로 정의하고 첫 인자 `self`에 계약 타입을 붙인다. `Main`이 `local X: Types.XService = require(...)`로 받으므로 **계약과 다르면 타입 검사가 실패한다.**

```lua
--!strict
local Types = require(game:GetService("ReplicatedStorage").Shared.Types)
local EnemyService = {}
local ctx: Types.Context
function EnemyService.Init(self: Types.EnemyService, c: Types.Context) ctx = c end
function EnemyService.Start(self: Types.EnemyService) end
-- ...
return EnemyService
```

- `Main`이 모든 서비스 `Init` → 모든 서비스 `Start` 순서로 부른다. 다른 서비스는 `ctx.Services.X`로만, **§3의 공개 API만** 호출한다. 클라이언트 컨트롤러도 같은 패턴.
- **순수 모듈**(`Rules`, `WeaponMath`, `EnemyLogic`, `Profile`, `Config/*`, `Maps/*`)은 Roblox 전역(`game`, `Vector3`, `Color3`, `Enum`, `workspace`)을 쓰지 않고, 다른 모듈을 `require`하지도 않는다. 벡터는 `{x, y, z}` 숫자 배열, 색은 `"#RRGGBB"`, 재질은 `"Brick"` 같은 `Enum.Material` 이름 문자열. 그래야 Lune에서 그대로 테스트된다. 필요한 값은 인자로 받는다.
- 맵 모듈은 `return function(K) ... end` 형태로 키트를 주입받는다 (§3.7).
- **외부 에셋**: Toolbox·InsertService·남의 모델 금지. 모델은 `Assets.get(key)`로 요청하고, 없으면 코드로 조립한 대체 모델을 쓴다 (§3.8). 소리는 `Config/Audio` 키로만 재생한다.

### 2.5 보안 규칙

- 클라이언트 → 서버 리모트 핸들러는 **모든 인자의 타입을 검사**하고 NaN·무한대·범위 밖 값은 버린다 (`Net.isVector`, `Net.isNumber`, `Net.isString`).
- 플레이어별 요청 속도 제한 (`Net.throttle`).
- 피해·처치·탄약·골드·도장·픽업은 전부 서버가 결정. 클라이언트는 "이렇게 쐈다/맞췄다고 주장한다"만 보낸다.
- **라운드 Id**: 스테이지 시작마다 `RoundId` +1. `Fire` `Throw` `Interact`는 `R`을 담고, 서버는 현재 라운드와 다르면 버린다. 몬스터 Id는 서버 전체에서 재사용하지 않는다.
- **처치 중복 방지**: `EnemyService:Damage`는 죽은 몬스터에 항상 `false`, `ReportKill`은 몬스터당 정확히 한 번.

### 2.6 몬스터 구현

- 서버가 소유한 실제 모델. `workspace.Enemies` 아래, `PrimaryPart` 이름 `HumanoidRootPart`, Humanoid 포함(R6), 속성 `EnemyId: number`, `Kind: string`, `HasKey: boolean`, `State: string`(`Idle`/`Alert`/`Flee`/`Tired`/`Chase`/`Return`/`Stunned`/`Dead`).
- 이동은 서버(`Humanoid:MoveTo`, 네트워크 소유 서버). 구역이 작으므로 길찾기는 직선 + 막히면 PathfindingService (서버 전체 초당 8회 이하).
- 행동 결정은 순수 모듈 `EnemyLogic`(테스트 대상)이 하고, `EnemyService`는 그 결과를 실행만 한다.
- 위치를 10Hz로 0.5초분 기록 (사격 검증용 `PositionAt`).
- 죽으면 즉시 `IsAlive = false`, 날아가는 연출 후 3초 안에 제거.
- 성능 목표: 몬스터 30마리 + 플레이어 4명에서 서버 안정.

### 2.7 사격 판정

1. 클라이언트가 레이캐스트로 몬스터 모델을 맞히면 그 `EnemyId`와 맞은 지점을 `Fire`로 보낸다. `T = workspace:GetServerTimeNow()`. 근접(`Bat`)은 `Id`/`P` 없이 보내고 서버가 대상을 고른다.
2. 서버(`WeaponService`)가 `WeaponMath`로 검증: 라운드 Id, 무기 보유, 연사 간격(10% 여유), 탄창 > 0, 상태 `Alive` / 원점이 머리에서 8스터드 이내 + 머리→원점 장애물 없음 + 방향 길이 ≈ 1 / 지점이 사거리 이내, 방향과 지점 각도 < 3° / 몬스터의 과거 위치(발사 시각, 최대 0.4초 전)가 지점에서 `반지름 + 2.5` 이내 / 원점→지점 장애물 없음.
3. 통과하면 `EnemyService:Damage`. 탄약은 맞든 안 맞든 차감.
4. 다른 클라이언트에는 `Effect`로 총알 궤적.

### 2.8 데이터 저장

- OX 서바이벌의 `DataService` 구조 이식: 세션 리스(`UpdateAsync`), 자동 저장, `BindToClose`, 로드 실패 시 킥.
- 결과 지급 이력(`Results`, 최근 20개)과 영수증 이력(`Receipts`, 최근 100개)은 분리.
- Studio 기본은 메모리 저장. 재접속 검증은 별도 테스트 플레이스에서 API 접근을 켜고 `StudioUseDataStore = true` + `StudioDataStoreName`으로.

---

## 3. 인터페이스 (코드 계약)

`src/shared/Types.luau`에 그대로 들어 있다. 이 절과 그 파일이 다르면 **파일이 기준**이고 오케스트레이터에게 보고한다.

### 3.1 공용 타입

```lua
export type Vec3 = { number }                 -- {x, y, z} (순수 모듈용)
export type Phase = "Lobby" | "Vote" | "Countdown" | "Playing" | "Result"
export type LifeState = "Alive" | "Downed" | "Out" | "Spectating"
export type KillCause = "Bullet" | "Melee" | "Explosion" | "Vehicle" | "Trap" | "Other"

export type MatchState = {
    Phase: Phase,
    RoundId: number,
    EndsAt: number?,                 -- workspace:GetServerTimeNow() 기준
    StageId: string?,
    Target: number,
    Killed: number,                  -- 팀 레드 처치
    PenaltyKills: number,
    StartedAt: number?,
    ParTime: number?,
    Party: { number },               -- 참가자 UserId
    Ready: { number }?,              -- Lobby: 준비한 UserId
    Ballot: { [string]: number }?,   -- Vote: 선택지별 표 수
    Options: { string }?,            -- Vote: 선택지 (스테이지 Id 또는 "Next"/"Retry"/"Lobby")
    Keys: { string }?,               -- 팀이 가진 열쇠 색
    Result: StageResult?,
}

export type StageResult = {
    StageId: string, Cleared: boolean, Flags: number, NewFlags: number,
    Seconds: number, Killed: number, Target: number, PenaltyKills: number,
    Gold: { [string]: number },      -- tostring(UserId) → 골드
}

export type StageRecord = { Flags: number, BestTime: number? }

export type Profile = {
    Version: number, Gold: number,
    Owned: { [string]: boolean },
    Stages: { [string]: StageRecord },
    Stats: { RedKills: number, Clears: number, Plays: number },
    Settings: { Sensitivity: number },
    Results: { string },
    Receipts: { string },
}
```

### 3.2 리모트 (`Net.luau`가 생성·조회)

| 이름 | 방향 | 인자 |
|---|---|---|
| `State` | S→C 전체 | `MatchState` |
| `Ready` | C→S | `on: boolean` |
| `Vote` | C→S | `option: string` |
| `Fire` | C→S | `{ R: number, W: string, O: Vector3, D: Vector3, T: number, Id: number?, P: Vector3? }` |
| `Reload` | C→S | `weaponId: string` |
| `Throw` | C→S | `{ R: number, W: string, O: Vector3, D: Vector3, Power: number }` |
| `Equip` | C→S | `weaponId: string` |
| `Interact` | C→S | `{ R: number, Kind: "ReviveStart" \| "ReviveStop", Target: number }` |
| `Setting` | C→S | `key: string, value: any` (`"Sensitivity"`, 0.2~3) |
| `Effect` | S→C 전체 | `kind: string, data: { [string]: any }` |
| `Feedback` | S→C 개인 | `{ Kind: string, Text: string?, [string]: any }` |
| `Request` | C→S | `kind: string, arg: any` (상점 등, MVP 이후) |

`Effect`: `Shot {From, To, W, UserId}`, `Melee {UserId, Target: number?}`, `Knockback {Id}`, `EnemyDeath {Id, Pos, From}`, `Explosion {Pos, Radius}`, `Projectile {Id, From, Dir, Speed}`, `Pickup {UserId, Marker: string}`.
`Feedback`: `Hit {Killed: boolean, Penalty: boolean}`, `Message {Text}`, `Hurt {Amount, From: Vector3?}`, `PickedUp {Weapon, Marker}`.

### 3.3 플레이어 속성

| 속성 | 타입 | 설명 |
|---|---|---|
| `Life` | string | `LifeState` |
| `HP` | number | 0~100 |
| `Equipped` | string | 무기 Id |
| `Weapons` | string | 지금 쓸 수 있는 무기 Id를 쉼표로 (`"Bat,Pistol,Sniper"`) |
| `Mag_<Id>` / `Ammo_<Id>` | number | 탄창 / 예비탄 |
| `Gold` | number | |
| `StageFlags` | string | JSON `{ ["1-1"]=7, ... }` |
| `Sensitivity` | number | 회전 감도 |
| `DataReady` | boolean | 데이터 로드 완료 |
| `ReviveProgress` | number | 0~1 |

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
    Model: Model,                               -- workspace.Stage
    Markers: { [string]: { BasePart } },        -- 태그 → 마커 파트들
}

export type StageService = {
    Init: (self: StageService, ctx: Context) -> (), Start: (self: StageService) -> (),
    Load: (self: StageService, stageId: string) -> StageHandle,
    Unload: (self: StageService) -> (),
    Current: (self: StageService) -> StageHandle?,
    LobbySpawn: (self: StageService, index: number) -> CFrame,
    SetBoard: (self: StageService, lines: { string }) -> (),   -- 칠판: {"LEVEL 1-1", "레드 1마리 잡기", "힌트: ..."}
    SetLobbyBoard: (self: StageService, text: string) -> (),
    GeometryParams: (self: StageService) -> RaycastParams,     -- 맵 지오메트리만
}

export type EnemyService = {
    Init: (self: EnemyService, ctx: Context) -> (), Start: (self: EnemyService) -> (),
    SpawnStage: (self: EnemyService, handle: StageHandle, redCount: number) -> (),
    ClearAll: (self: EnemyService) -> (),
    Damage: (self: EnemyService, id: number, amount: number, byPlayer: Player?,
        cause: KillCause, from: Vector3?) -> boolean,
    Knockback: (self: EnemyService, id: number, direction: Vector3, stunSeconds: number) -> (),
    IsAlive: (self: EnemyService, id: number) -> boolean,
    GetKind: (self: EnemyService, id: number) -> string?,
    GetRadius: (self: EnemyService, id: number) -> number,
    PositionAt: (self: EnemyService, id: number, serverTime: number) -> Vector3?,
    QueryRadius: (self: EnemyService, center: Vector3, radius: number) -> { number },
}

export type WeaponService = {
    Init: (self: WeaponService, ctx: Context) -> (), Start: (self: WeaponService) -> (),
    PrepareStage: (self: WeaponService, handle: StageHandle) -> (),   -- 픽업 생성
    ClearStage: (self: WeaponService) -> (),
    GiveLoadout: (self: WeaponService, player: Player) -> (),         -- 보유 무기 전부, 탄약 가득
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
StageFlow ──→ Stage:Load/Unload/Current/LobbySpawn/SetBoard/SetLobbyBoard,
              Enemy:SpawnStage/ClearAll, Weapon:PrepareStage/ClearStage/GiveLoadout/StripLoadout, Data:*
EnemyService ──→ Flow:ReportKill/DamagePlayer/GetParty/GetLife/IsPlaying, Stage:GeometryParams,
                 Weapon:Explode (Bomb)
WeaponService ──→ Enemy:Damage/Knockback/PositionAt/GetRadius/GetKind/IsAlive/QueryRadius,
                  Flow:RoundId/GetLife/GetParty/DamagePlayer, Stage:GeometryParams/Current, Data:Get
```

### 3.5 클라이언트 API

```lua
export type ClientContext = {
    Remotes: Folder,
    Controllers: ClientControllers,
    State: () -> MatchState,
    SetState: (state: MatchState) -> (),           -- HUDController만 호출
    PlaySound: (key: string, at: Vector3?) -> (),  -- Config/Audio 키, 빈 ID면 무시
}

export type ClientControllers = {
    Camera: CameraController, Weapon: WeaponController, Enemy: EnemyFX,
    HUD: HUDController, Lobby: LobbyUI, Mobile: MobileControls,
}

export type CameraController = {
    Init: (self: CameraController, ctx: ClientContext) -> (), Start: (self: CameraController) -> (),
    SetFirstPerson: (self: CameraController, on: boolean) -> (),
    SetZoom: (self: CameraController, fov: number?) -> (),          -- nil = 기본
    SetSensitivity: (self: CameraController, value: number) -> (),
}
export type WeaponController = {
    Init: (self: WeaponController, ctx: ClientContext) -> (), Start: (self: WeaponController) -> (),
    SetEnabled: (self: WeaponController, on: boolean) -> (),
    Attack: (self: WeaponController, down: boolean) -> (),          -- 모바일 버튼용
    Aim: (self: WeaponController, on: boolean) -> (),
    Reload: (self: WeaponController) -> (),
    Cycle: (self: WeaponController) -> (),
}
export type EnemyFX = {
    Init: (self: EnemyFX, ctx: ClientContext) -> (), Start: (self: EnemyFX) -> (),
}
export type HUDController = {
    Init: (self: HUDController, ctx: ClientContext) -> (), Start: (self: HUDController) -> (),
    Toast: (self: HUDController, text: string) -> (),
}
export type LobbyUI = {
    Init: (self: LobbyUI, ctx: ClientContext) -> (), Start: (self: LobbyUI) -> (),
}
export type MobileControls = {
    Init: (self: MobileControls, ctx: ClientContext) -> (), Start: (self: MobileControls) -> (),
}
```

- `HUDController`가 `State` 리모트를 받아 `ctx.SetState`로 갱신하고, 페이즈·`Life`에 따라 `Camera:SetFirstPerson`, `Weapon:SetEnabled`를 부른다 (로비·관전 3인칭, 무기 끔).
- `MobileControls`(C)가 터치 버튼을 그리고 `Weapon:Attack/Aim/Cycle`, 달리기, 점프, 부활을 호출한다. PC 입력은 각 컨트롤러가 직접 받는다 (공격·조준·재장전·무기 = A, 달리기·상호작용·일시정지 = C).
- HUD 배치 (원작 문법): 위 가운데 골드 + 목표 카운터, 오른쪽 위 **레이더**(반경 120, 레드=빨간 점, 다른 몬스터=흰 점, 동료=초록 점), 왼쪽 위 체력바 + 열쇠 아이콘, 가운데 조준점, 오른쪽 아래 무기·탄약.

### 3.6 Config 스키마 (순수 데이터)

```lua
-- Config/Game.luau
{
    MaxPlayers = 4, ReadyTimeoutSeconds = 20, VoteSeconds = 10, CountdownSeconds = 5, ResultSeconds = 8,
    TimeLimitMultiplier = 3, CoopScale = 0.5,
    MaxHP = 100, ReviveHP = 50, BleedOutSeconds = 30, AllDownGraceSeconds = 10,
    ReviveHoldSeconds = 3, ReviveRange = 6, DownedWalkSpeed = 4, WalkSpeed = 16, SprintSpeed = 24,
    StageOrigin = { 2000, 0, 0 },
    Reward = { PerRedOnFail = 2 },
    DataStoreName = "FindingRed_Profiles_v1", StudioDataStoreName = "FindingRed_STUDIO_v1",
    AutoSaveSeconds = 60, SessionLeaseSeconds = 180, StudioUseDataStore = false, StudioStartGold = 2000,
}

-- Config/Stages.luau
{
    Order = { "1-1", "1-2", "1-3" },
    ["1-1"] = { Level = 1, Name = "첫 사냥", Map = "S1_1", ParTime = 40, Sky = "Day",
        Red = { Base = 1, Spare = 1 }, Reward = { Base = 20, PerStamp = 10, FirstClear = 30 },
        Mission = "레드 %d마리 잡기", Hint = "레이더의 빨간 점을 찾아가세요" },
}

-- Config/Audio.luau
{ PistolShot = "", SniperShot = "", BatSwing = "", BatHit = "", Reload = "", DryFire = "", HitMarker = "",
  RedDeath = "", PenaltyKill = "", Alert = "", WhiteAttack = "", PlayerHurt = "", Downed = "", Revived = "",
  Pickup = "", Countdown = "", StageClear = "", StageFail = "", Stamp = "" }

-- Config/Weapons.luau        [A]
{ Order = { "Bat", "Pistol", "Sniper", ... }, Default = { "Bat", "Pistol" },
  [Id] = { Name: string, Kind: "Melee"|"Hitscan"|"Throw"|"Projectile", Slot: number, Damage: number,
           Rate: number, Mag: number?, Reserve: number?, Reload: number?, Range: number,
           Spread: number?, Pellets: number?, Radius: number?, Fuse: number?, Speed: number?,
           Auto: boolean?, AimFov: number?, Scope: boolean?, Knockback: { Speed: number, Stun: number }?,
           Price: number?, Sound: string } }

-- Config/Enemies.luau        [B]
{ [Kind] = { Name: string, HP: number, Radius: number, Speed: number, RunSpeed: number,
             Sight: number, Leash: number?, Penalty: boolean,
             Flee: { Run: number, Rest: number, RestSpeed: number }?,
             Melee: { Damage: number, Interval: number, Range: number }?,
             Blast: { Trigger: number, Fuse: number, Radius: number, PlayerDamage: number, EnemyDamage: number }?,
             Body: string, Accent: string } }          -- "#RRGGBB"
```

### 3.7 맵 계약

맵 모듈은 **키트를 주입받아 순수 데이터만** 반환한다:

```lua
export type MapPart = {
    Shape: "Block" | "Wedge" | "Cylinder" | "Ball",
    Size: Vec3, Pos: Vec3, Rot: Vec3?,          -- Rot = 도(degree) {x, y, z}
    Color: string, Material: string,            -- "#RRGGBB", Enum.Material 이름
    Collide: boolean?, Transparency: number?, Name: string?,
}
export type MapMarker = { Tag: string, Pos: Vec3, Rot: Vec3?, Id: string?, Attr: { [string]: string | number | boolean }? }
export type MapGimmick = { Type: string, Id: string, Attr: { [string]: string | number | boolean } }
export type MapSpec = {
    Name: string, Size: Vec3,                   -- 경기장 외곽 크기 (렌더러·검사용)
    Parts: { MapPart }, Markers: { MapMarker }, Gimmicks: { MapGimmick }?,
}
-- Maps/S1_1.luau
return function(K) -- K = Maps/Kit
    local parts, markers = {}, {}
    K.floor(parts, { 0, 0, 0 }, { 120, 120 }, "Tile")
    -- ...
    return { Name = "S1_1", Size = { 120, 30, 120 }, Parts = parts, Markers = markers }
end
```

- **키트(`Kit.luau`)**: 원작 문법의 조각을 함수로 제공 — `floor`, `wall(높이 Low/Mid/High, 스타일 Brick/Glass/Concrete)`, `stairs`, `platform`, `bridge`, `crate`, `barrel`, `tree`, `board`(칠판), `perimeter`(경기장 외벽). 원작처럼 **낮은 벽·상자는 점프로 올라갈 수 있는 높이**로.
- 좌표는 맵 기준 (바닥 가운데 = 원점). `MapBuilder`가 `StageOrigin`만큼 옮겨 `workspace.Stage`에 짓는다. 로비는 `workspace.Lobby`.
- 마커는 투명·충돌 없는 1×1×1 파트 + `CollectionService` 태그 + 속성. `StageService`는 **태그로만** 찾는다 (손으로 지은 맵도 같은 태그면 동작).

| 태그 | 속성 | 비고 |
|---|---|---|
| `PlayerSpawn` | — | 4개 이상 |
| `EnemySpawn` | `Kind`, `Count`(Red 제외), `Zone`(구역 반지름), `HasKey?`, `KeyColor?` | Red 마커는 `Count` 대신 `Weight` |
| `Board` | — | 칠판 1개 (시작 지점에서 보이게) |
| `WeaponPickup` | `Weapon` | 마커 `Id` 필수 (플레이어별 획득 기록용) |
| `AmmoPickup` / `HealthPickup` | — | MVP |
| `KeyPickup` / `KeyDoor` | `Color` | MVP |
| `VehicleSpawn` | `Kind` | 확장 |

- **맵 검사**(`tests/maps.spec.luau`, D): 필수 마커 수, 마커가 경기장 안, `PlayerSpawn`·`EnemySpawn`·`WeaponPickup` 아래 4스터드 이내에 바닥, 마커가 벽 속에 묻히지 않음, 레드 `Weight` 합 > 0.
- **미리보기**(`tools/map_preview.py`, D): `lune run tools/dump_maps.luau`가 맵을 JSON으로 내보내고, 파이썬이 **위에서 본 높이 지도 + 비스듬한 3D 뷰** PNG를 `build/previews/`에 그린다. 마커는 색 아이콘 (스폰 초록, 레드 빨강, 화이트 회색, 무기 노랑, 칠판 파랑).

### 3.8 에셋 레지스트리 (`Assets.luau`)

```lua
Assets.get(key: string): Instance?      -- ReplicatedStorage.Assets 안의 경로 ("Weapon/Pistol"), 있으면 Clone
```

- 키: `Weapon/<Id>`, `Enemy/<Kind>`, `Prop/<Name>`. 없으면 `nil` → 호출하는 쪽이 코드로 조립한 대체 모델을 쓴다.
- 규격: 무기 = `Handle` 파트 + `Muzzle` 어태치먼트, 정면 −Z. 몬스터 = R6 리그. 소품 = PrimaryPart가 바닥 중앙.

---

## 4. 1차 웨이브 = 수직 슬라이스

**범위**: 로비 + 스테이지 1-1 / 1-2 / 1-3, 무기 `Bat` `Pistol` `Sniper`(픽업), 몬스터 `Red` `White`, 1~4인 협동, 쓰러짐·부활, 도장, 저장, 레이더, 효과음 키.

| 스테이지 | 아이디어 (한 판에 하나) | 목표 Base | ParTime |
|---|---|---|---|
| 1-1 | 그냥 찾기: 레이더 보고 구석에 있는 레드 찾기 | 1 | 40 |
| 1-2 | 높은 곳: 플랫폼 위 레드, 근처에 저격총 픽업 | 2 | 60 |
| 1-3 | 피하기: 화이트 사이에 섞인 레드, 방망이 넉백 연습 | 3 | 75 |

| 에이전트 | 파일 | 플레이 검증 체크리스트 (검수자가 Studio에서) |
|---|---|---|
| **A 무기** | `Config/Weapons`, `WeaponMath`, `Models/WeaponModels`, `WeaponService`, `CameraController`, `WeaponController` | 1인칭, 화면에 방망이·권총, 1/2/3·Q 전환, 좌클릭 사격, 우클릭 조준(저격 스코프), R 재장전, 탄약 표시, 히트마커, 저격총 픽업이 내 화면에서만 사라짐, 방망이로 화이트 넉백·기절 |
| **B 몬스터** | `Config/Enemies`, `EnemyLogic`, `Models/EnemyModels`, `EnemyService`, `EnemyFX` | 레드가 구역 안에서 배회 → 발견 시 "!" → 도망 → 지침, 화이트가 쫓아와 때리고 멀어지면 귀환, 체력바, 죽으면 날아감, 30마리에서 끊김 없음 |
| **C 흐름·데이터** | `Profile`, `DataService`(OX 이식), `StageFlow`, `HUDController`, `LobbyUI`, `MobileControls` | 준비→투표→카운트다운→플레이→결과→다음 판, 카운터·레이더·체력바, 피격 빨간 화면, 쓰러짐·동료 부활(2인), 이탈 시 목표 감소, 도장 연출, 감도 설정, 재접속 유지(테스트 플레이스), 초대 버튼, 모바일 버튼 |
| **D 맵** | `MapBuilder`, `StageService`, `Maps/Kit`, `Maps/Lobby`, `Maps/S1_1~3`, `tests/maps.spec.luau`, `tools/dump_maps.luau`, `tools/map_preview.py` | 로비·3개 스테이지가 지어짐, 칠판 문구, 스폰 정상, 끼임·추락 없음, 상자·낮은 벽 점프 가능, 미리보기 PNG가 실제와 일치 |

**모든 에이전트 공통**

1. 이 문서 전체, `src/shared/Types.luau`, `docs/reference/ORIGINAL_NOTES.md`를 먼저 읽는다.
2. 자기 소유 파일만 만든다/고친다 (스텁이 이미 있으면 덮어쓴다). 순수 로직은 따로 모듈로 빼서 `tests/<이름>.spec.luau`에 Lune 테스트를 쓴다.
3. 다른 서비스는 스텁일 수 있다. 계약된 API만 호출하고, 스텁의 반환값에 기대지 않는다.
4. `tools/check.sh` → `CHECK PASS`.
5. `docs/reports/<A|B|C|D>.md`: 만든 파일, 공개 API 구현 여부, 테스트 결과, 자동 검사 상태 / 플레이 검증 상태(검수 대기), Studio 검수 체크리스트, 알려진 한계, 계약 변경 제안.

---

## 5. 이후 단계

| 단계 | 내용 |
|---|---|
| 첫 협동 테스트 | 슬라이스를 친구 2~4명과 플레이. 수치 조정 |
| 공개 MVP | 레벨 1~3 (스테이지 15 + 보너스 3), `Bomb` `Raptor` `Missile`, `Rifle` `Shotgun` `Grenade` `Rocket`, 기믹(열쇠·버튼·압력판·가시·미사일·울타리), 체력·탄약 픽업, 상점, 레벨 선택 화면 |
| 콘텐츠 확장 | 레벨 4 이후, 차량·헬기, 게임패스, 일일 퀘스트(OX 이식), 월 순방문자 2천 명 달성 후 보상형 광고 |

- 후반 스테이지는 원작 후반 영상에서 뽑은 **스테이지 설계 문법**(레벨별 목표 수·크기·밀도·기믹 수·새 요소 등장 시점)을 기준으로 AI가 생성하고, 맵 검사 + 미리보기 + 플레이로 거른다.

---

## 6. 변경 이력

- **v0.3 (2026-10-31)** 원작 영상 분석 반영: 짧은 판 템포, 슬라이스를 1-1~1-3으로, 목표 수 1부터 + 협동 곱셈 보정, 무기 픽업(플레이어별), 저격총 슬라이스 포함, R6 몬스터 + 구역 행동 + "!" + 체력바, 레이더·피격 화면·조작 버튼 구성, 결과 후 바로 다음 판 투표, 칠판 힌트, 맵 키트 + 순수 데이터 + 미리보기 렌더러 + 맵 검사, 기믹 스키마, 차량 처치 인정(화이트는 벌점), 에셋 레지스트리, 순수 모듈 규칙, 클라이언트 컨트롤러 타입.
- v0.2 (2026-10-31) 이름 파인딩 레드, 원작 방식 유지 + 협동, 외부 리뷰 반영.
- v0.1 (2026-10-31) 초안.
