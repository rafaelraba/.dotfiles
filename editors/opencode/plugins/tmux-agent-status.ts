import { execFileSync } from "node:child_process"
import { existsSync } from "node:fs"
import { homedir } from "node:os"
import { join } from "node:path"
import type { Hooks, Plugin } from "@opencode-ai/plugin"

const AGENT_STATUS_SCRIPT = join(homedir(), ".dotfiles", "scripts", "agent-status.sh")
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
  const activeSessions = new Set<string>()

  function markActive(sessionID: string): void {
    activeSessions.add(sessionID)
    setStatus(AGENT_STATE.RUNNING)
  }

  function markDoneIfActive(sessionID: string): void {
    if (!activeSessions.has(sessionID)) {
      setStatus(AGENT_STATE.IDLE)
      return
    }

    setStatus(AGENT_STATE.DONE)
  }

  return {
    "chat.message": async (input) => {
      markActive(input.sessionID)
    },

    "command.execute.before": async (input) => {
      markActive(input.sessionID)
    },

    "permission.ask": async () => {
      setStatus(AGENT_STATE.BLOCKED)
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
          setStatus(AGENT_STATE.BLOCKED)
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
          setStatus(AGENT_STATE.ERROR)
          return

        case "session.status":
          if (payload.status?.type === "busy" && sessionID) markActive(sessionID)
          if (payload.status?.type === "idle" && sessionID) markDoneIfActive(sessionID)
          return

        case "session.idle":
          if (sessionID) markDoneIfActive(sessionID)
          return
      }
    },
  } satisfies Hooks
}

export default TmuxAgentStatusPlugin
