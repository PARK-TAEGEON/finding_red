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

---

## v0.5 변경 (개선 웨이브 1.5: 시작 방 + 문 + 체력·탄약 픽업)

### 1. 바뀐 파일

| 파일 | 변경 |
|---|---|
| `src/server/Maps/Kit.luau` | `Kit.startRoom(parts, markers, center, opts)` + `Kit.startRoomSouth(parts, markers, d, x?, opts?)`, `Kit.health(markers, surface, id)`, `Kit.ammo(markers, surface, id, weapon?)`, `Kit.board`에 `legs = false`(벽걸이), 색 `Door/DoorFrame/DoorHandle/RoomWall/RoomBand/RoomFloor`, 상수 `Kit.Room`, 파트 이름 `Kit.Names` |
| `src/server/Maps/S1_1~3.luau` | 남쪽 가운데 스폰 패드·칠판을 시작 방으로 교체, 체력·탄약 픽업 추가 |
| `src/server/Maps/Validate.luau` | 시작 방 규칙, 체력·탄약 픽업 규칙, 지붕 아래 높이 보정, 문 열림/닫힘 두 격자 |
| `src/server/Services/StageService.luau` | 스텁을 `OpenStartDoor` / `StartDoorPosition` 실제 구현으로 교체. `Load`가 문을 닫힌 상태로 찾아 둔다 |
| `tests/maps.spec.luau` | 267 → **447개** 검사 |
| `tools/dump_maps.luau` | 요약 줄에 시작 방 크기·누수 칸·픽업 수 |
| `tools/map_preview.py` | 문(흰 막대 + 검은 테두리 + 열린 위치 점선·화살표), 시작 방 점선 상자 + 안에 있는 물건 목록, 체력(빨간 십자)·탄약(초록 상자) 아이콘. top 뷰는 방 지붕을 숨기고, iso 뷰는 지붕과 카메라 쪽 벽을 반투명하게 그린다 |

MapBuilder는 바꾸지 않았다 (문은 일반 Geometry 파트, 새 마커는 기존 태그·속성 규칙 그대로).

### 2. 시작 방 키트 (`Kit.startRoom`)

- 안쪽 14(문 벽 방향) × 10(깊이), 벽 높이 12, 두께 1, 지붕(0.8) → **완전히 막힌 방**. 바닥은 나무판(0.2) — 스폰 마커는 그 위 +3.
- `opts.facing` = 방에서 경기장 쪽 방향(`-z` 기본, `+z` `-x` `+x`), `opts.board = "right" | "left"`(좌우 반전), `opts.door = { at = 2, width = 6, height = 8 }`, `opts.length/depth/height`.
- **흰 문** 6×8×0.6 (`Name = "StartDoor"`, 충돌 있음) + 양면 손잡이 2개(`StartDoor`, 충돌 없음) + 남색 문틀(`DoorFrame` 기둥, 윗막대는 `DoorLintel`). 문 위 벽은 `DoorLintel`. 문은 **벽 두께 속으로 미끄러져 들어가는 포켓 도어**: 옆 벽 구간(길이 7)이 문 폭(6)보다 길어서 열리면 문이 벽 속에 완전히 숨는다(테스트로 확인).
- 칠판: 방 오른쪽 끝 벽에 벽걸이(8×5, 다리 없음), 스폰 4개(`Spawn1~4`)는 반대쪽 끝에 한 줄로 서서 칠판을 본다(약 10.5스터드). 문은 스폰에서 보면 왼쪽 앞.
- 조명: 천장 Neon 판 + 문 위 바깥쪽 등(둘 다 `Light`, 충돌 없음).
- 마커:
  - `StartDoor` — 문 중심(바닥 + 4). `Rot`은 경기장 쪽을 본다(LookVector = 나가는 방향). 속성 `Slide = "x,y,z"`(열린 위치까지의 이동량, 맵 좌표 = 월드 좌표), `Width`, `Height`.
  - `StartRoom` — 방 안쪽 중심(바닥 + 6). 속성 `Size = "14,12,10"`(월드 축 기준 안쪽 크기).
- 반환값 `{ spots, door, outside, floor, min, max }`: `spots` = 바닥 위 픽업 자리 3곳(스폰 줄에서 5.5 이상 떨어져서 스폰하자마자 자동으로 줍지는 않고, 문까지 걸어가는 길에 줍게 됨).
- `Kit.startRoomSouth(parts, markers, D, x)` = 남쪽 외벽에 붙여 문이 북쪽을 향하게. 방 뒷벽이 따로 있어서 외벽 유리 너머가 보이지 않는다.
- 파트 수: 방 하나 18개.

### 3. 스테이지별 시작 방

세 스테이지 모두 방은 남쪽 외벽 가운데(안쪽 x −7~7), 문은 북쪽 벽의 x −1~5, 맵 좌표 문 중심 = `(2, 4, D/2 − 11.5)`.

| 스테이지 | 방 안 | 경기장 픽업 | 메모 |
|---|---|---|---|
| 1-1 (90) | 없음 | `S1_1_Health` (13, 0, −4): 가운데 낮은 벽 사각형 동쪽 | 문 양옆 바깥에 가로등 (±11, 30). 문 밖에서 보이는 레드 마커 4개 중 1개 |
| 1-2 (110) | `S1_2_Sniper`(바닥, 스폰 앞) | `S1_2_Health` (−30, 0, 20): 서쪽 낮은 벽 뒤 / `S1_2_Ammo` (31, 0, 2): 동쪽 상자 L 옆 | 문이 저격 레인 시작점: 문 앞에서 탑 망대(`Perch`)가 바로 보인다(테스트). 원래 받침(plinth) 제거 |
| 1-3 (120, 밤) | `S1_3_AmmoRoom`(`AmmoPickup`, 속성 `Weapon = "Pistol"`) | 저격총은 가운데 사당에 그대로. `S1_3_HealthW` (−12, 0, 12), `S1_3_HealthE` (44, 0, −12), `S1_3_AmmoNW` (−44, 0, −18) | 문 양옆 가로등 (±11, 44). 방 안 천장등 + 문 위 등 |

모든 몬스터 구역은 방(벽 포함)과 겹치지 않는다(검사). 경기장 배치는 남쪽 스폰 패드·칠판·가로등만 바뀌었다.

### 4. StageService

- `Load`: 지은 모델에서 이름이 `StartDoor`이고 **태그가 없는** BasePart(= 문 Geometry, 마커 제외)를 모두 찾아 닫힌 CFrame을 기억한다. 이동량은 `StartDoor` 마커의 `Slide`, 없으면 가장 큰 파트의 긴 가로축 방향으로 그 폭만큼(손으로 지은 맵 대비).
- `OpenStartDoor()`: 멱등. 문 파트 전부를 TweenService로 0.6초(Quad Out) 미끄러뜨리고, 0.6초 뒤 최종 위치로 맞추고 `CanCollide = false`, `CanQuery = false`. 스테이지가 그 사이에 내려가도 안전(부모 없는 파트는 건너뜀). 문이 없으면 아무것도 안 한다.
- `StartDoorPosition()`: 스테이지가 없으면 nil, 있으면 **닫힌 문 중심**(StartDoor 마커 위치, 월드). 열린 뒤에도 같은 값.
- `Unload`: 문 상태 초기화. 로비는 영향 없음.
- 닫힌 문은 `GeometryParams`에 포함되므로 몬스터 시야·사격 검증에서도 벽이다.

### 5. 검사기 추가 규칙

- 스테이지마다 `StartDoor` 정확히 1개, `StartRoom` 정확히 1개, `Size` 속성 형식(`"x,y,z"`, 양수).
- 모든 `PlayerSpawn`이 StartRoom 상자 안. `StartDoor`가 방 벽(안쪽 + 2.5) 위.
- **밀폐(문 닫힘)**: 문은 벽으로, 플레이어가 밑으로 지나갈 수 있는 것(바닥 + 5 이상에 떠 있는 파트: 지붕·문 위 벽)은 빼고 1스터드 격자를 만든 뒤, 넉넉한 점프(7.5)로 스폰에서 채우기 → 방 안쪽(+0.5) 밖의 칸이 하나라도 닿으면 오류. 문 없는 문틀, 빠진 벽, 바닥에서 6 떠 있는 벽, 지붕 없는 6 높이 벽은 모두 잡힌다(테스트).
- **시야 밀폐**: 문이 닫힌 상태에서 어느 스폰에서도 어떤 적 마커도 보이지 않아야 한다.
- **지붕 오르기**: 경기장 쪽에서 방 주변 4스터드 안에 지붕 높이 − 7.5 이상인 칸에 닿으면 오류(방 옆에 8 높이 상자 피라미드 → 잡힘).
- **지붕 아래 높이 보정**: 방 안(벽 포함)에서 천장까지 5 미만인 칸(벽 위, 칠판 윗면)은 벽으로 본다. 높이맵이 지붕 밑 벽 위를 걸어 다니지 않게 하기 위함.
- **도달성은 문 열림 기준**: 문·지붕·문 위 벽을 뺀 격자. 문 바로 앞 경기장 칸이 스폰에서 닿아야 한다.
- 몬스터 구역 원이 방 상자(+ 벽 1)와 겹치면 오류.
- `HealthPickup` / `AmmoPickup`: `Id` 필수, 무기·체력·탄약 픽업 전체에서 `Id` 고유, 0~4 아래 바닥, 머리 위 3, 걸어서 도달.
- "스폰에서 보이는 레드" 통계(1-2 경고)는 이제 **문 밖 3스터드에서 본 것**으로 잰다.

### 6. 테스트·검사 결과

```
ok   tests/maps.spec.luau — maps.spec: 447 checks passed (Lobby, S1_1, S1_2, S1_3)
== map dump  ok — 4 maps ok
CHECK PASS
```
```
ok   S1_1: 178 parts, 12 markers, red weight 4, reach 91.7%, traps 0, reds seen from spawn/door 1, start room 14x12x10 (leak 0), pickups W0 H1 A0
ok   S1_2: 190 parts, 14 markers, red weight 3, reach 95.7%, traps 0, reds seen from spawn/door 3, start room 14x12x10 (leak 0), pickups W1 H1 A1
  warn:  S1_2: every Red marker is visible from the spawn   (의도: 문 밖에서 높은 곳의 레드가 보임)
ok   S1_3: 244 parts, 21 markers, red weight 5, reach 96.3%, traps 0, reds seen from spawn/door 4, start room 14x12x10 (leak 0), pickups W1 H2 A2
```

새 테스트: 키트(마커·속성, 문 6×8 흰색, 벽 ≥ 10 + 지붕, 열린 문이 포켓 벽 속에 숨음, 스폰이 칠판을 봄, 4방향 × 좌우 반전 8가지 방이 모두 검사 통과, `Slide`가 길이 6이고 문 벽과 평행), 검사기 실패 사례(StartDoor/StartRoom 없음, Size 형식, 방 밖 스폰, 문 없는 문틀, 벽 빠짐, 떠 있는 벽, 낮은 벽 + 지붕 없음, 지붕 오르기, 구역 겹침, Id 없음·중복(체력/탄약/무기 사이), 떠 있는 체력, 못 가는 탄약), 스테이지(방 1개·남쪽·14×10·스폰과 칠판이 방 안·문이 북쪽 벽·방 중심에서 모든 적 마커 안 보임·체력 1~2·탄약 ≤ 2(1-2, 1-3은 ≥ 1)·체력은 경기장에·1-2 저격총은 방 안·1-3 방 안 권총 탄약 1개 + 저격총은 방 밖·1-2 문 앞/문간에서 망대가 보임).

- **자동 검사 상태: 통과** (`tools/check.sh` → `CHECK PASS`)
- **플레이 검증 상태: 검수 대기**

### 7. Studio 검수 체크리스트 (v0.5)

1. 서버 Command Bar(Play 중): `local S = require(game.ServerScriptService.Server.Services.StageService); local h = S:Load("1-1"); print(#h.Markers.PlayerSpawn, #h.Markers.StartDoor, #h.Markers.StartRoom, h.Markers.StartRoom[1]:GetAttribute("Size"), #(h.Markers.HealthPickup or {}))` → `4 1 1 14,12,10 1`.
   1-2: WeaponPickup 1, HealthPickup 1, AmmoPickup 1. 1-3: WeaponPickup 1, HealthPickup 2, AmmoPickup 2.
2. `print(S:StartDoorPosition())` → 1-1 `2002, 4, 33.5` / 1-2 `2002, 4, 43.5` / 1-3 `2002, 4, 48.5`. `S:Unload(); print(S:StartDoorPosition())` → `nil`.
3. 캐릭터를 스폰으로: `game.Players:GetPlayers()[1].Character:PivotTo(h.Markers.PlayerSpawn[1].CFrame)` → 나무 바닥 위에 서서 오른쪽 끝 벽의 칠판을 정면으로 본다. 흰 문은 왼쪽 앞(북쪽 벽).
4. **문이 닫힌 동안**: 점프·벽 비비기로 방을 못 나간다. 문을 통과할 수 없다. 천장·벽 너머로 경기장이 보이지 않는다(지붕 있음). 방 안이 충분히 밝다(천장등). 1-3(밤)에서도 칠판 글씨가 읽힌다.
5. `S:OpenStartDoor()` → 흰 문이 약 0.6초 동안 왼쪽(서쪽) 벽 속으로 미끄러져 사라지고, 그 뒤 통과할 수 있다. 다시 `S:OpenStartDoor()`를 불러도 아무 변화 없음. 문이 벽 밖으로 삐져나오거나 깜빡이지 않는다(손잡이 포함).
6. 문을 나가 경기장에서 돌아보면 방이 회색 콘크리트 상자 + 남색 띠 + 흰 문(열린 뒤엔 빈 문틀) + 문 위 등으로 보인다. 방 지붕 위로 올라갈 방법이 없다.
7. 열린 문으로 몬스터(B 연동 후)가 방까지 쫓아올 수는 있지만, 문이 닫힌 카운트다운 동안에는 어떤 몬스터 구역도 방에 닿지 않는다.
8. **1-2**: 스폰 바로 앞 바닥에 저격총 마커(무기 A 연동 후 떠서 도는 저격총). 문 밖으로 한 걸음 나가면 북쪽 끝 탑 망대가 정면에 보인다.
9. **1-3**: 방 안 바닥에 탄약 상자(`AmmoPickup`, `Weapon = "Pistol"`), 저격총은 여전히 가운데 사당 안.
10. 체력(빨간 십자)·탄약(초록) 상자가 미리보기 위치에 있고, 바닥에서 약 2 위에 떠 있다(A가 모델을 그린 뒤).
11. C 연동 후: 카운트다운 = 방 단계, 문 5스터드 안에서 E/손 버튼 → 문 열림 + 타이머 시작, 20초 뒤 자동 열림.
12. 미리보기 PNG와 Studio 모습 비교.

### 8. 미리보기

`lune run tools/dump_maps.luau && python3 tools/map_preview.py` → `build/previews/`
- `Lobby_top.png`, `Lobby_iso.png` (변경 없음)
- `S1_1_top.png`, `S1_1_iso.png`, `S1_2_top.png`, `S1_2_iso.png`, `S1_3_top.png`, `S1_3_iso.png`

top: 하늘색 점선 = 시작 방(지붕 숨김), 옆 상자에 "start room 14×10, h12" + 방 안 물건 목록, 흰 막대 + 검은 테두리 = 문, 점선 칸 + 흰 화살표 = 열린 위치, 빨간 십자 = 체력, 초록 상자(노란 줄) = 탄약. iso: 방 지붕과 카메라 쪽 벽 반투명, 문 테두리 검은 선, 방 바닥 하늘색 점선. 세 스테이지 PNG를 직접 열어 보고 라벨 겹침을 고쳤다.

### 9. 알려진 한계

- `Light` 파트의 PointLight는 `Shadows = false`라서 방 천장등 빛이 벽 너머로 조금 샌다(눈에 띄면 MapBuilder에서 방 안 Light만 Shadows를 켜면 됨).
- 문 열림 트윈은 서버에서 CFrame을 바꾸므로 클라이언트에서는 복제 주기만큼 약간 끊겨 보일 수 있다.
- 밀폐 검사는 1스터드 높이맵 근사다. 1스터드보다 좁은 틈은 못 잡지만 사람도 못 지나간다. 지붕 없는 방은 "벽 높이 > 7.5"로만 막는다.
- `Kit.startRoom`의 다른 방향(`+z/±x`)과 좌우 반전은 단위 테스트로만 검증했다(지금 맵은 모두 남쪽 `-z`).
- 문 열림 소리 키가 `Config/Audio`에 없어 소리는 넣지 않았다.
- 1-1에는 탄약 픽업이 없다(과제 허용 범위, 레드 1마리 판).

### 10. 계약 변경 제안 (v0.5)

1. §3.7 마커 표: `StartDoor`에 선택 속성 `Slide`("x,y,z", 열린 위치 이동량), `Width`, `Height`와 "`Rot`의 LookVector = 경기장 쪽" 을 적자. C가 손 버튼 위치·방향에 쓸 수 있다.
2. §3.9 마커 높이에 `HealthPickup`/`AmmoPickup` = 바닥 + 2(무기와 같음) 추가.
3. `AmmoPickup`의 선택 속성 `Weapon`(예: "Pistol") — 지금은 힌트일 뿐이고 규칙은 "들고 있는 무기 +50%". A가 쓸지 정해 주면 좋겠다.
4. `Config/Audio`에 `DoorOpen` 키 → StageService가 `OpenStartDoor`에서 재생(서버 3D 소리) 또는 C가 재생.
5. 문 파트 이름 규칙(`StartDoor` = 움직이는 문 파트, `Geometry` 폴더 안 / 마커 파트도 이름이 `StartDoor`이지만 `Markers` 폴더 + 태그)을 §3.7에 적어 두면 다른 에이전트가 `FindFirstChild("StartDoor", true)`로 마커를 잘못 잡는 일을 막을 수 있다.
