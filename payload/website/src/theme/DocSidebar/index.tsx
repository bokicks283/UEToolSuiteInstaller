import React from 'react';
import OriginalDocSidebar from '@theme-original/DocSidebar';
import type {Props} from '@theme/DocSidebar';

export default function DocSidebarWrapper(props: Props): React.JSX.Element {
  return <OriginalDocSidebar {...props} />;
}
