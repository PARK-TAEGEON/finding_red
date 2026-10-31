# Agent D (맵) 보고서: 1차 웨이브

## 1. 만든 파일

| 파일 | 내용 |
|---|---|
| `src/server/Maps/Kit.luau` | 순수 맵 키트. `floor` `patch` `perimeter` `wall`(Low/Mid/High 또는 숫자 × Brick/Concrete/Glass/Marble/Hedge) `ring`(틈 지정) `stairs` `platform`(Deck/Building/Tower/Concrete + 난간) `parapet` `bridge` `crate` `crates` `barrel` `tree`(Ball/Block) `pen` `board` `lamp` `bench` `plinth` `spawnPad`, 마커 헬퍼 `playerSpawn` `spawnRow` `red` `white`/`enemy` `weapon` `marker`, 그리고 `faceRot` `box` `block` `span` `cylinder` `ball` |
| `src/server/Maps/Validate.luau` (**새 파일**) | 순수 맵 검사기. 테스트와 덤프 도구가 함께 쓴다 (§2.3에 따라 내 폴더 안에 만듦) |
| `src/server/Maps/Lobby.luau`, `S1_1.luau`, `S1_2.luau`, `S1_3.luau` | 로비 + 스테이지 1-1~1-3 (`return function(K) ... end`) |
| `src/server/Services/MapBuilder.luau` | MapSpec → `Model{Geometry, Markers}`. `build`, `setBoardLines`, `collectMarkers` (서비스가 아닌 헬퍼) |
| `src/server/Services/StageService.luau` | 계약 API 전부 |
| `tests/maps.spec.luau` | 키트 단위 검사 + 검사기 실패 사례 검사 + 맵별 설계 검사 (267개) |
| `tools/dump_maps.luau` | 맵 전부 로드 → 검사 → `build/maps/<Name>.json`, 마지막 줄 `4 maps ok`, 오류가 있으면 exit 1 |
| `tools/map_preview.py` | numpy z-buffer 래스터라이저. `build/previews/<Name>_top.png`, `<Name>_iso.png` |

다른 사람 파일은 고치지 않았다.

## 2. 계약 API 상태 (`Types.StageService`)

| API | 상태 | 비고 |
|---|---|---|
| `Init` / `Start` | 구현 | `Start`에서 조명을 Day로 맞추고 `Maps/Lobby`로 `workspace.Lobby`를 원점에 짓는다. 기존 `workspace.Lobby`가 있으면 지우고 새로 짓는다 |
| `Load(stageId)` | 구현 | 이전 스테이지를 내리고 `Config.Stages[id].Map` 모듈을 `require`해서 `Kit`으로 호출한 뒤 `workspace.Stage`를 `Config.Game.StageOrigin`(2000,0,0)에 짓는다. `Sky`에 맞춰 조명을 바꾸고, 칠판 기본 문구 `{"LEVEL 1-1", 스테이지 이름, ""}`를 쓴다. 반환하는 `StageHandle.Markers[tag]`는 모델 아래 BasePart를 **CollectionService 태그로만** 모은 것 |
| `Unload` | 구현 | Stage 모델을 지우고 조명을 Day로 되돌린다 |
| `Current` | 구현 | |
| `LobbySpawn(index)` | 구현 | 로비 스폰 8개를 `MarkerId`(`Lobby1`~`Lobby8`) 순으로 정렬해 `((index-1) mod n)+1`번을 돌려준다. 값은 마커 CFrame(서 있는 사람의 루트 높이, 칠판을 바라봄)에서 0.5 위. 0이나 음수 index도 처리한다 |
| `SetBoard(lines)` | 구현 | 3줄(1줄 크게). 4줄 이상이면 3번째 줄 뒤에 이어 붙인다 |
| `SetLobbyBoard(text)` | 구현 | `\n`으로 나눠 최대 3줄 |
| `GeometryParams()` | 구현 | 호출할 때마다 **새** `RaycastParams`(Include = 로비 `Geometry` + 현재 스테이지 `Geometry`)를 만든다. 마커·몬스터·캐릭터는 들어가지 않는다. 로드·언로드 뒤 다시 부르면 바뀐 내용이 반영된다 (**받은 params를 오래 보관하지 말고 그때그때 부를 것**) |

**마커 규칙 (A·B·C 참고)**
- 마커는 1×1×1, 투명, CanCollide/CanQuery/CanTouch false, 태그 + `Attr`의 모든 키를 속성으로, `Id` → 속성 `MarkerId`.
- 높이: `PlayerSpawn`·`EnemySpawn`은 **서 있는 면 + 3**(루트 파트 높이), `WeaponPickup`은 **면 + 2**(떠 있는 무기 높이). 스폰 마커의 Rot은 칠판/경기장 쪽을 본다 → C는 `marker.CFrame`으로 바로 `PivotTo`해도 된다.
- `Board` 마커는 MapBuilder가 진초록 칠판 판(속성 `Width`×`Height`×0.4, 충돌 있음, `SurfaceGui` 앞면, `LightInfluence = 0`이라 밤에도 잘 보임)으로 바꾼다. `Markers` 폴더 안에 있으므로 `GeometryParams`에는 들어가지 않는다.
- Geometry: 모두 Anchored. `Collide=false`인 장식(타일 줄눈, 창문 띠, 유리 격자, 드럼통 띠)은 `CanQuery=false`라 레이캐스트에 걸리지 않는다. 이름이 `Light`인 파트에는 PointLight를 붙인다(밤 가로등). 외벽 위로 보이지 않는 충돌 벽(`PerimeterBarrier`, 30스터드)이 있다.

## 3. 테스트와 검사 결과

```
== rojo build                ok
== type check (src/)         ok (lint warnings: 0)
== lune tests
ok   tests/maps.spec.luau — maps.spec: 267 checks passed (Lobby, S1_1, S1_2, S1_3)
ok   tests/rules.spec.luau — rules.spec: 33 checks passed
== map dump                  ok — 4 maps ok
CHECK PASS
```

덤프 요약:
```
ok   Lobby: 121 parts, 9 markers, reach 91.1%, traps 0
ok   S1_1: 164 parts, 9 markers, red weight 4, reach 92.3%, traps 0, reds seen from spawn 2
ok   S1_2: 173 parts, 10 markers, red weight 3, reach 95.7%, traps 0, reds seen from spawn 3
  warn:  S1_2: every Red marker is visible from the spawn   (의도: 높은 곳의 레드를 보여 주는 스테이지)
ok   S1_3: 230 parts, 15 markers, red weight 5, reach 96.6%, traps 0, reds seen from spawn 3
```

**검사기(`Validate.run`)가 확인하는 것**: 스키마(Shape, Size>0, `#RRGGBB`, 알려진 Enum.Material 이름, Transparency 범위), 파트 400개 미만, PlayerSpawn 4개 이상, Board 정확히 1개, 스테이지의 레드 Weight 합 > 0, Red는 `Weight`, 나머지는 정수 `Count`, `Zone` > 0, WeaponPickup의 `Weapon`과 고유 `Id`, 마커가 경기장 안에 있는지, 마커가 충돌 파트 속에 묻히지 않았는지, 스폰·적·픽업 마커 0~4스터드 아래에 바닥이 있는지, 머리 위 공간(스폰 5, 픽업 3), **적 구역**(링 샘플이 같은 높이의 걸을 수 있는 바닥 위에 있고 60% 이상 비어 있는지, 낭떠러지 위로 나가지 않는지, 경기장 밖으로 나가지 않는지), **1스터드 격자 도달성**(점프 5.5로 오를 수 있음 기준. 들어갈 수는 있는데 못 나오는 칸 = 함정 → 오류), 픽업은 걸어서 닿을 수 있는지, 적 마커는 걸어서 닿거나 스폰·픽업에서 보이는지, **외벽 탈출**(점프 7.5 기준으로 외벽 위에 뛰어오를 수 있는 칸이 가장자리 12스터드 안에 없는지), 모든 스폰에서 칠판이 보이는지, 스폰에서 모든 레드가 한꺼번에 보이면 경고. 회전한 파트는 회전한 상자의 AABB로 보수적으로 다룬다.

**맵별 설계 검사(spec)**: 1-1 레드 마커 3~4개가 서로 다른 구석에 있고 Weight 1, Zone 8~12, 화이트 없음, 스폰에서 일부만 보임 / 1-2 레드가 모두 높은 곳에 있고 Zone 4~6, 옥상 2개는 걸어서 도달, `Perch`는 도달 불가 + 15스터드 안에 뛰어오를 발판 없음 + 스폰과 저격총 위치에서 보임, 저격총은 스폰에서 16 이내, 화이트는 땅 위에 1개 이하 / 1-3 Count 2~3에 Zone 12~20인 화이트 무리 3개 이상, Pen 기믹 + 울타리 안에 구역이 다 들어가는 화이트, 레드 구역 3개 이상이 화이트 구역과 겹침, 저격총은 스폰에서 40 넘게 떨어져 있고 화이트 무리 곁, 가로등 8개 이상. 그리고 키트 단위 검사(높이, 계단 단차 ≤ 1, 외벽이 경기장을 침범하지 않음, ring의 틈, 울타리 틈 < 1, 마커 속성·높이, faceRot ↔ 회전 행렬 일치)와 검사기 실패 사례(묻힘, 공중 스폰, 낮은 천장, 중복 Id, 잘못된 재질·색, 낭떠러지 구역, 경기장 밖 구역, 외벽 탈출, 함정)도 있다.

## 4. 상태

- **자동 검사 상태: 통과** (`tools/check.sh` → `CHECK PASS`)
- **플레이 검증 상태: 검수 대기** (Studio에서 아래 체크리스트 수행 필요)

## 5. 스테이지 설계 메모

미리보기에서 남쪽(+z)은 아래쪽이다. 모든 스테이지는 남쪽 가운데 초록 스폰 패드에서 북쪽을 보고 시작한다. 바닥은 회색 타일(Slate + 줄눈), 외벽은 남색 띠 + 파란 격자 유리다.

### Lobby (64×64)
- 빨강·흰색 과녁 무늬 위에 스폰 8개가 원형으로 서서 북쪽 큰 칠판(22×9)을 본다. 벤치 4개, 네 구석에 나무, 상자, 드럼통, 칠판 양옆에 가로등. 가장자리는 잔디.

### 1-1 "그냥 찾기" (90×90, 낮)
- **아이디어**: 레드 1마리(+예비)가 네 구석 중 한 곳에 나온다. 구석마다 생김새가 달라 "어느 구석"인지 말로 부르기 쉽다.
- **구석**: 북서 = 벽돌 방(Mid 벽돌 L자, 남동쪽 모서리가 문), 북동 = 잔디 숲(나무 4그루 + 앞쪽 낮은 생울타리), 남서 = 상자 마당(Mid 콘크리트 벽 뒤라 스폰에서 안 보임), 남동 = 낮은 벽돌 U자 화단 + 블록 나무 + 드럼통.
- **동선**: 가운데에 틈이 네 개 있는 낮은 벽돌 사각형과 큰 나무가 시야를 나눈다. 모든 벽은 Low(점프로 넘음) 아니면 문이 있다.
- **레드**: 마커 4개, Weight 1, Zone 8~10. 스폰에서는 4개 중 2개만 보인다.

### 1-2 "높은 곳" (110×110, 낮)
- **아이디어**: 레드가 옥상에 있다. 둘은 계단으로 올라가서 잡고, 하나는 저격으로만 잡는다.
- **서쪽**: 벽돌 건물(옥상 높이 8, 창문 띠, 난간 2), 서쪽 외벽을 따라 북쪽으로 오르는 대리석 계단. **동쪽**: 콘크리트 블록(옥상 12, 난간), 남쪽에서 오르는 계단. **북쪽 가운데**: 대리석 탑 망대(꼭대기 24, 난간 2). 걸어서 못 올라가고 근처에 뛰어오를 발판도 없다.
- **저격 레인**: 스폰 → 망대가 경기장 한가운데를 일직선으로 지난다(칠판은 이 레인을 막지 않도록 왼쪽에 둠). 저격총은 스폰 오른쪽 대리석 받침 위.
- **땅**: 가운데 들판에 화이트 1마리(Zone 14). 레인 양옆에 낮은 벽돌 벽과 상자가 엄폐물.
- **레드**: `RoofWest`(Zone 5), `RoofEast`(Zone 5), `Perch`(Zone 4), 모두 Weight 1. 스폰에서 셋 다 보인다(의도: 경고만 뜸).

### 1-3 "섞여 있다" (120×120, 밤)
- **아이디어**: 레드가 화이트 무리 사이를 같이 걸어 다닌다. 쏘기 전에 확인하고, 화이트는 방망이로 밀어낸다.
- **화이트**: 서쪽 정원 3마리(Zone 16), 북쪽 2마리(Zone 14, 생울타리와 벽돌 벽 사이), 동쪽 2마리(Zone 14), 북동쪽 **우리**(22×22 울타리, 높이 4.5) 안에 3마리(Zone 7).
- **레드**: 서쪽·북쪽·동쪽 무리 안에 각 1, 북서쪽 벽돌 L자 정원에 1(Zone 9), 우리 옆에 1(Zone 10). 모두 Weight 1.
- **저격총**: 맵 한가운데 대리석 바닥 + 사방에 틈이 있는 낮은 벽돌 사당 안 받침 위. 북쪽 화이트 무리 바로 앞이라 위험하다.
- **밤**: 가로등 12개(Neon 머리 + PointLight). 스폰 앞에 상자 더미와 나무를 두어 첫눈에 다 보이지 않게 했다.

## 6. Studio 검수 체크리스트

1. `rojo build -o build/FindingRed.rbxl`로 만든 파일을 Studio에서 연다(또는 `rojo serve`). Play(솔로)를 누른다.
2. Output에 `[MapBuilder]` 경고가 없는지 본다(알 수 없는 재질·색이면 경고가 뜬다).
3. **로비**: `workspace.Lobby`가 원점에 있다. `Geometry`/`Markers` 폴더가 있다. 칠판에 "파인딩 레드 / 준비 버튼을 누르면 시작해요 / 레드만 잡으세요!"가 보인다. 캐릭터가 과녁 위 스폰에 서서 칠판을 본다(C 연동 후). 벤치·나무·상자가 미리보기 `Lobby_iso.png`와 같다.
4. 로비에서 상자 피라미드 2층(8)은 점프로 한 칸씩 오를 수 있고, 외벽 위로는 못 나간다.
5. 명령창에서 스테이지를 직접 불러 본다 (서버 측 Command Bar, Play 상태에서):
   `local S = require(game.ServerScriptService.Server.Services.StageService); local h = S:Load("1-1"); print(#h.Markers.PlayerSpawn, #h.Markers.EnemySpawn, h.Markers.Board and #h.Markers.Board)` → `4 4 1`.
   1-2는 `4 4 1`과 `#h.Markers.WeaponPickup == 1`, 1-3은 `4 9 1`과 픽업 1.
6. `workspace.Stage`가 x=2000에 생긴다. 칠판에 "LEVEL 1-1 / 첫 사냥"이 보인다. `S:SetBoard({"LEVEL 1-1","레드 1마리 잡기","힌트: 레이더의 빨간 점을 찾아가세요"})` → 3줄이 바뀐다.
7. 캐릭터를 스테이지 스폰 마커로 옮긴다: `game.Players:GetPlayers()[1].Character:PivotTo(h.Markers.PlayerSpawn[1].CFrame)` → 바닥에 끼지 않고 서서 칠판(1-1, 1-3은 정면, 1-2는 왼쪽 앞)을 본다.
8. **1-1**: 네 구석을 돌아본다. 낮은 벽돌 벽·화단·생울타리(높이 4)와 상자(4)는 점프로 올라간다. Mid 벽(8)은 못 넘는다. 벽돌 방 문(남동 모서리)으로 드나든다. 끼는 곳이 없다.
9. **1-2** (`S:Load("1-2")`): 조명이 그대로 낮이다. 서쪽 건물 계단으로 옥상(8)에, 동쪽 블록 계단으로 옥상(12)에 올라간다. 난간 틈으로 드나든다. 북쪽 탑 꼭대기에는 어떤 방법으로도 못 올라간다. 서쪽 옥상 난간 위에서 외벽 쪽으로 뛰어도 보이지 않는 벽에 막힌다. 스폰에서 탑 꼭대기가 시야를 가리는 것 없이 보인다(저격 레인).
10. **1-3** (`S:Load("1-3")`): 밤이 된다(ClockTime 0). 바닥·벽·빨간 물체가 충분히 보이고, 가로등 불빛이 있고, 칠판 글씨가 밝게 보인다. 북동쪽 울타리(4.5)는 플레이어가 넘을 수 있고, 울타리 가로대 사이로는 사람이 못 지나간다. 한가운데 사당 안 받침 위에 저격총 마커가 있다.
11. `S:Unload()` → `workspace.Stage`가 사라지고 조명이 낮으로 돌아온다. `S:Current()`는 nil.
12. `S:GeometryParams()`로 아래 방향 레이캐스트를 쏘면 바닥 Geometry에 맞고, 마커·캐릭터에는 맞지 않는다.
13. 몬스터(B)·무기(A)·흐름(C)이 붙은 뒤: 레드·화이트가 구역 원 안 평평한 바닥에서 생기고, 옥상 레드가 떨어지지 않고, 우리 화이트가 밖으로 못 나온다. 저격총이 받침 위에 떠서 돈다.
14. 미리보기 PNG(아래)와 Studio 모습을 비교한다.

## 7. 미리보기 이미지

`lune run tools/dump_maps.luau && python3 tools/map_preview.py` → `build/previews/` (build/는 gitignore라 다시 만들어야 한다)

- `Lobby_top.png`, `Lobby_iso.png`
- `S1_1_top.png`, `S1_1_iso.png`
- `S1_2_top.png`, `S1_2_iso.png`
- `S1_3_top.png`, `S1_3_iso.png`

top: 꼭대기 높이 색(viridis) + 파트색 섞음, 테두리, 걸어서 못 가는 칸은 어둡게, 함정 칸은 자홍색, 마커(스폰 초록 ▲ + 바라보는 방향, 레드 빨강 ●, 화이트 회색 ●, 무기 노랑 ★, 칠판 파랑 ■), 적 구역 점선 원, 라벨(`R w1 z9`, `W×3 z16`, 옥상이면 `y12`). iso: 남동쪽 위에서 본 3D(z-buffer, 면 음영, 모서리 선, 가까운 남·동 외벽은 거의 투명하게), MapBuilder가 만드는 칠판 판도 그린다. 밤 조명은 그리지 않는다.

## 8. 알려진 한계

- Studio를 열 수 없어서 조명 수치(특히 밤 Ambient/OutdoorAmbient/ExposureCompensation)와 칠판 글자 크기는 실제 화면으로 맞추지 못했다. 검수 때 밤이 너무 어둡거나 밝으면 `StageService`의 `SKIES.Night`를 조정한다.
- 도달성 격자는 한 층짜리 높이맵이다. 데크형 플랫폼 아래, 나무 그늘 아래 같은 공간은 "벽"으로 본다. 그래서 도달 가능 영역을 조금 적게 잡는데, 위험한 쪽으로 틀리지는 않는다. 점프로 건너는 틈은 모델링하지 않는다.
- 시야 검사는 충돌 파트의 AABB로 한다. 유리도 막는 것으로 친다(실제 총알도 유리에 맞음).
- Wedge는 키트에서 아직 쓰지 않는다. 렌더러는 Roblox 쐐기 방향(+Z가 높은 면)을 가정했고 Studio에서 확인하지 못했다.
- 1-1의 "무작위 구석"은 B가 레드 마커를 고르는 방식에 달려 있다. `Rules.distribute`는 결정적(같은 Weight면 앞 마커부터)이라 그대로 쓰면 매번 같은 구석에 나온다 → 아래 제안 1.
- `StageService.Start`는 기존 `workspace.Lobby`를 지우고 다시 짓는다(손으로 지은 로비는 덮어씀). 손으로 지은 맵도 태그만 맞으면 `collectMarkers`가 그대로 찾는다.

## 9. 계약 변경 제안

1. **레드 마커 선택에 무작위 섞기 (B/오케스트레이터)**: 레드 수를 Weight로 나누기 전에 마커 순서를 섞자(또는 `Rules.distribute`에 시드를 주자). 그래야 1-1처럼 "Weight 1 마커 4개 중 한 곳"이 무작위가 된다.
2. **스폰 마커 높이를 계약에 적기**: "PlayerSpawn/EnemySpawn 마커 = 서 있는 면 + 3(루트 높이), WeaponPickup = 면 + 2"를 §3.7에 넣자. 지금은 "4스터드 이내에 바닥"만 적혀 있다.
3. **`GeometryParams`는 호출마다 새 객체**라는 점을 §3.4 주석에 넣자(보관하지 말고 매번 부르기).
4. **MapPart에 조명 필드**: 지금은 `Name = "Light"`인 파트에 PointLight를 붙이는 관례를 쓴다. 이후 레벨을 위해 `MapPart.Light: { Range, Brightness, Color }?` 같은 필드를 제안한다.
5. **키트·문법 추가 (MVP 레벨용)**: 기믹 조각 `keyDoor`(색 문 + `KeyDoor` 마커), `switchTarget`(`ShootSwitch`), `pressurePlate`, `crusher`(천장 가시 + 경로), `missileLane`(경로 점 목록), 회복·탄약 상자 마커 헬퍼, 미로형 벽돌 통로 생성기(`maze(seed, cells)`), 경사로(Wedge) `ramp`, 벽 위를 걷는 통로(두꺼운 Mid 벽 + 계단). 이 기믹의 `MapGimmick.Attr` 스키마(연결 대상 Id, 경로 점 등)를 §3.7에 정해 주면 바로 키트에 넣겠다. 경로 점은 Attr가 스칼라만 받으므로 `"x,y,z;x,y,z"` 문자열 같은 형식이 필요하다.
6. **`Stages`에 `Sky` 외 조명 프리셋 이름**(예: `"Dusk"`)을 허용하면 StageService에 프리셋만 추가하면 된다.
