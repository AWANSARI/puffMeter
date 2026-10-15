// What PuffyMeter writes to Google Drive, plus CSV export. Same formats as the iOS app.

import { dayKeyOf } from './dates'
import type { History } from './engine'
import type { HabitLog, ScanRecord } from './types'

const pad = (n: number) => String(n).padStart(2, '0')

export const DriveNaming = {
  defaultFolderName: 'PuffyMeter Daily',
  appPropertyKey: 'puffymeter',
  /** "2026-10-08_0802" in local time. */
  baseName(date: Date): string {
    return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}_${pad(date.getHours())}${pad(date.getMinutes())}`
  },
  photoName: (date: Date) => `${DriveNaming.baseName(date)}.jpg`,
  scoresName: (date: Date) => `${DriveNaming.baseName(date)}.json`,
}

/** ISO 8601 with the local UTC offset, e.g. 2026-10-08T08:02:13-07:00. */
export function localISO(date: Date): string {
  const offset = -date.getTimezoneOffset()
  const sign = offset >= 0 ? '+' : '-'
  const abs = Math.abs(offset)
  return `${dayKeyOf(date)}T${pad(date.getHours())}:${pad(date.getMinutes())}:${pad(date.getSeconds())}${sign}${pad(Math.floor(abs / 60))}:${pad(abs % 60)}`
}

/** The JSON written next to each photo ("Scores and notes"). Schema version 1. */
export function scanExport(scan: ScanRecord, opts: {
  baselineID?: string; deltaVsYesterday?: number; deltaVsBaseline?: number; habits?: HabitLog; appVersion: string
}) {
  return {
    schemaVersion: 1,
    scanID: scan.id,
    capturedAt: localISO(new Date(scan.capturedAt)),
    score: scan.score,
    zones: scan.zones,
    raw: scan.raw,
    lowConfidence: scan.lowConfidence,
    isBaseline: scan.isBaseline,
    baselineScanID: opts.baselineID ?? null,
    delta: { vsYesterday: opts.deltaVsYesterday ?? null, vsBaseline: opts.deltaVsBaseline ?? null },
    quality: scan.quality,
    habits: {
      sleepHours: opts.habits?.sleepHours ?? null,
      waterLiters: opts.habits?.waterLiters ?? null,
      salt: opts.habits?.salt ?? null,
      alcohol: opts.habits?.alcohol ?? null,
    },
    tags: scan.tags,
    notes: scan.notes,
    appVersion: opts.appVersion,
    platform: 'web',
  }
}

export type ScanExport = ReturnType<typeof scanExport>

/** Rebuilds a local record when restoring history from Drive. */
export function recordFromExport(e: ScanExport): ScanRecord | undefined {
  const date = new Date(e.capturedAt)
  if (Number.isNaN(date.getTime())) return undefined
  return {
    id: e.scanID, capturedAt: date.toISOString(), dayKey: dayKeyOf(date), score: e.score, zones: e.zones, raw: e.raw,
    quality: e.quality, lowConfidence: e.lowConfidence, isBaseline: e.isBaseline, notes: e.notes, tags: e.tags, syncState: 'synced',
  }
}

export const CSV_HEADER = 'date,time,score,under_eyes,cheeks,jawline,sleep_h,water_l,salt,alcohol,notes,tags,drive_file_id'

export function toCSV(history: History): string {
  const escape = (f: string) => (/[",\n]/.test(f) ? `"${f.replace(/"/g, '""')}"` : f)
  const lines = [CSV_HEADER]
  for (const s of history.scans) {
    const h = history.habits.get(s.dayKey)
    const d = new Date(s.capturedAt)
    lines.push([
      s.dayKey, `${pad(d.getHours())}:${pad(d.getMinutes())}`, s.score, s.zones.underEyes, s.zones.cheeks, s.zones.jawline,
      h?.sleepHours ?? '', h?.waterLiters ?? '', h?.salt ?? '', h?.alcohol ?? '', s.notes, s.tags.join(';'), s.drivePhotoFileID ?? '',
    ].map((v) => escape(String(v))).join(','))
  }
  return lines.join('\n') + '\n'
}
