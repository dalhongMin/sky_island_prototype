# 공중섬 프로토타입 인수인계

기준일: 2026-10-03. 이 프로젝트는 기존 `night_greenhouse` Flutter/Godot 프로젝트와 분리된 독립적인 검증용 프로젝트다. 이전 두 프로젝트는 이 작업에서 수정하지 않았다.

## 실행

- 프로젝트 경로: `/Users/mindalhong/Desktop/Project/sky_island_prototype`
- 엔진: Godot 4.7.2 Stable, Mobile 렌더러, GDScript
- `project.godot`을 Godot에서 열고 메인 씬을 실행한다. 설계 화면은 세로 1080×1920, 데스크톱 창은 540×960이다.
- 실행·조작·구조·테스트 명령은 프로젝트 루트의 `README.md`에 정리했다.

## 주요 구조

- `scripts/state/sky_island_state.gd`: 성장 단계, 돌보기, 낮밤, 고래 방문의 단일 상태 소스.
- `scripts/world/`: 섬 성장 연출, 하늘 주기, 구름, 고래의 화면 표현.
- `scripts/art/`: 절차적 저폴리 메시와 공용 재질. 이전 게임의 렌더링 코드는 반입하지 않았다.
- `scripts/main.gd`, `scripts/camera_rig.gd`: 섬 터치와 하늘 드래그의 입력 분리 및 카메라.
- `scripts/ui/hud.gd`, `scenes/hud.tscn`: 임시 조작 UI. 한국어 폰트가 없어 영어 자리표시 문구다.
- `tests/prototype_test.gd`: 헤드리스 상태·구조 검사.
- `tools/capture_prototype.gd`: GUI 렌더 캡처 6장을 `docs/images/`에 저장.

## 범위와 한계

이 빌드는 작은 섬이 3단계 커지고 낮·노을·밤으로 하늘이 바뀌며, 완전히 자란 밤에 하늘고래가 지나가는 장면을 시험한다. 성장 탭 수는 데모 속도용 수치다. 장기 경제·레벨 밸런스·저장·광고·결제·다수 섬·완성 아트는 구현하지 않았다. 별도 게임으로 만들지, 기존 밤의 온실 기획과 연결할지는 결정하지 않았다.

데스크톱 Metal의 Mobile 렌더러 캡처는 모바일 실기기 성능 검증이 아니다. Android/iOS 실행, 터치 감각, 배터리·발열·FPS는 아직 확인이 필요하다.
