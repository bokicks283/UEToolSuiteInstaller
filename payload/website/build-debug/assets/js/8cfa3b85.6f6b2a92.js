"use strict";
(globalThis["webpackChunkue_project_docs"] = globalThis["webpackChunkue_project_docs"] || []).push([[2125],{

/***/ 6001
(__unused_webpack_module, __webpack_exports__, __webpack_require__) {

// ESM COMPAT FLAG
__webpack_require__.r(__webpack_exports__);

// EXPORTS
__webpack_require__.d(__webpack_exports__, {
  assets: () => (/* binding */ assets),
  contentTitle: () => (/* binding */ contentTitle),
  "default": () => (/* binding */ MDXContent),
  frontMatter: () => (/* binding */ frontMatter),
  metadata: () => (/* reexport */ site_docs_workflow_standards_ai_readme_md_8cf_namespaceObject),
  toc: () => (/* binding */ toc)
});

;// ./.docusaurus/docusaurus-plugin-content-docs/default/site-docs-workflow-standards-ai-readme-md-8cf.json
const site_docs_workflow_standards_ai_readme_md_8cf_namespaceObject = /*#__PURE__*/JSON.parse('{"id":"WorkflowStandards/AI/README","title":"AI Context","description":"Use this section to give AI stable repo context without relying on old chat threads.","source":"@site/../Docs/WorkflowStandards/AI/README.md","sourceDirName":"WorkflowStandards/AI","slug":"/ai-context","permalink":"/docs/ai-context","draft":false,"unlisted":false,"tags":[],"version":"current","frontMatter":{"title":"AI Context","slug":"/ai-context"},"sidebar":"workflow-standards-sidebar","previous":{"title":"Docusaurus Setup","permalink":"/docs/docs-site/setup"},"next":{"title":"Shared vs Private Context","permalink":"/docs/ai-context/shared-vs-private"}}');
// EXTERNAL MODULE: ./node_modules/react/jsx-runtime.js
var jsx_runtime = __webpack_require__(4848);
// EXTERNAL MODULE: ./node_modules/@mdx-js/react/lib/index.js
var lib = __webpack_require__(8453);
;// ../Docs/WorkflowStandards/AI/README.md


const frontMatter = {
	title: 'AI Context',
	slug: '/ai-context'
};
const contentTitle = 'AI Context';

const assets = {

};



const toc = [{
  "value": "Goals",
  "id": "goals",
  "level": 2
}, {
  "value": "Read Order",
  "id": "read-order",
  "level": 2
}, {
  "value": "Structure",
  "id": "structure",
  "level": 2
}, {
  "value": "Starter Workflow",
  "id": "starter-workflow",
  "level": 2
}, {
  "value": "Command Examples",
  "id": "command-examples",
  "level": 2
}, {
  "value": "Automatic Loading Reality",
  "id": "automatic-loading-reality",
  "level": 2
}, {
  "value": "Example Opening Message",
  "id": "example-opening-message",
  "level": 2
}, {
  "value": "Later, Not Now",
  "id": "later-not-now",
  "level": 2
}];
function _createMdxContent(props) {
  const _components = {
    a: "a",
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
        id: "ai-context",
        children: "AI Context"
      })
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Use this section to give AI stable repo context without relying on old chat threads."
    }), "\n", (0,jsx_runtime.jsx)(_components.h2, {
      id: "goals",
      children: "Goals"
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "Shared repo context lives in tracked files."
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "Private user context stays local and untracked."
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: [(0,jsx_runtime.jsx)(_components.code, {
          children: "AGENTS.md"
        }), " stays short and points AI at the right docs."]
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "New chats should start by reading the repo docs, not by assuming old chat history still applies."
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.h2, {
      id: "read-order",
      children: "Read Order"
    }), "\n", (0,jsx_runtime.jsxs)(_components.ol, {
      children: ["\n", (0,jsx_runtime.jsx)(_components.li, {
        children: (0,jsx_runtime.jsx)(_components.a, {
          href: "/docs/ai-context/shared-vs-private",
          children: "Shared vs Private Context"
        })
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.h2, {
      id: "structure",
      children: "Structure"
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: [(0,jsx_runtime.jsx)(_components.code, {
          children: "AGENTS.md"
        }), ": short repo-wide instructions for AI"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: [(0,jsx_runtime.jsx)(_components.code, {
          children: "Docs/WorkflowStandards/AI/"
        }), ": shared, committed AI-facing docs"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: [(0,jsx_runtime.jsx)(_components.code, {
          children: ".ai-local/"
        }), ": local-only repo context for the current user"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: [(0,jsx_runtime.jsx)(_components.code, {
          children: "C:\\Users\\<user>\\.ai\\"
        }), ": global AI defaults across many repos"]
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.h2, {
      id: "starter-workflow",
      children: "Starter Workflow"
    }), "\n", (0,jsx_runtime.jsxs)(_components.ol, {
      children: ["\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "Start a new AI chat in the repo root."
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["Generate a startup prompt with ", (0,jsx_runtime.jsx)(_components.code, {
          children: "ue-tools ai prompt"
        }), " or ", (0,jsx_runtime.jsx)(_components.code, {
          children: "ue-tools ai prompt"
        }), "."]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["Let ", (0,jsx_runtime.jsx)(_components.code, {
          children: "AGENTS.md"
        }), " drive the startup read order across the repo docs."]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["Add a project-specific ", (0,jsx_runtime.jsx)(_components.code, {
          children: "Docs/WorkflowStandards/AI/Project-Context.md"
        }), " when you want an explicit shared brief in the prompt."]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["If you want local-only guidance included, also point AI at ", (0,jsx_runtime.jsx)(_components.code, {
          children: ".ai-local/Private-Context.md"
        }), "."]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["Keep durable decisions in ", (0,jsx_runtime.jsx)(_components.code, {
          children: "Docs/"
        }), ", not in chat history."]
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.h2, {
      id: "command-examples",
      children: "Command Examples"
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-powershell",
        children: "ue-tools ai help\nue-tools ai prompt -Task \"Fix UnrealSync regeneration output\"\nue-tools ai prompt -Task \"Review coding standards docs\" -IncludePrivate -CopyToClipboard\n"
      })
    }), "\n", (0,jsx_runtime.jsx)(_components.h2, {
      id: "automatic-loading-reality",
      children: "Automatic Loading Reality"
    }), "\n", (0,jsx_runtime.jsxs)(_components.p, {
      children: ["The repo can strongly instruct AI to read the docs at startup through ", (0,jsx_runtime.jsx)(_components.code, {
        children: "AGENTS.md"
      }), ", but the repo cannot hard-guarantee a platform-level preload of every document in every new chat."]
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Use this stack for the most reliable behavior:"
    }), "\n", (0,jsx_runtime.jsxs)(_components.ol, {
      children: ["\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: [(0,jsx_runtime.jsx)(_components.code, {
          children: "AGENTS.md"
        }), " tells AI to read the repo docs on startup."]
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "Your opening prompt names the highest-priority docs for the task."
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["Stable team knowledge stays in ", (0,jsx_runtime.jsx)(_components.code, {
          children: "Docs/"
        }), " so a fresh chat can re-read it."]
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.h2, {
      id: "example-opening-message",
      children: "Example Opening Message"
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-text",
        children: "Read AGENTS.md and the repo docs it points to.\nThen read Docs/WorkflowStandards/Testing.md and any project-specific context docs.\nAlso use .ai-local/Private-Context.md for my local preferences.\nThen help me update the Unreal tooling docs.\n"
      })
    }), "\n", (0,jsx_runtime.jsx)(_components.h2, {
      id: "later-not-now",
      children: "Later, Not Now"
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Custom AI skills can layer on top of this structure later. Get the shared docs and private local notes working first."
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