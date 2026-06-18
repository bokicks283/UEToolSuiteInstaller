"use strict";
(globalThis["webpackChunkue_project_docs"] = globalThis["webpackChunkue_project_docs"] || []).push([[3128],{

/***/ 6839
(__unused_webpack_module, __webpack_exports__, __webpack_require__) {

// ESM COMPAT FLAG
__webpack_require__.r(__webpack_exports__);

// EXPORTS
__webpack_require__.d(__webpack_exports__, {
  assets: () => (/* binding */ assets),
  contentTitle: () => (/* binding */ contentTitle),
  "default": () => (/* binding */ MDXContent),
  frontMatter: () => (/* binding */ frontMatter),
  metadata: () => (/* reexport */ site_docs_workflow_standards_testing_md_a45_namespaceObject),
  toc: () => (/* binding */ toc)
});

;// ./.docusaurus/docusaurus-plugin-content-docs/default/site-docs-workflow-standards-testing-md-a45.json
const site_docs_workflow_standards_testing_md_a45_namespaceObject = /*#__PURE__*/JSON.parse('{"id":"WorkflowStandards/Testing","title":"Testing","description":"The transferred automation is only useful if it can be revalidated after future repo moves or script changes. Keep this suite green.","source":"@site/../Docs/WorkflowStandards/Testing.md","sourceDirName":"WorkflowStandards","slug":"/testing","permalink":"/docs/testing","draft":false,"unlisted":false,"tags":[],"version":"current","sidebarPosition":4,"frontMatter":{"title":"Testing","sidebar_position":4,"slug":"/testing"},"sidebar":"workflow-standards-sidebar","previous":{"title":"Unreal C++ Coding Standard (UE 5.7)","permalink":"/docs/coding-standards/unreal-cpp-standard"},"next":{"title":"Docs Site","permalink":"/docs/docs-site"}}');
// EXTERNAL MODULE: ./node_modules/react/jsx-runtime.js
var jsx_runtime = __webpack_require__(4848);
// EXTERNAL MODULE: ./node_modules/@mdx-js/react/lib/index.js
var lib = __webpack_require__(8453);
;// ../Docs/WorkflowStandards/Testing.md


const frontMatter = {
	title: 'Testing',
	sidebar_position: 4,
	slug: '/testing'
};
const contentTitle = 'Tooling And Workflow Tests';

const assets = {

};



const toc = [{
  "value": "Preferred Entrypoint",
  "id": "preferred-entrypoint",
  "level": 2
}, {
  "value": "Recommended Order",
  "id": "recommended-order",
  "level": 2
}, {
  "value": "What Each Test Covers",
  "id": "what-each-test-covers",
  "level": 2
}, {
  "value": "Master Runner",
  "id": "master-runner",
  "level": 2
}, {
  "value": "Adding Tests",
  "id": "adding-tests",
  "level": 2
}, {
  "value": "Preconditions",
  "id": "preconditions",
  "level": 2
}, {
  "value": "Crash-Capture Tools",
  "id": "crash-capture-tools",
  "level": 2
}, {
  "value": "Manual Validation Helper",
  "id": "manual-validation-helper",
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
    ul: "ul",
    ...(0,lib/* useMDXComponents */.R)(),
    ...props.components
  };
  return (0,jsx_runtime.jsxs)(jsx_runtime.Fragment, {
    children: [(0,jsx_runtime.jsx)(_components.header, {
      children: (0,jsx_runtime.jsx)(_components.h1, {
        id: "tooling-and-workflow-tests",
        children: "Tooling And Workflow Tests"
      })
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "The transferred automation is only useful if it can be revalidated after future repo moves or script changes. Keep this suite green."
    }), "\n", (0,jsx_runtime.jsx)(_components.h2, {
      id: "preferred-entrypoint",
      children: "Preferred Entrypoint"
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsx)(_components.li, {
        children: (0,jsx_runtime.jsx)(_components.code, {
          children: "pwsh -NoProfile -ExecutionPolicy Bypass -File Scripts/Tests/Run-AllTests.ps1"
        })
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "The master runner executes tests serially on purpose. Some tests create branches, reset the repo, or otherwise require exclusive access to the working tree, so the suite is not parallel-safe in a live repo."
    }), "\n", (0,jsx_runtime.jsx)(_components.h2, {
      id: "recommended-order",
      children: "Recommended Order"
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsx)(_components.li, {
        children: (0,jsx_runtime.jsx)(_components.code, {
          children: "pwsh -NoProfile -ExecutionPolicy Bypass -File Scripts/git-hooks/Test-Hooks.ps1"
        })
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: (0,jsx_runtime.jsx)(_components.code, {
          children: "pwsh -NoProfile -ExecutionPolicy Bypass -File Scripts/Tests/Test-UESyncShellAliases.ps1"
        })
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: (0,jsx_runtime.jsx)(_components.code, {
          children: "pwsh -NoProfile -ExecutionPolicy Bypass -File Scripts/Tests/Test-DocsTools.ps1"
        })
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: (0,jsx_runtime.jsx)(_components.code, {
          children: "pwsh -NoProfile -ExecutionPolicy Bypass -File Scripts/Tests/Test-AIStartupPrompt.ps1"
        })
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: (0,jsx_runtime.jsx)(_components.code, {
          children: "pwsh -NoProfile -ExecutionPolicy Bypass -File Scripts/Tests/Test-UnrealSync-Regeneration.ps1"
        })
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: (0,jsx_runtime.jsx)(_components.code, {
          children: "pwsh -NoProfile -ExecutionPolicy Bypass -File Scripts/Tests/Test-InitRepoToolReadiness.ps1"
        })
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: (0,jsx_runtime.jsx)(_components.code, {
          children: "pwsh -NoProfile -ExecutionPolicy Bypass -File Scripts/Tests/Test-New-ArtSourcePath.ps1"
        })
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: (0,jsx_runtime.jsx)(_components.code, {
          children: "pwsh -NoProfile -ExecutionPolicy Bypass -File Scripts/Tests/Test-UnrealSync.ps1"
        })
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: (0,jsx_runtime.jsx)(_components.code, {
          children: "pwsh -NoProfile -ExecutionPolicy Bypass -File Scripts/Tests/Test-BinaryGuard-Fixes.ps1"
        })
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.h2, {
      id: "what-each-test-covers",
      children: "What Each Test Covers"
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: [(0,jsx_runtime.jsx)(_components.code, {
          children: "Test-Hooks.ps1"
        }), ": validates committed hook plumbing, ", (0,jsx_runtime.jsx)(_components.code, {
          children: "core.hooksPath"
        }), ", git helper aliases, and Git Bash sourcing."]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: [(0,jsx_runtime.jsx)(_components.code, {
          children: "Test-UESyncShellAliases.ps1"
        }), ": validates ", (0,jsx_runtime.jsx)(_components.code, {
          children: "ue-tools"
        }), " and ", (0,jsx_runtime.jsx)(_components.code, {
          children: "ue"
        }), " alias bootstrap behavior."]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: [(0,jsx_runtime.jsx)(_components.code, {
          children: "Test-DocsTools.ps1"
        }), ": validates ", (0,jsx_runtime.jsx)(_components.code, {
          children: "ue-tools docs"
        }), " scaffolding, optional VS Code bridge install flow, TOC request queuing, and docs-site validation behavior."]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: [(0,jsx_runtime.jsx)(_components.code, {
          children: "Test-AIStartupPrompt.ps1"
        }), ": validates the AI startup prompt builder output and local private-context handling."]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: [(0,jsx_runtime.jsx)(_components.code, {
          children: "Test-UnrealSync-Regeneration.ps1"
        }), ": validates project-file regeneration, action-plan decisions, workspace artifact preservation, and engine-resolution fallback paths in isolation. One case intentionally forces an unresolved-engine failure and should still end in a green summary."]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: [(0,jsx_runtime.jsx)(_components.code, {
          children: "Test-InitRepoToolReadiness.ps1"
        }), ": validates ", (0,jsx_runtime.jsx)(_components.code, {
          children: "ue-tools init"
        }), " optional tool prerequisite setup and readiness reporting in a scratch UE project repo."]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: [(0,jsx_runtime.jsx)(_components.code, {
          children: "Test-New-ArtSourcePath.ps1"
        }), ": validates canonical ", (0,jsx_runtime.jsx)(_components.code, {
          children: "ArtSource/_Template"
        }), " handling and new asset folder creation."]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: [(0,jsx_runtime.jsx)(_components.code, {
          children: "Test-UnrealSync.ps1"
        }), ": validates structural trigger detection and hook/non-interactive behavior on a committed clean repo."]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: [(0,jsx_runtime.jsx)(_components.code, {
          children: "Test-BinaryGuard-Fixes.ps1"
        }), ": validates guarded binary conflict helpers across merge and rebase flows."]
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.h2, {
      id: "master-runner",
      children: "Master Runner"
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: [(0,jsx_runtime.jsx)(_components.code, {
          children: "Run-AllTests.ps1"
        }), " reads ", (0,jsx_runtime.jsx)(_components.code, {
          children: "Scripts/Tests/TestManifest.ps1"
        }), " and launches each selected test in a fresh ", (0,jsx_runtime.jsx)(_components.code, {
          children: "pwsh"
        }), " process."]
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "Default behavior is serial execution of the automated suite."
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "Tests that require a clean repo or existing commits are skipped with an explicit reason instead of being forced to run unsafely."
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["Child test output is streamed directly to the console so native ", (0,jsx_runtime.jsx)(_components.code, {
          children: "Write-Host"
        }), " colors and normal script formatting are preserved."]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["Use ", (0,jsx_runtime.jsx)(_components.code, {
          children: "-List"
        }), " to inspect the manifest-backed catalog."]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["Use ", (0,jsx_runtime.jsx)(_components.code, {
          children: "-Name"
        }), " or ", (0,jsx_runtime.jsx)(_components.code, {
          children: "-Category"
        }), " to run a subset, for example ", (0,jsx_runtime.jsx)(_components.code, {
          children: "-Category unreal"
        }), "."]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: [(0,jsx_runtime.jsx)(_components.code, {
          children: "-NoCleanup"
        }), " and ", (0,jsx_runtime.jsx)(_components.code, {
          children: "-FailFast"
        }), " are forwarded only to scripts that support those switches."]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["Use ", (0,jsx_runtime.jsx)(_components.code, {
          children: "-WriteJson"
        }), " when you want the runner to emit a machine-readable JSON summary alongside the suite log."]
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.h2, {
      id: "adding-tests",
      children: "Adding Tests"
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["Add the new automated test script under ", (0,jsx_runtime.jsx)(_components.code, {
          children: "Scripts/Tests/"
        }), "."]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["Add one entry to ", (0,jsx_runtime.jsx)(_components.code, {
          children: "Scripts/Tests/TestManifest.ps1"
        }), " with its path, category, and repo-safety metadata."]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["Keep repo-mutating tests marked with ", (0,jsx_runtime.jsx)(_components.code, {
          children: "RequiresCleanRepo"
        }), ", ", (0,jsx_runtime.jsx)(_components.code, {
          children: "RequiresCommits"
        }), ", and ", (0,jsx_runtime.jsx)(_components.code, {
          children: "MutatesRepo"
        }), " so the runner can serialize and gate them correctly."]
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "Keep manual helpers and operational scripts out of the default automated manifest unless they are safe for unattended runs."
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.h2, {
      id: "preconditions",
      children: "Preconditions"
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: [(0,jsx_runtime.jsx)(_components.code, {
          children: "Test-UnrealSync.ps1"
        }), " and ", (0,jsx_runtime.jsx)(_components.code, {
          children: "Test-BinaryGuard-Fixes.ps1"
        }), " require a clean repo with at least one commit."]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: [(0,jsx_runtime.jsx)(_components.code, {
          children: "Run-AllTests.ps1"
        }), " will skip those tests automatically when the repo is dirty or has no commits."]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["Tests write logs under ", (0,jsx_runtime.jsx)(_components.code, {
          children: "Scripts/Tests/*Results/"
        }), "."]
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "Crash-capture scripts are opt-in operational tools, not part of the normal quick suite."
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.h2, {
      id: "crash-capture-tools",
      children: "Crash-Capture Tools"
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: [(0,jsx_runtime.jsx)(_components.code, {
          children: "Collect-CrashEvidence.ps1"
        }), ": bundles Unreal logs, crash folders, event logs, and system metadata."]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: [(0,jsx_runtime.jsx)(_components.code, {
          children: "Run-CrashCaptureSession.ps1"
        }), ": launches the editor and arms a post-crash collection flow."]
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.h2, {
      id: "manual-validation-helper",
      children: "Manual Validation Helper"
    }), "\n", (0,jsx_runtime.jsxs)(_components.p, {
      children: ["Use ", (0,jsx_runtime.jsx)(_components.code, {
        children: "Scripts/Tests/Test-Setup-UESync-Manual.ps1"
      }), " when you want a disposable branch that introduces a structural C++ change to manually exercise the ", (0,jsx_runtime.jsx)(_components.code, {
        children: "post-checkout"
      }), " Unreal sync hook. Run it only from a clean working tree."]
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