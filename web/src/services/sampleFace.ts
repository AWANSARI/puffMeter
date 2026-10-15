// A neutral illustrated portrait used for demo photos and when no camera is available.
// `puffiness` 0…1 subtly widens the cheeks and under-eyes so frames differ.

import { canvasToBlob } from './photoStore'

export function drawSampleFace(ctx: CanvasRenderingContext2D, w: number, h: number, puffiness = 0.3) {
  const faceW = w * (0.4 + 0.03 * puffiness)
  const faceH = h * 0.4
  const cx = w / 2
  const cy = h * 0.42
  const bg = ctx.createLinearGradient(0, 0, 0, h)
  bg.addColorStop(0, '#D9D5CF')
  bg.addColorStop(1, '#C4BFB8')
  ctx.fillStyle = bg
  ctx.fillRect(0, 0, w, h)

  const ellipse = (x: number, y: number, rx: number, ry: number, color: string) => {
    ctx.beginPath()
    ctx.ellipse(x, y, rx, ry, 0, 0, Math.PI * 2)
    ctx.fillStyle = color
    ctx.fill()
  }
  ellipse(cx, h * 1.02, w * 0.53, h * 0.25, '#4A4A4C') // shoulders
  ctx.fillStyle = '#D8A98A'
  ctx.fillRect(cx - faceW * 0.21, cy + faceH * 0.4, faceW * 0.42, h * 0.16) // neck
  ellipse(cx, cy - faceH * 0.08, faceW * 0.56, faceH * 0.54, '#3B2A21') // hair back
  const skin = ctx.createRadialGradient(cx, cy, 0, cx, cy, faceW * 0.7)
  skin.addColorStop(0, '#F0C3A4')
  skin.addColorStop(1, '#DDA585')
  ctx.beginPath()
  ctx.ellipse(cx, cy, faceW / 2, faceH / 2, 0, 0, Math.PI * 2)
  ctx.fillStyle = skin
  ctx.fill()
  ellipse(cx, cy - faceH * 0.42, faceW * 0.49, faceH * 0.13, '#3B2A21') // hair top

  for (const side of [-1, 1]) {
    const ex = cx + side * faceW * 0.2
    ctx.save()
    ctx.translate(ex, cy - faceH * 0.12)
    ctx.rotate((side * 5 * Math.PI) / 180)
    ctx.fillStyle = '#4A3328'
    ctx.fillRect(-faceW * 0.1, -faceH * 0.0125, faceW * 0.2, faceH * 0.025)
    ctx.restore()
    ellipse(ex, cy - faceH * 0.04, faceW * 0.08, faceH * 0.03, '#FFFFFF')
    ellipse(ex, cy - faceH * 0.04, faceH * 0.025, faceH * 0.025, '#5A3E2B')
    ctx.globalAlpha = 0.25 + 0.3 * puffiness
    ellipse(ex, cy + faceH * 0.02, faceW * 0.085, faceH * (0.015 + 0.01 * puffiness), '#C98E70')
    ctx.globalAlpha = 1
  }
  ctx.globalAlpha = 0.6
  ellipse(cx, cy + faceH * 0.08, faceW * 0.035, faceH * 0.08, '#CF9878') // nose
  ctx.globalAlpha = 1
  ctx.beginPath()
  ctx.moveTo(cx - faceW * 0.12, cy + faceH * 0.25)
  ctx.quadraticCurveTo(cx, cy + faceH * 0.29, cx + faceW * 0.12, cy + faceH * 0.25)
  ctx.strokeStyle = '#B86B5E'
  ctx.lineWidth = faceH * 0.025
  ctx.lineCap = 'round'
  ctx.stroke()
}

export async function sampleFaceJPEG(puffiness: number, w = 600, h = 800): Promise<Blob> {
  const canvas = document.createElement('canvas')
  canvas.width = w
  canvas.height = h
  drawSampleFace(canvas.getContext('2d')!, w, h, puffiness)
  return canvasToBlob(canvas, 0.88)
}
