---
name: fableplan
description: opusplan의 커스텀 버전 — 플랜은 Fable subagent(fable-planner)가 작성하고, 구현은 Opus subagent(opus-builder)가 수행하는 하이브리드 워크플로. 사용자가 /fableplan <작업 설명> 을 입력하면 사용한다.
---

# fableplan 워크플로

opusplan(플랜=Opus, 구현=Sonnet)과 같은 구조를 "플랜=Fable, 구현=Opus"로 수행한다.
세션 모델과 무관하게 동작한다: 플랜은 `fable-planner` agent(model: fable)가, 구현은 `opus-builder` agent(model: opus)가 담당하고, 메인 스레드는 오케스트레이션·사용자 확인·검증만 맡는다. 플랜이나 구현을 메인 스레드에서 직접 수행하지 않는다.

작업 설명: $ARGUMENTS

## Agent 호출 규약 — 절차보다 먼저 읽을 것

이 워크플로는 subagent 를 여러 번 왕복시킨다(질문 답변, 플랜 거부 피드백, 검증 실패 수정).
왕복이 실제로 작동하려면 아래 다섯 가지를 지켜야 한다. 어기면 결과가 조용히 사라지고,
"agent 가 일을 안 했다"고 오인해 재실행하게 된다.

1. **`name` 을 넘기지 않는다.**
   Agent tool 에 `name` 을 주면 그 subagent 는 메일박스 기반 teammate 로 전환되고,
   **최종 텍스트가 자동 반환되지 않는다** — 스스로 `SendMessage({to: "main"})` 을 부르지
   않는 한 `idle_notification` 상태 핑만 온다. 이름 없는 agent 도 후속 메시지를 받을 수
   있으므로(4번), 이 워크플로에 이름이 필요한 자리는 없다.

2. **spawn 결과의 `agentId` 를 기록해 둔다.**
   이름 없는 agent 의 유일한 주소다. `ListAgents` 에는 **종료된 in-process subagent 가 뜨지
   않으므로**, agentId 를 놓치면 그 agent 를 다시 이을 방법이 없다 — 이미 탐색한 컨텍스트를
   통째로 버리고 새로 스폰해야 한다.

3. **모든 agent 호출은 비동기다.** `run_in_background` 같은 파라미터는 없다.
   Agent tool 은 즉시 반환하고, 실제 결과는 나중에 `<task-notification>` 의 `<result>` 로 온다.
   그 알림이 오기 전에는 결과를 추측하거나 사용자에게 보고하지 않는다.

4. **후속 메시지는 `SendMessage({to: "<agentId>"})`.**
   답장 역시 `<task-notification>` 의 `<result>` 에 자동으로 실려 온다. 재촉할 필요 없고,
   agent 쪽에 "SendMessage 로 회신하라"고 지시해서도 안 된다 — 중복 전달이 된다.

5. **spawn 결과의 `output_file` 을 Read 하지 않는다.**
   subagent 의 전체 JSONL transcript 라서 컨텍스트가 넘친다. 결과는 `<result>` 에 이미 있다.

## 절차

### 1. 플랜 단계 (fable-planner agent)

- 작업 설명이 비어 있으면 사용자에게 무엇을 만들지 물어본다.
- plan mode 가 아니면 `EnterPlanMode` 를 호출해 plan mode 로 진입한다(사용자 승인이 필요하다).
  subagent 는 부모의 권한 모드를 상속하므로 planner 의 파일 수정도 함께 차단된다.
- plan mode 진입 시 시스템이 Explore/Plan agent 를 쓰는 기본 플랜 절차를 주입한다.
  이 워크플로에서는 그 절차를 따르지 않고 `fable-planner` 하나만 쓴다.
- `fable-planner` 를 실행한다: Agent tool, `subagent_type: "fable-planner"`, **`name` 없이**.
  프롬프트에 작업 설명 전문과 작업 디렉토리 절대 경로를 담는다. **반환된 agentId 를 기록한다.**
- 완료 알림을 기다린 뒤 `<result>` 를 처리한다:
  - **`PLAN` 으로 시작**: 첫 줄 `PLAN` 을 뺀 나머지 전문을 plan mode 가 지정한 플랜 파일에
    그대로 옮겨 적은 뒤 `ExitPlanMode` 를 호출한다. `ExitPlanMode` 는 플랜을 인자로 받지 않고
    그 파일을 읽어 사용자에게 보여주므로, 옮겨 적지 않으면 승인 화면에 플랜이 뜨지 않는다.
    옮길 때 요약·재작성하지 않는다 — 전사(轉寫)만 허용된다.
  - **`QUESTIONS` 로 시작**: `AskUserQuestion` 으로 사용자에게 묻고, 답 전문을
    `SendMessage({to: "<planner agentId>"})` 로 전달한 뒤 다음 알림을 기다린다.
  - **둘 다 아님**: 메인 스레드가 형식을 맞춰 주지 않는다. `SendMessage` 로 planner 에게
    규정된 형식(`PLAN` 또는 `QUESTIONS`)으로 다시 반환하라고 요구한다.
- 승인이 거부되면: 피드백 **전문**을 `SendMessage({to: "<planner agentId>"})` 로 전달해
  수정된 플랜을 받고, 플랜 파일에 다시 전사한 뒤 승인을 재요청한다.
  메인 스레드가 플랜을 직접 고치지 않는다 — 고치는 순간, 실제로 승인돼 빌더에게 넘어가는
  최종 플랜을 Fable 이 아닌 세션 모델이 쓴 게 된다.

### 2. 구현 단계 (opus-builder agent)

- 플랜이 승인되면 즉시 `opus-builder` 를 실행한다:
  Agent tool, `subagent_type: "opus-builder"`, **`name` 없이**. **반환된 agentId 를 기록한다.**
- 프롬프트에 다음을 전부 담는다: 승인된 플랜 전문(요약 금지), 작업 디렉토리 절대 경로,
  planner 가 플랜에 명시한 관련 파일 경로·재사용할 코드 위치·주의사항.
- subagent 는 사용자에게 질문할 수 없으므로 프롬프트에 모호함이 남지 않게 전달한다.
  플랜에 없는 결정사항이 남아 있다면 agent 실행 전에 사용자에게 먼저 확인한다.
- 완료 알림을 기다린다. 알림 전에 진행 상황을 추측해 보고하지 않는다.

### 3. 검증·보고 단계 (메인 스레드)

- `<result>` 의 변경 파일 목록과 검증 결과를 확인한다.
- 플랜의 검증 절차를 메인 스레드에서 **직접 재실행한다** (테스트/빌드/실행).
  빌더의 자기 보고를 검증으로 갈음하지 않는다.
- 실패가 있으면: 실패 내용을 정리해 `SendMessage({to: "<builder agentId>"})` 로 수정을 위임한다.
  새로 스폰하면 구현 컨텍스트를 잃고, 커밋·PR 같은 부수효과가 중복될 수 있다.
- 최종 보고: 무엇이 바뀌었고, 검증이 어떻게 통과했는지 사용자에게 요약한다.

## 규칙

- 플랜 승인 전에는 어떤 파일도 수정하지 않는다. 단, plan mode 가 하드 차단하는 것은 Edit/Write 뿐이다 —
  변경성 Bash(rm, git commit 등)는 차단이 아니라 사용자 승인 프롬프트로 넘어가므로 승인되면 실행될 수 있다.
  그래도 이 워크플로에서는 승인 전에 변경성 Bash 를 호출하지 않으며, planner 에게도 시키지 않는다.
- agent 간에 플랜·피드백·답변을 전달할 때 축약하지 않는다 — 원문 그대로.
- opus-builder 가 플랜 범위를 벗어난 변경을 보고하면, 사용자에게 알리고 되돌릴지 확인한다.
- **agent 가 결과 없이 조용하면 재실행하지 말고 산출물로 확인한다.** `idleReason: "available"` 은
  실패가 아니라 용량 상태이고, 작업은 대개 이미 끝나 있다. 파일시스템·git·이슈 트래커로 실제 상태를
  본 뒤, 정말 미완이면 `SendMessage` 로 잇는다. 무턱대고 재실행하면 커밋이 두 번 얹히고
  이슈 코멘트와 PR 이 중복 생성된다.
- `fable-planner` 나 `opus-builder` agent 를 찾을 수 없으면(설치 누락) 메인 스레드가 대신 플랜을
  작성하거나 구현하지 말고, install.sh 재실행이 필요하다고 사용자에게 알린다.
- 워크트리에서 작업해야 하면 **플랜 안에 워크트리 생성 절차를 넣는다.** Agent tool 의
  `isolation: "worktree"` 는 쓰지 않는다 — 변경이 없으면 자동 삭제되고, 빌더가 push·PR 까지
  해야 하는 이 워크플로와 수명이 맞지 않는다.
