# Part 3. 개발 환경 설정

> 원본: [neo4j] GraphRAG 완전 정복 - 초보자를 위한 지식 그래프 기반 RAG 시스템
> https://wikidocs.net/book/18976

## 3-1. 준비물 체크리스트
원본: https://wikidocs.net/319199

- 지원 OS: Windows 10/11(64비트), macOS 11+, Ubuntu 20.04+ 등. 권장 사양은 RAM 16GB+/저장공간 20GB+/CPU 4코어+, 최소 사양은 RAM 8GB/저장공간 10GB/CPU 2코어. Neo4j + Python을 동시에 띄우면 메모리 소비가 크므로 RAM이 특히 중요하다고 강조.
- 필수 계정: OpenAI(전화번호 인증 필요, 실습 전체 예상 비용 약 $5~10), 선택 계정: Neo4j(클라우드 Aura 사용 시에만 필요). 이 책은 로컬 실습이 쉬운 **Neo4j Desktop**을 기준으로 진행한다(Aura와 비교해 계정 없이 자유롭게 실험 가능).
- 설치 소프트웨어: 필수 - Python 3.11+, uv(패키지 매니저), Neo4j Desktop / 권장 - VS Code, Git.
- 설치 순서: Python → uv → Neo4j Desktop → API 키 설정의 4단계로 구성.
- 진행 전 체크리스트: OS/RAM/저장공간 확인, OpenAI 계정 가입 완료, 안정적 인터넷 연결.

## 3-2. Python 환경 설정
원본: https://wikidocs.net/319200

- `python --version`으로 기존 설치 확인, 3.11 미만이면 새로 설치 권장(공식 인스톨러 시 Windows에서 "Add Python to PATH" 체크 필수, macOS는 Homebrew도 가능).
- **uv**: Rust로 작성된 차세대 Python 패키지 매니저로 기존 pip 대비 10~100배 빠르다고 소개되며, 별도 venv 없이 프로젝트별 가상환경을 자동 관리한다. 설치는 OS별 원라이너 스크립트(`irm ... | iex` / `curl ... | sh`).
- 가상환경이 필요한 이유: 프로젝트마다 요구하는 라이브러리 버전이 달라 충돌이 발생할 수 있음을 그림으로 설명 — uv가 이를 프로젝트 단위로 자동 격리.
- 프로젝트 생성 흐름: `mkdir graphrag-tutorial && cd graphrag-tutorial` → `uv init`(pyproject.toml, .python-version 등 생성) → `uv python pin 3.12` → 패키지 설치.
- 핵심 의존성 설치 명령 패턴:
```bash
uv add langchain langchain-openai langchain-community
uv add neo4j langchain-neo4j
uv add python-dotenv
```
- 즉 이 책의 스택은 LangChain 생태계(langchain, langchain-openai, langchain-community, langchain-neo4j) + 공식 neo4j 드라이버 + python-dotenv 조합.

## 3-3. Neo4j 설치와 첫 연결
원본: https://wikidocs.net/319202

- Neo4j Desktop을 공식 다운로드 페이지에서 이름/이메일 입력 후 받고, 발급되는 Activation Key를 첫 실행 시 입력해야 한다(반드시 별도 저장 필요).
- 데이터베이스 생성 흐름: 프로젝트 생성("GraphRAG Tutorial") → "Add" → "Local DBMS" 선택 → 이름/비밀번호/버전(5.x) 지정 → Start(기동에 30초~1분 소요) → Open으로 Neo4j Browser 접속.
- **APOC 플러그인**: Neo4j 기능 확장 라이브러리로, 이 책에서 다루는 `neo4j-graphrag` 패키지의 `SimpleKGPipeline`(문서로부터 지식 그래프 자동 구축) 기능에 필수. 단, 기본 연결·쿼리·CRUD는 APOC 없이도 동작함을 명시. Neo4j Desktop에서는 DB를 중지한 뒤 Plugins 탭에서 클릭 한 번으로 설치 가능하며, `RETURN apoc.version()` 쿼리로 설치를 검증한다. Docker 환경에서는 환경 변수로 APOC을 활성화하는 방식도 소개된다.
- 이 절 후반부(트렁케이션된 부분)에서는 Neo4j Browser의 기본 조작과 Python(`neo4j` 드라이버)에서의 연결 테스트 코드, 테스트 데이터 추가/정리까지 다룬다 — 다음 Part5에서 Cypher를 본격적으로 배우기 전 준비 단계.

## 3-4. API 키 설정과 첫 테스트
원본: https://wikidocs.net/319203

- OpenAI API 키 발급 절차: platform.openai.com 로그인 → API keys 메뉴 → "Create new secret key" → 키는 생성 시 단 한 번만 노출되므로 즉시 안전하게 복사 저장(재노출 불가, 분실 시 재발급 필요, 절대 공개 저장소에 올리지 말 것).
- 키 관리 원칙: 코드에 직접 하드코딩하지 않고 `.env` 파일 + `python-dotenv`로 로드하는 방식을 "올바른 방법"으로 제시. `.env` 예시 구조:
```env
OPENAI_API_KEY=sk-proj-...
NEO4J_URI=bolt://localhost:7687
NEO4J_USERNAME=neo4j
NEO4J_PASSWORD=password123
```
- `.gitignore`에 `.env`, `*.pyc`, `__pycache__/`, `.venv/`를 추가해 키 유출을 방지.
- 검증 스크립트 3종을 순서대로 실행: (1) `ChatOpenAI(model="gpt-4o-mini")`로 LLM 호출 테스트, (2) `OpenAIEmbeddings(model="text-embedding-3-small")`로 임베딩 생성 테스트(결과 벡터 차원 1536 확인), (3) Neo4j 드라이버 + LangChain-Neo4j 통합까지 포함한 종합 테스트(`test_all.py`)로 Neo4j 연결/LLM/임베딩/LangChain-Neo4j 4가지가 모두 통과하는지 확인.
- 마지막에 흔한 오류(OpenAI API 오류, Neo4j 연결 오류)에 대한 트러블슈팅 가이드로 마무리하며, 여기까지 완료되면 Part4의 벡터 검색 실습으로 넘어갈 준비가 끝난다.

---
이전: [Part2_지식그래프_기초.md](./Part2_지식그래프_기초.md) · 다음: [Part4_벡터검색.md](./Part4_벡터검색.md)
