// Small transcript records, shaped like Claude Code's. The SECRET strings must never reach a scan result.
export const NOW = Date.parse('2026-11-14T12:00:00Z')

type Usage = { input?: number; output?: number; write?: number; hour?: number; read?: number }

export const assistant = (id: string, at: string, u: Usage, model = 'claude-opus-5-5', extra: object = {}) =>
  JSON.stringify({
    type: 'assistant', timestamp: at, uuid: `u-${id}`, gitBranch: 'claude/x',
    message: {
      id, model, stop_reason: 'tool_use',
      content: [{ type: 'thinking', thinking: 'SECRET-THINK' }, { type: 'tool_use', name: 'Bash', input: { command: 'SECRET-INPUT' } }],
      usage: {
        input_tokens: u.input ?? 0, output_tokens: u.output ?? 0, cache_creation_input_tokens: u.write ?? 0,
        cache_creation: { ephemeral_1h_input_tokens: u.hour ?? 0 }, cache_read_input_tokens: u.read ?? 0,
      },
    },
    ...extra,
  })

export const user = (text = 'SECRET-PROMPT') => JSON.stringify({ type: 'user', message: { role: 'user', content: text } })
export const toolResult = () => JSON.stringify({ type: 'user', message: { role: 'user', content: [{ type: 'tool_result', content: 'SECRET-OUTPUT "usage":{ }' }] } })
export const title = (kind: 'custom-title' | 'ai-title', name: string) =>
  JSON.stringify(kind === 'custom-title' ? { type: kind, customTitle: name } : { type: kind, aiTitle: name })

export const lines = (...rows: string[]) => rows.map(r => `${r}\n`).join('')
