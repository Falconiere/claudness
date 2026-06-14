import { execFileSync, spawn } from "node:child_process";
import { existsSync, mkdirSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import type {
  ExtensionAPI,
  ExtensionContext,
  ToolCallEvent,
  ToolResultEvent,
} from "@earendil-works/pi-coding-agent";

const extensionDir = dirname(fileURLToPath(import.meta.url));
const packageRoot = resolve(extensionDir, "../..");

const preToolsScript = join(packageRoot, "plugins/claudness/hooks/pre-tools/mod.sh");
const postToolsScript = join(packageRoot, "plugins/claudness/hooks/post-tools/mod.sh");
const codeIntelRegister = join(packageRoot, "plugins/code-intel/hooks/register.sh");
const tsQualityRegister = join(packageRoot, "plugins/ts-quality/hooks/register.sh");
const rustQualityRegister = join(packageRoot, "plugins/rust-quality/hooks/register.sh");

const gateStatusKey = "claudness-gate";

type HookOutput = {
  systemMessage?: string;
  hookSpecificOutput?: {
    additionalContext?: string;
    permissionDecision?: string;
    permissionDecisionReason?: string;
  };
};

export function agentDir(): string {
  return process.env.PI_CODING_AGENT_DIR || join(homedir(), ".pi", "agent");
}

export function baseEnv(cwd: string): NodeJS.ProcessEnv {
  const dir = agentDir();
  mkdirSync(dir, { recursive: true });
  return {
    ...process.env,
    CLAUDNESS_CONFIG_DIR: dir,
    CLAUDE_CONFIG_DIR: dir,
    PI_CODING_AGENT_DIR: dir,
    CLAUDNESS_PROJECT_CONFIG_DIRNAME: ".pi",
    CLAUDNESS_RUNTIME: "pi",
    PWD: cwd,
  };
}

export function projectRoot(cwd: string): string {
  try {
    return (
      execFileSync("git", ["-C", cwd, "rev-parse", "--show-toplevel"], {
        encoding: "utf8",
        stdio: ["ignore", "pipe", "ignore"],
      }).trim() || cwd
    );
  } catch {
    return cwd;
  }
}

export function gateFile(cwd: string): string {
  return join(projectRoot(cwd), ".claude", "tmp", "quality-gate-status.json");
}

export function mappedToolName(toolName: string): string | undefined {
  switch (toolName) {
    case "bash":
      return "Bash";
    case "read":
      return "Read";
    case "edit":
      return "Edit";
    case "write":
      return "Write";
    case "grep":
      return "Grep";
    case "find":
    case "ls":
      return "Glob";
    default:
      return undefined;
  }
}

export function toolInputForEvent(
  event: ToolCallEvent | ToolResultEvent,
): Record<string, unknown> {
  switch (event.toolName) {
    case "bash":
      return {
        command: event.input.command,
        timeout: event.input.timeout,
      };
    case "read":
      return {
        path: event.input.path,
        file_path: event.input.path,
        offset: event.input.offset,
        limit: event.input.limit,
      };
    case "edit":
      return {
        path: event.input.path,
        file_path: event.input.path,
        target_file: event.input.path,
        edits: event.input.edits,
      };
    case "write":
      return {
        path: event.input.path,
        file_path: event.input.path,
        target_file: event.input.path,
      };
    case "grep":
      return { ...event.input };
    case "find":
    case "ls":
      return { ...event.input };
    default:
      return { ...event.input };
  }
}

export function toolCallPayload(event: ToolCallEvent): string {
  return JSON.stringify({
    tool_name: mappedToolName(event.toolName),
    tool_input: toolInputForEvent(event),
  });
}

export function parseBashExitCode(event: ToolResultEvent): number | undefined {
  if (event.toolName !== "bash") return undefined;
  if (!event.isError) return 0;
  const text = (event.content || [])
    .filter((part): part is { type: "text"; text: string } => part.type === "text")
    .map((part) => part.text)
    .join("\n");
  const match = text.match(/Command exited with code (\d+)/);
  if (match) return Number(match[1]);
  return undefined;
}

export function toolResultPayload(event: ToolResultEvent): string {
  const exitCode = parseBashExitCode(event);
  return JSON.stringify({
    tool_name: mappedToolName(event.toolName),
    tool_input: toolInputForEvent(event),
    tool_response: exitCode === undefined ? undefined : { metadata: { exit_code: exitCode } },
    tool_output: exitCode === undefined ? undefined : { exitCode },
  });
}

export async function runHook(
  script: string,
  cwd: string,
  input: string,
  signal?: AbortSignal
): Promise<{ code: number; stdout: string; stderr: string }> {
  return new Promise((resolve, reject) => {
    const child = spawn("bash", [script], {
      cwd,
      env: baseEnv(cwd),
      stdio: ["pipe", "pipe", "pipe"],
      signal,
    });

    let stdout = "";
    let stderr = "";

    child.stdout.on("data", (chunk) => {
      stdout += String(chunk);
    });
    child.stderr.on("data", (chunk) => {
      stderr += String(chunk);
    });

    const handleError = (error: Error) => {
      stderr += error.message;
    };

    child.on("error", handleError);
    child.on("close", (code) => {
      resolve({ code: code ?? 1, stdout: stdout.trim(), stderr: stderr.trim() });
    });

    child.stdin.end(input);
  });
}

export function parseHookOutput(stdout: string): HookOutput | undefined {
  if (!stdout) return undefined;
  try {
    return JSON.parse(stdout) as HookOutput;
  } catch {
    return undefined;
  }
}

export function hookText(output: HookOutput | undefined): string | undefined {
  if (!output) return undefined;
  const parts = [output.systemMessage, output.hookSpecificOutput?.additionalContext].filter(
    (value): value is string => Boolean(value),
  );
  if (parts.length === 0) return undefined;
  return parts.join("\n\n");
}

export function refreshGateStatus(ctx: ExtensionContext) {
  if (!ctx.hasUI) return;
  const theme = ctx.ui.theme;
  const file = gateFile(ctx.cwd);
  if (!existsSync(file)) {
    ctx.ui.setStatus(gateStatusKey, theme.fg("dim", "gate: clear"));
    return;
  }

  try {
    const raw = JSON.parse(readFileSync(file, "utf8")) as {
      status?: string;
      reason?: string;
    };
    if (raw.status === "failing") {
      const reason = raw.reason ? ` — ${raw.reason}` : "";
      ctx.ui.setStatus(gateStatusKey, theme.fg("warning", `gate: failing${reason}`));
      return;
    }
  } catch {
    ctx.ui.setStatus(gateStatusKey, theme.fg("warning", "gate: unreadable"));
    return;
  }

  ctx.ui.setStatus(gateStatusKey, theme.fg("success", "gate: clear"));
}

export async function runRegistrySync(cwd: string) {
  const env = baseEnv(cwd);
  mkdirSync(join(agentDir(), "claudness", "pre-tools.d"), { recursive: true });
  mkdirSync(join(agentDir(), "claudness", "post-tools.d"), { recursive: true });

  for (const script of [codeIntelRegister, tsQualityRegister, rustQualityRegister]) {
    if (!existsSync(script)) continue;
    await new Promise<void>((resolve) => {
      const child = spawn("bash", [script], {
        cwd,
        env,
        stdio: ["pipe", "ignore", "ignore"],
      });
      child.on("close", () => resolve());
      child.on("error", () => resolve());
      child.stdin.end("{}");
    });
  }
}

export default function claudnessPiExtension(pi: ExtensionAPI) {
  pi.on("session_start", async (_event, ctx) => {
    await runRegistrySync(ctx.cwd);
    refreshGateStatus(ctx);
  });

  pi.on("session_shutdown", (_event, ctx) => {
    if (ctx.hasUI) {
      ctx.ui.setStatus(gateStatusKey, undefined);
    }
  });

  pi.on("tool_call", async (event, ctx) => {
    const name = mappedToolName(event.toolName);
    if (!name || !existsSync(preToolsScript)) return;

    const result = await runHook(preToolsScript, ctx.cwd, toolCallPayload(event), ctx.signal);
    const output = parseHookOutput(result.stdout);

    if (result.code === 2) {
      return { block: true, reason: result.stderr || result.stdout || "Blocked by claudness pre-tool hook" };
    }

    if (output?.hookSpecificOutput?.permissionDecision === "deny") {
      return {
        block: true,
        reason: output.hookSpecificOutput.permissionDecisionReason || "Blocked by claudness pre-tool hook",
      };
    }

    const note = hookText(output);
    if (note && ctx.hasUI) {
      ctx.ui.notify(note, "info");
    }
  });

  pi.on("tool_result", async (event, ctx) => {
    if (!existsSync(postToolsScript)) return;
    if (event.toolName !== "bash" && event.toolName !== "edit" && event.toolName !== "write") {
      return;
    }

    const result = await runHook(postToolsScript, ctx.cwd, toolResultPayload(event), ctx.signal);
    const output = parseHookOutput(result.stdout);
    refreshGateStatus(ctx);

    if (result.code !== 0 && result.stderr) {
      return {
        content: [...event.content, { type: "text" as const, text: `\n[claudness]\n${result.stderr}` }],
      };
    }

    const text = hookText(output);
    if (!text) return { content: event.content };
    return {
      content: [...event.content, { type: "text" as const, text: `\n[claudness]\n${text}` }],
    };
  });
}
