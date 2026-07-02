import type {ReactNode} from 'react';

import {
  getAuthoringConnectionPresentation,
  type AuthoringConnectionFailure,
} from './runtimeDiscovery';

type AuthoringConnectionStatusCardProps = {
  status: AuthoringConnectionFailure;
  onRetry: () => void;
};

export default function AuthoringConnectionStatusCard({
  status,
  onRetry,
}: AuthoringConnectionStatusCardProps): ReactNode {
  const presentation = getAuthoringConnectionPresentation(status);

  return (
    <div>
      <h3>{presentation.title}</h3>
      <p>{presentation.summary}</p>
      <p>{presentation.nextAction}</p>
      {presentation.technicalDetails.length > 0 ? (
        <details>
          <summary>Technical details</summary>
          <dl>
            {presentation.technicalDetails.map((entry) => (
              <div key={entry.label}>
                <dt>{entry.label}</dt>
                <dd>{entry.value}</dd>
              </div>
            ))}
          </dl>
        </details>
      ) : null}
      <button className="button button--primary" type="button" onClick={onRetry}>
        Retry connection
      </button>
    </div>
  );
}
