// Local calendar days as "YYYY-MM-DD" strings. Arithmetic is done at local noon so DST
// transitions never skip or repeat a day.

export type DayKey = string
export type MonthKey = string // "YYYY-MM"

const pad = (n: number, w = 2) => String(n).padStart(w, '0')

export function dayKeyOf(date: Date): DayKey {
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`
}

export function parseDay(key: DayKey): { y: number; m: number; d: number } {
  const [y, m, d] = key.split('-').map(Number)
  return { y, m, d }
}

export function dayStart(key: DayKey): Date {
  const { y, m, d } = parseDay(key)
  return new Date(y, m - 1, d)
}

function dayNoon(key: DayKey): Date {
  const { y, m, d } = parseDay(key)
  return new Date(y, m - 1, d, 12)
}

export function addDays(key: DayKey, days: number): DayKey {
  const date = dayNoon(key)
  date.setDate(date.getDate() + days)
  return dayKeyOf(date)
}

export function daysBetween(from: DayKey, to: DayKey): number {
  return Math.round((dayNoon(to).getTime() - dayNoon(from).getTime()) / 86_400_000)
}

export function monthOf(key: DayKey): MonthKey {
  return key.slice(0, 7)
}

export function monthFirstDay(month: MonthKey): DayKey {
  return `${month}-01`
}

export function daysInMonth(month: MonthKey): number {
  const [y, m] = month.split('-').map(Number)
  return new Date(y, m, 0).getDate()
}

export function monthLastDay(month: MonthKey): DayKey {
  return `${month}-${pad(daysInMonth(month))}`
}

export function addMonths(month: MonthKey, n: number): MonthKey {
  const [y, m] = month.split('-').map(Number)
  const date = new Date(y, m - 1 + n, 1, 12)
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}`
}

export function dayRange(start: DayKey, end: DayKey): DayKey[] {
  const out: DayKey[] = []
  for (let d = start; d <= end; d = addDays(d, 1)) out.push(d)
  return out
}

/** Monday-first weekday index (0 = Monday … 6 = Sunday). */
export function weekdayIndexMondayFirst(key: DayKey): number {
  return (dayNoon(key).getDay() + 6) % 7
}

// MARK: Formatting

export const fmt = {
  weekdayInitial(key: DayKey): string {
    return dayNoon(key).toLocaleDateString('en-US', { weekday: 'narrow' })
  },
  longDay(key: DayKey): string {
    return dayNoon(key).toLocaleDateString('en-US', { weekday: 'long', month: 'long', day: 'numeric' })
  },
  shortDay(key: DayKey): string {
    return dayNoon(key).toLocaleDateString('en-US', { month: 'short', day: 'numeric' })
  },
  monthYear(month: MonthKey): string {
    return dayNoon(monthFirstDay(month)).toLocaleDateString('en-US', { month: 'long', year: 'numeric' })
  },
  monthName(month: MonthKey): string {
    return dayNoon(monthFirstDay(month)).toLocaleDateString('en-US', { month: 'long' })
  },
  range(start: DayKey, end: DayKey): string {
    if (monthOf(start) === monthOf(end)) return `${fmt.shortDay(start)}–${parseDay(end).d}`
    return `${fmt.shortDay(start)} – ${fmt.shortDay(end)}`
  },
  time(iso: string | Date): string {
    const date = typeof iso === 'string' ? new Date(iso) : iso
    return date.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' })
  },
  dateLong(iso: string | Date): string {
    const date = typeof iso === 'string' ? new Date(iso) : iso
    return date.toLocaleDateString('en-US', { month: 'long', day: 'numeric', year: 'numeric' })
  },
  dateMedium(iso: string | Date): string {
    const date = typeof iso === 'string' ? new Date(iso) : iso
    return date.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })
  },
  hours(h: number): string {
    return Number.isInteger(h) ? `${h}h` : `${h.toFixed(1)}h`
  },
  liters(l: number): string {
    const r = Math.round(l * 100) / 100
    return `${r} L`
  },
  plural(n: number, singular: string, plural = singular + 's'): string {
    return `${n} ${n === 1 ? singular : plural}`
  },
  reminder(t: { hour: number; minute: number }): string {
    const d = new Date(2000, 0, 1, t.hour, t.minute)
    return d.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' })
  },
}
