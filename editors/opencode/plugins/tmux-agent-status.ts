import { execFileSync } from "node:child_process"
import { existsSync } from "node:fs"
import { homedir } from "node:os"
import { join } from "node:path"
import type { Hooks, Plugin } from "@opencode-ai/plugin"

const AGENT_STATUS_SCRIPT = join(homedir(), ".dotfiles", "scripts", "agent-status.sh")
const HEARTBEAT_INTERVAL_MS = 240_000
let previousEventID = 0

const AGENT_STATE = {
  BLOCKED: "blocked",
  DONE: "done",
  ERROR: "error",
  IDLE: "idle",
  RUNNING: "running",
} as const

type AgentState = (typeof AGENT_STATE)[keyof typeof AGENT_STATE]

function nextEventID(): number {
  previousEventID = Math.max(Date.now(), previousEventID + 1)
  return previousEventID
}

interface EventPayload {
  info?: {
    id?: string
  }
  sessionID?: string
  status?: {
    type?: string
  }
}

interface OpenCodeEventShape {
  type?: string
  data?: EventPayload
  properties?: EventPayload
}

function setStatus(state: AgentState): void {
  if (!process.env.TMUX || !existsSync(AGENT_STATUS_SCRIPT)) return

  try {
    execFileSync(AGENT_STATUS_SCRIPT, ["set", state, "", "", "opencode", String(nextEventID())], {
      stdio: "ignore",
      timeout: 1000,
    })
  } catch {
    // Status rendering must never break the OpenCode session.
  }
}

function eventPayload(event: unknown): EventPayload {
  if (typeof event !== "object" || event === null) return {}

  const shapedEvent = event as OpenCodeEventShape
  return shapedEvent.data ?? shapedEvent.properties ?? {}
}

function eventType(event: unknown): string {
  if (typeof event !== "object" || event === null || !("type" in event)) return ""

  return typeof event.type === "string" ? event.type : ""
}

export const TmuxAgentStatusPlugin: Plugin = async () => {
  const sessionStates = new Map<string, AgentState>()
  const finishedSessions = new Set<string>()
  let heartbeat: ReturnType<typeof setInterval> | undefined
  let currentState: AgentState = AGENT_STATE.IDLE

  function stopHeartbeat(): void {
    if (heartbeat === undefined) return

    clearInterval(heartbeat)
    heartbeat = undefined
  }

  function updateStatus(state: AgentState): void {
    currentState = state
    setStatus(state)

    if (state !== AGENT_STATE.RUNNING && state !== AGENT_STATE.BLOCKED) {
      stopHeartbeat()
      return
    }
    if (heartbeat !== undefined) return

    heartbeat = setInterval(() => {
      if (currentState === AGENT_STATE.RUNNING || currentState === AGENT_STATE.BLOCKED) setStatus(currentState)
    }, HEARTBEAT_INTERVAL_MS)
    heartbeat.unref()
  }

  function aggregateActiveState(): AgentState | undefined {
    if ([...sessionStates.values()].includes(AGENT_STATE.BLOCKED)) return AGENT_STATE.BLOCKED
    if (sessionStates.size > 0) return AGENT_STATE.RUNNING

    return undefined
  }

  function updateSession(sessionID: string, state: AgentState): void {
    finishedSessions.delete(sessionID)
    sessionStates.set(sessionID, state)
    updateStatus(aggregateActiveState() ?? AGENT_STATE.IDLE)
  }

  function markActive(sessionID: string): void {
    updateSession(sessionID, AGENT_STATE.RUNNING)
  }

  function markFinished(sessionID: string, publishDone: boolean): void {
    if (publishDone && finishedSessions.has(sessionID)) return

    const wasActive = sessionStates.delete(sessionID)
    const activeState = aggregateActiveState()

    if (publishDone) finishedSessions.add(sessionID)
    else finishedSessions.delete(sessionID)

    if (activeState) {
      updateStatus(activeState)
      return
    }

    updateStatus(wasActive && publishDone ? AGENT_STATE.DONE : AGENT_STATE.IDLE)
  }

  return {
    "chat.message": async (input) => {
      markActive(input.sessionID)
    },

    "command.execute.before": async (input) => {
      markActive(input.sessionID)
    },

    "permission.ask": async (input) => {
      updateSession(input.sessionID, AGENT_STATE.BLOCKED)
    },

    "tool.execute.before": async (input) => {
      markActive(input.sessionID)
    },

    "tool.execute.after": async (input) => {
      markActive(input.sessionID)
    },

    event: async (input) => {
      const type = eventType(input.event)
      const payload = eventPayload(input.event)
      const sessionID = payload.sessionID

      switch (type) {
        case "permission.asked":
        case "permission.v2.asked":
        case "question.asked":
        case "question.v2.asked":
          if (sessionID) updateSession(sessionID, AGENT_STATE.BLOCKED)
          else updateStatus(AGENT_STATE.BLOCKED)
          return

        case "permission.replied":
        case "permission.v2.replied":
        case "question.replied":
        case "question.v2.replied":
        case "question.rejected":
        case "question.v2.rejected":
          if (sessionID) markActive(sessionID)
          return

        case "session.error":
        case "session.next.step.failed":
        case "session.next.tool.failed":
          if (sessionID) sessionStates.delete(sessionID)
          if (sessionID) finishedSessions.delete(sessionID)
          updateStatus(AGENT_STATE.ERROR)
          return

        case "session.status":
          if ((payload.status?.type === "busy" || payload.status?.type === "retry") && sessionID) markActive(sessionID)
          if (payload.status?.type === "idle" && sessionID) markFinished(sessionID, true)
          return

        case "session.idle":
          if (sessionID) markFinished(sessionID, true)
          return

        case "session.deleted":
          if (payload.info?.id) markFinished(payload.info.id, false)
          return
      }
    },
  } satisfies Hooks
}

export default TmuxAgentStatusPlugin
