"use strict";
(globalThis["webpackChunkue_project_docs"] = globalThis["webpackChunkue_project_docs"] || []).push([[9533],{

/***/ 2058
(__unused_webpack_module, __webpack_exports__, __webpack_require__) {

// ESM COMPAT FLAG
__webpack_require__.r(__webpack_exports__);

// EXPORTS
__webpack_require__.d(__webpack_exports__, {
  assets: () => (/* binding */ assets),
  contentTitle: () => (/* binding */ contentTitle),
  "default": () => (/* binding */ MDXContent),
  frontMatter: () => (/* binding */ frontMatter),
  metadata: () => (/* reexport */ site_docs_workflow_standards_pipeline_git_branch_and_pr_workflow_md_9c4_namespaceObject),
  toc: () => (/* binding */ toc)
});

;// ./.docusaurus/docusaurus-plugin-content-docs/default/site-docs-workflow-standards-pipeline-git-branch-and-pr-workflow-md-9c4.json
const site_docs_workflow_standards_pipeline_git_branch_and_pr_workflow_md_9c4_namespaceObject = /*#__PURE__*/JSON.parse('{"id":"WorkflowStandards/Pipeline/Git-Branch-And-PR-Workflow","title":"Git Workflow Standards","description":"This page is the source of truth for repo git standards:","source":"@site/../Docs/WorkflowStandards/Pipeline/Git-Branch-And-PR-Workflow.md","sourceDirName":"WorkflowStandards/Pipeline","slug":"/workflow/git-workflow-standards","permalink":"/docs/workflow/git-workflow-standards","draft":false,"unlisted":false,"tags":[],"version":"current","sidebarPosition":2,"frontMatter":{"title":"Git Workflow Standards","sidebar_position":2,"slug":"/workflow/git-workflow-standards"},"sidebar":"workflow-standards-sidebar","previous":{"title":"Workflow","permalink":"/docs/workflow"},"next":{"title":"Coding Standards","permalink":"/docs/coding-standards"}}');
// EXTERNAL MODULE: ./node_modules/react/jsx-runtime.js
var jsx_runtime = __webpack_require__(4848);
// EXTERNAL MODULE: ./node_modules/@mdx-js/react/lib/index.js
var lib = __webpack_require__(8453);
;// ../Docs/WorkflowStandards/Pipeline/Git-Branch-And-PR-Workflow.md


const frontMatter = {
	title: 'Git Workflow Standards',
	sidebar_position: 2,
	slug: '/workflow/git-workflow-standards'
};
const contentTitle = 'Git Workflow Standards';

const assets = {

};



const toc = [{
  "value": "Goals",
  "id": "goals",
  "level": 2
}, {
  "value": "Branch Naming",
  "id": "branch-naming",
  "level": 2
}, {
  "value": "Start-Of-Day Sync",
  "id": "start-of-day-sync",
  "level": 2
}, {
  "value": "Required Git Practices",
  "id": "required-git-practices",
  "level": 2
}, {
  "value": "Do Not",
  "id": "do-not",
  "level": 2
}, {
  "value": "Required Branch Cleanup And PR Flow",
  "id": "required-branch-cleanup-and-pr-flow",
  "level": 2
}, {
  "value": "1. Finish the work branch",
  "id": "1-finish-the-work-branch",
  "level": 3
}, {
  "value": "2. Validate before cleanup",
  "id": "2-validate-before-cleanup",
  "level": 3
}, {
  "value": "3. Run one interactive rebase onto current <code>main</code>",
  "id": "3-run-one-interactive-rebase-onto-current-main",
  "level": 3
}, {
  "value": "4. Write the final commit message",
  "id": "4-write-the-final-commit-message",
  "level": 3
}, {
  "value": "5. Push the rewritten branch safely",
  "id": "5-push-the-rewritten-branch-safely",
  "level": 3
}, {
  "value": "6. Open or update the PR from the cleaned branch",
  "id": "6-open-or-update-the-pr-from-the-cleaned-branch",
  "level": 3
}, {
  "value": "7. Merge with a real merge commit",
  "id": "7-merge-with-a-real-merge-commit",
  "level": 3
}, {
  "value": "8. Prune local leftovers",
  "id": "8-prune-local-leftovers",
  "level": 3
}, {
  "value": "Conflict Rule During Rebase",
  "id": "conflict-rule-during-rebase",
  "level": 2
}, {
  "value": "Decision Rule",
  "id": "decision-rule",
  "level": 2
}, {
  "value": "Worked Example",
  "id": "worked-example",
  "level": 2
}];
function _createMdxContent(props) {
  const _components = {
    code: "code",
    h1: "h1",
    h2: "h2",
    h3: "h3",
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
        id: "git-workflow-standards",
        children: "Git Workflow Standards"
      })
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "This page is the source of truth for repo git standards:"
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "branch naming"
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "start-of-day sync"
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "branch cleanup before review"
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "PR creation and merge policy"
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "guarded binary conflict handling"
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "If a workflow rule is mainly about branches, commits, rebases, merges, PRs, or conflict resolution, it belongs here."
    }), "\n", (0,jsx_runtime.jsx)(_components.h2, {
      id: "goals",
      children: "Goals"
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "This repo wants two things at the same time:"
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "one clean review commit per finished piece of work"
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["a real merge edge back into ", (0,jsx_runtime.jsx)(_components.code, {
          children: "main"
        }), " so the git graph stays readable"]
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "The standard workflow is:"
    }), "\n", (0,jsx_runtime.jsxs)(_components.ol, {
      children: ["\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "do normal work on a focused branch"
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["when the work is finished, run one interactive rebase onto current ", (0,jsx_runtime.jsx)(_components.code, {
          children: "main"
        })]
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "squash the branch down to one polished commit during that rebase"
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "open the PR from that cleaned-up branch"
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "merge the PR with a normal merge commit"
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsxs)(_components.p, {
      children: ["Do not use GitHub's ", (0,jsx_runtime.jsx)(_components.code, {
        children: "Squash and merge"
      }), " or ", (0,jsx_runtime.jsx)(_components.code, {
        children: "Rebase and merge"
      }), " options for final integration."]
    }), "\n", (0,jsx_runtime.jsx)(_components.h2, {
      id: "branch-naming",
      children: "Branch Naming"
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["Feature work: ", (0,jsx_runtime.jsx)(_components.code, {
          children: "feat/<scope>"
        })]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["Fix work: ", (0,jsx_runtime.jsx)(_components.code, {
          children: "fix/<scope>"
        })]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["Tooling and structure work: ", (0,jsx_runtime.jsx)(_components.code, {
          children: "chore/<scope>"
        })]
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Examples:"
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsx)(_components.li, {
        children: (0,jsx_runtime.jsx)(_components.code, {
          children: "feat/guest-panic-loop"
        })
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: (0,jsx_runtime.jsx)(_components.code, {
          children: "fix/ghost-possession-reset"
        })
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: (0,jsx_runtime.jsx)(_components.code, {
          children: "chore/docs-docusaurus-bootstrap"
        })
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.h2, {
      id: "start-of-day-sync",
      children: "Start-Of-Day Sync"
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Run these in order:"
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-powershell",
        children: "git pull --ff-only\ngit lfs pull\ngit status --short\n"
      })
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Only start work when the output is clean or intentionally understood."
    }), "\n", (0,jsx_runtime.jsx)(_components.h2, {
      id: "required-git-practices",
      children: "Required Git Practices"
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "Keep branch scope focused."
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "Keep docs updates in the same branch as workflow or policy changes."
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["Use one interactive rebase onto current ", (0,jsx_runtime.jsx)(_components.code, {
          children: "main"
        }), " before opening or finalizing a PR."]
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "Collapse the finished branch to one polished commit during that rebase."
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["Use ", (0,jsx_runtime.jsx)(_components.code, {
          children: "git push --force-with-lease"
        }), " when pushing a rebased branch."]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["Use ", (0,jsx_runtime.jsx)(_components.code, {
          children: "git ours"
        }), ", ", (0,jsx_runtime.jsx)(_components.code, {
          children: "git theirs"
        }), ", and ", (0,jsx_runtime.jsx)(_components.code, {
          children: "git conflicts"
        }), " for guarded binary conflict handling."]
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "Write validation steps clearly in the PR description."
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "Delete stale work branches after merge when they are no longer useful."
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.h2, {
      id: "do-not",
      children: "Do Not"
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "Mix large content migrations with unrelated gameplay work."
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["Commit ", (0,jsx_runtime.jsx)(_components.code, {
          children: "Saved/"
        }), ", ", (0,jsx_runtime.jsx)(_components.code, {
          children: "Intermediate/"
        }), ", ", (0,jsx_runtime.jsx)(_components.code, {
          children: "DerivedDataCache/"
        }), ", or ", (0,jsx_runtime.jsx)(_components.code, {
          children: "Binaries/"
        }), "."]
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "Resolve Unreal binary conflicts by hand-editing files."
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["Use GitHub ", (0,jsx_runtime.jsx)(_components.code, {
          children: "Squash and merge"
        }), " for final integration."]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["Use GitHub ", (0,jsx_runtime.jsx)(_components.code, {
          children: "Rebase and merge"
        }), " for final integration."]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["Force-push rebased work with plain ", (0,jsx_runtime.jsx)(_components.code, {
          children: "--force"
        }), " when ", (0,jsx_runtime.jsx)(_components.code, {
          children: "--force-with-lease"
        }), " is available."]
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.h2, {
      id: "required-branch-cleanup-and-pr-flow",
      children: "Required Branch Cleanup And PR Flow"
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "This is the default repo workflow for finishing a branch."
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Why this is the standard:"
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "the branch stays easy to review"
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: [(0,jsx_runtime.jsx)(_components.code, {
          children: "main"
        }), " still gets a real merge edge"]
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "the final history is clean without relying on GitHub squash merge"
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "the work branch itself becomes the PR branch, so there is no second cleanup branch to maintain"
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.h3, {
      id: "1-finish-the-work-branch",
      children: "1. Finish the work branch"
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Work normally on a focused branch such as:"
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsx)(_components.li, {
        children: (0,jsx_runtime.jsx)(_components.code, {
          children: "feat/<scope>"
        })
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: (0,jsx_runtime.jsx)(_components.code, {
          children: "fix/<scope>"
        })
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: (0,jsx_runtime.jsx)(_components.code, {
          children: "chore/<scope>"
        })
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Example:"
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-powershell",
        children: "git checkout -b fix/ue-tools docs\n"
      })
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "The branch can have as many commits as needed while the work is in progress."
    }), "\n", (0,jsx_runtime.jsx)(_components.h3, {
      id: "2-validate-before-cleanup",
      children: "2. Validate before cleanup"
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Run the checks that match the change before rewriting the branch history."
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Example for docs or tooling work:"
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-powershell",
        children: "pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File Scripts/Tests/Test-DocsTools.ps1\npwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File Scripts/ue-tools.ps1 -RepoRoot . docs check\n"
      })
    }), "\n", (0,jsx_runtime.jsxs)(_components.h3, {
      id: "3-run-one-interactive-rebase-onto-current-main",
      children: ["3. Run one interactive rebase onto current ", (0,jsx_runtime.jsx)(_components.code, {
        children: "main"
      })]
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-powershell",
        children: "git fetch origin\ngit checkout <work-branch>\ngit rebase -i origin/main\n"
      })
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "This does all three cleanup tasks in one operation:"
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["updates the branch against current ", (0,jsx_runtime.jsx)(_components.code, {
          children: "main"
        })]
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "lets you squash the branch to one commit"
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "lets you rewrite the final commit message"
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "In the rebase todo list:"
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["mark the first commit as ", (0,jsx_runtime.jsx)(_components.code, {
          children: "reword"
        })]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["mark every later commit as ", (0,jsx_runtime.jsx)(_components.code, {
          children: "fixup"
        })]
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "This keeps one final commit and folds the rest into it without keeping the intermediate messages."
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "If conflicts happen, resolve them, continue the rebase, and rerun the relevant validation if needed."
    }), "\n", (0,jsx_runtime.jsx)(_components.h3, {
      id: "4-write-the-final-commit-message",
      children: "4. Write the final commit message"
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "When the rebase prompts for the remaining commit message:"
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "first line: short summary"
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "body: key behavior changes, migration notes, and validation when useful"
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "The goal is one polished commit that is ready to live on the branch and in the PR history."
    }), "\n", (0,jsx_runtime.jsx)(_components.h3, {
      id: "5-push-the-rewritten-branch-safely",
      children: "5. Push the rewritten branch safely"
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-powershell",
        children: "git push --force-with-lease\n"
      })
    }), "\n", (0,jsx_runtime.jsxs)(_components.p, {
      children: ["Use ", (0,jsx_runtime.jsx)(_components.code, {
        children: "--force-with-lease"
      }), ", not plain ", (0,jsx_runtime.jsx)(_components.code, {
        children: "--force"
      }), "."]
    }), "\n", (0,jsx_runtime.jsx)(_components.h3, {
      id: "6-open-or-update-the-pr-from-the-cleaned-branch",
      children: "6. Open or update the PR from the cleaned branch"
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-powershell",
        children: "gh pr create --base main --assignee @me\n"
      })
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "If the PR already exists, just push the rebased branch and update the PR description if needed."
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "If you want to script the PR more explicitly:"
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-powershell",
        children: "gh pr create --base main --title \"<title>\" --body-file <path-to-body.md> --assignee @me\n"
      })
    }), "\n", (0,jsx_runtime.jsx)(_components.h3, {
      id: "7-merge-with-a-real-merge-commit",
      children: "7. Merge with a real merge commit"
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Use merge only:"
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-powershell",
        children: "gh pr merge <pr-number> --merge --delete-branch\n"
      })
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "On GitHub.com, choose:"
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsx)(_components.li, {
        children: (0,jsx_runtime.jsx)(_components.code, {
          children: "Create a merge commit"
        })
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Why:"
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: [(0,jsx_runtime.jsx)(_components.code, {
          children: "Squash and merge"
        }), " creates a single-parent commit, so the branch does not visibly merge back into ", (0,jsx_runtime.jsx)(_components.code, {
          children: "main"
        }), " in the graph."]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: [(0,jsx_runtime.jsx)(_components.code, {
          children: "Rebase and merge"
        }), " also removes the merge edge."]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: [(0,jsx_runtime.jsx)(_components.code, {
          children: "Create a merge commit"
        }), " keeps the graph honest while the branch itself has already been cleaned to one commit."]
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.h3, {
      id: "8-prune-local-leftovers",
      children: "8. Prune local leftovers"
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "After the PR is merged:"
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-powershell",
        children: "git checkout main\ngit pull --ff-only\ngit branch -D <work-branch>\ngit fetch --prune\n"
      })
    }), "\n", (0,jsx_runtime.jsx)(_components.h2, {
      id: "conflict-rule-during-rebase",
      children: "Conflict Rule During Rebase"
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "If the branch hits conflicts while rebasing:"
    }), "\n", (0,jsx_runtime.jsxs)(_components.ol, {
      children: ["\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "inspect the conflict state"
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "resolve the intended side"
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "confirm the conflict state again"
      }), "\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "continue the rebase"
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Example:"
    }), "\n", (0,jsx_runtime.jsx)(_components.pre, {
      children: (0,jsx_runtime.jsx)(_components.code, {
        className: "language-powershell",
        children: "git conflicts status\ngit ours \"Content/**/*.uasset\"\ngit theirs \"Content/Maps/**/*.umap\"\ngit conflicts status\ngit rebase --continue\n"
      })
    }), "\n", (0,jsx_runtime.jsx)(_components.h2, {
      id: "decision-rule",
      children: "Decision Rule"
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Use this rule:"
    }), "\n", (0,jsx_runtime.jsxs)(_components.ul, {
      children: ["\n", (0,jsx_runtime.jsx)(_components.li, {
        children: "branch still in progress: commit as needed, do not prematurely rewrite it"
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["branch finished and ready for PR: run one interactive rebase onto ", (0,jsx_runtime.jsx)(_components.code, {
          children: "origin/main"
        }), " and collapse the branch to one commit there"]
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["PR ready to merge: use ", (0,jsx_runtime.jsx)(_components.code, {
          children: "Create a merge commit"
        }), " / ", (0,jsx_runtime.jsx)(_components.code, {
          children: "gh pr merge --merge"
        })]
      }), "\n"]
    }), "\n", (0,jsx_runtime.jsx)(_components.h2, {
      id: "worked-example",
      children: "Worked Example"
    }), "\n", (0,jsx_runtime.jsx)(_components.p, {
      children: "Goal: move Unreal assets under a new content folder and document the policy change."
    }), "\n", (0,jsx_runtime.jsxs)(_components.ol, {
      children: ["\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["Create ", (0,jsx_runtime.jsx)(_components.code, {
          children: "chore/guest-reaction-restructure"
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
        children: "Commit only the moved assets and docs updates while the work is in progress."
      }), "\n", (0,jsx_runtime.jsxs)(_components.li, {
        children: ["When the work is finished, run one interactive rebase onto ", (0,jsx_runtime.jsx)(_components.code, {
          children: "origin/main"
        }), ", squash the branch there, and open the PR from that cleaned branch."]
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