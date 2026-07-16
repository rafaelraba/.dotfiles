import { execFileSync } from "node:child_process";
import { existsSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import type {
	ExtensionAPI,
	ExtensionContext,
} from "@earendil-works/pi-coding-agent";

const AGENT_STATUS_SCRIPT = join(
	homedir(),
	".dotfiles",
	"scripts",
	"agent-status.sh",
);

const AGENT_STATE = {
	BLOCKED: "blocked",
	DONE: "done",
	ERROR: "error",
	IDLE: "idle",
	RUNNING: "running",
} as const;

type AgentState = (typeof AGENT_STATE)[keyof typeof AGENT_STATE];

function setStatus(state: AgentState): void {
	if (!process.env.TMUX || !existsSync(AGENT_STATUS_SCRIPT)) return;

	try {
		execFileSync(AGENT_STATUS_SCRIPT, ["set", state], {
			stdio: "ignore",
			timeout: 1000,
		});
	} catch {
		// Status rendering must never break the agent session.
	}
}

function clearStatus(): void {
	if (!process.env.TMUX || !existsSync(AGENT_STATUS_SCRIPT)) return;

	try {
		execFileSync(AGENT_STATUS_SCRIPT, ["clear"], {
			stdio: "ignore",
			timeout: 1000,
		});
	} catch {
		// Status rendering must never break the agent session.
	}
}

function isAskUserQuestionTool(toolName: string): boolean {
	const normalizedToolName = toolName.toLowerCase().replace(/[^a-z0-9]/g, "");

	return (
		normalizedToolName === "askuserquestion" ||
		normalizedToolName === "askquestion"
	);
}

export default function (pi: ExtensionAPI) {
	let hasToolError = false;
	let uiPatched = false;

	function patchUI(ctx: ExtensionContext): void {
		if (uiPatched || !ctx.hasUI) return;

		const originalSelect = ctx.ui.select.bind(ctx.ui);
		const originalConfirm = ctx.ui.confirm.bind(ctx.ui);
		const originalInput = ctx.ui.input.bind(ctx.ui);

		ctx.ui.select = async (title, ...args) => {
			setStatus(AGENT_STATE.BLOCKED);
			try {
				return await originalSelect(title, ...args);
			} finally {
				setStatus(ctx.isIdle() ? AGENT_STATE.IDLE : AGENT_STATE.RUNNING);
			}
		};

		ctx.ui.confirm = async (...args) => {
			setStatus(AGENT_STATE.BLOCKED);
			try {
				return await originalConfirm(...args);
			} finally {
				setStatus(ctx.isIdle() ? AGENT_STATE.IDLE : AGENT_STATE.RUNNING);
			}
		};

		ctx.ui.input = async (...args) => {
			setStatus(AGENT_STATE.BLOCKED);
			try {
				return await originalInput(...args);
			} finally {
				setStatus(ctx.isIdle() ? AGENT_STATE.IDLE : AGENT_STATE.RUNNING);
			}
		};

		uiPatched = true;
	}

	pi.on("session_start", (_event, ctx) => {
		patchUI(ctx);
		hasToolError = false;
		setStatus(AGENT_STATE.IDLE);
	});

	pi.on("input", () => {
		hasToolError = false;
		setStatus(AGENT_STATE.RUNNING);
	});

	pi.on("agent_start", () => {
		hasToolError = false;
		setStatus(AGENT_STATE.RUNNING);
	});

	pi.on("turn_start", () => {
		setStatus(AGENT_STATE.RUNNING);
	});

	pi.on("tool_result", (event) => {
		if (event.isError) {
			hasToolError = true;
			setStatus(AGENT_STATE.ERROR);
			return;
		}

		if (isAskUserQuestionTool(event.toolName)) {
			setStatus(AGENT_STATE.RUNNING);
		}
	});

	pi.on("tool_call", (event) => {
		if (isAskUserQuestionTool(event.toolName)) {
			setStatus(AGENT_STATE.BLOCKED);
		}
	});

	pi.on("tool_execution_start", (event) => {
		if (isAskUserQuestionTool(event.toolName)) {
			setStatus(AGENT_STATE.BLOCKED);
		}
	});

	pi.on("tool_execution_end", (event) => {
		if (event.isError) {
			hasToolError = true;
			setStatus(AGENT_STATE.ERROR);
			return;
		}

		if (isAskUserQuestionTool(event.toolName)) {
			setStatus(AGENT_STATE.RUNNING);
		}
	});

	pi.on("agent_settled", () => {
		setStatus(hasToolError ? AGENT_STATE.ERROR : AGENT_STATE.DONE);
	});

	pi.on("session_shutdown", () => {
		clearStatus();
	});
}
