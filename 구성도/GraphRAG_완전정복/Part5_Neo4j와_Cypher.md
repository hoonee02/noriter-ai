# Part 5. Neo4j와 Cypher 기초

> 원본: [neo4j] GraphRAG 완전 정복 - 초보자를 위한 지식 그래프 기반 RAG 시스템
> https://wikidocs.net/book/18976

## 5-1. Neo4j Browser 탐험
원본: https://wikidocs.net/319213

- Neo4j Browser는 Neo4j Desktop과 함께 제공되는 웹 UI(`http://localhost:7474`)로, Cypher 쿼리 실행·그래프 시각화·DB 상태 확인을 한 화면에서 처리한다. 인터페이스는 사이드바(스키마/저장 스크립트), 에디터(쿼리 입력), 결과 영역(그래프/테이블/JSON 보기), 상태 표시줄 4개 영역으로 구성.
- 학습용 샘플 데이터로 `:play movies` 명령을 실행해 영화-배우-감독 그래프(Movie/Person 노드, ACTED_IN/DIRECTED 등 관계)를 로드하는 것으로 실습이 시작된다.
- 데이터 파악용 기본 쿼리 패턴: 전체 노드/관계 수 세기(`MATCH (n) RETURN count(n)`), 라벨별 개수 집계, `MATCH (p:Person)-[r:ACTED_IN]->(m:Movie) RETURN p, r, m LIMIT 25`로 일부를 그래프 뷰로 시각화(드래그로 이동, 더블클릭으로 관계 확장 등 조작 가능).
- 사이드바의 Node Labels/Relationship Types 섹션에서 DB 전체 스키마(Movie, Person 라벨 / ACTED_IN, DIRECTED, PRODUCED, WROTE, FOLLOWS, REVIEWED 등 관계 유형)를 한눈에 확인할 수 있다.
- 실습 문제로 특정 배우의 출연작 조회, 특정 영화의 출연진 조회, "감독이면서 배우인 인물" 찾기 등을 다루며 다음 절(Cypher 문법 정식 학습)로 연결된다.

## 5-2. Cypher 첫걸음 - 읽기
원본: https://wikidocs.net/319215

- Cypher 쿼리의 기본 골격은 `MATCH (패턴) WHERE 조건 RETURN 결과` — SQL의 SELECT/JOIN/WHERE에 대응하지만 패턴을 그래프 모양 그대로 표현하는 것이 특징.
- 노드는 `(변수:라벨 {속성: 값})` 형태로, 관계는 `-[:관계타입]->` 화살표로 표기하며 방향(`->`, `<-`, 무방향 `-`)을 명시할 수 있다. 관계에도 `[r:ACTED_IN]`처럼 변수를 부여해 `type(r)`로 관계 유형을 조회 가능.
- `WHERE`로 속성 비교(`m.released > 2000`), 문자열 검색(`CONTAINS`, `STARTS WITH`), `AND`/`OR` 복합 조건을 적용한다.
- **다단계 관계 탐색**이 Cypher의 핵심 강점: `(tom)-[:ACTED_IN]->(m)<-[:ACTED_IN]-(coActor)` 같은 패턴 하나로 "톰 행크스와 같은 영화에 출연한 배우"(2홉)를 찾고, 체인을 더 이어붙이면 3홉 이상의 탐색도 가능 — Part2-3에서 설명한 "다중 홉 추론"을 실제 쿼리로 구현하는 대목.
- 집계 함수 `count()`, `collect()` 등으로 "배우별 출연작 수", "배우별 출연작 목록"과 같은 집계 질의를 작성한다.
- 실습 문제로 최다 작품 감독 찾기, 배우 겸 감독 찾기, 두 배우의 공통 출연작 찾기를 다루며 읽기(MATCH/WHERE/RETURN) 문법을 체화시킨다.

## 5-3. Cypher로 데이터 만들기
원본: https://wikidocs.net/319216

- 데이터 쓰기의 4대 명령: `CREATE`(무조건 신규 생성, 중복 가능), `MERGE`(있으면 매칭·없으면 생성, 중복 방지 — 일반적으로 더 안전해 권장), `SET`(속성 추가/변경, 라벨 추가도 가능), `DELETE`/`DETACH DELETE`(노드·관계 삭제, DETACH DELETE는 연결된 관계까지 함께 제거하므로 주의).
- `CREATE`는 노드 단독 생성뿐 아니라 `CREATE (p:Person)-[:DIRECTED]->(m:Movie)`처럼 노드와 관계를 한 문장으로 동시에 생성할 수 있다.
- `MERGE`의 `ON CREATE SET` / `ON MATCH SET` 절로 "새로 만들어질 때만" 또는 "기존 노드가 매칭됐을 때만" 다른 속성을 세팅하는 분기 처리가 가능(예: 생성 시각 vs 마지막 접속 시각 구분 기록).
- 노드는 여러 라벨을 동시에 가질 수 있다(예: `Person:King`, `Person:Scientist`처럼 다중 라벨로 분류 체계를 표현).
- 실습으로 세종대왕/장영실/신숙주 등 한국 역사 인물 노드를 직접 CREATE하고 관계로 연결해 미니 지식 그래프를 만들어보는 과정이 이어지며, 이는 Part6의 "지식 그래프 스키마 설계·수동 구축"으로 바로 연결되는 준비 단계다.

## 5-4. Python에서 Neo4j 사용
원본: https://wikidocs.net/319217

- Python에서 Neo4j를 다루는 두 방식을 병행 소개: (1) 공식 `neo4j` 드라이버 — 저수준 제어가 필요할 때, (2) `langchain-neo4j`의 `Neo4jGraph` — LangChain 기반 AI 앱 개발에 최적화.
- 공식 드라이버 기본 패턴:
```python
driver = GraphDatabase.driver(URI, auth=(user, password))
driver.verify_connectivity()
with driver.session() as session:
    result = session.execute_read(query_fn, **params)  # 읽기
    session.execute_write(write_fn, **params)           # 쓰기
```
`execute_read`는 읽기 전용(복제본 활용 가능, 더 빠름), `execute_write`는 트랜잭션이 보장되는 쓰기용으로 명확히 구분해 사용한다. 쿼리 파라미터는 `$변수` 형태의 바인딩 파라미터로 전달해 SQL 인젝션 유사 문제를 방지.
- `langchain_neo4j.Neo4jGraph`는 연결 후 `graph.schema`로 DB 스키마 전체(라벨/관계/속성 목록)를 자동 파악해 문자열로 반환하며, `graph.query("...")`로 Cypher를 바로 실행한다. 이 `schema` 속성은 이후 Part8의 Text2Cypher(자연어→Cypher 변환)에서 LLM에게 스키마 맥락을 제공하는 용도로 재사용된다.
- 실습은 이전 절에서 만든 한국 역사 인물 그래프를 Python 코드로 재구성하고 탐색하는 것으로 마무리하며, 연결 정보(URI/계정/비밀번호)는 3-4에서 만든 `.env` + `python-dotenv` 방식으로 관리할 것을 재차 권장한다.

---
이전: [Part4_벡터검색.md](./Part4_벡터검색.md) · 다음: [Part6_지식그래프_만들기.md](./Part6_지식그래프_만들기.md)
