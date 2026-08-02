# Part 6. 첫 번째 지식 그래프 만들기

> 원본: [neo4j] GraphRAG 완전 정복 - 초보자를 위한 지식 그래프 기반 RAG 시스템
> https://wikidocs.net/book/18976

## 6-1. 지식 그래프 스키마 설계
원본: https://wikidocs.net/319219

- 스키마는 "어떤 엔티티가 있고, 어떤 속성을 가지며, 엔티티 간에 어떤 관계가 있는지"를 미리 정의한 설계도이며, 좋은 그래프 구축의 첫걸음으로 강조된다.
- 설계 프로세스 5단계: 도메인 이해 → 엔티티 유형 정의 → 속성 정의 → 관계 유형 정의 → 제약조건 설정.
- 조선시대 역사를 예제 도메인으로 삼아 엔티티 유형(Person/Achievement/Organization/Era/Event)과 각 유형의 속성(Person: name·born·died·role·description 등)을 정의하는 과정을 시연한다.
- 관계 유형 설계 원칙: 대문자+언더스코어 네이밍(예: `ACTED_IN`), 동사형 명명(`CREATED`), 방향을 명확히(시작 엔티티→끝 엔티티) — 예시로 `CREATED`(Person→Achievement), `ESTABLISHED`(Person→Organization), `WORKED_AT`, `COLLABORATED_WITH`, `RULED_DURING`, `PARTICIPATED_IN` 등을 제시.
- Neo4j에서 실제 스키마를 점검하는 시스템 프로시저: `CALL db.schema.visualization()`(스키마 그래프 시각화), `CALL db.labels()`/`db.relationshipTypes()`(라벨·관계 유형 목록 조회).
- **제약조건(Constraint)**: `CREATE CONSTRAINT ... FOR (p:Person) REQUIRE p.name IS UNIQUE`로 이름 중복 방지, `REQUIRE p.name IS NOT NULL`로 필수 속성 강제. 제약조건은 데이터 중복 방지·필수값 보장·자동 인덱스 생성을 통한 성능 향상 효과가 있다고 설명.
- 좋은 스키마의 4대 특징: 단순함(불필요한 복잡성 배제), 일관성(네이밍 규칙 통일), 확장성(새 유형 추가 용이), 질문 지향(답해야 할 질문을 먼저 고려하고 역산해 설계).

## 6-2. 수동으로 지식 그래프 구축
원본: https://wikidocs.net/319220

- 6-1에서 설계한 스키마를 실제 데이터로 채우는 실습. 세종대왕/장영실/집현전 학자(성삼문·박팽년)에 대한 문장을 바탕으로 Person 노드, Achievement 노드(훈민정음·앙부일구·자격루·측우기), Organization 노드(집현전)를 CREATE로 직접 생성한다.
- 관계 생성 예: 세종대왕 `-[:CREATED {year:1443}]->` 훈민정음, 세종대왕 `-[:ESTABLISHED]->` 집현전, 장영실의 각 발명품에 대한 관계, 학자들과 집현전의 소속 관계, 학자들과 훈민정음 창제의 참여 관계 등을 순서대로 MATCH+CREATE로 연결.
- 그래프 완성 후 시각화(`MATCH (n) RETURN n`류)와 세종대왕 중심의 1~2홉 확장 탐색 쿼리로 결과를 확인한다.
- 구축한 그래프로 실제 질문에 답하는 4가지 예시 질의를 실행: "세종대왕의 업적은?", "집현전 학자는 누구?", "장영실이 발명한 것은?", 그리고 다단계 추론이 필요한 "훈민정음 창제에 참여한 사람들은?"(세종대왕과 집현전 학자를 모두 연결해야 답이 나오는 질문) — 이는 Part1-3에서 설명한 다중 홉 추론이 실제로 동작하는 것을 보여주는 대목.
- 마지막으로 동일한 그래프 구축을 Cypher 대신 Python(`neo4j` 드라이버 또는 `Neo4jGraph`)으로도 수행할 수 있음을 보여주며, 수동 구축의 한계(정확하지만 확장성 없음, 문서가 많아지면 비현실적)를 다음 절의 동기로 제시한다.

## 6-3. 문서에서 자동으로 그래프 생성
원본: https://wikidocs.net/319221

- 수동 구축은 정확도는 높지만 문서량이 많아지면 비현실적이므로, LLM을 이용한 **자동 엔티티/관계 추출**로 지식 그래프를 대량 생성하는 방법을 다룬다.
- **방법 1: LangChain 직접 구현** — `ChatOpenAI` + 커스텀 시스템 프롬프트("텍스트에서 엔티티와 관계를 JSON으로 추출하라") + `JsonOutputParser`를 LCEL 체인으로 묶어, 원문 텍스트를 넣으면 `{"entities": [...], "relationships": [...]}` 형태의 구조화 출력을 받는 패턴. 추출 결과는 이후 `MERGE (n:{type} {name: $name}) SET n += $properties`같은 동적 Cypher로 Neo4jGraph에 저장한다.
- **방법 2: `neo4j-graphrag` 라이브러리의 `SimpleKGPipeline`** — Neo4j 공식 GraphRAG 패키지가 제공하는 파이프라인으로, 문서 입력부터 엔티티/관계 추출, Neo4j 저장까지 자동화되어 있다(3-3에서 설치를 안내했던 APOC 플러그인이 이 파이프라인 동작에 필요했던 이유가 여기서 드러남).
- **방법 3: LangChain의 `LLMGraphTransformer`** — LangChain 생태계 내에서 문서를 그래프 문서(GraphDocument) 객체로 변환해주는 유틸리티로, Neo4jGraph에 바로 적재 가능한 형태를 만들어준다.
- 품질 개선 팁 4가지: (1) 프롬프트 최적화(추출 스키마를 명확히 지정), (2) 청킹 최적화(너무 크거나 작지 않게), (3) 엔티티 정규화(동일 개체의 표기 통일, 예: "세종"과 "세종대왕"), (4) 중복 제거(MERGE 활용).
- 자동 추출 vs 수동 구축 비교로 마무리하며, Part7의 GraphRAG 파이프라인(벡터 인덱스 + 그래프 결합)으로 넘어갈 준비를 갖춘다.

---
이전: [Part5_Neo4j와_Cypher.md](./Part5_Neo4j와_Cypher.md) · 다음: [Part7_GraphRAG_파이프라인.md](./Part7_GraphRAG_파이프라인.md)
