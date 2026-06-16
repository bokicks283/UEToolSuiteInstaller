"use strict";
(globalThis["webpackChunkue_project_docs"] = globalThis["webpackChunkue_project_docs"] || []).push([[824],{

/***/ 8390
(__unused_webpack_module, __webpack_exports__, __webpack_require__) {

// ESM COMPAT FLAG
__webpack_require__.r(__webpack_exports__);

// EXPORTS
__webpack_require__.d(__webpack_exports__, {
  assets: () => (/* binding */ assets),
  contentTitle: () => (/* binding */ contentTitle),
  "default": () => (/* binding */ MDXContent),
  frontMatter: () => (/* binding */ frontMatter),
  metadata: () => (/* reexport */ site_docs_workflow_standards_docs_site_docusaurus_setup_md_089_namespaceObject),
  toc: () => (/* binding */ toc)
});

;// ./.docusaurus/docusaurus-plugin-content-docs/default/site-docs-workflow-standards-docs-site-docusaurus-setup-md-089.json
const site_docs_workflow_standards_docs_site_docusaurus_setup_md_089_namespaceObject = /*#__PURE__*/JSON.parse('{"id":"WorkflowStandards/DocsSite/Docusaurus-Setup","title":"Docusaurus Setup","description":"This project publishes repo docs through Docusaurus.","source":"@site/../Docs/WorkflowStandards/DocsSite/Docusaurus-Setup.md","sourceDirName":"WorkflowStandards/DocsSite","slug":"/docs-site/setup","permalink":"/docs/docs-site/setup","draft":false,"unlisted":false,"tags":[],"version":"current","frontMatter":{"title":"Docusaurus Setup","slug":"/docs-site/setup"},"sidebar":"workflow-standards-sidebar","previous":{"title":"Authoring Docs","permalink":"/docs/docs-site/authoring"},"next":{"title":"AI Context","permalink":"/docs/ai-context"}}');
// EXTERNAL MODULE: ./node_modules/react/jsx-runtime.js
var jsx_runtime = __webpack_require__(4848);
// EXTERNAL MODULE: ./node_modules/@mdx-js/react/lib/index.js
var lib = __webpack_require__(8453);
;// ../Docs/WorkflowStandards/DocsSite/Docusaurus-Setup.md


const frontMatter = {
	title: 'Docusaurus Setup',
	slug: '/docs-site/setup'
};
const contentTitle = 'Docusaurus Setup';

const assets = {

};



const toc = [{
  "value": "Source Of Truth",
  "id": "source-of-truth",
  "level": 2
}, {
  "value": "One-Time Local Setup",
  "id": "one-time-local-setup",
  "level": 2
}, {
  "value": "Daily Preview Workflow",
  "id": "daily-preview-workflow",
  "level": 2
}, {
  "value": "What To Edit",
  "id": "what-to-edit",
  "level": 2
}, {
  "value": "Production Build Check",
  "id": "production-build-check",
  "level": 2
}, {
  "value": "Other Docusaurus Commands",
  "id": "other-docusaurus-commands",
  "level": 2
}, {
  "value": "Current Wiring",
  "id": "current-wiring",
  "level": 2
}, {
  "value": "Optional VS Code TOC Bridge",
  "id": "optional-vs-code-toc-bridge",
  "level": 2
}, {
  "value": "Theme And Branding Updates",
  "id": "theme-and-branding-updates",
  "level": 2
}, {
  "value": "Deployment Notes",
  "id": "deployment-notes",
  "level": 2
}, {
  "value": "When To Update The Site App",
  "id": "when-to-update-the-site-app",
  "level": 2
}, {
  "value": "Common Mistakes",
  "id": "common-mistakes",
  "level": 2
}];
function _createMdxContent(props) {
  const _components = {
    code: "code",
    h1: "h1",
    h2: "h2",
    header: "header",
    li: "li",
    ol: "ol",
    p: "p",
    pre: "pre",
    ul: "ul",
    ...(0,lib/* useMDXComponents */.R)(),
    ...props.components
  };
  return (0,jsx_runtime.jsxs)(jsx_runtime.Fragment, {
    children: [(0,jsx_runtime.jsx)(_components.header, {
      children: (0,jsx_runtime.jsx)(_components.h1, {
        id: "docusaurus-setup",
        children: "Docusaurus Setup"
      })
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "This project publishes repo docs through Docusaurus."
    }), "\n", (0,jsx_runtime.jsxs)(_components.p, {
      children: ["You do not need to scaffold a new Docusaurus site for this repo. The site already exists in ", (0,jsx_runtime.jsx)(_components.code, {
        children: "website/"
      }), " and is wired to render the markdown in ", (0,jsx_runtime.jsx)(_components.code, {
        children: "Docs/"
      }), "."]
    }), "\n", (0,jsx_runtime.jsx)(_components.h2, {
      id: "source-of-truth",
      children: "Source Of Truth"
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["Source markdown: ", (0,jsx_runtime.jsx)(_components.code, {
          children: "Docs/"
        })]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["Docusaurus app: ", (0,jsx_runtime.jsx)(_components.code, {
          children: "website/"
        })]
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsxs)(_components.p, {
      children: ["Do not author long-form project docs in ", (0,jsx_runtime.jsx)(_components.code, {
        children: "website/docs"
      }), ". That scaffold is intentionally unused here."]
    }), "\n", (0,jsx_runtime.jsx)(_components.h2, {
      id: "one-time-local-setup",
      children: "One-Time Local Setup"
    }), "\n", (0,jsx_runtime.jsxs)(_components.ol, {
      children: ["\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "Make sure Node.js 20+ and npm are installed."
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "Open PowerShell in the repo root."
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "Run:"
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-powershell",
        children: "Set-Location website\nnpm install\n"
      })
    }), "\n", (0,jsx_runtime.jsxs)(_components.p, {
      children: ["That installs the Docusaurus app dependencies only. Your actual docs still live in ", (0,jsx_runtime.jsx)(_components.code, {
        children: "../Docs"
      }), "."]
    }), "\n", (0,jsx_runtime.jsx)(_components.h2, {
      id: "daily-preview-workflow",
      children: "Daily Preview Workflow"
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Run:"
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-powershell",
        children: "ue-tools docs start\n"
      })
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Then open:"
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-text",
        children: "http://localhost:3000/docs/\n"
      })
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "What happens next:"
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "Docusaurus starts a local dev server attached to the current terminal."
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["Editing files in ", (0,jsx_runtime.jsx)(_components.code, {
          children: "Docs/"
        }), " updates the site preview."]
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "You see live stdout/stderr directly in that terminal."
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsxs)(_components.p, {
      children: ["When you are running in the attached mode, stop it with normal terminal interruption such as ", (0,jsx_runtime.jsx)(_components.code, {
        children: "Ctrl+C"
      }), "."]
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "If you want the old tracked detached mode instead, run:"
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-powershell",
        children: "ue-tools docs start --background\n"
      })
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Stop the tracked background dev server with:"
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-powershell",
        children: "ue-tools docs stop\n"
      })
    }), "\n", (0,jsx_runtime.jsxs)(_components.p, {
      children: [(0,jsx_runtime.jsx)(_components.code, {
        children: "ue-tools docs start"
      }), " is the repo-local wrapper around ", (0,jsx_runtime.jsx)(_components.code, {
        children: "website/"
      }), "'s ", (0,jsx_runtime.jsx)(_components.code, {
        children: "npm start"
      }), ". By default it stays attached so you can watch the server logs. Use ", (0,jsx_runtime.jsx)(_components.code, {
        children: "--background"
      }), " when you want a detached tracked server instead."]
    }), "\n", (0,jsx_runtime.jsxs)(_components.p, {
      children: ["Use ", (0,jsx_runtime.jsx)(_components.code, {
        children: "ue-tools docs status"
      }), " to see whether the tracked background server is still running and where its logs are. Use ", (0,jsx_runtime.jsx)(_components.code, {
        children: "ue-tools docs doctor"
      }), " if the local docs workflow feels broken and you want a quick prerequisite check."]
    }), "\n", (0,jsx_runtime.jsx)(_components.h2, {
      id: "what-to-edit",
      children: "What To Edit"
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["Edit page content in ", (0,jsx_runtime.jsx)(_components.code, {
          children: "Docs/"
        }), "."]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["Create ordinary pages and sections with ", (0,jsx_runtime.jsx)(_components.code, {
          children: "ue-tools docs new-page"
        }), " and ", (0,jsx_runtime.jsx)(_components.code, {
          children: "ue-tools docs new-section"
        }), "."]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["Control sidebar order with ", (0,jsx_runtime.jsx)(_components.code, {
          children: "sidebar_position"
        }), " on docs and ", (0,jsx_runtime.jsx)(_components.code, {
          children: "_category_.json"
        }), " metadata on folders."]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["Treat ", (0,jsx_runtime.jsx)(_components.code, {
          children: "_category_.json"
        }), " as the section marker; a section README is optional."]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["Reorder existing pages and sections with ", (0,jsx_runtime.jsx)(_components.code, {
          children: "ue-tools docs reorder <TargetPath> <Position>"
        }), "."]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["If you omit ", (0,jsx_runtime.jsx)(_components.code, {
          children: "-Position"
        }), ", ", (0,jsx_runtime.jsx)(_components.code, {
          children: "ue-tools docs"
        }), " assigns the next available position automatically."]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["Only touch ", (0,jsx_runtime.jsx)(_components.code, {
          children: "website/sidebars.ts"
        }), " when the autogenerated docs shell itself needs to change."]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["Change site-wide branding, footer, navbar, or deploy metadata in ", (0,jsx_runtime.jsx)(_components.code, {
          children: "website/docusaurus.config.ts"
        }), "."]
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.h2, {
      id: "production-build-check",
      children: "Production Build Check"
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Use this before merging docs-navigation changes or site-config changes:"
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-powershell",
        children: "ue-tools docs check\n"
      })
    }), "\n", (0,jsx_runtime.jsxs)(_components.p, {
      children: [(0,jsx_runtime.jsx)(_components.code, {
        children: "ue-tools docs check"
      }), " validates docs metadata, catches common docs-site mistakes, and then runs the Docusaurus production build. If you specifically want the raw website commands, ", (0,jsx_runtime.jsx)(_components.code, {
        children: "ue-tools docs build"
      }), " wraps ", (0,jsx_runtime.jsx)(_components.code, {
        children: "npm run build"
      }), "."]
    }), "\n", (0,jsx_runtime.jsx)(_components.h2, {
      id: "other-docusaurus-commands",
      children: "Other Docusaurus Commands"
    }), "\n", (0,jsx_runtime.jsxs)(_components.p, {
      children: [(0,jsx_runtime.jsx)(_components.code, {
        children: "ue-tools docs"
      }), " forwards the ", (0,jsx_runtime.jsx)(_components.code, {
        children: "website/package.json"
      }), " scripts directly, so these all work from the repo root:"]
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-powershell",
        children: "ue-tools docs build\nue-tools docs clear\nue-tools docs deploy\nue-tools docs serve\nue-tools docs swizzle\nue-tools docs write-translations\nue-tools docs write-heading-ids\nue-tools docs typecheck\nue-tools docs docusaurus <args...>\n"
      })
    }), "\n", (0,jsx_runtime.jsx)(_components.h2, {
      id: "current-wiring",
      children: "Current Wiring"
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["The Docusaurus docs plugin reads from ", (0,jsx_runtime.jsx)(_components.code, {
          children: "../Docs"
        }), "."]
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "Blog output is disabled."
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["Coding-standard ", (0,jsx_runtime.jsx)(_components.code, {
          children: "Current/"
        }), " and ", (0,jsx_runtime.jsx)(_components.code, {
          children: "Templates/"
        }), " are excluded from the site build."]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: [(0,jsx_runtime.jsx)(_components.code, {
          children: "website/sidebars.ts"
        }), " delegates to autogenerated navigation rooted at ", (0,jsx_runtime.jsx)(_components.code, {
          children: "Docs/"
        }), "."]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["Section ordering comes from ", (0,jsx_runtime.jsx)(_components.code, {
          children: "_category_.json"
        }), " and page ordering comes from doc front matter."]
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.h2, {
      id: "optional-vs-code-toc-bridge",
      children: "Optional VS Code TOC Bridge"
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "If you want new pages and sections to start with a generated table of contents:"
    }), "\n", (0,jsx_runtime.jsxs)(_components.ol, {
      children: ["\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["Install the VS Code extension ", (0,jsx_runtime.jsx)(_components.code, {
          children: "Markdown All in One"
        }), "."]
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "Run:"
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-powershell",
        children: "ue-tools docs install-bridge\n"
      })
    }), "\n", (0,jsx_runtime.jsxs)(_components.p, {
      children: ["After that, ", (0,jsx_runtime.jsx)(_components.code, {
        children: "ue-tools docs new-page"
      }), " and ", (0,jsx_runtime.jsx)(_components.code, {
        children: "ue-tools docs new-section"
      }), " will queue Markdown All in One's ", (0,jsx_runtime.jsx)(_components.code, {
        children: "Create Table of Contents"
      }), " command through the local bridge extension. If either dependency is missing, ", (0,jsx_runtime.jsx)(_components.code, {
        children: "ue-tools docs"
      }), " falls back to plain scaffolding and skips TOC generation."]
    }), "\n", (0,jsx_runtime.jsx)(_components.h2, {
      id: "theme-and-branding-updates",
      children: "Theme And Branding Updates"
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "List available presets:"
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-powershell",
        children: "ue-tools docs theme list\n"
      })
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Available preset IDs:"
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        children: "neutral, graphite, ocean, forest, amber, violet, cobalt, teal, jade, indigo, crimson, rose, copper, slate"
      })
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Apply a preset and optional logo:"
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-powershell",
        children: "ue-tools docs theme apply neutral\nue-tools docs theme apply ocean -LogoPath C:\\Path\\ProjectLogo.svg\n"
      })
    }), "\n", (0,jsx_runtime.jsxs)(_components.p, {
      children: [(0,jsx_runtime.jsx)(_components.code, {
        children: "ue-tools docs theme apply"
      }), " updates:"]
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsx)(_components.li, {
        children: (0,jsx_runtime.jsx)(_components.code, {
          children: "website/src/css/custom.css"
        })
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: [(0,jsx_runtime.jsx)(_components.code, {
          children: "website/docusaurus.config.ts"
        }), " branding fields (", (0,jsx_runtime.jsx)(_components.code, {
          children: "title"
        }), ", ", (0,jsx_runtime.jsx)(_components.code, {
          children: "favicon"
        }), ", navbar title/logo, ", (0,jsx_runtime.jsx)(_components.code, {
          children: "themeConfig.image"
        }), ", suite custom fields)"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: [(0,jsx_runtime.jsx)(_components.code, {
          children: "website/.ue-tools/ownership.json"
        }), " management marker"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["If ", (0,jsx_runtime.jsx)(_components.code, {
          children: "-LogoPath"
        }), " is provided, the same custom asset is wired to navbar logo, favicon, and social card image."]
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Preserve-first behavior for existing sites:"
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "Managed site: theme apply runs immediately."
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "Unmanaged site: theme apply is blocked by default to preserve existing design."
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "To intentionally take over an existing site, adopt first:"
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-powershell",
        children: "ue-tools docs theme apply neutral --adopt-existing\n"
      })
    }), "\n", (0,jsx_runtime.jsx)(_components.h2, {
      id: "deployment-notes",
      children: "Deployment Notes"
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["Update ", (0,jsx_runtime.jsx)(_components.code, {
          children: "website/docusaurus.config.ts"
        }), " ", (0,jsx_runtime.jsx)(_components.code, {
          children: "url"
        }), " and repository metadata before a real deployment target is chosen."]
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "Keep docs deployment separate from gameplay feature branches when possible."
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["Validate ", (0,jsx_runtime.jsx)(_components.code, {
          children: "npm run build"
        }), " before merging navigation changes."]
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.h2, {
      id: "when-to-update-the-site-app",
      children: "When To Update The Site App"
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "Changing global navigation"
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "Adjusting theme, branding, or footer content"
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "Changing deploy metadata or base URL"
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "Changing how the autogenerated docs shell works"
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.h2, {
      id: "common-mistakes",
      children: "Common Mistakes"
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["Do not write the real project docs under ", (0,jsx_runtime.jsx)(_components.code, {
          children: "website/docs"
        }), "."]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["Do not edit ", (0,jsx_runtime.jsx)(_components.code, {
          children: "website/.docusaurus/"
        }), ", ", (0,jsx_runtime.jsx)(_components.code, {
          children: "website/build/"
        }), ", or ", (0,jsx_runtime.jsx)(_components.code, {
          children: "website/node_modules/"
        }), "."]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["If a new doc page exists but does not show in navigation, check ", (0,jsx_runtime.jsx)(_components.code, {
          children: "_category_.json"
        }), ", ", (0,jsx_runtime.jsx)(_components.code, {
          children: "sidebar_position"
        }), ", and the folder location under ", (0,jsx_runtime.jsx)(_components.code, {
          children: "Docs/"
        }), "."]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["If the build fails on links, fix the markdown links in ", (0,jsx_runtime.jsx)(_components.code, {
          children: "Docs/"
        }), " rather than weakening the Docusaurus checks."]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["If ", (0,jsx_runtime.jsx)(_components.code, {
          children: "ue-tools docs check"
        }), " reports an unprocessed TOC marker, either install the optional bridge workflow or remove the marker and author the TOC manually."]
      }), "\n"]
    })]
  });
}
function MDXContent(props = {}) {
  const {wrapper: MDXLayout} = {
    ...(0,lib/* useMDXComponents */.R)(),
    ...props.components
  };
  return MDXLayout ? (0,jsx_runtime.jsx)(MDXLayout, {
    ...props,
    children: (0,jsx_runtime.jsx)(_createMdxContent, {
      ...props
    })
  }) : _createMdxContent(props);
}



/***/ }

}]);