---
name: fableplan
description: opusplan의 커스텀 버전 — 플랜은 Fable subagent(fable-planner)가 작성하고, 구현은 Opus subagent(opus-builder)가 수행하는 하이브리드 워크플로. 사용자가 /fableplan <작업 설명> 을 입력하면 사용한다.
---

# fableplan 워크플로

opusplan(플랜=Opus, 구현=Sonnet)과 같은 구조를 "플랜=Fable, 구현=Opus"로 수행한다.
세션 모델과 무관하게 동작한다: 플랜은 `fable-planner` agent(model: fable)가, 구현은 `opus-builder` agent(model: opus)가 담당하고, 메인 스레드는 오케스트레이션·사용자 확인·검증만 맡는다. 플랜이나 구현을 메인 스레드에서 직접 수행하지 않는다.

작업 설명: $ARGUMENTS

## 절차

1. **플랜 단계 (fable-planner agent)**
   - 작업 설명이 비어 있으면 사용자에게 무엇을 만들지 물어본다.
   - plan mode가 아니면 `EnterPlanMode`를 호출해 plan mode로 진입한다. subagent는 부모의 권한 모드를 상속하므로 planner의 파일 수정도 함께 차단된다.
   - `fable-planner` agent를 실행한다: Agent tool, `subagent_type: "fable-planner"`, `run_in_background: false`. 프롬프트에 작업 설명 전문과 작업 디렉토리 절대 경로를 담는다.
   - 반환값 처리:
     - `PLAN`으로 시작하면: 플랜 전문 그대로 `ExitPlanMode`로 사용자 승인을 요청한다 (요약·재작성 금지).
     - `QUESTIONS`로 시작하면: `AskUserQuestion`으로 사용자에게 묻고, 답을 `SendMessage`로 planner에게 전달해 플랜을 받는다.
   - 승인이 거부되면: 피드백 전문을 `SendMessage`로 planner에게 전달해 수정된 플랜을 받고, 다시 승인을 요청한다. 메인 스레드가 플랜을 직접 고치지 않는다 — 고치는 순간, 실제로 승인돼 빌더에게 넘어가는 최종 플랜을 Fable이 아닌 세션 모델이 쓴 게 된다.

2. **구현 단계 (opus-builder agent)**
   - 플랜이 승인되면 즉시 `opus-builder` agent를 실행한다:
     - Agent tool, `subagent_type: "opus-builder"`, `run_in_background: false`
     - 프롬프트에 다음을 전부 담는다: 승인된 플랜 전문(요약 금지), 작업 디렉토리 절대 경로, planner가 플랜에 명시한 관련 파일 경로·재사용할 코드 위치·주의사항
   - subagent는 사용자에게 질문할 수 없으므로, 프롬프트에 모호함이 남지 않게 전달한다. 플랜에 없는 결정사항이 남아 있다면 agent 실행 전에 사용자에게 먼저 확인한다.

3. **검증·보고 단계 (메인 스레드)**
   - agent가 반환한 변경 파일 목록과 테스트 결과를 확인한다.
   - 플랜의 검증 절차를 메인 스레드에서 직접 재실행한다 (테스트/빌드/실행).
   - 실패가 있으면: 실패 내용을 정리해 `opus-builder`에게 수정 작업으로 다시 위임한다 (SendMessage로 기존 agent를 잇거나 새로 실행).
   - 최종 보고: 무엇이 바뀌었고, 검증이 어떻게 통과했는지 사용자에게 요약한다.

## 규칙

- 플랜 승인 전에는 어떤 파일도 수정하지 않는다. 단, plan mode가 하드 차단하는 것은 Edit/Write뿐이다 — 변경성 Bash(rm, git commit 등)는 차단이 아니라 사용자 승인 프롬프트로 넘어가므로 승인되면 실행될 수 있다. 그래도 이 워크플로에서는 승인 전에 변경성 Bash를 호출하지 않으며, planner에게도 시키지 않는다.
- agent 간에 플랜·피드백·답변을 전달할 때 축약하지 않는다 — 원문 그대로.
- opus-builder가 플랜 범위를 벗어난 변경을 보고하면, 사용자에게 알리고 되돌릴지 확인한다.
- 같은 이유로, `fable-planner` agent를 찾을 수 없으면(설치 누락) 메인 스레드가 대신 플랜을 작성하지 말고, install.sh 재실행이 필요하다고 사용자에게 알린다.
