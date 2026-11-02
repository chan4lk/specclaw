export type SpecclawChange = {
  name: string
  phase: string
  approved: boolean
  done: number
  total: number
  failed: number
  verdict?: string
  pr?: string
  mtimeMs: number
}

export type SpecclawSnapshot = { hasSpecclaw: boolean; changes: SpecclawChange[] }

declare module 'claude-code' {
  interface PluginState {
    'specclaw-mod': { snapshot: Shaped<SpecclawSnapshot> }
  }
}
