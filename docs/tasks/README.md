# 작업 카드 운영 방법

작업 카드 한 장 = Codex 작업 한 번 = PR 하나. 카드는 오케스트레이터(Claude)가 쓰고, 검수자가 Codex에 넘긴다.

## 흐름
1. **Claude**: 웨이브 계약을 고정하고 `docs/tasks/<카드ID>.md`를 쓴다 (양식: `TEMPLATE.md`). 카드끼리 파일이 겹치지 않게 나눈다.
2. **검수자**: Codex(클라우드)에서 이 저장소를 열고 "`docs/tasks/<카드ID>.md` 작업 카드를 수행해" 라고만 맡긴다. 카드 여러 장은 동시에 맡겨도 된다.
3. **Codex**: `AGENTS.md` 규칙대로 `task/<카드ID>` 브랜치에서 작업하고 PR을 연다. Codex 리뷰를 PR에 한 번 돌린다.
4. **Claude**: PR의 바뀐 부분만 보고 이음새를 점검, `tools/check.sh`, 병합, `.rbxl` 빌드.
5. **검수자**: Studio 플레이테스트 → 피드백.

## Codex 환경 설정 (처음 한 번)
- 저장소: `PARK-TAEGEON/finding_red`
- 설정(Setup) 스크립트: `tools/setup.sh`
- 인터넷: 설정 단계에서 GitHub 접속이 필요하다 (Rojo·luau-lsp·Lune 다운로드).

## 카드 ID 규칙
`W<웨이브>-<영역><번호>` — 영역: `A` 무기, `B` 몬스터, `C` 흐름·데이터·UI, `D` 맵, `X` 기타/도구. 예) `W2-B1`.
