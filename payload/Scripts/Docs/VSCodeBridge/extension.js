const crypto = require('crypto');
const fs = require('fs');
const os = require('os');
const path = require('path');
const vscode = require('vscode');

const TOC_COMMAND = 'markdown.extension.toc.create';
const REQUEST_ROOT = path.join(os.tmpdir(), 'ueproject-docs-tools');
const processing = new Set();
const watchers = new Map();
let queue = Promise.resolve();

function getWorkspaceFolders() {
  return vscode.workspace.workspaceFolders || [];
}

function getWorkspaceKey(workspaceRoot) {
  return crypto.createHash('sha1').update(path.resolve(workspaceRoot).toLowerCase()).digest('hex');
}

function getRequestDirectory(workspaceRoot) {
  return path.join(REQUEST_ROOT, getWorkspaceKey(workspaceRoot));
}

async function commandExists(commandId) {
  const commands = await vscode.commands.getCommands(true);
  return commands.includes(commandId);
}

async function openAndProcessTocRequest(request) {
  if (!(await commandExists(TOC_COMMAND))) {
    console.warn(`[DocsBridge] Markdown All in One command missing: ${TOC_COMMAND}`);
    return;
  }

  const document = await vscode.workspace.openTextDocument(request.filePath);
  const editor = await vscode.window.showTextDocument(document, {
    preview: false,
    preserveFocus: false,
  });

  const marker = request.marker || '<!-- docs-tools-toc -->';
  const markerText = document.getText();
  const markerIndex = markerText.indexOf(marker);
  if (markerIndex === -1) {
    console.warn(`[DocsBridge] TOC marker not found in ${request.filePath}`);
    return;
  }

  const markerStart = document.positionAt(markerIndex);
  const markerEnd = document.positionAt(markerIndex + marker.length);
  const markerLine = document.lineAt(markerStart.line);
  const deleteEnd =
    markerLine.rangeIncludingLineBreak.end.isAfter(markerEnd) ?
      markerLine.rangeIncludingLineBreak.end :
      markerEnd;

  await editor.edit((editBuilder) => {
    editBuilder.delete(new vscode.Range(markerStart, deleteEnd));
  });

  editor.selection = new vscode.Selection(markerStart, markerStart);
  await vscode.commands.executeCommand(TOC_COMMAND);
  await document.save();
}

async function processRequestFile(requestPath) {
  if (processing.has(requestPath)) {
    return;
  }

  processing.add(requestPath);
  try {
    await new Promise((resolve) => setTimeout(resolve, 150));
    const raw = await fs.promises.readFile(requestPath, 'utf8');
    const request = JSON.parse(raw);
    await openAndProcessTocRequest(request);
  } catch (error) {
    console.error(`[DocsBridge] Failed to process ${requestPath}`, error);
  } finally {
    processing.delete(requestPath);
    try {
      await fs.promises.unlink(requestPath);
    } catch (_error) {
      // Ignore cleanup failures.
    }
  }
}

function enqueueRequestFile(requestPath) {
  queue = queue.then(() => processRequestFile(requestPath));
  return queue;
}

async function processExistingRequestsForWorkspace(workspaceRoot) {
  const requestDir = getRequestDirectory(workspaceRoot);
  if (!fs.existsSync(requestDir)) {
    return;
  }

  const entries = await fs.promises.readdir(requestDir);
  const requestFiles = entries
    .filter((entry) => entry.endsWith('.json'))
    .map((entry) => path.join(requestDir, entry))
    .sort();

  for (const requestFile of requestFiles) {
    enqueueRequestFile(requestFile);
  }
}

function ensureWatcherForWorkspace(context, workspaceRoot) {
  const normalizedRoot = path.resolve(workspaceRoot);
  if (watchers.has(normalizedRoot)) {
    return;
  }

  const requestDir = getRequestDirectory(normalizedRoot);
  fs.mkdirSync(requestDir, {recursive: true});

  const watcher = fs.watch(requestDir, (_eventType, fileName) => {
    if (!fileName || !fileName.endsWith('.json')) {
      return;
    }

    const requestPath = path.join(requestDir, fileName);
    if (fs.existsSync(requestPath)) {
      enqueueRequestFile(requestPath);
    }
  });

  watchers.set(normalizedRoot, watcher);
  context.subscriptions.push({
    dispose: () => {
      watcher.close();
      watchers.delete(normalizedRoot);
    },
  });

  void processExistingRequestsForWorkspace(normalizedRoot);
}

function refreshWorkspaceWatchers(context) {
  for (const folder of getWorkspaceFolders()) {
    if (folder.uri.scheme !== 'file') {
      continue;
    }

    ensureWatcherForWorkspace(context, folder.uri.fsPath);
  }
}

function activate(context) {
  context.subscriptions.push(
    vscode.commands.registerCommand('ueproject.docsBridge.processPendingRequests', async () => {
      for (const folder of getWorkspaceFolders()) {
        if (folder.uri.scheme !== 'file') {
          continue;
        }

        await processExistingRequestsForWorkspace(folder.uri.fsPath);
      }
    }),
  );

  refreshWorkspaceWatchers(context);

  context.subscriptions.push(
    vscode.workspace.onDidChangeWorkspaceFolders(() => {
      refreshWorkspaceWatchers(context);
    }),
  );
}

function deactivate() {}

module.exports = {
  activate,
  deactivate,
};
