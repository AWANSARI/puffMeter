// Copies the MediaPipe Tasks WASM runtime into public/ so it's served from our own origin.
import { cpSync, existsSync, mkdirSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')
const from = join(root, 'node_modules/@mediapipe/tasks-vision/wasm')
const to = join(root, 'public/mediapipe/wasm')
if (!existsSync(from)) throw new Error('Run npm install first: @mediapipe/tasks-vision is missing')
mkdirSync(to, { recursive: true })
cpSync(from, to, { recursive: true })
console.log('Copied MediaPipe WASM to public/mediapipe/wasm')
