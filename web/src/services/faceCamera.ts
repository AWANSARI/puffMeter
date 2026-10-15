// Front camera + on-device face analysis with MediaPipe Face Landmarker. Nothing leaves the
// browser: frames are analyzed locally and only the final JPEG is stored (and uploaded to the
// user's own Drive folder).

import type { FaceLandmarker, FaceLandmarkerResult, NormalizedLandmark } from '@mediapipe/tasks-vision'
import type { RawFaceMetrics, ScanQuality } from '../domain/types'
import { canvasToBlob } from './photoStore'
import { drawSampleFace } from './sampleFace'

export interface ScanChecks {
  faceCount: number
  centered: boolean
  distance: 'ok' | 'tooFar' | 'tooClose'
  level: boolean
  goodLighting: boolean
  neutralFace: boolean
}

export const EMPTY_CHECKS: ScanChecks = { faceCount: 0, centered: false, distance: 'ok', level: false, goodLighting: false, neutralFace: false }
export const isCentered = (c: ScanChecks) => c.faceCount === 1 && c.centered && c.distance === 'ok' && c.level
export const allPassed = (c: ScanChecks) => isCentered(c) && c.goodLighting && c.neutralFace

/** The single most useful coaching message, or undefined when everything passes. */
export function guidance(c: ScanChecks): string | undefined {
  if (c.faceCount === 0) return 'Center your face in the oval'
  if (c.faceCount > 1) return 'Only one face, please'
  if (c.distance === 'tooFar') return 'Move a little closer'
  if (c.distance === 'tooClose') return 'Move back slightly'
  if (!c.level) return 'Level your head'
  if (!c.centered) return 'Center your face in the oval'
  if (!c.goodLighting) return 'Find softer, even light'
  if (!c.neutralFace) return 'Relax your face'
  return undefined
}

export interface CapturedFace { blob: Blob; capturedAt: Date; quality: ScanQuality; raw: RawFaceMetrics }

export interface CameraSession {
  kind: 'live' | 'simulated'
  start(video: HTMLVideoElement, canvas: HTMLCanvasElement): Promise<void>
  stop(): void
  onChecks(listener: (c: ScanChecks) => void): () => void
  capture(manual: boolean): Promise<CapturedFace>
}

/** Card aspect ratio and oval placement shared with the scan UI. */
export const CARD_ASPECT = 0.87
export const OVAL = { cx: 0.5, cy: 0.44, w: 0.64, h: 0.68 }

// MARK: Live camera

const WASM_PATH = '/mediapipe/wasm'
const MODEL_URL = 'https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task'

let landmarkerPromise: Promise<FaceLandmarker> | undefined
async function getLandmarker(): Promise<FaceLandmarker> {
  landmarkerPromise ??= (async () => {
    const { FaceLandmarker, FilesetResolver } = await import('@mediapipe/tasks-vision')
    const fileset = await FilesetResolver.forVisionTasks(WASM_PATH)
    const options = (delegate: 'GPU' | 'CPU') => ({
      baseOptions: { modelAssetPath: MODEL_URL, delegate },
      runningMode: 'VIDEO' as const,
      numFaces: 2,
      outputFaceBlendshapes: true,
      outputFacialTransformationMatrixes: true,
    })
    try {
      return await FaceLandmarker.createFromOptions(fileset, options('GPU'))
    } catch {
      return await FaceLandmarker.createFromOptions(fileset, options('CPU'))
    }
  })().catch((e) => { landmarkerPromise = undefined; throw e })
  return landmarkerPromise
}

/** Starts loading the model early (e.g. on the permissions screen). */
export function preloadFaceModel() {
  void getLandmarker().catch(() => undefined)
}

export function cameraSupported(): boolean {
  return !!navigator.mediaDevices?.getUserMedia
}

export async function cameraPermission(): Promise<'granted' | 'denied' | 'prompt'> {
  try {
    const status = await navigator.permissions.query({ name: 'camera' as PermissionName })
    return status.state
  } catch {
    return 'prompt'
  }
}

export async function requestCamera(): Promise<boolean> {
  try {
    const stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: 'user' }, audio: false })
    stream.getTracks().forEach((t) => t.stop())
    return true
  } catch {
    return false
  }
}

class LiveCamera implements CameraSession {
  kind = 'live' as const
  private stream?: MediaStream
  private video?: HTMLVideoElement
  private landmarker?: FaceLandmarker
  private raf = 0
  private lastRun = 0
  private listeners = new Set<(c: ScanChecks) => void>()
  private recent: RawFaceMetrics[] = []
  private quality: ScanQuality = { lighting: 0.5, yawDeg: 0, rollDeg: 0, pitchDeg: 0, neutrality: 0.5, method: 'mediapipe', manual: false }
  private sampler = document.createElement('canvas')

  async start(video: HTMLVideoElement) {
    this.video = video
    this.stream = await navigator.mediaDevices.getUserMedia({
      video: { facingMode: 'user', width: { ideal: 1280 }, height: { ideal: 1280 } }, audio: false,
    })
    video.srcObject = this.stream
    video.muted = true
    video.playsInline = true
    await video.play()
    this.landmarker = await getLandmarker()
    const loop = () => {
      this.raf = requestAnimationFrame(loop)
      const now = performance.now()
      if (now - this.lastRun < 100 || !this.video || this.video.readyState < 2) return // ~10 Hz
      this.lastRun = now
      const result = this.landmarker!.detectForVideo(this.video, now)
      this.evaluate(result)
    }
    loop()
  }

  stop() {
    cancelAnimationFrame(this.raf)
    this.stream?.getTracks().forEach((t) => t.stop())
    this.stream = undefined
  }

  onChecks(listener: (c: ScanChecks) => void) {
    this.listeners.add(listener)
    return () => { this.listeners.delete(listener) }
  }

  private emit(c: ScanChecks) {
    this.listeners.forEach((l) => l(c))
  }

  /** Maps video-normalized coordinates into the cropped (object-fit: cover) card. */
  private toCard(p: { x: number; y: number }) {
    const v = this.video!
    const va = v.videoWidth / v.videoHeight
    if (va > CARD_ASPECT) {
      const visible = CARD_ASPECT / va
      return { x: (p.x - (1 - visible) / 2) / visible, y: p.y }
    }
    const visible = va / CARD_ASPECT
    return { x: p.x, y: (p.y - (1 - visible) / 2) / visible }
  }

  private evaluate(result: FaceLandmarkerResult) {
    const faces = result.faceLandmarks
    const checks: ScanChecks = { ...EMPTY_CHECKS, faceCount: faces.length }
    if (faces.length !== 1) {
      this.recent = []
      this.emit(checks)
      return
    }
    const lm = faces[0]
    const xs = lm.map((p) => p.x)
    const ys = lm.map((p) => p.y)
    const box = { x0: Math.min(...xs), x1: Math.max(...xs), y0: Math.min(...ys), y1: Math.max(...ys) }
    const center = this.toCard({ x: (box.x0 + box.x1) / 2, y: (box.y0 + box.y1) / 2 })
    const top = this.toCard({ x: 0, y: box.y0 })
    const bottom = this.toCard({ x: 0, y: box.y1 })
    const faceHeight = bottom.y - top.y
    checks.centered = Math.abs(center.x - OVAL.cx) < 0.08 && Math.abs(center.y - OVAL.cy) < 0.11
    checks.distance = faceHeight < 0.4 ? 'tooFar' : faceHeight > 0.76 ? 'tooClose' : 'ok'

    // Head pose from the facial transformation matrix (column-major 4×4).
    const m = result.facialTransformationMatrixes?.[0]?.data
    let yaw = 0, pitch = 0, roll = 0
    if (m) {
      yaw = (Math.asin(Math.max(-1, Math.min(1, -m[2]))) * 180) / Math.PI
      pitch = (Math.atan2(m[6], m[10]) * 180) / Math.PI
      roll = (Math.atan2(m[1], m[0]) * 180) / Math.PI
    }
    checks.level = Math.abs(yaw) < 8 && Math.abs(roll) < 8 && Math.abs(pitch) < 15

    const blend = new Map((result.faceBlendshapes?.[0]?.categories ?? []).map((c) => [c.categoryName, c.score]))
    const expression = Math.max(blend.get('mouthSmileLeft') ?? 0, blend.get('mouthSmileRight') ?? 0,
      blend.get('jawOpen') ?? 0, blend.get('browInnerUp') ?? 0)
    const blink = Math.max(blend.get('eyeBlinkLeft') ?? 0, blend.get('eyeBlinkRight') ?? 0)
    checks.neutralFace = expression < 0.3 && blink < 0.5

    const { mean, evenness } = this.sampleLighting(box)
    checks.goodLighting = mean > 0.3 && mean < 0.85 && evenness < 0.2

    this.quality = {
      lighting: Math.max(0, Math.min(1, 1 - Math.abs(mean - 0.55) * 2 - evenness)), yawDeg: yaw, rollDeg: roll, pitchDeg: pitch,
      neutrality: 1 - expression, method: 'mediapipe', manual: false,
    }
    this.recent.push(measure(lm, this.video!.videoWidth, this.video!.videoHeight))
    if (this.recent.length > 12) this.recent.shift()
    this.emit(checks)
  }

  /** Mean luma of the face box and left/right difference (even light). */
  private sampleLighting(box: { x0: number; x1: number; y0: number; y1: number }) {
    const v = this.video!
    const c = this.sampler
    c.width = 32
    c.height = 32
    const ctx = c.getContext('2d', { willReadFrequently: true })!
    const sx = Math.max(0, box.x0 * v.videoWidth)
    const sy = Math.max(0, box.y0 * v.videoHeight)
    const sw = Math.max(1, (box.x1 - box.x0) * v.videoWidth)
    const sh = Math.max(1, (box.y1 - box.y0) * v.videoHeight)
    ctx.drawImage(v, sx, sy, sw, sh, 0, 0, 32, 32)
    const d = ctx.getImageData(0, 0, 32, 32).data
    let left = 0, right = 0
    for (let y = 0; y < 32; y++) {
      for (let x = 0; x < 32; x++) {
        const i = (y * 32 + x) * 4
        const l = (0.299 * d[i] + 0.587 * d[i + 1] + 0.114 * d[i + 2]) / 255
        if (x < 16) left += l; else right += l
      }
    }
    left /= 512
    right /= 512
    return { mean: (left + right) / 2, evenness: Math.abs(left - right) }
  }

  async capture(manual: boolean): Promise<CapturedFace> {
    const v = this.video
    if (!v) throw new Error('Camera not started')
    const canvas = document.createElement('canvas')
    canvas.width = v.videoWidth
    canvas.height = v.videoHeight
    // Saved photo keeps the true (unmirrored) orientation; only the preview is mirrored.
    canvas.getContext('2d')!.drawImage(v, 0, 0)
    const blob = await canvasToBlob(canvas, 0.9)
    const samples = this.recent.length ? this.recent : [measureFallback()]
    const median = (k: keyof RawFaceMetrics) => {
      const s = samples.map((r) => r[k]).sort((a, b) => a - b)
      return s[Math.floor(s.length / 2)]
    }
    return {
      blob, capturedAt: new Date(), quality: { ...this.quality, manual },
      raw: { underEyes: median('underEyes'), cheeks: median('cheeks'), jawline: median('jawline') },
    }
  }
}

/**
 * IPD-normalized zone measurements from MediaPipe's 478-point mesh. MediaPipe z is negative
 * toward the camera, so tissue that protrudes more (puffier) gives a higher value.
 */
export function measure(lm: NormalizedLandmark[], w: number, h: number): RawFaceMetrics {
  const P = (i: number) => ({ x: lm[i].x * w, y: lm[i].y * h, z: lm[i].z * w })
  const dist = (a: number, b: number) => Math.hypot(P(a).x - P(b).x, P(a).y - P(b).y)
  const ipd = Math.max(dist(468, 473), 1)
  const meanZ = (ids: number[]) => ids.reduce((s, i) => s + P(i).z, 0) / ids.length
  const underEye = [230, 231, 229, 450, 451, 449]
  const cheekbone = [116, 117, 345, 346]
  return {
    underEyes: (meanZ(cheekbone) - meanZ(underEye)) / ipd,
    cheeks: dist(234, 454) / ipd,
    jawline: dist(172, 397) / ipd,
  }
}

function measureFallback(): RawFaceMetrics {
  return { underEyes: 0.338, cheeks: 0.929, jawline: 0.826 }
}

// MARK: Simulated camera (demo mode, or no camera available)

class SimulatedCamera implements CameraSession {
  kind = 'simulated' as const
  private listeners = new Set<(c: ScanChecks) => void>()
  private timers: number[] = []
  private puffiness = 0.15 + Math.random() * 0.4

  async start(_video: HTMLVideoElement, canvas: HTMLCanvasElement) {
    canvas.width = 600
    canvas.height = Math.round(600 / CARD_ASPECT)
    drawSampleFace(canvas.getContext('2d')!, canvas.width, canvas.height, this.puffiness)
    let checks: ScanChecks = { ...EMPTY_CHECKS }
    const steps: [number, Partial<ScanChecks>][] = [
      [500, { faceCount: 1, distance: 'tooFar' }],
      [1000, { distance: 'ok', level: true, centered: true }],
      [1400, { goodLighting: true }],
      [1800, { neutralFace: true }],
    ]
    for (const [delay, change] of steps) {
      this.timers.push(window.setTimeout(() => {
        checks = { ...checks, ...change }
        this.listeners.forEach((l) => l(checks))
      }, delay))
    }
  }

  stop() {
    this.timers.forEach(clearTimeout)
  }

  onChecks(listener: (c: ScanChecks) => void) {
    this.listeners.add(listener)
    return () => { this.listeners.delete(listener) }
  }

  async capture(manual: boolean): Promise<CapturedFace> {
    const canvas = document.createElement('canvas')
    canvas.width = 900
    canvas.height = 1200
    drawSampleFace(canvas.getContext('2d')!, 900, 1200, this.puffiness)
    const base = measureFallback()
    const d = this.puffiness - 0.3
    return {
      blob: await canvasToBlob(canvas, 0.9), capturedAt: new Date(),
      quality: { lighting: 0.85, yawDeg: 1.2, rollDeg: 0.4, pitchDeg: 0, neutrality: 0.94, method: 'fixture', manual },
      raw: { underEyes: base.underEyes + d * 0.03, cheeks: base.cheeks + d * 0.03, jawline: base.jawline + d * 0.025 },
    }
  }
}

export function createCamera(simulated: boolean): CameraSession {
  return simulated || !cameraSupported() ? new SimulatedCamera() : new LiveCamera()
}
