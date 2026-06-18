"use strict";
(globalThis["webpackChunkue_project_docs"] = globalThis["webpackChunkue_project_docs"] || []).push([[8774],{

/***/ 7556
(__unused_webpack_module, __webpack_exports__, __webpack_require__) {

// ESM COMPAT FLAG
__webpack_require__.r(__webpack_exports__);

// EXPORTS
__webpack_require__.d(__webpack_exports__, {
  assets: () => (/* binding */ assets),
  contentTitle: () => (/* binding */ contentTitle),
  "default": () => (/* binding */ MDXContent),
  frontMatter: () => (/* binding */ frontMatter),
  metadata: () => (/* reexport */ site_docs_workflow_standards_pipeline_readme_md_24b_namespaceObject),
  toc: () => (/* binding */ toc)
});

;// ./.docusaurus/docusaurus-plugin-content-docs/default/site-docs-workflow-standards-pipeline-readme-md-24b.json
const site_docs_workflow_standards_pipeline_readme_md_24b_namespaceObject = /*#__PURE__*/JSON.parse('{"id":"WorkflowStandards/Pipeline/README","title":"Workflow","description":"This is the required day-to-day workflow for normal project work.","source":"@site/../Docs/WorkflowStandards/Pipeline/README.md","sourceDirName":"WorkflowStandards/Pipeline","slug":"/workflow","permalink":"/docs/workflow","draft":false,"unlisted":false,"tags":[],"version":"current","frontMatter":{"title":"Workflow","slug":"/workflow"},"sidebar":"workflow-standards-sidebar","previous":{"title":"Setup","permalink":"/docs/setup"},"next":{"title":"Git Workflow Standards","permalink":"/docs/workflow/git-workflow-standards"}}');
// EXTERNAL MODULE: ./node_modules/react/jsx-runtime.js
var jsx_runtime = __webpack_require__(4848);
// EXTERNAL MODULE: ./node_modules/@mdx-js/react/lib/index.js
var lib = __webpack_require__(8453);
;// ../Docs/WorkflowStandards/Pipeline/README.md


const frontMatter = {
	title: 'Workflow',
	slug: '/workflow'
};
const contentTitle = 'Daily Workflow';

const assets = {

};



const toc = [{
  "value": "Required Practices",
  "id": "required-practices",
  "level": 2
}, {
  "value": "UE Sync Actions",
  "id": "ue-sync-actions",
  "level": 2
}, {
  "value": "Do Not",
  "id": "do-not",
  "level": 2
}, {
  "value": "Worked Example",
  "id": "worked-example",
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
        id: "daily-workflow",
        children: "Daily Workflow"
      })
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "This is the required day-to-day workflow for normal project work."
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Git-specific repo standards now live in one place:"
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsx)(_components.li, {
        children: (0,jsx_runtime.jsx)(_components.a, {
          href: "/docs/workflow/git-workflow-standards",
          children: "Git Workflow Standards"
        })
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Use that page for:"
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "branch naming"
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "rebasing and branch cleanup before review"
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "PR and merge policy"
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "guarded conflict handling"
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.h2, {
      id: "required-practices",
      children: "Required Practices"
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["Move ", (0,jsx_runtime.jsx)(_components.code, {
          children: ".uasset"
        }), " and ", (0,jsx_runtime.jsx)(_components.code, {
          children: ".umap"
        }), " files in Unreal Editor, not with filesystem tools."]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["Start fresh AI sessions with ", (0,jsx_runtime.jsx)(_components.code, {
          children: "ue-tools ai prompt"
        }), " when you want the repo docs and local context called out consistently."]
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "Run the relevant script tests before changing hook or automation behavior."
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["Let the automated ", (0,jsx_runtime.jsx)(_components.code, {
          children: "ue-sync"
        }), " hook decide whether a C++ branch switch needs a build, project-file regeneration, or both."]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["Use ", (0,jsx_runtime.jsx)(_components.code, {
          children: "ue-tools docs new-section"
        }), " and ", (0,jsx_runtime.jsx)(_components.code, {
          children: "ue-tools docs new-page"
        }), " for routine docs scaffolding."]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["Use ", (0,jsx_runtime.jsx)(_components.code, {
          children: "ue-tools docs reorder"
        }), " instead of hand-editing multiple sibling positions when docs nav order changes."]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["Run ", (0,jsx_runtime.jsx)(_components.code, {
          children: "ue-tools docs check"
        }), " before merging docs-structure or docs-site workflow changes."]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["Preview docs locally when editing navigation or structure-heavy pages with ", (0,jsx_runtime.jsx)(_components.code, {
          children: "ue-tools docs start"
        }), ", or ", (0,jsx_runtime.jsx)(_components.code, {
          children: "ue-tools docs start --background"
        }), " when you want detached tracked mode."]
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.h2, {
      id: "ue-sync-actions",
      children: "UE Sync Actions"
    }), "\n", (0,jsx_runtime.jsxs)(_components.p, {
      children: [(0,jsx_runtime.jsx)(_components.code, {
        children: "Scripts/UETools/UEToolSuite.Unreal.psm1"
      }), " separates project-file regeneration from editor builds so branch changes do only the work they need."]
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["Build only: modified existing C++ implementation/header files under ", (0,jsx_runtime.jsx)(_components.code, {
          children: "Source/"
        }), " or ", (0,jsx_runtime.jsx)(_components.code, {
          children: "Plugins/"
        }), "."]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["Regenerate project files and build: ", (0,jsx_runtime.jsx)(_components.code, {
          children: ".uproject"
        }), ", ", (0,jsx_runtime.jsx)(_components.code, {
          children: ".uplugin"
        }), ", ", (0,jsx_runtime.jsx)(_components.code, {
          children: "*.Build.cs"
        }), ", ", (0,jsx_runtime.jsx)(_components.code, {
          children: "*.Target.cs"
        }), ", or added/deleted/renamed C++ files under ", (0,jsx_runtime.jsx)(_components.code, {
          children: "Source/"
        }), " or ", (0,jsx_runtime.jsx)(_components.code, {
          children: "Plugins/"
        }), "."]
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "No UE sync action: docs, content, config, or other files that do not affect C++ build/project structure."
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsxs)(_components.p, {
      children: ["When a git hook invokes ", (0,jsx_runtime.jsx)(_components.code, {
        children: "ue-sync"
      }), ", it calculates that action plan from the changed files and can run build only, regeneration only, or regeneration plus build. Manual runs still support explicit control:"]
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-powershell",
        children: "ue-tools build -NoRegen\nue-tools build -NoBuild\nue-tools build -CleanGenerated -NoRegen -NoBuild\nue-tools build -NoBuild -NoRegen -DryRun\n"
      })
    }), "\n", (0,jsx_runtime.jsxs)(_components.p, {
      children: [(0,jsx_runtime.jsx)(_components.code, {
        children: "-CleanGenerated"
      }), " explicitly deletes ", (0,jsx_runtime.jsx)(_components.code, {
        children: "Binaries/"
      }), " and ", (0,jsx_runtime.jsx)(_components.code, {
        children: "Intermediate/"
      }), ". Use it for a manual cleanup-only pass or when you want a build-only run to start from clean generated folders. Hook-triggered build-only runs skip that cleanup by default."]
    }), "\n", (0,jsx_runtime.jsxs)(_components.p, {
      children: ["Project-file regeneration is allowed to rewrite VS Code workspace artifacts. After regeneration, ", (0,jsx_runtime.jsx)(_components.code, {
        children: "ue-sync"
      }), " preserves user-owned VS Code workspace customization by merging previous extra folders, ", (0,jsx_runtime.jsx)(_components.code, {
        children: "settings"
      }), ", extension recommendations, custom tasks, and custom launch configurations back into the generated ", (0,jsx_runtime.jsx)(_components.code, {
        children: ".code-workspace"
      }), ". It also restores the pre-regen ", (0,jsx_runtime.jsx)(_components.code, {
        children: ".ignore"
      }), " content when that file existed before regeneration, which prevents Unreal-generated ", (0,jsx_runtime.jsx)(_components.code, {
        children: ".ignore"
      }), " churn from appearing as a tracked git change."]
    }), "\n", (0,jsx_runtime.jsx)(_components.h2, {
      id: "do-not",
      children: "Do Not"
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "Mix large content migrations with unrelated gameplay work."
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "Treat Confluence as the live source of truth for this project."
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.h2, {
      id: "worked-example",
      children: "Worked Example"
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Goal: move Unreal assets under a new content folder and document the policy change."
    }), "\n", (0,jsx_runtime.jsxs)(_components.ol, {
      children: ["\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["Create a correctly named branch using ", (0,jsx_runtime.jsx)(_components.a, {
          href: "/docs/workflow/git-workflow-standards",
          children: "Git Workflow Standards"
        }), "."]
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "Move the assets in Unreal Editor."
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "Fix redirectors in the moved folder."
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "Update the project structure docs if the canonical layout changed."
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "Run the relevant smoke test in editor."
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "Commit only the moved assets and docs updates."
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