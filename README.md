<p align="center">
  <img src="docs/icon.png" width="160" alt="Ppalli icon">
</p>

<h1 align="center">Ppalli 빨리</h1>

<p align="center">
  AI가 느릴 때, 화면을 채찍으로 <b>찰싹!</b><br>
  오래 걸리는 작업 시켜 놓고 기다리는 동안 마음껏 때리는 macOS 앱
</p>

<p align="center">
  <a href="../../releases/latest"><b>⬇️ 최신 버전 다운로드</b></a> ·
  <a href="#english">English</a>
</p>

---

## 이런 앱이에요

- **클릭하면 채찍** — 커서 옆 손잡이에서 긴 가죽 채찍이 날아가 찰싹! 소리와 함께 때려요
- **꾹 눌렀다 놓으면 필살기** — 게이지를 모았다가 놓으면 최대 12연타 + 마무리 한 방
- **효과 5종** — ⚡ 번개 · 🌪 바람 · 🔥 불 · 💧 물 · 🎲 랜덤
- **조준선** — 채찍 끝이 어디 떨어질지 미리 보여요
- **말풍선** — 때릴 때마다 "언제 끝나?", "빨리 해" 같은 말이 떠요 (문장은 직접 바꿀 수 있어요)
- **방해 안 함** — `⌥ Option + ESC`로 언제든 켜고 끌 수 있고, 꺼져 있을 땐 마우스를 평소처럼 써요

## 설치

1. [Releases](../../releases/latest)에서 `Ppalli-x.x.x.dmg`를 받아 열어요
2. 창 안의 **Ppalli**를 **Applications** 폴더로 끌어다 놓아요
3. 응용 프로그램 폴더에서 Ppalli를 실행해요

### ⚠️ "'Ppalli'을(를) 열지 않음" 경고가 뜨면

> Apple은 'Ppalli'에 사용자의 Mac에 손상을 입히거나 사용자의 개인정보에 침입할 수 있는 악성 코드가 없음을 확인할 수 없습니다.

Ppalli는 Apple 유료 개발자 인증서(연 $99) 없이 배포하는 무료 앱이라, 처음 한 번은 이 경고가 떠요. 앱에 문제가 있는 게 아니에요. 아래 두 방법 중 편한 걸로 **한 번만** 허용하면 그다음부터는 그냥 열려요.

> 💡 먼저 Ppalli를 **응용 프로그램(Applications)** 폴더로 옮긴 다음 해 주세요.

#### 방법 1. 시스템 설정에서 허용하기

1. 경고 창에서 **완료**를 눌러 닫아요
2. **시스템 설정 → 개인정보 보호 및 보안**으로 가서 맨 아래까지 내려요
3. "'Ppalli'이(가) Mac을 보호하기 위해 차단되었습니다" 옆의 **그래도 열기**를 눌러요
4. 다시 뜨는 창에서 **그래도 열기**를 누르고, 비밀번호나 Touch ID로 확인해요

#### 방법 2. 터미널에서 한 줄로 해결하기 (더 빠름)

**터미널**(Spotlight에서 `터미널` 검색)을 열고 아래 한 줄을 붙여넣은 뒤 Enter를 눌러요.

```bash
xattr -dr com.apple.quarantine /Applications/Ppalli.app
```

아무 메시지 없이 끝나면 성공이에요. 이제 Ppalli를 열면 경고 없이 바로 실행돼요.

## 사용법

### 🖱 마우스

| 동작 | 하는 일 |
|---|---|
| 클릭 | 채찍 한 방 |
| 꾹 눌렀다 놓기 | 필살기 (오래 누를수록 연타 수 증가, 최대 12연타) |

### ⌨️ 단축키

| 단축키 | 하는 일 | 언제 |
|---|---|---|
| `⌥ Option` + `ESC` | 채찍 모드 켜기 / 끄기 | **언제든, 어떤 앱을 쓰고 있든** |
| `ESC` | 채찍 모드 끄기 | 채찍 모드가 켜져 있을 때 |
| `⌘ Command` + `Q` | Ppalli 종료 | Ppalli가 앞에 있을 때 (채찍 모드 중 포함) |
| `⌘ Command` + `H` | Ppalli 가리기 | Ppalli가 앞에 있을 때 |

> 💡 제일 많이 쓰는 건 `⌥ESC` 하나예요. 작업 시켜 놓고 `⌥ESC` → 마음껏 때리기 → `ESC`로 끄고 하던 일 계속.

### 🚀 Dock / 메뉴

| 동작 | 하는 일 |
|---|---|
| Dock 아이콘 클릭 | 채찍 모드 켜기 |
| Dock 아이콘 우클릭 | 채찍 모드, 효과 선택, 말풍선 문장 바꾸기 |
| 메뉴 막대 ⚡ 아이콘 | Dock 우클릭과 같은 메뉴 + 채찍질 횟수 |
| 상단 메뉴 **Ppalli** | 로그인할 때 자동 실행, 메뉴 막대 아이콘 보기/숨기기, 정보 |

- 채찍 모드가 켜져 있는 동안에는 클릭이 다른 앱으로 전달되지 않아요. 실수로 뭘 누를 걱정 없이 때려도 돼요.
- 상단 메뉴 **Ppalli → 로그인할 때 자동으로 켜기**를 체크하면 맥을 켤 때 조용히 대기하고, `⌥ESC`로 바로 쓸 수 있어요.

## 효과

| 효과 | 한 방 | 필살기 마무리 |
|---|---|---|
| ⚡ 번개 | 스파크와 불똥 | 하늘에서 낙뢰 + 화면 번쩍 |
| 🌪 바람 | 나뭇잎과 흙먼지 | 회오리 + 화면을 가로지르는 돌풍 |
| 🔥 불 | 불꽃, 연기, 불탄 자국 | 불길이 번지고 불기둥이 솟음 |
| 💧 물 | 물보라, 물결, 젖은 자국 | 큰 물보라 + 쏟아지는 비 |
| 🎲 랜덤 | 매번 다른 효과 | 필살기마다 다른 효과 |

모든 그림과 소리는 코드로 직접 만들어서, 외부 리소스 없이 앱 하나로 동작해요.

## 소스에서 직접 빌드

Xcode 또는 Command Line Tools(`xcode-select --install`)가 필요해요.

```bash
git clone https://github.com/Jojunhyeong/ppalli.git
cd ppalli
./install.sh          # 빌드해서 응용 프로그램 폴더에 설치
```

- `./scripts/build-app.sh` — `build/Ppalli.app`만 만들기
- `./scripts/make-dmg.sh` — 배포용 `build/Ppalli-x.x.x.dmg`, `.zip` 만들기
- `python3 scripts/make-icon.py` — `Resources/icon.svg`를 고친 뒤 앱 아이콘 다시 만들기 (`pip install cairosvg` 필요)

### 새 버전 배포하기

`v`로 시작하는 태그를 올리면 GitHub Actions가 자동으로 앱을 빌드해서 Releases에 DMG와 ZIP을 올려요.

```bash
git tag v1.0.0
git push origin v1.0.0
```

## 요구 사항

- macOS 13 Ventura 이상
- Apple Silicon / Intel 모두 지원

## 라이선스

[MIT](LICENSE)

---

<a name="english"></a>

## English

**Ppalli** (Korean for *"hurry up!"*) is a silly little macOS app for when your AI is taking forever. Click anywhere and a leather whip cracks across your screen. *Thwack!*

**Features**

- **Click to whip** — a long lash flies out from the cursor and cracks with a sound
- **Hold & release for a special move** — charge up to a 12-hit combo with a finisher
- **5 effects** — ⚡ Lightning · 🌪 Wind · 🔥 Fire · 💧 Water · 🎲 Random
- **Crosshair** — see where the tip will land before you strike
- **Speech bubbles** — "Are you done yet?" style lines pop up on each hit (customizable)
- **Stays out of your way** — toggle anytime with `⌥ Option + Esc`; when it's off, your mouse works normally

**Install**

1. Download `Ppalli-x.x.x.dmg` from [Releases](../../releases/latest) and drag **Ppalli** into **Applications**
2. Open Ppalli from your Applications folder

**If macOS says "'Ppalli' Not Opened"**

Ppalli isn't signed with a paid Apple Developer certificate, so macOS blocks it the first time. Nothing is wrong with the app. Move it to **Applications** first, then allow it once using either method:

- **Option 1 — System Settings:** Click **Done** on the warning, open **System Settings → Privacy & Security**, scroll to the bottom, click **Open Anyway** next to the Ppalli message, and confirm with your password or Touch ID.
- **Option 2 — Terminal (faster):** Open Terminal and run:
  ```bash
  xattr -dr com.apple.quarantine /Applications/Ppalli.app
  ```
  If it finishes with no output, it worked. Ppalli will now open normally.

**Mouse**

| Action | What it does |
|---|---|
| Click | Whip |
| Press & hold, then release | Special move (longer hold = more hits, up to 12) |

**Keyboard shortcuts**

| Shortcut | What it does | When |
|---|---|---|
| `⌥ Option` + `Esc` | Toggle whip mode on / off | **Anytime, from any app** |
| `Esc` | Turn whip mode off | While whip mode is on |
| `⌘ Command` + `Q` | Quit Ppalli | While Ppalli is in front (including whip mode) |
| `⌘ Command` + `H` | Hide Ppalli | While Ppalli is in front |

**Dock / menus**

| Action | What it does |
|---|---|
| Click the Dock icon | Turn whip mode on |
| Right-click the Dock icon | Whip mode, pick an effect, edit speech bubbles |
| ⚡ menu bar icon | Same menu as the Dock, plus a hit counter |
| **Ppalli** app menu | Launch at login, show/hide menu bar icon, About |

While whip mode is on, clicks don't reach other apps, so you can't accidentally click anything.

**Build from source**

```bash
git clone https://github.com/Jojunhyeong/ppalli.git
cd ppalli
./install.sh
```

Requires macOS 13+ and Xcode or Command Line Tools. Push a `v*` tag to have GitHub Actions build and publish a release automatically.

**License** — [MIT](LICENSE)
