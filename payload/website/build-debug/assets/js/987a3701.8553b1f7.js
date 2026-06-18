"use strict";
(globalThis["webpackChunkue_project_docs"] = globalThis["webpackChunkue_project_docs"] || []).push([[5311],{

/***/ 2204
(__unused_webpack_module, __webpack_exports__, __webpack_require__) {

// ESM COMPAT FLAG
__webpack_require__.r(__webpack_exports__);

// EXPORTS
__webpack_require__.d(__webpack_exports__, {
  assets: () => (/* binding */ assets),
  contentTitle: () => (/* binding */ contentTitle),
  "default": () => (/* binding */ MDXContent),
  frontMatter: () => (/* binding */ frontMatter),
  metadata: () => (/* reexport */ site_docs_workflow_standards_setup_md_987_namespaceObject),
  toc: () => (/* binding */ toc)
});

;// ./.docusaurus/docusaurus-plugin-content-docs/default/site-docs-workflow-standards-setup-md-987.json
const site_docs_workflow_standards_setup_md_987_namespaceObject = /*#__PURE__*/JSON.parse('{"id":"WorkflowStandards/Setup","title":"Setup","description":"Use this flow when bootstrapping a fresh clone or when moving the repo to a new machine.","source":"@site/../Docs/WorkflowStandards/Setup.md","sourceDirName":"WorkflowStandards","slug":"/setup","permalink":"/docs/setup","draft":false,"unlisted":false,"tags":[],"version":"current","sidebarPosition":1,"frontMatter":{"title":"Setup","sidebar_position":1,"slug":"/setup"},"sidebar":"workflow-standards-sidebar","previous":{"title":"Workflow And Standards","permalink":"/docs/workflow-standards"},"next":{"title":"Workflow","permalink":"/docs/workflow"}}');
// EXTERNAL MODULE: ./node_modules/react/jsx-runtime.js
var jsx_runtime = __webpack_require__(4848);
// EXTERNAL MODULE: ./node_modules/@mdx-js/react/lib/index.js
var lib = __webpack_require__(8453);
;// ../Docs/WorkflowStandards/Setup.md


const frontMatter = {
	title: 'Setup',
	sidebar_position: 1,
	slug: '/setup'
};
const contentTitle = 'Project Setup';

const assets = {

};



const toc = [{
  "value": "Required Tools",
  "id": "required-tools",
  "level": 2
}, {
  "value": "First-Run Flow",
  "id": "first-run-flow",
  "level": 2
}, {
  "value": "Engine Discovery Rules",
  "id": "engine-discovery-rules",
  "level": 2
}, {
  "value": "Recommended Variants",
  "id": "recommended-variants",
  "level": 2
}, {
  "value": "UE Sync Behavior",
  "id": "ue-sync-behavior",
  "level": 2
}, {
  "value": "Tool Suite Updates",
  "id": "tool-suite-updates",
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
        id: "project-setup",
        children: "Project Setup"
      })
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Use this flow when bootstrapping a fresh clone or when moving the repo to a new machine."
    }), "\n", (0,jsx_runtime.jsx)(_components.h2, {
      id: "required-tools",
      children: "Required Tools"
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "Unreal Engine 5.x"
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "Git for Windows"
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "Git LFS"
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "PowerShell 7+"
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "Node.js 20+ and npm for the docs site"
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.h2, {
      id: "first-run-flow",
      children: "First-Run Flow"
    }), "\n", (0,jsx_runtime.jsxs)(_components.ol, {
      children: ["\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "Open PowerShell in the repo root."
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "Run:"
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-powershell",
        children: "pwsh -NoProfile -ExecutionPolicy Bypass -File Scripts/ue-tools.ps1 init\n"
      })
    }), "\n", (0,jsx_runtime.jsxs)(_components.ol, {
      start: "3",
      children: ["\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["Open the project ", (0,jsx_runtime.jsx)(_components.code, {
          children: ".uproject"
        }), " and let Unreal regenerate local workspace data if needed."]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["If the repo was moved, verify the ", (0,jsx_runtime.jsx)(_components.code, {
          children: ".code-workspace"
        }), " file points at the current repo root and local engine install."]
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "Start the docs site when you need a local preview:"
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-powershell",
        children: "ue-tools docs start\n"
      })
    }), "\n", (0,jsx_runtime.jsxs)(_components.p, {
      children: [(0,jsx_runtime.jsx)(_components.code, {
        children: "ue-tools init"
      }), " prepares installed optional tool prerequisites during first-run setup. When ", (0,jsx_runtime.jsx)(_components.code, {
        children: "website/package.json"
      }), " is present, it verifies Node.js 20+ and npm, runs ", (0,jsx_runtime.jsx)(_components.code, {
        children: "npm install"
      }), " if ", (0,jsx_runtime.jsx)(_components.code, {
        children: "website/node_modules"
      }), " is missing, installs the optional docs VS Code bridge when the ", (0,jsx_runtime.jsx)(_components.code, {
        children: "code"
      }), " CLI is available, and runs ", (0,jsx_runtime.jsx)(_components.code, {
        children: "ue-tools docs doctor"
      }), "."]
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Init also handles repository bootstrap safety:"
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["If the target folder is not a git repo, ", (0,jsx_runtime.jsx)(_components.code, {
          children: "ue-tools init -NonInteractive"
        }), " runs ", (0,jsx_runtime.jsx)(_components.code, {
          children: "git init"
        }), " automatically."]
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "Newly ignored tracked files are untracked from the git index by default (local files are kept)."
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["In non-interactive mode this untrack step runs automatically unless ", (0,jsx_runtime.jsx)(_components.code, {
          children: "-SkipIgnoredUntrack"
        }), " is passed."]
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsxs)(_components.p, {
      children: ["After init installs project shell aliases, open a new PowerShell session or reload the profile path printed by the script before using commands like ", (0,jsx_runtime.jsx)(_components.code, {
        children: "ue-tools"
      }), ", ", (0,jsx_runtime.jsx)(_components.code, {
        children: "ue-tools art"
      }), ", ", (0,jsx_runtime.jsx)(_components.code, {
        children: "ue-tools docs"
      }), ", or ", (0,jsx_runtime.jsx)(_components.code, {
        children: "ue-tools ai prompt"
      }), "."]
    }), "\n", (0,jsx_runtime.jsxs)(_components.p, {
      children: ["The Docusaurus site is already set up in ", (0,jsx_runtime.jsx)(_components.code, {
        children: "website/"
      }), ". You do not need to create a new site scaffold for this repo. See ", (0,jsx_runtime.jsx)(_components.a, {
        href: "/docs/docs-site/setup",
        children: "Docusaurus Setup"
      }), " for the edit/preview/build workflow."]
    }), "\n", (0,jsx_runtime.jsxs)(_components.p, {
      children: [(0,jsx_runtime.jsx)(_components.code, {
        children: "ue-tools docs start"
      }), " now stays attached to the current terminal so you can see live server output. If you want the old detached tracked mode instead, run ", (0,jsx_runtime.jsx)(_components.code, {
        children: "ue-tools docs start --background"
      }), "."]
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "When you are done with the tracked background docs server:"
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-powershell",
        children: "ue-tools docs stop\n"
      })
    }), "\n", (0,jsx_runtime.jsxs)(_components.p, {
      children: ["If ", (0,jsx_runtime.jsx)(_components.code, {
        children: "ue-tools init"
      }), " skipped the bridge because the ", (0,jsx_runtime.jsx)(_components.code, {
        children: "code"
      }), " CLI was unavailable, or if you want to rerun the install manually:"]
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-powershell",
        children: "ue-tools docs help\nue-tools docs install-bridge\n"
      })
    }), "\n", (0,jsx_runtime.jsxs)(_components.p, {
      children: [(0,jsx_runtime.jsx)(_components.code, {
        children: "ue-tools docs install-bridge"
      }), " is optional. It only enables table-of-contents generation for new pages and sections when ", (0,jsx_runtime.jsx)(_components.code, {
        children: "Markdown All in One"
      }), " is also installed in VS Code."]
    }), "\n", (0,jsx_runtime.jsx)(_components.h2, {
      id: "engine-discovery-rules",
      children: "Engine Discovery Rules"
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "The shared Unreal tooling resolves the engine in this order:"
    }), "\n", (0,jsx_runtime.jsxs)(_components.ol, {
      children: ["\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["The local ", (0,jsx_runtime.jsx)(_components.code, {
          children: ".code-workspace"
        }), " UE folder"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: [(0,jsx_runtime.jsx)(_components.code, {
          children: "UE_ENGINE_DIR"
        }), ", ", (0,jsx_runtime.jsx)(_components.code, {
          children: "UE_ENGINE_ROOT"
        }), ", or ", (0,jsx_runtime.jsx)(_components.code, {
          children: "UNREAL_ENGINE_DIR"
        })]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["Registry lookup from ", (0,jsx_runtime.jsx)(_components.code, {
          children: "EngineAssociation"
        })]
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "EngineAssociation-specific folders under common UE install roots"
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["Installed ", (0,jsx_runtime.jsx)(_components.code, {
          children: "UE_*"
        }), " folders under common UE install roots"]
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsxs)(_components.p, {
      children: ["Set ", (0,jsx_runtime.jsx)(_components.code, {
        children: "UE_ENGINE_COMMON_INSTALL_ROOTS"
      }), " to a semicolon-separated list when this machine uses nonstandard Epic Games install roots. If automated Unreal tooling cannot find the engine, fix one of those sources instead of hardcoding project-specific paths."]
    }), "\n", (0,jsx_runtime.jsx)(_components.h2, {
      id: "recommended-variants",
      children: "Recommended Variants"
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["Use ", (0,jsx_runtime.jsx)(_components.code, {
          children: "-NoBuild"
        }), " when you only want hooks, aliases, and repo config without a first build."]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["Use ", (0,jsx_runtime.jsx)(_components.code, {
          children: "-SkipUnrealSync"
        }), " when the local engine path is not resolved yet."]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["Use ", (0,jsx_runtime.jsx)(_components.code, {
          children: "-NonInteractive"
        }), " for CI/automated first-run setup. This mode applies safe defaults and automatically untracks newly ignored tracked files."]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["Use ", (0,jsx_runtime.jsx)(_components.code, {
          children: "-SkipIgnoredUntrack"
        }), " only when you intentionally want newly ignored tracked files to remain tracked."]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["Use ", (0,jsx_runtime.jsx)(_components.code, {
          children: "-SkipShellAliases"
        }), " on CI or any environment where PowerShell profiles should remain untouched."]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["Use ", (0,jsx_runtime.jsx)(_components.code, {
          children: "-SkipOptionalToolSetup"
        }), " when you want only the core git/hook/Unreal bootstrap without optional tool prerequisite work."]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["Use ", (0,jsx_runtime.jsx)(_components.code, {
          children: "-SkipDocsSetup"
        }), ", ", (0,jsx_runtime.jsx)(_components.code, {
          children: "-SkipDocsNpmInstall"
        }), ", ", (0,jsx_runtime.jsx)(_components.code, {
          children: "-ForceDocsNpmInstall"
        }), ", or ", (0,jsx_runtime.jsx)(_components.code, {
          children: "-SkipDocsBridgeInstall"
        }), " to control the docs-specific setup steps."]
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.h2, {
      id: "ue-sync-behavior",
      children: "UE Sync Behavior"
    }), "\n", (0,jsx_runtime.jsxs)(_components.p, {
      children: ["The git-hook ", (0,jsx_runtime.jsx)(_components.code, {
        children: "ue-sync"
      }), " workflow decides between build and project-file regeneration based on the changed files:"]
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "Modified existing C++ files build the editor without regenerating project files."
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: [(0,jsx_runtime.jsx)(_components.code, {
          children: ".uproject"
        }), ", ", (0,jsx_runtime.jsx)(_components.code, {
          children: ".uplugin"
        }), ", ", (0,jsx_runtime.jsx)(_components.code, {
          children: "*.Build.cs"
        }), ", ", (0,jsx_runtime.jsx)(_components.code, {
          children: "*.Target.cs"
        }), ", and added/deleted/renamed C++ files regenerate project files and then build."]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["Build-only hook runs skip ", (0,jsx_runtime.jsx)(_components.code, {
          children: "Binaries/"
        }), " and ", (0,jsx_runtime.jsx)(_components.code, {
          children: "Intermediate/"
        }), " cleanup by default; use ", (0,jsx_runtime.jsx)(_components.code, {
          children: "ue-tools build -CleanGenerated -NoRegen -NoBuild"
        }), " for a manual cleanup-only pass."]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["Project-file regeneration preserves user VS Code workspace customization and restores pre-regen ", (0,jsx_runtime.jsx)(_components.code, {
          children: ".ignore"
        }), " content so Unreal-generated churn does not keep dirtying tracked files."]
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.h2, {
      id: "tool-suite-updates",
      children: "Tool Suite Updates"
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Use the standalone UE tool suite installer repo to install or update these tools in a project. Installer/updater logic should stay outside this project; this repo should contain only the usable tools and docs payload."
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