# Noriter AI Project Plan Log

이 파일은 대화에서 합의된 계획을 누적 기록합니다.
앞으로 어떤 환경/위치에서 어떤 작업을 했는지 추적할 수 있도록 유지합니다.

## 2026-07-09 02:00 (KST)
- 작업 위치: `c:\Users\hoone\OneDrive\noriter-ai.worktrees\agents-project-brief-overview`
- 요청: 프로젝트 간단 개요 정리
- 결과: VS Code extension 구조, 핵심 기능, 기술 스택 요약 완료

## 2026-07-09 02:02 (KST)
- 작업 위치: Copilot 채팅(설계 논의)
- 요청: 서명 없는 Windows 앱 가능 여부 + Dart(Flutter) 전략
- 결과:
  - 단기: TypeScript 재사용 중심(Electron/Tauri) 권장
  - 장기: Flutter 크로스플랫폼 전환 전략 권장
  - 메모: 무서명 배포는 가능하지만 SmartScreen 경고 발생 가능

## 2026-07-09 02:03 (KST)
- 작업 위치: Copilot 채팅(설계 논의)
- 요청: LM Studio 없이 자체 모델 엔진 구동
- 결과:
  - `ModelProvider` 추상화 방향 제시
  - 내장 엔진으로 `llama.cpp` 계열 채택 권장

## 2026-07-09 02:05 (KST)
- 작업 위치: 코드 변경
- 요청:
  - 사용 가능한 LLM 모델 리스트업 기능
  - 계획/작업 기록 파일 누적 저장
- 구현:
  - 사이드바 채팅 `/models` 명령 추가
  - 텔레그램 브리지 `/models` 명령 추가
  - 계획 누적 파일 `.noriter-ai/project-plan-log.md` 생성

## 2026-07-09 02:09 (KST)
- 작업 위치: `c:\Users\hoone\OneDrive\noriter-ai.worktrees\agents-project-brief-overview\dart_platform`
- 요청: Dart 기반 자체 플랫폼 코딩 및 윈도우 무서명 실행 준비
- 구현:
  - `dart_platform/` 신규 추가
  - `/models` 명령 및 OpenAI-compatible 모델 목록 조회 구현
  - 누적 계획 로그 append 기능 구현
  - 무서명 EXE 빌드 명령 문서화
## 2026-07-09 02:15 (KST)
- 작업 위치: `dart_platform\build\`
- 요청: EXE 빌드 (`noriter-ai-0.0.6.exe`)
- 구현:
  - Dart SDK 3.12.2 설치 완료
  - `dart compile exe` 로 Windows 단독 실행 EXE 생성 (7.3 MB, 서명 불필요)
  - 실행 스모크 테스트 통과 (`/exit` 명령 정상 응답)
  - 빌드 결과물: `dart_platform/build/noriter-ai-0.0.6.exe`

