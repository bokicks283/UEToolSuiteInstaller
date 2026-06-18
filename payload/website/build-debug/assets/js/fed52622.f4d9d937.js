"use strict";
(globalThis["webpackChunkue_project_docs"] = globalThis["webpackChunkue_project_docs"] || []).push([[8377],{

/***/ 1831
(__unused_webpack_module, __webpack_exports__, __webpack_require__) {

// ESM COMPAT FLAG
__webpack_require__.r(__webpack_exports__);

// EXPORTS
__webpack_require__.d(__webpack_exports__, {
  assets: () => (/* binding */ assets),
  contentTitle: () => (/* binding */ contentTitle),
  "default": () => (/* binding */ MDXContent),
  frontMatter: () => (/* binding */ frontMatter),
  metadata: () => (/* reexport */ site_docs_workflow_standards_coding_standards_readme_md_fed_namespaceObject),
  toc: () => (/* binding */ toc)
});

;// ./.docusaurus/docusaurus-plugin-content-docs/default/site-docs-workflow-standards-coding-standards-readme-md-fed.json
const site_docs_workflow_standards_coding_standards_readme_md_fed_namespaceObject = /*#__PURE__*/JSON.parse('{"id":"WorkflowStandards/CodingStandards/README","title":"Coding Standards","description":"This project follows Epic\'s Unreal C++ coding standard at all times.","source":"@site/../Docs/WorkflowStandards/CodingStandards/README.md","sourceDirName":"WorkflowStandards/CodingStandards","slug":"/coding-standards","permalink":"/docs/coding-standards","draft":false,"unlisted":false,"tags":[],"version":"current","frontMatter":{"title":"Coding Standards","slug":"/coding-standards"},"sidebar":"workflow-standards-sidebar","previous":{"title":"Git Workflow Standards","permalink":"/docs/workflow/git-workflow-standards"},"next":{"title":"Unreal C++ Coding Standard (UE 5.7)","permalink":"/docs/coding-standards/unreal-cpp-standard"}}');
// EXTERNAL MODULE: ./node_modules/react/jsx-runtime.js
var jsx_runtime = __webpack_require__(4848);
// EXTERNAL MODULE: ./node_modules/@mdx-js/react/lib/index.js
var lib = __webpack_require__(8453);
;// ../Docs/WorkflowStandards/CodingStandards/README.md


const frontMatter = {
	title: 'Coding Standards',
	slug: '/coding-standards'
};
const contentTitle = 'Unreal C++ Coding Standards';

const assets = {

};



const toc = [{
  "value": "Folder Purpose",
  "id": "folder-purpose",
  "level": 2
}, {
  "value": "Required Layout",
  "id": "required-layout",
  "level": 2
}, {
  "value": "Best Way To Bring The Full Web Page Into Repo",
  "id": "best-way-to-bring-the-full-web-page-into-repo",
  "level": 2
}, {
  "value": "Snapshot Workflow (Exact)",
  "id": "snapshot-workflow-exact",
  "level": 2
}, {
  "value": "Update Frequency",
  "id": "update-frequency",
  "level": 2
}, {
  "value": "AI Usage",
  "id": "ai-usage",
  "level": 2
}, {
  "value": "Concrete Usage Example",
  "id": "concrete-usage-example",
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
        id: "unreal-c-coding-standards",
        children: "Unreal C++ Coding Standards"
      })
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "This project follows Epic's Unreal C++ coding standard at all times."
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Source of truth:"
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsx)(_components.li, {
        children: (0,jsx_runtime.jsx)(_components.a, {
          href: "https://dev.epicgames.com/documentation/en-us/unreal-engine/epic-cplusplus-coding-standard-for-unreal-engine",
          children: "https://dev.epicgames.com/documentation/en-us/unreal-engine/epic-cplusplus-coding-standard-for-unreal-engine"
        })
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.h2, {
      id: "folder-purpose",
      children: "Folder Purpose"
    }), "\n", (0,jsx_runtime.jsxs)(_components.p, {
      children: [(0,jsx_runtime.jsx)(_components.code, {
        children: "Docs/WorkflowStandards/CodingStandards/"
      }), " stores local snapshots and team-facing implementation notes for the official standard."]
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Use this folder so teammates can review the exact coding-standard source used at the time of a change."
    }), "\n", (0,jsx_runtime.jsxs)(_components.p, {
      children: ["The readable in-repo standard page lives at ", (0,jsx_runtime.jsx)(_components.code, {
        children: "Docs/WorkflowStandards/CodingStandards/UnrealCppStandard.md"
      }), ". Hidden capture metadata stays under ", (0,jsx_runtime.jsx)(_components.code, {
        children: "Docs/WorkflowStandards/CodingStandards/Current/"
      }), "."]
    }), "\n", (0,jsx_runtime.jsx)(_components.h2, {
      id: "required-layout",
      children: "Required Layout"
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-text",
        children: "Docs/WorkflowStandards/CodingStandards/\n|- README.md\n|- UnrealCppStandard.md\n|- Sync-UnrealCppStandard.ps1\n|- Parse-UnrealCppStandard.ps1\n|- Templates/\n|  |- SOURCE.template.md\n|- Current/\n|  |- page.html\n|  |- SOURCE.md\n"
      })
    }), "\n", (0,jsx_runtime.jsx)(_components.h2, {
      id: "best-way-to-bring-the-full-web-page-into-repo",
      children: "Best Way To Bring The Full Web Page Into Repo"
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Use a raw HTML snapshot from the official Epic page, then keep metadata with it."
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Why this is best:"
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "Captures the full source page, not partial summaries."
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "Makes reviews deterministic when the web page changes later."
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "Avoids manual copy/paste drift."
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.h2, {
      id: "snapshot-workflow-exact",
      children: "Snapshot Workflow (Exact)"
    }), "\n", (0,jsx_runtime.jsxs)(_components.ol, {
      children: ["\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["Run:", "\n", (0,jsx_runtime.jsxs)(_components.ul, {
          children: ["\n", (0,jsx_runtime.jsx)(_components.li, {
            children: (0,jsx_runtime.jsx)(_components.code, {
              children: "pwsh -File Docs/WorkflowStandards/CodingStandards/Sync-UnrealCppStandard.ps1"
            })
          }), "\n"]
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["This refreshes:", "\n", (0,jsx_runtime.jsxs)(_components.ul, {
          children: ["\n", (0,jsx_runtime.jsx)(_components.li, {
            children: (0,jsx_runtime.jsx)(_components.code, {
              children: "Docs/WorkflowStandards/CodingStandards/Current/page.html"
            })
          }), "\n", (0,jsx_runtime.jsx)(_components.li, {
            children: (0,jsx_runtime.jsx)(_components.code, {
              children: "Docs/WorkflowStandards/CodingStandards/Current/SOURCE.md"
            })
          }), "\n"]
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["Fill all placeholders in ", (0,jsx_runtime.jsx)(_components.code, {
          children: "Docs/WorkflowStandards/CodingStandards/Current/SOURCE.md"
        }), "."]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["Parse the current snapshot into the readable docs page:", "\n", (0,jsx_runtime.jsxs)(_components.ul, {
          children: ["\n", (0,jsx_runtime.jsx)(_components.li, {
            children: (0,jsx_runtime.jsx)(_components.code, {
              children: "pwsh -File Docs/WorkflowStandards/CodingStandards/Parse-UnrealCppStandard.ps1"
            })
          }), "\n"]
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["This rewrites:", "\n", (0,jsx_runtime.jsxs)(_components.ul, {
          children: ["\n", (0,jsx_runtime.jsx)(_components.li, {
            children: (0,jsx_runtime.jsx)(_components.code, {
              children: "Docs/WorkflowStandards/CodingStandards/UnrealCppStandard.md"
            })
          }), "\n"]
        }), "\n"]
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "Commit the refreshed current snapshot + docs page in a docs-only commit."
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.h2, {
      id: "update-frequency",
      children: "Update Frequency"
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Refresh coding-standard snapshot:"
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "When upgrading Unreal engine version."
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "When Epic updates the coding-standard page."
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "At least once per quarter while active development is ongoing."
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "At minimum, treat the snapshot as stale once it is older than six months and refresh it before relying on it as the current local reference."
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.h2, {
      id: "ai-usage",
      children: "AI Usage"
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["Agents should scrutinize ", (0,jsx_runtime.jsx)(_components.code, {
          children: "Docs/WorkflowStandards/CodingStandards/"
        }), " thoroughly before C++ or style-sensitive work."]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["Start with this file, then inspect ", (0,jsx_runtime.jsx)(_components.code, {
          children: "Docs/WorkflowStandards/CodingStandards/UnrealCppStandard.md"
        }), "."]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["Use ", (0,jsx_runtime.jsx)(_components.code, {
          children: "Docs/WorkflowStandards/CodingStandards/Current/SOURCE.md"
        }), " for hidden capture metadata and ", (0,jsx_runtime.jsx)(_components.code, {
          children: "Docs/WorkflowStandards/CodingStandards/Current/page.html"
        }), " for the exact raw source page."]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["If the snapshot date in ", (0,jsx_runtime.jsx)(_components.code, {
          children: "Docs/WorkflowStandards/CodingStandards/Current/SOURCE.md"
        }), " is older than six months:", "\n", (0,jsx_runtime.jsxs)(_components.ol, {
          children: ["\n", (0,jsx_runtime.jsxs)(_components.li, {
            children: ["Run ", (0,jsx_runtime.jsx)(_components.code, {
              children: "pwsh -File Docs/WorkflowStandards/CodingStandards/Sync-UnrealCppStandard.ps1"
            })]
          }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
            children: ["Update ", (0,jsx_runtime.jsx)(_components.code, {
              children: "Docs/WorkflowStandards/CodingStandards/Current/SOURCE.md"
            })]
          }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
            children: ["Run ", (0,jsx_runtime.jsx)(_components.code, {
              children: "pwsh -File Docs/WorkflowStandards/CodingStandards/Parse-UnrealCppStandard.ps1"
            })]
          }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
            children: ["Commit the refreshed current snapshot and ", (0,jsx_runtime.jsx)(_components.code, {
              children: "Docs/WorkflowStandards/CodingStandards/UnrealCppStandard.md"
            }), " in docs scope"]
          }), "\n"]
        }), "\n"]
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.h2, {
      id: "concrete-usage-example",
      children: "Concrete Usage Example"
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Scenario: teammate introduces new class naming that is questioned in review."
    }), "\n", (0,jsx_runtime.jsxs)(_components.ol, {
      children: ["\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["Reviewer opens ", (0,jsx_runtime.jsx)(_components.code, {
          children: "Docs/WorkflowStandards/CodingStandards/Current/"
        }), "."]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["Reviewer checks official guidance in ", (0,jsx_runtime.jsx)(_components.code, {
          children: "page.html"
        }), "."]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["Reviewer references snapshot date and source URL from ", (0,jsx_runtime.jsx)(_components.code, {
          children: "SOURCE.md"
        }), "."]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["Reviewer and author use ", (0,jsx_runtime.jsx)(_components.code, {
          children: "Docs/WorkflowStandards/CodingStandards/UnrealCppStandard.md"
        }), " as the readable in-repo reference during discussion."]
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "Team aligns code to standard and merges with traceable rationale."
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