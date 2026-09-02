# fableplan

Claude Code의 `opusplan`(플랜=Opus, 구현=Sonnet)과 같은 워크플로를 **플랜=Fable, 구현=Opus** 조합으로 쓰게 해주는 skill + agent 세트입니다.

Claude Code 세션 안에서 원할 때만 `/fableplan <작업 설명>` 으로 켭니다. 세션 모델이 무엇이든 동작합니다.

## 동작 방식

```
> /fableplan 로그인 기능 추가
> /fableplan docs/설계-합의문.md     # /grill-me 가 남긴 설계 문서 경로도 받는다

0. [메인]   topic-branch 로 이 작업의 브랜치+워크트리를 연다 (plan mode 진입 전)
            — 이후 모든 단계의 작업 디렉토리가 이 워크트리다
1. [Fable]  fable-planner agent가 코드 탐색 후 플랜 작성
            — 설계 문서가 있으면 원문을 읽고 남은 결정만 다룬다
            — 결정이 필요한 지점은 grilling 규율로 한 번에 하나씩 질문 (메인 스레드가 중계)
            — 상태기계·권한류 모델이 있으면 explore-model 로 플랜 확정 전에 모델 검사
2. [사용자]  플랜 검토, 승인 (거부하면 피드백이 planner에게 전달돼 재플랜)
3. [Opus]   opus-builder agent가 승인된 플랜을 그대로 구현 (플랜이 지시하면 TDD)
4. [메인]   테스트/빌드 재실행 + code-review 로 검증 — 발견 사항은 builder에게 수정 위임
5. [Opus]   검증·리뷰 통과 후, 메인 스레드가 위임한 커밋을 scoped-commits 규약으로 수행
6. [사용자]  브랜치를 어떻게 닫을지 확인 — main 에 합치기 / PR 열기 / 브랜치로 두기
            — 확인 없이 합치거나 push 하지 않는다
```

### 의존 스킬

워크플로의 단계들이 외부 스킬 6개를 참조합니다: `topic-branch`(작업 브랜치),
`grilling`·`explore-model`(플랜), `tdd`·`scoped-commits`(구현·커밋),
`code-review`(검증). install.sh 가 설치 시 이들의 존재를 확인해 없으면
경고합니다 — 설치 자체는 계속됩니다.

하드 의존은 아닙니다. 없는 스킬이 쓰이는 단계는 건너뛰거나 그 규율 없이 진행하고,
최종 보고에 명시합니다. 작업 디렉토리가 git repo 가 아니면 작업 브랜치·code-review·
커밋 단계를 생략합니다.

### 왜 이런 구조인가

`opusplan`처럼 세션의 메인 모델이 자동으로 바뀌는 커스텀 조합(`fableplan`)은 Claude Code가 네이티브로 지원하지 않습니다:

- `model` 설정의 alias 목록(`fable`, `opus`, `opusplan` 등)은 하드코딩되어 있어 커스텀 pair를 등록할 수 없습니다.
- hook이나 skill로 실행 중인 세션의 모델을 바꿀 수도 없습니다.

대신 **subagent는 모델을 지정할 수 있다**는 점을 이용해, 플랜과 구현을 각각 모델이 고정된 subagent로 돌립니다:

- `fable-planner`(model: fable) — 코드 탐색과 플랜 작성. 읽기 도구만 갖습니다.
- `opus-builder`(model: opus) — 승인된 플랜의 구현.
- 메인 스레드(세션 모델) — 오케스트레이션, 사용자 확인(플랜 승인·질문 중계), 구현 결과 검증.

세션 모델은 어느 단계에도 관여하지 않으므로 `/model` 설정이나 `settings.json`을 건드릴 필요가 없습니다.

## 설치

```bash
git clone https://github.com/uwonu606/fableplan.git && cd fableplan
bash install.sh              # 전역 설치 (~/.claude) — 모든 프로젝트에서 사용 가능
# 또는
bash install.sh --project    # 특정 프로젝트의 .claude/ 에만 설치
```

설치본은 복사본이라 저장소를 pull하거나 수정해도 자동으로 갱신되지 않습니다. 변경 후에는 install.sh를 다시 실행하세요.

```bash
git pull && bash install.sh
```

제거:

```bash
bash install.sh --uninstall
```

## 사용법

1. `/fableplan 작업 설명` 입력.
2. 플랜이 나오면 검토 후 승인. 승인하는 순간부터 구현은 Opus가 합니다.

동작 확인용 시험:

```
/fableplan 간단한 hello world 스크립트 만들어줘
```

plan mode 진입 → fable-planner 플랜 → 승인 → opus-builder 실행 → 파일 생성까지 이어지면 정상입니다.

## opusplan과의 차이 (제약)

- 메인 루프의 모델이 전환되는 게 아니라 **플랜과 구현을 모델 고정 subagent에 위임**하는 방식입니다. 사용자와 대화하는 주체는 여전히 세션 모델(메인 스레드)입니다.
- 권한 프롬프트(파일 편집, 커맨드 실행 승인)는 평소처럼 사용자에게 뜹니다. plan mode의 수정 차단은 subagent에도 상속됩니다.
- subagent는 사용자에게 직접 질문할 수 없습니다. planner가 결정이 필요한 지점을 만나면 **결정 하나당 질문 하나**를(grilling 규율) 반환하고, 메인 스레드가 사용자에게 물어 답을 중계합니다. 플랜 거부 피드백도 같은 경로로 planner에게 전달됩니다 — 한 홉씩 늘어나는 대신, planner가 탐색한 컨텍스트는 유지됩니다.
- 플랜 비용은 Fable 요금으로 플랜 단계에만 발생합니다. 세션 전체를 Fable로 돌리는 것보다 쌉니다.

## 저장소 구성

```
fableplan/
├── README.md
├── dep-skills.md                 # 의존 스킬 매니페스트 — 설치 경고 목록의 단일 출처
├── install.sh                    # 설치/제거 스크립트
├── skills/fableplan/SKILL.md     # /fableplan 슬래시 커맨드 (워크플로 정의)
└── agents/
    ├── fable-planner.md          # model: fable 지정된 플랜 전용 agent
    └── opus-builder.md           # model: opus 지정된 구현 전용 agent
```
