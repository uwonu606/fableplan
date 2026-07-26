# fableplan

Claude Code의 `opusplan`(플랜=Opus, 구현=Sonnet)과 같은 워크플로를 **플랜=Fable, 구현=Opus** 조합으로 쓰게 해주는 skill + agent 세트입니다.

Claude Code 세션 안에서 원할 때만 `/fableplan <작업 설명>` 으로 켭니다.

## 동작 방식

```
> /fableplan 로그인 기능 추가

1. [Fable]  plan mode 진입, 코드 탐색 후 플랜 작성
2. [사용자]  플랜 검토, 승인 (거부하면 피드백 반영해 재플랜)
3. [Opus]   opus-builder subagent가 승인된 플랜을 그대로 구현
4. [Fable]  테스트/빌드 재실행으로 검증, 결과 보고
```

### 왜 이런 구조인가

`opusplan`처럼 세션의 메인 모델이 자동으로 바뀌는 커스텀 조합(`fableplan`)은 Claude Code가 네이티브로 지원하지 않습니다:

- `model` 설정의 alias 목록(`fable`, `opus`, `opusplan` 등)은 하드코딩되어 있어 커스텀 pair를 등록할 수 없습니다.
- hook이나 skill로 실행 중인 세션의 모델을 바꿀 수도 없습니다.

대신 **subagent는 모델을 지정할 수 있다**는 점을 이용합니다. agent 정의(`opus-builder.md`)의 frontmatter에 `model: opus`를 지정해, 플랜 승인 후 구현만 Opus에 위임합니다.

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

1. 세션 모델이 Fable인지 확인 (`/model fable` — 플랜을 Fable이 작성하게 하는 조건).
2. `/fableplan 작업 설명` 입력.
3. 플랜이 나오면 검토 후 승인. 승인하는 순간부터 구현은 Opus가 합니다.

동작 확인용 시험:

```
/fableplan 간단한 hello world 스크립트 만들어줘
```

plan mode 진입 → 승인 → opus-builder 실행 → 파일 생성까지 이어지면 정상입니다.

## opusplan과의 차이 (제약)

- 메인 루프의 모델이 전환되는 게 아니라 **구현을 Opus subagent에 위임**하는 방식입니다. 구현 중 대화의 주체는 여전히 Fable(메인 스레드)입니다.
- 권한 프롬프트(파일 편집, 커맨드 실행 승인)는 평소처럼 사용자에게 뜹니다.
- subagent는 구현 도중 사용자에게 질문할 수 없습니다. 그래서 이 워크플로는 플랜을 구체적으로 승인받는 것을 전제로 하며, 모호한 결정이 남아 있으면 skill이 구현 시작 전에 먼저 물어봅니다.
- 플랜 단계의 모델은 "현재 세션 모델"입니다. 세션 모델이 Fable이 아니면 그 모델로 플랜이 작성됩니다.

## 저장소 구성

```
fableplan/
├── README.md
├── install.sh                    # 설치/제거 스크립트
├── skills/fableplan/SKILL.md     # /fableplan 슬래시 커맨드 (워크플로 정의)
└── agents/opus-builder.md        # model: opus 지정된 구현 전용 agent
```
