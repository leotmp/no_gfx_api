import * as fs from "fs";
import * as path from "path";
import {
	ExtensionContext,
	OutputChannel,
	Position,
	Range,
	Selection,
	TextDocumentContentProvider,
	Uri,
	commands,
	window,
	workspace,
} from "vscode";
import {
	LanguageClient,
	LanguageClientOptions,
	ServerOptions,
	TransportKind,
} from "vscode-languageclient/node";

let client: LanguageClient | undefined;
const FMAG_SCHEME = "misl-fmag";
const SPIRV_SCHEME = "misl-spirv";
let latestFmag = "";
let latestSpirv = "";
let lastServerPathFromConfig = "";

const LSP_CONFIG_FILENAME = "misl.lsp.json";

/** Default misl.lsp.json — all features on, empty collections/server_path. */
export const DEFAULT_MISL_LSP_JSON = `{
  "server_path": "",
  "collections": [],
  "features": {
    "hover": true,
    "definition": true,
    "type_definition": true,
    "references": true,
    "document_highlight": true,
    "document_symbol": true,
    "workspace_symbol": true,
    "rename": true,
    "completion": true,
    "signature_help": true,
    "semantic_tokens": true,
    "inlay_hints": true,
    "code_actions": true,
    "code_lens": true,
    "fmag_preview": true,
    "spirv_preview": true
  }
}
`;

interface MislLspConfig {
	server_path?: string;
	collections?: Array<{ name: string; path: string }>;
	features?: Record<string, boolean>;
}

class MislFmagProvider implements TextDocumentContentProvider {
	provideTextDocumentContent(_uri: Uri): string {
		return latestFmag;
	}
}

class MislSpirvProvider implements TextDocumentContentProvider {
	provideTextDocumentContent(_uri: Uri): string {
		return latestSpirv;
	}
}

function workspaceRoot(): string | undefined {
	return workspace.workspaceFolders?.[0]?.uri.fsPath;
}

function lspConfigPath(): string | undefined {
	const root = workspaceRoot();
	if (!root) {
		return undefined;
	}
	return path.join(root, LSP_CONFIG_FILENAME);
}

function readMislLspConfig(): MislLspConfig | undefined {
	const cfgPath = lspConfigPath();
	if (!cfgPath || !fs.existsSync(cfgPath)) {
		return undefined;
	}
	try {
		const raw = fs.readFileSync(cfgPath, "utf8");
		return JSON.parse(raw) as MislLspConfig;
	} catch {
		return undefined;
	}
}

function resolveServerPath(context: ExtensionContext): string {
	const fileCfg = readMislLspConfig();
	if (fileCfg && typeof fileCfg.server_path === "string" && fileCfg.server_path.length > 0) {
		const sp = fileCfg.server_path;
		if (path.isAbsolute(sp)) {
			return sp;
		}
		const root = workspaceRoot();
		if (root) {
			return path.resolve(root, sp);
		}
		return sp;
	}

	const override = workspace.getConfiguration("misl").get<string>("serverPath", "");
	if (override && override.length > 0) {
		return override;
	}
	const exe = process.platform === "win32" ? "misl_lsp.exe" : "misl_lsp";
	return path.join(context.extensionPath, "server", exe);
}

async function createOrOpenLspConfig(): Promise<void> {
	const root = workspaceRoot();
	if (!root) {
		window.showErrorMessage("Open a workspace folder to create misl.lsp.json");
		return;
	}
	const cfgPath = path.join(root, LSP_CONFIG_FILENAME);
	if (!fs.existsSync(cfgPath)) {
		fs.writeFileSync(cfgPath, DEFAULT_MISL_LSP_JSON, "utf8");
	}
	const doc = await workspace.openTextDocument(cfgPath);
	await window.showTextDocument(doc);
}

async function restartClient(context: ExtensionContext, output: OutputChannel): Promise<void> {
	if (client) {
		try {
			await client.stop();
		} catch {
			/* ignore */
		}
		client = undefined;
	}
	await startClient(context, output);
}

async function startClient(context: ExtensionContext, output: OutputChannel): Promise<void> {
	const fileCfg = readMislLspConfig();
	if (fileCfg) {
		output.appendLine(`Loaded ${LSP_CONFIG_FILENAME}`);
	} else {
		output.appendLine(`No ${LSP_CONFIG_FILENAME} — using defaults (all features on)`);
	}

	const serverPath = resolveServerPath(context);
	lastServerPathFromConfig =
		fileCfg && typeof fileCfg.server_path === "string" ? fileCfg.server_path : "";
	output.appendLine(`Server path: ${serverPath}`);

	if (!fs.existsSync(serverPath)) {
		const msg = `MISL language server not found at:\n${serverPath}\nSet server_path in misl.lsp.json, misl.serverPath, or rebuild with: odin run build -define:TARGET=lspc`;
		output.appendLine(msg);
		window.showErrorMessage(msg);
		return;
	}

	const vscodeCollections = workspace.getConfiguration("misl").get<Record<string, string>>("collections", {});
	const initOptions: { collections?: Record<string, string> } = {};
	// Only pass VS Code collections when no project file owns config.
	if (!fileCfg) {
		initOptions.collections = vscodeCollections;
	}

	const serverOptions: ServerOptions = {
		run: { command: serverPath, transport: TransportKind.stdio },
		debug: { command: serverPath, transport: TransportKind.stdio },
	};

	const clientOptions: LanguageClientOptions = {
		documentSelector: [{ language: "misl" }, { pattern: "**/*.misl" }],
		synchronize: {
			fileEvents: [
				workspace.createFileSystemWatcher("**/*.misl"),
				workspace.createFileSystemWatcher("**/misl.lsp.json"),
			],
		},
		initializationOptions: initOptions,
		outputChannel: output,
	};

	client = new LanguageClient(
		"mislLanguageServer",
		"MISL Language Server",
		serverOptions,
		clientOptions,
	);

	try {
		await client.start();
		output.appendLine("Language client started.");
	} catch (err) {
		const msg = `Failed to start MISL language server: ${err}`;
		output.appendLine(msg);
		window.showErrorMessage(msg);
	}
}

export async function activate(context: ExtensionContext): Promise<void> {
	const output = window.createOutputChannel("MISL Language Server");
	context.subscriptions.push(output);
	output.appendLine("MISL extension activating…");

	const fmagProvider = new MislFmagProvider();
	const spirvProvider = new MislSpirvProvider();
	context.subscriptions.push(
		workspace.registerTextDocumentContentProvider(FMAG_SCHEME, fmagProvider),
		workspace.registerTextDocumentContentProvider(SPIRV_SCHEME, spirvProvider),
	);

	const SHOW_FMAG = "misl.showFmag";
	const SHOW_SPIRV = "misl.showSpirv";

	const parsePreviewArgs = (...args: unknown[]): { uri: string; entity: string } => {
		let uri = "";
		let entity = "";
		// CodeLens may pass (uri, entity), ([uri, entity]), or ({uri, entity}).
		if (args.length >= 2 && typeof args[0] === "string" && typeof args[1] === "string") {
			uri = args[0];
			entity = args[1];
		} else if (args.length >= 1 && Array.isArray(args[0]) && args[0].length >= 2) {
			uri = String(args[0][0] ?? "");
			entity = String(args[0][1] ?? "");
		} else if (args.length === 1 && args[0] && typeof args[0] === "object") {
			const o = args[0] as { uri?: string; entity?: string; arguments?: unknown[] };
			if (Array.isArray(o.arguments) && o.arguments.length >= 2) {
				uri = String(o.arguments[0] ?? "");
				entity = String(o.arguments[1] ?? "");
			} else {
				uri = o.uri ?? "";
				entity = o.entity ?? "";
			}
		}
		return { uri, entity };
	};

	const showFmagHandler = async (...args: unknown[]) => {
		if (!client) {
			window.showErrorMessage("MISL language server is not running");
			return;
		}
		const { uri, entity } = parsePreviewArgs(...args);
		if (!uri || !entity) {
			window.showErrorMessage(`Show FMAG: missing uri/entity (args=${JSON.stringify(args)})`);
			return;
		}
		try {
			const result = await client.sendRequest<{
				fmag: string;
				line: number;
				character: number;
				entity: string;
				search: string;
			}>("misl/fmagPreview", { uri, entity });
			latestFmag = result.fmag ?? "";
			const previewUri = Uri.parse(
				`${FMAG_SCHEME}:${entity}.fmagasm?t=${Date.now()}&src=${encodeURIComponent(uri)}`,
			);
			const doc = await workspace.openTextDocument(previewUri);
			const editor = await window.showTextDocument(doc, { preview: false, viewColumn: 2 });
			const pos = new Position(result.line ?? 0, result.character ?? 0);
			editor.selection = new Selection(pos, pos);
			editor.revealRange(new Range(pos, pos));
		} catch (err) {
			const msg = `Show FMAG failed: ${err}`;
			output.appendLine(msg);
			window.showErrorMessage(msg);
		}
	};

	const showSpirvHandler = async (...args: unknown[]) => {
		if (!client) {
			window.showErrorMessage("MISL language server is not running");
			return;
		}
		const { uri, entity } = parsePreviewArgs(...args);
		if (!uri || !entity) {
			window.showErrorMessage(`Show SPIRV: missing uri/entity (args=${JSON.stringify(args)})`);
			return;
		}
		try {
			const result = await client.sendRequest<{
				spirv: string;
				line: number;
				character: number;
				entity: string;
				search: string;
			}>("misl/spirvPreview", { uri, entity });
			latestSpirv = result.spirv ?? "";
			const previewUri = Uri.parse(
				`${SPIRV_SCHEME}:${entity}.spvasm?t=${Date.now()}&src=${encodeURIComponent(uri)}`,
			);
			const doc = await workspace.openTextDocument(previewUri);
			const editor = await window.showTextDocument(doc, { preview: false, viewColumn: 2 });
			const pos = new Position(result.line ?? 0, result.character ?? 0);
			editor.selection = new Selection(pos, pos);
			editor.revealRange(new Range(pos, pos));
		} catch (err) {
			const msg = `Show SPIRV failed: ${err}`;
			output.appendLine(msg);
			window.showErrorMessage(msg);
		}
	};

	context.subscriptions.push(
		commands.registerCommand(SHOW_FMAG, showFmagHandler),
		commands.registerCommand(SHOW_SPIRV, showSpirvHandler),
		commands.registerCommand("misl.createLspConfig", createOrOpenLspConfig),
	);

	const configWatcher = workspace.createFileSystemWatcher("**/misl.lsp.json");
	const onConfigFileChange = async () => {
		const cfg = readMislLspConfig();
		const nextServerPath = cfg && typeof cfg.server_path === "string" ? cfg.server_path : "";
		if (nextServerPath !== lastServerPathFromConfig) {
			output.appendLine("misl.lsp.json server_path changed — restarting language client");
			await restartClient(context, output);
			return;
		}
		output.appendLine("misl.lsp.json changed — server will reload via didChangeWatchedFiles");
	};
	configWatcher.onDidChange(onConfigFileChange);
	configWatcher.onDidCreate(onConfigFileChange);
	configWatcher.onDidDelete(async () => {
		output.appendLine("misl.lsp.json deleted — restarting language client with defaults");
		await restartClient(context, output);
	});
	context.subscriptions.push(configWatcher);

	await startClient(context, output);
}

export function deactivate(): Thenable<void> | undefined {
	if (!client) {
		return undefined;
	}
	return client.stop();
}
