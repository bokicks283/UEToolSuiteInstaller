import type {AuthoringConnectionFailure, AuthoringConnectionStatus} from './runtimeDiscovery';

export type DocPageAuthoringState = {
  sourceToken: string;
  sourceTokenValid: boolean;
  pageIsEditable: boolean;
  pageSupportsVisibility: boolean;
  pageSupportsAuthoringUi: boolean;
  authoringAvailable: boolean;
  pageCanManageVisibility: boolean;
  showConnectionNotice: boolean;
  connectionFailure: AuthoringConnectionFailure | null;
};

type GetDocPageAuthoringStateOptions = {
  sourceToken: string;
  runtimeReady: boolean;
  runtimeAvailable: boolean;
  connectionStatus: AuthoringConnectionStatus;
};

export function getDocPageAuthoringState({
  sourceToken,
  runtimeReady,
  runtimeAvailable,
  connectionStatus,
}: GetDocPageAuthoringStateOptions): DocPageAuthoringState {
  const normalizedSourceToken = (sourceToken || '').trim();
  const lowerSourceToken = normalizedSourceToken.toLowerCase();
  const sourceTokenValid = normalizedSourceToken.length > 0;
  const pageIsEditable = lowerSourceToken.endsWith('.md');
  const pageSupportsVisibility = sourceTokenValid && !lowerSourceToken.endsWith('/_category_.json');
  const pageSupportsAuthoringUi = pageIsEditable || pageSupportsVisibility;
  const authoringAvailable = runtimeReady && runtimeAvailable;
  const pageCanManageVisibility = authoringAvailable && pageSupportsVisibility;
  const connectionFailure =
    connectionStatus.kind === 'checking' || connectionStatus.kind === 'connected'
      ? null
      : connectionStatus;
  const showConnectionNotice =
    !!connectionFailure && runtimeReady && !runtimeAvailable && pageSupportsAuthoringUi;

  return {
    sourceToken: normalizedSourceToken,
    sourceTokenValid,
    pageIsEditable,
    pageSupportsVisibility,
    pageSupportsAuthoringUi,
    authoringAvailable,
    pageCanManageVisibility,
    showConnectionNotice,
    connectionFailure,
  };
}
