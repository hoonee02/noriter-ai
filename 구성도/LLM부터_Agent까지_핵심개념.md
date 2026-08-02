# 「LLM부터 Agent까지」 — 핵심 개념 노트

> 원본: WikiDocs "LLM부터 Agent까지" (Da Sol) — https://wikidocs.net/book/17206
> ※ 이 책은 파이썬 입문부터 Claude Code 실무, 딥러닝 수학, 각종 모델 파인튜닝, RAG/LangGraph/Agent,
> 서빙·DB·크롤링 도구, 주간 AI 뉴스, 논문 리뷰까지 아우르는 저자 개인의 학습 노트/위키에 가까운
> 매우 방대하고 이질적인 구성이라, 절별로 재구성하지 않고 전체 주제 지도만 정리했습니다.
> 세부 내용은 원본 링크에서 관심 있는 챕터를 직접 확인하는 것을 권합니다.

## 이 책의 성격

저자 소개에 따르면 "파이썬을 처음 독학할 때부터 지금 Claude Code로 제품을 만드는 과정까지, 그
사이에 필요했던 내용을 모두 다룬다"는 목표로 계속 갱신되는 개인 지식 위키다. 하나의 일관된
커리큘럼이라기보다, 시기별로 저자가 학습·정리한 주제를 폴더처럼 계속 이어 붙인 구조에 가깝다.
독자에게도 "필요한 파트로 가서 공부하라"고 안내하는 것이 이 성격을 잘 보여준다.

## 전체 주제 지도 (대분류 기준)

| 대분류 | 다루는 주제 (예시) |
|---|---|
| 00. Claude Code | 기본/커스텀/MCP 명령어, 모드, 서브에이전트, Agent Team, Skills, Hooks, 권한 모드, Plugins/Marketplace, Cowork, worktree, Loop Engineering(8편 연재) 등 — 사용자가 최초 링크한 절(01번)이 이 챕터에 속함 |
| 01. 파이썬 기초 및 중급편 | input/print/logging부터 자료형, 리스트/튜플/집합/딕셔너리, 반복문·조건문, 함수와 스코프, 파일 입출력, 예외 처리까지 프로그래밍 입문 커리큘럼 |
| 02. 딥러닝 기초이론 | BM25, 미분·시그마·테일러전개 같은 수학 기초, 활성화함수, 확률분포, 역전파, MLE, 손실함수, Optimizer, 정규화 기법, 양자화 |
| 03. Fine-Tuning | LLM/VLM/RL/이미지/STT/TTS 등 모달리티별 파인튜닝 실습 (Gemma, Whisper, Qwen3-TTS, LLaMA-Factory 등 구체 모델 다수) |
| 04. Pretraining | 대형 LLM 사전학습 관련 자료(Smol Training Playbook 번역 등) |
| 05. LLM API 사용법 | Claude/OpenAI/Google Studio API 사용법, Claude Agent SDK |
| 07. RAG | Obsidian 기반 RAG, 가드레일 |
| 09. LangGraph | LangGraph 개념 소개 |
| 10. Agent | 에이전트란 무엇인가 |
| 11. Serving | vLLM, Signal-Decision Driven Architecture 등 서빙 인프라 |
| 12. 데이터베이스와 SQL | SQLite |
| 13. 다양한 툴 | PDF 전처리, 가상환경(uv), 대용량 다운로드(rclone), 크롤링(Firecrawl, Tavily), 에이전트 학습 프레임워크 |
| 15. Docker | 도커 기초 |
| 17. Blog | 주간 AI 뉴스, 모델 성능/스케일링 관련 단상 |
| 18. 논문리뷰 | Transformer(Attention is All You Need) 등 논문 리뷰 |

## 사용자가 링크한 절의 위치

`https://wikidocs.net/317831` (01) 클로드 코드 기본, 커스텀, MCP 명령어)은 이 책의 **00. Claude Code**
챕터 안에 있으며, 이 챕터는 Claude Code 실무 활용(기본 명령어부터 서브에이전트, Skills, MCP, Hooks,
Plugins, Loop Engineering까지 20개 안팎의 절)을 다루는 부분이다. 이 챕터만 별도로 더 깊이 정리하고
싶다면 범위를 좁혀 다시 요청하면 된다.

## 우리 `구성도/` 문서들과 맞닿는 지점

- **00장 Claude Code**(서브에이전트, MCP, Skills, Hooks)는 [하이브리드_에이전트_RAG.md](하이브리드_에이전트_RAG.md)의
  도구함(Tool Definition)·오케스트레이션 개념, [에르메스_에이전트_핵심개념.md](에르메스_에이전트_핵심개념.md)·
  [딥에이전트_핵심개념.md](딥에이전트_핵심개념.md)에서 다룬 서브에이전트/MCP 연동과 실무 도구 수준에서
  직접 맞닿는다.
- **07장 RAG**(Obsidian-RAG)는 [구성도.md](구성도.md)·[LLM위키_완벽가이드/](LLM위키_완벽가이드/)에서
  다룬 "위키를 RAG의 지식 소스로 쓰는" 아이디어와 같은 방향이다.
- **09장 LangGraph·10장 Agent**는 이미 전체를 정리해 둔 [langgraph_가이드북/](langgraph_가이드북/)의
  개론 격에 해당하는 짧은 절로 보인다.

## 결론

이 책은 하나의 완결된 가이드북이라기보다, Claude Code 실무·파이썬 기초·딥러닝 이론·파인튜닝·
RAG/에이전트·인프라 도구·주간 뉴스·논문 리뷰가 뒤섞인 "저자의 성장 로그"에 가깝다. 우리가 지금
쌓아온 `구성도/` 폴더의 관심사(LLM 위키, RAG, 에이전트 아키텍처)와 직접 맞닿는 부분은 00장(Claude
Code), 07장(RAG), 09~10장(LangGraph/Agent) 정도이며, 나머지(파이썬 기초, 딥러닝 수학, 모달리티별
파인튜닝, 인프라 도구, 뉴스/논문)는 별개의 학습 트랙에 가깝다. 특정 챕터를 더 자세히 보고 싶다면
범위를 좁혀 다시 요청하면 된다.
