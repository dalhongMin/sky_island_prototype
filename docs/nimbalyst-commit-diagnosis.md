# Nimbalyst 커밋 제안 오류 진단

확인일: 2026-10-06. 대상: 설치된 Nimbalyst 0.79.1과 이 프로젝트의 현재 Codex 세션. 앱 패키지·로그를 읽고 SQLite를 mode=ro 및 query_only로 조회했다. 앱 코드·설정·DB와 게임 코드는 수정하지 않았다.

## 결론

커밋 실패의 직접 원인은 **도구 호출 ID를 찾는 조회가 최근 메시지 대신 세션의 처음 50개 메시지만 읽는 버그**다. 이후 생성한 제안에는 실제 도구 ID가 저장되지 않아, 화면이 보내는 도구 ID를 서버가 해당 제안으로 식별하지 못한다. Git 명령 실행 이전에 거부된다.

문서 내용·Git 충돌·Git 사용자 정보가 이번 오류의 원인이라는 증거는 없다. 단순 응답 대기나 사용자 미확정으로 설명한 이전 안내는 부정확했다. 실제 로그에는 확정 요청 실패가 남아 있다.

## 확인한 처리 경로

설치 앱의 app.asar에서 읽은 코드:

1. main의 resolveToolUseIdFromMcpRequest는 요청에서 직접 도구 ID를 찾고, 없으면 AgentMessagesRepository.list(sessionId, { limit: 50 })를 호출한다.
2. 이 list는 ORDER BY id ASC LIMIT 50 OFFSET 0이다. 즉, 최근 50개가 아니라 처음 50개다. 별도의 listTail 메서드도 이미 존재한다.
3. findCodexAppServerToolCallId는 조회된 행에서 현재 turnId의 item/started, mcpToolCall, tool 이름을 찾아 실제 호출 ID를 반환한다. 현재 호출이 처음 50개 밖에 있으면 찾지 못한다.
4. handleGitCommitProposal은 ID를 찾지 못하면 git-commit-proposal-시간-난수 형태로 대체하고 toolUseId는 기록하지 않는다.
5. GitCommitProposalWidget은 toolCall.providerToolCallId를 proposalId로 사용한다. 이번 호출들은 exec-… 형태다.
6. git:commit은 resolveGitCommitProposalPromptId(sessionId, proposalId, false)로 정확히 한 제안이 연결되는지 검사한다. 저장된 임의 ID와 화면의 exec-… ID는 일치하지 않아 오류를 던진다. executeGitCommitAcrossRepos는 호출되지 않는다.

요청 로그의 메타데이터에는 callId와 itemId가 있지만 extractToolUseIdFromMcpRequest의 직접 조회 키에는 이 두 키가 없다. 그래서 이번 호출은 메시지 조회에 의존한다. 각 키의 의미가 다를 수 있으므로 무조건 동일한 ID로 취급하는 수정은 별도 검토가 필요하다.

## 실제 세션 DB와 대조

| 제안 시각(KST) | 해당 호출의 표시 메시지 순번 | 저장된 proposalId | toolUseId | 결과 |
| --- | --- | --- | --- | --- |
| 12:37:40 | 38 | exec-3b5d6df8-… | 같은 exec ID | 정상 연결, 이후 취소 |
| 12:40:01 | 61 | git-commit-proposal-1791258001898-7wwv7o | 없음 | 화면의 exec-a4c42f68-…와 불일치 |
| 13:15:35 | 162 | git-commit-proposal-1791260135596-5bl6lq | 없음 | 화면의 exec-cf0a0d35-…와 불일치 |

각 제안이 저장된 시점까지의 실제 행을 읽어 ASC LIMIT 50과 DESC LIMIT 50을 비교했다. 처음 50개 조회는 세 번 모두 첫 호출만 포함한다. 최근 50개 조회에는 두 번째와 세 번째 호출이 각각 포함된다. DB를 수정하거나 커밋을 재실행하지 않고 실패 조건을 확인했다.

메인 로그의 13:01:53, 13:03:28, 13:15:33, 13:16:18에 다음 오류와 동일한 스택이 있다:

```text
Error occurred in handler for 'git:commit':
Cannot identify this exact commit proposal. Refresh the session before answering.
resolveGitCommitProposalPromptId → git:commit handler
```

13:01과 13:03 오류는 장시간 대기 및 이후 중단보다 먼저 발생했다. 호출 중단 때문에만 실패했다고 볼 수 없다.

## 질문 중첩 오류는 별개

12:35:24부터 GitOperationsPanel의 스마트 커밋 메시지 전송(ai:sendMessage)이 Cannot start overlapping Codex question turns로 거부된 기록도 있다. CodexQuestionTurns.begin은 이전 turn이 active인 동안 새 turn 시작을 거부한다.

이 오류는 같은 세션이 실행 중일 때 추가 요청이 들어온 경로의 문제이며, 제안 ID 조회 버그와 직접 같은 원인이라고 확인한 것은 아니다. 로그에는 turn retired도 남아 있어, 모든 대기가 영구적으로 해제되지 않는 상태라고 단정할 수 없다.

## 해결 방향과 범위

- 앱 소스에서 도구 ID 조회를 실제 최근 행 조회(listTail)로 바꾸거나, 해당 turnId와 도구 호출을 직접 조회하는 방식으로 수정해야 한다. 여러 동일 도구 호출이 한 turn에 존재할 때의 모호성도 확인해야 한다.
- 앱 수정 검증은 50개 초과 메시지 세션에서 제안 생성·확정·취소, ID 연결, 중복 확정 및 동시 동일 도구 호출을 포함해야 한다.
- 현재 세션 새로고침이나 앱 재시작만으로 처음 50개 조회가 바뀌지는 않는다. 기존 오류 문구의 새로고침 안내만으로 해결된다고 보장할 수 없다.
- 메시지가 적은 새 세션에서는 같은 제한을 피할 가능성이 있지만, 실제 새 세션 커밋 성공을 이번에 검증하지 않았다. 범위가 섞인 문서 변경을 그대로 전체 파일 커밋해서는 안 된다.
- 설치 앱을 직접 패치하거나 DB의 제안 ID를 변경하는 조치는 하지 않았다. 지정 커밋 도구를 우회한 CLI 커밋도 하지 않았다.

## 근거 위치

- 설치 앱: /Applications/Nimbalyst.app/Contents/Resources/app.asar (package.json 버전 0.79.1).
- main 코드: out/main/index.js의 resolveToolUseIdFromMcpRequest(271020 부근), createPGLiteAgentMessagesStore.list(139945 부근), handleGitCommitProposal(317761 부근), git:commit(284644 부근).
- 위젯 코드: out/renderer/assets/registerExtensionSystem-BxdRel1z.js의 proposalId 계산(191340 부근).
- 로그: [main.log](/Users/mindalhong/Library/Application%20Support/@nimbalyst/electron/logs/main.log:1216), [nimbalyst-debug.log](/Users/mindalhong/Library/Application%20Support/@nimbalyst/electron/nimbalyst-debug.log:286).
- DB: [nimbalyst.sqlite](/Users/mindalhong/Library/Application%20Support/@nimbalyst/electron/sqlite-db/nimbalyst.sqlite). 현재 세션의 제안과 관련 호출 행만 읽기 전용으로 대조했다.

앱 소스와 로그의 줄 번호는 설치 버전에 종속적이다. 새 버전에서는 함수 이름을 기준으로 다시 확인한다. 현재 HEAD는 889065e이고 이번 진단에서도 새 커밋은 생성되지 않았다.
