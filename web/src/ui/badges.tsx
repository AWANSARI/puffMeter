import { Camera, Droplet, Flame, Moon, Sparkles } from 'lucide-react'
import { useId } from 'react'
import type { AwardDefinition, BadgeTint } from '../domain/progress'

const TINTS: Record<BadgeTint, [string, string]> = {
  pink: ['#FF8FB0', '#E0104A'], lime: ['#D8FF6E', '#7FBF1A'], cyan: ['#8FF8FF', '#0FB5C9'],
  silver: ['#F2F2F5', '#9A9AA3'], gold: ['#FFE59A', '#C8901C'], indigo: ['#B3B1FF', '#4B48D8'],
}

function shapePath(shape: AwardDefinition['badge']['shape'], s: number): string {
  const c = s / 2
  switch (shape) {
    case 'coin':
      return `M ${c} 0 A ${c} ${c} 0 1 1 ${c - 0.01} 0 Z`
    case 'hexagon': {
      const pts = Array.from({ length: 6 }, (_, i) => {
        const a = (Math.PI / 3) * i + Math.PI / 6
        return `${c + c * Math.cos(a)},${c + c * Math.sin(a)}`
      })
      return `M ${pts.join(' L ')} Z`
    }
    case 'shield':
      return `M ${c} 0 Q ${s * 0.8} ${s * 0.02} ${s} ${s * 0.14} L ${s} ${s * 0.5} Q ${s} ${s * 0.85} ${c} ${s} Q 0 ${s * 0.85} 0 ${s * 0.5} L 0 ${s * 0.14} Q ${s * 0.2} ${s * 0.02} ${c} 0 Z`
    case 'star': {
      const pts = Array.from({ length: 10 }, (_, i) => {
        const r = i % 2 === 0 ? c : c * 0.5
        const a = -Math.PI / 2 + (i * Math.PI) / 5
        return `${c + r * Math.cos(a)},${c + s * 0.04 + r * Math.sin(a)}`
      })
      return `M ${pts.join(' L ')} Z`
    }
  }
}

/** 3D-looking medal: metallic rim, colored face, center icon or label, and a specular highlight. */
export function AwardBadge({ award, locked, size }: { award: AwardDefinition; locked: boolean; size: number }) {
  const id = useId().replace(/:/g, '')
  const [light, dark] = TINTS[award.badge.tint]
  const inner = size * 0.84
  const off = (size - inner) / 2
  const Icon = { camera: Camera, flame: Flame, droplet: Droplet, rings: CircleRings, moon: Moon, sparkles: Sparkles, star: Sparkles }[award.badge.icon ?? 'sparkles']
  return (
    <div aria-hidden style={{ position: 'relative', width: size, height: size, flex: 'none',
      filter: locked ? 'grayscale(1) brightness(0.62)' : undefined, opacity: locked ? 0.8 : 1 }}>
      <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} style={{ position: 'absolute', inset: 0, overflow: 'visible' }}>
        <defs>
          <linearGradient id={`rim${id}`} x1="0" y1="0" x2="1" y2="1">
            <stop offset="0" stopColor="#ffffff" /><stop offset=".35" stopColor="#9d9da3" /><stop offset=".6" stopColor="#ececf0" /><stop offset="1" stopColor="#7d7d84" />
          </linearGradient>
          <radialGradient id={`face${id}`} cx=".35" cy=".3" r=".8">
            <stop offset="0" stopColor={light} /><stop offset="1" stopColor={dark} />
          </radialGradient>
          <linearGradient id={`spec${id}`} x1="0" y1="0" x2=".7" y2=".7">
            <stop offset="0" stopColor="#fff" stopOpacity=".5" /><stop offset=".5" stopColor="#fff" stopOpacity="0" />
          </linearGradient>
          <filter id={`sh${id}`}><feDropShadow dx="0" dy={size * 0.04} stdDeviation={size * 0.05} floodOpacity=".35" /></filter>
        </defs>
        <path d={shapePath(award.badge.shape, size)} fill={`url(#rim${id})`} filter={`url(#sh${id})`} />
        <g transform={`translate(${off} ${off})`}>
          <path d={shapePath(award.badge.shape, inner)} fill={`url(#face${id})`} stroke="rgba(255,255,255,.35)" strokeWidth={size * 0.012} />
          <path d={shapePath(award.badge.shape, inner)} fill={`url(#spec${id})`} />
        </g>
      </svg>
      <div style={{ position: 'absolute', inset: 0, display: 'grid', placeItems: 'center', color: '#fff',
        filter: 'drop-shadow(0 1px 1px rgba(0,0,0,.3))', paddingTop: award.badge.shape === 'star' ? size * 0.06 : 0 }}>
        {award.badge.label
          ? <span style={{ font: `800 ${size * 0.3}px var(--font-rounded)` }}>{award.badge.label}</span>
          : award.badge.icon ? <Icon size={size * (award.badge.shape === 'star' ? 0.24 : 0.38)} strokeWidth={2.2} fill="rgba(255,255,255,.85)" /> : null}
      </div>
    </div>
  )
}

function CircleRings({ size }: { size?: number; strokeWidth?: number; fill?: string }) {
  const s = size ?? 24
  return (
    <svg width={s} height={s} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.4}>
      <circle cx="12" cy="12" r="10" /><circle cx="12" cy="12" r="6" /><circle cx="12" cy="12" r="2" />
    </svg>
  )
}
