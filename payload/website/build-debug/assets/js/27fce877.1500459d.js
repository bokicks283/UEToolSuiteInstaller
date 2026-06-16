"use strict";
(globalThis["webpackChunkue_project_docs"] = globalThis["webpackChunkue_project_docs"] || []).push([[8862],{

/***/ 7686
(__unused_webpack_module, __webpack_exports__, __webpack_require__) {

// ESM COMPAT FLAG
__webpack_require__.r(__webpack_exports__);

// EXPORTS
__webpack_require__.d(__webpack_exports__, {
  assets: () => (/* binding */ assets),
  contentTitle: () => (/* binding */ contentTitle),
  "default": () => (/* binding */ MDXContent),
  frontMatter: () => (/* binding */ frontMatter),
  metadata: () => (/* reexport */ site_docs_workflow_standards_ai_shared_vs_private_md_27f_namespaceObject),
  toc: () => (/* binding */ toc)
});

;// ./.docusaurus/docusaurus-plugin-content-docs/default/site-docs-workflow-standards-ai-shared-vs-private-md-27f.json
const site_docs_workflow_standards_ai_shared_vs_private_md_27f_namespaceObject = /*#__PURE__*/JSON.parse('{"id":"WorkflowStandards/AI/Shared-vs-Private","title":"Shared vs Private Context","description":"Use the following split.","source":"@site/../Docs/WorkflowStandards/AI/Shared-vs-Private.md","sourceDirName":"WorkflowStandards/AI","slug":"/ai-context/shared-vs-private","permalink":"/docs/ai-context/shared-vs-private","draft":false,"unlisted":false,"tags":[],"version":"current","frontMatter":{"title":"Shared vs Private Context","slug":"/ai-context/shared-vs-private"},"sidebar":"workflow-standards-sidebar","previous":{"title":"AI Context","permalink":"/docs/ai-context"}}');
// EXTERNAL MODULE: ./node_modules/react/jsx-runtime.js
var jsx_runtime = __webpack_require__(4848);
// EXTERNAL MODULE: ./node_modules/@mdx-js/react/lib/index.js
var lib = __webpack_require__(8453);
;// ../Docs/WorkflowStandards/AI/Shared-vs-Private.md


const frontMatter = {
	title: 'Shared vs Private Context',
	slug: '/ai-context/shared-vs-private'
};
const contentTitle = 'Shared vs Private Context';

const assets = {

};



const toc = [{
  "value": "Shared, Committed, Team-Visible",
  "id": "shared-committed-team-visible",
  "level": 2
}, {
  "value": "Private, Local, Not Committed",
  "id": "private-local-not-committed",
  "level": 2
}, {
  "value": "Quick Guide",
  "id": "quick-guide",
  "level": 2
}, {
  "value": "Example Shared Note",
  "id": "example-shared-note",
  "level": 2
}, {
  "value": "Example Private Note",
  "id": "example-private-note",
  "level": 2
}, {
  "value": "Safety Notes",
  "id": "safety-notes",
  "level": 2
}];
function _createMdxContent(props) {
  const _components = {
    code: "code",
    h1: "h1",
    h2: "h2",
    header: "header",
    li: "li",
    p: "p",
    pre: "pre",
    table: "table",
    tbody: "tbody",
    td: "td",
    th: "th",
    thead: "thead",
    tr: "tr",
    ul: "ul",
    ...(0,lib/* useMDXComponents */.R)(),
    ...props.components
  };
  return (0,jsx_runtime.jsxs)(jsx_runtime.Fragment, {
    children: [(0,jsx_runtime.jsx)(_components.header, {
      children: (0,jsx_runtime.jsx)(_components.h1, {
        id: "shared-vs-private-context",
        children: "Shared vs Private Context"
      })
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Use the following split."
    }), "\n", (0,jsx_runtime.jsx)(_components.h2, {
      id: "shared-committed-team-visible",
      children: "Shared, Committed, Team-Visible"
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: [(0,jsx_runtime.jsx)(_components.code, {
          children: "AGENTS.md"
        }), "\nUse for short repo instructions and pointers."]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: [(0,jsx_runtime.jsx)(_components.code, {
          children: "Docs/WorkflowStandards/AI/"
        }), "\nUse for AI-facing project context, examples, and workflow guidance."]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["The rest of ", (0,jsx_runtime.jsx)(_components.code, {
          children: "Docs/"
        }), "\nUse for the actual project rules, setup, testing, architecture, and process docs."]
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.h2, {
      id: "private-local-not-committed",
      children: "Private, Local, Not Committed"
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: [(0,jsx_runtime.jsx)(_components.code, {
          children: ".ai-local/"
        }), "\nUse for repo-specific personal notes, prompt starters, and preferences that should stay on one machine."]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: [(0,jsx_runtime.jsx)(_components.code, {
          children: "C:\\Users\\<user>\\.ai\\"
        }), "\nUse for global personal defaults that should apply across many repos."]
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.h2, {
      id: "quick-guide",
      children: "Quick Guide"
    }), "\n", (0,jsx_runtime.jsxs)(_components.table, {
      children: [(0,jsx_runtime.jsx)(_components.thead, {
        children: (0,jsx_runtime.jsxs)(_components.tr, {
          children: [(0,jsx_runtime.jsx)(_components.th, {
            children: "Location"
          }), (0,jsx_runtime.jsx)(_components.th, {
            children: "Shared?"
          }), (0,jsx_runtime.jsx)(_components.th, {
            children: "Good for"
          }), (0,jsx_runtime.jsx)(_components.th, {
            children: "Avoid"
          })]
        })
      }), (0,jsx_runtime.jsxs)(_components.tbody, {
        children: [(0,jsx_runtime.jsxs)(_components.tr, {
          children: [(0,jsx_runtime.jsx)(_components.td, {
            children: (0,jsx_runtime.jsx)(_components.code, {
              children: "AGENTS.md"
            })
          }), (0,jsx_runtime.jsx)(_components.td, {
            children: "Yes"
          }), (0,jsx_runtime.jsx)(_components.td, {
            children: "Short instructions and doc pointers"
          }), (0,jsx_runtime.jsx)(_components.td, {
            children: "Long design docs"
          })]
        }), (0,jsx_runtime.jsxs)(_components.tr, {
          children: [(0,jsx_runtime.jsx)(_components.td, {
            children: (0,jsx_runtime.jsx)(_components.code, {
              children: "Docs/WorkflowStandards/AI/"
            })
          }), (0,jsx_runtime.jsx)(_components.td, {
            children: "Yes"
          }), (0,jsx_runtime.jsx)(_components.td, {
            children: "Stable AI-facing repo context"
          }), (0,jsx_runtime.jsx)(_components.td, {
            children: "Temporary personal notes"
          })]
        }), (0,jsx_runtime.jsxs)(_components.tr, {
          children: [(0,jsx_runtime.jsx)(_components.td, {
            children: (0,jsx_runtime.jsx)(_components.code, {
              children: ".ai-local/"
            })
          }), (0,jsx_runtime.jsx)(_components.td, {
            children: "No"
          }), (0,jsx_runtime.jsx)(_components.td, {
            children: "Personal repo notes and private prompt snippets"
          }), (0,jsx_runtime.jsx)(_components.td, {
            children: "Secrets or huge scratchpads"
          })]
        }), (0,jsx_runtime.jsxs)(_components.tr, {
          children: [(0,jsx_runtime.jsx)(_components.td, {
            children: (0,jsx_runtime.jsx)(_components.code, {
              children: "C:\\Users\\<user>\\.ai\\"
            })
          }), (0,jsx_runtime.jsx)(_components.td, {
            children: "No"
          }), (0,jsx_runtime.jsx)(_components.td, {
            children: "Global defaults, skills, and rules"
          }), (0,jsx_runtime.jsx)(_components.td, {
            children: "Repo-specific team docs"
          })]
        })]
      })]
    }), "\n", (0,jsx_runtime.jsx)(_components.h2, {
      id: "example-shared-note",
      children: "Example Shared Note"
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-md",
        children: "## Unreal Tooling\n- Use Scripts/Tests/Run-AllTests.ps1 as the default test runner.\n- Read Docs/WorkflowStandards/Testing.md before running branch-mutating tests.\n"
      })
    }), "\n", (0,jsx_runtime.jsx)(_components.h2, {
      id: "example-private-note",
      children: "Example Private Note"
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-md",
        children: "## My Working Preferences\n- When I ask for test changes, start with the serial master runner.\n- Call out branch-mutating scripts before you run them.\n- Prefer docs updates in the same change when tooling behavior changes.\n"
      })
    }), "\n", (0,jsx_runtime.jsx)(_components.h2, {
      id: "safety-notes",
      children: "Safety Notes"
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["Do not store tokens, passwords, or secrets in ", (0,jsx_runtime.jsx)(_components.code, {
          children: ".ai-local/"
        }), "."]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["If a private note becomes team policy, move it into ", (0,jsx_runtime.jsx)(_components.code, {
          children: "Docs/"
        }), "."]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["If a shared doc becomes too long, split it instead of bloating ", (0,jsx_runtime.jsx)(_components.code, {
          children: "AGENTS.md"
        }), "."]
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