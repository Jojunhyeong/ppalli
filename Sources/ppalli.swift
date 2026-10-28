// Ppalli (빨리) - 느린 AI를 채찍으로 찰싹! (macOS 앱)
//  - 실행하면 바로 채찍 모드: 클릭 = 채찍 "찰싹!", 꾹 눌렀다 놓기 = 필살기 (아래 앱엔 클릭이 안 감)
//  - ⌥ Option + ESC: 어디서든 채찍 모드 켜기/끄기 (켜져 있을 땐 ESC만 눌러도 꺼짐)
//    꺼져 있을 땐 마우스를 평소처럼 사용
//  - 효과: ⚡ 번개 / 🌪 바람 / 🔥 불 / 💧 물 / 🎲 랜덤 (메뉴에서 선택)
//  - 자동 업데이트: 켤 때 GitHub에 새 버전이 있으면 패치 내용을 보여 주고 바로 업데이트
//  - Dock 아이콘 클릭 = 채찍 모드 켜기, 우클릭 = 메뉴 (메뉴 막대 ⚡ 아이콘에도 같은 메뉴)
//
// 빌드:  ./scripts/build-app.sh   → build/Ppalli.app
// 설치:  ./install.sh             → 빌드해서 응용 프로그램 폴더에 설치

import Cocoa
import AVFoundation
import Carbon
import ServiceManagement

// MARK: - 작은 도우미

extension CGPoint {
    static func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
    func moved(_ angle: Double, _ dist: Double) -> CGPoint {
        CGPoint(x: x + CGFloat(cos(angle) * dist), y: y + CGFloat(sin(angle) * dist))
    }
}

func smooth(_ x: Double) -> Double {
    let c = max(0, min(1, x)); return c * c * (3 - 2 * c)
}

// MARK: - 소리 합성 (외부 파일 없이 코드로 생성)

enum Synth {
    static let sr = 44100.0
    static func count(_ dur: Double) -> Int { Int(sr * dur) }
    static func rnd() -> Double { Double.random(in: -1...1) }

    /// 휘이익~ (점점 빨라지는 바람 소리, 0.36초 끝에 "착!"과 이어짐)
    static func whoosh() -> [Double] {
        var y = 0.0
        return (0..<count(0.36)).map { i in
            let u = Double(i) / sr / 0.36
            y += (0.03 + 0.25 * u) * (rnd() - y)
            return y * pow(u, 2.2) * 2.4
        }
    }

    /// 착!
    static func crack() -> [Double] {
        (0..<count(0.25)).map { i in
            let t = Double(i) / sr
            return rnd() * exp(-t * 60) + (t < 0.0015 ? 1 : 0)
        }
    }

    /// 지직! (번개 채찍 한 방)
    static func zap() -> [Double] {
        var phase = 0.0
        return (0..<count(0.22)).map { i in
            let t = Double(i) / sr
            let f = max(180, 1600 * exp(-t * 12))
            phase += 2 * .pi * f / sr
            let buzz = (sin(phase) > 0 ? 1.0 : -1.0) * 0.35 * exp(-t * 18)
            return buzz + rnd() * 0.8 * exp(-t * 45) + (t < 0.0015 ? 1 : 0)
        }
    }

    /// 콰르릉! (마무리 낙뢰)
    static func thunder() -> [Double] {
        var low = 0.0, mid = 0.0
        return (0..<count(1.7)).map { i in
            let t = Double(i) / sr
            let r = rnd()
            low += 0.015 * (r - low)
            mid += 0.08 * (r - mid)
            var s = r * exp(-t * 35)                                         // 첫 파열
            s += low * exp(-t * 2.0) * 9 * (0.7 + 0.3 * sin(2 * .pi * 3 * t)) // 우르릉
            s += mid * exp(-t * 4.5) * 2
            return s + (t < 0.002 ? 1 : 0)
        }
    }

    /// 게이지 모으는 소리 (점점 높아지는 전기 웅웅 + 지직)
    static func charge(_ dur: Double, rising: Bool) -> [Double] {
        var phase = 0.0, burst = 0.0
        return (0..<count(dur)).map { i in
            let t = Double(i) / sr
            let u = rising ? t / dur : 1
            let f = rising ? 90 + 500 * pow(u, 1.5) : 590       // 590Hz × 0.5초 = 딱 맞아떨어져서 반복 재생이 매끄러움
            phase += f / sr
            phase -= floor(phase)
            let saw = 2 * phase - 1
            if Double.random(in: 0..<1) < 0.0006 + 0.004 * u { burst = 1 }
            burst *= 0.993
            return saw * (0.12 + 0.3 * u) + burst * rnd() * 0.5
        }
    }

    static func wav(_ samples: [Double]) -> Data {
        var d = Data()
        func u32(_ v: UInt32) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: UInt16) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 2)) }
        let dataSize = UInt32(samples.count * 2)
        d.append("RIFF".data(using: .ascii)!); u32(36 + dataSize)
        d.append("WAVE".data(using: .ascii)!)
        d.append("fmt ".data(using: .ascii)!); u32(16); u16(1); u16(1)
        u32(UInt32(sr)); u32(UInt32(sr) * 2); u16(2); u16(16)
        d.append("data".data(using: .ascii)!); u32(dataSize)
        for s in samples {
            let c = max(-1, min(1, s))
            u16(UInt16(bitPattern: Int16(c * 32767 * 0.9)))
        }
        return d
    }
}

/// 미리 준비해 둔 플레이어를 돌려 쓰는 효과음 (연타해도 끊김/지연 없음)
final class Sfx {
    let data: Data
    var pool: [AVAudioPlayer] = []

    init(_ samples: [Double]) {
        data = Synth.wav(samples)
        for _ in 0..<3 { if let p = make() { pool.append(p) } }
    }

    private func make() -> AVAudioPlayer? {
        let p = try? AVAudioPlayer(data: data)
        p?.prepareToPlay()
        return p
    }

    @discardableResult
    func play(volume: Float = 0.9, loop: Bool = false) -> AVAudioPlayer? {
        var player = pool.first { !$0.isPlaying }
        if player == nil, let p = make() { pool.append(p); player = p }
        guard let p = player else { return nil }
        p.numberOfLoops = loop ? -1 : 0
        p.volume = volume
        p.currentTime = 0
        p.play()
        return p
    }

    static let whoosh = Sfx(Synth.whoosh())
    static let crack = Sfx(Synth.crack())
    static let zap = Sfx(Synth.zap())
    static let thunder = Sfx(Synth.thunder())
    static let chargeRise = Sfx(Synth.charge(1.3, rising: true))
    static let chargeHold = Sfx(Synth.charge(0.5, rising: false))
}

// MARK: - 채찍 끈 애니메이션
//
// 손잡이는 커서 옆에 두고, 끈만 손잡이 끝에서 길게 뻗어 나갑니다 (40마디로 매 프레임 계산).
//  1) 0.00~0.14초: 끈이 손잡이에서 자라나며 뒤로 젖혀짐
//  2) 0.14~0.36초: 손잡이 쪽부터 펴지면서 고리가 끝으로 굴러감
//  3) 0.36초: 끝이 쫙 펴지며 찰싹!
//  4) 살짝 튕겼다가 사라짐
//
// 생김새: 꼬아 만든 가죽 줄무늬 + 한쪽 하이라이트 + 바닥 그림자 + 끝의 풀린 실(크래커) + 빠를 때 잔상

final class WhipStrike {
    static let tBack = 0.14, tCrack = 0.36, tEnd = 0.62
    static let segments = 40

    let phi: Double              // 때리는 방향
    let length: Double
    let speed: Double            // 1 = 보통, 3 = 필살기 연타
    let glowColor: CGColor?      // 필살기 때만 은은한 속성 빛
    let origin: () -> CGPoint    // 손잡이 끝 위치 (커서를 따라감)

    static let leather = NSColor(calibratedRed: 0.24, green: 0.14, blue: 0.07, alpha: 1).cgColor
    static let leatherLight = NSColor(calibratedRed: 0.68, green: 0.48, blue: 0.28, alpha: 0.9).cgColor
    static let leatherDark = NSColor(calibratedRed: 0.10, green: 0.055, blue: 0.025, alpha: 0.95).cgColor
    static let thread = NSColor(calibratedRed: 0.86, green: 0.8, blue: 0.68, alpha: 1).cgColor

    let body = CAShapeLayer()        // 가죽 몸통 (+ 바닥 그림자)
    let braid = CAShapeLayer()       // 꼬인 줄무늬
    let shine = CAShapeLayer()       // 한쪽 하이라이트
    let cracker = CAShapeLayer()     // 끝의 풀린 실
    let trails: [CAShapeLayer] = (0..<4).map { _ in CAShapeLayer() }
    var history: [CGPath] = []
    var start: CFTimeInterval = 0
    var timer: Timer?
    var cracked = false
    var onCrack: ((CGPoint) -> Void)?
    var onDone: ((WhipStrike) -> Void)?

    var allLayers: [CALayer] { trails + [body, braid, shine, cracker] }

    init(in view: NSView, phi: Double, length: Double, speed: Double, glow: CGColor?,
         origin: @escaping () -> CGPoint) {
        self.phi = phi; self.length = length; self.speed = speed
        self.glowColor = glow; self.origin = origin

        let scale = view.window?.backingScaleFactor ?? 2
        for l in allLayers {
            l.frame = view.bounds
            l.contentsScale = scale
            view.layer?.addSublayer(l)
        }
        for (i, t) in trails.enumerated() {           // 잔상 (모션 블러)
            t.fillColor = Self.leather; t.strokeColor = nil
            t.opacity = [0.28, 0.18, 0.1, 0.05][i]
        }
        body.fillColor = Self.leather
        body.strokeColor = NSColor.black.withAlphaComponent(0.35).cgColor
        body.lineWidth = 0.6
        if let glow {
            body.shadowColor = glow; body.shadowRadius = 8; body.shadowOpacity = 0.85; body.shadowOffset = .zero
        } else {
            body.shadowColor = NSColor.black.cgColor        // 화면 위에 떠 있는 듯한 그림자
            body.shadowRadius = 2.5; body.shadowOpacity = 0.45; body.shadowOffset = CGSize(width: 3, height: -4)
        }
        braid.fillColor = nil; braid.strokeColor = Self.leatherDark; braid.lineWidth = 0.9
        shine.fillColor = nil; shine.strokeColor = Self.leatherLight; shine.lineWidth = 1.1; shine.lineCap = .round
        cracker.fillColor = nil; cracker.strokeColor = Self.thread; cracker.lineWidth = 0.9; cracker.lineCap = .round
    }

    func begin() {
        start = CACurrentMediaTime()
        tick()
        let t = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func shape(at t: Double) -> [CGPoint] {
        let n = Self.segments
        let o = origin()
        let len = length * (0.1 + 0.9 * smooth(t / 0.2))    // 손잡이에서 쭉 자라남
        let seg = len / Double(n)
        var pts = [o]
        var x = Double(o.x), y = Double(o.y)
        for i in 0..<n {
            let s = (Double(i) + 0.5) / Double(n)           // 0 = 손잡이 쪽, 1 = 끝
            let rest = -3.5 - 0.3 * s
            let back = -2.3 - 0.5 * s
            var a: Double
            if t < Self.tBack {
                a = rest + (back - rest) * smooth((t / Self.tBack) * 1.6 - s * 0.6)
            } else if t < Self.tCrack {
                let v = pow((t - Self.tBack) / (Self.tCrack - Self.tBack), 1.7)
                let w = 0.35
                let front = -w / 2 + v * (1 + w)
                a = back * smooth((s - front) / w + 0.5)
            } else {
                let r = min(1, (t - Self.tCrack) / 0.12)
                a = 0.35 * sin(.pi * r) * (1 - r) * s * s
            }
            x += cos(phi + a) * seg; y += sin(phi + a) * seg
            pts.append(CGPoint(x: x, y: y))
        }
        return pts
    }

    /// 손잡이 쪽은 두껍고 끝으로 갈수록 가늘어지는 양쪽 가장자리
    private func edges(_ pts: [CGPoint]) -> (left: [CGPoint], right: [CGPoint], dirs: [CGVector]) {
        var left = [CGPoint](), right = [CGPoint](), dirs = [CGVector]()
        let n = pts.count
        for i in 0..<n {
            let a = pts[max(0, i - 1)], b = pts[min(n - 1, i + 1)]
            var dx = Double(b.x - a.x), dy = Double(b.y - a.y)
            let len = max(0.0001, hypot(dx, dy)); dx /= len; dy /= len
            let s = Double(i) / Double(n - 1)
            let half = (6.5 * pow(1 - s, 1.3) + 1.0) / 2
            left.append(CGPoint(x: pts[i].x - CGFloat(dy * half), y: pts[i].y + CGFloat(dx * half)))
            right.append(CGPoint(x: pts[i].x + CGFloat(dy * half), y: pts[i].y - CGFloat(dx * half)))
            dirs.append(CGVector(dx: dx, dy: dy))
        }
        return (left, right, dirs)
    }

    private func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }

    private func tick() {
        let t = (CACurrentMediaTime() - start) * speed
        if t > Self.tEnd { finish(); return }

        let pts = shape(at: t)
        let (left, right, dirs) = edges(pts)
        let n = pts.count

        let bodyPath = CGMutablePath()
        bodyPath.addLines(between: left + right.reversed())
        bodyPath.closeSubpath()

        // 꼬인 가죽: 한쪽 가장자리에서 반대쪽으로 비스듬한 줄 (끝 15%는 매끈한 '폴' 부분이라 생략)
        let braidPath = CGMutablePath()
        let braidEnd = Int(Double(n - 1) * 0.85)
        for i in 0..<max(0, braidEnd - 1) {
            braidPath.move(to: left[i]); braidPath.addLine(to: mid(right[i], right[i + 1]))
            braidPath.move(to: mid(left[i], left[i + 1])); braidPath.addLine(to: right[i + 1])
        }

        // 빛 받는 쪽 하이라이트
        let shinePath = CGMutablePath()
        let shinePts = (0..<braidEnd).map { i in
            CGPoint(x: pts[i].x * 0.45 + left[i].x * 0.55, y: pts[i].y * 0.45 + left[i].y * 0.55)
        }
        if shinePts.count > 1 { shinePath.addLines(between: shinePts) }

        // 끝에 달린 풀린 실 몇 가닥
        let crackerPath = CGMutablePath()
        if let tip = pts.last, let d = dirs.last {
            let base = atan2(Double(d.dy), Double(d.dx))
            for (k, spread) in [-0.35, -0.1, 0.15, 0.4].enumerated() {
                let wobble = sin(t * 40 + Double(k)) * 0.15
                crackerPath.move(to: tip)
                crackerPath.addLine(to: tip.moved(base + spread + wobble, 7 + Double(k % 2) * 4))
            }
        }

        history.append(bodyPath)
        if history.count > 10 { history.removeFirst() }

        let fade: Float = t > 0.45 ? Float(max(0, 1 - (t - 0.45) / (Self.tEnd - 0.45))) : 1
        let swinging = t > Self.tBack && t < Self.tCrack + 0.03

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body.path = bodyPath
        braid.path = braidPath
        shine.path = shinePath
        cracker.path = crackerPath
        for l in [body, braid, shine, cracker] { l.opacity = fade }
        for (i, tr) in trails.enumerated() {
            let idx = history.count - 1 - (i + 1) * 2
            tr.path = (swinging && idx >= 0) ? history[idx] : nil
        }
        CATransaction.commit()

        if !cracked && t >= Self.tCrack, let tip = pts.last {
            cracked = true
            onCrack?(tip)
        }
    }

    private func finish() {
        timer?.invalidate(); timer = nil
        allLayers.forEach { $0.removeFromSuperlayer() }
        onDone?(self)
    }
}

// MARK: - 손잡이 (채찍 쓰는 동안만 커서 옆에 나타남)

/// 마우스 위치 기준, 손잡이 끝(끈이 시작되는 곳)까지의 거리 (y는 위쪽이 +)
let handleTipOffset = CGPoint(x: 26, y: -30)
let handleGripOffset = CGPoint(x: 40, y: -44)

// MARK: - 효과 창 (클릭은 그대로 통과, 그림만 그림)

enum HitKind { case normal, combo, finisher }

/// 채찍 모드: 화면이 클릭을 받아서 클릭 = 채찍 (아래 앱에는 클릭이 안 감)
var whipOnlyMode = false

class FxWindow: NSWindow {
    override var canBecomeKey: Bool { whipOnlyMode }
    override var canBecomeMain: Bool { whipOnlyMode }
}

/// 채찍만 쓰기 모드 때의 커서 (평소엔 짧은 끈 달린 채찍, 휘두르는 동안엔 손잡이만)
func makeWhipCursor(withLash: Bool) -> NSCursor {
    // 그림 좌표는 위쪽이 0. 핫스팟(3,3) 기준으로 손잡이 위치가 handleTipOffset / handleGripOffset과 같음
    let grip = NSPoint(x: 3 + handleGripOffset.x, y: 3 - handleGripOffset.y)
    let tip = NSPoint(x: 3 + handleTipOffset.x, y: 3 - handleTipOffset.y)
    let img = NSImage(size: NSSize(width: 52, height: 54), flipped: true) { _ in
        func handle() -> NSBezierPath {
            let p = NSBezierPath(); p.move(to: grip); p.line(to: tip); p.lineCapStyle = .round; return p
        }
        func lash() -> NSBezierPath {
            let p = NSBezierPath()
            p.move(to: tip)
            p.curve(to: NSPoint(x: 3, y: 3), controlPoint1: NSPoint(x: tip.x, y: 10),
                    controlPoint2: NSPoint(x: 14, y: 22))
            p.lineCapStyle = .round
            return p
        }
        NSColor.white.withAlphaComponent(0.8).setStroke()
        let h1 = handle(); h1.lineWidth = 10; h1.stroke()
        if withLash { let l1 = lash(); l1.lineWidth = 4.5; l1.stroke() }
        NSColor(calibratedRed: 0.30, green: 0.18, blue: 0.09, alpha: 1).setStroke()
        let h2 = handle(); h2.lineWidth = 7; h2.stroke()
        NSColor(calibratedRed: 0.2, green: 0.12, blue: 0.06, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: grip.x - 3.5, y: grip.y - 3.5, width: 8, height: 8)).fill()
        if withLash {
            NSColor(calibratedRed: 0.24, green: 0.14, blue: 0.07, alpha: 1).setStroke()
            let l2 = lash(); l2.lineWidth = 2.2; l2.stroke()
        }
        return true
    }
    return NSCursor(image: img, hotSpot: NSPoint(x: 3, y: 3))
}

class WhipView: NSView {
    var onHit: ((CGPoint, CGPoint, HitKind) -> Void)?  // (채찍 끝 위치, 마우스 위치, 종류)
    var strikes: [WhipStrike] = []
    var currentElement: () -> Element = { .lightning }   // 메뉴에서 고른 효과

    // 손잡이 그림 (마우스 위치에 통째로 붙어 다님)
    let handleRig = CALayer()
    let crosshair = CALayer()
    var followTimer: Timer?

    // 게이지
    var pressTime: CFTimeInterval?
    var chargeTimer: Timer?
    var charging = false
    var gauge = 0.0
    var specialRunning = false
    var risePlayer: AVAudioPlayer?
    var holdPlayer: AVAudioPlayer?
    let ringBG = CAShapeLayer()
    let ring = CAShapeLayer()
    let sparkLayer = CAShapeLayer()
    let hitsLabel = CATextLayer()
    let dim = CALayer()

    static let chargeDelay = 0.22     // 이만큼 누르고 있으면 게이지 시작
    static let chargeFull = 1.3       // 게이지 다 차는 데 걸리는 시간

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    var scale: CGFloat { window?.backingScaleFactor ?? 2 }

    func mouseLocal() -> CGPoint {
        guard let w = window else { return .zero }
        return convert(w.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
    }
    func handleTip() -> CGPoint { mouseLocal() + handleTipOffset }

    // MARK: 손잡이 따라다니기

    var busy: Bool { !strikes.isEmpty || charging || specialRunning }

    func buildHandle() {
        handleRig.bounds = .zero
        handleRig.contentsScale = scale
        let grip = handleGripOffset, tip = handleTipOffset
        let dx = tip.x - grip.x, dy = tip.y - grip.y
        let len = max(0.001, hypot(dx, dy))
        let nx = -dy / len, ny = dx / len           // 손잡이에 수직인 방향

        func line(_ a: CGPoint, _ b: CGPoint) -> CGPath {
            let p = CGMutablePath(); p.move(to: a); p.addLine(to: b); return p
        }
        func stroke(_ path: CGPath, _ color: CGColor, _ width: CGFloat) -> CAShapeLayer {
            let l = CAShapeLayer()
            l.contentsScale = scale
            l.path = path; l.fillColor = nil; l.strokeColor = color
            l.lineWidth = width; l.lineCap = .round
            return l
        }
        let shaft = line(grip, tip)
        let outline = stroke(shaft, NSColor.white.withAlphaComponent(0.55).cgColor, 10)   // 어두운 화면에서도 보이게
        let wood = stroke(shaft, NSColor(calibratedRed: 0.30, green: 0.18, blue: 0.09, alpha: 1).cgColor, 7)
        wood.shadowColor = NSColor.black.cgColor
        wood.shadowRadius = 2; wood.shadowOpacity = 0.5; wood.shadowOffset = CGSize(width: 2, height: -3)
        let shine = stroke(line(CGPoint(x: grip.x + nx * 1.6, y: grip.y + ny * 1.6),
                                CGPoint(x: tip.x + nx * 1.6, y: tip.y + ny * 1.6)),
                           NSColor(calibratedRed: 0.7, green: 0.5, blue: 0.3, alpha: 0.9).cgColor, 1.2)
        // 감아 놓은 가죽끈
        let wraps = CGMutablePath()
        for k in 1...4 {
            let f = CGFloat(k) / 5
            let c = CGPoint(x: grip.x + dx * f, y: grip.y + dy * f)
            wraps.move(to: CGPoint(x: c.x + nx * 3.4 - dx / len * 1.5, y: c.y + ny * 3.4 - dy / len * 1.5))
            wraps.addLine(to: CGPoint(x: c.x - nx * 3.4 + dx / len * 1.5, y: c.y - ny * 3.4 + dy / len * 1.5))
        }
        let wrap = stroke(wraps, NSColor(calibratedRed: 0.1, green: 0.06, blue: 0.03, alpha: 0.9).cgColor, 1.3)
        // 끝의 둥근 손잡이 머리
        let knob = CAShapeLayer()
        knob.contentsScale = scale
        let kc = CGPoint(x: grip.x - dx / len * 2, y: grip.y - dy / len * 2)
        knob.path = CGPath(ellipseIn: CGRect(x: kc.x - 4.5, y: kc.y - 4.5, width: 9, height: 9), transform: nil)
        knob.fillColor = NSColor(calibratedRed: 0.2, green: 0.12, blue: 0.06, alpha: 1).cgColor
        knob.strokeColor = NSColor(calibratedRed: 0.65, green: 0.47, blue: 0.28, alpha: 1).cgColor
        knob.lineWidth = 1
        for l in [outline, wood, shine, wrap, knob] { handleRig.addSublayer(l) }
        layer?.addSublayer(handleRig)
    }

    func updateHandle() {
        if handleRig.superlayer == nil { buildHandle() }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        handleRig.position = mouseLocal()
        handleRig.isHidden = !busy || whipOnlyMode     // 채찍만 모드에선 커서 자체가 손잡이
        handleRig.zPosition = 10
        CATransaction.commit()
        refreshCursor()
        if !busy { followTimer?.invalidate(); followTimer = nil }
    }

    // MARK: 채찍만 쓰기 모드 (이 창이 직접 클릭을 받음)

    static let idleCursor = makeWhipCursor(withLash: true)
    static let swingCursor = makeWhipCursor(withLash: false)

    func refreshCursor() {
        updateCrosshair()
        guard whipOnlyMode else { return }
        (busy ? Self.swingCursor : Self.idleCursor).set()
    }

    // MARK: 조준선 (채찍 끝이 떨어질 자리)

    func buildCrosshair() {
        crosshair.bounds = .zero
        crosshair.zPosition = 20
        // 가운데가 살짝 빈 단순한 십자
        let path = CGMutablePath()
        for a in stride(from: 0.0, to: 2 * .pi, by: .pi / 2) {
            path.move(to: CGPoint.zero.moved(a, 4))
            path.addLine(to: CGPoint.zero.moved(a, 13))
        }
        let outline = CAShapeLayer()                    // 밝은 화면에서도 보이게 얇은 어두운 테두리
        outline.path = path
        outline.fillColor = nil
        outline.strokeColor = NSColor.black.withAlphaComponent(0.5).cgColor
        outline.lineWidth = 3.5
        let line = CAShapeLayer()
        line.path = path
        line.fillColor = nil
        line.strokeColor = NSColor.white.cgColor
        line.lineWidth = 1.6
        for l in [outline, line] {
            l.contentsScale = scale
            crosshair.addSublayer(l)
        }
        layer?.addSublayer(crosshair)
    }

    func updateCrosshair() {
        if crosshair.superlayer == nil { buildCrosshair() }
        let m = mouseLocal()
        let show = whipOnlyMode && bounds.contains(m)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        crosshair.isHidden = !show
        if show && !specialRunning {                 // 필살기 중엔 쏜 자리에 고정
            let o = m + handleTipOffset
            let (phi, len) = normalAim(from: o)
            crosshair.position = o.moved(phi, len)
        }
        CATransaction.commit()
    }

    func crosshairPulse() {
        let a = CAKeyframeAnimation(keyPath: "transform.scale")
        a.values = [1, 0.6, 1.25, 1]
        a.keyTimes = [0, 0.3, 0.7, 1]
        a.duration = 0.4
        crosshair.add(a, forKey: "pulse")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.activeAlways, .mouseMoved, .cursorUpdate, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }
    override func resetCursorRects() {
        if whipOnlyMode { addCursorRect(bounds, cursor: Self.idleCursor) }
    }
    override func cursorUpdate(with event: NSEvent) { refreshCursor() }
    override func mouseMoved(with event: NSEvent) { refreshCursor() }
    override func mouseDragged(with event: NSEvent) { refreshCursor() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        guard whipOnlyMode, !specialRunning else { return }
        pressBegan()
    }
    override func mouseUp(with event: NSEvent) {
        guard whipOnlyMode else { return }
        pressEnded()
    }

    func startFollowing() {
        updateHandle()
        guard followTimer == nil else { return }
        let t = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in self?.updateHandle() }
        RunLoop.main.add(t, forMode: .common)
        followTimer = t
    }

    // MARK: 누르기 / 떼기 (AppDelegate가 전달)

    func pressBegan() {
        guard !specialRunning else { return }
        normalStrike()
        pressTime = CACurrentMediaTime()
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.chargeTick() }
        RunLoop.main.add(t, forMode: .common)
        chargeTimer = t
    }

    func pressEnded() {
        chargeTimer?.invalidate(); chargeTimer = nil
        pressTime = nil
        if charging {
            charging = false
            stopChargeEffects()
            special(gauge)
        }
    }

    // MARK: 보통 채찍

    /// 끝이 화면 안에 들어오는 방향/길이 고르기
    func pickDirection(from o: CGPoint, preferred: [Double], maxLen: Double) -> (Double, Double) {
        let area = bounds.insetBy(dx: 30, dy: 30)
        for f in [1.0, 0.8, 0.6, 0.45, 0.3] {
            for deg in preferred {
                let a = deg * .pi / 180
                if area.contains(o.moved(a, maxLen * f)) { return (a, maxLen * f) }
            }
        }
        return (135 * .pi / 180, 120)
    }

    func addStrike(_ s: WhipStrike) {
        s.onDone = { [weak self] done in
            self?.strikes.removeAll { $0 === done }
            self?.updateHandle()
        }
        strikes.append(s)
        startFollowing()
        s.begin()
    }

    /// 지금 클릭하면 채찍 끝이 떨어질 방향/길이 (조준선도 같은 계산을 씀)
    func normalAim(from o: CGPoint) -> (Double, Double) {
        pickDirection(from: o, preferred: [135, 155, 115, 175, 95, 195, 75, 215, 55],
                      maxLen: Double(min(520, bounds.width * 0.42)))
    }

    func normalStrike() {
        let el = currentElement().resolved
        let o = handleTip()
        let aim = mouseLocal()
        let (phi, len) = normalAim(from: o)
        crosshairPulse()
        let s = WhipStrike(in: self, phi: phi, length: len, speed: 1, glow: nil,
                           origin: { [weak self] in self?.handleTip() ?? o })
        s.onCrack = { [weak self] tip in
            guard let self else { return }
            Sfx.crack.play()
            self.impact(at: tip, dir: phi)
            self.elementHit(el, at: tip, dir: phi, volume: 0.8)
            self.onHit?(tip, aim, .normal)
        }
        Sfx.whoosh.play(volume: 0.8)
        addStrike(s)
    }

    // MARK: 게이지 모으기

    func chargeTick() {
        guard let pt = pressTime else { return }
        let held = CACurrentMediaTime() - pt
        if held < Self.chargeDelay { return }
        if !charging {
            charging = true
            startChargeEffects()
            startFollowing()
        }
        gauge = min(1, (held - Self.chargeDelay) / Self.chargeFull)
        if gauge >= 1 && holdPlayer == nil {
            risePlayer?.stop(); risePlayer = nil
            holdPlayer = Sfx.chargeHold.play(volume: 0.5, loop: true)
        }
        updateChargeEffects()
    }

    func startChargeEffects() {
        guard let root = layer else { return }
        let circle = CGMutablePath()
        circle.addArc(center: .zero, radius: 38, startAngle: .pi / 2, endAngle: .pi / 2 - 2 * .pi, clockwise: true)
        for l in [ringBG, ring, sparkLayer] {
            l.contentsScale = scale
            l.bounds = .zero
            l.fillColor = nil
            l.lineCap = .round
            l.removeAllAnimations()
            root.addSublayer(l)
        }
        ringBG.path = circle
        ringBG.strokeColor = NSColor.white.withAlphaComponent(0.25).cgColor
        ringBG.lineWidth = 6
        ring.path = circle
        ring.lineWidth = 6
        ring.strokeEnd = 0
        ring.shadowRadius = 10; ring.shadowOpacity = 1; ring.shadowOffset = .zero
        sparkLayer.lineWidth = 1.8
        sparkLayer.strokeColor = NSColor(calibratedRed: 0.8, green: 0.93, blue: 1, alpha: 1).cgColor
        sparkLayer.shadowColor = NSColor.cyan.cgColor
        sparkLayer.shadowRadius = 6; sparkLayer.shadowOpacity = 1; sparkLayer.shadowOffset = .zero

        hitsLabel.contentsScale = scale
        hitsLabel.fontSize = 18
        hitsLabel.font = NSFont.boldSystemFont(ofSize: 18)
        hitsLabel.alignmentMode = .center
        hitsLabel.bounds = CGRect(x: 0, y: 0, width: 80, height: 24)
        hitsLabel.shadowColor = NSColor.black.cgColor
        hitsLabel.shadowRadius = 3; hitsLabel.shadowOpacity = 1; hitsLabel.shadowOffset = .zero
        root.addSublayer(hitsLabel)

        risePlayer = Sfx.chargeRise.play(volume: 0.5)
    }

    func updateChargeEffects() {
        let c = mouseLocal()
        let full = gauge >= 1
        let color: NSColor = full ? NSColor(calibratedRed: 0.45, green: 0.85, blue: 1, alpha: 1)
            : gauge > 0.5 ? .systemOrange : .systemYellow

        let sp = CGMutablePath()
        let n = Int(1 + gauge * 5 + (full ? 3 : 0))
        for _ in 0..<n where Double.random(in: 0..<1) < 0.35 + gauge * 0.6 {
            let a = Double.random(in: 0..<(2 * .pi))
            let r1 = 42.0, r2 = r1 + Double.random(in: 10...(18 + gauge * 30))
            sp.addLines(between: boltPoints(CGPoint.zero.moved(a, r1), CGPoint.zero.moved(a, r2), jag: 0.35, depth: 3))
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for l in [ringBG, ring, sparkLayer] { l.position = c }
        ring.strokeEnd = CGFloat(gauge)
        ring.strokeColor = color.cgColor
        ring.shadowColor = color.cgColor
        sparkLayer.path = sp
        let pulse: CGFloat = full ? 1 + 0.08 * CGFloat(sin(CACurrentMediaTime() * 30)) : 1
        ring.transform = CATransform3DMakeScale(pulse, pulse, 1)
        hitsLabel.position = CGPoint(x: c.x, y: c.y + 60)
        hitsLabel.string = full ? "MAX ×\(hitCount(for: gauge))" : "×\(hitCount(for: gauge))"
        hitsLabel.foregroundColor = color.cgColor
        CATransaction.commit()
    }

    func stopChargeEffects() {
        risePlayer?.stop(); risePlayer = nil
        holdPlayer?.stop(); holdPlayer = nil
        for l in [ringBG, ring, sparkLayer, hitsLabel] as [CALayer] { l.removeFromSuperlayer() }
    }

    func hitCount(for g: Double) -> Int { 3 + Int((g * 9).rounded()) }   // 3 ~ 12연타

    // MARK: 필살기

    func special(_ g: Double) {
        specialRunning = true
        startFollowing()
        let el = currentElement().resolved       // 랜덤이면 이번 필살기 동안은 한 속성으로
        let hits = hitCount(for: g)
        let o = handleTip()
        let aim = mouseLocal()
        // 손을 놓은 순간 조준선이 있던 자리 (조준선과 똑같은 계산)
        let (aimPhi, aimLen) = normalAim(from: o)
        let target = o.moved(aimPhi, aimLen)
        updateCrosshair()

        setDim(0.45, duration: 0.12)
        Sfx.zap.play(volume: 0.5)

        let interval = 0.075
        for i in 0..<hits {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15 + Double(i) * interval) { [weak self] in
                self?.comboStrike(from: o, at: target, aim: aim, element: el)
            }
        }
        let finT = 0.15 + Double(hits) * interval + 0.1
        DispatchQueue.main.asyncAfter(deadline: .now() + finT) { [weak self] in
            self?.finisher(from: o, at: target, aim: aim, power: g, element: el)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + finT + 1.4) { [weak self] in
            self?.setDim(0, duration: 0.4)
            self?.specialRunning = false
            self?.updateHandle()
        }
    }

    /// 손잡이 끝 o에서 점 p를 정확히 때리는 방향/길이 (채찍은 '착!' 순간 일직선으로 펴짐)
    func strike(from o: CGPoint, to p: CGPoint) -> (Double, Double) {
        let dx = Double(p.x - o.x), dy = Double(p.y - o.y)
        return (atan2(dy, dx), max(40, hypot(dx, dy)))
    }

    /// 연타: 조준선 주변을 촘촘하게 두들김
    func comboStrike(from o: CGPoint, at target: CGPoint, aim: CGPoint, element el: Element) {
        let a = Double.random(in: 0..<(2 * .pi))
        let r = Double.random(in: 0...1).squareRoot() * 110       // 반지름 110 안에 고르게 흩뿌림
        let area = bounds.insetBy(dx: 20, dy: 20)
        var p = target.moved(a, r)
        p.x = min(max(p.x, area.minX), area.maxX)
        p.y = min(max(p.y, area.minY), area.maxY)
        let (phi, len) = strike(from: o, to: p)
        let s = WhipStrike(in: self, phi: phi, length: len, speed: 3, glow: el.glow, origin: { o })
        s.onCrack = { [weak self] tip in
            guard let self else { return }
            Sfx.crack.play(volume: 0.4)
            if el == .lightning { self.bolt(from: o, to: tip, width: 2, branches: 1, duration: 0.2) }
            self.impact(at: tip, dir: phi)
            self.elementHit(el, at: tip, dir: phi, volume: 0.45)
            self.shake(5)
            self.onHit?(tip, aim, .combo)
        }
        addStrike(s)
    }

    /// 마무리: 조준선 한가운데에 정확히
    func finisher(from o: CGPoint, at target: CGPoint, aim: CGPoint, power: Double, element el: Element) {
        let (phi, len) = strike(from: o, to: target)
        let s = WhipStrike(in: self, phi: phi, length: len, speed: 1.7, glow: el.glow, origin: { o })
        s.onCrack = { [weak self] tip in
            guard let self else { return }
            Sfx.crack.play(volume: 1)
            self.elementFinisher(el, from: o, to: tip, dir: phi, max: power >= 1)
            self.onHit?(tip, aim, .finisher)
        }
        addStrike(s)
    }

    // MARK: 효과

    /// 지그재그 번개 좌표 (중간점을 랜덤하게 비트는 방식)
    func boltPoints(_ a: CGPoint, _ b: CGPoint, jag: CGFloat, depth: Int = 5) -> [CGPoint] {
        var pts = [a, b]
        var disp = hypot(b.x - a.x, b.y - a.y) * jag
        for _ in 0..<depth {
            var np = [CGPoint]()
            for i in 0..<(pts.count - 1) {
                let p = pts[i], q = pts[i + 1]
                np.append(p)
                let dx = q.x - p.x, dy = q.y - p.y
                let len = max(0.001, hypot(dx, dy))
                let off = CGFloat.random(in: -disp...disp)
                np.append(CGPoint(x: (p.x + q.x) / 2 - dy / len * off, y: (p.y + q.y) / 2 + dx / len * off))
            }
            np.append(pts[pts.count - 1])
            pts = np
            disp *= 0.5
        }
        return pts
    }

    func boltPath(_ a: CGPoint, _ b: CGPoint, branches: Int) -> CGPath {
        let path = CGMutablePath()
        let main = boltPoints(a, b, jag: 0.18)
        path.addLines(between: main)
        let dist = Double(hypot(b.x - a.x, b.y - a.y))
        let dir = atan2(Double(b.y - a.y), Double(b.x - a.x))
        for _ in 0..<branches {
            let idx = Int.random(in: (main.count / 5)...(main.count * 4 / 5))
            let start = main[idx]
            let ang = dir + (Bool.random() ? 1 : -1) * Double.random(in: 0.35...0.9)
            let end = start.moved(ang, dist * Double.random(in: 0.12...0.3))
            path.addLines(between: boltPoints(start, end, jag: 0.25, depth: 4))
        }
        return path
    }

    func bolt(from a: CGPoint, to b: CGPoint, width: CGFloat, branches: Int, duration: Double) {
        guard let root = layer else { return }
        let glow = CAShapeLayer(), core = CAShapeLayer()
        let path = boltPath(a, b, branches: branches)
        for l in [glow, core] {
            l.frame = bounds; l.contentsScale = scale
            l.fillColor = nil; l.lineJoin = .round; l.lineCap = .round
            l.path = path
            root.addSublayer(l)
        }
        let blue = NSColor(calibratedRed: 0.55, green: 0.8, blue: 1, alpha: 1).cgColor
        glow.strokeColor = blue
        glow.lineWidth = width * 3.5
        glow.opacity = 0.55
        glow.shadowColor = blue; glow.shadowRadius = 14; glow.shadowOpacity = 1; glow.shadowOffset = .zero
        core.strokeColor = NSColor.white.cgColor
        core.lineWidth = width

        // 번쩍번쩍 모양이 바뀌며 깜빡임
        for k in 1...2 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05 * Double(k)) { [weak self] in
                guard let self else { return }
                let p = self.boltPath(a, b, branches: branches)
                CATransaction.begin(); CATransaction.setDisableActions(true)
                glow.path = p; core.path = p
                CATransaction.commit()
            }
        }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1; fade.toValue = 0
        fade.beginTime = CACurrentMediaTime() + 0.1
        fade.duration = max(0.05, duration - 0.1)
        fade.fillMode = .forwards; fade.isRemovedOnCompletion = false
        glow.add(fade, forKey: nil); core.add(fade, forKey: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.05) {
            glow.removeFromSuperlayer(); core.removeFromSuperlayer()
        }
    }

    /// 채찍 끝에서 튀는 섬광
    func flash(at p: NSPoint, big: Bool) {
        guard let root = layer else { return }
        let size: CGFloat = big ? 200 : 80
        let c = size / 2
        let f = CAShapeLayer()
        f.frame = CGRect(x: p.x - c, y: p.y - c, width: size, height: size)
        f.contentsScale = scale
        let fp = CGMutablePath()
        let rays = big ? 14 : 8
        for i in 0..<rays {
            let a = Double(i) * 2 * .pi / Double(rays) + .pi / 8
            let r1 = Double(c) * 0.25, r2 = Double(c) * (i % 2 == 0 ? 0.9 : 0.65)
            fp.move(to: CGPoint(x: Double(c) + cos(a) * r1, y: Double(c) + sin(a) * r1))
            fp.addLine(to: CGPoint(x: Double(c) + cos(a) * r2, y: Double(c) + sin(a) * r2))
        }
        f.path = fp
        f.fillColor = nil
        f.strokeColor = NSColor(calibratedRed: 1, green: 0.9, blue: 0.4, alpha: 1).cgColor
        f.lineWidth = big ? 5 : 3; f.lineCap = .round
        f.shadowColor = NSColor.orange.cgColor; f.shadowRadius = 6; f.shadowOpacity = big ? 1 : 0
        f.opacity = 0
        root.addSublayer(f)

        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 0.3; grow.toValue = 1.3
        let vanish = CABasicAnimation(keyPath: "opacity")
        vanish.fromValue = 1; vanish.toValue = 0
        let g = CAAnimationGroup()
        g.animations = [grow, vanish]
        g.duration = big ? 0.4 : 0.22
        g.timingFunction = CAMediaTimingFunction(name: .easeOut)
        g.fillMode = .forwards; g.isRemovedOnCompletion = false
        f.add(g, forKey: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + g.duration + 0.05) { f.removeFromSuperlayer() }
    }

    func shake(_ amount: CGFloat) {
        guard let root = layer else { return }
        let a = amount
        for (key, vals) in [("sublayerTransform.translation.x", [0, a, -a, a * 0.6, -a * 0.6, a * 0.3, 0]),
                            ("sublayerTransform.translation.y", [0, -a * 0.7, a * 0.7, -a * 0.4, a * 0.4, 0, 0])] {
            let k = CAKeyframeAnimation(keyPath: key)
            k.values = vals
            k.duration = 0.25
            root.add(k, forKey: key)
        }
    }

    func screenFlash() { tintFlash(.white, peak: 0.9) }

    func tintFlash(_ color: NSColor, peak: Float) {
        guard let root = layer else { return }
        let w = CALayer()
        w.frame = bounds
        w.backgroundColor = color.cgColor
        w.opacity = 0
        root.addSublayer(w)
        let a = CAKeyframeAnimation(keyPath: "opacity")
        a.values = [peak, peak * 0.2, peak * 0.75, 0].map { NSNumber(value: $0) }
        a.keyTimes = [0, 0.15, 0.3, 1]
        a.duration = 0.45
        w.add(a, forKey: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { w.removeFromSuperlayer() }
    }

    func setDim(_ target: Float, duration: Double) {
        guard let root = layer else { return }
        if dim.superlayer == nil {
            dim.frame = bounds
            dim.backgroundColor = NSColor.black.cgColor
            dim.opacity = 0
            root.insertSublayer(dim, at: 0)
        }
        let a = CABasicAnimation(keyPath: "opacity")
        a.fromValue = dim.presentation()?.opacity ?? dim.opacity
        a.toValue = target
        a.duration = duration
        dim.opacity = target
        dim.add(a, forKey: "dim")
    }

    /// 말풍선 ("언제 끝나?")
    func showBubble(_ text: String, at p: NSPoint, big: Bool) {
        guard let root = layer else { return }
        let fs: CGFloat = big ? 26 : 16
        let font = NSFont.boldSystemFont(ofSize: fs)
        let ts = (text as NSString).size(withAttributes: [.font: font])
        let w = ceil(ts.width) + 28, h = ceil(ts.height) + 14
        var x = p.x - w / 2, y = p.y + 28
        x = max(10, min(bounds.width - w - 10, x))         // 화면 밖으로 안 나가게
        y = max(10, min(bounds.height - h - 60, y))

        let bubble = CALayer()
        bubble.frame = CGRect(x: x, y: y, width: w, height: h)
        bubble.backgroundColor = NSColor.white.cgColor
        bubble.cornerRadius = h / 2
        bubble.borderColor = NSColor.black.cgColor
        bubble.borderWidth = 2
        bubble.contentsScale = scale

        let t = CATextLayer()
        t.frame = CGRect(x: 0, y: (h - ceil(ts.height)) / 2, width: w, height: ceil(ts.height))
        t.string = text
        t.font = font
        t.fontSize = fs
        t.foregroundColor = NSColor.black.cgColor
        t.alignmentMode = .center
        t.contentsScale = scale
        bubble.addSublayer(t)
        bubble.opacity = 0
        root.addSublayer(bubble)

        let rise = CABasicAnimation(keyPath: "position.y")
        rise.fromValue = bubble.position.y; rise.toValue = bubble.position.y + 40
        let op = CAKeyframeAnimation(keyPath: "opacity")
        op.values = [0, 1, 1, 0]; op.keyTimes = [0, 0.1, 0.7, 1]
        let g = CAAnimationGroup()
        g.animations = [rise, op]; g.duration = big ? 2.0 : 1.4
        g.fillMode = .forwards; g.isRemovedOnCompletion = false
        bubble.add(g, forKey: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + g.duration + 0.1) { bubble.removeFromSuperlayer() }
    }
}

// MARK: - 속성 효과 (번개 / 바람 / 불 / 물)

enum Element: String, CaseIterable {
    case lightning, wind, fire, water, random

    var title: String {
        switch self {
        case .lightning: return "⚡ 번개"
        case .wind: return "🌪 바람"
        case .fire: return "🔥 불"
        case .water: return "💧 물"
        case .random: return "🎲 랜덤 (매번 바뀜)"
        }
    }

    /// 랜덤이면 실제로 쓸 속성 하나 고르기
    var resolved: Element {
        self == .random ? [Element.lightning, .wind, .fire, .water].randomElement()! : self
    }

    static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
        NSColor(calibratedRed: r, green: g, blue: b, alpha: a)
    }

    /// 필살기 때 채찍 둘레에 은은하게 도는 빛
    var glow: CGColor {
        switch self {
        case .lightning, .random: return Self.rgb(0.4, 0.75, 1).cgColor
        case .wind: return Self.rgb(0.75, 1, 0.92).cgColor
        case .fire: return Self.rgb(1, 0.35, 0.05).cgColor
        case .water: return Self.rgb(0.25, 0.6, 1).cgColor
        }
    }
}

/// 파티클 하나의 규칙
func particle(_ img: CGImage, color: NSColor, rate: Float, life: Float, lifeRange: Float = 0,
              vel: CGFloat, velRange: CGFloat = 0, lon: CGFloat = 0, range: CGFloat = .pi * 2,
              yAcc: CGFloat = 0, scale: CGFloat, scaleRange: CGFloat = 0, scaleSpeed: CGFloat = 0,
              alphaSpeed: Float = 0, spin: CGFloat = 0, xAcc: CGFloat = 0, colorRange: Float = 0,
              rSpeed: Float = 0, gSpeed: Float = 0, bSpeed: Float = 0) -> CAEmitterCell {
    let c = CAEmitterCell()
    c.contents = img
    c.color = color.cgColor
    c.birthRate = rate
    c.lifetime = life; c.lifetimeRange = lifeRange
    c.velocity = vel; c.velocityRange = velRange
    c.emissionLongitude = lon; c.emissionRange = range
    c.xAcceleration = xAcc; c.yAcceleration = yAcc
    c.scale = scale; c.scaleRange = scaleRange; c.scaleSpeed = scaleSpeed
    c.alphaSpeed = alphaSpeed
    c.spin = spin; c.spinRange = spin * 2
    c.redRange = colorRange; c.greenRange = colorRange; c.blueRange = colorRange * 0.5
    c.redSpeed = rSpeed; c.greenSpeed = gSpeed; c.blueSpeed = bSpeed   // 시간이 지나며 색이 변함 (불꽃: 노랑 → 빨강)
    return c
}

/// 파티클 그림 (전부 코드로 생성)
enum Sprite {
    static let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
    static let clear = CGColor(red: 1, green: 1, blue: 1, alpha: 0)

    static let soft = radial(64, inner: 0)      // 부드러운 빛 덩어리 (안개)
    static let dot = radial(16, inner: 0.5)     // 작은 알갱이 (불씨, 물보라, 스파크, 먼지)

    /// 위로 길쭉한 불꽃 한 조각
    static let flame: CGImage = image(32, 48) { ctx in
        ctx.scaleBy(x: 1, y: 1.5)
        let g = gradient([white, CGColor(red: 1, green: 1, blue: 1, alpha: 0.6), clear], [0, 0.35, 1])
        ctx.drawRadialGradient(g, startCenter: CGPoint(x: 16, y: 12), startRadius: 0,
                               endCenter: CGPoint(x: 16, y: 15), endRadius: 16, options: [])
    }

    /// 몽글몽글한 연기 덩어리
    static let smoke: CGImage = image(64, 64) { ctx in
        for _ in 0..<7 {
            let c = CGPoint(x: CGFloat.random(in: 20...44), y: CGFloat.random(in: 20...44))
            let r = CGFloat.random(in: 12...20)
            let g = gradient([CGColor(red: 1, green: 1, blue: 1, alpha: 0.45), clear], [0, 1])
            ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: r, options: [])
        }
    }

    /// 반짝이는 물방울 (파란 몸통 + 흰 하이라이트)
    static let drop: CGImage = image(20, 20) { ctx in
        let g = gradient([CGColor(red: 0.85, green: 0.95, blue: 1, alpha: 0.95),
                          CGColor(red: 0.3, green: 0.55, blue: 0.9, alpha: 0.85),
                          CGColor(red: 0.2, green: 0.45, blue: 0.85, alpha: 0)], [0, 0.8, 1])
        ctx.drawRadialGradient(g, startCenter: CGPoint(x: 8, y: 12), startRadius: 0,
                               endCenter: CGPoint(x: 10, y: 10), endRadius: 10, options: [])
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.9))
        ctx.fillEllipse(in: CGRect(x: 5.5, y: 11.5, width: 3.5, height: 3.5))
    }

    static let rain: CGImage = image(6, 36) { ctx in
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.9))
        ctx.addPath(CGPath(roundedRect: CGRect(x: 1, y: 0, width: 4, height: 36),
                           cornerWidth: 2, cornerHeight: 2, transform: nil))
        ctx.fillPath()
    }

    /// 나뭇잎 (색은 파티클에서 입힘)
    static let leaf: CGImage = image(22, 12) { ctx in
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 1, y: 6))
        p.addQuadCurve(to: CGPoint(x: 21, y: 6), control: CGPoint(x: 11, y: 13))
        p.addQuadCurve(to: CGPoint(x: 1, y: 6), control: CGPoint(x: 11, y: -1))
        ctx.addPath(p)
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
        ctx.fillPath()
        ctx.setStrokeColor(CGColor(red: 0.55, green: 0.55, blue: 0.55, alpha: 0.9))
        ctx.setLineWidth(0.8)
        ctx.move(to: CGPoint(x: 2, y: 6)); ctx.addLine(to: CGPoint(x: 19, y: 6))
        ctx.strokePath()
    }

    /// 불탄 자국
    static let scorch: CGImage = image(96, 96) { ctx in
        let center = gradient([CGColor(red: 0.05, green: 0.03, blue: 0.02, alpha: 0.85),
                               CGColor(red: 0.12, green: 0.06, blue: 0.02, alpha: 0)], [0, 1])
        ctx.drawRadialGradient(center, startCenter: CGPoint(x: 48, y: 48), startRadius: 0,
                               endCenter: CGPoint(x: 48, y: 48), endRadius: 30, options: [])
        for _ in 0..<9 {
            let c = CGPoint(x: CGFloat.random(in: 22...74), y: CGFloat.random(in: 22...74))
            let g = gradient([CGColor(red: 0.08, green: 0.04, blue: 0.02, alpha: 0.4),
                              CGColor(red: 0.2, green: 0.08, blue: 0.02, alpha: 0)], [0, 1])
            ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c,
                                   endRadius: CGFloat.random(in: 10...22), options: [])
        }
    }

    /// 젖은 자국
    static let splat: CGImage = image(96, 96) { ctx in
        ctx.setFillColor(CGColor(red: 0.45, green: 0.7, blue: 1, alpha: 0.28))
        ctx.fillEllipse(in: CGRect(x: 26, y: 26, width: 44, height: 44))
        for _ in 0..<14 {
            let a = CGFloat.random(in: 0..<(2 * .pi))
            let d = CGFloat.random(in: 14...40)
            let r = CGFloat.random(in: 2...9)
            let c = CGPoint(x: 48 + cos(a) * d, y: 48 + sin(a) * d)
            ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        }
        ctx.setStrokeColor(CGColor(red: 0.85, green: 0.95, blue: 1, alpha: 0.5))
        ctx.setLineWidth(1.5)
        ctx.strokeEllipse(in: CGRect(x: 28, y: 28, width: 40, height: 40))
    }

    static func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
        CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: locations)!
    }

    static func radial(_ size: Int, inner: CGFloat) -> CGImage {
        image(size, size) { ctx in
            let g = gradient([white, white, clear], [0, inner, 1])
            let c = CGPoint(x: CGFloat(size) / 2, y: CGFloat(size) / 2)
            ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c,
                                   endRadius: CGFloat(size) / 2, options: [])
        }
    }

    static func image(_ w: Int, _ h: Int, _ draw: (CGContext) -> Void) -> CGImage {
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        draw(ctx)
        return ctx.makeImage()!
    }
}

// MARK: - 속성 소리

extension Synth {
    /// 쉬이익~ 바람
    static func windGust(_ dur: Double, big: Bool) -> [Double] {
        var y = 0.0, y2 = 0.0
        return (0..<count(dur)).map { i in
            let t = Double(i) / sr
            let r = rnd()
            let c = 0.015 + 0.05 * (0.5 + 0.5 * sin(2 * .pi * t * (big ? 1.6 : 4)))   // 휘몰아치는 느낌
            y += c * (r - y)
            y2 += 0.2 * (r - y2)
            let env = min(1, t / (big ? 0.15 : 0.04)) * exp(-t * (big ? 1.3 : 5))
            return (y * 7 + y2 * 0.25) * env
        }
    }

    /// 화르륵 + 타닥타닥
    static func fireBurst(_ dur: Double, big: Bool) -> [Double] {
        var low = 0.0, mid = 0.0, pop = 0.0
        return (0..<count(dur)).map { i in
            let t = Double(i) / sr
            let r = rnd()
            low += 0.03 * (r - low)
            mid += 0.12 * (r - mid)
            let env = min(1, t / 0.03) * exp(-t * (big ? 1.6 : 5))
            if Double.random(in: 0..<1) < (big ? 0.0018 : 0.0009) * exp(-t * 1.2) { pop = 1 }
            pop *= 0.94
            return low * env * 9 + mid * env * 0.9 + pop * r * 0.7 + (big && t < 0.002 ? 1 : 0)
        }
    }

    /// 촤악 + 똑똑 물방울
    static func splash(_ dur: Double, big: Bool) -> [Double] {
        var mid = 0.0
        var s = (0..<count(dur)).map { i -> Double in
            let t = Double(i) / sr
            let r = rnd()
            mid += 0.3 * (r - mid)
            return r * exp(-t * 16) * 0.6 + mid * exp(-t * (big ? 3 : 7)) * 1.3
        }
        for _ in 0..<(big ? 70 : 18) {
            let start = Int(Double.random(in: 0.02...(dur * 0.85)) * sr)
            let f = Double.random(in: 900...3200)
            let a = Double.random(in: 0.08...0.25)
            let n = min(count(0.05), s.count - start)
            if n <= 0 { continue }
            for k in 0..<n {
                let t = Double(k) / sr
                s[start + k] += sin(2 * .pi * f * t * (1 + t * 8)) * a * exp(-t * 80)
            }
        }
        return s
    }
}

extension Sfx {
    static let windHit = Sfx(Synth.windGust(0.6, big: false))
    static let windBig = Sfx(Synth.windGust(2.0, big: true))
    static let fireHit = Sfx(Synth.fireBurst(0.7, big: false))
    static let fireBig = Sfx(Synth.fireBurst(2.0, big: true))
    static let splashHit = Sfx(Synth.splash(0.7, big: false))
    static let splashBig = Sfx(Synth.splash(1.8, big: true))
}

// MARK: - 속성 효과 그리기 (전부 '맞는 순간'에만)

extension WhipView {
    @discardableResult
    func emitter(at p: CGPoint, cells: [CAEmitterCell], additive: Bool,
                 shape: CAEmitterLayerEmitterShape = .point, size: CGSize = .zero,
                 on: Double, life: Double) -> CAEmitterLayer {
        let e = CAEmitterLayer()
        e.frame = bounds
        e.emitterPosition = p
        e.emitterShape = shape
        e.emitterSize = size
        e.renderMode = additive ? .additive : .unordered
        e.emitterCells = cells
        e.beginTime = CACurrentMediaTime()
        layer?.addSublayer(e)
        DispatchQueue.main.asyncAfter(deadline: .now() + on) {     // on초 동안 뿜고
            CATransaction.begin(); CATransaction.setDisableActions(true)
            e.birthRate = 0
            CATransaction.commit()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + on + life) { e.removeFromSuperlayer() }  // 남은 게 사라지면 정리
        return e
    }

    /// 바닥에 잠깐 남는 자국 (불탄 자국, 젖은 자국)
    func mark(_ img: CGImage, at p: CGPoint, radius r: CGFloat, peak: Float, duration: Double) {
        guard let root = layer else { return }
        let l = CALayer()
        l.contents = img
        l.bounds = CGRect(x: 0, y: 0, width: r * 2, height: r * 2)
        l.position = p
        l.transform = CATransform3DMakeRotation(CGFloat.random(in: 0..<(2 * .pi)), 0, 0, 1)
        l.opacity = 0
        root.insertSublayer(l, at: dim.superlayer == nil ? 0 : 1)   // 다른 효과보다 아래에
        let a = CAKeyframeAnimation(keyPath: "opacity")
        a.values = [0, peak, peak, 0].map { NSNumber(value: $0) }
        a.keyTimes = [0, 0.05, 0.6, 1]
        a.duration = duration
        l.add(a, forKey: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { l.removeFromSuperlayer() }
    }

    /// 찰싹! 하는 순간의 공기 충격파 + 먼지 (모든 속성 공통)
    func impact(at p: CGPoint, dir: Double) {
        guard let root = layer else { return }
        for i in 0..<2 {
            let r = CAShapeLayer()
            r.contentsScale = scale
            r.bounds = .zero
            r.position = p
            r.path = CGPath(ellipseIn: CGRect(x: -26, y: -20, width: 52, height: 40), transform: nil)
            r.fillColor = nil
            r.strokeColor = NSColor.white.withAlphaComponent(0.75 - 0.3 * CGFloat(i)).cgColor
            r.lineWidth = 1.6 - 0.6 * CGFloat(i)
            r.opacity = 0
            root.addSublayer(r)
            let grow = CABasicAnimation(keyPath: "transform.scale")
            grow.fromValue = 0.15; grow.toValue = 1.3 + 0.5 * Double(i)
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1; fade.toValue = 0
            let g = CAAnimationGroup()
            g.animations = [grow, fade]
            g.duration = 0.2 + 0.06 * Double(i)
            g.timingFunction = CAMediaTimingFunction(name: .easeOut)
            r.add(g, forKey: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + g.duration) { r.removeFromSuperlayer() }
        }
        emitter(at: p, cells: [particle(Sprite.dot, color: Element.rgb(0.85, 0.82, 0.75, 0.8), rate: 260, life: 0.35,
                                        vel: 160, velRange: 80, lon: CGFloat(dir), range: 1.2,
                                        scale: 0.18, alphaSpeed: -2.5)],
                additive: false, on: 0.05, life: 0.5)
    }

    /// 보통 채찍 / 필살기 연타 한 방의 속성 효과
    func elementHit(_ el: Element, at tip: CGPoint, dir: Double, volume: Float) {
        switch el {
        case .lightning, .random:
            for _ in 0..<3 {
                let end = tip.moved(Double.random(in: 0..<(2 * .pi)), Double.random(in: 40...80))
                bolt(from: tip, to: end, width: 1.5, branches: 0, duration: 0.18)
            }
            sparks(at: tip, k: 1)
            Sfx.zap.play(volume: volume * 0.8)
        case .wind:
            swirls(at: tip, count: 2, maxR: 60, dir: dir)
            debris(at: tip, dir: dir, k: 1)
            Sfx.windHit.play(volume: volume)
        case .fire:
            fireBurst(at: tip, size: 1)
            mark(Sprite.scorch, at: tip, radius: 34, peak: 0.7, duration: 2.0)
            Sfx.fireHit.play(volume: volume)
        case .water:
            splash(at: tip, size: 1)
            Sfx.splashHit.play(volume: volume)
        }
    }

    /// 필살기 마무리 한 방
    func elementFinisher(_ el: Element, from o: CGPoint, to tip: CGPoint, dir: Double, max: Bool) {
        switch el {
        case .lightning, .random:
            Sfx.thunder.play(volume: 1)
            for _ in 0..<3 {
                let off = CGPoint(x: CGFloat.random(in: -30...30), y: CGFloat.random(in: -30...30))
                bolt(from: o, to: tip + off, width: 3, branches: 3, duration: 0.4)
            }
            for k in 0..<(max ? 3 : 1) {      // 하늘에서 내리꽂는 낙뢰
                let top = CGPoint(x: tip.x + CGFloat.random(in: -120...120) * CGFloat(k), y: bounds.maxY + 10)
                bolt(from: top, to: tip, width: 4.5, branches: 4, duration: 0.5)
            }
            sparks(at: tip, k: 3)
            mark(Sprite.scorch, at: tip, radius: 70, peak: 0.8, duration: 2.5)
            screenFlash()
            flash(at: tip, big: true)
            shake(16)

        case .fire:
            Sfx.fireBig.play(volume: 1)
            for k in 0...5 {                  // 채찍 지나간 자리를 따라 불이 옮겨붙음
                let f = CGFloat(k) / 5
                let pt = CGPoint(x: o.x + (tip.x - o.x) * f, y: o.y + (tip.y - o.y) * f)
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(k) * 0.035) { [weak self] in
                    self?.fireBurst(at: pt, size: 0.7, on: 0.3)
                }
            }
            fireBurst(at: tip, size: max ? 2.6 : 2.0, on: 0.35)
            emitter(at: tip, cells: [                                      // 치솟는 불기둥
                particle(Sprite.flame, color: Element.rgb(1, 0.75, 0.3), rate: 800, life: 1.0, lifeRange: 0.3,
                         vel: 600, velRange: 180, lon: .pi / 2, range: 0.3, yAcc: 200,
                         scale: 1.4, scaleRange: 0.5, scaleSpeed: -0.6, alphaSpeed: -1.0,
                         gSpeed: -1.2, bSpeed: -0.5),
                particle(Sprite.flame, color: Element.rgb(1, 0.95, 0.7), rate: 350, life: 0.6,
                         vel: 480, lon: .pi / 2, range: 0.18, scale: 0.8, scaleSpeed: -0.8, alphaSpeed: -1.6),
            ], additive: true, on: max ? 0.8 : 0.5, life: 1.4)
            emitter(at: CGPoint(x: tip.x, y: tip.y + 120), cells: [        // 그 위로 피어오르는 검은 연기
                particle(Sprite.smoke, color: Element.rgb(0.18, 0.16, 0.15, 0.6), rate: 90, life: 2.4, lifeRange: 0.6,
                         vel: 160, velRange: 60, lon: .pi / 2, range: 0.5, yAcc: 40,
                         scale: 1.2, scaleRange: 0.4, scaleSpeed: 1.0, alphaSpeed: -0.25, spin: 0.4),
            ], additive: false, on: max ? 1.0 : 0.7, life: 2.6)
            mark(Sprite.scorch, at: tip, radius: 110, peak: 0.85, duration: 3.0)
            tintFlash(Element.rgb(1, 0.45, 0.1), peak: 0.45)
            shake(16)

        case .water:
            Sfx.splashBig.play(volume: 1)
            splash(at: tip, size: max ? 2.6 : 2.0)
            emitter(at: CGPoint(x: bounds.midX, y: bounds.maxY + 20), cells: [   // 뒤이어 쏟아지는 비
                particle(Sprite.rain, color: Element.rgb(0.75, 0.9, 1, 0.65), rate: max ? 900 : 500, life: 1.8,
                         vel: 600, velRange: 150, lon: -.pi / 2, range: 0.03, yAcc: -900,
                         scale: 0.55, scaleRange: 0.3, alphaSpeed: -0.2),
            ], additive: false, shape: .line, size: CGSize(width: bounds.width, height: 0), on: 1.0, life: 2.0)
            tintFlash(Element.rgb(0.2, 0.5, 1), peak: 0.28)
            shake(10)

        case .wind:
            Sfx.windBig.play(volume: 1)
            tornado(at: tip, big: max)
            gust(dir: dir, count: max ? 40 : 26)
            debris(at: tip, dir: dir, k: 3)
            swirls(at: tip, count: 4, maxR: 130, dir: dir)
            tintFlash(.white, peak: 0.18)
            shake(12)
        }
    }

    /// 번개 맞은 자리에서 튀는 불똥
    func sparks(at p: CGPoint, k: CGFloat) {
        emitter(at: p, cells: [
            particle(Sprite.dot, color: Element.rgb(0.85, 0.93, 1), rate: Float(400 * k), life: 0.5, lifeRange: 0.2,
                     vel: 260 * k, velRange: 120 * k, yAcc: -700, scale: 0.25, scaleRange: 0.1, alphaSpeed: -2),
        ], additive: true, on: 0.05, life: 0.7)
    }

    /// 불: 연기 → 불꽃(노랑에서 빨강으로) → 위로 떠오르는 불씨
    func fireBurst(at p: CGPoint, size k: CGFloat, on: Double = 0.12) {
        emitter(at: CGPoint(x: p.x, y: p.y + 20 * k), cells: [
            particle(Sprite.smoke, color: Element.rgb(0.22, 0.2, 0.19, 0.55), rate: Float(45 * k), life: 1.8,
                     lifeRange: 0.6, vel: 45 * k, velRange: 25 * k, lon: .pi / 2, range: 0.9, yAcc: 60,
                     scale: 0.45 * k, scaleRange: 0.2 * k, scaleSpeed: 0.8, alphaSpeed: -0.3, spin: 0.5),
        ], additive: false, on: on + 0.2, life: 2.4)
        emitter(at: p, cells: [
            particle(Sprite.flame, color: Element.rgb(1, 0.95, 0.75), rate: Float(220 * k), life: 0.3, lifeRange: 0.1,
                     vel: 60 * k, velRange: 30 * k, lon: .pi / 2, range: 1.2, yAcc: 320,
                     scale: 0.45 * k, scaleRange: 0.15 * k, scaleSpeed: -1, alphaSpeed: -2.8),
            particle(Sprite.flame, color: Element.rgb(1, 0.7, 0.25), rate: Float(420 * k), life: 0.8, lifeRange: 0.3,
                     vel: 120 * k, velRange: 60 * k, lon: .pi / 2, range: 1.8, yAcc: 340,
                     scale: 0.7 * k, scaleRange: 0.3 * k, scaleSpeed: -0.55, alphaSpeed: -1.2,
                     gSpeed: -1.5, bSpeed: -0.6),
            particle(Sprite.dot, color: Element.rgb(1, 0.75, 0.35), rate: Float(110 * k), life: 1.6, lifeRange: 0.7,
                     vel: 200 * k, velRange: 120 * k, yAcc: 90, scale: 0.22, scaleRange: 0.1, alphaSpeed: -0.6,
                     xAcc: CGFloat.random(in: -40...40), gSpeed: -0.4),
        ], additive: true, on: on, life: 1.8)
    }

    /// 물: 왕관 모양 물보라 + 잔물방울 + 물안개 + 물결 + 젖은 자국
    func splash(at p: CGPoint, size k: CGFloat) {
        emitter(at: p, cells: [
            particle(Sprite.drop, color: .white, rate: Float(520 * k), life: 1.2, lifeRange: 0.3,
                     vel: 330 * k, velRange: 120 * k, lon: .pi / 2, range: 1.2, yAcc: -1300,
                     scale: 0.6, scaleRange: 0.3, alphaSpeed: -0.45),
            particle(Sprite.dot, color: Element.rgb(0.8, 0.92, 1, 0.85), rate: Float(500 * k), life: 0.7,
                     vel: 460 * k, velRange: 200 * k, lon: .pi / 2, range: 2.6, yAcc: -1100,
                     scale: 0.2, scaleRange: 0.1, alphaSpeed: -1.2),
            particle(Sprite.soft, color: Element.rgb(0.85, 0.93, 1, 0.22), rate: Float(70 * k), life: 1.0,
                     vel: 50 * k, velRange: 30 * k, scale: 1.0 * k, scaleSpeed: 1.1, alphaSpeed: -0.25),
        ], additive: false, on: 0.08, life: 1.5)
        ripples(at: p, count: k > 1 ? 4 : 2, radius: 70 * k)
        mark(Sprite.splat, at: p, radius: 50 * k, peak: 0.9, duration: 1.8)
    }

    /// 물결 동그라미 (밝은 테두리 + 그 아래 어두운 테두리)
    func ripples(at p: CGPoint, count: Int, radius: CGFloat) {
        guard let root = layer else { return }
        for i in 0..<count {
            let ring = CALayer()
            ring.bounds = .zero
            ring.position = p
            ring.opacity = 0
            for (color, width, dy) in [(Element.rgb(0.2, 0.45, 0.8, 0.5), 1.0, -2.0),
                                       (Element.rgb(0.88, 0.96, 1, 0.85), 1.8, 0.0)] as [(NSColor, CGFloat, CGFloat)] {
                let l = CAShapeLayer()
                l.contentsScale = scale
                l.path = CGPath(ellipseIn: CGRect(x: -radius, y: -radius * 0.35 + dy, width: radius * 2,
                                                  height: radius * 0.7), transform: nil)
                l.fillColor = nil
                l.strokeColor = color.cgColor
                l.lineWidth = width
                ring.addSublayer(l)
            }
            root.addSublayer(ring)

            let grow = CABasicAnimation(keyPath: "transform.scale")
            grow.fromValue = 0.15; grow.toValue = 1
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.9; fade.toValue = 0
            let g = CAAnimationGroup()
            g.animations = [grow, fade]
            g.duration = 0.8
            g.beginTime = CACurrentMediaTime() + Double(i) * 0.14
            g.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ring.add(g, forKey: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.14 + 0.85) { ring.removeFromSuperlayer() }
        }
    }

    /// 바람: 날아가는 나뭇잎 + 흙먼지 + 희미한 공기 덩어리
    func debris(at p: CGPoint, dir: Double, k: CGFloat) {
        emitter(at: p, cells: [
            particle(Sprite.leaf, color: Element.rgb(0.5, 0.55, 0.25), rate: Float(30 * k), life: 1.4, lifeRange: 0.5,
                     vel: 420, velRange: 200, lon: CGFloat(dir), range: 0.6, yAcc: -160,
                     scale: 0.7, scaleRange: 0.3, alphaSpeed: -0.5, spin: 5, colorRange: 0.25),
            particle(Sprite.dot, color: Element.rgb(0.78, 0.72, 0.62, 0.7), rate: Float(320 * k), life: 0.8,
                     vel: 380, velRange: 180, lon: CGFloat(dir), range: 0.7,
                     scale: 0.14, scaleRange: 0.08, alphaSpeed: -1),
            particle(Sprite.soft, color: Element.rgb(1, 1, 1, 0.12), rate: Float(60 * k), life: 0.5,
                     vel: 500, lon: CGFloat(dir), range: 0.3, scale: 0.5, scaleSpeed: 1, alphaSpeed: -0.25),
        ], additive: false, on: 0.1 * Double(k), life: 1.6)
    }

    /// 희미하게 휘감기는 공기 흐름
    func swirls(at p: CGPoint, count: Int, maxR: CGFloat, dir: Double) {
        guard let root = layer else { return }
        for i in 0..<count {
            let r = maxR * (0.45 + 0.55 * CGFloat(i) / CGFloat(Swift.max(1, count - 1)))
            let a0 = CGFloat.random(in: 0..<(2 * .pi))
            let l = CAShapeLayer()
            l.contentsScale = scale
            l.bounds = .zero
            l.position = p.moved(dir, Double(r) * 0.3)
            let path = CGMutablePath()
            path.addArc(center: .zero, radius: r, startAngle: a0, endAngle: a0 + 3.6, clockwise: false)
            l.path = path
            l.fillColor = nil
            l.strokeColor = NSColor.white.withAlphaComponent(0.4).cgColor
            l.lineWidth = Swift.max(0.8, 1.8 - CGFloat(i) * 0.3)
            l.lineCap = .round
            l.strokeEnd = 0
            root.addSublayer(l)

            let draw = CABasicAnimation(keyPath: "strokeEnd")
            draw.fromValue = 0; draw.toValue = 1; draw.duration = 0.2
            draw.fillMode = .forwards; draw.isRemovedOnCompletion = false
            let erase = CABasicAnimation(keyPath: "strokeStart")
            erase.fromValue = 0; erase.toValue = 1; erase.beginTime = 0.12; erase.duration = 0.3
            erase.fillMode = .both
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = 0; spin.toValue = -2.2; spin.duration = 0.42
            let grow = CABasicAnimation(keyPath: "transform.scale")
            grow.fromValue = 0.6; grow.toValue = 1.5; grow.duration = 0.42
            let g = CAAnimationGroup()
            g.animations = [draw, erase, spin, grow]
            g.duration = 0.44
            g.fillMode = .forwards; g.isRemovedOnCompletion = false
            l.add(g, forKey: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { l.removeFromSuperlayer() }
        }
    }

    /// 회오리 (흐릿한 공기 고리 + 빨려 올라가는 먼지와 잎)
    func tornado(at p: CGPoint, big: Bool) {
        guard let root = layer else { return }
        let container = CALayer()
        container.frame = bounds
        root.addSublayer(container)
        let rings = 16
        let height: CGFloat = big ? 420 : 320
        for i in 0..<rings {
            let f = CGFloat(i) / CGFloat(rings - 1)
            let w = 30 + (big ? 280 : 220) * f * f + 20 * f
            let h = w * 0.22
            let ring = CAShapeLayer()
            ring.contentsScale = scale
            ring.bounds = .zero
            ring.position = CGPoint(x: p.x, y: p.y - 30 + height * f)
            ring.path = CGPath(ellipseIn: CGRect(x: -w / 2, y: -h / 2, width: w, height: h), transform: nil)
            ring.fillColor = nil
            ring.strokeColor = Element.rgb(0.85, 0.82, 0.75, 0.25 + 0.3 * (1 - f)).cgColor
            ring.lineWidth = 1.6
            ring.lineCap = .round
            ring.lineDashPattern = [NSNumber(value: Double(w) * 0.3), NSNumber(value: Double(w) * 0.2)]
            container.addSublayer(ring)

            let spin = CABasicAnimation(keyPath: "lineDashPhase")      // 점선이 돌아서 회전하는 것처럼
            spin.fromValue = 0; spin.toValue = Double(w) * 0.5
            spin.duration = 0.18 + 0.1 * Double(f)
            spin.repeatCount = .infinity
            ring.add(spin, forKey: "spin")

            let sway = CAKeyframeAnimation(keyPath: "position.x")       // 위로 갈수록 크게 흔들림
            sway.values = [p.x, p.x + 22 * f, p.x - 22 * f, p.x]
            sway.duration = 0.6
            sway.repeatCount = .infinity
            ring.add(sway, forKey: "sway")
        }
        let appear = CAKeyframeAnimation(keyPath: "opacity")
        appear.values = [0, 1, 1, 0]
        appear.keyTimes = [0, 0.1, 0.75, 1]
        appear.duration = 1.7
        appear.fillMode = .forwards; appear.isRemovedOnCompletion = false
        container.add(appear, forKey: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { container.removeFromSuperlayer() }

        emitter(at: CGPoint(x: p.x, y: p.y + height * 0.2), cells: [
            particle(Sprite.dot, color: Element.rgb(0.75, 0.7, 0.6, 0.7), rate: 350, life: 1.1,
                     vel: 140, velRange: 80, yAcc: 300, scale: 0.15, scaleRange: 0.08, alphaSpeed: -0.8),
            particle(Sprite.leaf, color: Element.rgb(0.5, 0.55, 0.25), rate: 30, life: 1.4,
                     vel: 160, velRange: 80, yAcc: 280, scale: 0.6, scaleRange: 0.3, alphaSpeed: -0.6,
                     spin: 6, colorRange: 0.25),
        ], additive: false, shape: .circle, size: CGSize(width: 120, height: 30), on: 1.1, life: 1.4)
    }

    /// 화면을 가로지르는 희미한 바람 줄기
    func gust(dir: Double, count: Int) {
        guard let root = layer else { return }
        for _ in 0..<count {
            let len = Double.random(in: 120...320)
            let l = CAShapeLayer()
            l.contentsScale = scale
            l.bounds = .zero
            let path = CGMutablePath()
            path.move(to: .zero)
            path.addLine(to: CGPoint.zero.moved(dir, len))
            l.path = path
            l.strokeColor = NSColor.white.withAlphaComponent(CGFloat.random(in: 0.15...0.4)).cgColor
            l.lineWidth = CGFloat.random(in: 0.8...1.6)
            l.lineCap = .round
            l.opacity = 0
            let spot = CGPoint(x: CGFloat.random(in: bounds.minX...bounds.maxX),
                               y: CGFloat.random(in: bounds.minY...bounds.maxY))
            let from = spot.moved(dir + .pi, 700)
            l.position = from
            root.addSublayer(l)

            let delay = Double.random(in: 0...0.35)
            let dur = Double.random(in: 0.35...0.55)
            let move = CABasicAnimation(keyPath: "position")
            move.fromValue = NSValue(point: from)
            move.toValue = NSValue(point: from.moved(dir, 1400))
            let op = CAKeyframeAnimation(keyPath: "opacity")
            op.values = [0, 1, 1, 0]; op.keyTimes = [0, 0.15, 0.7, 1]
            let g = CAAnimationGroup()
            g.animations = [move, op]
            g.duration = dur
            g.beginTime = CACurrentMediaTime() + delay
            l.add(g, forKey: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay + dur + 0.05) { l.removeFromSuperlayer() }
        }
    }
}

extension WhipView {
    /// 화면 위쪽에 잠깐 떴다 사라지는 안내
    func toast(_ text: String) {
        guard let root = layer else { return }
        let font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        let ts = (text as NSString).size(withAttributes: [.font: font])
        let w = ceil(ts.width) + 36, h = ceil(ts.height) + 18
        let box = CALayer()
        box.frame = CGRect(x: (bounds.width - w) / 2, y: bounds.height - h - 60, width: w, height: h)
        box.backgroundColor = NSColor.black.withAlphaComponent(0.72).cgColor
        box.cornerRadius = h / 2
        let t = CATextLayer()
        t.frame = CGRect(x: 0, y: (h - ceil(ts.height)) / 2, width: w, height: ceil(ts.height))
        t.string = text
        t.font = font; t.fontSize = 15
        t.foregroundColor = NSColor.white.cgColor
        t.alignmentMode = .center
        t.contentsScale = scale
        box.addSublayer(t)
        box.opacity = 0
        root.addSublayer(box)
        let a = CAKeyframeAnimation(keyPath: "opacity")
        a.values = [0, 1, 1, 0]; a.keyTimes = [0, 0.08, 0.8, 1]
        a.duration = 2.6
        box.add(a, forKey: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { box.removeFromSuperlayer() }
    }
}

// MARK: - 자동 업데이트 (GitHub Releases)
//
// 1) 앱을 켤 때(그리고 메뉴의 "업데이트 확인…") GitHub의 최신 릴리스를 확인
// 2) 지금 버전보다 새 버전이면 패치 내용과 함께 물어봄
// 3) "업데이트" → Ppalli-x.x.x.zip을 받아서 앱을 바꾸고 다시 실행
//    (앱이 직접 받은 파일이라 "확인할 수 없는 개발자" 경고가 다시 뜨지 않음)
// 앱 폴더에 쓸 권한이 없으면 다운로드 페이지를 대신 열어 줌

let updateRepo = "Jojunhyeong/ppalli"

struct ReleaseInfo {
    let version: String
    let notes: String
    let pageURL: URL
    let zipURL: URL?
}

final class Updater: NSObject {
    static let shared = Updater()
    private let defaults = UserDefaults.standard
    private var busy = false

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    var autoCheck: Bool {
        get { defaults.object(forKey: "autoUpdateCheck") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "autoUpdateCheck") }
    }

    /// "1.0.10" > "1.0.9" 처럼 숫자로 비교
    static func isNewer(_ a: String, than b: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            s.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
                .split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        }
        let x = parts(a), y = parts(b)
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }

    /// 앱을 켤 때 조용히 확인 (새 버전이 없거나 인터넷이 안 되면 아무것도 안 뜸)
    func checkOnLaunch() {
        guard autoCheck, Bundle.main.bundleIdentifier != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { self.check(userInitiated: false) }
    }

    func check(userInitiated: Bool) {
        guard !busy else { return }
        busy = true
        fetchLatest { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy = false
                switch result {
                case .failure(let error):
                    if userInitiated { self.alert("업데이트를 확인하지 못했어요", error.localizedDescription) }
                case .success(let info):
                    if Self.isNewer(info.version, than: self.currentVersion) {
                        // 자동 확인에서는 "이 버전 건너뛰기"한 버전은 다시 묻지 않음
                        if !userInitiated, self.defaults.string(forKey: "skippedVersion") == info.version { return }
                        self.offer(info)
                    } else if userInitiated {
                        self.alert("최신 버전이에요", "지금 쓰고 있는 Ppalli \(self.currentVersion)이(가) 최신 버전이에요.")
                    }
                }
            }
        }
    }

    private func fetchLatest(_ done: @escaping (Result<ReleaseInfo, Error>) -> Void) {
        guard let url = URL(string: "https://api.github.com/repos/\(updateRepo)/releases/latest") else { return }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("Ppalli/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { data, response, error in
            if let error { done(.failure(error)); return }
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String,
                  let page = (json["html_url"] as? String).flatMap({ URL(string: $0) }) else {
                done(.failure(NSError(domain: "Ppalli", code: 1,
                                      userInfo: [NSLocalizedDescriptionKey: "GitHub에서 릴리스 정보를 읽지 못했어요."])))
                return
            }
            let assets = json["assets"] as? [[String: Any]] ?? []
            let zip = assets.first { ($0["name"] as? String)?.hasSuffix(".zip") == true }?["browser_download_url"] as? String
            let version = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            done(.success(ReleaseInfo(version: version,
                                      notes: Self.plainText(json["body"] as? String ?? ""),
                                      pageURL: page,
                                      zipURL: zip.flatMap({ URL(string: $0) }))))
        }.resume()
    }

    /// 릴리스 노트의 마크다운 기호를 걷어내서 알림 창에 보기 좋게
    static func plainText(_ md: String) -> String {
        var lines: [String] = []
        for raw in md.components(separatedBy: .newlines) {
            var l = raw
            if l.hasPrefix("#") { l = l.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces) }
            if l.hasPrefix("> ") { l = String(l.dropFirst(2)) }
            if l.hasPrefix("- ") || l.hasPrefix("* ") { l = "• " + l.dropFirst(2) }
            l = l.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "")
            lines.append(l)
        }
        let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.count > 900 ? String(text.prefix(900)) + "…" : text
    }

    /// 채찍 모드의 투명 창이 알림 창을 덮지 않도록 잠깐 꺼 둠
    private func clearOverlay() {
        if whipOnlyMode { (NSApp.delegate as? AppDelegate)?.setWhipOnly(false, quiet: true) }
    }

    private func offer(_ info: ReleaseInfo) {
        clearOverlay()
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "새 버전이 있어요: Ppalli \(info.version)"
        a.informativeText = "지금 버전: \(currentVersion)\n\n"
            + (info.notes.isEmpty ? "" : "바뀐 내용\n\(info.notes)\n\n")
            + "업데이트하면 앱이 잠깐 꺼졌다가 새 버전으로 다시 켜져요."
        a.addButton(withTitle: "업데이트")
        a.addButton(withTitle: "나중에")
        a.addButton(withTitle: "이 버전 건너뛰기")
        switch a.runModal() {
        case .alertFirstButtonReturn: install(info)
        case .alertThirdButtonReturn: defaults.set(info.version, forKey: "skippedVersion")
        default: break
        }
    }

    // MARK: 설치

    private func install(_ info: ReleaseInfo) {
        let appURL = Bundle.main.bundleURL
        let parent = appURL.deletingLastPathComponent()
        // 앱 폴더에 쓸 수 없거나(권한, 다운로드 폴더에서 바로 실행 등) zip이 없으면 → 다운로드 페이지
        guard let zipURL = info.zipURL,
              FileManager.default.isWritableFile(atPath: parent.path),
              !appURL.path.contains("/AppTranslocation/") else {
            alert("직접 받아 주세요",
                  "이 위치에서는 자동으로 바꿀 수 없어요. 다운로드 페이지를 열게요.\n"
                  + "(Ppalli를 응용 프로그램 폴더로 옮겨 두면 다음부터 자동으로 돼요.)")
            NSWorkspace.shared.open(info.pageURL)
            return
        }
        toast("⬇️ Ppalli \(info.version) 받는 중…")
        URLSession.shared.downloadTask(with: zipURL) { [weak self] tmp, response, error in
            // 받은 임시 파일은 이 블록이 끝나면 지워지므로 바로 옮겨 둠
            var saved: URL?
            if let tmp, error == nil, (response as? HTTPURLResponse)?.statusCode ?? 200 < 400 {
                let dst = FileManager.default.temporaryDirectory.appendingPathComponent("ppalli-\(UUID().uuidString).zip")
                if (try? FileManager.default.moveItem(at: tmp, to: dst)) != nil { saved = dst }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                guard let saved else {
                    self.alert("업데이트를 받지 못했어요", error?.localizedDescription ?? "다시 시도해 주세요.")
                    return
                }
                do {
                    try self.replace(app: appURL, withZip: saved)
                } catch {
                    self.alert("업데이트를 설치하지 못했어요",
                               error.localizedDescription + "\n다운로드 페이지를 열게요.")
                    NSWorkspace.shared.open(info.pageURL)
                }
            }
        }.resume()
    }

    private func replace(app appURL: URL, withZip zip: URL) throws {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("ppalli-update-\(UUID().uuidString)")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        let zipPath = work.appendingPathComponent("update.zip")
        try fm.moveItem(at: zip, to: zipPath)

        // 압축 풀기
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unzip.arguments = ["-x", "-k", zipPath.path, work.path]
        try unzip.run()
        unzip.waitUntilExit()
        let newApp = work.appendingPathComponent("Ppalli.app")
        guard unzip.terminationStatus == 0,
              let newID = Bundle(url: newApp)?.bundleIdentifier,
              newID == Bundle.main.bundleIdentifier else {
            throw NSError(domain: "Ppalli", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "받은 파일이 올바른 Ppalli 앱이 아니에요."])
        }

        // 지금 앱이 꺼지길 기다렸다가 → 바꾸고 → 다시 실행하는 작은 스크립트
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = """
        while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
        rm -rf "$1" && mv "$2" "$1"
        xattr -dr com.apple.quarantine "$1" 2>/dev/null
        open "$1"
        rm -rf "$3"
        """
        let sh = Process()
        sh.executableURL = URL(fileURLWithPath: "/bin/sh")
        sh.arguments = ["-c", script, "sh", appURL.path, newApp.path, work.path]
        try sh.run()
        NSApp.terminate(nil)
    }

    // MARK: 알림

    private func alert(_ title: String, _ text: String) {
        clearOverlay()
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.runModal()
    }

    private func toast(_ text: String) {
        (NSApp.delegate as? AppDelegate)?.views.first?.toast(text)
    }
}

// MARK: - 앱 (메뉴 막대 아이콘으로 설정)

/// GitHub 저장소 주소 (정보 창과 메뉴의 "홈페이지"에 쓰임)
let homepageURL = "https://github.com/Jojunhyeong/ppalli"

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    var windows: [FxWindow] = []
    var views: [WhipView] = []
    var count = 0

    var statusItem: NSStatusItem!
    let countItem = NSMenuItem(title: "채찍질 0회", action: nil, keyEquivalent: "")
    var keyMonitor: Any?
    var hotKeyRef: EventHotKeyRef?

    // 설정은 껐다 켜도 유지
    let defaults = UserDefaults.standard
    var element: Element {
        get { Element(rawValue: defaults.string(forKey: "element") ?? "") ?? .lightning }
        set { defaults.set(newValue.rawValue, forKey: "element") }
    }
    var phrasesText: String {
        get { defaults.string(forKey: "phrases") ?? "언제 끝나?, 빨리 해, 집중 좀 해, 그거 아니잖아, 다시 해" }
        set { defaults.set(newValue, forKey: "phrases") }
    }
    var showMenuBarIcon: Bool {
        get { defaults.object(forKey: "menuBarIcon") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "menuBarIcon"); statusItem.isVisible = newValue }
    }

    // MARK: 시작

    static let wakeNote = Notification.Name("com.ppalli.app.wake")

    func applicationWillFinishLaunching(_ notification: Notification) {
        // 이미 켜져 있는데 또 실행하면 → 새로 켜지 않고, 켜져 있는 쪽을 채찍 모드로
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).count > 1 {
            DistributedNotificationCenter.default().postNotificationName(Self.wakeNote, object: nil,
                                                                         userInfo: nil, deliverImmediately: true)
            exit(0)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = buildMainMenu()
        setupStatusItem()
        registerHotKey()
        // 채찍 모드에서 ESC = 모드 끄기
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53, whipOnlyMode { self?.setWhipOnly(false); return nil }
            return event
        }
        _ = [Sfx.whoosh, Sfx.crack, Sfx.zap, Sfx.thunder, Sfx.chargeRise, Sfx.chargeHold,   // 소리 미리 만들어 두기
             Sfx.windHit, Sfx.windBig, Sfx.fireHit, Sfx.fireBig, Sfx.splashHit, Sfx.splashBig]

        // 모니터마다 투명한 효과 창 (채찍 모드가 꺼지면 클릭이 전부 아래로 통과)
        for screen in NSScreen.screens {
            let w = FxWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.setFrame(screen.frame, display: true)
            w.isOpaque = false
            w.backgroundColor = .clear
            w.hasShadow = false
            w.ignoresMouseEvents = true
            w.level = .screenSaver
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

            let v = WhipView(frame: NSRect(origin: .zero, size: screen.frame.size))
            v.onHit = { [weak self, weak v] tip, aim, kind in
                guard let self, let v else { return }
                self.handleHit(tip: tip, aim: aim, kind: kind, in: v)
            }
            v.currentElement = { [weak self] in self?.element ?? .lightning }
            w.contentView = v
            w.orderFrontRegardless()
            windows.append(w)
            views.append(v)
        }

        DistributedNotificationCenter.default().addObserver(forName: Self.wakeNote, object: nil, queue: .main) { [weak self] _ in
            self?.setWhipOnly(true)
        }

        // 직접 실행하면 바로 채찍 모드. 로그인 때 자동 실행이 켜져 있으면 조용히 대기 (⌥ESC로 켜기)
        setWhipOnly(!loginItemEnabled)
        Updater.shared.checkOnLaunch()
    }

    /// Dock 아이콘 클릭 (또는 Finder/Spotlight에서 다시 실행) → 채찍 모드 켜기
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        setWhipOnly(true)
        return false
    }

    /// Dock 아이콘 우클릭 메뉴
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        controlItems().forEach { menu.addItem($0) }
        return menu
    }

    // MARK: 채찍 모드

    @objc func toggleWhipOnly() { setWhipOnly(!whipOnlyMode) }

    func setWhipOnly(_ on: Bool, quiet: Bool = false) {
        whipOnlyMode = on
        for w in windows {
            w.ignoresMouseEvents = !on
            // 완전 투명하면 클릭이 뒤로 빠지므로, 거의 안 보이는 정도만 칠함
            w.backgroundColor = on ? NSColor.black.withAlphaComponent(0.01) : .clear
            w.acceptsMouseMovedEvents = on
            w.invalidateCursorRects(for: w.contentView!)
        }
        views.forEach { $0.updateCrosshair() }
        if on {
            NSApp.activate(ignoringOtherApps: true)
            windows.first?.makeKeyAndOrderFront(nil)
            views.first?.toast("🎯 채찍 모드 · 클릭하면 채찍, 꾹 누르면 필살기 · ESC로 끄기")
        } else {
            NSCursor.arrow.set()
            if !quiet {
                views.first?.toast("채찍 모드 끔 · ⌥ESC 또는 Dock 아이콘으로 다시 켜기")
                NSApp.deactivate()      // 하던 앱으로 바로 돌아가기
            }
        }
    }

    /// ⌥ Option + ESC: 어떤 앱을 쓰고 있든 채찍 모드 켜기/끄기
    /// (시스템 단축키로 등록해서 다른 앱에는 전달되지 않고, 따로 권한도 필요 없음)
    func registerHotKey() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ -> OSStatus in
            DispatchQueue.main.async { (NSApp.delegate as? AppDelegate)?.toggleWhipOnly() }
            return noErr
        }, 1, &spec, nil, nil)
        let id = EventHotKeyID(signature: OSType(0x5748_4950), id: 1)   // 'WHIP'
        RegisterEventHotKey(UInt32(kVK_Escape), UInt32(optionKey), id,
                            GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    // MARK: 맞았을 때

    func phrases() -> [String] {
        phrasesText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    func handleHit(tip: CGPoint, aim: CGPoint, kind: HitKind, in view: WhipView) {
        count += 1
        countItem.title = "채찍질 \(count)회"
        statusItem.button?.title = " \(count)"
        NSApp.dockTile.badgeLabel = "\(count)"          // Dock 아이콘에 횟수 배지
        if kind == .combo { return }                   // 연타 중엔 카운트만

        guard let phrase = phrases().randomElement() else { return }
        view.showBubble(kind == .finisher ? phrase + "!!" : phrase, at: tip, big: kind == .finisher)
    }

    // MARK: 로그인할 때 자동 실행

    var isAppBundle: Bool { Bundle.main.bundleIdentifier != nil }

    var loginItemEnabled: Bool {
        guard isAppBundle, #available(macOS 13.0, *) else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    @objc func toggleLoginItem() {
        guard isAppBundle, #available(macOS 13.0, *) else { return }
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch {
            views.first?.toast("자동 실행 설정 실패: \(error.localizedDescription)")
        }
    }

    // MARK: 메뉴 (상단 메뉴, Dock 우클릭, 메뉴 막대 아이콘에 똑같이 들어감)

    func item(_ title: String, _ action: Selector?, key: String = "", indent: Int = 0) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = action == nil ? nil : self
        i.isEnabled = action != nil
        i.indentationLevel = indent
        return i
    }

    /// 채찍 모드 / 효과 / 말풍선
    func controlItems() -> [NSMenuItem] {
        var items = [item("🎯 채찍 모드    ⌥ESC", #selector(toggleWhipOnly)),
                     item("클릭 = 채찍 · 꾹 눌렀다 놓기 = 필살기", nil, indent: 1),
                     .separator(),
                     item("효과", nil)]
        for el in Element.allCases {
            let i = item(el.title, #selector(pickElement(_:)), indent: 1)
            i.representedObject = el.rawValue
            items.append(i)
        }
        items += [.separator(), item("말풍선 문장 바꾸기…", #selector(editPhrases))]
        return items
    }

    /// 메뉴를 열 때마다 체크 표시를 현재 상태로 맞춤
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(toggleWhipOnly):
            menuItem.state = whipOnlyMode ? .on : .off
        case #selector(pickElement(_:)):
            menuItem.state = (menuItem.representedObject as? String) == element.rawValue ? .on : .off
        case #selector(toggleLoginItem):
            menuItem.state = loginItemEnabled ? .on : .off
            return isAppBundle
        case #selector(toggleMenuBarIcon):
            menuItem.state = showMenuBarIcon ? .on : .off
        case #selector(toggleAutoUpdate):
            menuItem.state = Updater.shared.autoCheck ? .on : .off
        default:
            break
        }
        return true
    }

    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let b = statusItem.button {
            b.image = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: "Ppalli")
            b.imagePosition = .imageLeft
            b.title = " 0"
        }
        let menu = NSMenu()
        countItem.isEnabled = false
        menu.addItem(countItem)
        menu.addItem(.separator())
        controlItems().forEach { menu.addItem($0) }
        menu.addItem(.separator())
        menu.addItem(item("업데이트 확인…", #selector(checkForUpdates)))
        menu.addItem(item("Ppalli 종료", #selector(NSApplication.terminate(_:)), key: "q"))
        menu.items.last?.target = NSApp
        statusItem.menu = menu
        statusItem.isVisible = showMenuBarIcon
    }

    func buildMainMenu() -> NSMenu {
        let main = NSMenu()

        // Ppalli 메뉴
        let appMenu = NSMenu()
        appMenu.addItem(item("Ppalli에 관하여", #selector(showAbout)))
        appMenu.addItem(.separator())
        appMenu.addItem(item("로그인할 때 자동으로 켜기", #selector(toggleLoginItem)))
        appMenu.addItem(item("메뉴 막대에 아이콘 보기", #selector(toggleMenuBarIcon)))
        appMenu.addItem(.separator())
        appMenu.addItem(item("업데이트 확인…", #selector(checkForUpdates)))
        appMenu.addItem(item("자동으로 업데이트 확인", #selector(toggleAutoUpdate)))
        appMenu.addItem(item("홈페이지 (GitHub)", #selector(openHomepage)))
        appMenu.addItem(.separator())
        let hide = NSMenuItem(title: "Ppalli 가리기", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(hide)
        appMenu.addItem(NSMenuItem(title: "Ppalli 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        main.addItem(appItem)

        // 채찍 메뉴
        let whipMenu = NSMenu(title: "채찍")
        controlItems().forEach { whipMenu.addItem($0) }
        let whipItem = NSMenuItem()
        whipItem.submenu = whipMenu
        main.addItem(whipItem)

        // 편집 메뉴 (문장 입력창에서 ⌘C/⌘V/⌘A가 되도록)
        let edit = NSMenu(title: "편집")
        edit.addItem(withTitle: "잘라내기", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "복사하기", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "붙여넣기", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "전체 선택", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem()
        editItem.submenu = edit
        main.addItem(editItem)
        return main
    }

    @objc func toggleMenuBarIcon() { showMenuBarIcon.toggle() }
    @objc func checkForUpdates() { Updater.shared.check(userInitiated: true) }
    @objc func toggleAutoUpdate() { Updater.shared.autoCheck.toggle() }

    @objc func openHomepage() {
        if let url = URL(string: homepageURL) { NSWorkspace.shared.open(url) }
    }

    @objc func showAbout() {
        let credits = NSAttributedString(
            string: "빨리 해! 느린 AI를 채찍으로 찰싹.\n⌥ESC로 어디서든 채찍 모드 켜기/끄기\n\n\(homepageURL)",
            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor])
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "Ppalli", .credits: credits])
    }

    @objc func pickElement(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let e = Element(rawValue: raw) { element = e }
    }

    @objc func editPhrases() {
        if whipOnlyMode { setWhipOnly(false, quiet: true) }   // 투명 창이 입력 창을 덮지 않도록
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "말풍선 문장"
        alert.informativeText = "쉼표로 구분해서 적어 주세요. 채찍질할 때마다 이 중 하나가 랜덤으로 떠요."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 340, height: 24))
        field.stringValue = phrasesText
        alert.accessoryView = field
        alert.addButton(withTitle: "저장")
        alert.addButton(withTitle: "취소")
        alert.window.initialFirstResponder = field
        if alert.runModal() == .alertFirstButtonReturn {
            phrasesText = field.stringValue
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)       // Dock에 아이콘이 있는 일반 앱
app.run()
