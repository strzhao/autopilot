import { spawn } from "node:child_process";
import readline from "node:readline";

function toErrorMessage(error) {
  if (!error) {
    return "Unknown error";
  }

  if (typeof error === "string") {
    return error;
  }

  if (typeof error.message === "string" && error.message) {
    return error.message;
  }

  return JSON.stringify(error);
}

export class JsonRpcError extends Error {
  constructor(message, payload = null) {
    super(message);
    this.name = "JsonRpcError";
    this.payload = payload;
  }
}

export class CodexAppServerClient {
  constructor(options = {}) {
    this.codexCommand = options.codexCommand || "codex";
    this.cwd = options.cwd || process.cwd();
    this.env = options.env || process.env;
    this.child = null;
    this.reader = null;
    this.nextId = 1;
    this.pending = new Map();
    this.stderr = [];
    this.started = false;
  }

  async start() {
    if (this.started) {
      return;
    }

    this.child = spawn(this.codexCommand, ["app-server", "--listen", "stdio://"], {
      cwd: this.cwd,
      env: this.env,
      stdio: ["pipe", "pipe", "pipe"],
    });

    this.child.on("error", (error) => {
      this.#failAllPending(new JsonRpcError(`Failed to start codex app-server: ${toErrorMessage(error)}`));
    });

    this.child.stderr.setEncoding("utf8");
    this.child.stderr.on("data", (chunk) => {
      this.stderr.push(chunk);
    });

    this.reader = readline.createInterface({ input: this.child.stdout });
    this.reader.on("line", (line) => {
      this.#handleLine(line);
    });

    this.child.on("exit", (code, signal) => {
      const stderr = this.stderr.join("").trim();
      const reason = stderr || `codex app-server exited (${signal || code || "unknown"})`;
      this.#failAllPending(new JsonRpcError(reason));
    });

    const result = await this.request("initialize", {
      clientInfo: {
        name: "string-codex-plugin",
        title: "String Codex Plugin Helper",
        version: "0.1.0",
      },
      capabilities: {
        experimentalApi: false,
      },
    });

    this.notify("initialized", {});
    this.started = true;
    return result;
  }

  notify(method, params = {}) {
    this.#write({ jsonrpc: "2.0", method, params });
  }

  request(method, params) {
    const id = this.nextId++;
    const payload = { jsonrpc: "2.0", id, method, params };

    return new Promise((resolve, reject) => {
      this.pending.set(id, { resolve, reject, method });
      this.#write(payload);
    });
  }

  async close() {
    if (!this.child) {
      return;
    }

    const child = this.child;
    this.child = null;

    this.reader?.close();
    this.reader = null;

    child.stdin.end();

    await new Promise((resolve) => {
      const timer = setTimeout(() => {
        if (!child.killed) {
          child.kill("SIGTERM");
        }
      }, 250);

      child.once("exit", () => {
        clearTimeout(timer);
        resolve();
      });
    });
  }

  #handleLine(line) {
    const trimmed = line.trim();
    if (!trimmed) {
      return;
    }

    let message;
    try {
      message = JSON.parse(trimmed);
    } catch (error) {
      this.#failAllPending(
        new JsonRpcError(`Failed to parse app-server response: ${toErrorMessage(error)}`)
      );
      return;
    }

    if (typeof message.id === "undefined") {
      return;
    }

    const pending = this.pending.get(message.id);
    if (!pending) {
      return;
    }

    this.pending.delete(message.id);

    if (message.error) {
      pending.reject(new JsonRpcError(toErrorMessage(message.error), message.error));
      return;
    }

    pending.resolve(message.result);
  }

  #write(payload) {
    if (!this.child || !this.child.stdin.writable) {
      throw new JsonRpcError("codex app-server is not running");
    }

    this.child.stdin.write(`${JSON.stringify(payload)}\n`);
  }

  #failAllPending(error) {
    for (const { reject } of this.pending.values()) {
      reject(error);
    }
    this.pending.clear();
  }
}
