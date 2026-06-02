import React, {type ComponentProps, useCallback, useEffect, useMemo, useRef, useState} from 'react';
import clsx from 'clsx';
import DocSidebar from '@theme-original/DocSidebar';
import type {PropSidebarItem} from '@docusaurus/plugin-content-docs';
import {createPortal} from 'react-dom';

import styles from './index.module.css';
import {getDocsRouteFromToken, useDocsAuthoringApi, type DocsNodeType, type DocsTreeNode, type DocsTreePayload} from '../authoring/api';

type Props = ComponentProps<typeof DocSidebar>;

type DragPayload = {
  path: string;
  type: DocsNodeType;
  parentPath: string;
  siblingIndex: number;
};

type DropMode = 'before' | 'after' | 'inside';
type CreateMode = 'page' | 'section';

type DropIntent = {
  destinationParentPath: string;
  insertIndex: number;
  mode: DropMode;
};

type TreeTarget = DragPayload & {
  name: string;
  node: DocsTreeNode;
};

type CreateContext = {
  mode: CreateMode | null;
  target: TreeTarget;
};

type SidebarRouteMaps = {
  byDocId: Record<string, string>;
  byLabel: Record<string, string>;
};

function normalizeRoute(value: string): string {
  return value.replace(/\/+$/g, '').toLowerCase() || '/docs';
}

function routeIsActive(currentRoute: string, targetRoute: string): boolean {
  return normalizeRoute(currentRoute) === normalizeRoute(targetRoute);
}

function routeIsNestedUnder(currentRoute: string, sectionRoute: string): boolean {
  const current = normalizeRoute(currentRoute);
  const section = normalizeRoute(sectionRoute);
  return current === section || current.startsWith(`${section}/`);
}

function normalizeToken(value: string): string {
  return (value || '').replaceAll('\\', '/').trim().replace(/^\/+|\/+$/g, '').replace(/\.md$/i, '');
}

function normalizeDocId(value: string): string {
  return normalizeToken(value);
}

function buildSidebarRouteMaps(items: readonly PropSidebarItem[]): SidebarRouteMaps {
  const byDocId: Record<string, string> = {};
  const byLabel: Record<string, string> = {};

  const visit = (nodes: readonly PropSidebarItem[]) => {
    for (const item of nodes) {
      if (item.type === 'link') {
        if (item.docId) {
          byDocId[normalizeDocId(item.docId)] = item.href;
        }
        byLabel[item.label.toLowerCase()] = item.href;
        continue;
      }

      if (item.type === 'category') {
        if (item.href) {
          byLabel[item.label.toLowerCase()] = item.href;
        }
        visit(item.items);
      }
    }
  };

  visit(items);
  return {byDocId, byLabel};
}

function SidebarIcon({name}: {name: 'plus' | 'folderPlus' | 'filePlus' | 'trash' | 'check' | 'x'}): React.ReactElement {
  const common = {
    className: styles.actionIcon,
    viewBox: '0 0 24 24',
    'aria-hidden': true,
  };
  switch (name) {
    case 'plus':
      return <svg {...common}><path d="M12 5v14M5 12h14" /></svg>;
    case 'folderPlus':
      return <svg {...common}><path d="M4 20h16a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-8l-2-2H4a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2z" /><path d="M12 17v-6M9 14h6" /></svg>;
    case 'filePlus':
      return <svg {...common}><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z" /><path d="M14 2v6h6" /><path d="M12 18v-6M9 15h6" /></svg>;
    case 'trash':
      return <svg {...common}><path d="M4 7h16M9 7V4h6v3M8 11v7M12 11v7M16 11v7" /></svg>;
    case 'check':
      return <svg {...common}><path d="M20 6 9 17l-5-5" /></svg>;
    case 'x':
      return <svg {...common}><path d="M18 6 6 18M6 6l12 12" /></svg>;
    default:
      return <svg {...common}><circle cx="12" cy="12" r="9" /></svg>;
  }
}

function ActionButton({
  activateOnPointerDown,
  disabled,
  icon,
  label,
  onClick,
}: {
  activateOnPointerDown?: boolean;
  disabled?: boolean;
  icon: 'plus' | 'folderPlus' | 'filePlus' | 'trash' | 'check' | 'x';
  label: string;
  onClick: () => void;
}): React.ReactElement {
  const handleActivate = (event: React.SyntheticEvent) => {
    event.preventDefault();
    event.stopPropagation();
    if (!disabled) {
      onClick();
    }
  };

  return (
    <button
      type="button"
      className={styles.actionButton}
      onPointerDown={(event) => {
        if (activateOnPointerDown) {
          handleActivate(event);
          return;
        }
        event.preventDefault();
        event.stopPropagation();
      }}
      onDragStart={(event) => {
        event.preventDefault();
        event.stopPropagation();
      }}
      onClick={handleActivate}
      onKeyDown={(event) => {
        if (event.key === 'Enter' || event.key === ' ') {
          handleActivate(event);
        }
      }}
      disabled={disabled}
      draggable={false}
      aria-label={label}
      title={label}
    >
      <SidebarIcon name={icon} />
    </button>
  );
}

export default function DocSidebarWrapper(props: Props): React.ReactElement {
  const {runtimeReady, requestJson} = useDocsAuthoringApi();
  const [tree, setTree] = useState<DocsTreePayload>({root: 'Docs', children: []});
  const [busy, setBusy] = useState(false);
  const [errorText, setErrorText] = useState('');
  const [statusText, setStatusText] = useState('');
  const [dropTargetPath, setDropTargetPath] = useState('');
  const [dropTargetMode, setDropTargetMode] = useState<DropMode>('after');
  const [dragSource, setDragSource] = useState<DragPayload | null>(null);
  const [hoveredPath, setHoveredPath] = useState('');
  const [createContext, setCreateContext] = useState<CreateContext | null>(null);
  const [createName, setCreateName] = useState('');
  const [deleteTarget, setDeleteTarget] = useState<TreeTarget | null>(null);
  const [expandedSections, setExpandedSections] = useState<Record<string, boolean>>({});
  const [currentRoute, setCurrentRoute] = useState(() => (typeof window === 'undefined' ? '/docs/' : window.location.pathname));
  const shellRef = useRef<HTMLDivElement>(null);
  const sidebarRouteMaps = useMemo(() => buildSidebarRouteMaps((props.sidebar ?? []) as readonly PropSidebarItem[]), [props.sidebar]);
  const dialogRoot = typeof document === 'undefined' ? null : document.body;

  const resolveNodeRoute = useCallback(
    (node: DocsTreeNode): string => {
      const normalizedPath = normalizeToken(node.path);
      if (normalizedPath) {
        if (node.type === 'section') {
          const sectionDocId = `${normalizedPath}/README`;
          const sectionRoute = sidebarRouteMaps.byDocId[sectionDocId];
          if (sectionRoute) {
            return sectionRoute;
          }
        } else {
          const pageRoute = sidebarRouteMaps.byDocId[normalizedPath];
          if (pageRoute) {
            return pageRoute;
          }
        }
      }

      const labelRoute = sidebarRouteMaps.byLabel[node.name.toLowerCase()];
      if (labelRoute) {
        return labelRoute;
      }

      return getDocsRouteFromToken(node.path);
    },
    [sidebarRouteMaps],
  );

  const loadTree = useCallback(async () => {
    if (!runtimeReady) {
      return;
    }
    try {
      const payload = await requestJson<{ok: true; tree: DocsTreePayload}>('/api/tree');
      setTree(payload.tree);
      setErrorText('');
      setStatusText('');
    } catch (error) {
      setErrorText(error instanceof Error ? error.message : 'Failed to load docs structure.');
    }
  }, [requestJson, runtimeReady]);

  useEffect(() => {
    void loadTree();
  }, [loadTree]);

  useEffect(() => {
    const handleRouteChange = () => {
      setCurrentRoute(window.location.pathname);
    };
    window.addEventListener('popstate', handleRouteChange);
    window.addEventListener('hashchange', handleRouteChange);
    return () => {
      window.removeEventListener('popstate', handleRouteChange);
      window.removeEventListener('hashchange', handleRouteChange);
    };
  }, []);

  useEffect(() => {
    if (!tree.children.length) {
      return;
    }
    setExpandedSections((current) => {
      const nextExpanded = {...current};
      let changed = false;
      const visit = (nodes: DocsTreeNode[]) => {
        nodes.forEach((node) => {
          if (node.type === 'section') {
            const route = resolveNodeRoute(node);
            if (routeIsNestedUnder(currentRoute, route) && !nextExpanded[node.path]) {
              nextExpanded[node.path] = true;
              changed = true;
            }
            if (node.children?.length) {
              visit(node.children);
            }
          }
        });
      };
      visit(tree.children);
      return changed ? nextExpanded : current;
    });
  }, [currentRoute, resolveNodeRoute, tree]);

  useEffect(() => {
    const shell = shellRef.current;
    if (!shell) {
      return;
    }
    const onShellPointerDown = (event: PointerEvent) => {
      const target = event.target as HTMLElement | null;
      if (!target?.closest(`.${styles.rowActions}`)) {
      }
    };
    shell.addEventListener('pointerdown', onShellPointerDown);
    return () => {
      shell.removeEventListener('pointerdown', onShellPointerDown);
    };
  }, []);

  const moveNode = useCallback(
    async (source: DragPayload, destinationParentPath: string, insertIndex: number) => {
      setBusy(true);
      setErrorText('');
      try {
        await requestJson('/api/move', {
          method: 'POST',
          headers: {'Content-Type': 'application/json'},
          body: JSON.stringify({
            sourcePath: source.path,
            destinationParentPath,
            insertIndex,
          }),
        });
        await loadTree();
        setStatusText('Sidebar order updated.');
      } catch (error) {
        const message = error instanceof Error ? error.message : 'Move failed.';
        setErrorText(message);
        if (message.toLowerCase().includes('reverted')) {
          setStatusText('Move was undone to protect docs references.');
        } else {
          setStatusText('');
        }
        await loadTree();
      } finally {
        setBusy(false);
        setDropTargetPath('');
        setDragSource(null);
      }
    },
    [loadTree, requestJson],
  );

  const getDropIntent = useCallback((node: DocsTreeNode, parentPath: string, siblingIndex: number, mode: DropMode): DropIntent => {
    if (mode === 'inside' && node.type === 'section') {
      return {
        destinationParentPath: node.path,
        insertIndex: node.children?.length ?? 0,
        mode,
      };
    }

    return {
      destinationParentPath: parentPath,
      insertIndex: mode === 'before' ? siblingIndex : siblingIndex + 1,
      mode,
    };
  }, []);

  const moveRelativeToNode = useCallback(
    async (source: DragPayload, node: DocsTreeNode, parentPath: string, siblingIndex: number, mode: DropMode) => {
      if (source.path === node.path) {
        setDropTargetPath('');
        return;
      }

      const intent = getDropIntent(node, parentPath, siblingIndex, mode);
      await moveNode(source, intent.destinationParentPath, intent.insertIndex);
    },
    [getDropIntent, moveNode],
  );

  const beginCreate = useCallback((target: TreeTarget) => {
    setCreateName('');
    setCreateContext({mode: null, target});
    setErrorText('');
    setStatusText('');
  }, []);

  const submitCreate = useCallback(async () => {
    const context = createContext;
    const trimmedName = createName.trim();
    if (!context || !context.mode || !trimmedName) {
      return;
    }

    const {mode, target} = context;
    setBusy(true);
    setErrorText('');
    try {
      const createPayload = await requestJson<{ok: true; result: {path: string}}>(mode === 'page' ? '/api/create/page' : '/api/create/section', {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body:
          mode === 'page'
            ? JSON.stringify({
                sectionPath: target.parentPath,
                pageName: trimmedName,
                title: trimmedName,
              })
            : JSON.stringify({
                parentPath: target.parentPath,
                sectionName: trimmedName,
                title: trimmedName,
              }),
      });

      await requestJson('/api/move', {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({
          sourcePath: createPayload.result.path,
          destinationParentPath: target.parentPath,
          insertIndex: target.siblingIndex + 1,
        }),
      });

      await loadTree();
      setCreateContext(null);
      setCreateName('');
      setStatusText(`Created ${mode}: ${createPayload.result.path}`);
      if (mode === 'page') {
        window.location.assign(`${getDocsRouteFromToken(createPayload.result.path)}?edit=1`);
      }
    } catch (error) {
      setErrorText(error instanceof Error ? error.message : `Create ${mode} failed.`);
      setStatusText('');
    } finally {
      setBusy(false);
    }
  }, [createContext, createName, loadTree, requestJson]);

  const confirmDelete = useCallback(async () => {
    if (!deleteTarget) {
      return;
    }

    const route = resolveNodeRoute(deleteTarget.node);
    const shouldRedirect =
      routeIsActive(currentRoute, route) ||
      (deleteTarget.type === 'section' && routeIsNestedUnder(currentRoute, route));

    setBusy(true);
    setErrorText('');
    try {
      await requestJson('/api/delete', {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({
          path: deleteTarget.path,
        }),
      });

      setDeleteTarget(null);
      await loadTree();
      setStatusText(`Deleted ${deleteTarget.name}`);
      if (shouldRedirect) {
        window.location.assign('/docs/');
      }
    } catch (error) {
      setErrorText(error instanceof Error ? error.message : 'Delete failed.');
      setStatusText('');
    } finally {
      setBusy(false);
    }
  }, [currentRoute, deleteTarget, loadTree, requestJson, resolveNodeRoute]);

  const renderNode = useCallback(
    (node: DocsTreeNode, parentPath: string, siblingIndex: number): React.ReactElement => {
      const route = resolveNodeRoute(node);
      const active = routeIsActive(currentRoute, route);
      const expanded = node.type === 'section' ? Boolean(expandedSections[node.path]) : false;
      const target: TreeTarget = {
        path: node.path,
        type: node.type,
        parentPath,
        siblingIndex,
        name: node.name,
        node,
      };
      const showActions = hoveredPath === node.path;
      const isDropTarget = dropTargetPath === node.path;
      const rowActions = (
        <div
          className={clsx(styles.rowActions, showActions && styles.rowActionsVisible)}
          onPointerDown={(event) => {
            event.preventDefault();
            event.stopPropagation();
          }}
          onDragStart={(event) => {
            event.preventDefault();
            event.stopPropagation();
          }}
        >
          <ActionButton
            activateOnPointerDown
            icon="plus"
            label="Add below"
            disabled={busy}
            onClick={() => {
              beginCreate(target);
            }}
          />
          <ActionButton activateOnPointerDown icon="trash" label={`Delete ${node.name}`} disabled={busy} onClick={() => setDeleteTarget(target)} />
        </div>
      );

      const handleDragStart: React.DragEventHandler<HTMLLIElement> = (event) => {
        event.stopPropagation();
        event.dataTransfer.effectAllowed = 'move';
        event.dataTransfer.setData('application/json', JSON.stringify(target));
        setDragSource(target);
      };

      const getModeFromPointer = (event: React.DragEvent<HTMLElement>): DropMode => {
        const rect = (event.currentTarget as HTMLElement).getBoundingClientRect();
        const ratio = rect.height > 0 ? (event.clientY - rect.top) / rect.height : 1;
        if (node.type === 'section' && ratio >= 0.25 && ratio <= 0.75) {
          return 'inside';
        }
        return ratio < 0.5 ? 'before' : 'after';
      };

      const handleDragOver: React.DragEventHandler<HTMLLIElement> = (event) => {
        event.stopPropagation();
        event.preventDefault();
        const mode = getModeFromPointer(event);
        setDropTargetPath(node.path);
        setDropTargetMode(mode);
      };

      const handleDragLeave: React.DragEventHandler<HTMLLIElement> = (event) => {
        event.stopPropagation();
        setDropTargetPath('');
      };

      const handleDrop: React.DragEventHandler<HTMLLIElement> = (event) => {
        event.stopPropagation();
        event.preventDefault();
        const raw = event.dataTransfer.getData('application/json');
        const source = raw ? (JSON.parse(raw) as DragPayload) : dragSource;
        if (!source || source.path === node.path) {
          setDropTargetPath('');
          return;
        }
        const mode = getModeFromPointer(event);
        void moveRelativeToNode(source, node, parentPath, siblingIndex, mode);
      };

      return (
        <li
          key={node.path}
          className="menu__list-item"
          data-ue-docs-path={node.path}
          data-ue-drop-target={isDropTarget ? 'true' : 'false'}
          data-ue-drop-mode={isDropTarget ? dropTargetMode : ''}
          draggable={!busy}
          onDragStart={handleDragStart}
          onDragEnd={() => {
            setDropTargetPath('');
            setDragSource(null);
          }}
          onDragOver={handleDragOver}
          onDragLeave={handleDragLeave}
          onDrop={handleDrop}
          onMouseEnter={() => setHoveredPath(node.path)}
          onMouseLeave={() => setHoveredPath((current) => (current === node.path ? '' : current))}
        >
          {node.type === 'section' ? (
            <div className="menu__list-item-collapsible">
              <a
                className={clsx('menu__link menu__link--sublist', active && 'menu__link--active')}
                href={route}
                onClick={() => setCurrentRoute(route)}
              >
                {node.name}
              </a>
              <button
                type="button"
                className={clsx('clean-btn menu__caret', expanded ? styles.caretExpanded : styles.caretCollapsed)}
                aria-label={expanded ? `Collapse ${node.name}` : `Expand ${node.name}`}
                title={expanded ? 'Collapse section' : 'Expand section'}
                onClick={(event) => {
                  event.preventDefault();
                  event.stopPropagation();
                  setExpandedSections((current) => ({
                    ...current,
                    [node.path]: !expanded,
                  }));
                }}
              />
              {rowActions}
            </div>
          ) : (
            <a
              className={clsx('menu__link', active && 'menu__link--active')}
              href={route}
              onClick={() => setCurrentRoute(route)}
            >
              {node.name}
            </a>
          )}

          {node.type === 'page' ? rowActions : null}

          {node.type === 'section' && expanded && node.children?.length ? (
            <ul className="menu__list">
              {node.children.map((child, childIndex) => renderNode(child, node.path, childIndex))}
            </ul>
          ) : null}
        </li>
      );
    },
    [beginCreate, busy, currentRoute, deleteTarget, dragSource, dropTargetMode, dropTargetPath, expandedSections, hoveredPath, moveRelativeToNode, resolveNodeRoute],
  );

  if (!runtimeReady) {
    return <DocSidebar {...props} />;
  }

  return (
    <div className={styles.sidebarAuthoring} ref={shellRef}>
      <nav className="theme-doc-sidebar-menu menu thin-scrollbar">
        <ul className="menu__list">
          {tree.children.map((node, index) => renderNode(node, '', index))}
        </ul>
      </nav>

      {statusText ? <p className={styles.statusText}>{statusText}</p> : null}
      {errorText ? <p className={styles.errorText}>{errorText}</p> : null}

      {createContext && dialogRoot
        ? createPortal(
            <div className={styles.dialogBackdrop} onMouseDown={() => !busy && setCreateContext(null)}>
              <div className={styles.dialogCard} role="dialog" aria-modal="true" onMouseDown={(event) => event.stopPropagation()}>
                <h3 className={styles.dialogTitle}>
                  {createContext.mode === 'page' ? 'Create Page' : createContext.mode === 'section' ? 'Create Section' : 'Create Item'}
                </h3>
                <p className={styles.dialogBody}>Add below <strong>{createContext.target.name}</strong>.</p>
                <div className={styles.dialogActions}>
                  <ActionButton
                    icon="filePlus"
                    label="New page below"
                    disabled={busy}
                    onClick={() => setCreateContext((current) => (current ? {...current, mode: 'page'} : current))}
                  />
                  <ActionButton
                    icon="folderPlus"
                    label="New section below"
                    disabled={busy}
                    onClick={() => setCreateContext((current) => (current ? {...current, mode: 'section'} : current))}
                  />
                </div>
                {createContext.mode ? (
                  <input
                    className={styles.dialogInput}
                    value={createName}
                    onChange={(event) => setCreateName(event.target.value)}
                    placeholder={createContext.mode === 'page' ? 'Page name' : 'Section name'}
                    aria-label={createContext.mode === 'page' ? 'Page name' : 'Section name'}
                    disabled={busy}
                    autoFocus
                  />
                ) : null}
                <div className={styles.dialogActions}>
                  <ActionButton icon="check" label="Create" disabled={busy || !createContext.mode || !createName.trim()} onClick={() => void submitCreate()} />
                  <ActionButton icon="x" label="Cancel" disabled={busy} onClick={() => setCreateContext(null)} />
                </div>
              </div>
            </div>,
            dialogRoot,
          )
        : null}

      {deleteTarget && dialogRoot
        ? createPortal(
            <div className={styles.dialogBackdrop} onMouseDown={() => !busy && setDeleteTarget(null)}>
              <div className={styles.dialogCard} role="dialog" aria-modal="true" onMouseDown={(event) => event.stopPropagation()}>
                <h3 className={styles.dialogTitle}>Delete Item</h3>
                <p className={styles.dialogBody}>
                  Delete <strong>{deleteTarget.name}</strong>? This cannot be undone from the browser.
                </p>
                <div className={styles.dialogActions}>
                  <ActionButton icon="trash" label="Delete" disabled={busy} onClick={() => void confirmDelete()} />
                  <ActionButton icon="x" label="Cancel" disabled={busy} onClick={() => setDeleteTarget(null)} />
                </div>
              </div>
            </div>,
            dialogRoot,
          )
        : null}
    </div>
  );
}
